#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Applications
<#
.SYNOPSIS
  App registrations with secrets or certificates that expire within N days, or already have.
.NOTES
  Scopes: Application.Read.All
#>
[CmdletBinding()]
param([int]$Days = 30)

$now   = (Get-Date).ToUniversalTime()
$limit = $now.AddDays($Days)

Get-MgApplication -All -Property 'id,appId,displayName,passwordCredentials,keyCredentials' |
    ForEach-Object {
        $app = $_
        $credentials = @(
            $app.PasswordCredentials | ForEach-Object { [pscustomobject]@{ Type = 'Secret'; Name = $_.DisplayName; End = $_.EndDateTime } }
            $app.KeyCredentials | ForEach-Object { [pscustomobject]@{ Type = 'Certificate'; Name = $_.DisplayName; End = $_.EndDateTime } }
        )
        foreach ($credential in $credentials | Where-Object { $_.End -and $_.End -lt $limit }) {
            [pscustomobject]@{
                Application = $app.DisplayName
                AppId       = $app.AppId
                Type        = $credential.Type
                Name        = $credential.Name
                Expires     = $credential.End
                Status      = if ($credential.End -lt $now) { 'Expired' } else { 'Expiring' }
            }
        }
    } |
    Sort-Object Expires |
    Format-Table -AutoSize
