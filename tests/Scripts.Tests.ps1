BeforeDiscovery {
    $scripts = Get-ChildItem -Path "$PSScriptRoot/../src" -Filter '*.ps1' |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
}

Describe '<Name>' -ForEach $scripts {
    BeforeAll {
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
        $text = Get-Content -Path $Path -Raw
    }

    It 'parses without errors' {
        $parseErrors | Should -BeNullOrEmpty
    }

    It 'requires PowerShell 7.2 or later' {
        $ast.ScriptRequirements.RequiredPSVersion | Should -BeGreaterOrEqual ([version]'7.2')
    }

    It 'documents the Graph permissions it needs' {
        $text | Should -Match 'Scopes:'
    }

    It 'contains no hard-coded secrets or object IDs' {
        $text | Should -Not -Match '(?i)(client_?secret|password)\s*=\s*[''"][^''"]{8,}'
        $text | Should -Not -Match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    }
}
