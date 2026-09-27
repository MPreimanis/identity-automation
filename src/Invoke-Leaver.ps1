#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Users.Actions
<#
.SYNOPSIS
  Offboards a user: disable, revoke sessions, remove cloud group memberships, log each step.
.NOTES
  Scopes: User.ReadWrite.All, GroupMember.ReadWrite.All
  Synced users: disable in AD first (sync would overwrite a cloud change), then run this.
  Removing members of role-assignable groups needs Privileged Role Administrator.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Ticket', Justification = 'Used by Write-Step for the audit log')]
param(
    [Parameter(Mandatory)][string]$UserPrincipalName,
    [string]$Ticket = '',
    [string]$LogPath = './leaver-log.csv'
)

$log = [System.Collections.Generic.List[object]]::new()
function Write-Step {
    param([string]$Step, [string]$Result)
    $log.Add([pscustomobject]@{
        Time = (Get-Date).ToUniversalTime().ToString('o'); User = $UserPrincipalName; Ticket = $Ticket; Step = $Step; Result = $Result
    })
}

$user = Get-MgUser -UserId $UserPrincipalName -Property 'id,displayName,accountEnabled,onPremisesSyncEnabled' -ErrorAction Stop

# 1. Disable sign-in
if ($user.OnPremisesSyncEnabled) {
    Write-Step 'Disable account' 'Skipped: synced user, disable in Active Directory'
}
elseif ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Disable account')) {
    Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop
    Write-Step 'Disable account' 'Done'
}

# 2. Revoke refresh tokens and session cookies
if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Revoke sign-in sessions')) {
    $null = Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop
    Write-Step 'Revoke sessions' 'Done'
}

# 3. Remove group memberships that are managed in the cloud
$groups = Get-MgUserMemberOf -UserId $user.Id -All |
    Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group' }

foreach ($group in $groups) {
    $name = $group.AdditionalProperties['displayName']

    if (@($group.AdditionalProperties['groupTypes']) -contains 'DynamicMembership') {
        Write-Step "Group: $name" 'Skipped: dynamic, membership follows attributes'
        continue
    }
    if ($group.AdditionalProperties['onPremisesSyncEnabled']) {
        Write-Step "Group: $name" 'Skipped: synced from AD'
        continue
    }

    if ($PSCmdlet.ShouldProcess($name, "Remove $UserPrincipalName")) {
        try {
            $uri = 'v1.0/groups/{0}/members/{1}/$ref' -f $group.Id, $user.Id
            Invoke-MgGraphRequest -Method DELETE -Uri $uri
            Write-Step "Group: $name" 'Removed'
        }
        catch {
            Write-Step "Group: $name" "Failed: $($_.Exception.Message)"
        }
    }
}

$log | Export-Csv -Path $LogPath -NoTypeInformation -Append -Encoding utf8
$log | Format-Table Step, Result -AutoSize
