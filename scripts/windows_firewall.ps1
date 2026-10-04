# Loaded from the packaged resource, then passed as an encoded command.
# The caller sets GameExecutable, GamePort and Mode (probe/ensure/apply).
$ErrorActionPreference = 'Stop'
function Get-NightfallRuleName {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($GameExecutable.ToLowerInvariant()))).Replace('-', '').Substring(0, 16) }
    finally { $sha.Dispose() }
    return "NightfallPoker-LAN-$hash-UDP-$GamePort"
}
function Test-NightfallPort($Ports) {
    foreach ($value in @($Ports)) {
        if ($value -eq 'Any' -or $value -eq "$GamePort") { return $true }
        if ($value -match '^(\d+)-(\d+)$' -and $GamePort -ge [int]$Matches[1] -and $GamePort -le [int]$Matches[2]) { return $true }
    }
    return $false
}
function Get-NightfallStatus {
    $connections = @(Get-NetConnectionProfile)
    $categories = @($connections | ForEach-Object { if ($_.NetworkCategory -eq 'DomainAuthenticated') { 'Domain' } else { "$($_.NetworkCategory)" } })
    # Explicit blocks override allows. Do not remove another administrator's rules.
    $blocks = @(Get-NetFirewallRule -PolicyStore ActiveStore | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' })
    foreach ($rule in $blocks) {
        if ($categories.Count -gt 0 -and "$($rule.Profile)" -ne 'Any' -and -not @($categories | Where-Object { "$($rule.Profile)" -match $_ }).Count) { continue }
        $app = $rule | Get-NetFirewallApplicationFilter
        if ($app.Program -ne 'Any' -and $app.Program -ne $GameExecutable) { continue }
        $filter = $rule | Get-NetFirewallPortFilter
        if ($filter.Protocol -in @('UDP', '17', 'Any', '256') -and (Test-NightfallPort $filter.LocalPort)) { return 4 }
    }
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
    foreach ($connection in $connections) {
        $category = if ($connection.NetworkCategory -eq 'DomainAuthenticated') { 'Domain' } else { "$($connection.NetworkCategory)" }
        $profile = $profiles | Where-Object Name -EQ $category
        if ($profile.Enabled -eq 'True' -and ($profile.AllowInboundRules -eq 'False' -or $profile.AllowLocalFirewallRules -eq 'False')) { return 6 }
    }
    $rule = Get-NetFirewallRule -PolicyStore ActiveStore -Name (Get-NightfallRuleName) -ErrorAction SilentlyContinue
    if ($rule -and $rule.Enabled -eq 'True' -and $rule.Action -eq 'Allow' -and $rule.Direction -eq 'Inbound' -and "$($rule.Profile)" -eq 'Any') {
        $app = $rule | Get-NetFirewallApplicationFilter
        $filter = $rule | Get-NetFirewallPortFilter
        $remote = $rule | Get-NetFirewallAddressFilter
        if ($app.Program -eq $GameExecutable -and $filter.Protocol -in @('UDP', '17') -and @($filter.LocalPort).Count -eq 1 -and "$($filter.LocalPort)" -eq "$GamePort" -and @($remote.RemoteAddress).Count -eq 1 -and "$($remote.RemoteAddress)" -eq 'LocalSubnet') { return 0 }
    }
    return 1
}
function Invoke-NightfallFirewall {
    if ($GamePort -lt 1024 -or $GamePort -gt 65535 -or -not [IO.Path]::IsPathRooted($GameExecutable) -or -not (Test-Path -LiteralPath $GameExecutable -PathType Leaf)) { return 2 }
    $status = Get-NightfallStatus
    if ($status -ne 1 -or $Mode -eq 'probe') { return $status }
    if ($Mode -eq 'apply') {
        $name = Get-NightfallRuleName
        # Recreate only our own deterministic rule; no unrelated rules are changed.
        $old = Get-NetFirewallRule -PolicyStore PersistentStore -Name $name -ErrorAction SilentlyContinue
        if ($old) { $old | Remove-NetFirewallRule }
        New-NetFirewallRule -PolicyStore PersistentStore -Name $name -DisplayName "Nightfall Poker LAN UDP $GamePort" -Description 'Current executable and chosen UDP port; local subnet only.' -Direction Inbound -Action Allow -Enabled True -Profile Any -Program $GameExecutable -Protocol UDP -LocalPort $GamePort -RemoteAddress LocalSubnet -EdgeTraversalPolicy Block | Out-Null
        return (Get-NightfallStatus)
    }
    $path64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($GameExecutable))
    $prefix = "`$GameExecutable=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$path64'));`$GamePort=$GamePort;`$Mode='apply';"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prefix + $NightfallSource + ';try {$code=Invoke-NightfallFirewall} catch {$code=2};exit $code'))
    try {
        $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-EncodedCommand', $encoded) -Verb RunAs -WindowStyle Hidden -PassThru
        $null = $child.Handle
        if (-not $child.WaitForExit(90000)) { $child.Kill(); return 5 }
        return $child.ExitCode
    } catch [ComponentModel.Win32Exception] { return 3 }
}
