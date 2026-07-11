#!/bin/bash
# 脚本名称: set-proxy-wsl.sh
# 作用: 通过 resolv.conf 获取 WSL 虚拟网关 IP 并设置代理

CLASH_HTTP_PORT="7890" 
CLASH_SOCKS5_PORT="7890" 

# 动态获取 WSL 内部虚拟网关 IP
WSL_GATEWAY_IP=$(ip route show default | awk '{print $3}' | head -n 1)

if [ -n "$WSL_GATEWAY_IP" ]; then
    export HTTP_PROXY="http://${WSL_GATEWAY_IP}:${CLASH_HTTP_PORT}"
    export HTTPS_PROXY="http://${WSL_GATEWAY_IP}:${CLASH_HTTP_PORT}"
    export ALL_PROXY="socks5://${WSL_GATEWAY_IP}:${CLASH_SOCKS5_PORT}"

    export http_proxy=$HTTP_PROXY
    export https_proxy=$HTTPS_PROXY
    export all_proxy=$ALL_PROXY

    # 可选：设置本机和局域网不走代理
    # export NO_PROXY="localhost,127.0.0.1,::1,.local,192.168.*.*,10.*.*.*,172.16.*.*"
    # export no_proxy=$NO_PROXY

    echo "[WSL 模式] 代理已稳定指向虚拟网关 IP: ${WSL_GATEWAY_IP}"
else
    echo "警告: 未能从 /etc/resolv.conf 自动获取网关 IP。"
fi
