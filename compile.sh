#!/bin/bash

# shellcheck disable=SC2164

BORINGSSL_VERSION="0.20250311.0"
NGINX_VERSION="1.26.3"
FANCYINDEX_VERSION="0.5.2"
DEB_REVISION="6"
ARCHITECTURE="$(dpkg --print-architecture)"

cat << EOF > /etc/apt/sources.list.d/debian.sources
Types: deb
URIs: http://ftp.pl.debian.org/debian
Suites: bookworm bookworm-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: bookworm-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

if [ -n "${APT_PROXY_URL}" ]; then
	echo "Acquire::http { Proxy \"${APT_PROXY_URL}\"; }" > /etc/apt/apt.conf.d/01proxy
fi

apt update
apt upgrade -y
apt install -y --no-install-recommends \
	build-essential \
	ca-certificates \
	curl \
	git \
	cmake \
	ninja-build \
	libunwind-dev \
	libpcre2-dev \
	zlib1g-dev \
	libxslt1-dev \
	libgd-dev \
	libgeoip-dev \
	libperl-dev \
	libbrotli-dev \
	zstd \
	tree

mkdir -p /build
mkdir -p destdir

cd /build
git clone -b "${BORINGSSL_VERSION}" --single-branch https://github.com/google/boringssl
cd boringssl
patch -Np1 -i /patches/fix-boringssl-release-build.patch
cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=1 -DCMAKE_INSTALL_PREFIX=/opt/boringssl
ninja -C build
DESTDIR=/build/destdir ninja -C build install
mv /build/destdir/opt/boringssl/bin/bssl /build/destdir/opt/boringssl/bin/bssl-bin
cp /distrib/bssl /build/destdir/opt/boringssl/bin/bssl
ln -s /build/destdir/opt/boringssl /opt/boringssl

cd /build
git clone -b master --single-branch https://github.com/google/ngx_brotli
cd ngx_brotli
git submodule update --init
patch -Np1 -i /patches/0001-Fix-Vary-header.patch

cd /build
curl -LO https://github.com/aperezdc/ngx-fancyindex/releases/download/v"${FANCYINDEX_VERSION}"/ngx-fancyindex-"${FANCYINDEX_VERSION}".tar.xz
tar xvf ngx-fancyindex-"${FANCYINDEX_VERSION}".tar.xz
cd ngx-fancyindex-"${FANCYINDEX_VERSION}"
patch -Np1 -i /patches/0001-Fix-404-not-found-when-indexing-filesystem-root.patch

cd /build
curl -LO https://nginx.org/download/nginx-"${NGINX_VERSION}".tar.gz
tar xvf nginx-"${NGINX_VERSION}".tar.gz
cd nginx-"${NGINX_VERSION}"
./configure --with-cc=c++ --with-cc-opt="-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC -Wdate-time -D_FORTIFY_SOURCE=2 -I/opt/boringssl/include -x c" --with-ld-opt="-Wl,-z,relro -Wl,-z,now -fPIC -L/opt/boringssl/lib" --prefix=/usr/share/nginx --conf-path=/etc/nginx/nginx.conf --http-log-path=/var/log/nginx/access.log --error-log-path=stderr --lock-path=/var/lock/nginx.lock --pid-path=/run/nginx.pid --modules-path=/usr/lib/nginx/modules --http-client-body-temp-path=/var/lib/nginx/body --http-fastcgi-temp-path=/var/lib/nginx/fastcgi --http-proxy-temp-path=/var/lib/nginx/proxy --http-scgi-temp-path=/var/lib/nginx/scgi --http-uwsgi-temp-path=/var/lib/nginx/uwsgi --with-compat --with-debug --with-pcre-jit --with-http_ssl_module --with-http_stub_status_module --with-http_realip_module --with-http_auth_request_module --with-http_v2_module --with-http_v3_module --with-http_dav_module --with-http_slice_module --with-threads --with-http_addition_module --with-http_flv_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_mp4_module --with-http_random_index_module --with-http_secure_link_module --with-http_sub_module --with-mail_ssl_module --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module --with-http_geoip_module=dynamic --with-http_image_filter_module=dynamic --with-http_perl_module=dynamic --with-http_xslt_module=dynamic --with-mail=dynamic --with-stream=dynamic --with-stream_geoip_module=dynamic --add-dynamic-module=../ngx_brotli --add-dynamic-module=../ngx-fancyindex-"${FANCYINDEX_VERSION}"
make -j"$(nproc)"
DESTDIR=/build/destdir make install
rm -r /build/destdir/etc/nginx
cp -r /distrib/conf /build/destdir/etc/nginx
mkdir -p /build/destdir/usr/sbin
mv /build/destdir/usr/share/nginx/sbin/nginx /build/destdir/usr/sbin/nginx
rm -r /build/destdir/usr/share/nginx/sbin
chown -R root:adm /build/destdir/var/log/nginx
chmod 750 /build/destdir/var/log/nginx
mkdir -p /build/destdir/usr/share/man/man8
cp man/nginx.8 /build/destdir/usr/share/man/man8
gzip /build/destdir/usr/share/man/man8/nginx.8
mkdir -p /build/destdir/etc/nginx/conf.d \
	/build/destdir/etc/nginx/modules-enabled \
	/build/destdir/etc/nginx/sites-enabled \
	/build/destdir/etc/logrotate.d \
	/build/destdir/etc/ufw/applications.d \
	/build/destdir/usr/share/apport/package-hooks \
	/build/destdir/usr/share/nginx/modules-available \
	/build/destdir/usr/share/vim/addons \
	/build/destdir/usr/share/vim/registry \
	/build/destdir/var/lib/nginx \
	/build/destdir/var/www/html
