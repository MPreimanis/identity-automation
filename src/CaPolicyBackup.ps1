#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
  Export Conditional Access policies to JSON; import a policy back in report-only mode.
.NOTES
  Export scopes: Policy.Read.All. Import scopes: Policy.Read.All, Policy.ReadWrite.ConditionalAccess
#>

function Export-CaPolicy {
    [CmdletBinding()]
    param([string]$Path = './ca-backup')

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $uri = 'v1.0/identity/conditionalAccess/policies'
    do {
        $page = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject
        foreach ($policy in $page.value) {
            $fileName = ($policy.displayName -replace '[\\/:*?"<>|]', '_') + '.json'
            $policy | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $Path $fileName) -Encoding utf8
        }
        $uri = $page.'@odata.nextLink'
    } while ($uri)
}

function Import-CaPolicyReportOnly {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$File)

    $policy = Get-Content -Path $File -Raw | ConvertFrom-Json -AsHashtable
    foreach ($readOnly in 'id', 'createdDateTime', 'modifiedDateTime', 'templateId') {
        $policy.Remove($readOnly)
    }
    $policy['state'] = 'enabledForReportingButNotEnforced'

    if ($PSCmdlet.ShouldProcess($policy['displayName'], 'Create Conditional Access policy in report-only mode')) {
        $request = @{
            Method      = 'POST'
            Uri         = 'v1.0/identity/conditionalAccess/policies'
            Body        = ($policy | ConvertTo-Json -Depth 20)
            ContentType = 'application/json'
        }
        Invoke-MgGraphRequest @request
    }
}
