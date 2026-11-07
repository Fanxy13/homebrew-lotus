# The pets and their math game on Windows (Public/pets.ps1, Public/zetamac.ps1): the same .pet files and pets.tsv as the
# zsh engine, hunger, the drawings, adopting, feeding, reactions, /help with a pet, and a game played with keys.
# (tests/test-pets.zsh and tests/test-zetamac.zsh check the same things in zsh.)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-pets'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    lotus settings set LOTUS_NAME Ada | Out-Null
    InModuleScope Lotus { Initialize-Lotus; Import-LotusLangGroup pets; Import-LotusCommand pets; Import-LotusCommand zetamac }
    # pets.tsv with pets that ate <hours> ago: "Mochi cat 20" …
    function Set-TestPets {
        param([string[]]$Rows)
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $lines = foreach ($r in $Rows) { $f = $r -split ' '; "$($f[0])`t$($f[1])`t`t$($now - [long]$f[2] * 3600)" }
        New-Item -ItemType Directory -Force -Path $env:LOTUS_CONF | Out-Null
        [IO.File]::WriteAllText((Join-Path $env:LOTUS_CONF 'pets.tsv'), "# test`n$($lines -join "`n")`n")
        Remove-Item -LiteralPath (Join-Path $env:LOTUS_STATE 'pets.tsv') -Force -ErrorAction SilentlyContinue
    }
    function Get-Plain { param([string]$Text) $Text -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '' }
    # what a pet said: the words of its bubble in one line
    function Get-Said { param([string]$Text) ((Get-Plain $Text) -replace '[\u2500-\u259F]', ' ' -replace '\s+', ' ').Trim() }
    # the cat's drawing from its pet file
    $script:CatIdle = [System.Collections.Generic.List[string]]::new()
    $on = $false
    foreach ($line in Get-Content (Join-Path $PSScriptRoot '../../data/pets/cat.pet')) {
        if ($line -ceq '[idle]') { $on = $true } elseif ($line.StartsWith('[')) { $on = $false } elseif ($on -and $line.Trim()) { $script:CatIdle.Add($line) }
    }
}

