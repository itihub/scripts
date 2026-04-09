#!/bin/bash
# Nginx 自动化源码编译安装脚本
# 开启 Debug 追踪模式：使用 bash -x 命令来执行脚本
#
# 【离线安装说明】：如果是无外网的离线环境，请提前将对应版本的 Nginx 源码压缩包
# 放置在下方配置区中 SRC_DIR 变量所指定的目录下，脚本将自动跳过下载直接使用。
#
# 【仅下载模式】：执行脚本时带上 --download-only 或 -d 参数，将仅下载源码包到 SRC_DIR 并退出。
# 【便携打包模式】：执行带上 --portable 或 -p 参数，编译配置完成后将直接打包成绿色可移植包并退出。

set -e # 遇到错误立即退出

# ================= 帮助信息函数 =================
show_help() {
    echo "用法: bash nginx_install.sh [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help           显示此帮助信息并退出"
    echo "  -d, --download-only  仅下载模式：仅下载源码包到配置的 SRC_DIR 目录并退出"
    echo "  -p, --portable       便携打包模式：编译配置完成后直接生成绿色可移植包 (.tar.gz) 并退出"
    echo ""
    echo "如果不带任何参数执行，脚本将按默认流程完成下载、编译、安装、系统服务注册及进程启动。"
}
# ==================================================

# ================= 命令行参数解析 =================
DOWNLOAD_ONLY=false
BUILD_PORTABLE=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        -d|--download-only) DOWNLOAD_ONLY=true; shift ;;
        -p|--portable) BUILD_PORTABLE=true; shift ;;
        *) echo "未知参数 '$1'。请使用 -h 或 --help 查看可用参数。" >&2; exit 1 ;;
    esac
done
# ==================================================

# ================= 配置区 =================
NGINX_VER="1.28.3"
PCRE_VER="10.42"
OPENSSL_VER="3.3.0"
ZLIB_VER="1.3.1"

INSTALL_DIR="/app/nginx/install"
SRC_DIR="/app/nginx/src"

# 服务控制配置
SKIP_SERVICE_SETUP="true" # 设置为 "true" 则跳过 Systemd 注册与自动启动

# 运行用户与用户组配置
RUN_USER="nginx"
RUN_GROUP="nginx"
# ==========================================

echo ">>> [0/7] 检查当前幂等状态..."

# 探测是否支持 Systemd
HAS_SYSTEMD=false
if command -v systemctl >/dev/null 2>&1; then
    HAS_SYSTEMD=true
fi

