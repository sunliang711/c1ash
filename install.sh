#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
thisDir="$(cd $(dirname $rpath) && pwd)"
cd "$thisDir"

user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 5)
        bold=$(tput bold)
reset=$(tput sgr0)
function runAsRoot(){
    verbose=0
    while getopts ":v" opt;do
        case "$opt" in
            v)
                verbose=1
                ;;
            \?)
                echo "Unknown option: \"$OPTARG\""
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))
    cmd="$@"
    if [ -z "$cmd" ];then
        echo "${red}Need cmd${reset}"
        exit 1
    fi

    if [ "$verbose" -eq 1 ];then
        echo "run cmd:\"${red}$cmd${reset}\" as root."
    fi

    if (($EUID==0));then
        sh -c "$cmd"
    else
        if ! command -v sudo >/dev/null 2>&1;then
            echo "Need sudo cmd"
            exit 1
        fi
        sudo sh -c "$cmd"
    fi
}
###############################################################################
# write your code below (just define function[s])
# function with 'function' is hidden when run help, without 'function' is show
###############################################################################
# TODO
function need(){
    if ! command -v $1 >/dev/null 2>&1;then
        echo "Need cmd: $1"
        exit 1
    fi
}

install(){
    cd ${thisDir}
    need curl
    need unzip
    case $(uname) in
        Linux)
            clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/clash-linux.tar.bzip
            name=clash-linux
            ;;
        Darwin)
            clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/clash-darwin.tar.bzip
            name=clash-darwin
            ;;
    esac

    #download
    cd /tmp
    if [ ! -e $name.tar.bzip ];then
        curl -LO $clashURL || { echo "download $name failed!"; exit 1; }
    fi

    #unzip
    tar xvf $name.tar.bzip
    chmod +x $name
    mv $name ${thisDir}
    cd ${thisDir}

    if [ ! -e Country.mmdb ];then
        curl -LO https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/Country.mmdb
    fi


    case $(uname) in
        Linux)
            sudo sed -e "s|CWD|${thisDir}|g" \
                     -e "s|USER|$user|g" \
                     -e "s|NAME|$name|g" clash.service >/etc/systemd/system/clash.service
            sudo systemctl enable clash.service
            ;;
        Darwin)
            sed -e "s|CWD|${thisDir}|g" \
                -e "s|NAME|$name|g" clash.plist >$home/Library/LaunchAgents/clash.plist
            ;;
    esac
    echo "Add ${thisDir}/clash.sh to PATH manually."
}



###############################################################################
# write your code above
###############################################################################
function help(){
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    perl -lne 'print "\t$1" if /^\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | grep -v runAsRoot
}
function loadENV(){
    if [ -z "$INIT_HTTP_PROXY" ];then
        echo "INIT_HTTP_PROXY is empty"
        echo -n "Enter http proxy: (if you need) "
        read INIT_HTTP_PROXY
    fi
    if [ -n "$INIT_HTTP_PROXY" ];then
        echo "set http proxy to $INIT_HTTP_PROXY"
        export http_proxy=$INIT_HTTP_PROXY
        export https_proxy=$INIT_HTTP_PROXY
        export HTTP_PROXY=$INIT_HTTP_PROXY
        export HTTPS_PROXY=$INIT_HTTP_PROXY
        git config --global http.proxy $INIT_HTTP_PROXY
        git config --global https.proxy $INIT_HTTP_PROXY
    else
        echo "No use http proxy"
    fi
}

function unloadENV(){
    if [ -n "$https_proxy" ];then
        unset http_proxy
        unset https_proxy
        unset HTTP_PROXY
        unset HTTPS_PROXY
        git config --global --unset-all http.proxy
        git config --global --unset-all https.proxy
    fi
}


case "$1" in
     ""|-h|--help|help)
        help
        ;;
    *)
        "$@"
esac
