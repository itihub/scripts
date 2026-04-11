<#
.SYNOPSIS
    Windows 一键生成 Maven 全量/增量更新包
#>
[CmdletBinding()]
param()

# 统一字符集并设置严格的错误处理模式
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

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
$BasePath = Split-Path -Path $PSScriptRoot -Parent
$RepositoryPath = Join-Path $BasePath "repository"
$IncrementalPath = Join-Path $BasePath "incremental"
$DistPath = Join-Path $BasePath "dist"
$TimestampFile = Join-Path $BasePath ".last_build_time"
$CurrentRunTimeFile = Join-Path $BasePath ".current_run_time"

Write-Host "开始提取 Maven 依赖..." -ForegroundColor Cyan

if (-not (Test-Path $RepositoryPath)) {
    Write-Error "找不到 Maven 仓库源目录: $RepositoryPath"
    Exit
}

# 记录运行时状态标志
$isSuccess = $false

try {
    # 建立工作区
    if (Test-Path $IncrementalPath) { Remove-Item -Path $IncrementalPath -Recurse -Force }
    New-Item -Path $IncrementalPath -ItemType Directory -Force | Out-Null
    if (-not (Test-Path $DistPath)) { New-Item -Path $DistPath -ItemType Directory -Force | Out-Null }

    New-Item -Path $CurrentRunTimeFile -ItemType File -Force | Out-Null
    $runDate = (Get-Item $CurrentRunTimeFile).LastWriteTime.ToString("yyyyMMdd_HHmmss")

    # 增量扫描逻辑
    if (Test-Path $TimestampFile) {
        Write-Host "检测到时间戳记录，提取新增量文件..." -ForegroundColor Yellow
        $refTime = (Get-Item $TimestampFile).LastWriteTime
        $changedFiles = Get-ChildItem -Path $RepositoryPath -Recurse -File | Where-Object { $_.LastWriteTime -gt $refTime }
        $prefix = "update"
    } else {
        Write-Host "首次执行，进行【全量打包】..." -ForegroundColor Yellow
        $changedFiles = Get-ChildItem -Path $RepositoryPath -Recurse -File
        $prefix = "full"
    }

    if (-not $changedFiles) {
        Write-Host "🎉 完美！没有发现需要同步的新增/修改依赖文件。" -ForegroundColor Green
        return
    }

    Write-Host "共发现 $($changedFiles.Count) 个变更文件，正在复制..." -ForegroundColor Cyan
    foreach ($file in $changedFiles) {
        $relativePath = $file.FullName.Substring($RepositoryPath.Length).TrimStart('\')
        $targetPath = Join-Path $IncrementalPath $relativePath
        $targetDir = Split-Path $targetPath -Parent

        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item -Path $file.FullName -Destination $targetPath -Force
    }

    # 清理无用文件
    $cleanExtensions = @("*.sha1", "*.md5", "*.lastUpdated", "_remote.repositories")
    foreach ($ext in $cleanExtensions) {
        Get-ChildItem -Path $IncrementalPath -Filter $ext -Recurse -File -ErrorAction Ignore | Remove-Item -Force
    }

    $validFiles = Get-ChildItem -Path $IncrementalPath -Recurse -File
    if (-not $validFiles) {
        Write-Host "🎉 清理冗余文件后，没有需要打包的依赖。" -ForegroundColor Green
        return
    }

    # 压缩打包
    $zipFullPath = Join-Path $DistPath "${prefix}_${runDate}.zip"
    Write-Host "正在生成 ZIP 文件..." -ForegroundColor Cyan
    Compress-Archive -Path "$IncrementalPath\*" -DestinationPath $zipFullPath -Force

    # 标记成功并更新时间戳
    $isSuccess = $true
    Move-Item -Path $CurrentRunTimeFile -Destination $TimestampFile -Force
    Write-Host "✅ 打包成功：$zipFullPath" -ForegroundColor Green

} catch {
    Write-Host "❌ 执行过程中发生错误: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Guaranteed Cleanup 机制
    Write-Host "🧹 执行资源清理..." -ForegroundColor Yellow
    if (Test-Path $IncrementalPath) { Remove-Item -Path $IncrementalPath -Recurse -Force }
    if (-not $isSuccess -and (Test-Path $CurrentRunTimeFile)) {
        Remove-Item -Path $CurrentRunTimeFile -Force
    }
}