# /zetamac [seconds] [easy|normal|hard] – the math game of the pets, a port of lib/cmd/zetamac.zsh (loaded by pets.ps1).
# Like the Arithmetic Game on arithmetic.zetamac.com: as many problems as you can in 120 seconds, and an answer counts
# as soon as it is right – no Enter. "normal" has Zetamac's default ranges: (2–100) + (2–100) and (2–12) × (2–100),
# subtraction and division are these in reverse, so every answer is a whole number above 1. Every right answer is a bite
# for each of your pets: it keeps them full longer, up to two days. The best score per level and time is kept in
# zetamac.tsv in the state folder.

# addition: left min max, right min max · multiplication: left min max, right min max
$script:ZmRange = @{
    easy   = @(2, 20, 2, 20, 2, 10, 2, 10)
    normal = @(2, 100, 2, 100, 2, 12, 2, 100)
    hard   = @(10, 500, 10, 500, 2, 20, 10, 100)
}
$script:ZmMinutes = @{ easy = 10; normal = 15; hard = 20 }   # how long one right answer keeps a pet full
$script:ZmFullMax = 48                                       # hours – fuller than that a pet does not get
$script:ZmQ = ''                                             # the problem on screen
$script:ZmA = 0                                              # its answer
$script:ZmScore = 0

# A new problem → $script:ZmQ, $script:ZmA; never the same one twice in a row
function script:New-LotusZmProblem {
    param([string]$Level)
    $r = $script:ZmRange[$Level]
    if (-not $r) { $r = $script:ZmRange['normal'] }
    $last = $script:ZmQ
    $q = ''
    for ($try = 0; $try -lt 5; $try++) {
        $op = Get-Random -Maximum 4
        if ($op -lt 2) {
            $x = Get-Random -Minimum $r[0] -Maximum ($r[1] + 1); $y = Get-Random -Minimum $r[2] -Maximum ($r[3] + 1)
            if ($op -eq 0) { $q = "$x + $y"; $script:ZmA = $x + $y }
            else { $q = "$($x + $y) – $x"; $script:ZmA = $y }
        } else {
            $x = Get-Random -Minimum $r[4] -Maximum ($r[5] + 1); $y = Get-Random -Minimum $r[6] -Maximum ($r[7] + 1)
            if ($op -eq 2) { $q = "$x × $y"; $script:ZmA = $x * $y }
            else { $q = "$($x * $y) ÷ $x"; $script:ZmA = $y }
        }
        if ($q -cne $last) { break }
    }
    $script:ZmQ = $q
}

# The pets eat what was earned: <right answers> <level> → the minutes each pet is full now, or $null: nothing to eat.
# A pet is hungry 12 hours after its last meal – a big meal moves that meal into the future.
function script:Invoke-LotusZmFeed {
    param([int]$Score, [string]$Level)
    if ($Score -le 0 -or -not $script:PetN.Count) { return $null }
    $minutes = $script:ZmMinutes[$Level]
    if (-not $minutes) { $minutes = 15 }
    $gain = [long]$Score * $minutes * 60
    $max = [long]$script:ZmFullMax * 3600
    $now = Get-LotusEpoch
    $out = [System.Collections.Generic.List[long]]::new()
    for ($i = 0; $i -lt $script:PetN.Count; $i++) {
        $low = $script:PetN[$i].ToLowerInvariant()
        $full = [Math]::Max(0L, (Get-LotusPetFed $i) + 43200 - $now)
        $full = [Math]::Min($max, $full + $gain)
        $script:PetFed[$low] = $now + $full - 43200
        $c = 0L; [void]$script:PetCount.TryGetValue($low, [ref]$c)
        $script:PetCount[$low] = $c + 1
        $out.Add([long][Math]::Truncate(($full + 30) / 60))
    }
    Save-LotusPetState
    Write-LotusLog INFO pets "Math game: $Score right ($Level) – the pets ate"
    , $out.ToArray()
}

# Keeps the best score: <level> <seconds> <score> → the best before (0: none yet)
function script:Save-LotusZmRecord {
    param([string]$Level, [int]$Secs, [int]$Score)
    $file = Join-Path $script:Paths.State 'zetamac.tsv'
    $before = 0L; $games = 0L
    $sb = [System.Text.StringBuilder]::new()
    $text = Read-LotusFile $file
    if ($null -ne $text) {
        foreach ($line in $text -split "`n") {
            $f = $line -split "`t"
            if ($f.Count -lt 3 -or $f[2] -notmatch '^\d+\z') { continue }
            if ($f[0] -ceq $Level -and $f[1] -ceq [string]$Secs) { $before = Get-LotusInt $f[2] 0; $games = if ($f.Count -gt 3) { Get-LotusInt $f[3] 0 } else { 0 } }
            else { [void]$sb.Append("$line`n") }
        }
    }
    [void]$sb.Append("$Level`t$Secs`t$([Math]::Max([long]$Score, $before))`t$($games + 1)`n")
    try { Write-LotusFile $file $sb.ToString() } catch { Write-LotusLog WARN pets "The best score could not be saved: $_" }
    $before
}

