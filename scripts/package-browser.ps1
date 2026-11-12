# [INPUT]: Windows Chromium 引擎。
# [OUTPUT]: 验证 Windows 引擎与版本元数据。
# [POS]: Windows 构建前置检查，不包含 SSH、资料读取或部署。
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root
$stagedUi = [IO.Path]::GetFullPath((Join-Path $root 'src-tauri\target\release\browser-ui'))
$expectedBuildRoot = [IO.Path]::GetFullPath((Join-Path $root 'src-tauri\target\release')) + '\'
if (-not $stagedUi.StartsWith($expectedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected generated resource path' }
if (Test-Path -LiteralPath $stagedUi) {
    if ((Get-Item -LiteralPath $stagedUi -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Generated UI must not be a junction' }
    foreach ($staleFile in Get-ChildItem -LiteralPath $stagedUi -File -Recurse) {
        $relative = $staleFile.FullName.Substring($stagedUi.Length).TrimStart('\')
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $root 'dist') $relative) -PathType Leaf)) {
            Remove-Item -LiteralPath $staleFile.FullName -Force
        }
    }
}
if (-not (Test-Path "browser-runtime\WindowsBrowser\chrome.exe")) {
    python scripts/fetch-browser.py
}
$v1 = (Get-Content "browser-runtime\WindowsBrowser\version.txt").Trim()
$v2 = (Get-Content "browser-runtime\version.txt").Trim()
if ($v1 -ne $v2) {
    throw "Engine version mismatch: $v1 vs $v2"
}
Write-Output "Windows browser engine package verified."
