param([switch]$Offline)
. (Join-Path $PSScriptRoot 'Core.ps1')
try {
    Write-Host 'Claude Code 环境检查（不显示 token、不发送模型请求）' -ForegroundColor Cyan
    $root = Get-SetupRoot
    $config = Read-SetupConfig $root
    Write-Host '本地配置：可读取'
    $secret = Read-Token $root
    $secret.Dispose()
    Write-Host 'token：当前 Windows 用户可解密；服务端有效性未知'
    $cli = $config.cliPath
    $version = & $cli --version 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Claude 版本检查失败。' }
    Write-Host ('Claude：' + ($version -join ' '))
    Write-Host ('网络方式：' + $config.proxyMode)
    if (-not $Offline) {
        $observed = Get-RouteObservation $config.proxyMode $config.proxyUrl $config.expectedExitIp
        Write-Host ('当前出口：' + $observed.ip)
        Write-Host ('预期出口匹配：' + $(if ($observed.expectedMatched) { '通过' } else { '未配置预期值，未核验' }))
    } else { Write-Host '出口检测：本次离线跳过' }
    $conflicts = @(Get-ConflictNames)
    if ($conflicts.Count) {
        Write-Host '既有配置字段（未改写）：' -ForegroundColor Yellow
        $conflicts | ForEach-Object { Write-Host ('  ' + $_) }
    }
    Write-Host '未覆盖：Claude 服务端鉴权、模型调用、独立 DNS 泄漏、运行中断网阻断、项目/MCP/工具各自路由。'
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
