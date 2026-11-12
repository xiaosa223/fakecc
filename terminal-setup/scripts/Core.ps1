# Windows PowerShell 5.1 / PowerShell 7. 本文件只定义函数，加载时不写入配置。
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SetupRoot {
    if (-not $env:LOCALAPPDATA) { throw '无法确定当前用户的本地应用数据目录。' }
    return Join-Path $env:LOCALAPPDATA 'ClaudeCodeSetup'
}

function Assert-PlainDirectory([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw '配置目录不能是文件、符号链接或目录联接。'
    }
}

function Set-PrivateAcl([string]$Path) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '拒绝向链接写入配置。' }
    $existing = Get-Acl -LiteralPath $Path
    if ($existing.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) {
        throw '配置文件不属于当前 Windows 用户，已停止；不会接管其他用户的文件。'
    }
    $rules = @($existing.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if ($existing.AreAccessRulesProtected -and $rules.Count -eq 1 -and
        $rules[0].IdentityReference.Value -eq $sid.Value -and
        $rules[0].AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
        ($rules[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl) {
        return
    }
    if ($item.PSIsContainer) {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    } else {
        $acl = New-Object Security.AccessControl.FileSecurity
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')
    }
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
    $confirmed = Get-Acl -LiteralPath $Path
    $confirmedRules = @($confirmed.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if (-not $confirmed.AreAccessRulesProtected -or $confirmedRules.Count -ne 1 -or
        $confirmedRules[0].IdentityReference.Value -ne $sid.Value) { throw '未能核验私密文件权限。' }
}

function Initialize-PrivateRoot([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root)) {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $security = New-Object Security.AccessControl.DirectorySecurity
        $security.SetOwner($sid)
        $security.SetAccessRuleProtection($true, $false)
        $security.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        if ($PSVersionTable.PSEdition -eq 'Core') {
            [IO.FileSystemAclExtensions]::CreateDirectory($security, $Root) | Out-Null
        } else {
            [IO.Directory]::CreateDirectory($Root, $security) | Out-Null
        }
    }
    Assert-PlainDirectory $Root
    Set-PrivateAcl $Root
}

function Write-PrivateText([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    Assert-PlainDirectory $parent
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw '拒绝覆盖目录或链接。'
        }
    }
    $temp = Join-Path $parent ([guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $security = New-Object Security.AccessControl.FileSecurity
        $security.SetOwner($sid)
        $security.SetAccessRuleProtection($true, $false)
        $security.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')))
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $stream = [IO.FileSystemAclExtensions]::Create((New-Object IO.FileInfo($temp)), [IO.FileMode]::CreateNew, [Security.AccessControl.FileSystemRights]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough, $security)
        } else {
            $stream = New-Object IO.FileStream($temp, [IO.FileMode]::CreateNew, [Security.AccessControl.FileSystemRights]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough, $security)
        }
        try {
            $encoding = New-Object Text.UTF8Encoding($true)
            [byte[]]$bytes = $encoding.GetPreamble() + $encoding.GetBytes($Text)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        Set-PrivateAcl $temp
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($temp, $Path, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [IO.File]::Move($temp, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Get-ProxyUrl([string]$Value) {
    $uri = $null
    if (-not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) { throw '代理地址格式不正确。' }
    if ($uri.Scheme -ne 'http' -or -not $uri.IsLoopback -or $uri.UserInfo -or
        $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment -or $uri.Port -lt 1) {
        throw '此版本只支持本机无密码 HTTP/混合代理端口，例如 http://127.0.0.1:端口。'
    }
    return $uri.GetLeftPart([UriPartial]::Authority)
}

function Get-ProxyCandidate {
    # 只把现有配置作为候选，不推断端口，不扫描网络，也不显示可能存在的账号密码。
    foreach ($name in @('HTTPS_PROXY', 'HTTP_PROXY', 'https_proxy', 'http_proxy')) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ($value) { try { return Get-ProxyUrl $value } catch { } }
    }
    try {
        $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        if ($settings.ProxyEnable -eq 1 -and $settings.ProxyServer) {
            $server = [string]$settings.ProxyServer
            if ($server -match '(?:^|;)https?=([^;]+)') { $server = $Matches[1] }
            if ($server -notmatch '^[a-z]+://') { $server = 'http://' + $server }
            return Get-ProxyUrl $server
        }
    } catch { }
    return $null
}

function Get-IPAddress([string]$Value) {
    $address = $null
    if (-not [Net.IPAddress]::TryParse($Value, [ref]$address)) { throw '出口地址不是有效的 IP。' }
    return $address.ToString()
}

function Get-Delivery([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @{ expectedExitIp = $null } }
    if ((Get-Item -LiteralPath $Path).Length -gt 16384) { throw '线路说明文件过大。' }
    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($data.schemaVersion -ne 1) { throw '不支持的线路说明文件版本。' }
    $expected = $null
    if ($data.expectedExitIp) { $expected = Get-IPAddress ([string]$data.expectedExitIp) }
    return @{ expectedExitIp = $expected }
}

function Get-RouteObservation([string]$Mode, [string]$ProxyUrl, [string]$ExpectedExitIp) {
    if ($Mode -notin @('local', 'tun')) { throw '未知网络模式。' }
    $request = [Net.HttpWebRequest]::Create('https://api.ipify.org?format=json')
    $request.Timeout = 12000
    $request.ReadWriteTimeout = 12000
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'ClaudeCodeSetup/0.1'
    $request.Proxy = $null
    if ($Mode -eq 'local') { $request.Proxy = New-Object Net.WebProxy((Get-ProxyUrl $ProxyUrl)) }
    $response = $null
    $reader = $null
    try {
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200 -or $response.ContentLength -gt 1024) { throw 'Invalid response' }
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        $buffer = New-Object char[] 1025
        $count = $reader.ReadBlock($buffer, 0, $buffer.Length)
        if ($count -gt 1024) { throw 'Invalid response' }
        $body = -join $buffer[0..($count - 1)]
        $ip = Get-IPAddress ([string](ConvertFrom-Json $body).ip)
    } catch {
        throw '当前网络路径未能取得有效出口。请检查代理客户端、端口、TUN 和线路后重试。'
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($response) { $response.Dispose() }
    }
    if ($ExpectedExitIp -and $ip -ne (Get-IPAddress $ExpectedExitIp)) {
        throw ('出口不符合线路提供者的预期，已停止。实际出口：' + $ip)
    }
    return [pscustomobject]@{ ip = $ip; expectedMatched = [bool]$ExpectedExitIp; checkedAt = [DateTime]::UtcNow.ToString('o') }
}

function Get-ClaudePath {
    $paths = @((Join-Path $env:USERPROFILE '.local\bin\claude.exe'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\claude.exe'))
    $command = Get-Command claude.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $paths = @($command.Source) + $paths }
    foreach ($path in $paths) { if (Test-Path -LiteralPath $path -PathType Leaf) { return $path } }
    return $null
}

function Get-GitBashPath {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $candidates.Add($env:CLAUDE_CODE_GIT_BASH_PATH) }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if ($base) { $candidates.Add((Join-Path $base 'Git\bin\bash.exe')) }
    }
    $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) { $candidates.Add((Join-Path (Split-Path (Split-Path $git.Source -Parent) -Parent) 'bin\bash.exe')) }
    foreach ($path in $candidates) { if (Test-Path -LiteralPath $path -PathType Leaf) { return $path } }
    return $null
}

function Get-FileConflictNames([string[]]$Paths) {
    foreach ($homeConfig in @($Paths | Select-Object -Unique)) {
      if (Test-Path -LiteralPath $homeConfig) {
        try {
            $settings = Get-Content -LiteralPath $homeConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($settings.PSObject.Properties['env'] -and $settings.env) {
                foreach ($property in $settings.env.PSObject.Properties) {
                    if ($property.Name -match '^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_BASE_URL|CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_VERTEX|CLAUDE_CODE_USE_FOUNDRY|HTTPS?_PROXY|ALL_PROXY|NO_PROXY)$') {
                        $homeConfig + ':env.' + $property.Name
                    }
                }
            }
            if ($settings.PSObject.Properties['apiKeyHelper']) { $homeConfig + ':apiKeyHelper' }
        } catch { $homeConfig + ':无法读取或解析' }
      }
    }
}

function Get-ConflictNames([string]$ProjectDirectory) {
    foreach ($name in @('ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL', 'CLAUDE_CODE_OAUTH_TOKEN', 'CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_USE_BEDROCK', 'CLAUDE_CODE_USE_VERTEX', 'CLAUDE_CODE_USE_FOUNDRY')) {
        if ([Environment]::GetEnvironmentVariable($name, 'Process')) { $name }
    }
    $files = @((Join-Path $env:USERPROFILE '.claude\settings.json'))
    if ($env:CLAUDE_CONFIG_DIR) { $files += Join-Path $env:CLAUDE_CONFIG_DIR 'settings.json' }
    if ($ProjectDirectory) {
        $files += Join-Path $ProjectDirectory '.claude\settings.json'
        $files += Join-Path $ProjectDirectory '.claude\settings.local.json'
    }
    Get-FileConflictNames $files
}

function Get-WinGetArguments([string]$Id, [string]$Mode, [string]$ProxyUrl, [bool]$SupportsProxy) {
    if ($Id -notin @('Git.Git', 'Anthropic.ClaudeCode')) { throw '未批准的软件标识。' }
    if ($Mode -notin @('local', 'tun')) { throw '未知网络模式。' }
    $arguments = @('install', '--id', $Id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($Id -eq 'Anthropic.ClaudeCode') { $arguments += @('--scope', 'user') }
    if ($Mode -eq 'local') {
        if (-not $SupportsProxy) { throw '当前 WinGet 不支持指定代理。请更新 Microsoft Store 的「应用安装程序」，或开启 TUN 后返回上一步重选网络。' }
        $arguments += @('--proxy', (Get-ProxyUrl $ProxyUrl))
    }
    return $arguments
}

function Install-OfficialPackage([string]$Id, [string]$Mode, [string]$ProxyUrl) {
    $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $winget) { throw '未找到 WinGet。请在 Microsoft Store 安装或更新「应用安装程序」，再重试。' }
    $help = (& $winget.Source install --help 2>$null) -join "`n"
    $arguments = @(Get-WinGetArguments $Id $Mode $ProxyUrl ($help -match '--proxy'))
    & $winget.Source @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'WinGet 安装未成功，请检查上述安装提示后重试。' }
}

function Save-Token([string]$Root, [Security.SecureString]$Token) {
    if ($Token.Length -eq 0) { throw 'token 不能为空。' }
    $ciphertext = ConvertFrom-SecureString -SecureString $Token
    Write-PrivateText (Join-Path $Root 'token.dpapi') $ciphertext
}

function Read-Token([string]$Root) {
    Assert-PlainDirectory $Root
    $path = Join-Path $Root 'token.dpapi'
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 65536) {
        throw 'token 文件无效。'
    }
    try { return ConvertTo-SecureString (Get-Content -LiteralPath $path -Raw -Encoding UTF8) }
    catch { throw '无法解密 token。请使用原 Windows 用户，或重新配置 token。' }
}

