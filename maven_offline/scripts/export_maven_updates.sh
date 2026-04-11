#!/bin/bash
# Linux 一键生成 Maven 全量/增量更新包 (智能时间戳标记法)

# 开启 Strict Mode (Fail-Fast 机制)
# -e: 遇错即停; -u: 使用未定义变量报错; -o pipefail: 管道中任何命令失败则整个管道失败
set -euo pipefail

# ================= 颜色与常量定义 =================
readonly RED='\033[31m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly CYAN='\033[36m'
readonly NC='\033[0m'

# ================= 配置区 =================
# 【重要路径说明】
# 本脚本采用动态相对路径，自动将“脚本所在目录的上一级目录”作为基础工作空间。
#
# 为了保证脚本正常运行，请务必保持以下目录结构：
# 你的工作根目录 (如 maven_offline) /
#   ├── repository/         <-- 必须手动准备：将你外网全量的 Maven 仓库放在这里
#   ├── scripts/            <-- 必须手动准备：请将本脚本 (build_incremental.sh) 放在这个文件夹内！
#   ├── incremental/        <-- 无需手动建：脚本运行时会自动生成并存放零散的增量文件
#   └── dist/               <-- 无需手动建：脚本运行时会自动生成并存放最终的 ZIP 压缩包
# =========================================
readonly BASE_PATH="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPOSITORY_PATH="$BASE_PATH/repository"
readonly INCREMENTAL_PATH="$BASE_PATH/incremental"
readonly DIST_PATH="$BASE_PATH/dist"
readonly TIMESTAMP_FILE="$BASE_PATH/.last_build_time"
readonly CURRENT_RUN_TIME_FILE="$BASE_PATH/.current_run_time"

# ================= 资源清理与异常捕获 =================
# 无论脚本正常退出还是异常终止，都将执行清理操作
cleanup() {
    local exit_code=$?
    echo -e "${YELLOW}🧹 执行清理生命周期...${NC}"
    rm -rf "$INCREMENTAL_PATH"
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}❌ 脚本异常终止，丢弃本次时间戳标记。${NC}"
        rm -f "$CURRENT_RUN_TIME_FILE"
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ================= 主逻辑 =================
echo -e "${CYAN}开始提取 Maven 依赖...${NC}"

# 依赖检查
if ! command -v zip >/dev/null 2>&1; then
    echo -e "${RED}❌ 错误: 当前系统未安装 'zip' 命令！${NC}"
    exit 1
fi

if [ ! -d "$REPOSITORY_PATH" ]; then
    echo -e "${RED}❌ 错误: 找不到 Maven 仓库源目录: $REPOSITORY_PATH${NC}"
    exit 1
fi

# 初始化目录与时间戳
mkdir -p "$INCREMENTAL_PATH" "$DIST_PATH"
touch "$CURRENT_RUN_TIME_FILE"
readonly run_date=$(date +%Y%m%d_%H%M%S)

cd "$REPOSITORY_PATH"

# 智能增量判断
local prefix="full"
if [ -f "$TIMESTAMP_FILE" ]; then
    echo -e "${YELLOW}检测到上次打包时间戳记录，提取新增量文件...${NC}"
    prefix="update"
    find . -type f -newer "$TIMESTAMP_FILE" -exec cp --parents {} "$INCREMENTAL_PATH" \; 2>/dev/null || true
else
    echo -e "${YELLOW}首次执行，进行【全量打包】...${NC}"
    find . -type f -exec cp --parents {} "$INCREMENTAL_PATH" \; 2>/dev/null || true
fi

# 检查是否有文件变更
local file_count
file_count=$(find "$INCREMENTAL_PATH" -type f | wc -l)

if [ "$file_count" -eq 0 ]; then
    echo -e "${GREEN}🎉 没有发现需要同步的新增/修改依赖文件。${NC}"
    rm -f "$CURRENT_RUN_TIME_FILE"
    exit 0
fi

echo -e "${CYAN}共发现 $file_count 个变更文件，正在清理冗余校验文件...${NC}"
find "$INCREMENTAL_PATH" -type f \( -name "*.sha1" -o -name "*.md5" -o -name "*.lastUpdated" -o -name "_remote.repositories" \) -exec rm -f {} + 2>/dev/null || true

local valid_file_count
valid_file_count=$(find "$INCREMENTAL_PATH" -type f | wc -l)

if [ "$valid_file_count" -eq 0 ]; then
    echo -e "${GREEN}🎉 清理无用校验文件后，无有效依赖文件需打包。${NC}"
    rm -f "$CURRENT_RUN_TIME_FILE"
    exit 0
fi

# 执行打包
readonly zip_name="${prefix}_${run_date}.zip"
readonly zip_full_path="$DIST_PATH/$zip_name"

echo -e "${CYAN}正在生成 ZIP 文件...${NC}"
cd "$INCREMENTAL_PATH"
zip -qr "$zip_full_path" .

# 成功后更新时间戳
mv -f "$CURRENT_RUN_TIME_FILE" "$TIMESTAMP_FILE"
echo -e "${GREEN}✅ 打包成功：$zip_full_path${NC}"