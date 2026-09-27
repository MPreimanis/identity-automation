#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Reports
<#
.SYNOPSIS
  Authentication method registration per user, with a summary.
.NOTES
  Scopes: AuditLog.Read.All. Requires Entra ID P1 or P2.
#>
[CmdletBinding()]
param([string]$OutFile = "./auth-methods-$(Get-Date -Format yyyyMMdd).csv")

$details = Get-MgReportAuthenticationMethodUserRegistrationDetail -All

$details |
    Select-Object UserPrincipalName, UserDisplayName, UserType, IsAdmin, IsMfaRegistered, IsMfaCapable,
        IsPasswordlessCapable, IsSsprRegistered, UserPreferredMethodForSecondaryAuthentication,
        @{ Name = 'MethodsRegistered'; Expression = { $_.MethodsRegistered -join ';' } } |
    Export-Csv -Path $OutFile -NoTypeInformation -Encoding utf8

$members = @($details | Where-Object UserType -eq 'member')
[pscustomobject]@{
    Members             = $members.Count
    MfaRegistered       = @($members | Where-Object IsMfaRegistered).Count
    PasswordlessCapable = @($members | Where-Object IsPasswordlessCapable).Count
    AdminsWithoutMfa    = @($members | Where-Object { $_.IsAdmin -and -not $_.IsMfaRegistered }).Count
}
