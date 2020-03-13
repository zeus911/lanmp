#!/usr/bin/env bash

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cur_dir=$(pwd)

include(){
    local include=${1}
    if [[ -s ${cur_dir}/include/${include}.sh ]];then
        . ${cur_dir}/include/${include}.sh
    else
        wget -P include https://d.hws.com/free/hwslinuxmaster/script/include/${include}.sh >/dev/null 2>&1
        if [ "$?" -ne 0 ]; then
            echo "Error: ${cur_dir}/include/${include}.sh not found, shell can not be executed."
            exit 1
        fi
        . ${cur_dir}/include/${include}.sh
    fi
}

main(){
    case "$1" in
        -h|--help)
            printf "Usage: $0 [Options] [php-config path] [phpize path]
Options:
-h, --help                      Print this help text and exit
--install-php-redis             Install php-redis extension
"
            ;;
        --install-php-redis)
            include php-redis
            install_php_redis ${2} ${3}
            ;;
        *)
            echo "Please Usage: $0 -h, Show Help"
            ;;
    esac
}

include config
include public
load_config
IsRoot
main "$@" 2>&1 | tee /tmp/install.log