function Read-SetupConfig([string]$Root) {
    Assert-PlainDirectory $Root
    $path = Join-Path $Root 'config.json'
    $file = Get-Item -LiteralPath $path -Force
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 16384) { throw '配置文件无效。' }
    $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.schemaVersion -ne 1 -or $config.proxyMode -notin @('local', 'tun')) { throw '配置版本或网络模式无效。' }
    if ($config.proxyMode -eq 'local') { $config.proxyUrl = Get-ProxyUrl ([string]$config.proxyUrl) }
    if ($config.expectedExitIp) { $config.expectedExitIp = Get-IPAddress ([string]$config.expectedExitIp) }
    if (-not [IO.Path]::IsPathRooted($config.cliPath) -or [IO.Path]::GetExtension($config.cliPath) -ne '.exe' -or
        -not (Test-Path -LiteralPath $config.cliPath -PathType Leaf)) { throw '官方 Claude 原生程序已移动或不存在，请重新配置。' }
    if (-not (Test-Path -LiteralPath $config.gitBashPath -PathType Leaf)) { throw 'Git Bash 已移动或不存在，请重新配置。' }
    return $config
}

function Invoke-ClaudeEnvironment($Config, [Security.SecureString]$Token, [scriptblock]$Action) {
    $names = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN',
        'ANTHROPIC_BASE_URL', 'CLAUDE_CODE_OAUTH_TOKEN', 'CLAUDE_CODE_GIT_BASH_PATH',
        'CLAUDE_CODE_USE_BEDROCK', 'CLAUDE_CODE_USE_VERTEX', 'CLAUDE_CODE_USE_FOUNDRY')
    $saved = @{}
    $pointer = [IntPtr]::Zero
    try {
        foreach ($name in $names) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
        if ($Config.proxyMode -eq 'local') {
            $proxy = Get-ProxyUrl ([string]$Config.proxyUrl)
            [Environment]::SetEnvironmentVariable('HTTP_PROXY', $proxy, 'Process')
            [Environment]::SetEnvironmentVariable('HTTPS_PROXY', $proxy, 'Process')
        }
        [Environment]::SetEnvironmentVariable('NO_PROXY', 'localhost,127.0.0.1,::1', 'Process')
        [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $Config.gitBashPath, 'Process')
        if ($null -ne $Token) {
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
            [Environment]::SetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN', [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer), 'Process')
        }
        & $Action
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
}

