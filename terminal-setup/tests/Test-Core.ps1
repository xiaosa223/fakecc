# 仅使用可丢弃文件、虚构 token 和本机关闭的端口，不登录账号或安装软件。
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Core.ps1')
$script:Checks = 0
function Assert([bool]$Condition, [string]$Label) {
    if (-not $Condition) { throw ('FAIL: ' + $Label) }
    $script:Checks++
    Write-Host ('PASS: ' + $Label)
}
function Assert-Throws([scriptblock]$Action, [string]$Label) {
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    Assert $thrown $Label
}

$base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp = Join-Path $base ('claude-setup-test-' + [guid]::NewGuid().ToString('N'))
$savedEnv = @{}
$testEnvNames = @('ANTHROPIC_API_KEY','CLAUDE_CODE_OAUTH_TOKEN','HTTP_PROXY','HTTPS_PROXY','NO_PROXY','CLAUDE_CODE_USE_BEDROCK')
foreach ($name in $testEnvNames) { $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    Initialize-PrivateRoot $temp
    Assert (Test-Path -LiteralPath $temp) 'private state created'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $acl = Get-Acl -LiteralPath $temp
    Assert ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq $sid) 'new private root belongs to current user'
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    Assert ($acl.AreAccessRulesProtected -and $rules.Count -eq 1 -and $rules[0].IdentityReference.Value -eq $sid) 'exclusive current-user ACL'

    $textFile = Join-Path $temp 'write.json'
    Write-PrivateText $textFile '{"version":1}'
    Write-PrivateText $textFile '{"version":2}'
    Assert ((Get-Content -LiteralPath $textFile -Raw | ConvertFrom-Json).version -eq 2) 'atomic replacement preserves valid content'
    Assert (@(Get-ChildItem -LiteralPath $temp -Filter '*.tmp').Count -eq 0) 'temporary writes cleaned up'

    $secret = ConvertTo-SecureString 'fixture-only-long-lived-token-not-a-real-credential' -AsPlainText -Force
    try { Save-Token $temp $secret } finally { $secret.Dispose() }
    $cipher = Get-Content -LiteralPath (Join-Path $temp 'token.dpapi') -Raw
    Assert (-not $cipher.Contains('fixture-only')) 'token file contains no plaintext fixture'
    $restored = Read-Token $temp
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($restored)
        try { Assert ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) -eq 'fixture-only-long-lived-token-not-a-real-credential') 'DPAPI roundtrip under same user' }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    } finally { $restored.Dispose() }
    Assert-Throws { Save-Token $temp (New-Object Security.SecureString) } 'empty token rejected'

    Assert ((Get-ProxyUrl 'http://127.0.0.1:8080') -eq 'http://127.0.0.1:8080') 'IPv4 loopback proxy accepted'
    $ipv6Proxy = [uri](Get-ProxyUrl 'http://[::1]:8080')
    Assert ($ipv6Proxy.IsLoopback -and $ipv6Proxy.Port -eq 8080) 'IPv6 loopback proxy accepted'
    Assert ((Get-ProxyUrl 'http://localhost:8080/') -eq 'http://localhost:8080') 'localhost proxy normalized'
    foreach ($invalid in @('socks5://127.0.0.1:1080','http://example.com:8080','http://u:p@127.0.0.1:8080','http://127.0.0.1:8080/path','http://127.0.0.1:8080/?x=1','file:///C:/Windows','not-a-url')) {
        Assert-Throws { Get-ProxyUrl $invalid } 'unsupported or unsafe proxy rejected'
    }
    Assert ((Get-IPAddress '203.0.113.9') -eq '203.0.113.9') 'expected exit IP parsed'
    Assert-Throws { Get-IPAddress 'example.com' } 'hostname is not an expected exit IP'

    $delivery = Join-Path $temp 'delivery.json'
    Write-PrivateText $delivery '{"schemaVersion":1,"expectedExitIp":"203.0.113.9"}'
    Assert ((Get-Delivery $delivery).expectedExitIp -eq '203.0.113.9') 'provider exit loaded'
    Write-PrivateText $delivery '{"schemaVersion":999,"expectedExitIp":null}'
    Assert-Throws { Get-Delivery $delivery } 'unsupported delivery schema rejected'

    $settingsPath = Join-Path $temp 'settings.json'
    Write-PrivateText $settingsPath '{"env":{"ANTHROPIC_API_KEY":"fixture-do-not-print","ANTHROPIC_DEFAULT_SONNET_MODEL":"allowed-model"},"apiKeyHelper":"fixture-helper","permissions":{"allow":[]}}'
    $fileConflicts = @(Get-FileConflictNames @($settingsPath))
    Assert ($fileConflicts.Count -eq 2 -and ($fileConflicts -join ' ').Contains('ANTHROPIC_API_KEY')) 'auth config conflict detected; benign model kept'
    Assert (-not (($fileConflicts -join ' ').Contains('fixture-do-not-print'))) 'conflict output excludes secret values'
    $installArgs = @(Get-WinGetArguments 'Anthropic.ClaudeCode' 'local' 'http://127.0.0.1:8080' $true)
    Assert ($installArgs -contains '--proxy' -and $installArgs -contains 'http://127.0.0.1:8080') 'installation uses selected explicit proxy'
    Assert-Throws { Get-WinGetArguments 'Git.Git' 'local' 'http://127.0.0.1:8080' $false } 'unsupported installer proxy cannot silently go direct'
    Assert-Throws { Get-WinGetArguments 'Unknown.Package' 'tun' '' $true } 'package allowlist enforced'

    $fixtureExe = Join-Path $temp 'fixture.exe'
    Write-PrivateText $fixtureExe 'fixture; never executed'
    $config = [pscustomobject]@{schemaVersion=1;proxyMode='local';proxyUrl='http://127.0.0.1:8080';expectedExitIp=$null;observedExitIp='203.0.113.9';cliPath=$fixtureExe;gitBashPath=$fixtureExe;configuredAt='fixture'}
    Write-PrivateText (Join-Path $temp 'config.json') ($config | ConvertTo-Json)
    Assert ((Read-SetupConfig $temp).proxyUrl -eq $config.proxyUrl) 'valid config accepted'
    $config.proxyMode = 'unknown'
    Write-PrivateText (Join-Path $temp 'config.json') ($config | ConvertTo-Json)
    Assert-Throws { Read-SetupConfig $temp } 'invalid stored route rejected'
    $config.proxyMode = 'local'

    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', 'fixture-original', 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN', 'fixture-original-oauth', 'Process')
    [Environment]::SetEnvironmentVariable('HTTP_PROXY', 'http://127.0.0.1:9999', 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_USE_BEDROCK', '1', 'Process')
    $secret = Read-Token $temp
    try {
        Invoke-ClaudeEnvironment $config $secret {
            Assert ($env:HTTP_PROXY -eq 'http://127.0.0.1:8080') 'managed proxy applied to process'
            Assert (-not $env:ANTHROPIC_API_KEY -and -not $env:CLAUDE_CODE_USE_BEDROCK) 'conflicting auth mode cleared in child context'
            Assert ($env:CLAUDE_CODE_OAUTH_TOKEN -eq 'fixture-only-long-lived-token-not-a-real-credential') 'managed token injected'
            $childCode = 'if ($env:CLAUDE_CODE_OAUTH_TOKEN -eq "fixture-only-long-lived-token-not-a-real-credential" -and $env:HTTPS_PROXY -eq "http://127.0.0.1:8080") { "child-context-ok"; exit 7 }; exit 1'
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
            $child = & powershell.exe -NoProfile -EncodedCommand $encoded
            Assert ($child -eq 'child-context-ok' -and $LASTEXITCODE -eq 7) 'real child inherits token/proxy and exit code'
        }
        Assert ($env:ANTHROPIC_API_KEY -eq 'fixture-original' -and $env:HTTP_PROXY -eq 'http://127.0.0.1:9999' -and $env:CLAUDE_CODE_OAUTH_TOKEN -eq 'fixture-original-oauth') 'original process environment restored'
        Assert-Throws { Invoke-ClaudeEnvironment $config $secret { throw 'fixture failure' } } 'child failure propagated'
        Assert ($env:CLAUDE_CODE_OAUTH_TOKEN -eq 'fixture-original-oauth') 'environment restored after failure'
        $config.proxyMode = 'tun'
        Invoke-ClaudeEnvironment $config $secret { Assert (-not $env:HTTP_PROXY -and -not $env:HTTPS_PROXY) 'TUN probe context does not inherit explicit HTTP proxy' }
    } finally { $secret.Dispose() }

    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $closedPort = $listener.LocalEndpoint.Port
    $listener.Stop()
    Assert-Throws { Get-RouteObservation 'local' ('http://127.0.0.1:' + $closedPort) $null } 'dead local proxy fails; no direct retry'

    $desktop = Join-Path $temp 'desktop'
    New-Item -ItemType Directory -Path $desktop | Out-Null
    $packageRoot = Split-Path $PSScriptRoot -Parent
    $app = Install-Wizard $temp $packageRoot $desktop
    Assert ((Get-ChildItem -LiteralPath $desktop -Filter '*.lnk').Count -eq 3) 'three shortcuts created in isolated desktop'
    Assert (Test-Path -LiteralPath (Join-Path $app 'scripts\Core.ps1')) 'runtime copied outside original package'
    foreach ($link in Get-ChildItem -LiteralPath $desktop -Filter '*.lnk') {
        Assert ([ClaudeCodeSetup.Shortcuts]::ReadTarget($link.FullName).StartsWith($app)) 'Unicode shortcut points to managed runtime'
    }
    Install-Wizard $temp $packageRoot $desktop | Out-Null
    Assert ($true) 'reconfiguration can safely replace own runtime and shortcuts'

    Write-Host ('TOTAL: ' + $script:Checks + ' checks passed') -ForegroundColor Green
} finally {
    foreach ($name in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnv[$name], 'Process') }
    # 只清理本次自己创建、位于 TEMP 下的 GUID 目录。
    $resolved = [IO.Path]::GetFullPath($temp)
    if ($resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf) -match '^claude-setup-test-[a-f0-9]{32}$' -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
