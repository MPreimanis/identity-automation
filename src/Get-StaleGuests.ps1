#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Users
<#
.SYNOPSIS
  Guests who never redeemed their invitation or have not signed in for N days. Optionally disables them.
.NOTES
  Scopes: User.Read.All, AuditLog.Read.All (add User.ReadWrite.All for -Disable)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$Days = 90,
    [switch]$Disable
)

$cutoff = (Get-Date).ToUniversalTime().AddDays(-$Days)
$props  = 'id,displayName,mail,userType,accountEnabled,createdDateTime,externalUserState,signInActivity'

$stale = Get-MgUser -All -Filter "userType eq 'Guest'" -Property $props |
    Where-Object AccountEnabled |
    Where-Object {
        $last = $_.SignInActivity.LastSignInDateTime
        if ($_.ExternalUserState -eq 'PendingAcceptance') { $_.CreatedDateTime -lt $cutoff }
        elseif ($last) { $last -lt $cutoff }
        else { $_.CreatedDateTime -lt $cutoff }
    }

$stale |
    Select-Object DisplayName, Mail, ExternalUserState, CreatedDateTime,
        @{ Name = 'LastSignIn'; Expression = { $_.SignInActivity.LastSignInDateTime } } |
    Format-Table -AutoSize

if ($Disable) {
    foreach ($guest in $stale) {
        if ($PSCmdlet.ShouldProcess($guest.Mail, 'Disable guest account')) {
            Update-MgUser -UserId $guest.Id -AccountEnabled:$false
        }
    }
}
