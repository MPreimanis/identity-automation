BeforeAll {
    # Load only the helper functions from the script, without running the script itself
    $path = "$PSScriptRoot/../src/Invoke-Joiner.ps1"
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    foreach ($function in $functions) {
        . ([scriptblock]::Create($function.Extent.Text))
    }
}

Describe 'ConvertTo-UpnPart' {
    It 'turns <Text> into <Expected>' -ForEach @(
        @{ Text = 'Bērziņš';     Expected = 'berzins' }
        @{ Text = 'Ķēniņa';      Expected = 'kenina' }
        @{ Text = 'ŽANIS';       Expected = 'zanis' }
        @{ Text = 'Anna-Marija'; Expected = 'annamarija' }
        @{ Text = "O'Brien";     Expected = 'obrien' }
    ) {
        ConvertTo-UpnPart -Text $Text | Should -BeExactly $Expected
    }
}

Describe 'Get-RandomPassword' {
    It 'returns the requested length' {
        (Get-RandomPassword -Length 32).Length | Should -Be 32
    }

    It 'avoids characters that are easy to misread' {
        Get-RandomPassword | Should -Not -MatchExactly '[iloIO01]'
    }

    It 'returns a different value each time' {
        Get-RandomPassword | Should -Not -Be (Get-RandomPassword)
    }
}

Describe 'Invoke-WithRetry' {
    It 'retries until the action succeeds' {
        $script:attempts = 0
        $result = Invoke-WithRetry -Attempts 3 -DelaySeconds 0 -Action {
            $script:attempts++
            if ($script:attempts -lt 3) { throw 'not yet' }
            'done'
        }
        $result | Should -Be 'done'
        $script:attempts | Should -Be 3
    }

    It 'rethrows the error after the last attempt' {
        { Invoke-WithRetry -Attempts 2 -DelaySeconds 0 -Action { throw 'still failing' } } | Should -Throw 'still failing'
    }
}
