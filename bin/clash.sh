#!/bin/bash
if [ -z "${BASH_SOURCE}" ]; then
    this=${PWD}
    logfile="/tmp/$(%FT%T).log"
else
    rpath="$(readlink ${BASH_SOURCE})"
    if [ -z "$rpath" ]; then
        rpath=${BASH_SOURCE}
    fi
    this="$(cd $(dirname $rpath) && pwd)"
    logfile="/tmp/$(basename ${BASH_SOURCE}).log"
fi

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

# export TERM=xterm-256color

# Use colors, but only if connected to a terminal, and that terminal
# supports them.
if which tput >/dev/null 2>&1; then
  ncolors=$(tput colors 2>/dev/null)
fi
if [ -t 1 ] && [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    CYAN="$(tput setaf 5)"
    BOLD="$(tput bold)"
    NORMAL="$(tput sgr0)"
else
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    BLUE=""
    BOLD=""
    NORMAL=""
fi

_err(){
    echo "$*" >&2
}

_command_exists(){
    command -v "$@" > /dev/null 2>&1
}

rootID=0

_runAsRoot(){
    cmd="${*}"
    bash_c='bash -c'
    if [ "${EUID}" -ne "${rootID}" ];then
        if _command_exists sudo; then
            bash_c='sudo -E bash -c'
        elif _command_exists su; then
            bash_c='su -c'
        else
            cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
            exit 1
        fi
    fi
    # only output stderr
    (set -x; $bash_c "${cmd}" >> ${logfile} )
}

function _insert_path(){
    if [ -z "$1" ];then
        return
    fi
    echo -e ${PATH//:/"\n"} | grep -c "^$1$" >/dev/null 2>&1 || export PATH=$1:$PATH
}

_run(){
    # only output stderr
    (set -x; bash -c "${cmd}" >> ${logfile})
}

function _root(){
    if [ ${EUID} -ne ${rootID} ];then
        echo "Need run as root!"
        echo "Requires root privileges."
        exit 1
    fi
}

ed=vi
if _command_exists vim; then
    ed=vim
fi
if _command_exists nvim; then
    ed=nvim
fi
# use ENV: editor to override
if [ -n "${editor}" ];then
    ed=${editor}
fi
_onlyLinux(){
    if [ $(uname) != "Linux" ];then
        _err "Only on linux"
        exit 1
    fi
}
###############################################################################
# write your code below (just define function[s])
# function is hidden when begin with '_'
###############################################################################
binName=clash

case $(uname) in
    Linux)
        # binName=clash-linux
        # binName=clash
        cmdStat=stat
        ;;
    Darwin)
        # binName=clash-darwin
        cmdStat='stat -x'
        ;;
esac
logfile=/tmp/clash.log
configFile=${this}/../config.yaml
configExampleFile=${this}/../config-example.yaml

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
    cd ${this}
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
    local redir_port="$(perl -lne 'print $1 if /^\s*redir-port:\s*(\d+)/' ${configFile})"
    if [ -z "${redir_port}" ];then
        echo "Cannot find redir_port"
        exit 1
    fi
    echo "${green}Found redir_port: ${redir_port}${reset}"
    cmd="$(cat<<EOF
    iptables -t nat -N clash || { return 0; }
    iptables -t nat -A clash -d 0.0.0.0/8 -j RETURN
    iptables -t nat -A clash -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A clash -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A clash -d 169.254.0.0/16 -j RETURN
    iptables -t nat -A clash -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A clash -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A clash -d 224.0.0.0/4 -j RETURN
    iptables -t nat -A clash -d 240.0.0.0/4 -j RETURN
    iptables -t nat -A clash -p tcp -j REDIRECT --to-ports ${redir_port}
    iptables -t nat -A PREROUTING -p tcp -j clash

    ip rule add fwmark 1 table 100
    ip route add local default dev lo table 100
    iptables -t mangle -N clash
    iptables -t mangle -A clash -d 0.0.0.0/8 -j RETURN
    iptables -t mangle -A clash -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A clash -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A clash -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A clash -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A clash -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A clash -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A clash -d 240.0.0.0/4 -j RETURN
    iptables -t mangle -A clash -p udp -j TPROXY --on-port ${redir_port} --tproxy-mark 1
    iptables -t mangle -A PREROUTING -p udp -j clash
EOF
)"
    _runAsRoot "${cmd}"
}

    # iptables -t nat -A PREROUTING -p tcp -j REDIRECT --to-ports 7892
    # iptables -t nat -D PREROUTING -p tcp -j REDIRECT --to-ports 7892
clear(){
    cmd="$(cat<<EOF
    iptables -t nat -D PREROUTING -p tcp -j clash
    iptables -t nat -F clash
    iptables -t nat -X clash

    iptables -t mangle -D PREROUTING -p udp -j clash
    iptables -t mangle -F clash
    iptables -t mangle -X clash

    ip rule del fwmark 1 table 100
EOF
)"
    _runAsRoot "${cmd}"
}

config(){
    if [ ! -e $configFile ];then
        cp $configExampleFile $configFile
    fi
    mtime0="$(${cmdStat} $configFile | grep Modify)"
    $ed $configFile
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
    $ed $0
}

pac(){
    pacfile=${this}/../RuleSet/Pac.yaml
    local mtime0="$(${cmdStat} $pacfile | grep Modify)"
    $ed $pacfile
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
    cd ${this}
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    # perl -lne 'print "\t$1" if /^\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE})
    # perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | grep -v '^\t_'
    perl -lne 'print "\t$2" if /^\s*(function)?\s*(\S+)\s*\(\)\s*\{$/' $(basename ${BASH_SOURCE}) | perl -lne "print if /^\t[^_]/"
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
