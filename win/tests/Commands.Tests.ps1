# The commands, with the system mocked where they would open a browser, call a web service or touch the hardware.
# What only Windows can do (the apps of the Start menu, keep awake, the volume) is in Windows.Tests.ps1.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    lotus settings set LOTUS_NAME Ada | Out-Null
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'web' {
    # (a mock does not run inside the module: what it sees goes into a global)
    BeforeEach {
        $global:LotusOpened = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Lotus Open-LotusTarget { $global:LotusOpened.Add($Target); 0 }
    }
    AfterAll { Remove-Variable -Name LotusOpened -Scope Global -ErrorAction SilentlyContinue }
    It 'searches with the engine of the settings, the words encoded' {
        lotus settings set LOTUS_SEARCH_ENGINE duckduckgo | Out-Null
        lotus search 'rust & go' 'café' *>&1 | Out-Null
        $global:LotusOpened[0] | Should -Be 'https://duckduckgo.com/?q=rust+%26+go+caf%C3%A9'
        lotus google mac shortcuts *>&1 | Out-Null
        $global:LotusOpened[1] | Should -Be 'https://www.google.com/search?q=mac+shortcuts'
    }
    It 'opens a site by name, searches it, or opens what looks like a link' {
        lotus browse github lotus *>&1 | Out-Null
        lotus browse example.com/page *>&1 | Out-Null
        lotus browse youtube *>&1 | Out-Null
        $global:LotusOpened -join ' ' | Should -Be 'https://github.com/search?q=lotus https://example.com/page https://www.youtube.com'
    }
    It 'opens only real links' {
        $out = lotus open 'not a link' *>&1 | Out-String
        $out | Should -Match 'not a valid link'
        $LASTEXITCODE | Should -Be 1
        lotus open https://github.com/Fanxy13 *>&1 | Out-Null
        $global:LotusOpened[-1] | Should -Be 'https://github.com/Fanxy13'
    }
    It 'needs words to search for' {
        (lotus search *>&1 | Out-String) | Should -Match 'Nothing to search for'
    }
}

Describe 'weather' {
    BeforeAll {
        $script:Geo = [pscustomobject]@{ results = @([pscustomobject]@{ name = 'Zurich'; admin1 = 'Zurich'; country = 'Switzerland'; latitude = 47.36667; longitude = 8.55 }) }
        $script:Forecast = @{
            current = @{ temperature_2m = 12.7; apparent_temperature = 10.2; relative_humidity_2m = 81; weather_code = 61; wind_speed_10m = 9.4; is_day = 1; time = '2026-11-06T09:00' }
            daily   = @{ time = @('2026-11-06', '2026-11-07', '2026-11-08', '2026-11-09'); weather_code = @(61, 3, 0, 95); temperature_2m_max = @(13.1, 11.0, 9.5, 8.0); temperature_2m_min = @(6.2, 4.0, -1.5, 2.0); precipitation_probability_max = @(80, 20, 0, 60) }
        } | ConvertTo-Json -Depth 5
    }
    It 'shows the city, the art and four days, from Open-Meteo' {
        Mock -ModuleName Lotus Invoke-RestMethod { $script:Geo } -ParameterFilter { $Uri -like 'https://geocoding-api.open-meteo.com/*' }
        Mock -ModuleName Lotus Invoke-WebRequest { [pscustomobject]@{ Content = $script:Forecast } } -ParameterFilter { $Uri -like 'https://api.open-meteo.com/*latitude=47.36667*' }
        $out = lotus weather Zurich *>&1 | Out-String
        $out | Should -Match 'Zurich, Zurich, Switzerland'
        $out | Should -Match '12°C\s+Rain'
        $out | Should -Match 'Feels like\s+10°C'
        $out | Should -Match 'Fri\s+Rain\s+13°C / 6°C\s+80% rain'
        $out | Should -Match 'Sun\s+Clear sky\s+9°C / -1°C'
        $out | Should -Match 'Thunderstorm'
    }
    It 'says when a city does not exist, and refuses what is no city name' {
        Mock -ModuleName Lotus Invoke-RestMethod { [pscustomobject]@{ } }
        (lotus weather Atlantisxyz *>&1 | Out-String) | Should -Match 'City not found'
        (lotus weather 'Paris; rm' *>&1 | Out-String) | Should -Match 'does not look like a city name'
    }
}

Describe 'clock' {
    It 'prints the time once without a terminal' {
        (lotus clock) | Should -Match '^\d\d:\d\d:\d\d$'
    }
    It 'draws every design, and keeps the last one for next time' {
        lotus settings set LOTUS_CLOCK_DESIGN minimal | Out-Null
        $out = Invoke-LotusWithKeys @('timeout', 'right', 'right', 'right', 'right', 'right', 'z', 'q') { lotus clock }
        $out | Should -Match 'lotus clock'
        (lotus settings get LOTUS_CLOCK_DESIGN) | Should -Be 'world'
        (lotus settings get LOTUS_CLOCK_ZONE) | Should -Be 'America/New_York'
    }
    It 'knows the time in the zones of the settings' {
        InModuleScope Lotus {
            Initialize-Lotus; Import-LotusCommand clock; Initialize-LotusClock
            Get-LotusClockZoneLine 'Asia/Tokyo' $false | Should -Match '^Tokyo \d\d:\d\d'
            Get-LotusClockZoneLine 'Nowhere/Atlantis' $false | Should -Be 'Nowhere/Atlantis ?'
            (Get-LotusClockWorld $true).Lines -join "`n" | Should -Match 'UTC\+9'
        }
    }
}

