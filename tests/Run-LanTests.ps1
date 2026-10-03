param([int[]]$PlayerCounts = @(2, 3, 4))
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$godotExecutable = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot_console.exe'
if (-not (Test-Path -LiteralPath $godotExecutable)) {
    $godotExecutable = (Get-Command godot_console -ErrorAction Stop).Source
}
$resultDirectory = Join-Path $projectDirectory 'test-results'
New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
foreach ($playerCount in $PlayerCounts) {
    if ($playerCount -lt 2 -or $playerCount -gt 4) { throw 'PlayerCounts must be 2, 3 or 4' }
    $roomPort = 24700 + $playerCount
    $processes = @()
    try {
        foreach ($index in 0..($playerCount - 1)) {
            $role = if ($index -eq 0) { 'host' } else { 'client' }
            $outputPath = Join-Path $resultDirectory "lan-$playerCount-$index.out.log"
            $errorPath = Join-Path $resultDirectory "lan-$playerCount-$index.err.log"
            $arguments = @('--headless', '--path', ('"' + $projectDirectory + '"'), '--script', 'res://tests/test_lan_peer.gd', '--', "--role=$role", "--count=$playerCount", "--port=$roomPort", "--client=$index")
            $process = Start-Process -FilePath $godotExecutable -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru
            $processes += @{ Process = $process; Output = $outputPath; Error = $errorPath }
            if ($index -eq 0) { Start-Sleep -Milliseconds 700 }
        }
        $deadline = (Get-Date).AddSeconds(40)
        while (@($processes | Where-Object { -not $_.Process.HasExited }).Count -gt 0 -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 200
        }
        $failed = $false
        foreach ($entry in $processes) {
            $entry.Process.Refresh()
            $outText = Get-Content -LiteralPath $entry.Output -Raw
            $errText = Get-Content -LiteralPath $entry.Error -Raw -ErrorAction SilentlyContinue
            Write-Output $outText.Trim()
            if ($errText) { Write-Output $errText.Trim() }
            if (-not $entry.Process.HasExited -or $entry.Process.ExitCode -ne 0 -or $outText -notmatch 'PASS:' -or $errText -match 'ERROR|FAIL|SCRIPT ERROR') { $failed = $true }
        }
        if ($failed) { throw "LAN test failed for $playerCount players. See test-results logs." }
    } finally {
        foreach ($entry in $processes) {
            if (-not $entry.Process.HasExited) { Stop-Process -Id $entry.Process.Id }
        }
    }
}
Write-Output 'PASS: all selected ENet multiplayer room tests'