function Initialize-ShortcutApi {
    if ('ClaudeCodeSetup.Shortcuts' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
namespace ClaudeCodeSetup {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLinkObject { }
    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
    internal interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count, IntPtr findData, uint flags);
        void GetIDList(out IntPtr list);
        void SetIDList(IntPtr list);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text, int count);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string path);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder arguments, int count);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
        void GetHotkey(out short hotkey);
        void SetHotkey(short hotkey);
        void GetShowCmd(out int command);
        void SetShowCmd(int command);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }
    public static class Shortcuts {
        public static string ReadTarget(string path) {
            object link = new ShellLinkObject();
            try {
                ((IPersistFile)link).Load(path, 0);
                var target = new StringBuilder(32768);
                ((IShellLinkW)link).GetPath(target, target.Capacity, IntPtr.Zero, 4);
                return target.ToString();
            } finally { Marshal.FinalReleaseComObject(link); }
        }
        public static void Save(string path, string target, string workingDirectory) {
            if (File.Exists(path) && !String.Equals(ReadTarget(path), target, StringComparison.OrdinalIgnoreCase))
                throw new IOException("A shortcut with a different target already exists; it was preserved.");
            object link = new ShellLinkObject();
            try {
                ((IShellLinkW)link).SetPath(target);
                ((IShellLinkW)link).SetWorkingDirectory(workingDirectory);
                ((IPersistFile)link).Save(path, true);
            } finally { Marshal.FinalReleaseComObject(link); }
        }
    }
}
'@
}

