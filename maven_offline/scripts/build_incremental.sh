#!/bin/bash
# Linux 一键生成 Maven 全量/增量更新包 (智能时间戳标记法)

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

# 自动获取脚本所在目录的上一级目录作为绝对路径
BASE_PATH="$(cd "$(dirname "$0")/.." && pwd)"
REPOSITORY_PATH="$BASE_PATH/repository"
INCREMENTAL_PATH="$BASE_PATH/incremental"
DIST_PATH="$BASE_PATH/dist"
TIMESTAMP_FILE="$BASE_PATH/.last_build_time"
CURRENT_RUN_TIME_FILE="$BASE_PATH/.current_run_time"
# =========================================

# ================= 颜色定义 =================
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
NC='\033[0m' # No Color (重置默认颜色)
# =========================================

echo -e "${CYAN}开始提取 Maven 依赖...${NC}"

# 0. 检查系统是否安装了必要的 zip 命令
if ! command -v zip &> /dev/null; then
    echo -e "${RED}❌ 错误: 当前系统未安装 'zip' 命令！${NC}"
    echo -e "${YELLOW}💡 提示: CentOS/RHEL 请执行 'sudo yum install zip'，Ubuntu/Debian 请执行 'sudo apt-get install zip' 安装后重试。${NC}"
    exit 1
fi

# 1. 检查源目录
if [ ! -d "$REPOSITORY_PATH" ]; then
    echo -e "${RED}❌ 错误: 找不到 Maven 仓库源目录: $REPOSITORY_PATH${NC}"
    echo -e "${YELLOW}💡 提示: 请检查是否按规范将本脚本放入了 scripts/ 目录下，并且 repository/ 目录与 scripts/ 目录同级。${NC}"
    exit 1
fi

# 2. 清理并重建相关目录
rm -rf "$INCREMENTAL_PATH"
mkdir -p "$INCREMENTAL_PATH"
mkdir -p "$DIST_PATH"

# 记录本次任务开始的时间标记，作为下次的增量基准（防漏扫机制）
touch "$CURRENT_RUN_TIME_FILE"
DATE=$(date +%Y%m%d_%H%M%S)

# 3. 智能判断全量还是增量
cd "$REPOSITORY_PATH" || exit

if [ -f "$TIMESTAMP_FILE" ]; then
    echo -e "${YELLOW}检测到上次打包时间戳记录，正在提取新增量文件...${NC}"
    PREFIX="update"
    # 使用 -newer 查找修改时间晚于时间戳记录的文件并复制（保留目录结构）
    find . -type f -newer "$TIMESTAMP_FILE" -exec cp --parents {} "$INCREMENTAL_PATH" \; 2>/dev/null
else
    echo -e "${YELLOW}首次执行(无时间戳记录)，正在扫描所有依赖进行【全量打包】...${NC}"
    PREFIX="full"
    # 查找并复制所有文件
    find . -type f -exec cp --parents {} "$INCREMENTAL_PATH" \; 2>/dev/null
fi

# 统计提取出来的文件总数
FILE_COUNT=$(find "$INCREMENTAL_PATH" -type f | wc -l)

if [ "$FILE_COUNT" -eq 0 ]; then
    echo -e "${GREEN}🎉 完美！没有发现需要同步的新增/修改依赖文件。${NC}"
    rm -f "$CURRENT_RUN_TIME_FILE"
    # 顺手清理一下空目录
    rm -rf "$INCREMENTAL_PATH"
    exit 0
fi

echo -e "${CYAN}共发现 $FILE_COUNT 个变更文件，正在清理临时文件和缓存标记...${NC}"

# 清理无用的校验文件和 Maven 本地缓存标记文件
find "$INCREMENTAL_PATH" -type f \( -name "*.sha1" -o -name "*.md5" -o -name "*.lastUpdated" -o -name "_remote.repositories" \) -exec rm -f {} + 2>/dev/null

# 再次检查清理冗余文件后是否还有有效文件
VALID_FILE_COUNT=$(find "$INCREMENTAL_PATH" -type f | wc -l)
if [ "$VALID_FILE_COUNT" -eq 0 ]; then
    echo -e "${GREEN}🎉 清理无用校验文件后，没有需要打包的有效依赖文件。${NC}"
    rm -f "$CURRENT_RUN_TIME_FILE"
    rm -rf "$INCREMENTAL_PATH"
    exit 0
fi

# 4. 打包 ZIP 包
ZIP_NAME="${PREFIX}_${DATE}.zip"
ZIP_FULL_PATH="$DIST_PATH/$ZIP_NAME"

echo -e "${CYAN}正在打包生成 ZIP 文件...${NC}"
# 切换到增量目录内部进行打包，防止解压时带入冗余的顶层文件夹路径
cd "$INCREMENTAL_PATH" || exit

# 执行打包命令，并将结果状态码记录下来
zip -qr "$ZIP_FULL_PATH" .
ZIP_STATUS=$?

# ================= 公共清理阶段 =================
# 切回基础目录，避免因占用导致删除失败
cd "$BASE_PATH" || exit
# 无论成功或失败，都清理暂存区
rm -rf "$INCREMENTAL_PATH"
echo -e "${YELLOW}🧹 已清理临时暂存目录。${NC}"

# ================= 结果处理阶段 =================
if [ $ZIP_STATUS -eq 0 ]; then
    # 5. 更新增量时间戳标记
    mv -f "$CURRENT_RUN_TIME_FILE" "$TIMESTAMP_FILE"
    
    echo -e "${GREEN}✅ 打包成功：$ZIP_FULL_PATH${NC}"
    echo -e "${CYAN}请将此 ZIP 包传输至内网，并使用 unzip -o 命令覆盖到内网的 repository 目录中。${NC}"
else
    # 失败则丢弃本次的防漏扫标记
    rm -f "$CURRENT_RUN_TIME_FILE"
    
    echo -e "${RED}❌ 错误: ZIP 打包失败！请检查磁盘剩余空间或目录权限。${NC}"
    exit 1
fi