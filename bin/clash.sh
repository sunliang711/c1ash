#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
this="$(cd $(dirname $rpath) && pwd)"
cd "$this"

user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 5)
        bold=$(tput bold)
reset=$(tput sgr0)
function _runAsRoot(){
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
# function is hidden when begin with '_'
###############################################################################
# TODO
case $(uname) in
    Linux)
        binName=clash-linux
        binName=clashp
        cmdStat=stat
        ;;
    Darwin)
        binName=clash-darwin
        cmdStat='stat -x'
        ;;
esac
editor=vi
if command -v vim >/dev/null 2>&1;then
    editor=vim
fi
if command -v nvim >/dev/null 2>&1;then
    editor=nvim
fi
logfile=/tmp/clash.log
configFile=../config.yaml
configExampleFile=../config-example.yaml

start(){
    if status >/dev/null;then
        echo "clash is ${bold}already${reset} running,do nothing."
        exit 1
    fi
    echo "start clash..."
    case $(uname) in
        Linux)
            _runAsRoot systemctl start clash.service
            ;;
        Darwin)
            launchctl load -w $home/Library/LaunchAgents/clash.plist 2>/dev/null
            ;;
    esac

    if status >/dev/null;then
        if [ $(uname) = "Darwin" ];then
            port=$(grep '^port:' $configFile | awk '{print $2}')
            if [ -n $port ];then
                echo "Set system http proxy: localhost:$port"
                echo "Set system https proxy: localhost:$port"
                bash ../setMacProxy.sh http $port >/dev/null
                bash ../setMacProxy.sh https $port >/dev/null
            else
                echo "${red}Error${reset}: get http port error."
            fi
        fi
        echo "OK: clash is running now."
    else
        echo "Error: clash is not running."
    fi
}

stop(){
    echo "stop clash..."
    case $(uname) in
        Linux)
            _runAsRoot systemctl stop clash.service
            ;;
        Darwin)
            launchctl unload -w $home/Library/LaunchAgents/clash.plist 2>/dev/null
            bash ../setMacProxy.sh unset
            ;;
    esac
}

set(){
    cmd="$(cat<<EOF
    iptables -t nat -N clash || { return 0; }
    iptables -t nat -A clash -d 10.1.1.1/16 -j RETURN
    iptables -t nat -A clash -p tcp -j REDIRECT --to-ports 7892
    iptables -t nat -A PREROUTING -p tcp -j clash
EOF
)"
    _runAsRoot "${cmd}"
}

    # iptables -t nat -A PREROUTING -p tcp -j REDIRECT --to-ports 7892
    # iptables -t nat -D PREROUTING -p tcp -j REDIRECT --to-ports 7892
clear(){
    cmd="$(cat<<EOF
    iptables -t nat -F clash
    iptables -t nat -D PREROUTING -p tcp -j clash
EOF
)"
}

config(){
    if [ ! -e $configFile ];then
        cp $configExampleFile $configFile
    fi
    mtime0="$(${cmdStat} $configFile | grep Modify)"
    $editor $configFile
    mtime1="$(${cmdStat} $configFile | grep Modify)"
    #配置文件被修改
    if [ "$mtime0" != "$mtime1" ];then
        #并且当前是运行状态，则重启服务
        if status >/dev/null;then
            echo "Config file changed,restart server"
            restart
        fi
    fi
}

restart(){
    stop
    start
}

status(){
    pid=$(ps aux | grep "$binName -d ." | grep -v grep | awk '{print $2}')
    if [ -n "$pid" ];then
        port=$(grep '^port:' ${this}/../config.yaml 2>/dev/null | awk '{print $2}')
        echo "clash is running on port: ${bold}$port${reset} with pid: $pid"
        return 0
    else
        echo "clash is ${bold}not${reset} running"
        return 1
    fi
}

log(){
    case $(uname) in
        Linux)
            sudo journalctl -u clash -f
            ;;
        Darwin)
            echo "Watching $logfile..."
            tail -f $logfile
            ;;
    esac
}

doctor(){
    if status >/dev/null;then
        port=$(grep '^port:' $configFile | awk '{print $2}')
        if curl -m 5 -x http://localhost:$port -s ifconfig.me >/dev/null;then
            echo "Proxy is ${green}${bold}healthy${reset}"
        else
            echo "Proxy ${red}not work${reset}"
        fi

    fi
}

em(){
    $editor $0
}

pac(){
    pacfile=${this}/../RuleSet/Pac.yaml
    local mtime0="$(${cmdStat} $pacfile | grep Modify)"
    $editor $pacfile
    local mtime1="$(${cmdStat} $pacfile | grep Modify)"
    #配置文件被修改
    if [ "$mtime0" != "$mtime1" ];then
        #并且当前是运行状态，则重启服务
        if status >/dev/null;then
            echo "Pac file changed,restart server"
            restart
        fi
    fi

}


###############################################################################
# write your code above
###############################################################################
function _help(){
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    # perl -lne 'print "\t$1" if /^\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE})
    # perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | grep -v '^\t_'
    perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | perl -lne "print if /^\t[^_]/"
}

function _loadENV(){
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

function _unloadENV(){
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
        _help
        ;;
    *)
        "$@"
esac
