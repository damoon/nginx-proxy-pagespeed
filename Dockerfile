FROM ubuntu:14.04
MAINTAINER David Sauer davedamoon@gmail.com

# Install Nginx.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get install build-essential cmake zlib1g-dev libpcre3 libpcre3-dev unzip curl -y && apt-get clean

ENV NGINX_VERSION 1.7.8
ENV LIBRESSL_VERSION libressl-2.1.1
ENV MODULESDIR /usr/src/nginx-modules
ENV NPS_VERSION 1.9.32.2

RUN mkdir -p ${MODULESDIR}

RUN cd /usr/src/ && curl -O http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && tar xf nginx-${NGINX_VERSION}.tar.gz && unlink nginx-${NGINX_VERSION}.tar.gz
RUN cd /usr/src/ && curl -O http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${LIBRESSL_VERSION}.tar.gz && tar xf ${LIBRESSL_VERSION}.tar.gz && unlink ${LIBRESSL_VERSION}.tar.gz
RUN cd ${MODULESDIR} && curl -L -O https://github.com/openresty/headers-more-nginx-module/archive/v0.25.tar.gz && tar xf v0.25.tar.gz && unlink v0.25.tar.gz && mv headers-mo* headers-more-nginx-module

RUN cd ${MODULESDIR} && \
    curl -L -O https://github.com/pagespeed/ngx_pagespeed/archive/release-${NPS_VERSION}-beta.zip && \
    unzip release-${NPS_VERSION}-beta.zip && \
    unlink release-${NPS_VERSION}-beta.zip && \
    cd ngx_pagespeed-release-${NPS_VERSION}-beta/ && \
    curl -O https://dl.google.com/dl/page-speed/psol/${NPS_VERSION}.tar.gz && \
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
    	--add-module=${MODULESDIR}/headers-more-nginx-module

RUN cd /usr/src/${LIBRESSL_VERSION}/ && ./config && make && make install && ./after.sh && cd /usr/src/nginx-${NGINX_VERSION} && make && make install

# add forego
RUN cd /usr/local/bin && curl -O https://godist.herokuapp.com/projects/ddollar/forego/releases/current/linux-amd64/forego
RUN chmod u+x /usr/local/bin/forego

# add default ssl cert
RUN mkdir -p /etc/nginx/ssl
COPY ssl/* /etc/nginx/ssl

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