# How long, in words
function script:Format-LotusZmDuration {
    param([long]$Minutes)
    if ($Minutes -lt 60) { (T zm_minutes).Replace('%s', [string]$Minutes) }
    elseif ($Minutes -lt 120) { T zm_hour }
    else { (T zm_hours).Replace('%s', [string][Math]::Truncate($Minutes / 60)) }
}

function script:Invoke-LotusZetamac {
    param([string[]]$Arguments)
    Import-LotusLangGroup pets
    $level = 'normal'
    $secs = 120
    foreach ($word in @($Arguments)) {
        $w = ([string]$word).ToLowerInvariant()
        $n = 0
        if ($w -match '^\d+\z' -and [int]::TryParse($w, [ref]$n) -and $n -ge 10 -and $n -le 600) { $secs = $n }
        elseif ($w -cin 'easy', 'leicht', 'facile', 'facil', 'fácil') { $level = 'easy' }
        elseif ($w -ceq 'normal') { $level = 'normal' }
        elseif ($w -cin 'hard', 'schwer', 'difficile', 'dificil', 'difícil') { $level = 'hard' }
        else { Write-LotusError ((T zm_bad).Replace('%s', $word)) '' @(T zm_usage); return (St 1) }
    }
    if (-not ((Test-LotusOutTty) -and (Test-LotusTty))) { Write-LotusError (T zm_tty) '' @(T zm_usage); return (St 1) }
    Initialize-LotusPets
    while ($true) {
        $rc = Invoke-LotusZmGame $level $secs
        if ($rc -eq 130) { break }
        if (-not (Show-LotusZmAfter $level $secs $script:ZmScore $rc)) { break }
    }
    Write-LotusRaw "$([char]27)[H$([char]27)[2J"
    St 0
}

# One game → $script:ZmScore; 0: the time is up, 1: ended with Esc, 130: Ctrl-C
function script:Invoke-LotusZmGame {
    param([string]$Level, [int]$Secs)
    if (-not (Enter-LotusPetScreen)) { return 130 }
    try {
        $esc = [char]27
        # the pets watch and eat along – when the window is tall enough
        $idle = @(); $eat = @()
        if ($script:PetN.Count -and (Get-LotusSize)[1] -ge 24) { $idle = Get-LotusPetLineup 'idle'; $eat = Get-LotusPetLineup 'eat' }
        $top = Get-LotusHeroLines (T zm_title) (Format-LotusPetText (T zm_sub) @([string]$Secs, (T "zm_$Level")))
        $a = "$esc[1;$($script:C['accent'])m"; $k = "$esc[1;$($script:C['key'])m"; $d = E dim; $b = E border; $r = $script:R; $bold = $script:B
        $boxw = 30
        $bar = Get-LotusLine $boxw
        $script:ZmScore = 0; $script:ZmQ = ''
        New-LotusZmProblem $Level
        $typed = ''; $pos = 0; $ended = 0   # pos: the digits left of the cursor
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $eatUntil = -1.0
        Write-LotusRaw "$esc[H$esc[2J"
        while ($true) {
            $now = $clock.Elapsed.TotalSeconds
            $left = [int][Math]::Truncate($Secs - $now + 0.999)
            if ($left -le 0) { break }
            # everything drawn again – synchronized, so nothing flickers
            $sb = [System.Text.StringBuilder]::new("$esc[?2026h$esc[H")
            foreach ($line in $top) { [void]$sb.Append("$line$esc[K`n") }
            [void]$sb.Append("$esc[K`n")
            if ($idle.Count) {
                foreach ($line in $(if ($now -lt $eatUntil) { $eat } else { $idle })) { [void]$sb.Append("$line$esc[0m$esc[K`n") }
                [void]$sb.Append("$esc[K`n")
            }
            # the time as a bar that runs out, the score next to it
            $full = [Math]::Max(0, [Math]::Min(30, [int][Math]::Truncate(($Secs - $now) * 30 / $Secs + 0.5)))
            [void]$sb.Append("    $d$(T zm_left)$r $k$(PadL ([string]$left) 3) s$r  $a$([string]::new([char]0x2501, $full))$b$([string]::new([char]0x2500, 30 - $full))$r   $d$(T zm_score)$r $k$($script:ZmScore)$r$esc[K`n")
            [void]$sb.Append("$esc[K`n")
            # the problem in a box
            $task = "$($script:ZmQ) = $typed"
            [void]$sb.Append("    $b╭$bar╮$r$esc[K`n")
            [void]$sb.Append("    $b│$r    $a$($script:ZmQ) = $r$bold$($typed.Substring(0, $pos))$r$a▏$r$bold$($typed.Substring($pos))$r$([string]::new(' ', [Math]::Max(0, $boxw - $task.Length - 5)))$b│$r$esc[K`n")
            [void]$sb.Append("    $b╰$bar╯$r$esc[K`n")
            [void]$sb.Append("$esc[K`n")
            [void]$sb.Append("    $d$(T zm_hint)$r$esc[K`n")
            [void]$sb.Append("    $d$(T zm_keys)$r$esc[K`n")
            [void]$sb.Append("$esc[J$esc[?2026l")
            Write-LotusRaw $sb.ToString()
            # (the keys of the tests: a queue that ran dry ends the game, it does not wait for the time)
            $key = if ($script:KeyQueueActive -and -not $script:KeyQueue.Count) { 'esc' } else { Read-LotusPetKey 0.05 }
            if ($script:PetInt) { return 130 }
            # a digit goes where the cursor is: the last digit first, then ← and the ones before it
            if ($key -cmatch '^[0-9]\z') { if ($typed.Length -lt 7) { $typed = $typed.Insert($pos, $key); $pos++ } }
            elseif ($key -ceq 'back') { if ($pos -gt 0) { $typed = $typed.Remove($pos - 1, 1); $pos-- } }
            elseif ($key -ceq 'left') { if ($pos -gt 0) { $pos-- } }
            elseif ($key -ceq 'right') { if ($pos -lt $typed.Length) { $pos++ } }
            elseif ($key -ceq 'home') { $pos = 0 }
            elseif ($key -ceq 'end') { $pos = $typed.Length }
            elseif ($key -ceq 'esc') { $ended = 1; break }
            if ($typed -and [long]$typed -eq $script:ZmA) {
                $script:ZmScore++
                $typed = ''; $pos = 0
                New-LotusZmProblem $Level
                $eatUntil = $clock.Elapsed.TotalSeconds + 0.3
            }
        }
        $ended
    } finally { Exit-LotusPetScreen }
}

