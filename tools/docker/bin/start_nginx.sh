#!/bin/bash

# 定义容器名称
CONTAINER_NAME="my-nginx"

# 定义 Nginx 配置和静态文件在宿主机用户目录下的相对路径
NGINX_CONFIG_FILE="${HOME}/nginx/nginx.conf"
NGINX_CONFIG_DIR="${HOME}/nginx/conf.d"
MY_HTML_DIR="${HOME}/wiki"

# 停止并删除可能存在的同名容器 (可选，但推荐在开发环境)
echo "Stopping and removing existing container (if any)..."
docker stop ${CONTAINER_NAME} || true
docker rm ${CONTAINER_NAME} || true

echo "Starting Nginx container..."

# docker run 命令
docker run --name ${CONTAINER_NAME} \
  -p 80:80 -p 443:443 \
  -v ${NGINX_CONFIG_FILE}:/etc/nginx/nginx.conf:ro \
  -v ${NGINX_CONFIG_DIR}:/etc/nginx/conf.d:ro \
  -v ${MY_HTML_DIR}:/wiki:ro \
  -d \
  nginx:1.26.1

echo "Nginx container '${CONTAINER_NAME}' started."
