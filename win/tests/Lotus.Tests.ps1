# Pester 5. The module's own functions are reached with InModuleScope; `lotus` itself is called like a user does.
# These run on Windows in CI (.github/workflows/windows.yml, test.yml) – and on any system with PowerShell 7.
# The settings file in fixtures/ was written by the zsh engine (lotus_save), so the two sides are tested against each other.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv
    $script:Repo = $script:Ctx.Repo
    $env:LOTUS_TMP = $script:Ctx.Tmp
    $env:LOTUS_FIXTURES = Join-Path $PSScriptRoot 'fixtures'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Remove-Item Env:LOTUS_TMP, Env:LOTUS_FIXTURES -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'the data it shares with the zsh engine' {
    It 'reports the version of lib/core.zsh' {
        $core = Get-Content (Join-Path $script:Repo 'lib/core.zsh') | Where-Object { $_ -match '^typeset -g LOTUS_VERSION=' } | Select-Object -First 1
        $want = ($core -split '=')[1].Trim()
        (lotus version) | Should -Be $want
        (lotus -v) | Should -Be $want
        $LASTEXITCODE | Should -Be 0
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
    It 'takes the keys and defaults of the settings from lib/core.zsh' {
        InModuleScope Lotus {
            $schema = Get-LotusSchema
            $schema.Keys.Count | Should -BeGreaterThan 60
            foreach ($k in $schema.Keys) { $schema.Defaults.ContainsKey($k) | Should -BeTrue -Because "$k has a default in lotus_defaults" }
            $schema.Defaults['LOTUS_THEME'] | Should -Be 'matcha'
            $schema.Defaults['LOTUS_BG_OUTPUT'] | Should -Be '~/Pictures/Lotus/Background Removed'
        }
    }
}

Describe 'settings.zsh' {
    It 'reads a file that zsh wrote' {
        InModuleScope Lotus {
            $s = (Read-LotusSettings (Join-Path $env:LOTUS_FIXTURES 'settings.zsh')).Values
            $s['LOTUS_NAME'] | Should -Be 'Ada'
            $s['LOTUS_THEME'] | Should -Be 'ocean'
            $s['LOTUS_AI_URL'] | Should -Be ''
            $s['LOTUS_CLOCK_ZONES'] | Should -Be 'America/New_York Europe/London'
            $s['LOTUS_WEATHER_LOCATION'] | Should -Be "Saint John's"
        }
    }
    It 'saves as zsh does, keeps the shortcuts and keys of newer versions, no CR' {
        New-Item -ItemType Directory -Force -Path $env:LOTUS_CONF | Out-Null
        Copy-Item (Join-Path $env:LOTUS_FIXTURES 'settings.zsh') (Join-Path $env:LOTUS_CONF 'settings.zsh')
        Add-Content -LiteralPath (Join-Path $env:LOTUS_CONF 'settings.zsh') -Value "LOTUS_FROM_THE_FUTURE='42'"
        InModuleScope Lotus {
            Initialize-Lotus
            Set-LotusSetting -Name 'LOTUS_THEME' -Value 'sakura'
            Set-LotusSetting -Name 'LOTUS_NAME' -Value "O'Brien"
        }
        $text = [System.IO.File]::ReadAllText((Join-Path $env:LOTUS_CONF 'settings.zsh'))
        $text | Should -Match "(?m)^LOTUS_THEME='sakura'$"
        $text | Should -Match "(?m)^LOTUS_NAME='O'\\''Brien'$"
        $text | Should -Match "(?m)^LOTUS_WEATHER_LOCATION='Saint John'\\''s'$"
        $text | Should -Match "(?m)^LOTUS_FROM_THE_FUTURE='42'$"
        $text | Should -Match "typeset -gA LOTUS_SHORTCUTS=\('yt' 'url\|https://youtube.com\|on'\)"
        $text | Should -Not -Match "`r"
        $text.StartsWith('# lotus – settings') | Should -BeTrue
    }
    It 'refuses a name that is not a Lotus setting, and a value of two lines' {
        InModuleScope Lotus {
            Initialize-Lotus
            { Set-LotusSetting -Name 'PATH' -Value 'x' } | Should -Throw
            { Set-LotusSetting -Name 'LOTUS_X' -Value "a`nb" } | Should -Throw
        }
    }
    It 'is used through lotus settings' {
        lotus settings set LOTUS_NAME Grace | Out-Null
        (lotus settings get LOTUS_NAME) | Should -Be 'Grace'
        $all = lotus settings *>&1 | Out-String
        $all | Should -Match 'LOTUS_NAME\s+Grace'
        lotus settings get LOTUS_NOT_THERE | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'the lines in the PowerShell profile' {
    It 'adds them once, keeps the rest, and takes them out again' {
        InModuleScope Lotus {
            $profilePath = Join-Path $env:LOTUS_TMP 'profile-hook.ps1'
            Set-Content -LiteralPath $profilePath -Value "Set-Alias ll Get-ChildItem`n"
            Add-LotusHook -ProfilePath $profilePath | Out-Null
            Add-LotusHook -ProfilePath $profilePath | Out-Null
            $text = Get-Content $profilePath -Raw
            ([regex]::Matches($text, '# >>> lotus >>>')).Count | Should -Be 1
            $text | Should -Match 'Import-Module'
            $text | Should -Match 'lotus shell-init'
            $text | Should -Match 'Set-Alias ll'
            Test-LotusHook -ProfilePath $profilePath | Should -BeTrue
            Remove-LotusHook -ProfilePath $profilePath | Should -BeTrue
            $after = Get-Content $profilePath -Raw
            $after | Should -Not -Match 'lotus'
            $after | Should -Match 'Set-Alias ll'
        }
    }
    It 'lotus setup --hook writes them to the profile, lotus unhook takes them out' {
        $out = lotus setup --hook *>&1 | Out-String
        $out | Should -Match ([regex]::Escape($env:LOTUS_PROFILE))
        (Get-Content $env:LOTUS_PROFILE -Raw) | Should -Match '# >>> lotus >>>'
        lotus unhook *>&1 | Out-Null
        (Get-Content $env:LOTUS_PROFILE -Raw) | Should -Not -Match 'lotus'
    }
}

Describe 'the start screen' {
    It 'shows the logo and the greeting without fastfetch, and says how to get the rest' {
        lotus settings set LOTUS_NAME Ada | Out-Null
        lotus settings set LOTUS_CONFIGURED 1 | Out-Null
        $out = InModuleScope Lotus {
            Mock Get-LotusFastfetch { $null }
            lotus show *>&1 | Out-String
        }
        $out | Should -Match 'Ada'
        $out | Should -Match 'fastfetch is missing'
    }
    It 'puts the greeting, the bottom line and the music lines into what fastfetch printed' {
        $out = InModuleScope Lotus {
            Initialize-Lotus
            $script:S['LOTUS_SALUTE'] = 'en'
            $script:NpOn = $true
            Mock Get-LotusFastfetch { 'fastfetch' }
            Mock Invoke-LotusNativeText { if ($Arguments -contains 'none' -or $Arguments[1] -like '*np-*') { "♫ Song`n  [■■··] 1:00" } else { "@@LOTUS_HELLO@@`n@@LOTUS_SALUTE@@`n@@LOTUS_NP1@@`n@@LOTUS_NP2@@" } }
            Get-LotusStartText -Columns 140
        }
        $out | Should -Not -Match '@@LOTUS_'
        $out | Should -Match 'Ada'
        $out | Should -Match 'Good (morning|afternoon|evening|night)'
        $out | Should -Match '♫ Song'
    }
    It 'takes the minimal lotus in a narrow window, and none in a very narrow one' {
        InModuleScope Lotus {
            Initialize-Lotus
            $wide = Get-LotusArtArgs 22 200
            $wide[1] | Should -Match 'lotus\.txt$'
            $narrow = Get-LotusArtArgs 22 100
            $narrow[1] | Should -Match 'minimal\.txt$'
            (Get-LotusArtArgs 22 60) -join ' ' | Should -Be '--logo none'
        }
    }
}

Describe 'the lotus command' {
    It 'suggests the closest command for an unknown one' {
        $out = lotus weathr *>&1 | Out-String
        $out | Should -Match 'Command not found'
        $out | Should -Match '/weather'
        $LASTEXITCODE | Should -Be 1
    }
    It 'says what Windows does not have, instead of failing quietly' {
        $out = lotus ios *>&1 | Out-String
        $out | Should -Match 'macOS only'
        $LASTEXITCODE | Should -Be 2
        $out = lotus minecraft *>&1 | Out-String
        $out | Should -Match 'not on Windows yet'
    }
    It 'explains a feature that is turned off (and runs nothing)' {
        lotus features weather off *>&1 | Out-Null
        $out = lotus weather Paris *>&1 | Out-String
        $out | Should -Match 'Weather'
        $out | Should -Match '(?i)turned off|is off'
        $LASTEXITCODE | Should -Be 3
        lotus features weather on *>&1 | Out-Null
    }
    It 'lists the features without a keyboard, and switches one for scripts' {
        $list = lotus features | Out-String
        $list | Should -Match 'weather\s+Weather\s+on'
        lotus features caffeine off *>&1 | Out-Null
        (lotus settings get LOTUS_FEATURES_OFF) | Should -Match 'caffeine'
        lotus features caffeine on *>&1 | Out-Null
        (lotus settings get LOTUS_FEATURES_OFF) | Should -Not -Match 'caffeine'
    }
}

Describe 'help, doctor and themes' {
    It 'lists every command of a feature that is on, and none of one that is off' {
        $out = lotus help *>&1 | Out-String
        $out | Should -Match 'lotus doctor'
        $out | Should -Match '/weather'
        lotus features weather off *>&1 | Out-Null
        $out = lotus cheatsheet *>&1 | Out-String
        $out | Should -Not -Match '/weather \[city\]'
        $out | Should -Match 'Turned off: Weather'
        lotus features weather on *>&1 | Out-Null
    }
    It 'says what is there' {
        $out = lotus doctor *>&1 | Out-String
        $out | Should -Match 'PowerShell'
        $out | Should -Match 'Settings'
        $out | Should -Match 'Features\s+\d+ of \d+ on'
    }
    It 'lists every theme of data/themes.tsv' {
        $out = lotus themes *>&1 | Out-String
        foreach ($name in 'Matcha', 'Sakura', 'Ocean') { $out | Should -Match $name }
    }
    It 'adds your own theme from the Theme Studio line, uses it, and removes it again' {
        $out = lotus themes add 'Night Sea' 0a1b2c '255;136;0' '#ff8800' 112233 445566 778899 aabbcc ddeeff *>&1 | Out-String
        $out | Should -Match 'Theme: Night Sea'
        (lotus settings get LOTUS_THEME) | Should -Be 'night-sea'
        (Get-Content (Join-Path $env:LOTUS_CONF 'themes.tsv') -Raw) | Should -Match "night-sea`tNight Sea`t10;27;44`t255;136;0"
        lotus themes add matcha 1 2 3 4 5 6 7 8 *>&1 | Out-String | Should -Match 'not a color|built-in'
        lotus themes remove night sea *>&1 | Out-Null
        (lotus settings get LOTUS_THEME) | Should -Be 'matcha'
    }
}

Describe 'the line PowerShell runs when you press Enter' {
    BeforeAll {
        InModuleScope Lotus {
            Initialize-Lotus
            $script:Shortcuts['yt'] = 'url|https://www.youtube.com/results?search_query={q}|on'
            $script:Shortcuts['old'] = 'url|https://example.com|off'
            Update-LotusShellTables
            [void]$script:PetNames.Add('mochi')
        }
    }
    It 'turns <Typed> into <Runs>' -ForEach @(
        @{ Typed = '/weather Paris'; Runs = 'lotus weather Paris' }
        @{ Typed = '/weather "New York"'; Runs = "lotus weather 'New York'" }
        @{ Typed = '/caffeine on 90'; Runs = 'lotus caffeine on 90' }
        @{ Typed = '/lotus'; Runs = 'lotus' }
        @{ Typed = '/google rust & go'; Runs = "lotus google rust '&' go" }
        @{ Typed = '/yt lofi beats'; Runs = 'lotus run yt lofi beats' }
        @{ Typed = '/old'; Runs = 'lotus suggest /old' }
        @{ Typed = '/weathr'; Runs = 'lotus suggest /weathr' }
        @{ Typed = 'https://example.com/?a=1&b=2'; Runs = "lotus open 'https://example.com/?a=1&b=2'" }
        @{ Typed = 'open Spotify'; Runs = 'lotus app Spotify' }
        @{ Typed = 'open Visual Studio Code'; Runs = "lotus app 'Visual Studio Code'" }
        @{ Typed = 'Mochi, how are you?'; Runs = "lotus pet mochi 'how are you?'" }
        @{ Typed = 'mochi'; Runs = 'lotus pet mochi' }
        @{ Typed = 'who is the goat?'; Runs = 'lotus goat' }
    ) {
        InModuleScope Lotus -Parameters @{ Typed = $Typed } { Convert-LotusShellLine $Typed } | Should -BeExactly $Runs
    }
    It 'leaves <Typed> as it is' -ForEach @(
        @{ Typed = 'Get-ChildItem' }
        @{ Typed = 'open notes.txt' }
        @{ Typed = 'open C:\temp' }
        @{ Typed = 'git commit -m "/weather"' }
        @{ Typed = "Write-Host one`nWrite-Host two" }
        @{ Typed = '' }
    ) {
        InModuleScope Lotus -Parameters @{ Typed = $Typed } { Convert-LotusShellLine $Typed } | Should -BeNullOrEmpty
    }
    It 'runs nothing for a feature that is off' {
        InModuleScope Lotus {
            $script:S['LOTUS_FEATURES_OFF'] = 'web apps'
            Convert-LotusShellLine 'https://example.com' | Should -BeNullOrEmpty
            Convert-LotusShellLine 'open Spotify' | Should -BeNullOrEmpty
            $script:S['LOTUS_FEATURES_OFF'] = ''
        }
    }
}

Describe 'the screens, with keys' {
    It 'picks a theme from the list with the arrow keys' {
        lotus settings set LOTUS_THEME matcha | Out-Null
        $out = Invoke-LotusWithKeys @('down', 'down', 'enter') { lotus themes }
        $out | Should -Match 'Theme: Ocean'
        (lotus settings get LOTUS_THEME) | Should -Be 'ocean'
    }
    It 'changes a setting in /settings and saves it' {
        lotus settings set LOTUS_STARTUP 1 | Out-Null
        # the first row is the name; down goes to the language, then auto-start, which space turns off
        Invoke-LotusWithKeys @('down', 'down', 'space', 'q') { lotus settings } | Out-Null
        (lotus settings get LOTUS_STARTUP) | Should -Be '0'
    }
    It 'asks "Did you mean …?" for a typo, and picks from a short list when several are close' {
        InModuleScope Lotus {
            $script:KeyQueue.Clear(); $script:KeyQueue.Enqueue('y'); $script:KeyQueueActive = $true
            try { Select-LotusPick 'spotfy' 'app' @('Spotify', 'Steam', 'Slack') 6>$null | Should -Be 'Spotify' }
            finally { $script:KeyQueueActive = $false }
            Select-LotusPick 'Spotify' 'app' @('Spotify', 'Steam') 6>$null | Should -Be 'Spotify'
        }
    }
}
