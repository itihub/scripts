#!/bin/bash

# --- 变量设置 ---
# 容器名称
CONTAINER_NAME="my-mariadb"
IMAGE_TAG="mariadb:11.4"
MARIADB_ROOT_PASSWORD="123456"
# 映射到主机的端口号
HOST_PORT="13306"
# 用于持久化数据的 Docker 命名卷名称
VOLUME_NAME="mariadb_data"

echo "--- 正在启动 MariaDB 容器 ---"
echo "Checking for existing container: ${CONTAINER_NAME}..."

# 1. 检查容器是否存在
if docker ps -a -q -f name=^/${CONTAINER_NAME}$ | grep -q .; then
    # 如果找到了容器
    echo "Container '${CONTAINER_NAME}' exists. Starting it..."
    docker start ${CONTAINER_NAME}
else
    # 2. 如果容器不存在，则执行 docker run 命令
    echo "Creating new MariaDB container..."
    
    docker run --name ${CONTAINER_NAME} \
        -d \
        --restart unless-stopped \
        -p ${HOST_PORT}:3306 \
        -e MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD}" \
        -v ${VOLUME_NAME}:/var/lib/mysql \
        ${IMAGE_TAG}

    if [ $? -eq 0 ]; then
        echo "MariaDB container '${CONTAINER_NAME}' created and started successfully."
    else
        echo "Error: Failed to create or start MariaDB container."
        exit 1
    fi
fi

# 3. 最终状态检查
if docker ps -q -f name=^/${CONTAINER_NAME}$ | grep -q .; then
    echo "--------------------------------------------------------"
    echo "✅ MariaDB 容器 '${CONTAINER_NAME}' 运行中。"
    echo "镜像版本: ${IMAGE_TAG}"
    echo "端口: ${HOST_PORT}"
    echo "数据卷: ${VOLUME_NAME}"
    echo "连接示例: mariadb -h 127.0.0.1 -P ${HOST_PORT} -u root -p"
    echo "--------------------------------------------------------"
else
    echo "❌ Error: MariaDB 容器未能在操作后正常运行。"
    echo "请执行 'docker logs ${CONTAINER_NAME}' 查看报错日志。"
    exit 1
fi