# After a game: the score, the record, the pets eat → $true: Enter plays again, $false: Esc
function script:Show-LotusZmAfter {
    param([string]$Level, [int]$Secs, [int]$Score, [int]$Ended)
    $best = Save-LotusZmRecord $Level $Secs $Score
    Write-LotusRaw "$([char]27)[H$([char]27)[2J"
    Write-LotusHero (T zm_title) (Format-LotusPetText (T zm_sub) @([string]$Secs, (T "zm_$Level")))
    $k = "$([char]27)[1;$($script:C['key'])m"; $d = E dim; $r = $script:R
    $text = if ($Ended) { T zm_stopped } else { T zm_over }
    $text += "  $k$((T zm_result).Replace('%s', [string]$Score))$r"
    if ($Score -gt $best -and $best -gt 0) { $text += "  $k$(T zm_new_best)$r" }
    elseif ($best -gt 0) { $text += "  $d$((T zm_best).Replace('%s', [string]$best))$r" }
    Write-LotusLine "    $text"
    Write-LotusLine ''
    if ($script:PetN.Count) {
        $idx = Get-Random -Maximum $script:PetN.Count
        $snack = Get-LotusPetSnack (Get-LotusPetKind $idx)
        [void](Enter-LotusPetScreen)
        try {
            $script:PetDrawn = 0
            $mins = Invoke-LotusZmFeed $Score $Level
            if ($null -ne $mins) {
                $key = if ($script:PetN.Count -gt 1) { 'zm_fed_n' } else { 'zm_fed_1' }
                $bites = if ($Score -eq 1) { T zm_bite } else { (T zm_bites).Replace('%s', [string]$Score) }
                $said = Format-LotusPetText (T $key) @($bites, (Format-LotusZmDuration $mins[$idx]))
                if ($script:PetTty) { Show-LotusPetMeal $idx $snack }
                Show-LotusPetSpeech $idx $said 'happy'
            } else {
                Show-LotusPetSpeech $idx (T zm_none) 'idle'
            }
        } finally { Exit-LotusPetScreen }
    } else {
        Write-LotusDim "  $(T zm_nopets)"
    }
    Write-LotusLine ''
    Write-LotusDim "  $(T zm_again)"
    while ($true) {
        $key = Read-LotusKey
        if ($key -ceq 'enter') { return $true }
        if ($key -ceq 'quit') { return $false }
    }
}
