#!/bin/bash
# Redis 自动化源码编译安装脚本
# 开启 Debug 追踪模式：使用 bash -x 命令来执行脚本
#
# 【离线安装说明】：如果是无外网的离线环境，请提前将对应版本的 Redis 源码压缩包
# 放置在下方配置区中 SRC_DIR 变量所指定的目录下，脚本将自动跳过下载直接使用。
#
# 【仅下载模式】：执行脚本时带上 --download-only 或 -d 参数，将仅下载源码包到 SRC_DIR 并退出。

set -e # 遇到错误立即退出

# ================= 命令行参数解析 =================
DOWNLOAD_ONLY=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--download-only) DOWNLOAD_ONLY=true; shift ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done
# ==================================================

# ================= 配置区 =================
REDIS_VER="7.2.4"

INSTALL_DIR="/app/my_redis"
SRC_DIR="/app/redis-build/src"
CONF_DIR="${INSTALL_DIR}/conf"
DATA_DIR="/data/redis"

# 网络与安全配置
REDIS_PORT="6379"
REDIS_PASS="" # 设置为空 ("") 则不开启密码验证

# 服务控制配置
SKIP_SERVICE_SETUP="false" # 设置为 "true" 则跳过 Systemd 注册与自动启动

# 运行用户与用户组配置
RUN_USER="redis"
RUN_GROUP="redis"
# ==========================================

# 内部停止函数 (处理端口和密码参数，屏蔽警告与错误输出)
stop_redis_cli() {
    if [ -x "${INSTALL_DIR}/bin/redis-cli" ]; then
        if [ -n "$REDIS_PASS" ]; then
            ${INSTALL_DIR}/bin/redis-cli -p ${REDIS_PORT} -a "${REDIS_PASS}" shutdown 2>/dev/null || true
        else
            ${INSTALL_DIR}/bin/redis-cli -p ${REDIS_PORT} shutdown 2>/dev/null || true
        fi
    fi
}

echo ">>> [0/7] 检查当前环境与幂等状态..."

# 探测是否支持 Systemd
HAS_SYSTEMD=false
if command -v systemctl >/dev/null 2>&1; then
    HAS_SYSTEMD=true
fi

SKIP_COMPILE=false
if [ -x "${INSTALL_DIR}/bin/redis-server" ]; then
    # 提取已安装的 Redis 版本号
    INSTALLED_VER=$(${INSTALL_DIR}/bin/redis-server -v | grep -oP 'v=\K[0-9.]+')
    if [ "$INSTALLED_VER" == "$REDIS_VER" ]; then
        echo ">>> 检测到 Redis v${REDIS_VER} 已成功安装在 ${INSTALL_DIR}，跳过源码编译步骤！"
        SKIP_COMPILE=true
    else
        echo ">>> 现存版本 ($INSTALLED_VER) 与目标版本 ($REDIS_VER) 不符，准备重编译..."
    fi
fi

if [ "$SKIP_COMPILE" = false ]; then
    if [ "$DOWNLOAD_ONLY" = false ]; then
        echo ">>> [1/7] 验证编译环境 (GCC/Make)..."
        if ! command -v gcc >/dev/null 2>&1; then
            echo "❌ 错误: 未检测到 gcc 编译器。请先安装环境 (如: yum install -y gcc)" >&2
            exit 1
        fi
        if ! command -v make >/dev/null 2>&1; then
            echo "❌ 错误: 未检测到 make 工具。请先安装环境 (如: yum install -y make)" >&2
            exit 1
        fi
    else
        echo ">>> [1/7] 仅下载模式激活，跳过编译环境验证..."
    fi

    echo ">>> [2/7] 准备依赖包与目录..."
    mkdir -p $SRC_DIR
    cd $SRC_DIR

    [ ! -f redis-${REDIS_VER}.tar.gz ] && wget https://download.redis.io/releases/redis-${REDIS_VER}.tar.gz

    if [ "$DOWNLOAD_ONLY" = true ]; then
        echo ">>> 下载完成！源码包已保存在：${SRC_DIR}"
        echo ">>> 仅下载模式执行完毕，正常退出。"
        exit 0
    fi

    echo ">>> [3/7] 清理旧目录并解压源码..."
    rm -rf redis-${REDIS_VER}
    tar -zxf redis-${REDIS_VER}.tar.gz

    echo ">>> [4/7] 开始编译 Redis..."
    # 【核心防御】：探测真实的 Redis 进程，防止覆盖运行时文件报错
    if ps -ef | grep -v grep | grep -q "redis-server"; then
        echo ">>> 检测到 Redis 进程运行中，正在停止以便覆盖安装..."
        
        stop_redis_cli
        
        if [ "$HAS_SYSTEMD" = true ]; then
            systemctl stop redis 2>/dev/null || true
        fi
        
        sleep 2
    fi

    cd redis-${REDIS_VER}
    # Redis 直接 make 即可，无需 ./configure
    make -j $(nproc)
    make PREFIX=${INSTALL_DIR} install

    # 准备配置文件与数据目录
    mkdir -p ${CONF_DIR}
    mkdir -p ${DATA_DIR}/data
    mkdir -p ${DATA_DIR}/logs
    cp redis.conf ${CONF_DIR}/

    # 修改 Redis 配置以符合后台服务规范
    sed -i 's/^daemonize no/daemonize yes/' ${CONF_DIR}/redis.conf
    sed -i "s|^dir .*|dir ${DATA_DIR}/data|" ${CONF_DIR}/redis.conf
    sed -i "s|^logfile .*|logfile ${DATA_DIR}/logs/redis.log|" ${CONF_DIR}/redis.conf
    
    # 动态修改端口配置
    sed -i "s/^port .*/port ${REDIS_PORT}/" ${CONF_DIR}/redis.conf
    
    # 动态修改密码配置
    if [ -n "$REDIS_PASS" ]; then
        # 移除可能已存在的 requirepass（防止重复写入），然后追加
        sed -i '/^requirepass/d' ${CONF_DIR}/redis.conf
        echo "requirepass ${REDIS_PASS}" >> ${CONF_DIR}/redis.conf
    else
        sed -i '/^requirepass/d' ${CONF_DIR}/redis.conf
    fi
