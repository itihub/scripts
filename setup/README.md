```bash
cat << 'EOF' >> ~/.bashrc

# ==========================================
# WSL / 局域网代理快捷切换工具
# ==========================================

# 1. 启动 [虚拟网关代理]
alias proxy-wsl="source ~/scripts/setup/set-proxy-wsl.sh"

# 2. 启动 [物理局域网代理]
alias proxy-lan="source ~/scripts/setup/set-proxy-lan.sh"

# 3. 一键关闭所有代理
alias proxy-off="unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY no_proxy && echo ' 代理已完全关闭'"

# 4. 检查当前代理状态
alias proxy-status="env | grep -iE 'http_proxy|https_proxy|all_proxy'"

# 5. 自动设置 WSL 虚拟网关代理
PROXY_SCRIPT="$HOME/scripts/setup/set-proxy-wsl.sh"
if [ -f "$PROXY_SCRIPT" ]; then
    source "$PROXY_SCRIPT"
fi
# ==========================================
EOF

```
