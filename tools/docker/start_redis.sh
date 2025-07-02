#!/bin/bash

# 定义容器名称
CONTAINER_NAME="my-redis"


echo "Checking for existing container: ${CONTAINER_NAME}..."

# 检查容器是否存在
if docker ps -a -q -f name=${CONTAINER_NAME} | grep -q .; then
    # 如果找到了容器ID (grep -q . 表示找到了非空输出)
    echo "Container '${CONTAINER_NAME}' exists. Starting it..."
    docker start ${CONTAINER_NAME}
else
  # docker run 命令
  docker run --name ${CONTAINER_NAME} \
    -p 6379:6379 \
    -v redis_data:/data \
    redis:7.2.5

  if [ $? -eq 0 ]; then
      echo "Redis container '${CONTAINER_NAME}' created and started successfully."
  else
      echo "Error: Failed to create or start redis container '${CONTAINER_NAME}'."
      exit 1
  fi
fi

# 检查容器是否正在运行
if docker ps -q -f name=${CONTAINER_NAME} | grep -q .; then
    echo "Redis container '${CONTAINER_NAME}' is now running."
else
    echo "Error: Redis container '${CONTAINER_NAME}' is not running after operation."
    exit 1
