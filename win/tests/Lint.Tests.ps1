# Mistakes PowerShell does not report until the line runs – checked in every file of the module and the installers.

BeforeDiscovery {
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Files = @(Get-ChildItem -Path (Join-Path $repo 'win') -Recurse -Filter '*.ps1' | Where-Object FullName -notmatch '[\\/]meshchat[\\/]') +
        @(Get-Item (Join-Path $repo 'install.ps1')) +
        @(Get-ChildItem -Path (Join-Path $repo 'bin') -Filter '*.ps1' -ErrorAction SilentlyContinue) |
        ForEach-Object { @{ Name = $_.FullName.Substring($repo.Length + 1); Path = $_.FullName } }
}

Describe '<Name>' -ForEach $script:Files {
    BeforeAll {
        $tokens = $null; $errors = $null
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $script:Errors = $errors
        $script:Tokens = $tokens
    }
    It 'parses' {
        @($script:Errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) | Should -BeNullOrEmpty
    }
    It 'has no variable spelled in two cases in one function ($L and $l are the same variable)' {
        $found = foreach ($fn in $script:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $names = @{}
            foreach ($v in $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
                $p = $v.VariablePath
                if (-not $p.IsUnqualified -and -not $p.IsLocal) { continue }
                $k = $p.UserPath.ToLowerInvariant()
                if (-not $names.ContainsKey($k)) { $names[$k] = [System.Collections.Generic.HashSet[string]]::new() }
                [void]$names[$k].Add($p.UserPath)
            }
            foreach ($k in $names.Keys) {
                if ($names[$k].Count -gt 1 -and $k -notin 'true', 'false', 'null', '_', 'args', 'matches', 'pid', 'home', 'host', 'input', 'error', 'pwd', 'psitem') {
                    "$($fn.Name): $(($names[$k] | Sort-Object) -join ' ')"
                }
            }
        }
        @($found) | Should -BeNullOrEmpty
    }
    It 'has no typographic apostrophe in a single-quoted string (PowerShell takes it for a quote)' {
        # (the pattern from character codes: written as characters it would be read as quotes, the mistake it looks for)
        $q = "[$([char]0x2018)$([char]0x2019)$([char]0x201a)$([char]0x201b)]"
        $bad = foreach ($t in $script:Tokens) {
            if ($t.Kind -eq 'StringLiteral' -and $t.Text.Length -gt 2 -and $t.Text[0] -eq "'" -and $t.Text.Substring(1, $t.Text.Length - 2) -match $q) { "line $($t.Extent.StartLineNumber)" }
        }
        @($bad) | Should -BeNullOrEmpty
    }
}
