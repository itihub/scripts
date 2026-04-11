#!/bin/bash
# 深度清理 Maven 本地仓库中的损坏文件
# ==============================================================================
# 脚本名称: clean_maven_repo.sh
# 脚本描述: 深度清理 Maven 本地仓库中的损坏文件，主要用于解决离线打包报错问题。
# 使用场景: 当 Maven 依赖下载中断或需要强制从本地环境打包时使用。
# 
# 参数说明:
#   $1 - (可选) 目标仓库路径。默认为$HOME/.m2/repository。
#
# 使用示例:
#   ./clean_maven_repo.sh                      # 清理$HOME/.m2/repository
#   ./clean_maven_repo.sh /path/to/your/repo   # 清理指定目录
# ==============================================================================


set -euo pipefail

# 强制要求传递路径，或者配置更安全的默认用户目录。
readonly target_dir="${1:-$HOME/.m2/repository}"

if [ ! -d "$target_dir" ]; then
    echo "错误: 目录 '$target_dir' 不存在。"
    exit 1
fi

readonly repo_path=$(cd "$target_dir" && pwd)
echo ">>> 开始清理 Maven 仓库: $repo_path"

# 清理下载失败的标记文件 (*.lastUpdated)
# 这些文件会阻止 Maven 在网络恢复后重新下载依赖。
find "$repo_path" -name "*.lastUpdated" -type f -exec rm -f {} +
echo " [OK] 已移除所有下载失败标记 (.lastUpdated)"

# 清理远程仓库记录文件 (_remote.repositories)
# 离线打包关键：移除此文件可防止 Maven 在离线模式下校验远程仓库 ID。
find "$repo_path" -name "_remote.repositories" -type f -exec rm -f {} +
echo " [OK] 已移除所有远程同步记录 (_remote.repositories)"

echo ">>> 清理完成！"