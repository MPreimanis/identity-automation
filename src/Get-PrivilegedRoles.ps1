#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Identity.Governance
<#
.SYNOPSIS
  Lists active and PIM-eligible directory role assignments.
.NOTES
  Scopes: RoleManagement.Read.Directory. Eligible assignments only exist with Entra ID P2.
#>
[CmdletBinding()]
param([string]$OutFile = "./privileged-roles-$(Get-Date -Format yyyyMMdd).csv")

$roleNames = @{}
Get-MgRoleManagementDirectoryRoleDefinition -All | ForEach-Object { $roleNames[$_.Id] = $_.DisplayName }

function ConvertTo-RoleRow {
    param($Item, [string]$Assignment)
    $principal = $Item.Principal.AdditionalProperties
    [pscustomobject]@{
        Role          = $roleNames[$Item.RoleDefinitionId]
        Assignment    = $Assignment
        PrincipalName = $principal['displayName']
        PrincipalUpn  = $principal['userPrincipalName']
        PrincipalType = ($principal['@odata.type'] -replace '^#microsoft\.graph\.', '')
        Scope         = $Item.DirectoryScopeId
    }
}

$rows = [System.Collections.Generic.List[object]]::new()
Get-MgRoleManagementDirectoryRoleAssignment -All -ExpandProperty 'principal' |
    ForEach-Object { $rows.Add((ConvertTo-RoleRow -Item $_ -Assignment 'Active')) }
Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All -ExpandProperty 'principal' |
    ForEach-Object { $rows.Add((ConvertTo-RoleRow -Item $_ -Assignment 'Eligible')) }

$rows | Sort-Object Role, Assignment | Export-Csv -Path $OutFile -NoTypeInformation -Encoding utf8
$rows | Group-Object Role | Sort-Object Count -Descending | Select-Object Count, Name | Format-Table -AutoSize
