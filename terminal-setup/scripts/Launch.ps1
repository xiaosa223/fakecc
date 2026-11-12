param([string]$ProjectDirectory, [Parameter(ValueFromRemainingArguments = $true)][string[]]$ClaudeArguments)
. (Join-Path $PSScriptRoot 'Core.ps1')
try {
    $root = Get-SetupRoot
    $config = Read-SetupConfig $root
    Write-Host '正在检查本次启动的网络路径……'
    $observed = Get-RouteObservation $config.proxyMode $config.proxyUrl $config.expectedExitIp
    Write-Host ('当前出口：' + $observed.ip)
    if (-not $observed.expectedMatched) { Write-Host '未配置提供者预期出口，仅确认当前检测请求可联网。' -ForegroundColor Yellow }
    if (-not $ProjectDirectory) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object Windows.Forms.FolderBrowserDialog
        try {
            $dialog.Description = '请选择本次 Claude Code 要使用的项目文件夹'
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 0 }
            $ProjectDirectory = $dialog.SelectedPath
        } finally { $dialog.Dispose() }
    }
    if (-not (Test-Path -LiteralPath $ProjectDirectory -PathType Container)) { throw '项目文件夹不存在。' }
    $conflicts = @(Get-ConflictNames $ProjectDirectory)
    if ($conflicts.Count) {
        Write-Host '检测到既有配置，可能影响实际认证或路由；请检查 CLI 显示的账号与模式。' -ForegroundColor Yellow
        $conflicts | ForEach-Object { Write-Host ('  ' + $_) }
        if (@($conflicts | Where-Object { $_ -match ':env\.|:apiKeyHelper$|:无法读取或解析$' }).Count) {
            throw '发现可能覆盖本次认证/代理的配置文件，已停止；请先处理列出的字段。'
        }
    }
    $secret = Read-Token $root
    $cli = $config.cliPath
    Push-Location -LiteralPath $ProjectDirectory
    try {
        Invoke-ClaudeEnvironment $config $secret { & $cli @ClaudeArguments; $script:ClaudeExit = $LASTEXITCODE }
    } finally { Pop-Location; $secret.Dispose() }
    exit $script:ClaudeExit
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host '未继续启动。请运行「检查 Claude 环境」或「重新配置 Claude」。'
    exit 1
}
