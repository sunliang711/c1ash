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
start(){
    case $(uname) in
        Linux)
            runAsRoot systemctl start clash.service
            ;;
        Darwin)
            launchctl load -w $home/Library/LaunchAgents/clash.plist
            port=$(grep '^port:' config.yaml | awk '{print $2}')
            if [ -n $port ];then
                bash ./setMacProxy.sh http $port
                bash ./setMacProxy.sh https $port
            else
                echo "get http port error."
            fi
            ;;
    esac
}

stop(){
    case $(uname) in
        Linux)
            runAsRoot systemctl stop clash.service
            ;;
        Darwin)
            launchctl unload -w $home/Library/LaunchAgents/clash.plist
            bash ./setMacProxy.sh unset
            ;;
    esac
}

config(){
    editor=vi
    if command -v vim >/dev/null 2>&1;then
        editor=vim
    fi
    if command -v nvim >/dev/null 2>&1;then
        editor=nvim
    fi
    if [ ! -e config.yaml ];then
        cp config-example.yaml config.yaml
    fi
    $editor config.yaml
    #TODO
    #restart after config.yaml changed
}

restart(){
    stop
    start
}

status(){
    case $(uname) in
        Linux)
            name=clash-linux
        ;;
        Darwin)
            name=clash-darwin
        ;;
    esac
    port=$(grep '^port:' config.yaml 2>/dev/null | awk '{print $2}')
    pid=$(ps aux | grep "$name -d ." | grep -v grep | awk '{print $2}')
    if [ -n $pid ] && [ -n $port ];then
        echo "clash is running on port: $port with pid: $pid"
    else
        echo "clash is not running"
    fi
}

log(){
    tail -f /tmp/clash.log
}

em(){
    editor=vi
    if command -v vim >/dev/null 2>&1;then
        editor=vim
    fi
    if command -v nvim >/dev/null 2>&1;then
        editor=nvim
    fi
    $editor $0
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
