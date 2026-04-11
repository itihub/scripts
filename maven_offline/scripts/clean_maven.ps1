<#
.SYNOPSIS
    深度清理 Maven 本地仓库中的损坏文件。
.DESCRIPTION
    删除指定的 .lastUpdated 和 _remote.repositories 文件，以解决离线打包时的依赖校验问题。
.PARAMETER Path
    指定 Maven 仓库的路径。默认为用户家目录下的 .m2\repository。
.EXAMPLE
    .\clean-maven.ps1
    # 不带参数运行：将使用默认路径 "$HOME\.m2\repository" 进行清理。
.EXAMPLE
    .\clean-maven.ps1 -Path "D:\maven_repo"
    # 指定路径运行：清理特定位置的仓库。
#>

param (
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Path = "$HOME\.m2\repository"
)

# 1. 路径验证
if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Error "[错误] 找不到路径: '$Path'，请确保路径正确且是一个目录。"
    exit 1
}

# 转换为绝对路径，确保输出信息清晰
$FullPath = (Resolve-Path -Path $Path).Path
Write-Host ">>> 开始清理 Maven 仓库: $FullPath" -ForegroundColor Cyan

# 2. 定义目标文件模式
$TargetPatterns = @("*.lastUpdated", "_remote.repositories")

# 3. 性能优化：合并搜索与删除
# 使用管道流式处理，减少内存占用。-ErrorAction SilentlyContinue 防止权限不足的文件夹报错。
Write-Host "正在扫描并执行清理..." -ForegroundColor Gray

try {
    Get-ChildItem -Path $FullPath -Include $TargetPatterns -Recurse -File -Force -ErrorAction SilentlyContinue | 
    ForEach-Object {
        $FileName = $_.Name
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Host " [OK] 已移除: $FileName" -ForegroundColor Gray
    }
}
catch {
    Write-Warning "清理过程中发生非致命错误: $($_.Exception.Message)"
}

# 4. 结束提示
Write-Host "`n>>> 清理完成！" -ForegroundColor Yellow