Describe 'keep awake' {
    It 'starts the keep-awake process, keeps its state, and stops only that one' {
        Mock -ModuleName Lotus Start-LotusAwake { [pscustomobject]@{ Code = 0; Value = $PID; Msg = @() } }
        Mock -ModuleName Lotus Test-LotusAwake { $ProcessId -eq $PID }
        Mock -ModuleName Lotus Stop-LotusAwake { }
        (lotus caffeine on 90 *>&1 | Out-String) | Should -Match '1 h 30 min'
        $state = (Get-Content (Join-Path $env:LOTUS_STATE 'caffeine') -Raw).Trim() -split ' '
        [int]$state[0] | Should -Be $PID
        [long]$state[2] - [long]$state[1] | Should -BeGreaterThan 5000
        (lotus caffeine status) | Should -Match 'on'
        lotus caffeine off *>&1 | Out-Null
        Should -Invoke -ModuleName Lotus Stop-LotusAwake -Times 1
        Test-Path (Join-Path $env:LOTUS_STATE 'caffeine') | Should -BeFalse
        (lotus caffeine status) | Should -Match 'off'
    }
    It 'forgets a process that is not its own any more' {
        Mock -ModuleName Lotus Test-LotusAwake { $false }
        Set-Content -LiteralPath (Join-Path $env:LOTUS_STATE 'caffeine') -Value '12345 1 0'
        (lotus caffeine status) | Should -Match 'off'
        Test-Path (Join-Path $env:LOTUS_STATE 'caffeine') | Should -BeFalse
    }
    It 'refuses what is no number of minutes' {
        (lotus caffeine on soon *>&1 | Out-String) | Should -Match 'must be a number'
        (lotus caffeine on 5000 *>&1 | Out-String) | Should -Match 'At most 24 hours'
    }
}

