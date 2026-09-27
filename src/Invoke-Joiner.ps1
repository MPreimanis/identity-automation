#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns
<#
.SYNOPSIS
  Creates or updates cloud-only users from an HR export. Safe to re-run.
.EXAMPLE
  ./Invoke-Joiner.ps1 -CsvPath ./data/hr-export-sample.csv -UpnSuffix yourlab.onmicrosoft.com -WhatIf
.NOTES
  Scopes: User.ReadWrite.All, GroupMember.ReadWrite.All, UserAuthenticationMethod.ReadWrite.All
  In hybrid environments joiners are created in AD and reach Entra ID through sync.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$CsvPath,
    [Parameter(Mandatory)][string]$UpnSuffix,
    [switch]$IssueTap,
    [string]$ResultPath = './joiner-results.csv'
)

function ConvertTo-UpnPart {
    param([Parameter(Mandatory)][string]$Text)
    # "Bērziņš" -> "berzins": split letters from their diacritics, drop the marks, keep a-z and 0-9
    $decomposed = $Text.Normalize([Text.NormalizationForm]::FormD)
    $baseChars = $decomposed.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark
    }
    (-join $baseChars).ToLowerInvariant() -replace '[^a-z0-9]', ''
}

function Get-RandomPassword {
    param([int]$Length = 24)
    $chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%*-_=+'
    -join (1..$Length | ForEach-Object { $chars[[Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)] })
}

function Invoke-WithRetry {
    # New objects take a few seconds to replicate; retry with a growing delay
    param([Parameter(Mandatory)][scriptblock]$Action, [int]$Attempts = 4, [int]$DelaySeconds = 5)
    for ($i = 1; $i -le $Attempts; $i++) {
        try { return (& $Action) }
        catch {
            if ($i -eq $Attempts) { throw }
            Start-Sleep -Seconds ($DelaySeconds * $i)
        }
    }
}

$rows = Import-Csv -Path $CsvPath -Encoding utf8
$groupCache = @{}

$results = foreach ($row in $rows) {
    $alias  = '{0}.{1}' -f (ConvertTo-UpnPart $row.GivenName), (ConvertTo-UpnPart $row.Surname)
    $result = [ordered]@{ Upn = "$alias@$UpnSuffix"; EmployeeId = $row.EmployeeId; Action = 'None'; Manager = ''; Groups = ''; Tap = ''; Error = '' }

    try {
        # 1. Validate input: bad HR data is the most common cause of broken automation
        if ([string]::IsNullOrWhiteSpace($row.EmployeeId)) { throw 'EmployeeId is missing' }
        if ($row.UsageLocation -cnotmatch '^[A-Z]{2}$') { throw "UsageLocation '$($row.UsageLocation)' is not a two-letter country code" }

        $attributes = @{
            givenName     = $row.GivenName
            surname       = $row.Surname
            displayName   = '{0} {1}' -f $row.GivenName, $row.Surname
            companyName   = $row.Company
            department    = $row.Department
            jobTitle      = $row.JobTitle
            country       = $row.Country
            usageLocation = $row.UsageLocation
            employeeId    = $row.EmployeeId
        }

        # 2. Match on employeeId: names and UPNs change, HR identifiers should not
        $idFilter = "employeeId eq '{0}'" -f $row.EmployeeId.Replace("'", "''")
        $user = Get-MgUser -Filter $idFilter -Property 'id,userPrincipalName' -ErrorAction Stop | Select-Object -First 1

        if (-not $user) {
            # 3. Find a free UPN: anna.ozola, then anna.ozola2, anna.ozola3...
            $upn = "$alias@$UpnSuffix"
            $n = 1
            while (Get-MgUser -Filter ("userPrincipalName eq '{0}'" -f $upn.Replace("'", "''")) -Property 'id' -ErrorAction Stop) {
                $n++
                $upn = '{0}{1}@{2}' -f $alias, $n, $UpnSuffix
            }
            $result.Upn = $upn

            if ($PSCmdlet.ShouldProcess($upn, 'Create user')) {
                $body = $attributes + @{
                    accountEnabled    = $true
                    userPrincipalName = $upn
                    mailNickname      = $upn.Split('@')[0]
                    passwordProfile   = @{ password = (Get-RandomPassword); forceChangePasswordNextSignIn = $true }
                }
                $user = New-MgUser -BodyParameter $body -ErrorAction Stop
                $result.Action = 'Created'
            }
        }
        else {
            $result.Upn = $user.UserPrincipalName
            if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Update HR attributes')) {
                Update-MgUser -UserId $user.Id -BodyParameter $attributes -ErrorAction Stop
                $result.Action = 'Updated'
            }
        }

        # 4. Manager
        if ($user -and $row.ManagerUpn) {
            $manager = Get-MgUser -UserId $row.ManagerUpn -Property 'id' -ErrorAction Stop
            if ($PSCmdlet.ShouldProcess($result.Upn, "Set manager to $($row.ManagerUpn)")) {
                $ref = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($manager.Id)" }
                Invoke-WithRetry -Action { Set-MgUserManagerByRef -UserId $user.Id -BodyParameter $ref -ErrorAction Stop }
                $result.Manager = $row.ManagerUpn
            }
        }

        # 5. Groups, skipping dynamic groups and existing memberships
        if ($user -and $row.Groups) {
            $current = [System.Collections.Generic.HashSet[string]]::new()
            Invoke-WithRetry -Action { Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction Stop } |
                ForEach-Object { [void]$current.Add($_.Id) }

            $added = foreach ($name in ($row.Groups -split ';' | ForEach-Object Trim | Where-Object { $_ })) {
                if (-not $groupCache.ContainsKey($name)) {
                    $found = @(Get-MgGroup -Filter ("displayName eq '{0}'" -f $name.Replace("'", "''")) -Property 'id,groupTypes' -ErrorAction Stop)
                    if ($found.Count -ne 1) { throw "Group '$name' matched $($found.Count) groups. Use group IDs in production." }
                    $groupCache[$name] = $found[0]
                }
                $group = $groupCache[$name]
                if ($group.GroupTypes -contains 'DynamicMembership') { continue }
                if ($current.Contains($group.Id)) { continue }

                if ($PSCmdlet.ShouldProcess($result.Upn, "Add to group $name")) {
                    Invoke-WithRetry -Action { New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop }
                    $name
                }
            }
            $result.Groups = @($added) -join ';'
        }

        # 6. Temporary Access Pass for passwordless onboarding
        if ($IssueTap -and $result.Action -eq 'Created' -and $PSCmdlet.ShouldProcess($result.Upn, 'Issue a one-time Temporary Access Pass')) {
            $tapBody = @{ isUsableOnce = $true; lifetimeInMinutes = 60 }
            $tap = Invoke-WithRetry -Action { New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $user.Id -BodyParameter $tapBody -ErrorAction Stop }
            # Lab only. In production the pass goes to the manager through a secure channel, never into a file or pipeline log.
            Write-Information ('TAP for {0}: {1}' -f $result.Upn, $tap.TemporaryAccessPass) -InformationAction Continue
            $result.Tap = 'Issued'
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    [pscustomobject]$result
}

$results | Export-Csv -Path $ResultPath -NoTypeInformation -Encoding utf8
$results | Format-Table Upn, Action, Groups, Tap, Error -AutoSize
