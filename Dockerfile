FROM ubuntu:14.04
MAINTAINER Jason Wilder jwilder@litl.com

# Install Nginx.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get install nano git build-essential cmake zlib1g-dev libpcre3 libpcre3-dev unzip wget -y && apt-get clean

ENV NGINX_VERSION 1.7.8
ENV LIBRESSL_VERSION libressl-2.1.1
ENV MODULESDIR /usr/src/nginx-modules
ENV NPS_VERSION 1.9.32.2

RUN mkdir -p ${MODULESDIR}

RUN cd /usr/src/ && wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && tar xf nginx-${NGINX_VERSION}.tar.gz && rm -f nginx-${NGINX_VERSION}.tar.gz
RUN cd /usr/src/ && wget http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${LIBRESSL_VERSION}.tar.gz && tar xvzf ${LIBRESSL_VERSION}.tar.gz
RUN cd ${MODULESDIR} && git clone git://github.com/bpaquet/ngx_http_enhanced_memcached_module.git
RUN cd ${MODULESDIR} && git clone https://github.com/openresty/headers-more-nginx-module.git

RUN apt-get update && apt-get install -y build-essential zlib1g-dev libpcre3 libpcre3-dev unzip
RUN cd ${MODULESDIR} && \
    wget --no-check-certificate https://github.com/pagespeed/ngx_pagespeed/archive/release-${NPS_VERSION}-beta.zip && \
    unzip release-${NPS_VERSION}-beta.zip && \
    cd ngx_pagespeed-release-${NPS_VERSION}-beta/ && \
    wget --no-check-certificate https://dl.google.com/dl/page-speed/psol/${NPS_VERSION}.tar.gz && \
    tar -xzvf ${NPS_VERSION}.tar.gz

ADD libressl-config /usr/src/${LIBRESSL_VERSION}/config
ADD after.sh /usr/src/${LIBRESSL_VERSION}/after.sh
RUN chmod +x /usr/src/${LIBRESSL_VERSION}/config /usr/src/${LIBRESSL_VERSION}/after.sh


# Compile nginx
RUN cd /usr/src/nginx-${NGINX_VERSION} && ./configure \
	--prefix=/etc/nginx \
	--sbin-path=/usr/sbin/nginx \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
	--pid-path=/var/run/nginx.pid \
	--lock-path=/var/run/nginx.lock \
	--with-http_ssl_module \
	--with-http_realip_module \
	--with-http_addition_module \
	--with-http_sub_module \
	--with-http_dav_module \
	--with-http_flv_module \
	--with-http_mp4_module \
	--with-http_gunzip_module \
	--with-http_gzip_static_module \
	--with-http_random_index_module \
	--with-http_secure_link_module \
	--with-http_stub_status_module \
	--with-mail \
	--with-mail_ssl_module \
	--with-file-aio \
	--with-http_spdy_module \
	--with-cc-opt='-g -O2 -fstack-protector --param=ssp-buffer-size=4 -Wformat -Wformat-security -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2' \
	--with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,--as-needed' \
	--with-ipv6 \
	--with-sha1='../${LIBRESSL_VERSION}' \
 	--with-md5='../${LIBRESSL_VERSION}' \
	--with-openssl='../${LIBRESSL_VERSION}' \
	--add-module=${MODULESDIR}/ngx_pagespeed-release-${NPS_VERSION}-beta \
    	--add-module=${MODULESDIR}/ngx_http_enhanced_memcached_module \
    	--add-module=${MODULESDIR}/headers-more-nginx-module

RUN cd /usr/src/${LIBRESSL_VERSION}/ && ./config && make && make install && ./after.sh && cd /usr/src/nginx-${NGINX_VERSION} && make && make install

# add forego
RUN wget -P /usr/local/bin https://godist.herokuapp.com/projects/ddollar/forego/releases/current/linux-amd64/forego
RUN chmod u+x /usr/local/bin/forego

# add default ssl cert
RUN mkdir -p /etc/nginx/ssl
WORKDIR /etc/nginx/ssl
# The cert and its key are published with the docker image,
# so it is insecure anyway and can be of short length (faster build time).
# Use your own cert (4096 bit) for production.
RUN openssl genrsa  -out server.key 512
RUN openssl req -new -batch -key server.key -out server.csr
RUN openssl x509 -req -days 10000 -in server.csr -signkey server.key -out server.crt
RUN openssl dhparam -out dhparam.pem 512

# add nginx confif
RUN mkdir -p /etc/nginx/sites-enabled
ADD default.conf /etc/nginx/sites-enabled/default.conf
ADD nginx.conf /etc/nginx/nginx.conf
ADD pagespeed.conf /etc/nginx/pagespeed.conf
ADD pagespeed-extra.conf /etc/nginx/pagespeed-extra.conf
ADD proxy_params /etc/nginx/proxy_params

# add dynamic rewrite
RUN mkdir /app
WORKDIR /app
ADD ./app /app
RUN chmod u+x /app/init.sh

EXPOSE 80 443
VOLUME /app /etc/nginx /var/log/nginx
ENV DOCKER_HOST unix:///tmp/docker.sock

CMD ["/app/init.sh"]
