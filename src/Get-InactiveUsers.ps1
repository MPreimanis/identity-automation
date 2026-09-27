#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Users
<#
.SYNOPSIS
  Lists enabled member accounts with no sign-in in the last N days.
.NOTES
  Scopes: User.Read.All, AuditLog.Read.All. signInActivity requires Entra ID P1 or P2.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3650)][int]$Days = 90,
    [string]$OutFile = "./inactive-users-$(Get-Date -Format yyyyMMdd).csv"
)

$now    = (Get-Date).ToUniversalTime()
$cutoff = $now.AddDays(-$Days)
$props  = 'id,displayName,userPrincipalName,accountEnabled,userType,createdDateTime,companyName,department,onPremisesSyncEnabled,signInActivity'

$report = Get-MgUser -All -Property $props |
    Where-Object { $_.UserType -eq 'Member' -and $_.AccountEnabled } |
    ForEach-Object {
        $last = @($_.SignInActivity.LastSignInDateTime, $_.SignInActivity.LastNonInteractiveSignInDateTime) |
            Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1

        $inactive = if ($last) { $last -lt $cutoff } else { $_.CreatedDateTime -lt $cutoff }

        if ($inactive) {
            [pscustomobject]@{
                DisplayName       = $_.DisplayName
                UserPrincipalName = $_.UserPrincipalName
                Company           = $_.CompanyName
                Department        = $_.Department
                Synced            = [bool]$_.OnPremisesSyncEnabled
                Created           = $_.CreatedDateTime
                LastSignIn        = $last
                DaysSinceSignIn   = if ($last) { [int]($now - $last).TotalDays } else { $null }
            }
        }
    }

$report | Sort-Object LastSignIn | Export-Csv -Path $OutFile -NoTypeInformation -Encoding utf8
Write-Output "Inactive accounts: $(@($report).Count). Report written to $OutFile"
