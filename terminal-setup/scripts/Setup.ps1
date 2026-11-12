. (Join-Path $PSScriptRoot 'Core.ps1')

function Confirm([string]$Message) { return (Read-Host ($Message + ' [y/N]')) -match '^(y|yes)$' }
function Wait-Step([string]$Title, [scriptblock]$Action) {
    while ($true) {
        Write-Host ("`n" + $Title) -ForegroundColor Cyan
        try { return & $Action } catch {
            Write-Host $_.Exception.Message -ForegroundColor Yellow
            if (-not (Confirm '修好后重试这一步？')) { throw '配置已停止。再次运行可重新检查；已有 token 不会自动删除。' }
        }
    }
}

try {
    Write-Host 'Claude Code Windows 配置向导（预览版）' -ForegroundColor Cyan
    Write-Host '共 6 步。请保留窗口；不会修改系统代理、系统时区或全局环境变量。'
    $root = Get-SetupRoot
    $package = Split-Path $PSScriptRoot -Parent
    $delivery = Get-Delivery (Join-Path $package 'delivery.json')

    Wait-Step '1/6 检查并准备程序' {
        if (Get-GitBashPath) { Write-Host 'Git Bash：已找到。' }
        else { Write-Host 'Git Bash：未找到，网络测通后再准备。' }
        $existing = Get-ClaudePath
        if ($existing) { Write-Host 'Claude Code：已找到原生程序，稍后验证版本。' }
        else { Write-Host 'Claude Code：尚未找到原生程序，网络测通后安装。' }
        $conflicts = @(Get-ConflictNames)
        if ($conflicts.Count) {
            Write-Host '发现既有认证/代理配置；只列字段名：' -ForegroundColor Yellow
            $conflicts | ForEach-Object { Write-Host ('  ' + $_) }
            Write-Host '已有 settings.json / 自定义配置目录可能影响运行。本版不自动改写，请先处理冲突。'
            if (@($conflicts | Where-Object { $_ -match ':env\.|:apiKeyHelper$|:无法读取或解析$' }).Count) {
                throw '已有文件中的认证/代理字段会覆盖本次设置。请将字段名提供给维护者处理，勿发送 token 内容。'
            }
            if (-not (Confirm '已理解，将在最终测试中核实使用本次 token 和线路？')) { throw '请先处理既有配置后继续。' }
        }
    } | Out-Null

    Wait-Step '2/6 导入并打开线路' {
        Write-Host '打开你的代理客户端，在「订阅 / 配置」中导入线路提供者给的订阅或配置文件。'
        Write-Host '选择提供的节点并连接。已有线路可直接使用；本配置包不包含 VPS 凭据或订阅。'
        Write-Host '下一步会自动检测本机代理候选，也支持已经开启的 TUN 模式。'
        if (-not (Confirm '线路已导入、客户端保持运行，并已选择节点？')) { throw '请先完成导入与连接。' }
    } | Out-Null

    $network = Wait-Step '3/6 设置终端网络并实测' {
        $candidate = Get-ProxyCandidate
        Write-Host '1：使用代理客户端的本机 HTTP / 混合端口（仅用于本启动器）'
        Write-Host '2：已开启 TUN，由虚拟网卡接管终端流量'
        $choice = Read-Host '请选择 1 或 2'
        $proxy = $null
        if ($choice -eq '1') {
            if ($candidate) { Write-Host ('检测到候选：' + $candidate) }
            $value = Read-Host '输入 HTTP/混合代理地址，候选正确时直接回车；不要填 SOCKS 端口'
            if (-not $value) { $value = $candidate }
            $proxy = Get-ProxyUrl $value
            $mode = 'local'
        } elseif ($choice -eq '2') { $mode = 'tun' }
        else { throw '请选择 1 或 2。' }
        Write-Host '正在通过所选路径请求 api.ipify.org，检查出口……'
        $observed = Get-RouteObservation $mode $proxy $delivery.expectedExitIp
        Write-Host ('实际出口：' + $observed.ip)
        if ($observed.expectedMatched) { Write-Host '与线路提供者预设出口一致。' -ForegroundColor Green }
        else { Write-Host '提供者未预设出口；目前只确认该路径可联网，不能确认这是预期线路。' -ForegroundColor Yellow }
        if (-not (Confirm '确认使用上述网络配置？')) { throw '请重新选择网络方式。' }
        return [pscustomobject]@{ proxyMode = $mode; proxyUrl = $proxy; observedExitIp = $observed.ip; expectedExitIp = $delivery.expectedExitIp }
    }

    $cli = Wait-Step '4/6 安装或验证官方 Claude Code' {
        if (-not (Get-GitBashPath)) {
            if (-not (Confirm '通过 WinGet 安装 Git for Windows？安装器可能请求管理员权限')) { throw '需要 Git for Windows 后才能继续。' }
            Install-OfficialPackage 'Git.Git' $network.proxyMode $network.proxyUrl
            if (-not (Get-GitBashPath)) { throw '未能定位 Git Bash，请检查安装结果后重试。' }
        }
        $path = Get-ClaudePath
        if (-not $path) {
            if (-not (Confirm '通过 WinGet 安装 Anthropic.ClaudeCode 官方原生客户端？')) { throw '需要 Claude Code 原生客户端。' }
            Install-OfficialPackage 'Anthropic.ClaudeCode' $network.proxyMode $network.proxyUrl
            $path = Get-ClaudePath
        }
        if (-not $path) { throw '安装后仍未找到 Claude 原生程序。' }
        $version = & $path --version 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $version) { throw 'Claude 版本检查失败。' }
        Write-Host ('Claude Code：' + ($version -join ' '))
        return $path
    }

    $config = [pscustomobject]@{
        schemaVersion = 1; proxyMode = $network.proxyMode; proxyUrl = $network.proxyUrl
        expectedExitIp = $network.expectedExitIp; observedExitIp = $network.observedExitIp
        cliPath = $cli; gitBashPath = Get-GitBashPath; configuredAt = [DateTime]::UtcNow.ToString('o')
    }
    Wait-Step '5/6 配置长期 token' {
        Write-Host '1：已有 setup-token 生成的长期 token，直接安全输入'
        Write-Host '2：在本机运行官方 claude setup-token，按浏览器指引授权后输入'
        $hasSaved = Test-Path -LiteralPath (Join-Path $root 'token.dpapi')
        if ($hasSaved) { Write-Host '3：保留本向导已经加密保存的 token' }
        $choice = Read-Host '请选择'
        if ($choice -eq '3' -and $hasSaved) {
            $savedToken = Read-Token $root
            $savedToken.Dispose()
            return
        }
        if ($choice -eq '2') {
            Write-Host '官方命令可能在本机终端显示 token；不要截图或发给他人。此向导不记录其输出。'
            Invoke-ClaudeEnvironment $config $null { & $cli setup-token | Out-Host }
            if ($LASTEXITCODE -ne 0) { throw '官方 token 授权未成功完成。' }
        } elseif ($choice -ne '1') { throw '请选择有效选项。' }
        $secret = Read-Host '粘贴长期 token（输入不显示，右键或 Ctrl+V）' -AsSecureString
        try {
            Initialize-PrivateRoot $root
            Save-Token $root $secret
            $check = Read-Token $root
            $check.Dispose()
        } finally { $secret.Dispose() }
        Write-Host '已使用 Windows 当前用户加密保存；未验证服务端认证。' -ForegroundColor Green
    } | Out-Null

    Wait-Step '6/6 保存配置与日常入口' {
        Initialize-PrivateRoot $root
        Write-PrivateText (Join-Path $root 'config.json') ($config | ConvertTo-Json)
        $installed = Install-Wizard $root $package
        Write-Host '桌面已生成「启动 Claude Code」「检查 Claude 环境」「重新配置 Claude」。'
        Write-Host ('应用目录：' + $installed)
        Write-Host '完成本地配置。首次启动后，需在官方 CLI 内确认账号、模型与实际请求。' -ForegroundColor Green
        Write-Host '本向导未发送模型请求；网络观测不代表账号已被服务器接受。'
    } | Out-Null
    Read-Host '按回车结束' | Out-Null
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