SKIP_COMPILE=false
if [ -x "${INSTALL_DIR}/sbin/nginx" ]; then
    # 提取已安装的 Nginx 版本号
    INSTALLED_VER=$(${INSTALL_DIR}/sbin/nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
    if [ "$INSTALLED_VER" == "$NGINX_VER" ]; then
        echo ">>> 检测到 Nginx v${NGINX_VER} 已成功安装在 ${INSTALL_DIR}，跳过源码编译步骤！"
        SKIP_COMPILE=true
    else
        echo ">>> 现存版本 ($INSTALLED_VER) 与目标版本 ($NGINX_VER) 不符，准备重编译..."
    fi
fi

if [ "$SKIP_COMPILE" = false ]; then
    if [ "$DOWNLOAD_ONLY" = false ]; then
        echo ">>> [1/7] 验证编译环境 (GCC/Make)..."
        if ! command -v gcc >/dev/null 2>&1; then
            echo "❌ 错误: 未检测到 gcc 编译器。请先安装环境 (如: yum install -y gcc 或 apt install -y gcc)" >&2
            exit 1
        fi
        if ! command -v make >/dev/null 2>&1; then
            echo "❌ 错误: 未检测到 make 工具。请先安装环境 (如: yum install -y make 或 apt install -y make)" >&2
            exit 1
        fi
    else
        echo ">>> [1/7] 仅下载模式激活，跳过编译环境验证..."
    fi

    echo ">>> [2/7] 准备依赖包与目录..."
    mkdir -p $SRC_DIR
    cd $SRC_DIR

    [ ! -f nginx-${NGINX_VER}.tar.gz ] && wget https://nginx.org/download/nginx-${NGINX_VER}.tar.gz
    [ ! -f pcre2-${PCRE_VER}.tar.gz ] && wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE_VER}/pcre2-${PCRE_VER}.tar.gz
    [ ! -f openssl-${OPENSSL_VER}.tar.gz ] && wget https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz
    [ ! -f zlib-${ZLIB_VER}.tar.gz ] && wget https://zlib.net/fossils/zlib-${ZLIB_VER}.tar.gz

    if [ "$DOWNLOAD_ONLY" = true ]; then
        echo ">>> 下载完成！源码包已保存在：${SRC_DIR}"
        echo ">>> 仅下载模式执行完毕，正常退出。"
        exit 0
    fi

    echo ">>> [3/7] 清理旧目录并解压源码..."
    rm -rf nginx-${NGINX_VER} pcre2-${PCRE_VER} openssl-${OPENSSL_VER} zlib-${ZLIB_VER}
    for file in *.tar.gz; do tar -zxf "$file"; done

    echo ">>> [4/7] 开始编译 Nginx..."
    # 【核心防御】：如果 Nginx 正在运行，覆盖二进制文件会报 text file busy，需先停止
    if ps -ef | grep -v grep | grep -q "nginx: master process"; then
        echo ">>> 检测到 Nginx 进程运行中，正在停止以便覆盖安装..."
        
        # 1. 优先使用 Nginx 原生命令优雅停止
        if [ -x "${INSTALL_DIR}/sbin/nginx" ]; then
            ${INSTALL_DIR}/sbin/nginx -s stop 2>/dev/null || true
        fi
        
        # 2. 如果系统有 systemd，也同步 stop 一下，以修正 Systemd 内部的状态机
        if [ "$HAS_SYSTEMD" = true ]; then
            systemctl stop nginx 2>/dev/null || true
        fi
        
        sleep 2 # 等待进程完全释放文件描述符
    fi

    cd nginx-${NGINX_VER}
    ./configure \
      --prefix=${INSTALL_DIR} \
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-pcre=../pcre2-${PCRE_VER} \
      --with-zlib=../zlib-${ZLIB_VER} \
      --with-openssl=../openssl-${OPENSSL_VER}

    make -j $(nproc) && make install

    if [ "$BUILD_PORTABLE" = true ]; then
        echo ">>> [4.5/7] 便携打包模式激活：正在生成可移植绿色包..."
        PORTABLE_PKG="${SRC_DIR}/nginx_portable_$(uname -m)_${NGINX_VER}.tar.gz"
        cd $(dirname ${INSTALL_DIR})
        
        # 将已编译和配置好的程序主目录打包
        tar -zcvf ${PORTABLE_PKG} --transform 's/^install/nginx/' $(basename ${INSTALL_DIR})
        
        echo ">>> ----------------------------------------------------"
        echo ">>> 打包完成！离线便携包已生成至：${PORTABLE_PKG}"
        echo ">>> 【离线分发部署指南】："
        echo ">>> 1. 将此压缩包和本安装脚本拷至目标离线服务器"
        echo ">>> 2. 在目标服务器创建父目录: mkdir -p $(dirname ${INSTALL_DIR})"
        echo ">>> 3. 解压绿色便携包: tar -zxvf $(basename ${PORTABLE_PKG}) -C $(dirname ${INSTALL_DIR})"
        echo ">>> 4. 在目标服务器执行本脚本: bash nginx_install.sh"
        echo ">>> 此时脚本将跳过编译，直接完成用户装配、权限下发与启动！"
        echo ">>> ----------------------------------------------------"
        exit 0
    fi
fi

echo ">>> [5/7] 配置运行用户与权限..."
if ! getent group ${RUN_GROUP} >/dev/null; then groupadd ${RUN_GROUP}; fi
if ! getent passwd ${RUN_USER} >/dev/null; then useradd -g ${RUN_GROUP} -s /sbin/nologin ${RUN_USER}; fi
chown -R ${RUN_USER}:${RUN_GROUP} ${INSTALL_DIR}

echo ">>> [6/7] 配置服务管理机制..."
if [ "$SKIP_SERVICE_SETUP" = "true" ]; then
    echo ">>> 配置指定了 SKIP_SERVICE_SETUP=true，已跳过服务注册。"
elif [ "$HAS_SYSTEMD" = true ]; then
    cat > /usr/lib/systemd/system/nginx.service << EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=network.target

[Service]
Type=forking
ExecStart=${INSTALL_DIR}/sbin/nginx
ExecReload=${INSTALL_DIR}/sbin/nginx -s reload
ExecStop=${INSTALL_DIR}/sbin/nginx -s quit
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable nginx
else
    echo ">>> 当前系统不支持 Systemd，已跳过 .service 注册。将使用原生二进制控制进程。"
fi

echo ">>> [7/7] 启动或重载服务..."
if [ "$SKIP_SERVICE_SETUP" = "true" ]; then
    echo ">>> 部署完成！因配置了跳过服务管理，程序未自动启动。"
    echo ">>> 如果需要手动启动，请执行以下命令："
    echo ">>> ${INSTALL_DIR}/sbin/nginx"
else
    # 统一通过真实进程判定走 start 还是 reload
    if ps -ef | grep -v grep | grep -q "nginx: master process"; then
        if [ "$HAS_SYSTEMD" = true ]; then
            # 注意：如果原来是手动拉起的，这里 systemctl reload 可能会失败，
            # 但我们在第三步已经强制 stop 过了，能走到这里的通常是跳过编译(SKIP_COMPILE=true)的情况
            systemctl reload nginx || ${INSTALL_DIR}/sbin/nginx -s reload
        else
            ${INSTALL_DIR}/sbin/nginx -s reload
        fi
        echo ">>> 进程已在运行，重新加载配置完成！"
    else
        if [ "$HAS_SYSTEMD" = true ]; then
            systemctl start nginx
        else
            ${INSTALL_DIR}/sbin/nginx
        fi
        echo ">>> 安装并启动完成！"
    fi
fi