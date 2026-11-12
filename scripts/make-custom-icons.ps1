# [INPUT]: assets/claude-in-hand*.svg 与锁定的 Tauri CLI。
# [OUTPUT]: A/B 的 PNG、ICO、ICNS；构建过程不改写浏览器引擎。
# [POS]: 本地定制图标的跨平台容器生成入口；临时目录仅含本脚本生成的文件。
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$iconWork = Join-Path ([IO.Path]::GetTempPath()) ('ccbaga-icons-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $iconWork | Out-Null
Push-Location $projectRoot
try {
    foreach ($variant in @('app', 'browser')) {
        $source = if ($variant -eq 'app') { 'assets/claude-in-hand.svg' } else { 'assets/claude-in-hand-browser.svg' }
        $generated = Join-Path $iconWork $variant
        & bun run tauri icon $source --output $generated
        if ($LASTEXITCODE -ne 0) { throw "Tauri icon generation failed: $variant" }
        $destination = if ($variant -eq 'app') { 'src-tauri/icons' } else { 'browser-runtime/icons' }
        Copy-Item -LiteralPath (Join-Path $generated 'icon.png') -Destination (Join-Path $destination 'icon.png')
        $ico = if ($variant -eq 'app') { 'icon.ico' } else { 'browser.ico' }
        $icns = if ($variant -eq 'app') { 'icon.icns' } else { 'app.icns' }
        Copy-Item -LiteralPath (Join-Path $generated 'icon.ico') -Destination (Join-Path $destination $ico)
        Copy-Item -LiteralPath (Join-Path $generated 'icon.icns') -Destination (Join-Path $destination $icns)
    }
} finally {
    Pop-Location
    # The GUID directory is created above under the resolved OS temporary directory.
    $resolvedWork = [IO.Path]::GetFullPath($iconWork)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedWork.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected icon temporary path' }
    Remove-Item -LiteralPath $resolvedWork -Recurse -Force
}
