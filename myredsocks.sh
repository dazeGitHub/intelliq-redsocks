#!/bin/bash

#check the user
if [[ "$EUID" -ne 0 ]]; then
	echo "==================<Attention>=================="
        echo "Sorry, you need to run this as root"
	echo "==============================================="
        exit
fi

OS='cat /etc/*-release | sed -r "s/^ID=(.*)$/\\1/;tA;d;:A;s/^\"(.*)\"$/\\1/"'
#OSTYPE=$(cat /etc/os-release | grep -E "^NAME=.*" | awk -F\" '{print $2}')
SOCK_SERVER="127.0.0.1"    #socket5代理服务器
SOCK_PORT="7070"      #socket5代理端口
PROXY_PORT="12345"  #redsock的监听端口

#Installation dependencies
case ${OS} in
	"centos")
	echo "==================<Attention>=================="
        echo "The operating system is CentOS"
	echo "==============================================="
	yum install libevent libevent-devel -y
	;;
	"ubuntu")
	echo "==================<Attention>=================="
        echo "The operating system is Ubuntu"
	echo "==============================================="
	sudo apt-get install libevent-2.0-5 libevent-dev -y
	;;
esac

redsocks_pid="/tmp/redsocks.pid"
function start_redsocks()
{
  echo "start the redsocks........................"
  if [[ -f ${redsocks_pid} ]];then
    echo "the redsocks is stared..................."
    return 0
  fi
  rm -rf redsocks.conf
  cp redsocks.conf.example redsocks.conf 
  if [[ ! -f proxyserverinfo ]];then
    # 本地不存在代理服务器的配置
    read -p "please tell me you sock_server:" sock_server
    if [[ ${sock_server} != "" ]];then
      SOCK_SERVER=$sock_server
    fi
    read -p "please tell me you sock_port:" sock_port
    if [[ ${SOCK_PORT} != "" ]];then
      SOCK_PORT=${sock_port}
    fi
    echo "${SOCK_SERVER}:${SOCK_PORT}" > proxyserverinfo
  else
    # 本地已经存在了代理服务的配置信息,直接读取就好了
    SOCK_SERVER=$(head -n 1 proxyserverinfo | awk -F: '{print $1}')
    SOCK_PORT=$(head -n 1 proxyserverinfo | awk -F: '{print $2}')

  fi
  sed -i '18s/daemon.*/daemon = on;/g'  redsocks.conf
  sed -i '44s/local_port.*/local_port = '${PROXY_PORT}';/g'  redsocks.conf
  sed -i '61s/ip.*/ip = '${SOCK_SERVER}';/g'  redsocks.conf
  sed -i '62s/port.*/port = '${SOCK_PORT}';/g'  redsocks.conf
  ./redsocks -c redsocks.conf -p ${redsocks_pid}
  iptables -t nat -A OUTPUT -p tcp -d ${SOCK_SERVER} -j RETURN
}
function stop_redsocks()
{
  echo "stop the redsocks........................"
  if [[ ! -f ${redsocks_pid} ]];then
    echo "the redsocks is not run...please start......"
    return 0
  fi
  pid=$(cat ${redsocks_pid})
  rm -rf ${redsocks_pid}
  kill -9 ${pid}
  iptables -t nat -F
}
function restart_redsocks()
{
  stop_redsocks
  start_redsocks 
}
until [ $# -eq 0 ]
do
  case $1 in
    start)
    start_redsocks
    shift
    ;;
    stop)
    stop_redsocks
    shift
    ;;
    restart)
    restart_redsocks
    shift
    ;;
    clean)
    iptables -t nat -F 
    shift
    ;;
    proxy)
    #proxy the fwlist.txt
    iptables -t nat -F
    read -p "please tell me you network:" mynetwork
    iptables -t nat -A OUTPUT -p tcp -d ${mynetwork} -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d ${SOCK_SERVER} -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 -j RETURN
    while read line
    do
     echo -e "\033[32m this ip[${line}] will use proxy connected .... \033[0m"
     iptables -t nat -A OUTPUT -p tcp -d ${line} -j REDIRECT --to-ports ${PROXY_PORT}
    done < GFlist.txt
    echo -e "\033[32m your iptabls OUTPUT chain like this.... \033[0m"
    iptables -t nat -nvL --line-numbers
    shift
    ;;
    proxyall)
    #proxy all connection
    #iptables -t nat -F
    #read -p "please tell me you network:" mynetwork
    for i in $(ip route show| awk '{print $1}'|grep -v default)
    do
        iptables -t nat -A OUTPUT -p tcp -d ${i} -j RETURN
    done
    iptables -t nat -A OUTPUT -p tcp -d ${SOCK_SERVER} -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 -j RETURN
    iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports ${PROXY_PORT}
    echo -e "\033[32m your iptabls OUTPUT chain like this.... \033[0m"
    iptables -t nat -nvL --line-numbers
    shift
    ;;
    stop)
    #clean all iptables
    shift
    ;;
    install)
    echo "install the redsocket"
    install_redsocks
    shift
    ;;
    *)
    shift
    ;;
  esac
done

