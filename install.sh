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
            # clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/clash-linux.tar.bzip
            clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/20201227/clash-linux-amd64-2020.12.27.gz
            ;;
        Darwin)
            # clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/clash-darwin.tar.bzip
            clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/20201227/clash-darwin-amd64-2020.12.27.gz
            ;;
    esac

    case $(uname -m) in
        aarch64)
            # 树莓派
            clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/20201227/clash-linux-armv8-2020.12.27.gz
            ;;
    esac

    tarFile=${clashURL##*/}
    name=${tarFile%.gz}

    #download
    cd /tmp
    if [ ! -e $tarFile ];then
        curl -LO $clashURL || { echo "download $tarFile failed!"; exit 1; }
    fi

    #unzip
    gunzip $tarFile
    chmod +x $name
    mv $name ${thisDir}/clash
    cd ${thisDir}

    if [ ! -e Country.mmdb ];then
        curl -LO https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/Country.mmdb
    fi

    local start="${thisDir}/clash -d ."

    case $(uname) in
        Linux)
            sed -e "s|CWD|${thisDir}|g" \
                     -e "s|USER|root|g" \
                     -e "s|<START>|$start|g" clash.service > /tmp/clash.service 
            sudo mv /tmp/clash.service /etc/systemd/system/clash.service
            sudo systemctl enable clash.service
            ;;
        Darwin)
            sed -e "s|CWD|${thisDir}|g" \
                -e "s|NAME|clash|g" clash.plist >$home/Library/LaunchAgents/clash.plist
            ;;
    esac
    export PATH="${thisDir}/bin:${PATH}"
    echo "Add ${thisDir}/bin to PATH manually."
}

install-trans(){
    install

    local start="${thisDir}/clash -d ."
    local start_post="${thisDir}/bin/clash.sh set"
    local stop_post="${thisDir}/bin/clash.sh clear"
    case $(uname) in
        Linux)
            sed -e "s|CWD|${thisDir}|g" \
                     -e "s|USER|root|g" \
                     -e "s|<START_POST>|${start_post}|g" \
                     -e "s|<STOP_POST>|${stop_post}|g" \
                     -e "s|<START>|$start|g" clash.service > /tmp/clash.service
            sudo mv /tmp/clash.service /etc/systemd/system/clash.service
            sudo systemctl daemon-reload
            sudo systemctl enable --now clash.service
            ;;
        Darwin)
            echo "Not support MacOS"
            exit 1
            ;;
    esac
}


###############################################################################
# write your code above
###############################################################################
function help(){
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    perl -lne 'print "\t$1" if /^\s*(\S+)\s*\(\)\s*\{$/' $(basename ${BASH_SOURCE}) | grep -v runAsRoot
}

case "$1" in
     ""|-h|--help|help)
        help
        ;;
    *)
        "$@"
esac
