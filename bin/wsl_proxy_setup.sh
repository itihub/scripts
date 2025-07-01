#!/bin/bash
# 确保替换 Clash 端口
# --- 修正版 WSL 代理配置，基于默认网关查找 ---

# 动态获取Windows宿主机的真实局域网IP地址
# 查找具有默认网关的IPv4地址，这是最可靠的方式来识别主要的网络连接
export WINDOWS_HOST_IP=$(
  ipconfig.exe | \
  iconv -f GBK -t UTF-8 | \
  sed -n '/无线局域网适配器 WLAN:/,/^$/p' | \
  grep -E 'IPv4 地址|IPv4 Address' | \
  grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
  head -n 1
)

# 你的Clash代理端口
CLASH_HTTP_PORT="7890" # 替换为你的Clash HTTP端口
CLASH_SOCKS5_PORT="7890" # 替换为你的Clash SOCKS5端口

# 检查是否获取到IP，如果获取到则设置代理
if [ -n "$WINDOWS_HOST_IP" ]; then
    export HTTP_PROXY="http://${WINDOWS_HOST_IP}:${CLASH_HTTP_PORT}"
    export HTTPS_PROXY="http://${WINDOWS_HOST_IP}:${CLASH_HTTP_PORT}"
    export ALL_PROXY="socks5://${WINDOWS_HOST_IP}:${CLASH_SOCKS5_PORT}"

    # 某些工具可能使用小写环境变量
    export http_proxy=$HTTP_PROXY
    export https_proxy=$HTTPS_PROXY
    export all_proxy=$ALL_PROXY

    echo "Proxy set to ${HTTP_PROXY} for WSL: ${WINDOWS_HOST_IP}"
else
    echo "警告: 未能自动获取Windows宿主机IP地址。代理未设置。请检查网络连接和ipconfig输出。"
fi

# --- 结束 WSL 代理配置 ---

# 应用方式：在 ~/.bashrc 中引用这个脚本
# if [ -f "$HOME/scripts/wsl_proxy_setup.sh" ]; then
#    . "$HOME/scripts/wsl_proxy_setup.sh" # 或者 source "$HOME/scripts/wsl_proxy_setup.sh"
# fi
