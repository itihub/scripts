#!/bin/bash

# --- 变量设置 ---
# 容器名称
CONTAINER_NAME="my-mysql"
# MySQL Docker Hub 官方 LTS 标签
IMAGE_TAG="mysql:lts"
# Root 用户密码（!!! 请务必修改为复杂密码 !!!）
MYSQL_ROOT_PASSWORD="YourSecurePasswordHere"
# 映射到主机的端口号
HOST_PORT="3306"
# 用于持久化数据的 Docker 命名卷名称
VOLUME_NAME="mysql_data"


echo "--- 正在启动 MySQL LTS 容器 ---"
echo "Checking for existing container: ${CONTAINER_NAME}..."

# 1. 检查容器是否存在
# docker ps -a -q -f name=... 用于查询所有容器（包括已停止的）
if docker ps -a -q -f name=${CONTAINER_NAME} | grep -q .; then
    # 如果找到了容器ID (grep -q . 表示找到了非空输出)
    echo "Container '${CONTAINER_NAME}' exists. Starting it..."
    docker start ${CONTAINER_NAME}

else
    # 2. 如果容器不存在，则执行 docker run 命令创建并启动

    docker run --name ${CONTAINER_NAME} \
        -d \
        -p ${HOST_PORT}:3306 \
        -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
        -v ${VOLUME_NAME}:/var/lib/mysql \
        ${IMAGE_TAG}

    # 检查 docker run 命令是否成功
    if [ $? -eq 0 ]; then
        echo "MySQL container '${CONTAINER_NAME}' created and started successfully."
    else
        echo "Error: Failed to create or start MySQL container '${CONTAINER_NAME}'."
        exit 1
    fi
fi

# 3. 最终状态检查：检查容器是否正在运行
# docker ps -q -f name=... 只查询正在运行的容器
if docker ps -q -f name=${CONTAINER_NAME} | grep -q .; then
    echo "--------------------------------------------------------"
    echo "✅ MySQL LTS 容器 '${CONTAINER_NAME}' 运行中。"
    echo "镜像版本: ${IMAGE_TAG}"
    echo "端口: ${HOST_PORT}"
    echo "数据卷: ${VOLUME_NAME}"
    echo "连接示例: mysql -h 127.0.0.1 -P ${HOST_PORT} -u root -p"
    echo "--------------------------------------------------------"
else
    echo "❌ Error: MySQL 容器 '${CONTAINER_NAME}' 在操作后未运行。"
    echo "请检查 'docker logs ${CONTAINER_NAME}' 获取更多信息。"
    exit 1
fi
