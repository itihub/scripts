<#
.SYNOPSIS
    Windows 一键生成 Maven 全量/增量更新包 (智能时间戳标记法)
#>

# ================= 配置区 =================
# 【重要路径说明】
# 本脚本采用动态相对路径，自动将“脚本所在目录的上一级目录”作为基础工作空间。
#
# 为了保证脚本正常运行，请务必保持以下目录结构：
# 你的工作根目录 (如 maven_offline) /
#   ├── repository/         <-- 必须手动准备：将你外网全量的 Maven 仓库放在这里
#   ├── scripts/            <-- 必须手动准备：请将本脚本 (build_incremental.ps1) 放在这个文件夹内！
#   ├── incremental/        <-- 无需手动建：脚本运行时会自动生成并存放零散的增量文件
#   └── dist/               <-- 无需手动建：脚本运行时会自动生成并存放最终的 ZIP 压缩包
# =========================================

$BASE_PATH = Split-Path -Path $PSScriptRoot -Parent
$REPOSITORY_PATH = "$BASE_PATH\repository"
$INCREMENTAL_PATH = "$BASE_PATH\incremental"
$DIST_PATH = "$BASE_PATH\dist"
$TIMESTAMP_FILE = "$BASE_PATH\.last_build_time"
$CURRENT_RUN_TIME_FILE = "$BASE_PATH\.current_run_time"
# =========================================

Write-Host "开始提取 Maven 依赖..." -ForegroundColor Cyan

# 1. 检查源目录
if (-not (Test-Path $REPOSITORY_PATH)) {
    Write-Host "❌ 错误: 找不到 Maven 仓库源目录: $REPOSITORY_PATH" -ForegroundColor Red
    Write-Host "💡 提示: 请检查是否按规范将本脚本放入了 scripts/ 目录下，并且 repository/ 目录与 scripts/ 目录同级。" -ForegroundColor Yellow
    Pause
    Exit
}

# 2. 清理并重建相关目录
Remove-Item -Path $INCREMENTAL_PATH -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $INCREMENTAL_PATH -ItemType Directory -Force | Out-Null
if (-not (Test-Path $DIST_PATH)) {
    New-Item -Path $DIST_PATH -ItemType Directory -Force | Out-Null
}

# 记录本次任务开始的时间标记，作为下次的增量基准（防漏扫机制）
New-Item -Path $CURRENT_RUN_TIME_FILE -ItemType File -Force | Out-Null
$DATE = (Get-Item $CURRENT_RUN_TIME_FILE).LastWriteTime.ToString("yyyyMMdd_HHmmss")

# 3. 智能判断全量还是增量
if (Test-Path $TIMESTAMP_FILE) {
    Write-Host "检测到上次打包时间戳记录，正在提取新增量文件..." -ForegroundColor Yellow
    $RefTime = (Get-Item $TIMESTAMP_FILE).LastWriteTime
    $ChangedFiles = Get-ChildItem -Path $REPOSITORY_PATH -Recurse -File | Where-Object { $_.LastWriteTime -gt $RefTime }
    $PREFIX = "update"
} else {
    Write-Host "首次执行(无时间戳记录)，正在扫描所有依赖进行【全量打包】..." -ForegroundColor Yellow
    $ChangedFiles = Get-ChildItem -Path $REPOSITORY_PATH -Recurse -File
    $PREFIX = "full"
}

if ($null -eq $ChangedFiles -or $ChangedFiles.Count -eq 0) {
    Write-Host "🎉 完美！没有发现需要同步的新增/修改依赖文件。" -ForegroundColor Green
    Remove-Item $CURRENT_RUN_TIME_FILE -Force -ErrorAction SilentlyContinue
    Pause
    Exit
}

Write-Host "共发现 $($ChangedFiles.Count) 个变更文件，正在复制并保留目录结构..." -ForegroundColor Cyan

# 复制文件并动态保留相对目录结构
foreach ($file in $ChangedFiles) {
    $relativePath = $file.FullName.Substring($REPOSITORY_PATH.Length).TrimStart('\')
    $targetPath = Join-Path $INCREMENTAL_PATH $relativePath
    $targetDir = Split-Path $targetPath -Parent

    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Copy-Item -Path $file.FullName -Destination $targetPath -Force
}

# 清理无用的校验文件和 Maven 本地缓存标记文件
Write-Host "正在清理临时文件和缓存标记..." -ForegroundColor Yellow
$CleanExtensions = @("*.sha1", "*.md5", "*.lastUpdated", "_remote.repositories")
foreach ($ext in $CleanExtensions) {
    Get-ChildItem -Path $INCREMENTAL_PATH -Filter $ext -Recurse -File -ErrorAction SilentlyContinue | Remove-Item -Force
}

# 4. 打包 ZIP 包
$ZIP_FULL_PATH = "$DIST_PATH\${PREFIX}_${DATE}.zip"
Write-Host "正在打包生成 ZIP 文件..." -ForegroundColor Cyan
Compress-Archive -Path "$INCREMENTAL_PATH\*" -DestinationPath "$ZIP_FULL_PATH" -Force

# 5. 更新时间戳标记
# 将本次运行的基准时间重命名为上次打包时间，供下次使用
Move-Item -Path $CURRENT_RUN_TIME_FILE -Destination $TIMESTAMP_FILE -Force

Write-Host "✅ 打包成功：$ZIP_FULL_PATH" -ForegroundColor Green
Write-Host "请将此 ZIP 包传输至内网，并解压覆盖到内网的 repository 目录中。" -ForegroundColor Cyan

Pause