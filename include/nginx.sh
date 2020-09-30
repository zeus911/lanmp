_install_nginx_depend(){
    _info "Starting to install dependencies packages for Nginx..."
    if [ "${PM}" = "yum" ];then
        local yum_depends=(zlib-devel)
        for depend in ${yum_depends[@]}
        do
            InstallPack "yum -y install ${depend}"
        done
    elif [ "${PM}" = "apt-get" ];then
        local apt_depends=(zlib1g-dev)
        for depend in ${apt_depends[@]}
        do
            InstallPack "apt-get -y install ${depend}"
        done
    fi
    id -u www >/dev/null 2>&1
    [ $? -ne 0 ] && useradd -M -U www -r -d /dev/null -s /sbin/nologin
    _success "Install dependencies packages for Nginx completed..."
}

_start_nginx() {
    DownloadUrl "/etc/init.d/nginx" "${download_sysv_url}/nginx"
    sed -i "s|^prefix={nginx_location}$|prefix=${nginx_location}|i" /etc/init.d/nginx
    CheckError "chmod +x /etc/init.d/nginx"
    chkconfig --add nginx > /dev/null 2>&1
    update-rc.d -f nginx defaults > /dev/null 2>&1
    CheckError "service nginx start"
}

install_nginx(){
    if [ $# -lt 1 ]; then
        echo "[Parameter Error]: nginx_location [default_port]"
        exit 1
    fi
    nginx_location=${1}

    # 如果存在第二个参数
    if [ $# -ge 2 ]; then
        nginx_port=${2}
    fi

    _install_nginx_depend
    cd /tmp
    _info "Downloading and Extracting ${pcre_filename} files..."
    DownloadFile "${pcre_filename}.tar.gz" ${pcre_download_url}
    rm -fr ${pcre_filename}
    tar zxf ${pcre_filename}.tar.gz
    _info "Downloading and Extracting ${openssl_filename} files..."
    DownloadFile "${openssl_filename}.tar.gz" ${openssl_download_url}
    rm -fr ${openssl_filename}
    tar zxf ${openssl_filename}.tar.gz
    _info "Downloading and Extracting ${nginx_filename} files..."
    DownloadFile "${nginx_filename}.tar.gz" ${nginx_download_url}
    rm -fr ${nginx_filename}
    tar zxf ${nginx_filename}.tar.gz
    cd ${nginx_filename}
    nginx_configure_args="--prefix=${nginx_location} \
    --conf-path=${nginx_location}/etc/nginx.conf \
    --error-log-path=${nginx_location}/var/log/error.log \
    --pid-path=${nginx_location}/var/run/nginx.pid \
    --lock-path=${nginx_location}/var/lock/nginx.lock \
    --http-log-path=${nginx_location}/var/log/access.log \
    --http-client-body-temp-path=${nginx_location}/var/tmp/client \
    --http-proxy-temp-path=${nginx_location}/var/tmp/proxy \
    --http-fastcgi-temp-path=${nginx_location}/var/tmp/fastcgi \
    --http-uwsgi-temp-path=${nginx_location}/var/tmp/uwsgi \
    --http-scgi-temp-path=${nginx_location}/var/tmp/scgi \
    --with-pcre=/tmp/${pcre_filename} \
    --with-openssl=/tmp/${openssl_filename} \
    --user=www \
    --group=www \
    --with-threads \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gzip_static_module \
    --with-http_realip_module \
    --with-http_stub_status_module"
    _info "Make Install ${nginx_filename}..."
    CheckError "./configure ${nginx_configure_args}"
    CheckError "parallel_make"
    CheckError "make install"
    mkdir -p ${nginx_location}/var/{log,run,lock,tmp}
    mkdir -p ${nginx_location}/var/tmp/{client,proxy,fastcgi,uwsgi}
    mkdir -p ${nginx_location}/etc/vhost
    _info "Config ${nginx_filename}"
    _config_nginx
    _start_nginx
    _success "${nginx_filename} install completed..."
    rm -fr /tmp/${pcre_filename}
    rm -fr /tmp/${openssl_filename}
    rm -fr /tmp/${nginx_filename}
}

_config_nginx(){
    # 备份原配置文件
    [ -f "${nginx_location}/etc/nginx.conf" ] && \
        mv ${nginx_location}/etc/nginx.conf ${nginx_location}/etc/nginx.conf-$(date +%Y-%m-%d_%H:%M:%S).bak

    # 写入默认配置文件
    cat > ${nginx_location}/etc/nginx.conf <<EOF
worker_processes auto;
worker_rlimit_nofile 51200;

events {
    use epoll;
    worker_connections 51200;
    multi_accept on;
}

http {
    include mime.types;
    default_type application/octet-stream;
    server_names_hash_bucket_size 512;
    client_max_body_size 50m;
    client_header_buffer_size 32k;
    client_body_buffer_size 128k;
    large_client_header_buffers 4 32k;

    sendfile   on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 60;

    # fastcgi
    fastcgi_connect_timeout 300;
    fastcgi_send_timeout 300;
    fastcgi_read_timeout 300;
    fastcgi_buffer_size 64k;
    fastcgi_buffers 4 64k;
    fastcgi_busy_buffers_size 128k;
    fastcgi_temp_file_write_size 256k;
    fastcgi_intercept_errors on;

    # gzip
    gzip on;
    gzip_min_length 1k;
    gzip_buffers 4 16k;
    gzip_http_version 1.0;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/javascript application/json application/javascript application/x-javascript application/xml;
    gzip_vary on;

    # http_proxy
    proxy_connect_timeout 75;
    proxy_send_timeout 75;
    proxy_read_timeout 75;
    proxy_buffer_size 4k;
    proxy_buffers 4 32k;
    proxy_busy_buffers_size 64k;
    proxy_temp_file_write_size 64k;

    server_tokens off;
    limit_conn_zone \$binary_remote_addr zone=perip:10m;
    limit_conn_zone \$server_name zone=perserver:10m;

    # include virtual host config
    include vhost/*.conf;

    server {
       listen 998;
       server_name localhost;
       root ${var}/pma;
       index index.php default.php index.html index.htm default.html default.htm;
       error_log "${var}/pma/pma-error.log";
       access_log "${var}/pma/pma-access.log";

       #DENY FILES
       location ~ ^/(\.user.ini|\.sql|\.zip|\.gz|\.htaccess|\.git|\.svn|\.project|LICENSE|README.md)
       {
           return 404;
       }

       #PHP
       location ~ \.php\$ {
           fastcgi_pass unix:/tmp/php-5.6.40-default.sock;
           fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
           include fastcgi_params;
       }
    }

    server {
       listen ${nginx_port} default;
       return 403;
    }
}
EOF

    # 定期清理日志
    cat > /etc/logrotate.d/hws_nginx_log <<EOF
${nginx_location}/logs/*log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    sharedscripts
    postrotate
        [ ! -f ${nginx_location}/var/run/nginx.pid ] || kill -USR1 \`cat ${nginx_location}/var/run/nginx.pid\`
    endscript
}
EOF

    # 授权
    chown -R www:www ${nginx_location}
}
