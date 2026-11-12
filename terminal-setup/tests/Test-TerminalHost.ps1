# Disposable child scripts only; no real setup, CLI, credentials or desktop windows.
$ErrorActionPreference = 'Stop'
$terminalTemp = Join-Path ([IO.Path]::GetTempPath()) ('terminal-host-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $terminalTemp | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TerminalHost.ps1') -Destination $terminalTemp
    foreach ($name in @('Setup.ps1','Launch.ps1','Doctor.ps1')) {
        $code = if ($name -eq 'Setup.ps1') { 7 } else { 0 }
        [IO.File]::WriteAllText((Join-Path $terminalTemp $name), ('Write-Output "fixture-' + $name + '"; exit ' + $code))
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = Join-Path $PSHOME 'powershell.exe'
        $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $terminalTemp 'TerminalHost.ps1') + '" -ScriptName ' + $name
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $child = [Diagnostics.Process]::Start($startInfo)
        $child.StandardInput.WriteLine('')
        $child.StandardInput.Close()
        $output = $child.StandardOutput.ReadToEnd()
        $errors = $child.StandardError.ReadToEnd()
        $child.WaitForExit()
        if ($child.ExitCode -ne $code -or -not $output.Contains('fixture-' + $name)) { throw ('Terminal host failed: ' + $name + ' ' + $errors) }
        Write-Host ('PASS: terminal host ' + $name + ' exit code preserved')
        $child.Dispose()
    }
} finally {
    $resolvedTerminalTemp = [IO.Path]::GetFullPath($terminalTemp)
    $resolvedOsTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedTerminalTemp.StartsWith($resolvedOsTemp, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid test directory' }
    Remove-Item -LiteralPath $resolvedTerminalTemp -Recurse -Force
}
