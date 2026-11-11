# What only Windows has – run on Windows only (.github/workflows/windows.yml): the system the module sees, Windows API
# calls without a compiler, the apps of the Start menu, keep awake with SetThreadExecutionState, secrets protected by
# DPAPI, and command lines as Windows programs split them.

BeforeDiscovery { $script:OnWindows = $IsWindows }

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-windows'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    InModuleScope Lotus { Initialize-Lotus }
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'Windows' -Skip:(-not $script:OnWindows) {
    It 'knows which Windows this is' {
        InModuleScope Lotus {
            $script:Os.Name | Should -Be 'windows'
            $script:Os.Build | Should -BeGreaterThan 17000
            $script:Os.Product | Should -Match 'Windows'
            $script:Os.Arch | Should -BeIn 'x86_64', 'arm64'
            Get-LotusOsDescription | Should -Match '^Windows .* · (x86_64|arm64)$'
            Test-LotusTrueColor | Should -BeTrue
        }
    }
    It 'keeps its files in the folders of Windows, unless told otherwise' {
        InModuleScope Lotus {
            $saved = @{ c = $env:LOTUS_CONF; k = $env:LOTUS_CACHE; s = $env:LOTUS_STATE; d = $env:LOTUS_DATA }
            Remove-Item Env:LOTUS_CONF, Env:LOTUS_CACHE, Env:LOTUS_STATE, Env:LOTUS_DATA
            try {
                $p = Get-LotusPaths
                $p.Conf | Should -Be (Join-Path $env:APPDATA 'lotus')
                $p.Cache | Should -Be (Join-Path $env:LOCALAPPDATA 'lotus\cache')
                $p.State | Should -Be (Join-Path $env:LOCALAPPDATA 'lotus\state')
                $p.Settings | Should -Be (Join-Path $env:APPDATA 'lotus\settings.zsh')
            } finally { $env:LOTUS_CONF = $saved.c; $env:LOTUS_CACHE = $saved.k; $env:LOTUS_STATE = $saved.s; $env:LOTUS_DATA = $saved.d }
        }
    }
    It 'calls a function of a Windows DLL without a compiler' {
        InModuleScope Lotus {
            $f = Get-LotusNative 'kernel32.dll' 'GetTickCount64' ([uint64]) @()
            $f.Invoke($null, @()) | Should -BeGreaterThan 0
            (Get-LotusNative 'kernel32.dll' 'GetTickCount64' ([uint64]) @()) | Should -Be $f
        }
    }
    It 'lists the apps of the Start menu' {
        InModuleScope Lotus {
            $r = Get-LotusInstalledApps
            $r.Code | Should -Be 0
            $r.Value.Count | Should -BeGreaterThan 0
        }
    }
    It 'keeps Windows awake with a hidden process that it alone can stop' {
        InModuleScope Lotus {
            $r = Start-LotusAwake 120
            $r.Code | Should -Be 0
            $p = Get-Process -Id $r.Value
            $p.ProcessName | Should -BeIn 'pwsh', 'powershell'
            Test-LotusAwake $r.Value (Get-LotusEpoch $p.StartTime) | Should -BeTrue
            Test-LotusAwake $r.Value 1000 | Should -BeFalse
            Stop-LotusAwake $r.Value
            Start-Sleep -Milliseconds 500
            Get-Process -Id $r.Value -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }
    It 'keeps a secret that only this Windows account can read' {
        InModuleScope Lotus {
            Set-LotusSecret 'lotus-test' 'sk-test-0123456789' | Should -Be 0
            $raw = Get-Content (Get-LotusSecretFile 'lotus-test') -Raw
            $raw | Should -Not -Match 'sk-test'
            Get-LotusSecret 'lotus-test' | Should -Be 'sk-test-0123456789'
            Remove-LotusSecret 'lotus-test' | Should -Be 0
            Get-LotusSecret 'lotus-test' | Should -BeNullOrEmpty
        }
    }
    It 'quotes a command line the way a Windows program splits it again' {
        InModuleScope Lotus -Parameters @{ Tmp = $script:Ctx.Tmp } {
            # a script that prints the arguments it got, one per line ($args reaches a script run with -File unchanged)
            $out = Join-Path $Tmp 'argv.txt'
            $echo = Join-Path $Tmp 'argv.ps1'
            Set-Content -LiteralPath $echo -Value '$args | ForEach-Object { "[$_]" }'
            $words = @('plain', 'two words', 'say "hi"', 'C:\a b\', '')
            $line = ConvertTo-LotusCommandLine (@('-NoProfile', '-File', $echo) + $words)
            Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $line -NoNewWindow -Wait -RedirectStandardOutput $out
            (Get-Content $out) -join '|' | Should -Be '[plain]|[two words]|[say "hi"]|[C:\a b\]|[]'
        }
    }
    It 'answers on the volume, with or without a sound device' {
        InModuleScope Lotus {
            $r = Invoke-LotusVolume 'get'
            $r.Code | Should -BeIn 0, 1, 2
            if ($r.Code -eq 0) { $r.Value | Should -BeIn (0..100) }
        }
    }
    It 'writes settings.zsh with LF line ends and no byte order mark, as zsh reads it' {
        lotus settings set LOTUS_NAME Ada | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $env:LOTUS_CONF 'settings.zsh'))
        $bytes[0] | Should -Not -Be 0xEF
        $bytes | Should -Not -Contain 13
    }
}