fi

echo ">>> [5/7] 配置运行用户与权限..."
if ! getent group ${RUN_GROUP} >/dev/null; then groupadd ${RUN_GROUP}; fi
if ! getent passwd ${RUN_USER} >/dev/null; then useradd -g ${RUN_GROUP} -s /sbin/nologin ${RUN_USER}; fi
chown -R ${RUN_USER}:${RUN_GROUP} ${INSTALL_DIR}
chown -R ${RUN_USER}:${RUN_GROUP} ${DATA_DIR}

echo ">>> [6/7] 配置服务管理机制..."
if [ "$SKIP_SERVICE_SETUP" = "true" ]; then
    echo ">>> 配置指定了 SKIP_SERVICE_SETUP=true，已跳过服务注册。"
elif [ "$HAS_SYSTEMD" = true ]; then
    # 构造 Systemd 使用的 ExecStop 行，确保停止服务时带有密码和端口验证
    if [ -n "$REDIS_PASS" ]; then
        EXEC_STOP_LINE="ExecStop=${INSTALL_DIR}/bin/redis-cli -p ${REDIS_PORT} -a \"${REDIS_PASS}\" shutdown"
    else
        EXEC_STOP_LINE="ExecStop=${INSTALL_DIR}/bin/redis-cli -p ${REDIS_PORT} shutdown"
    fi

    cat > /usr/lib/systemd/system/redis.service << EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
Type=forking
User=${RUN_USER}
Group=${RUN_GROUP}
ExecStart=${INSTALL_DIR}/bin/redis-server ${CONF_DIR}/redis.conf
${EXEC_STOP_LINE}
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable redis
else
    echo ">>> 当前系统不支持 Systemd，已跳过 .service 注册。将使用原生二进制控制进程。"
fi

echo ">>> [7/7] 启动或重启服务..."
if [ "$SKIP_SERVICE_SETUP" = "true" ]; then
    echo ">>> 部署完成！因配置了跳过服务管理，程序未自动启动。"
    echo ">>> 如果需要手动启动，请执行以下命令："
    echo ">>> sudo -u ${RUN_USER} ${INSTALL_DIR}/bin/redis-server ${CONF_DIR}/redis.conf"
else
    # 统一通过真实进程判定状态
    if ps -ef | grep -v grep | grep -q "redis-server"; then
        if [ "$HAS_SYSTEMD" = true ]; then
            # Redis 不支持无缝 reload，变更配置需 restart
            systemctl restart redis || (stop_redis_cli && sleep 1 && sudo -u ${RUN_USER} ${INSTALL_DIR}/bin/redis-server ${CONF_DIR}/redis.conf)
        else
            stop_redis_cli
            sleep 1
            sudo -u ${RUN_USER} ${INSTALL_DIR}/bin/redis-server ${CONF_DIR}/redis.conf
        fi
        echo ">>> 进程已在运行，服务已安全重启（确保加载最新配置）！"
    else
        if [ "$HAS_SYSTEMD" = true ]; then
            systemctl start redis
        else
            sudo -u ${RUN_USER} ${INSTALL_DIR}/bin/redis-server ${CONF_DIR}/redis.conf
        fi
        echo ">>> 安装并启动完成！"
    fi