cp -r /distrib/logrotate.d/nginx /build/destdir/etc/logrotate.d/nginx
cp -r /distrib/ufw/nginx /build/destdir/etc/ufw/applications.d/nginx
cp -r /distrib/apport/source_nginx.py /build/destdir/usr/share/apport/package-hooks/source_nginx.py
cp -r /distrib/vim/nginx.yaml /build/destdir/usr/share/vim/registry/nginx.yaml
cp -r contrib/vim/* /build/destdir/usr/share/vim/addons/
cp -r /distrib/mod.conf.d/* /build/destdir/usr/share/nginx/modules-available/
cd /build/destdir/etc/nginx
ln -s ../../usr/share/nginx/modules-available .
cd /build/destdir/usr/share/nginx
ln -s ../../lib/nginx/modules .
cp -r /build/destdir/usr/share/nginx/html/index.html /build/destdir/var/www/html/index.nginx-debian.html
mv /build/destdir/usr/sbin/nginx /build/destdir/usr/sbin/nginx-bin
cp /distrib/nginx /build/destdir/usr/sbin/nginx

tree /build/destdir

cd /build
apt install -y --no-install-recommends \
	ruby-rubygems
gem install fpm
cd destdir
fpm -a native -s dir -t deb -p ../nginx_"${NGINX_VERSION}"-"${DEB_REVISION}"_"${ARCHITECTURE}".deb --name nginx --version "${NGINX_VERSION}" --iteration "${DEB_REVISION}" --deb-build-depends cmake --deb-build-depends ninja-build --deb-build-depends libunwind-dev --deb-build-depends libpcre2-dev --deb-build-depends zlib1g-dev --deb-build-depends libxslt1-dev --deb-build-depends libgd-dev --deb-build-depends libgeoip-dev --deb-build-depends libperl-dev --depends libc6 --depends libgcc-s1 --depends libstdc++6 --depends libcrypt1 --depends libpcre2-8-0 --depends zlib1g --depends libgeoip1 --depends libgd3 --depends libperl5.36 --depends perl --depends libxml2 --depends libxslt1.1 --depends libbrotli1 --conflicts nginx-common --provides nginx-common --conflicts libnginx-mod-http-brotli-filter --provides libnginx-mod-http-brotli-filter --conflicts libnginx-mod-http-brotli-static --provides libnginx-mod-http-brotli-static --conflicts libnginx-mod-http-fancyindex --provides libnginx-mod-http-fancyindex --conflicts libnginx-mod-http-geoip --provides libnginx-mod-http-geoip --conflicts libnginx-mod-http-image-filter --provides libnginx-mod-http-image-filter --conflicts libnginx-mod-http-perl --provides libnginx-mod-http-perl --conflicts libnginx-mod-http-xslt-filter --provides libnginx-mod-http-xslt-filter --conflicts libnginx-mod-mail --provides libnginx-mod-mail --conflicts libnginx-mod-stream --provides libnginx-mod-stream --conflicts libnginx-mod-stream-geoip --provides libnginx-mod-stream-geoip --conflicts nginx-core --provides nginx-core --deb-compression zst --deb-default /distrib/default/nginx --deb-init /distrib/init.d/nginx --deb-systemd /distrib/systemd/nginx.service --deb-systemd-auto-start --deb-systemd-enable --description "small, powerful, scalable web/proxy server" --url "http://nginx.org" --maintainer "Damian Duży <dame@zakonfeniksa.org>" .
