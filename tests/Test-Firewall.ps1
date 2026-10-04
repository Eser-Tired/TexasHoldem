$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/windows_firewall.ps1')
$GameExecutable = Join-Path $env:SystemRoot 'System32/notepad.exe'
$GamePort = 24680
$Mode = 'probe'
$script:Fixture = 'missing'
$script:Created = $null
function Get-NetFirewallRule {
    param($PolicyStore, $Enabled, $Direction, $Action, $Name, $ErrorAction)
    if (-not $Name) {
        if ($script:Fixture -eq 'blocked') { [pscustomobject]@{ Kind = 'block'; Enabled = 'True'; Direction = 'Inbound'; Action = 'Block'; Profile = 'Public' } }
        return
    }
    if ($script:Fixture -eq 'allowed' -or $script:Created) { [pscustomobject]@{ Kind = 'allow'; Enabled = 'True'; Action = 'Allow'; Direction = 'Inbound'; Profile = 'Any' } }
}
function Get-NetFirewallApplicationFilter { param([Parameter(ValueFromPipeline)]$InputObject) process { [pscustomobject]@{ Program = $GameExecutable } } }
function Get-NetFirewallPortFilter { param([Parameter(ValueFromPipeline)]$InputObject) process { [pscustomobject]@{ Protocol = 'UDP'; LocalPort = if ($InputObject.Kind -eq 'block') { '24000-25000' } else { "$GamePort" } } } }
function Get-NetFirewallAddressFilter { param([Parameter(ValueFromPipeline)]$InputObject) process { [pscustomobject]@{ RemoteAddress = 'LocalSubnet' } } }
function Get-NetConnectionProfile { [pscustomobject]@{ NetworkCategory = 'Public' } }
function Get-NetFirewallProfile { [pscustomobject]@{ Name = 'Public'; Enabled = 'True'; AllowInboundRules = if ($script:Fixture -eq 'policy') { 'False' } else { 'True' }; AllowLocalFirewallRules = 'True' } }
function New-NetFirewallRule {
    param($PolicyStore, $Name, $DisplayName, $Description, $Direction, $Action, $Enabled, $Profile, $Program, $Protocol, $LocalPort, $RemoteAddress, $EdgeTraversalPolicy)
    $script:Created = @{} + $PSBoundParameters
}
function Remove-NetFirewallRule { throw 'Existing rules must not be removed in this fixture' }
function Check($Condition, $Message) { if (-not $Condition) { throw $Message } }
Check ((Invoke-NightfallFirewall) -eq 1) 'Missing allow is reported without mutation'
Check ($null -eq $script:Created) 'Probe never changes firewall'
$script:Fixture = 'blocked'
Check ((Invoke-NightfallFirewall) -eq 4) 'Explicit UDP block is surfaced'
$script:Fixture = 'policy'
Check ((Invoke-NightfallFirewall) -eq 6) 'Block-all public policy is surfaced'
$script:Fixture = 'allowed'
Check ((Invoke-NightfallFirewall) -eq 0) 'Existing exact allow is reused'
$script:Fixture = 'missing'
$Mode = 'apply'
Check ((Invoke-NightfallFirewall) -eq 0) 'Apply verifies the newly created rule'
Check ($script:Created.Program -eq $GameExecutable -and $script:Created.Protocol -eq 'UDP' -and $script:Created.LocalPort -eq 24680) 'Only current executable and chosen UDP port are opened'
Check ($script:Created.RemoteAddress -eq 'LocalSubnet' -and $script:Created.Profile -eq 'Any' -and $script:Created.EdgeTraversalPolicy -eq 'Block') 'Public/private profiles are supported, limited to local subnet'
$script:Created = $null
$GamePort = 0
Check ((Invoke-NightfallFirewall) -eq 2 -and $null -eq $script:Created) 'Invalid ports never change rules'
Write-Output 'PASS: read-only probing, deny/policy diagnostics, idempotence and scoped UDP rule creation (mocked OS cmdlets)'
