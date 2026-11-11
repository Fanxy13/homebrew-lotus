# The contract between the two engines (tests/contract): Lotus for Windows has to make exactly what the zsh engine makes
# of the same cases – the colors, the fuzzy scores, the settings file, the language files, the painted logos, the
# fastfetch configs and the greetings. tests/contract/expected holds zsh's answers (tests/test-contract.zsh keeps them
# current); these tests run on Windows, Linux and macOS.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-contract'
    $script:Repo = $script:Ctx.Repo
    $script:Cases = Join-Path $script:Repo 'tests/contract/cases'
    $script:Expected = Join-Path $script:Repo 'tests/contract/expected'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    function script:Read-Expected([string]$Name) { [System.IO.File]::ReadAllText((Join-Path $script:Expected $Name)).Replace("`r`n", "`n") }
    function script:Rows([string]$Name) { (Read-Expected $Name).TrimEnd("`n") -split "`n" | ForEach-Object { , ($_ -split "`t") } }
    function script:Sha256([string]$Text) {
        $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($Text))
        -join ($h | ForEach-Object { $_.ToString('x2') })
    }
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'the same colors as lotus_sgr' {
    It 'gives every color the same code, 24-bit and of the 256' {
        foreach ($r in Rows 'sgr.tsv') {
            InModuleScope Lotus -Parameters @{ r = $r } {
                ConvertTo-LotusSgr $r[0] -TrueColor $true | Should -BeExactly $r[1]
                ConvertTo-LotusSgr $r[0] -TrueColor $false | Should -BeExactly $r[2] -Because "$($r[0]) in 256 colors"
            }
        }
    }
}

Describe 'the same fuzzy matching as lib/fuzzy.zsh' {
    It 'scores every pair the same' {
        foreach ($r in Rows 'fuzzy.tsv') {
            InModuleScope Lotus -Parameters @{ r = $r } {
                Get-LotusScore $r[0] $(if ($r.Count -gt 1) { $r[1] } else { '' }) | Should -Be ([int]$r[2]) -Because "'$($r[0])' against '$($r[1])'"
            }
        }
    }
    It 'ranks in the same order, ties included' {
        foreach ($r in Rows 'rank.tsv') {
            InModuleScope Lotus -Parameters @{ r = $r } {
                $cases = Get-Content -LiteralPath (Join-Path $env:LOTUS_ROOT 'tests/contract/cases/rank.txt') | Where-Object { $_ -and $_[0] -ne '#' } | ForEach-Object { , ($_ -split "`t") }
                $case = $cases | Where-Object { $_[0] -ceq $r[0] } | Select-Object -First 1
                $rank = Get-LotusRank $case[0] ([int]$case[1]) ($case[2] -split '\|')
                $got = for ($i = 0; $i -lt $rank.Names.Count; $i++) { "$($rank.Names[$i]):$($rank.Scores[$i])" }
                ($got -join '|') | Should -BeExactly $r[2] -Because "the ranking of '$($r[0])'"
            }
        }
    }
}

Describe 'the same settings file as lotus_save' {
    BeforeEach {
        Remove-Item -LiteralPath $env:LOTUS_CONF -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $env:LOTUS_CONF | Out-Null
        Copy-Item (Join-Path $script:Cases 'settings.zsh') (Join-Path $env:LOTUS_CONF 'settings.zsh')
    }
    It 'migrates an older file the same way' {
        InModuleScope Lotus { Initialize-Lotus }
        [System.IO.File]::ReadAllText((Join-Path $env:LOTUS_CONF 'settings.zsh')) | Should -BeExactly (Read-Expected 'settings-migrated.zsh')
    }
    It 'writes the corrected values the same way' {
        InModuleScope Lotus { Initialize-Lotus; Save-LotusSettings -Quiet }
        [System.IO.File]::ReadAllText((Join-Path $env:LOTUS_CONF 'settings.zsh')) | Should -BeExactly (Read-Expected 'settings-saved.zsh')
    }
}

Describe 'the language files, read as data' {
    It 'reads every text of every file as zsh does' {
        foreach ($r in Rows 'lang.tsv') {
            InModuleScope Lotus -Parameters @{ r = $r } {
                $map = Read-LotusLangFile (Join-Path (Get-LotusRoot) "lib/lang/$($r[0])")
                $keys = [string[]]@($map.Keys)
                [Array]::Sort($keys, [StringComparer]::Ordinal)
                $sb = [System.Text.StringBuilder]::new()
                foreach ($k in $keys) { [void]$sb.Append($k).Append([char]0x1f).Append($map[$k]).Append([char]0x1e) }
                $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($sb.ToString()))
                $map.Count | Should -Be ([int]$r[1]) -Because $r[0]
                (-join ($h | ForEach-Object { $_.ToString('x2') })) | Should -Be $r[2] -Because $r[0]
            }
        }
    }
}

