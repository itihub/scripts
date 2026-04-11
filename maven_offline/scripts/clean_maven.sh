#!/bin/bash

# ==============================================================================
# 脚本名称: clean_maven.sh
# 脚本描述: 深度清理 Maven 本地仓库中的损坏文件，主要用于解决离线打包报错问题。
# 使用场景: 当 Maven 依赖下载中断或需要强制从本地环境打包时使用。
# 
# 参数说明:
#   $1 - (可选) 目标仓库路径。默认为当前目录下的 local_repos。
#
# 使用示例:
#   ./clean_maven.sh                      # 清理当前目录下的 local_repos
#   ./clean_maven.sh /path/to/your/repo   # 清理指定目录
# ==============================================================================

# 1. 动态获取目标路径：优先使用命令行参数，缺省则指向 ./local_repos
TARGET_DIR="${1:-./local_repos}"

# 2. 检查目录是否存在，避免 find 命令报错
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误: 目录 '$TARGET_DIR' 不存在，请检查路径是否正确。"
    exit 1
fi

# 3. 将相对路径转换为绝对路径
REPO_PATH=$(cd "$TARGET_DIR" && pwd)

echo ">>> 开始清理 Maven 仓库: $REPO_PATH"

# 4. 清理下载失败的标记文件 (*.lastUpdated)
# 这些文件会阻止 Maven 在网络恢复后重新下载依赖。
find "$REPO_PATH" -name "*.lastUpdated" -type f -delete
echo " [OK] 已移除所有下载失败标记 (.lastUpdated)"

# 5. 清理远程仓库记录文件 (_remote.repositories)
# 离线打包关键：移除此文件可防止 Maven 在离线模式下校验远程仓库 ID。
find "$REPO_PATH" -name "_remote.repositories" -type f -delete
echo " [OK] 已移除所有远程同步记录 (_remote.repositories)"

echo ">>> 清理完成！"