function Install-Wizard([string]$Root, [string]$PackageRoot, [string]$DesktopPath) {
    Initialize-PrivateRoot $Root
    $app = Join-Path $Root 'app'
    Initialize-PrivateRoot $app
    $scripts = Join-Path $app 'scripts'
    Initialize-PrivateRoot $scripts
    foreach ($name in @('Core.ps1', 'Setup.ps1', 'Launch.ps1', 'Doctor.ps1')) {
        $source = Join-Path (Join-Path $PackageRoot 'scripts') $name
        $target = Join-Path $scripts $name
        if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) {
            Write-PrivateText $target ([IO.File]::ReadAllText($source))
        }
    }
    foreach ($name in @('Configure.cmd', 'StartClaude.cmd', 'CheckEnvironment.cmd')) {
        Write-PrivateText (Join-Path $app $name) ([IO.File]::ReadAllText((Join-Path $PackageRoot $name)))
    }
    $delivery = Join-Path $PackageRoot 'delivery.json'
    if (Test-Path -LiteralPath $delivery) {
        Get-Delivery $delivery | Out-Null
        Write-PrivateText (Join-Path $app 'delivery.json') ([IO.File]::ReadAllText($delivery))
    }
    $desktop = $DesktopPath
    if (-not $desktop) { $desktop = [Environment]::GetFolderPath('Desktop') }
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { throw '无法找到桌面，配置已保存；可以从应用目录启动。' }
    Initialize-ShortcutApi
    foreach ($entry in @(@('启动 Claude Code.lnk', 'StartClaude.cmd'), @('检查 Claude 环境.lnk', 'CheckEnvironment.cmd'), @('重新配置 Claude.lnk', 'Configure.cmd'))) {
        $linkPath = Join-Path $desktop $entry[0]
        [ClaudeCodeSetup.Shortcuts]::Save($linkPath, (Join-Path $app $entry[1]), $env:USERPROFILE)
    }
    return $app
}