Describe 'the logos, painted' {
    It 'paints every logo byte for byte as lib/art.zsh does' {
        InModuleScope Lotus {
            Initialize-Lotus
            $rows = [System.IO.File]::ReadAllText((Join-Path (Get-LotusRoot) 'tests/contract/expected/art.tsv')).Replace("`r`n", "`n").TrimEnd("`n") -split "`n"
            foreach ($row in $rows) {
                $f = $row -split "`t"
                $p = $f[0] -split '-'
                $script:S['LOTUS_COLORS'] = $p[0]; $script:S['LOTUS_THEME'] = $p[1]; $script:S['LOTUS_LOGO_FADE'] = $p[2]; $script:S['LOTUS_LOGO_THEME'] = $p[3]
                Initialize-LotusColors
                $painted = Get-LotusLogoPainted $p[4]
                "$($painted.Width) $($painted.Height)" | Should -Be $f[1] -Because $f[0]
                Get-LotusSha256 $painted.File | Should -Be $f[2] -Because "the painting $($f[0])"
            }
        }
    }
}

Describe 'the fastfetch configs of the start screen' {
    It 'writes <Name> as lotus_build does' -ForEach @(
        @{ Name = 'default'; Set = @{ LOTUS_COLORS = 'truecolor' } }
        @{ Name = 'mono-256'; Set = @{ LOTUS_COLORS = '256'; LOTUS_THEME = 'mono' } }
        @{ Name = 'quiet'; Set = @{ LOTUS_COLORS = 'truecolor'; LOTUS_THEME = 'neon'; LOTUS_GREETING = 'off'; LOTUS_SALUTE = 'de'; LOTUS_SHOW_SESSION = '0' } }
        @{ Name = 'bare'; Set = @{ LOTUS_COLORS = '256'; LOTUS_SHOW_HARDWARE = '0'; LOTUS_SHOW_TIME = '0'; LOTUS_FEATURES_OFF = 'music' } }
    ) {
        InModuleScope Lotus -Parameters @{ Set = $Set } {
            Initialize-Lotus
            Reset-LotusSettings
            $script:S['LOTUS_NAME'] = 'Ada'
            foreach ($k in $Set.Keys) { $script:S[$k] = $Set[$k] }
            Initialize-LotusColors
            $script:NpOn = (Test-LotusOn $script:S['LOTUS_SHOW_MUSIC']) -and (Test-LotusFeature 'music')
            Update-LotusFastfetchConfig -Force
        }
        $mode = if ($Set.LOTUS_COLORS -eq '256') { '256' } else { 'tc' }
        [System.IO.File]::ReadAllText((Join-Path $env:LOTUS_CACHE "fastfetch-$mode.jsonc")) | Should -BeExactly (Read-Expected "fastfetch/$Name.jsonc")
        [System.IO.File]::ReadAllText((Join-Path $env:LOTUS_CACHE "fastfetch-$mode.jsonc.lines")) | Should -BeExactly (Read-Expected "fastfetch/$Name.lines")
        [System.IO.File]::ReadAllText((Join-Path $env:LOTUS_CACHE "np-$mode.jsonc")) | Should -BeExactly (Read-Expected "fastfetch/$Name.np.jsonc")
    }
}

Describe 'the greetings' {
    It 'greets in the same languages in the same order, and says the same at every hour' {
        $want = Rows 'texts.tsv'
        InModuleScope Lotus -Parameters @{ want = $want } {
            Initialize-Lotus
            Reset-LotusSettings
            $script:S['LOTUS_NAME'] = 'Ada'; $script:S['LOTUS_COLORS'] = 'truecolor'
            Initialize-LotusColors
            Remove-Item -LiteralPath (Join-Path $script:Paths.Cache 'greeting') -ErrorAction SilentlyContinue
            foreach ($w in $want) {
                if ($w[0] -eq 'hello') { Get-LotusHello | Should -BeExactly $w[1]; continue }
                $p = $w[0] -split '-'
                $script:S['LOTUS_SALUTE'] = $p[1]
                Get-LotusSalute -Hour ([int]$p[2]) | Should -BeExactly $(if ($w.Count -gt 1) { $w[1] } else { '' }) -Because $w[0]
            }
        }
    }
}
