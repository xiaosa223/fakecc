param([Parameter(Mandatory = $true)][ValidateSet('Setup.ps1','Launch.ps1','Doctor.ps1')][string]$ScriptName)
$ErrorActionPreference = 'Stop'
$scriptFile = Join-Path $PSScriptRoot $ScriptName
try {
    if (-not (Test-Path -LiteralPath $scriptFile -PathType Leaf)) { throw 'Terminal setup resources are missing.' }
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File $scriptFile
    $result = $LASTEXITCODE
    if ($result -ne 0) { Write-Host ('Operation stopped. Exit code: ' + $result) -ForegroundColor Yellow }
    if ($result -ne 0 -or $ScriptName -eq 'Doctor.ps1') { Read-Host 'Press Enter to close' | Out-Null }
    exit $result
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Press Enter to close' | Out-Null
    exit 1
}