AfterAll {
    InModuleScope Lotus { $script:PetHour = $null }
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'kinds of pets' {
    It 'reads the cat and the dog of data/pets' {
        InModuleScope Lotus {
            Initialize-LotusPets
            @($script:PetKinds) -join ' ' | Should -Be 'cat dog'
            Get-LotusPetKindLabel 'dog' | Should -Be 'Dog'
            Get-LotusPetInfo 'cat' 'sound' | Should -Not -BeNullOrEmpty
            Get-LotusPetArtWidth 'cat' | Should -BeGreaterThan 5
            @(Get-LotusPetArtLines 'cat' 'idle').Count | Should -BeGreaterThan 2
        }
    }
    It 'says what is wrong with a file that is not a pet' {
        $dir = Join-Path $env:LOTUS_CACHE 'bad-pets'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $cases = @{
            'nospecies'  = "label: X`n[idle]`n ▄▄`n"
            'noidle'     = "species: blob`n[happy]`n ▄▄`n"
            'high'       = "species: blob`n[idle]`n" + ("x`n" * 9)
            'wide'       = "species: blob`n[idle]`n" + ('x' * 25) + "`n"
            'badspecies' = "species: 1blob`n[idle]`n x`n"
        }
        $want = @{ nospecies = 'species: is missing'; noidle = 'the drawing \[idle\] is missing'; high = 'higher than 8 lines'; wide = 'wider than 24'; badspecies = 'species: is missing' }
        foreach ($k in $cases.Keys) {
            $f = Join-Path $dir "$k.pet"
            [IO.File]::WriteAllText($f, $cases[$k])
            $r = InModuleScope Lotus -Parameters @{ F = $f } { Read-LotusPetFile $F }
            $r.Code | Should -Be 1 -Because $k
            "$($r.Msg)" | Should -Match $want[$k] -Because $k
        }
        $big = Join-Path $dir 'big.pet'
        [IO.File]::WriteAllText($big, "species: big`n[idle]`n x`n# " + ('x' * 16100))
        (InModuleScope Lotus -Parameters @{ F = $big } { Read-LotusPetFile $F }).Msg | Should -Be 'the file is too big'
    }
    It 'keeps only ASCII and block pixels in drawings, and no control characters in values' {
        $f = Join-Path $env:LOTUS_CACHE 'clean.pet'
        [IO.File]::WriteAllText($f, "species: Clean`nlabel: Cl$([char]7)ean`r`n[idle]`r`n ▄█▀ é$([char]27)[31m🐱x   `r`n")
        InModuleScope Lotus -Parameters @{ F = $f } {
            (Read-LotusPetFile $F).Value | Should -Be 'clean'
            Get-LotusPetInfo 'clean' 'label' | Should -Be 'Clean'
            Get-LotusPetArtText 'clean' 'idle' | Should -Be ' ▄█▀ [31mx'
        }
    }
}

Describe 'your pets' {
    BeforeEach { Set-TestPets @('Mochi cat 20', 'Bello dog 2'); InModuleScope Lotus { $script:PetHour = 14 } }

    It 'are hungry 12 hours after a meal, very hungry after a day' {
        InModuleScope Lotus {
            Initialize-LotusPets
            Get-LotusPetStatus 0 | Should -Be 'hungry'
            Get-LotusPetStatus 1 | Should -Be 'full for 10 h'
            Get-LotusPetMood 0 | Should -Be 'hungry'
            $script:PetFed['mochi'] = (Get-LotusEpoch) - 30 * 3600
            Get-LotusPetStatus 0 | Should -Be 'very hungry'
        }
    }
    It 'sleep from 11 pm to 6 am' {
        InModuleScope Lotus {
            Initialize-LotusPets
            $script:PetHour = 2
            Get-LotusPetMood 1 | Should -Be 'asleep'
            Get-LotusPetMood 1 'awake' | Should -Be 'happy'
            Get-LotusPetStatus 1 | Should -Be 'full for 10 h · asleep'
        }
    }
    It 'are adopted with a name that is not a command, up to three' {
        Set-TestPets @()
        lotus pets adopt cat Mochi | Out-Null
        $LASTEXITCODE | Should -Be 0
        lotus pets adopt dog mochi 6>&1 | Out-String | Should -Match 'already a pet called mochi'
        $LASTEXITCODE | Should -Be 1
        lotus pets adopt dog ls 6>&1 | Out-String | Should -Match 'already a command'
        lotus pets adopt dog foreach 6>&1 | Out-String | Should -Match 'already a command'
        lotus pets adopt dog 'Mo chi' 6>&1 | Out-String | Should -Match '1 to 16 letters'
        lotus pets adopt fish Nemo 6>&1 | Out-String | Should -Match 'no such kind'
        lotus pets adopt dog Bello | Out-Null
        lotus pets adopt cat Kiwi | Out-Null
        lotus pets adopt cat Luna 6>&1 | Out-String | Should -Match '3 pets'
        $rows = @(Get-Content (Join-Path $env:LOTUS_CONF 'pets.tsv') | Where-Object { $_ -notlike '#*' })
        @($rows | ForEach-Object { ($_ -split "`t")[0..1] -join ' ' }) -join ', ' | Should -Be 'Mochi cat, Bello dog, Kiwi cat'
        Get-Content (Join-Path $env:LOTUS_STATE 'pets.tsv') | Should -Contain "mochi`t$((($rows[0] -split "`t")[3]))`t0"
    }
    It 'are listed without a terminal' {
        $out = @(lotus pets)
        $out[0] | Should -Match '^Mochi\s+cat\s+hungry$'
        $out[1] | Should -Match '^Bello\s+dog\s+full for 10 h$'
    }
    It 'eat: hunger is gone, the meal is counted – and a full pet only sniffs' {
        $out = lotus feed mochi 6>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        Get-Plain $out | Should -Match 'Mochi'
        InModuleScope Lotus { Initialize-LotusPets; Get-LotusPetStatus 0; $script:PetCount['mochi'] } | Should -Be @('full for 12 h', 1)
        Get-Plain (lotus feed mochi 6>&1 | Out-String) | Should -Match 'is full and only sniffs'
        lotus feed nobody 6>&1 | Out-String | Should -Match 'no pet called nobody'
        lotus feed 6>&1 | Out-String | Should -Match 'Which pet'
    }
    It 'answer with short phrases when they cannot think' {
        lotus settings set LOTUS_PET_BRAIN off | Out-Null
        try { Get-Said (lotus pet mochi 'how are you' 6>&1 | Out-String) | Should -Match "I can only \w+ right now – with the AI of /ai I can talk" }
        finally { lotus settings set LOTUS_PET_BRAIN ai | Out-Null }
    }
    It 'remember the last three exchanges' {
        InModuleScope Lotus {
            Initialize-LotusPets
            1..4 | ForEach-Object { Save-LotusPetMemory 0 "q$_" "a$_" }
            (Get-LotusPetMemory 0) -split "`n" | Should -Be @('Ada: q2', 'Mochi: a2', 'Ada: q3', 'Mochi: a3', 'Ada: q4', 'Mochi: a4')
        }
    }
    It 'say only plain words' {
        InModuleScope Lotus {
            ConvertTo-LotusPetText "Mochi: **Hi**  there`n`e[31mfriend`` ## " 'Mochi' | Should -Be 'Hi there friend'
            ConvertTo-LotusPetText '"Purr."' 'Mochi' | Should -Be 'Purr.'
            (ConvertTo-LotusPetText ('x' * 400) 'Mochi').Length | Should -Be 318
        }
    }
    It 'know only what Lotus does on Windows, for the features that are on' {
        InModuleScope Lotus {
            Initialize-LotusPets
            $k = Get-LotusPetKnowledge
            $k | Should -Match 'winget'
            $k | Should -Not -MatchExactly 'Homebrew|\bMac\b|/bg |/minecraft|/ios'
            Set-LotusFeature weather $false
            try { $script:PetKnow = $null; Get-LotusPetKnowledge | Should -Not -Match '/weather' } finally { Set-LotusFeature weather $true }
        }
    }
    It 'are told who they are, in the language of Lotus' {
        InModuleScope Lotus {
            Initialize-LotusPets
            $i = Get-LotusPetInstructions 0 '' ''
            $i | Should -Match 'You are Mochi, a little cat who lives in Lotus, a start screen in the (Windows )?terminal'
            $i | Should -Match 'You belong to Ada'
            $i | Should -Match '/feed mochi'
            $i | Should -Match 'Always answer in English'
            Get-LotusPetInstructions 1 'help' '' | Should -Not -Match 'What you know about Lotus'
        }
    }
}

Describe 'drawings' {
    BeforeEach { Set-TestPets @('Mochi cat 1'); InModuleScope Lotus { $script:PetHour = 14 } }

    It 'a reaction draws the whole pet, not only the row with its eyes' {
        $env:COLUMNS = '100'
        $out = Get-Plain (Invoke-LotusWithKeys @() { Invoke-LotusPetReact typo })
        foreach ($row in $script:CatIdle) { $out | Should -Match ([regex]::Escape($row.TrimEnd())) }
        $out | Should -Match 'Mochi'
        $out | Should -Match 'tilts its head'
        (Get-Plain (Invoke-LotusWithKeys @() { Invoke-LotusPetReact done })) | Should -Match '╭'
    }
    It 'too narrow for the drawing: one line with the name' {
        $env:COLUMNS = '24'
        try {
            $lines = @((Get-Plain (Invoke-LotusWithKeys @() { Invoke-LotusPetReact typo })).Trim() -split "`n")
            $lines.Count | Should -Be 1
            $lines[0] | Should -Match 'Mochi: '
        } finally { $env:COLUMNS = '140' }
    }
    It 'a speech bubble wraps long words and keeps every line inside' {
        InModuleScope Lotus {
            $w = Split-LotusPetWords 'a bb ccccccccccccccc dd' 6
            $w | Should -Be @('a bb', 'cccccc', 'cccccc', 'ccc dd')
            Initialize-LotusPets
            $b = Get-LotusPetBlock 0 'idle' -1 'bubble' @('one', 'three')
            $plain = $b | ForEach-Object { $_ -replace "$([char]27)\[[0-9;]*m", '' }
            ($plain -join "`n") | Should -Match '─┤ one   │'
            ($plain -join "`n") | Should -Match '│ three │'
            # while it speaks, the bubble shows the first characters only
            (Get-LotusPetBlock 0 'talk' 5 'bubble' @('one', 'three') | ForEach-Object { $_ -replace "$([char]27)\[[0-9;]*m", '' }) -join "`n" | Should -Match '│ th    │'
        }
    }
    It 'the start screen: a hello in a bubble, a sleeping pet at night' {
        $out = Get-Plain (Invoke-LotusWithKeys @() { Show-LotusPetGreeting })
        $out | Should -Match '╭'
        $out | Should -Match 'Ada'
        $night = Get-Plain (Invoke-LotusWithKeys @() { $script:PetHour = 2; try { Show-LotusPetGreeting } finally { $script:PetHour = 14 } })
        $night | Should -Match 'Psst – Mochi is asleep'
        $night | Should -Not -Match '╭'
    }
    It 'a tip names one command of a feature that is on' {
        InModuleScope Lotus {
            Initialize-LotusPets
            $tip = Get-LotusPetTip
            $tip | Should -Match '^\S.* – \p{Ll}'
            $tip | Should -Not -Match 'System\.'
        }
    }
    It '/pets shows the pets side by side, with their names' {
        Set-TestPets @('Mochi cat 1', 'Bello dog 1')
        $out = Invoke-LotusWithKeys @() {
            $script:SelectHook = { param($Default, $Options) $global:PetsOptions = $Options; $null }
            try { Show-LotusPetsScreen } finally { $script:SelectHook = $null }
        }
        # the row of the names has the names only: the drawings stand above them, one row each
        (Get-Plain $out) -split "`n" | Where-Object { $_ -match '^\s+Mochi\s+Bello\s*$' } | Should -Not -BeNullOrEmpty
        @((Get-Plain $out) -split "`n" | Where-Object { $_ -match '[\u2580-\u259F].*\s{4,}.*[\u2580-\u259F]' }).Count | Should -BeGreaterThan 2
        $global:PetsOptions[0] | Should -Match '^Mochi\|Cat · full for 11 h$'
        $global:PetsOptions[2] | Should -Match '^Math game\|'
        Remove-Variable -Name PetsOptions -Scope Global
    }
    It 'the setup wizard adopts and introduces' {
        Set-TestPets @()
        $out = Invoke-LotusWithKeys @() {
            Import-LotusPetKinds
            "count=$(@(Get-LotusPets).Count)"
            "added=$(Add-LotusPet 'dog' 'Rex' -Quiet)"
            "count=$(@(Get-LotusPets).Count)"
            Show-LotusPetIntro 'Rex'
        }
        $out | Should -Match 'count=0'
        $out | Should -Match 'added=True'
        $out | Should -Match 'count=1'
        Get-Plain $out | Should -Match 'Hi Ada, I am Rex'
    }
}

Describe '/help with a pet' {
    BeforeEach { Set-TestPets @('Mochi cat 1'); InModuleScope Lotus { $script:PetHour = 14 } }

    It 'shows the commands that fit, without an AI, and puts the chosen one on the command line' {
        lotus settings set LOTUS_PET_BRAIN off | Out-Null
        Remove-Item -LiteralPath (Join-Path $env:LOTUS_CACHE 'ai-prompt') -Force -ErrorAction SilentlyContinue
        try {
            # (a key ends a speech at once: one for each of the two, then the pick)
            $out = Invoke-LotusWithKeys @('space', 'space', '1') {
                $script:LineHook = { param($Label, $Text) 'what is the weather forecast' }
                try { Invoke-LotusPetHelp } finally { $script:LineHook = $null }
            }
            Get-Plain $out | Should -Match 'Where do you need help'
            Get-Plain $out | Should -Match '1  /weather'
            Get-Plain $out | Should -Match 'Ready on your command line'
            Get-Content (Join-Path $env:LOTUS_CACHE 'ai-prompt') | Should -Match '^/weather'
        } finally { lotus settings set LOTUS_PET_BRAIN ai | Out-Null }
    }
    It 'finds commands with words in other languages' {
        # (the commands of Windows: on Linux the plugins' rows would tie with /weather – "weather-art")
        $env:LOTUS_AS_WINDOWS = '1'
        try {
            InModuleScope Lotus {
                Initialize-LotusPets
                $cmds = Get-LotusPetCommands
                $cmds[@(Get-LotusPetRank 'Wetter')[0]].Usage | Should -Match '^/weather'
                $cmds[@(Get-LotusPetRank 'el tiempo de mañana')[0]].Usage | Should -Match '^/weather'
                @(Get-LotusPetRank 'xyzzy plugh').Count | Should -Be 0
            }
        } finally { Remove-Item env:LOTUS_AS_WINDOWS -ErrorAction SilentlyContinue }
    }
    It 'leaves out what Windows does not have' {
        InModuleScope Lotus {
            Initialize-LotusPets
            $u = @(Get-LotusPetCommands | ForEach-Object Usage) -join ' '
            $u | Should -Not -Match '/minecraft|/ios|/bg '
        }
    } -Skip:(-not $IsWindows)
}

Describe 'settings and doctor' {
    BeforeEach { Set-TestPets @('Mochi cat 1'); InModuleScope Lotus { $script:PetHour = 14 } }

    It 'turn the start screen pet off and the thinking off' {
        Invoke-LotusWithKeys @() {
            $script:SelectAnswers = [System.Collections.Generic.Queue[object]]::new()
            foreach ($a in 1, 4, $null) { $script:SelectAnswers.Enqueue($a) }
            $script:SelectHook = { param($Default, $Options) $script:SelectAnswers.Dequeue() }
            try { Show-LotusPetsSettings } finally { $script:SelectHook = $null }
        } | Out-Null
        $s = Get-Content (Join-Path $env:LOTUS_CONF 'settings.zsh') -Raw
        $s | Should -Match "LOTUS_PET_START='0'"
        $s | Should -Match "LOTUS_PET_BRAIN='off'"
        lotus settings set LOTUS_PET_START 1 | Out-Null
        lotus settings set LOTUS_PET_BRAIN ai | Out-Null
    }
    It 'doctor lists the pets, the kinds and how they think' {
        $rows = InModuleScope Lotus {
            $global:PetRows = [System.Collections.Generic.List[string]]::new()
            Show-LotusPetDoctorRows { param($Mark, $Label, $Text) $global:PetRows.Add("$Mark|$Label|$Text") } 'ok' 'opt'
            $global:PetRows
        }
        $rows | Should -Contain 'ok|Mochi|cat · full for 11 h'
        ($rows -join "`n") | Should -Match 'ok\|Kinds\|cat, dog'
        ($rows -join "`n") | Should -Match 'Thinking'
        Remove-Variable -Name PetRows -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'your own kind of pet' {
    It 'is added from a file, as clean text, and a built-in species is refused' {
        $f = Join-Path $env:LOTUS_CACHE 'axolotl.txt'
        [IO.File]::WriteAllText($f, "Here it is:`n``````text`nspecies: axolotl`nlabel: Axolotl`npersonality: calm and curious`nsnack: ~~`n[idle]`n ▗▄▖`n▐██▌ `n``````")
        lotus pets add $f 6>&1 | Out-String | Should -Match 'The Axolotl is ready'
        $saved = Get-Content (Join-Path $env:LOTUS_CONF 'pets/axolotl.pet') -Raw
        $saved | Should -Match '^# Lotus pet, added with lotus pets add'
        $saved | Should -Match 'species: axolotl'
        $saved | Should -Match "\[idle\]`n ▗▄▖`n▐██▌`n"
        $saved | Should -Not -Match '```'
        InModuleScope Lotus { Initialize-LotusPets; $script:PetKinds -contains 'axolotl' } | Should -BeTrue
        [IO.File]::WriteAllText($f, "species: cat`n[idle]`n x`n")
        lotus pets add $f 6>&1 | Out-String | Should -Match "one of Lotus.* own pets"
        [IO.File]::WriteAllText($f, 'just words')
        lotus pets add $f 6>&1 | Out-String | Should -Match 'not a Lotus pet'
    }
}

Describe 'the math game' {
    BeforeEach { Set-TestPets @('Mochi cat 20', 'Bello dog 2'); InModuleScope Lotus { $script:PetHour = 14 } }

    It "has Zetamac's problems, the answer always a whole number, never the same twice in a row" {
        InModuleScope Lotus {
            $seen = @{}
            for ($i = 0; $i -lt 2000; $i++) {
                $last = $script:ZmQ
                New-LotusZmProblem normal
                $script:ZmQ | Should -Not -Be $last
                $p = $script:ZmQ -split ' '
                $x = [int]$p[0]; $y = [int]$p[2]; $ans = $script:ZmA
                $ok = switch ($p[1]) {
                    '+' { $x -in 2..100 -and $y -in 2..100 -and $ans -eq $x + $y }
                    '–' { $ans -in 2..100 -and $y -in 2..100 -and $x - $y -eq $ans }
                    '×' { $x -in 2..12 -and $y -in 2..100 -and $ans -eq $x * $y }
                    '÷' { $y -in 2..12 -and $ans -in 2..100 -and $x -eq $y * $ans }
                    default { $false }
                }
                $ok | Should -BeTrue -Because $script:ZmQ
                $seen[$p[1]] = 1
            }
            $seen.Count | Should -Be 4
            for ($i = 0; $i -lt 300; $i++) { New-LotusZmProblem easy; $script:ZmA | Should -BeLessOrEqual 100 }
        }
    }
    It 'feeds the pets: every right answer keeps them full longer, up to two days' {
        InModuleScope Lotus {
            Initialize-LotusPets
            Get-LotusPetStatus 0 | Should -Be 'hungry'
            $m = Invoke-LotusZmFeed 40 normal
            $m | Should -Be @(600, 1200)
            Get-LotusPetStatus 1 | Should -Be 'full for 20 h'
            Initialize-LotusPets
            Get-LotusPetStatus 1 | Should -Be 'full for 20 h'
            $m = Invoke-LotusZmFeed 1000 normal
            $m | Should -Be @(2880, 2880)
            $before = Get-Content (Join-Path $script:Paths.State 'pets.tsv') -Raw
            Invoke-LotusZmFeed 0 normal | Should -BeNullOrEmpty
            Get-Content (Join-Path $script:Paths.State 'pets.tsv') -Raw | Should -Be $before
        }
    }
    It 'keeps the best score per level and time' {
        InModuleScope Lotus {
            Remove-Item -LiteralPath (Join-Path $script:Paths.State 'zetamac.tsv') -Force -ErrorAction SilentlyContinue
            Save-LotusZmRecord normal 120 30 | Should -Be 0
            Save-LotusZmRecord normal 120 25 | Should -Be 30
            Save-LotusZmRecord normal 60 12 | Should -Be 0
            Get-Content (Join-Path $script:Paths.State 'zetamac.tsv') | Should -Contain "normal`t120`t30`t2"
        }
    }
    It 'says what it needs' {
        lotus zetamac 6>&1 | Out-String | Should -Match 'needs a terminal'
        $out = lotus zetamac 45 extreme 6>&1 | Out-String
        $out | Should -Match 'I do not know extreme'
        $out | Should -Match '/zetamac \[seconds\] \[easy\|normal\|hard\]'
    }
    It 'a game: right answers count without Enter, a wrong digit is taken back, the pets eat' {
        $out = Invoke-LotusWithKeys @('4', '2', '2', 'left', '4', '0', 'back', '4', '2', 'esc') {
            $real = (Get-Item function:New-LotusZmProblem).ScriptBlock
            Set-Item function:script:New-LotusZmProblem { param($Level) $script:ZmQ = '12 + 30'; $script:ZmA = 42 }
            try {
                Remove-Item -LiteralPath (Join-Path $script:Paths.State 'zetamac.tsv') -Force -ErrorAction SilentlyContinue
                Invoke-LotusZetamac @('10')
            } finally { Set-Item function:script:New-LotusZmProblem $real }
        }
        $plain = Get-Plain $out
        $plain | Should -Match '12 \+ 30 = '
        $plain | Should -Match 'Game over\.\s+3 right'
        $plain | Should -Match '3 bites for all of us'
        Get-Content (Join-Path $env:LOTUS_STATE 'zetamac.tsv') | Should -Contain "normal`t10`t3`t1"
    }
}
