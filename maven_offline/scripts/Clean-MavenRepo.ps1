<#
.SYNOPSIS
    深度清理 Maven 本地仓库中的损坏文件（如 .lastUpdated）和离线屏障文件。
.DESCRIPTION
    采用底层过滤 API 提升扫描速度，并支持 -WhatIf (模拟运行) 和 -Verbose 机制。
.EXAMPLE
    .\Clean-MavenRepo.ps1
    使用默认的 ~/.m2/repository 路径进行清理。
.EXAMPLE
    .\Clean-MavenRepo.ps1 -Path "D:\maven_repo" -Verbose
    清理指定目录，并打印每一个被删除的具体文件路径。
.EXAMPLE
    .\Clean-MavenRepo.ps1 -WhatIf
    安全测试模式：只显示将要删除哪些文件，而不实际执行删除。
#>

# 1. 引入高级函数特性：支持安全风险拦截 (WhatIf/Confirm)
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param (
    [Parameter(Position=0, ValueFromPipeline=$true)]
    # 2. 前置防御：利用参数验证属性，路径不存在则脚本根本无法启动，无需手动写 if 报错
    [ValidateScript({
        if (-not (Test-Path -Path $_ -PathType Container)) {
            throw "指定的 Maven 仓库路径不存在: $_"
        }
        $true
    })]
    [string]$Path = (Join-Path $HOME ".m2\repository")
)

# 统一字符集，防止中文乱码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$TargetDir = (Resolve-Path -Path $Path).Path
Write-Host ">>> 开始扫描并清理 Maven 仓库: $TargetDir" -ForegroundColor Cyan

# 3. 性能优化：拆分规则
# 原理说明：Get-ChildItem 的 -Include 参数是在内存中进行二次过滤，性能极差。
# 而 -Filter 参数是直接下推到 Windows 底层文件系统 (NTFS) API 执行的，速度可提升 10 倍以上。
$TargetFilters = @("*.lastUpdated", "_remote.repositories")
$TotalRemoved = 0

$StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($Filter in $TargetFilters) {
    Write-Host "正在扫描特征文件: $Filter ..." -ForegroundColor DarkGray
    
    # 捕获所有目标文件 (由于使用了 -Filter，每次只能传一个字符串，因此用 foreach 循环)
    $TargetFiles = Get-ChildItem -Path $TargetDir -Filter $Filter -Recurse -File -Force -ErrorAction SilentlyContinue

    if ($null -ne $TargetFiles) {
        foreach ($File in $TargetFiles) {
            # 4. 安全机制：ShouldProcess
            # 这允许用户在调用脚本时加上 -WhatIf 参数来预览删除列表，而不会真实删除
            if ($PSCmdlet.ShouldProcess($File.FullName, "彻底删除冗余/损坏文件")) {
                try {
                    Remove-Item -Path $File.FullName -Force -ErrorAction Stop
                    $TotalRemoved++
                    # 5. 消除 IO 瓶颈：使用 Write-Verbose 替代原先的 Write-Host
                    # 如果有几千个文件，逐个 Write-Host 会导致控制台 IO 阻塞，严重拖慢脚本速度。
                    Write-Verbose "[成功] 已删除: $($File.Name)"
                } catch {
                    Write-Warning "文件删除失败: $($File.FullName) - $($_.Exception.Message)"
                }
            }
        }
    }
}

$StopWatch.Stop()

# 6. 标准化输出反馈
if ($TotalRemoved -gt 0) {
    Write-Host "✅ 清理完成！共移除了 $TotalRemoved 个文件。耗时: $($StopWatch.Elapsed.TotalSeconds.ToString('F2')) 秒。" -ForegroundColor Green
} else {
    Write-Host "🎉 仓库非常干净，未发现需要清理的损坏或冗余文件。" -ForegroundColor Green
}