Describe 'music' {
    It 'shows what plays, from fastfetch' {
        Mock -ModuleName Lotus Get-LotusFastfetch { 'fastfetch' }
        Mock -ModuleName Lotus Invoke-LotusNativeText { '[{"type":"Media","result":{"song":{"name":"Habiba","artist":"Boef","album":"Habiba","status":"Playing","position":168000,"length":215000},"player":{"name":"Spotify","id":"spotify"}}}]' }
        $out = lotus audio now *>&1 | Out-String
        $out | Should -Match 'Habiba'
        $out | Should -Match 'Boef'
        $out | Should -Match '2:48 / 3:35'
    }
    It 'presses play only when it is paused' {
        Mock -ModuleName Lotus Get-LotusFastfetch { 'fastfetch' }
        Mock -ModuleName Lotus Invoke-LotusNativeText { '[{"result":{"song":{"name":"Song","status":"Playing"},"player":{"name":"Spotify"}}}]' }
        Mock -ModuleName Lotus Invoke-LotusMedia { [pscustomobject]@{ Code = 0; Value = 'Spotify'; Msg = @() } }
        (lotus audio play *>&1 | Out-String) | Should -Match 'Play\s+Spotify'
        Should -Invoke -ModuleName Lotus Invoke-LotusMedia -ParameterFilter { $Action -eq 'play' -and $Status -eq 'Playing' }
    }
    It 'says when nothing plays' {
        Mock -ModuleName Lotus Get-LotusFastfetch { 'fastfetch' }
        Mock -ModuleName Lotus Invoke-LotusNativeText { '[]' }
        (lotus audio now *>&1 | Out-String) | Should -Match 'Nothing is playing'
        (lotus audio next *>&1 | Out-String) | Should -Match 'Nothing is playing'
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'shortcuts' {
    It 'adds a link with {q}, lists it, and runs it with the words' {
        Mock -ModuleName Lotus Open-LotusTarget { $global:LotusLastOpen = $Target; 0 }
        (lotus shortcut add yt 'https://www.youtube.com/results?search_query={q}' *>&1 | Out-String) | Should -Match '/yt'
        (lotus shortcut list *>&1 | Out-String) | Should -Match '/yt\s+url'
        lotus run yt lofi beats *>&1 | Out-Null
        $global:LotusLastOpen | Should -Be 'https://www.youtube.com/results?search_query=lofi+beats'
        (Get-Content (Join-Path $env:LOTUS_CONF 'settings.zsh') -Raw) | Should -Match "LOTUS_SHORTCUTS=\('yt' 'url\|https://www.youtube.com/results\?search_query=\{q\}\|on'\)"
    }
    It 'runs a Lotus command with the words you add' {
        Mock -ModuleName Lotus Open-LotusTarget { $global:LotusLastOpen = $Target; 0 }
        lotus shortcut add gs '/google lotus' *>&1 | Out-Null
        lotus run gs terminal *>&1 | Out-Null
        $global:LotusLastOpen | Should -Be 'https://www.google.com/search?q=lotus+terminal'
    }
    It 'refuses a name of Lotus, a bad name and a shell command' {
        (lotus shortcut add weather https://x.com *>&1 | Out-String) | Should -Match 'is a Lotus command'
        (lotus shortcut add 'Bad Name' https://x.com *>&1 | Out-String) | Should -Match 'Invalid name'
        (lotus shortcut add rmall 'rm -rf /' *>&1 | Out-String) | Should -Match 'does not know what to open'
    }
    It 'turns one off and says so when it is run' {
        lotus shortcut off yt *>&1 | Out-Null
        (lotus run yt x *>&1 | Out-String) | Should -Match 'turned off'
        lotus shortcut on yt *>&1 | Out-Null
    }
}

Describe 'logos' {
    It 'takes your own ASCII art from the clipboard, and keeps $ for fastfetch' {
        Mock -ModuleName Lotus Get-LotusClipboardText { [pscustomobject]@{ Code = 0; Value = "`n  /\_/\`n ( o.o ) $`n  > ^ <`n`n"; Msg = @() } }
        InModuleScope Lotus {
            $script:KeyQueue.Clear(); $script:KeyQueue.Enqueue('y'); $script:KeyQueueActive = $true
            try { lotus logo import --clipboard *>&1 | Out-Null } finally { $script:KeyQueueActive = $false }
        }
        (lotus settings get LOTUS_LOGO) | Should -Be 'custom'
        $file = Get-Content (Join-Path $env:LOTUS_CONF 'logo.txt') -Raw
        $file | Should -Be "  /\_/\`n ( o.o ) `$`$`n  > ^ <`n"
        (lotus logo preview custom *>&1 | Out-String) | Should -Match ([regex]::Escape('( o.o ) $'))
        lotus logo reset *>&1 | Out-Null
        (lotus settings get LOTUS_LOGO) | Should -Be 'lotus'
    }
}

Describe 'the log' {
    It 'writes lines in the format of the zsh engine, keys masked, the home folder as ~' {
        InModuleScope Lotus {
            Initialize-Lotus
            Write-LotusLog WARN test "key sk-ant-abcdefghijklmnop and Bearer xyz123 and password=hunter2 in $(Get-LotusHome)/x"
        }
        $line = (Get-Content (Join-Path $env:LOTUS_STATE 'lotus.log'))[-1]
        $line | Should -Match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}\tWARN\ttest\t'
        $line | Should -Match 'sk-ant-•••'
        $line | Should -Match 'Bearer •••'
        $line | Should -Match 'password=•••'
        $line | Should -Match '~/x'
        $line | Should -Not -Match 'hunter2'
    }
    It 'prints the last lines, sets the level, tells where it is' {
        (lotus log tail 5 | Out-String) | Should -Match 'WARN\s+test'
        lotus log level detailed *>&1 | Out-Null
        (lotus settings get LOTUS_LOG_LEVEL) | Should -Be 'debug'
        (lotus log level loud *>&1 | Out-String) | Should -Match 'Not a log level|log_bad_level|level'
        (lotus log path) | Should -Be (Join-Path $env:LOTUS_STATE 'lotus.log')
        lotus log level info *>&1 | Out-Null
    }
    It 'opens the viewer and leaves it with q' {
        $out = Invoke-LotusWithKeys @('f', 'up', 'q') { lotus log }
        $out | Should -Match 'lotus'
    }
}

Describe 'MeshChat' {
    # its file is loaded first: a function that is not there yet cannot be mocked
    BeforeAll { InModuleScope Lotus { Import-LotusCommand meshchat } }
    It 'says what it is and where it comes from when meshchat.exe is not there' {
        Mock -ModuleName Lotus Find-LotusMeshChat { $null }
        $out = lotus meshchat *>&1 | Out-String
        $out | Should -Match 'MeshChat'
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'starts meshchat.exe with what you typed' {
        Mock -ModuleName Lotus Find-LotusMeshChat { 'meshchat.exe' }
        Mock -ModuleName Lotus Invoke-LotusInTheOpen { $global:LotusRan = "$Program $($Arguments -join ' ')"; 0 }
        lotus meshchat nick 'Ada L' *>&1 | Out-Null
        $global:LotusRan | Should -Be 'meshchat.exe nick Ada L'
    }
    It 'quotes arguments the way Windows programs split them' {
        InModuleScope Lotus {
            ConvertTo-LotusCommandLine @('nick', 'Ada L', 'say "hi"', 'C:\a b\', '') | Should -Be 'nick "Ada L" "say \"hi\"" "C:\a b\\" ""'
        }
    }
}
