# install.ps1 from start to end, into a temporary folder and a temporary profile (nothing of yours is touched).

BeforeAll {
    $script:Repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('lotus-install-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Tmp | Out-Null
    $script:Pwsh = (Get-Process -Id $PID).Path
}

AfterAll {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'install.ps1' {
    It 'parses' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Repo 'install.ps1'), [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }
    It 'installs from a checkout, loads in the profile, and runs' {
        $dest = Join-Path $script:Tmp 'app'
        $profileFile = Join-Path $script:Tmp 'profile.ps1'
        $env:LOTUS_SRC = $script:Repo
        $env:LOTUS_DEST = $dest
        $env:LOTUS_PROFILE = $profileFile
        $env:LOTUS_CONF = Join-Path $script:Tmp 'conf'
        $env:LOTUS_CACHE = Join-Path $script:Tmp 'cache'
        Remove-Item Env:LOTUS_ROOT -ErrorAction SilentlyContinue
        try {
            $out = & $script:Pwsh -NoProfile -NonInteractive -File (Join-Path $script:Repo 'install.ps1') 2>&1 | Out-String
        } finally {
            Remove-Item Env:LOTUS_SRC, Env:LOTUS_DEST, Env:LOTUS_PROFILE -ErrorAction SilentlyContinue
        }
        $out | Should -Match 'Lotus is in'
        $out | Should -Match 'Done'
        foreach ($file in 'win/Lotus.psd1', 'win/Public/lotus.ps1', 'data/commands.tsv', 'logos/lotus.txt', 'lib/core.zsh') {
            Test-Path (Join-Path $dest $file) | Should -BeTrue -Because "$file is copied"
        }
        Test-Path (Join-Path $dest 'win/tests') | Should -BeFalse
        Test-Path (Join-Path $dest 'lib/cmd') | Should -BeFalse
        $profileText = Get-Content $profileFile -Raw
        $profileText | Should -Match '# >>> lotus >>>'
        $profileText | Should -Match 'Import-Module'
        $core = Get-Content (Join-Path $script:Repo 'lib/core.zsh') | Where-Object { $_ -match '^typeset -g LOTUS_VERSION=' } | Select-Object -First 1
        $want = ($core -split '=')[1].Trim()
        $got = & $script:Pwsh -NoProfile -Command "`$env:LOTUS_CONF = '$($env:LOTUS_CONF)'; Import-Module '$(Join-Path $dest 'win/Lotus.psd1')'; lotus version"
        $got | Should -Be $want
    }
    It 'is run a second time without a second block' {
        $dest = Join-Path $script:Tmp 'app'
        $profileFile = Join-Path $script:Tmp 'profile.ps1'
        $env:LOTUS_SRC = $script:Repo; $env:LOTUS_DEST = $dest; $env:LOTUS_PROFILE = $profileFile
        try { & $script:Pwsh -NoProfile -NonInteractive -File (Join-Path $script:Repo 'install.ps1') 2>&1 | Out-Null }
        finally { Remove-Item Env:LOTUS_SRC, Env:LOTUS_DEST, Env:LOTUS_PROFILE -ErrorAction SilentlyContinue }
        ([regex]::Matches((Get-Content $profileFile -Raw), '# >>> lotus >>>')).Count | Should -Be 1
    }
}
