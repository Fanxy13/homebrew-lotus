# Pester 5. The module's own functions are reached with InModuleScope; `lotus` itself is called like a user does.
# These run on Windows in CI (.github/workflows/test.yml) – and on any system with PowerShell 7.
# The settings file in fixtures/ was written by the zsh engine (lotus_save), so the two sides are tested against each other.

BeforeAll {
    $script:Repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('lotus-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Tmp | Out-Null
    $env:LOTUS_ROOT = $script:Repo
    $env:LOTUS_CONF = Join-Path $script:Tmp 'conf'
    $env:LOTUS_CACHE = Join-Path $script:Tmp 'cache'
    $env:LOTUS_TMP = $script:Tmp
    $env:LOTUS_FIXTURES = Join-Path $PSScriptRoot 'fixtures'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
}

AfterAll {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'the data it shares with the zsh engine' {
    It 'reports the version of lib/core.zsh' {
        $core = Get-Content (Join-Path $script:Repo 'lib/core.zsh') | Where-Object { $_ -match '^typeset -g LOTUS_VERSION=' } | Select-Object -First 1
        $want = ($core -split '=')[1].Trim()
        (lotus version) | Should -Be $want
        (lotus -v) | Should -Be $want
    }
    It 'reads the themes of data/themes.tsv' {
        InModuleScope Lotus {
            $themes = @(Get-LotusThemes)
            $themes.Count | Should -BeGreaterThan 10
            ($themes | Where-Object Name -eq 'matcha').Colors['logo'] | Should -Be '248;184;208'
        }
    }
    It 'reads the commands of data/commands.tsv' {
        InModuleScope Lotus {
            $commands = @(Get-LotusCommands)
            $commands.Count | Should -BeGreaterThan 30
            ($commands | Where-Object Trigger -eq '/weather').Command | Should -Be 'weather'
        }
    }
}

Describe 'settings.zsh' {
    It 'reads a file that zsh wrote' {
        InModuleScope Lotus {
            $s = Read-LotusSettings (Join-Path $env:LOTUS_FIXTURES 'settings.zsh')
            $s['LOTUS_NAME'] | Should -Be 'Ada'
            $s['LOTUS_THEME'] | Should -Be 'ocean'
            $s['LOTUS_AI_URL'] | Should -Be ''
            $s['LOTUS_CLOCK_ZONES'] | Should -Be 'America/New_York Europe/London'
            $s['LOTUS_WEATHER_LOCATION'] | Should -Be "Saint John's"
        }
    }
    It 'changes one setting and leaves the other lines as they are' {
        InModuleScope Lotus {
            $file = Join-Path $env:LOTUS_TMP 'settings.zsh'
            Copy-Item (Join-Path $env:LOTUS_FIXTURES 'settings.zsh') $file
            Set-LotusSetting -Path $file -Name 'LOTUS_THEME' -Value 'sakura'
            Set-LotusSetting -Path $file -Name 'LOTUS_NAME' -Value "O'Brien"
            Set-LotusSetting -Path $file -Name 'LOTUS_NEW' -Value 'x y'
            $s = Read-LotusSettings $file
            $s['LOTUS_THEME'] | Should -Be 'sakura'
            $s['LOTUS_NAME'] | Should -Be "O'Brien"
            $s['LOTUS_NEW'] | Should -Be 'x y'
            $s['LOTUS_WEATHER_LOCATION'] | Should -Be "Saint John's"
            (Get-Content $file -Raw) | Should -Match "typeset -gA LOTUS_SHORTCUTS=\('yt'"
            (Get-Content $file -Raw) | Should -Not -Match "`r"
        }
    }
    It 'refuses a name that is not a Lotus setting' {
        InModuleScope Lotus {
            $file = Join-Path $env:LOTUS_TMP 'refused'
            { Set-LotusSetting -Path $file -Name 'PATH' -Value 'x' } | Should -Throw
            { Set-LotusSetting -Path $file -Name 'LOTUS_X' -Value "a`nb" } | Should -Throw
        }
    }
    It 'is used through lotus settings' {
        lotus settings set LOTUS_NAME Grace | Out-Null
        (lotus settings get LOTUS_NAME) | Should -Be 'Grace'
        $all = lotus settings *>&1 | Out-String
        $all | Should -Match 'LOTUS_NAME\s+Grace'
    }
}

Describe 'the lines in the PowerShell profile' {
    It 'adds them once, keeps the rest, and takes them out again' {
        InModuleScope Lotus {
            $profilePath = Join-Path $env:LOTUS_TMP 'profile.ps1'
            Set-Content -LiteralPath $profilePath -Value "Set-Alias ll Get-ChildItem`n"
            Add-LotusHook -ProfilePath $profilePath | Out-Null
            Add-LotusHook -ProfilePath $profilePath | Out-Null
            $text = Get-Content $profilePath -Raw
            ([regex]::Matches($text, '# >>> lotus >>>')).Count | Should -Be 1
            $text | Should -Match 'Import-Module'
            $text | Should -Match 'Set-Alias ll'
            Test-LotusHook -ProfilePath $profilePath | Should -BeTrue
            Remove-LotusHook -ProfilePath $profilePath | Should -BeTrue
            $after = Get-Content $profilePath -Raw
            $after | Should -Not -Match 'lotus'
            $after | Should -Match 'Set-Alias ll'
        }
    }
}

Describe 'doctor and themes' {
    It 'says what is there' {
        $out = lotus doctor *>&1 | Out-String
        $out | Should -Match 'PowerShell 7.2 or newer'
        $out | Should -Match 'Settings file'
    }
    It 'lists every theme of data/themes.tsv' {
        $out = lotus themes *>&1 | Out-String
        foreach ($name in 'matcha', 'sakura', 'ocean') { $out | Should -Match $name }
    }
}

Describe 'what it does not do yet' {
    It 'says so instead of failing quietly' {
        $out = lotus weather *>&1 | Out-String
        $out | Should -Match 'not available on Windows yet'
    }
    It 'lists what it can do' {
        $out = lotus help *>&1 | Out-String
        $out | Should -Match 'lotus doctor'
    }
}
