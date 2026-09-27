#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Groups, Microsoft.Graph.Users
<#
.SYNOPSIS
  Licence usage per SKU, plus users with group-based licensing errors.
.NOTES
  Scopes: Organization.Read.All, GroupMember.Read.All, User.Read.All
#>
[CmdletBinding()]
param()

$skus = Get-MgSubscribedSku
$skuNames = @{}
$skus | ForEach-Object { $skuNames[$_.SkuId] = $_.SkuPartNumber }

'== Licence usage =='
$skus |
    Select-Object SkuPartNumber,
        @{ Name = 'Purchased'; Expression = { $_.PrepaidUnits.Enabled } },
        ConsumedUnits,
        @{ Name = 'Available'; Expression = { $_.PrepaidUnits.Enabled - $_.ConsumedUnits } } |
    Sort-Object SkuPartNumber |
    Format-Table -AutoSize

'== Group-based licensing errors =='
Get-MgGroup -All -Filter 'hasMembersWithLicenseErrors eq true' -Property 'id,displayName' | ForEach-Object {
    $group = $_
    $uri = 'v1.0/groups/{0}/membersWithLicenseErrors?$select=id' -f $group.Id
    $failing = (Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject).value

    foreach ($member in $failing) {
        $user = Get-MgUser -UserId $member.id -Property 'userPrincipalName,licenseAssignmentStates'
        $user.LicenseAssignmentStates |
            Where-Object { $_.AssignedByGroup -eq $group.Id -and $_.State -eq 'Error' } |
            ForEach-Object {
                [pscustomobject]@{
                    Group = $group.DisplayName
                    User  = $user.UserPrincipalName
                    Sku   = $skuNames[$_.SkuId]
                    Error = $_.Error
                }
            }
    }
} | Format-Table -AutoSize
