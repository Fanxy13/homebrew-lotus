# /pets on Windows – little pixel friends that live in the terminal (feature "pets", up to 3), a port of lib/cmd/pets.zsh.
#   /pets                    adopt, talk, feed, rename, personality, settings
#   <name> [message]         a pet's name typed in the shell talks to it (→ lotus pet <name> …)
#   /feed [name]             feed a pet – pets get hungry after half a day (they never get ill)
#   /zetamac                 the math game: every right answer feeds your pets (Public/zetamac.ps1)
#   /help                    your pet asks where you need help and shows the commands
#   lotus pets add [file]    your own kind of pet from the prompt on the website (default: the clipboard)
# The same files as the zsh engine: the kinds of pets are data/pets/*.pet and your own in <conf>/pets/ – read as data,
# never run; their drawings keep ASCII and block pixels (▀ … ▟) only. Adopted pets live in <conf>/pets.tsv, hunger and
# what they remember in the state folder. Every lotus command reads them again (another window may have fed a pet).
# On Windows the pets think with the AI of /ai (Public/ai.ps1) – or answer with short phrases.

function script:Invoke-Lotuspets {
    param([string]$Cmd, [string[]]$Rest)
    Import-LotusLangGroup pets
    $first = if ($Rest.Count) { $Rest[0] } else { '' }
    $more = [string[]]@($Rest | Select-Object -Skip 1)
    switch -CaseSensitive ($Cmd) {
        'pet' { return Invoke-LotusPetTalk $first $more }
        'feed' { return Invoke-LotusPetFeed $first }
        'zetamac' { Import-LotusCommand zetamac; return Invoke-LotusZetamac ([string[]]@($Rest)) }
    }
    switch -CaseSensitive ($first) {
        'add' { return Add-LotusPetKind $(if ($more.Count) { $more[0] } else { '' }) }
        'adopt' { return Invoke-LotusPetsAdopt $more }
        'greet' { Show-LotusPetGreeting; return (St 0) }
        '' { return Show-LotusPetsScreen }
        'list' { return Show-LotusPetsScreen }
        default { return Invoke-LotusPetTalk $first $more }
    }
}

# ── Kinds of pets (.pet files) ────────────────────────────────

$script:PetKinds = [System.Collections.Generic.List[string]]::new()
$script:PetInfo = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
$script:PetArt = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
$script:PetAW = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
$script:PetAH = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)

# Your pets: names, kinds, personalities, adopted (epoch, as text); hunger by lowercase name
$script:PetN = [System.Collections.Generic.List[string]]::new()
$script:PetK = [System.Collections.Generic.List[string]]::new()
$script:PetP = [System.Collections.Generic.List[string]]::new()
$script:PetT = [System.Collections.Generic.List[string]]::new()
$script:PetFed = [System.Collections.Generic.Dictionary[string, long]]::new([System.StringComparer]::Ordinal)
$script:PetCount = [System.Collections.Generic.Dictionary[string, long]]::new([System.StringComparer]::Ordinal)

$script:PetDrawn = 0        # lines of the last block on screen (Write-LotusPetPaint draws over them)
$script:PetTty = $false     # a pet is on screen: keys are read, line wrap and the cursor are off
$script:PetInt = $false     # Ctrl-C was pressed while a pet was on screen
$script:PetBrain = ''       # ai · off · none, once asked
$script:PetKnow = $null
$script:PetCmds = $null
$script:PetReq = $null      # the AI's answer on its way (Public/ai.ps1)
$script:PetHour = $null     # the hour of the day, for the tests (else the clock's)

# Everything again from the files: the kinds, your pets, their hunger
function script:Initialize-LotusPets {
    $script:PetKinds.Clear(); $script:PetInfo.Clear(); $script:PetArt.Clear(); $script:PetAW.Clear(); $script:PetAH.Clear()
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in @((Join-Path (Get-LotusRoot) 'data/pets'), (Join-Path $script:Paths.Conf 'pets'))) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $names = @(Get-ChildItem -LiteralPath $dir -Filter '*.pet' -File | Where-Object { $_.Extension -ceq '.pet' } | ForEach-Object Name)
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
        foreach ($n in $names) { $files.Add((Join-Path $dir $n)) }
    }
    foreach ($f in $files) {
        $r = Read-LotusPetFile $f
        if ($r.Code) { Write-LotusLog WARN pets "Not a pet: $f ($($r.Msg))" }
    }
    Read-LotusPets
    $script:PetBrain = ''; $script:PetKnow = $null; $script:PetCmds = $null
}
# (the setup wizard asks for the kinds when it starts)
function script:Import-LotusPetKinds { Initialize-LotusPets }

# Reads one .pet file – as data, nothing in it is run. Drawings keep plain ASCII and the block characters ▀ … ▟ (pixel
# sprites) only; other values lose control characters. → Lr 0 <kind>, or Lr 1 with what is wrong
function script:Read-LotusPetFile {
    param([string]$File)
    $item = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer) { return (Lr 1 $null 'cannot read the file') }
    if ($item.Length -ge 16000) { return (Lr 1 $null 'the file is too big') }
    try { $text = [System.IO.File]::ReadAllText($item.FullName, [System.Text.UTF8Encoding]::new($false)) } catch { return (Lr 1 $null 'cannot read the file') }
    $info = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $art = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $frame = ''
    foreach ($raw in ($text -replace '\n+\z', '') -split "`n") {
        $line = $raw.TrimEnd("`r").Replace("`t", '  ')
        if ($line -cmatch '^\[[a-z]+\]\z') { $frame = $line.Substring(1, $line.Length - 2); $art[$frame] = ''; continue }
        if (-not $frame) {
            $line = $line -replace '^[\s-]+', ''
            if ($line -cnotmatch '^[a-z_]+:') { continue }       # comments, empty lines
            $i = $line.IndexOf(':')
            $info[$line.Substring(0, $i)] = ($line.Substring($i + 1) -replace '\p{Cc}', '').Trim()
        } else {
            $art[$frame] += ($line -replace '[^\x20-\x7E▀-▟]', '').TrimEnd() + "`n"
        }
    }
    $sp = if ($info.ContainsKey('species')) { $info['species'].ToLowerInvariant() } else { '' }
    if ($sp -cnotmatch '^[a-z][a-z0-9-]*\z' -or $sp.Length -gt 16) { return (Lr 1 $null 'species: is missing') }
    if (-not $art.ContainsKey('idle') -or -not ($art['idle'] -replace '\s', '')) { return (Lr 1 $null 'the drawing [idle] is missing') }
    $w = 0; $h = 0
    foreach ($fr in @($art.Keys)) {
        $a = $art[$fr] -replace '\n+\z', ''
        $art[$fr] = $a
        $rows = $a -split "`n"
        if ($rows.Count -gt 8) { return (Lr 1 $null "[$fr] is higher than 8 lines") }
        foreach ($row in $rows) {
            if ($row.Length -gt 24) { return (Lr 1 $null "[$fr] is wider than 24 characters") }
            if ($row.Length -gt $w) { $w = $row.Length }
        }
        if ($rows.Count -gt $h) { $h = $rows.Count }
    }
    if (-not $script:PetKinds.Contains($sp)) { $script:PetKinds.Add($sp) }
    foreach ($key in $info.Keys) { $script:PetInfo["$sp,$key"] = Cut $info[$key] 300 }
    foreach ($fr in $art.Keys) { $script:PetArt["$sp,$fr"] = $art[$fr] }
    $script:PetAW[$sp] = $w; $script:PetAH[$sp] = $h; $script:PetInfo["$sp,file"] = $item.FullName
    Lr 0 $sp
}

function script:Get-LotusPetInfo {
    param([string]$Kind, [string]$Key)
    $v = $null
    if ($script:PetInfo.TryGetValue("$Kind,$Key", [ref]$v)) { $v } else { '' }
}
function script:Get-LotusPetArtText {
    param([string]$Kind, [string]$Frame)
    $v = $null
    if ($script:PetArt.TryGetValue("$Kind,$Frame", [ref]$v) -and $v) { return $v }
    if ($script:PetArt.TryGetValue("$Kind,idle", [ref]$v)) { $v } else { '' }
}
# The rows of a drawing as they are, and the width of the widest drawing of a kind (the setup wizard draws them)
function script:Get-LotusPetArtLines { param([string]$Kind, [string]$Frame = 'idle') (Get-LotusPetArtText $Kind $Frame) -split "`n" }
function script:Get-LotusPetArtWidth { param([string]$Kind) $v = 0; if ($script:PetAW.TryGetValue($Kind, [ref]$v)) { $v } else { 0 } }
function script:Get-LotusPetArtHeight { param([string]$Kind) $v = 0; if ($script:PetAH.TryGetValue($Kind, [ref]$v)) { $v } else { 0 } }

# The name of a kind in the interface language
function script:Get-LotusPetKindLabel {
    param([string]$Kind)
    $v = Get-LotusPetInfo $Kind "label_$($script:S['LOTUS_LANG'])"
    if (-not $v) { $v = Get-LotusPetInfo $Kind 'label' }
    if (-not $v) { $v = [cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($Kind) }
    $v
}
# A few words about a kind, in the interface language
function script:Get-LotusPetKindAbout {
    param([string]$Kind)
    $v = Get-LotusPetInfo $Kind "about_$($script:S['LOTUS_LANG'])"
    if (-not $v) { $v = Get-LotusPetInfo $Kind 'about' }
    if (-not $v) { $v = Cut (Get-LotusPetInfo $Kind 'personality') 48 }
    $v
}

# ── Your pets ─────────────────────────────────────────────────

# A name: 1 to 16 letters, digits, _ and -, starting with a letter
function script:Test-LotusPetName {
    param([AllowEmptyString()][AllowNull()][string]$Name)
    [bool]($Name -and $Name.Length -le 16 -and $Name -match '^\p{L}[\p{L}\p{Nd}_-]*\z')
}

function script:Read-LotusPets {
    $script:PetN.Clear(); $script:PetK.Clear(); $script:PetP.Clear(); $script:PetT.Clear(); $script:PetFed.Clear(); $script:PetCount.Clear()
    $now = [string](Get-LotusEpoch)
    $text = Read-LotusFile (Join-Path $script:Paths.Conf 'pets.tsv')
    if ($null -ne $text) {
        foreach ($line in $text -split "`n") {
            if (-not $line -or $line.StartsWith('#')) { continue }
            $f = $line -split "`t"
            if (-not (Test-LotusPetName $f[0])) { continue }
            if ($script:PetN.Count -ge 3) { break }
            $script:PetN.Add($f[0])
            $script:PetK.Add($(if ($f.Count -gt 1 -and $f[1]) { $f[1] } else { 'cat' }))
            $script:PetP.Add($(if ($f.Count -gt 2) { $f[2] } else { '' }))
            $script:PetT.Add($(if ($f.Count -gt 3 -and $f[3]) { $f[3] } else { $now }))
        }
    }
    $state = Read-LotusFile (Join-Path $script:Paths.State 'pets.tsv')
    if ($null -ne $state) {
        foreach ($line in $state -split "`n") {
            $f = $line -split "`t"
            $fed = 0L
            if ($f.Count -lt 2 -or $f[1] -notmatch '^\d+\z' -or -not [long]::TryParse($f[1], [ref]$fed)) { continue }
            $low = $f[0].ToLowerInvariant()
            $script:PetFed[$low] = $fed
            $script:PetCount[$low] = if ($f.Count -gt 2) { Get-LotusInt $f[2] 0 } else { 0 }
        }
    }
}

# The names of your pets (the setup wizard asks)
function script:Get-LotusPets { Initialize-LotusPets; $script:PetN.ToArray() }

function script:Save-LotusPets {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("# Lotus pets: name, kind, personality (empty: the usual one of the kind), adopted (epoch). Edit with /pets.`n")
    for ($i = 0; $i -lt $script:PetN.Count; $i++) {
        [void]$sb.Append("$($script:PetN[$i])`t$($script:PetK[$i])`t$($script:PetP[$i] -replace '\p{Cc}', ' ')`t$($script:PetT[$i])`n")
    }
    Write-LotusFile (Join-Path $script:Paths.Conf 'pets.tsv') $sb.ToString()
    Save-LotusPetState
    Write-LotusLog INFO pets "Pets: $(if ($script:PetN.Count) { $script:PetN -join ', ' } else { 'none' })"
}

function script:Save-LotusPetState {
    $now = @($script:PetN | ForEach-Object { $_.ToLowerInvariant() })
    $sb = [System.Text.StringBuilder]::new()
    foreach ($low in $script:PetFed.Keys) {
        if ($now -cnotcontains $low) { continue }
        $c = 0L; [void]$script:PetCount.TryGetValue($low, [ref]$c)
        [void]$sb.Append("$low`t$($script:PetFed[$low])`t$c`n")
    }
    try { Write-LotusFile (Join-Path $script:Paths.State 'pets.tsv') $sb.ToString() } catch { Write-LotusLog WARN pets "The pets' state could not be saved: $_" }
}

# A pet by its name (case does not matter) → its index, or -1
function script:Find-LotusPet {
    param([string]$Name)
    $want = ([string]$Name).ToLowerInvariant()
    for ($i = 0; $i -lt $script:PetN.Count; $i++) { if ($script:PetN[$i].ToLowerInvariant() -ceq $want) { return $i } }
    -1
}

# The kind of a pet; one whose file is gone becomes a cat again
function script:Get-LotusPetKind {
    param([int]$Idx)
    $k = $script:PetK[$Idx]
    if ($script:PetArt.ContainsKey("$k,idle")) { $k } else { 'cat' }
}

# When a pet ate last (epoch): what it ate, else when it moved in
function script:Get-LotusPetFed {
    param([int]$Idx)
    $v = 0L
    if ($script:PetFed.TryGetValue($script:PetN[$Idx].ToLowerInvariant(), [ref]$v)) { return $v }
    $t = [string]$script:PetT[$Idx]
    if ($t -match '^\d+\z' -and [long]::TryParse($t, [ref]$v)) { return $v }
    Get-LotusEpoch
}
# Hours since the last meal (below 0 after a big one: /zetamac moves the meal into the future)
function script:Get-LotusPetHours { param([int]$Idx) [long][Math]::Truncate(((Get-LotusEpoch) - (Get-LotusPetFed $Idx)) / 3600) }
function script:Get-LotusPetHour { if ($null -ne $script:PetHour) { [int]$script:PetHour } else { [datetime]::Now.Hour } }

# asleep (11 pm – 6 am) · starving · hungry · happy
function script:Get-LotusPetMood {
    param([int]$Idx, [string]$Awake)
    $hour = Get-LotusPetHour
    $h = Get-LotusPetHours $Idx
    if (($hour -ge 23 -or $hour -lt 6) -and $Awake -cne 'awake') { 'asleep' }
    elseif ($h -ge 24) { 'starving' }
    elseif ($h -ge 12) { 'hungry' }
    else { 'happy' }
}

# One short line about a pet
function script:Get-LotusPetStatus {
    param([int]$Idx)
    $mood = Get-LotusPetMood $Idx
    if ($mood -ceq 'starving') { return (T pt_starving) }
    if ($mood -ceq 'hungry') { return (T pt_hungry) }
    # asleep, or full: hungry 12 hours after a meal – later after a big one (/zetamac)
    $h = Get-LotusPetHours $Idx
    $text = if ($h -ge 24) { T pt_starving } elseif ($h -ge 12) { T pt_hungry } else {
        $left = [long][Math]::Truncate(((Get-LotusPetFed $Idx) + 43200 - (Get-LotusEpoch) + 1800) / 3600)
        (T pt_full_h).Replace('%s', [string][Math]::Max(1, $left))
    }
    if ($mood -ceq 'asleep') { $text += " · $(T pt_asleep)" }
    $text
}

# Each pet keeps its own color: the theme's logo, greeting and key colors
function script:Get-LotusPetColor {
    param([int]$Idx)
    $role = @('logo', 'salute', 'key')[[Math]::Min([Math]::Max($Idx, 0), 2)]
    "$([char]27)[$($script:C[$role])m"
}

# %s after %s: the first one gets the first value
function script:Format-LotusPetText {
    param([string]$Text, [string[]]$Values)
    foreach ($v in $Values) {
        $i = $Text.IndexOf('%s')
        if ($i -lt 0) { break }
        $Text = $Text.Substring(0, $i) + $v + $Text.Substring($i + 2)
    }
    $Text
}

# What a pet eats, as it flies in: printable ASCII, up to 6 characters
function script:Get-LotusPetSnack {
    param([string]$Kind)
    $s = Get-LotusPetInfo $Kind 'snack'
    if (-not $s) { $s = 'o' }
    Cut ($s -replace '[^\x20-\x7E]', '') 6
}

# ── Drawing ───────────────────────────────────────────────────

# The drawing of a pet, every line as wide as the widest drawing of its kind and the feet on the ground (shorter
# drawings get empty lines on top)
function script:Get-LotusPetArt {
    param([int]$Idx, [string]$Frame)
    $kind = Get-LotusPetKind $Idx
    $rows = (Get-LotusPetArtText $kind $Frame) -split "`n"
    $w = Get-LotusPetArtWidth $kind
    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = $rows.Count; $i -lt (Get-LotusPetArtHeight $kind); $i++) { $out.Add([string]::new(' ', $w)) }
    foreach ($row in $rows) { $out.Add((PadR $row $w)) }
    , $out.ToArray()
}

# Word wrap; very long words are cut into pieces
function script:Split-LotusPetWords {
    param([AllowEmptyString()][string]$Text, [int]$Width)
    $Width = [Math]::Max(1, $Width)
    $out = [System.Collections.Generic.List[string]]::new()
    $line = ''
    foreach ($word in ([string]$Text -split '[ \t\n\r\0]+')) {
        $wd = $word
        while ($wd.Length -gt $Width) {
            if ($line) { $out.Add($line); $line = '' }
            $out.Add($wd.Substring(0, $Width)); $wd = $wd.Substring($Width)
        }
        if (-not $wd) { continue }
        if ($line.Length -and $line.Length + $wd.Length + 1 -gt $Width) { $out.Add($line); $line = $wd }
        elseif ($line) { $line += " $wd" }
        else { $line = $wd }
    }
    if ($line) { $out.Add($line) }
    , $out.ToArray()
}

# Width for the speech bubble next to a pet
function script:Get-LotusPetBubbleWidth {
    param([int]$Idx)
    $aw = [Math]::Max((Get-LotusPetArtWidth (Get-LotusPetKind $Idx)), $script:PetN[$Idx].Length)
    $cols = Get-LotusColumns
    if ($cols -le 0) { $cols = 80 }
    [Math]::Max(12, [Math]::Min(54, $cols - $aw - 12))
}

# A pet with a speech bubble → its lines
#   Get-LotusPetBlock <pet> <drawing> <characters shown, -1 = all> <style> <lines>
#   style: bubble · plain (the lines without a bubble, e.g. a snack flying in) · none
function script:Get-LotusPetBlock {
    param([int]$Idx, [string]$Frame, [int]$Shown = -1, [string]$Style = 'none', [string[]]$Text = @())
    $art = Get-LotusPetArt $Idx $Frame
    $name = $script:PetN[$Idx]
    $ah = $art.Count
    $colw = [Math]::Max((Get-LotusPetArtWidth (Get-LotusPetKind $Idx)), $name.Length)
    $c = Get-LotusPetColor $Idx; $b = E border; $d = E dim; $y = E key2; $r = "$([char]27)[0m"
    $bub = [System.Collections.Generic.List[string]]::new()
    if ($Style -ceq 'bubble' -and $Text.Count) {
        $iw = 0
        foreach ($t in $Text) { if ($t.Length -gt $iw) { $iw = $t.Length } }
        $left = if ($Shown -lt 0) { 999999 } else { $Shown }
        $bar = Get-LotusLine ($iw + 2)
        $bub.Add("  $b╭$bar╮$r")
        for ($k = 0; $k -lt $Text.Count; $k++) {
            $part = Cut $Text[$k] ([Math]::Max(0, $left))
            $left -= $Text[$k].Length
            if ($k -eq 0) { $bub.Add(" $b─┤$r $(PadR $part $iw) $b│$r") }
            else { $bub.Add("  $b│$r $(PadR $part $iw) $b│$r") }
        }
        $bub.Add("  $b╰$bar╯$r")
    } elseif ($Style -ceq 'plain') {
        foreach ($t in $Text) { $bub.Add("  $y$t$r") }
        # next to the middle of the drawing
        for ($k = 0; $k -lt [Math]::Truncate(($ah - 1) / 2); $k++) { $bub.Insert(0, '') }
    }
    $rows = [Math]::Max($ah + 1, $bub.Count)
    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $rows; $i++) {
        $line = if ($i -lt $ah) { "$c$(PadR $art[$i] $colw)$r" }
        elseif ($i -eq $ah) { "$d$(PadR (PadL $name ([Math]::Truncate(($colw + $name.Length) / 2))) $colw)$r" }
        else { [string]::new(' ', $colw) }
        $out.Add($line + $(if ($i -lt $bub.Count) { $bub[$i] } else { '' }))
    }
    , $out.ToArray()
}

# Draws a block where the last one was (the cursor stays below it). Blocks only grow, so the lines above never move –
# that works at the bottom of the window too.
function script:Write-LotusPetPaint {
    param([string[]]$Lines)
    $esc = [char]27
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("$esc[?2026h")
    if ($script:PetDrawn) { [void]$sb.Append("$esc[$($script:PetDrawn)A") }
    foreach ($line in $Lines) { [void]$sb.Append("`r  $line$esc[0m$esc[K`n") }
    for ($i = $Lines.Count; $i -lt $script:PetDrawn; $i++) { [void]$sb.Append("`r$esc[K`n") }
    if ($Lines.Count -gt $script:PetDrawn) { $script:PetDrawn = $Lines.Count }
    [void]$sb.Append("$esc[?2026l")
    Write-LotusRaw $sb.ToString()
}

# A block once (no animation, no terminal needed)
function script:Write-LotusPetLines {
    param([string[]]$Lines)
    if (-not $Lines.Count) { return }
    $r = "$([char]27)[0m"
    Write-LotusLine (($Lines | ForEach-Object { "  $_$r" }) -join "`n")
}

# While a pet is on screen: line wrap and the cursor are off, Ctrl-C is a key (it sets $script:PetInt). Everything comes
# back in Exit-LotusPetScreen – the callers run it in a finally block.
function script:Enter-LotusPetScreen {
    if ($script:PetTty) { return $true }
    if (-not ((Test-LotusOutTty) -and (Test-LotusTty))) { return $false }
    $script:PetTty = $true
    $script:PetInt = $false
    Enter-LotusKeys
    Write-LotusRaw "$([char]27)[?7l$([char]27)[?25l"
    $true
}
function script:Exit-LotusPetScreen {
    if (-not $script:PetTty) { return }
    Write-LotusRaw "$([char]27)[0m$([char]27)[?7h$([char]27)[?25h"
    Exit-LotusKeys
    $script:PetTty = $false
}

# One key while a pet is on screen (a timeout lets the animation go on). With the keys of the tests a queue that ran dry
# lets the time pass; without a timeout it counts as esc.
function script:Read-LotusPetKey {
    param([double]$Timeout = -1)
    if ($script:KeyQueueActive -and -not $script:KeyQueue.Count -and $Timeout -ge 0) { return 'timeout' }
    $k = Read-LotusKeyX $Timeout
    if ($k -ceq 'interrupt') { $script:PetInt = $true }
    $k
}

# A pet says something: the words appear one after another while its mouth moves
function script:Show-LotusPetSpeech {
    param([int]$Idx, [AllowEmptyString()][string]$Text, [string]$Last = 'idle')
    $lines = Split-LotusPetWords $Text (Get-LotusPetBubbleWidth $Idx)
    if (-not $script:PetTty) { Write-LotusPetLines (Get-LotusPetBlock $Idx $Last -1 'bubble' $lines); return }
    $total = ($lines -join '').Length
    $step = [Math]::Truncate($total / 80) + 1
    $shown = 0; $tick = 0
    while ($shown -lt $total) {
        $shown = [Math]::Min($total, $shown + $step)
        $fr = if ([Math]::Truncate($tick / 2) % 2) { 'idle' } else { 'talk' }
        Write-LotusPetPaint (Get-LotusPetBlock $Idx $fr $shown 'bubble' $lines)
        $tick++
        if ((Read-LotusPetKey 0.025) -cne 'timeout') { $shown = $total }
        if ($script:PetInt) { break }
    }
    Write-LotusPetPaint (Get-LotusPetBlock $Idx $Last -1 'bubble' $lines)
}

# A snack flies in, the pet eats it
function script:Show-LotusPetMeal {
    param([int]$Idx, [string]$Snack)
    for ($i = 14; $i -ge 0 -and -not $script:PetInt; $i -= 2) {
        Write-LotusPetPaint (Get-LotusPetBlock $Idx 'idle' -1 'plain' @("$([string]::new(' ', $i))$Snack"))
        [void](Read-LotusPetKey 0.05)
    }
    for ($i = 0; $i -lt 6 -and -not $script:PetInt; $i++) {
        $fr = if ($i % 2) { 'happy' } else { 'eat' }
        Write-LotusPetPaint (Get-LotusPetBlock $Idx $fr -1 'plain' @($(if ($fr -ceq 'eat') { 'nom' } else { '' })))
        [void](Read-LotusPetKey 0.16)
    }
}

# ── Thinking ──────────────────────────────────────────────────

# Who answers for the pets → 'ai', or $null when nothing can. Apple Intelligence is a Mac's: on Windows the pets think
# with the AI of /ai (a settings file from a Mac that says "apple" means that too).
function script:Get-LotusPetBrain {
    if ($script:PetBrain) { return $(if ($script:PetBrain -ceq 'ai') { 'ai' } else { $null }) }
    $script:PetBrain = 'none'
    if ([string]$script:S['LOTUS_PET_BRAIN'] -ceq 'off') { $script:PetBrain = 'off'; return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/ai.ps1'))) { return $null }
    Import-LotusCommand ai
    if (-not (Get-LotusAiProvider)) { return $null }
    $script:PetBrain = 'ai'
    'ai'
}

# The answer starts on its way ($script:PetReq); Wait-LotusPetThought waits for it
function script:Start-LotusPetThought {
    param([string]$System, [string]$Prompt)
    $script:PetReq = Start-LotusAiRequest -System $System -Prompt $Prompt -MaxTokens 400
}

# Waits for the answer while the pet thinks ("· · ·") → the clean text; '' when it was stopped (Esc) or is empty
function script:Wait-LotusPetThought {
    param([int]$Idx)
    $dots = @('·', '· ·', '· · ·')
    $req = $script:PetReq
    $t = 0
    while ($req -and -not (Update-LotusAiRequest $req)) {
        $fr = if ($t % 14 -eq 6) { 'blink' } elseif ($t % 14 -in 10, 11) { 'wag' } else { 'idle' }
        if ($script:PetTty) {
            Write-LotusPetPaint (Get-LotusPetBlock $Idx $fr -1 'bubble' @($dots[$t % 3]))
            $k = Read-LotusPetKey 0.15
            if ($script:KeyQueueActive) { Start-Sleep -Milliseconds 20 }
            if ($k -cin 'esc', 'interrupt') { Stop-LotusAiRequest $req; return '' }
        } else { Start-Sleep -Milliseconds 150 }
        if (++$t -gt 600) { Stop-LotusAiRequest $req; break }
    }
    ConvertTo-LotusPetText $(if ($req) { [string]$req.Text } else { '' }) $script:PetN[$Idx]
}

# Only plain words get on screen: no escape sequences, no control characters, no markdown
function script:ConvertTo-LotusPetText {
    param([AllowEmptyString()][string]$Text, [string]$Name)
    $t = $Text -replace "$([char]27)\[[0-9;?]*[@-~]", ''
    $t = $t -replace '\p{Cc}', ' '
    $t = $t -replace '\*\*|`|##', ''
    $t = ($t -replace ' {2,}', ' ').Trim()
    if ($Name -and $t.StartsWith("$($Name):", [System.StringComparison]::OrdinalIgnoreCase)) { $t = $t.Substring($Name.Length + 1).TrimStart() }
    if ($t.Length -ge 2 -and $t.StartsWith('"') -and $t.EndsWith('"')) { $t = $t.Substring(1, $t.Length - 2) }
    if ($t.Length -gt 320) { $t = $t.Substring(0, 317) + '…' }
    $t
}

# How a pet is: personality, mood, time, language → instructions for the AI (<mode> help: /help lists the commands
# itself; a chat gets what the pet knows about Lotus)
function script:Get-LotusPetInstructions {
    param([int]$Idx, [string]$Mode, [string]$Extra)
    $kind = Get-LotusPetKind $Idx
    $name = $script:PetN[$Idx]
    $owner = if ($script:S['LOTUS_NAME']) { $script:S['LOTUS_NAME'] } else { 'my human' }
    $label = Get-LotusPetInfo $kind 'label'; if (-not $label) { $label = $kind }
    $label = $label.ToLower()
    $persona = if ($script:PetP[$Idx]) { $script:PetP[$Idx] } else { Get-LotusPetInfo $kind 'personality' }
    $sound = Get-LotusPetInfo $kind 'sound'; if (-not $sound) { $sound = 'hello' }
    $food = Get-LotusPetInfo $kind 'food'; if (-not $food) { $food = 'treats' }
    $hour = Get-LotusPetHour
    $part = if ($hour -lt 12) { 'morning' } elseif ($hour -lt 18) { 'afternoon' } elseif ($hour -lt 23) { 'evening' } else { 'night' }
    $lang = switch ([string]$script:S['LOTUS_LANG']) { 'de' { 'German' } 'fr' { 'French' } 'es' { 'Spanish' } default { 'English' } }
    $mood = Get-LotusPetMood $Idx 'awake'
    $know = if ($Mode -ceq 'help') { '' } else { Get-LotusPetKnowledge }
    $where = if ($IsMacOS) { 'the macOS terminal' } elseif ($IsLinux) { 'the terminal' } else { 'the Windows terminal' }
    $text = "You are $name, a little $label who lives in Lotus, a start screen in $where. You belong to $owner and you like $owner a lot.`n" +
    "Your personality: $persona.`n" +
    "Talk like a $label would: short, warm, playful sentences, and now and then you say `"$sound`". It is $part."
    if ($mood -cin 'starving', 'hungry') { $text += " You are hungry and would love some $food – you may say so, or that $owner can type /feed $($name.ToLower()) or play /zetamac for a big meal." }
    if ($know) { $text += "`nWhat you know about Lotus: $know" }
    $text += "`nRules: reply directly to what $owner just said – answer the question if there is one. Use 1 or 2 short sentences, at most 35 words. " +
    'Plain text only: no emojis, no lists, no markdown. You cannot run commands or change files and never say you did. ' +
    "When $owner asks about Lotus or how to do something with it, answer from what you know and name the command; when you do not know it, suggest typing /help. " +
    "Do not bring Lotus up when $owner talks about something else. Always answer in $lang."
    if ($Extra) { $text += "`n$Extra" }
    $text
}

# What a pet knows about Lotus: data/pets/lotus.windows.tsv, the lines of the features that are on (lotus.tsv is the
# Mac's: its commands are not all here)
function script:Get-LotusPetKnowledge {
    if ($null -ne $script:PetKnow) { return $script:PetKnow }
    $know = foreach ($f in Read-LotusTsv 'pets/lotus.windows') {
        if ($f.Count -ge 2 -and (Test-LotusFeature $f[0])) { Convert-LotusHere $f[1] }
    }
    $script:PetKnow = @($know) -join ' '
    $script:PetKnow
}

# What a pet remembers: the last three exchanges
function script:Get-LotusPetMemoryFile { param([int]$Idx) Join-Path $script:Paths.State "pets/$($script:PetN[$Idx].ToLowerInvariant()).mem" }
function script:Get-LotusPetMemory {
    param([int]$Idx)
    $text = Read-LotusFile (Get-LotusPetMemoryFile $Idx)
    if (-not $text) { return '' }
    @($text.TrimEnd("`n") -split "`n" | Select-Object -Last 6) -join "`n"
}
function script:Save-LotusPetMemory {
    param([int]$Idx, [string]$Said, [string]$Answer)
    $file = Get-LotusPetMemoryFile $Idx
    $lines = [System.Collections.Generic.List[string]]::new()
    $text = Read-LotusFile $file
    if ($text) { foreach ($l in $text.TrimEnd("`n") -split "`n") { $lines.Add($l) } }
    $who = if ($script:S['LOTUS_NAME']) { $script:S['LOTUS_NAME'] } else { 'Human' }
    $lines.Add("$($who): $($Said -replace '\p{Cc}', ' ')")
    $lines.Add("$($script:PetN[$Idx]): $($Answer -replace '\p{Cc}', ' ')")
    try { Write-LotusFile $file ((@($lines | Select-Object -Last 6) -join "`n") + "`n") } catch { Write-LotusLog WARN pets "A pet's memory could not be saved: $_" }
}

# Short phrases, for pets without an AI: hi · reply
function script:Get-LotusPetPhrase {
    param([int]$Idx, [string]$What)
    $owner = if ($script:S['LOTUS_NAME']) { $script:S['LOTUS_NAME'] } else { 'you' }
    $kind = Get-LotusPetKind $Idx
    $sound = Get-LotusPetInfo $kind "sound_$($script:S['LOTUS_LANG'])"
    if (-not $sound) { $sound = Get-LotusPetInfo $kind 'sound' }
    if (-not $sound) { $sound = 'hi' }
    $mood = Get-LotusPetMood $Idx 'awake'
    if ($What -ceq 'hi') {
        if ($mood -cin 'hungry', 'starving') { return (T "pt_hi_hungry_$(Get-Random -Minimum 1 -Maximum 3)").Replace('%s', $script:PetN[$Idx].ToLower()) }
        $hour = Get-LotusPetHour
        $key = if ($hour -lt 11) { 'pt_hi_morning' } elseif ($hour -lt 18) { 'pt_hi_day' } else { 'pt_hi_evening' }
        return (T "$($key)_$(Get-Random -Minimum 1 -Maximum 3)").Replace('%s', $owner)
    }
    $big = [cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($sound.ToLower())
    "$big! $((T pt_noai_ai (T pt_noai)).Replace('%s', $sound))"
}

# A pet answers a message: it thinks (with the AI), then speaks → $false when it was stopped
function script:Invoke-LotusPetAnswer {
    param([int]$Idx, [string]$Message, [string]$Extra)
    if (Get-LotusPetBrain) {
        $sys = Get-LotusPetInstructions $Idx '' $Extra
        $mem = Get-LotusPetMemory $Idx
        $who = if ($script:S['LOTUS_NAME']) { $script:S['LOTUS_NAME'] } else { 'Your human' }
        $prompt = "$(if ($mem) { "Earlier:`n$mem`n`n" })$($who): $Message"
        Write-LotusLog INFO pets "$($script:PetN[$Idx]) thinks ($($script:PetBrain))"
        Start-LotusPetThought $sys $prompt
        $script:PetDrawn = 0
        $answer = Wait-LotusPetThought $Idx
        if (-not $answer) {
            if ($script:PetInt) { return $false }
            $answer = T pt_confused
        }
        Save-LotusPetMemory $Idx $Message $answer
    } else {
        $answer = Get-LotusPetPhrase $Idx 'reply'
        $script:PetDrawn = 0
    }
    Show-LotusPetSpeech $Idx $answer
    -not $script:PetInt
}

# ── Talking: <name> [message] ─────────────────────────────────

function script:Write-LotusPetUnknown {
    param([string]$Want)
    Write-LotusError ((T pt_unknown).Replace('%s', $Want)) '' @((T pt_unknown_hint).Replace('%s', ($script:PetN -join ', ')))
}

function script:Invoke-LotusPetTalk {
    param([string]$Want, [string[]]$Words)
    Initialize-LotusPets
    $msg = @($Words) -join ' '
    if (-not $script:PetN.Count) { Write-LotusError (T pt_nopets) '' @(T pt_nopets_hint); return (St 1) }
    $idx = Find-LotusPet $Want
    if ($idx -lt 0) { Write-LotusPetUnknown $Want; return (St 1) }
    [void](Enter-LotusPetScreen)
    try {
        Write-LotusLine ''
        if ($msg.Trim()) { [void](Invoke-LotusPetAnswer $idx $msg) }
        else {
            # just the name: the pet comes, says hi, and you can chat until an empty line
            $script:PetDrawn = 0
            if ((Get-LotusPetMood $idx) -ceq 'asleep') { Show-LotusPetSpeech $idx (T pt_wake) 'sleep' }
            else { Show-LotusPetSpeech $idx (Get-LotusPetPhrase $idx 'hi') }
            while ($script:PetTty -and -not $script:PetInt) {
                Write-LotusLine ''
                Write-LotusDim "  $(T pt_chat_hint)"
                Write-LotusRaw "$([char]27)[?25h"
                $said = Read-LotusLine (T pt_you) ''
                Write-LotusRaw "$([char]27)[?25l"
                if ($null -eq $said -or -not $said.Trim()) { break }
                Write-LotusLine ''
                if (-not (Invoke-LotusPetAnswer $idx $said)) { break }
            }
        }
    } finally { Exit-LotusPetScreen }
    Write-LotusLine ''
    Write-LotusLog INFO pets "Talked with $($script:PetN[$idx])"
    St 0
}

# ── Feeding: /feed [name] ─────────────────────────────────────

function script:Invoke-LotusPetFeed {
    param([string]$Want)
    Initialize-LotusPets
    if (-not $script:PetN.Count) { Write-LotusError (T pt_nopets) '' @(T pt_nopets_hint); return (St 1) }
    $idx = 0
    if ($Want) {
        $idx = Find-LotusPet $Want
        if ($idx -lt 0) { Write-LotusPetUnknown $Want; return (St 1) }
    } elseif ($script:PetN.Count -gt 1) {
        if (-not (Test-LotusTty)) { Write-LotusError (T pt_which) '' @("/feed $($script:PetN[0].ToLower())"); return (St 1) }
        $pick = Read-LotusChoice (T pt_which) @($script:PetN)
        if ($null -eq $pick) { return (St 0) }
        $idx = $pick - 1
    }
    $kind = Get-LotusPetKind $idx
    $name = $script:PetN[$idx]
    $low = $name.ToLowerInvariant()
    $food = Get-LotusPetInfo $kind "food_$($script:S['LOTUS_LANG'])"
    if (-not $food) { $food = Get-LotusPetInfo $kind 'food' }
    if (-not $food) { $food = 'food' }
    $hours = Get-LotusPetHours $idx
    $count = 0L; [void]$script:PetCount.TryGetValue($low, [ref]$count)
    [void](Enter-LotusPetScreen)
    try {
        Write-LotusLine ''
        $script:PetDrawn = 0
        if ($hours -lt 1 -and $count -gt 0) {
            Show-LotusPetSpeech $idx (Format-LotusPetText (T pt_full_now) @($name, $food)) 'idle'
        } else {
            if ($script:PetTty) { Show-LotusPetMeal $idx (Get-LotusPetSnack $kind) }
            $script:PetFed[$low] = Get-LotusEpoch
            $script:PetCount[$low] = $count + 1
            Save-LotusPetState
            Write-LotusLog INFO pets "$name was fed"
            Show-LotusPetSpeech $idx ((T "pt_thanks_$(Get-Random -Minimum 1 -Maximum 4)").Replace('%s', $food)) 'happy'
        }
    } finally { Exit-LotusPetScreen }
    Write-LotusLine ''
    St 0
}

# ── Greeting on the start screen ──────────────────────────────

# Rows below the cursor, so a greeting never makes the window scroll (99 when the console cannot say)
function script:Get-LotusFreeRows {
    if ($script:KeyQueueActive) { return 99 }
    try {
        if ([Console]::IsOutputRedirected) { return 99 }
        $free = [Console]::WindowTop + [Console]::WindowHeight - [Console]::CursorTop - 1
        if ($free -ge 0) { return $free }
    } catch { }
    99
}

# One pet (a different one every day) says hi below the start screen – only when it fits without scrolling. No AI here:
# it has to be quick. (The Mac's hint for people who updated is left out: Lotus for Windows had its pets from the start.)
function script:Show-LotusPetGreeting {
    if (-not (Test-LotusOutTty)) { return }
    Import-LotusLangGroup pets
    Initialize-LotusPets
    if (-not $script:PetN.Count) { return }
    $free = Get-LotusFreeRows
    $day = [datetime]::Now.DayOfYear
    $idx = $day % $script:PetN.Count
    $mood = Get-LotusPetMood $idx
    if ($mood -ceq 'asleep') { $text = (T pt_hi_night).Replace('%s', $script:PetN[$idx]) }
    else { $text = Get-LotusPetPhrase $idx 'hi' }
    # a tip every few days, and how to call the pet in its first days
    if ($mood -ceq 'happy') {
        $adopted = 0L; [void][long]::TryParse([string]$script:PetT[$idx], [ref]$adopted)
        if ((Get-LotusEpoch) - $adopted -lt 3 * 86400) { $text += " $(T pt_call_tip)" }
        elseif ($day % 3 -eq 0) { $tip = Get-LotusPetTip; if ($tip) { $text += " $(T pt_tip) $tip" } }
    }
    $lines = if ($mood -ceq 'asleep') { Get-LotusPetBlock $idx 'sleep' -1 'none' }
    else { Get-LotusPetBlock $idx 'idle' -1 'bubble' (Split-LotusPetWords $text (Get-LotusPetBubbleWidth $idx)) }
    if ($lines.Count + 1 -gt $free) { return }
    Write-LotusPetLines $lines
    if ($mood -ceq 'asleep') { Write-LotusLine "  $(E dim)$text$($script:R)" }
}

# The commands of the features that are on, as this system has them (the rows of data/commands.tsv, in Windows' words)
function script:Get-LotusPetCommands {
    if ($null -ne $script:PetCmds) { return , $script:PetCmds }
    Import-LotusCommand help
    $script:PetCmds = @(foreach ($c in Get-LotusCommandsHere) {
            if ($c.Hidden -or -not (Test-LotusFeature (Get-LotusFeatureOf (($c.Command -split ' ')[0])))) { continue }
            $c
        })
    , $script:PetCmds
}

# A random command of a feature that is on ("/weather Paris – shows the weather …"), or $null
function script:Get-LotusPetTip {
    $all = @(foreach ($c in Get-LotusPetCommands) {
            if ($c.Usage.StartsWith('lotus') -or $c.Command -ceq 'pet' -or -not $c.Description) { continue }
            "$($c.Example) – $($c.Description.Substring(0, 1).ToLower())$($c.Description.Substring(1))"
        })
    if (-not $all.Count) { return $null }
    $all[(Get-Random -Maximum $all.Count)]
}

# ── Reactions (typos, finished work) ──────────────────────────

# <typo|done>: the whole pet with a speech bubble – the same drawing as everywhere else. Too narrow for the drawing: one
# line of text with the pet's name.
function script:Invoke-LotusPetReact {
    param([string]$What)
    Import-LotusLangGroup pets
    Initialize-LotusPets
    if (-not $script:PetN.Count) { return }
    $idx = Get-Random -Maximum $script:PetN.Count
    if ($What -ceq 'typo') { $frame = 'idle'; $style = 'plain'; $text = (T pt_typo).Replace('%s', $script:PetN[$idx]) }   # told about the pet
    elseif ($What -ceq 'done') { $frame = 'happy'; $style = 'bubble'; $text = T "pt_done_$(Get-Random -Minimum 1 -Maximum 4)" }   # said by the pet
    else { return }
    if ((Get-LotusColumns) -lt (Get-LotusPetArtWidth (Get-LotusPetKind $idx)) + 26) {
        Write-LotusLine "  $(Get-LotusPetColor $idx)$($script:PetN[$idx])$([char]27)[0m: $text"
        return
    }
    Write-LotusPetLines (Get-LotusPetBlock $idx $frame -1 $style (Split-LotusPetWords $text (Get-LotusPetBubbleWidth $idx)))
}

# ── /help with a pet ──────────────────────────────────────────

# The commands that fit a question best, without an AI → indexes in Get-LotusPetCommands (up to 3)
function script:Get-LotusPetRank {
    param([string]$Question)
    $cmds = Get-LotusPetCommands
    # a few words in other languages that lead to the English descriptions
    $alias = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($pair in @('wetter weather', 'météo weather', 'tiempo weather', 'clima weather', 'hintergrund background', 'fond background', 'fondo background',
            'bild image', 'foto image', 'photo image', 'imagen image', 'musik music', 'musique music', 'música music', 'lied song', 'chanson song', 'canción song',
            'öffnen open', 'ouvrir open', 'abrir open', 'suchen search', 'chercher search', 'buscar search', 'herunterladen download', 'télécharger download',
            'descargar download', 'installieren install', 'installer install', 'instalar install', 'einstellungen settings', 'réglages settings', 'ajustes settings',
            'farbe theme', 'couleur theme', 'color theme', 'haustier pet', 'animal pet', 'mascota pet', 'füttern feed', 'nourrir feed', 'alimentar feed',
            'zwischenablage clipboard', 'presse-papiers clipboard', 'portapapeles clipboard', 'ki ai', 'ia ai', 'abkürzung shortcut', 'raccourci shortcut', 'atajo shortcut')) {
        $kv = $pair -split ' '
        $alias[$kv[0]] = $kv[1]
    }
    $stop = @('the', 'and', 'how', 'can', 'what', 'with', 'for', 'ich', 'wie', 'kann', 'was', 'mit', 'und', 'der', 'die', 'das', 'ein', 'eine', 'einen', 'mein', 'meine',
        'comment', 'que', 'pour', 'avec', 'les', 'des', 'une', 'cómo', 'como', 'qué', 'para', 'con', 'los', 'las', 'una')
    $words = [System.Collections.Generic.List[string]]::new()
    foreach ($w in (([string]$Question).ToLower() -replace '[^\p{L}\p{Nd}-]', ' ') -split ' ') {
        if ($w.Length -lt 3 -or $stop -ccontains $w) { continue }
        $words.Add($w)
        $v = $null
        if ($alias.TryGetValue($w, [ref]$v)) { $words.Add($v) }
    }
    $scored = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $cmds.Count; $i++) {
        $c = $cmds[$i]
        $hay = "$($c.Category) $($c.Usage) $($c.Description) $($c.Example)".ToLower()
        $s = 0
        foreach ($w in $words) {
            if ($hay.Contains($w)) { $s += 3 }
            elseif ($w.Length -ge 5 -and $hay.Contains($w.Substring(0, 5))) { $s += 1 }
        }
        if ($s) { $scored.Add([pscustomobject]@{ I = $i; S = $s }) }
    }
    # the best first; of equal ones the first in the table
    $scored | Sort-Object -Property @{ Expression = 'S'; Descending = $true }, @{ Expression = 'I'; Ascending = $true } | Select-Object -First 3 | ForEach-Object { $_.I }
}

# Asks the pet's AI which commands help (by number) and how → @{ Picks (indexes); Text }, or $null when it was
# stopped or did not answer
function script:Get-LotusPetHelpThought {
    param([int]$Idx, [string]$Question)
    $cmds = Get-LotusPetCommands
    $list = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $cmds.Count; $i++) { [void]$list.Append("$($i + 1). $($cmds[$i].Usage) – $($cmds[$i].Description)`n") }
    $owner = if ($script:S['LOTUS_NAME']) { $script:S['LOTUS_NAME'] } else { 'your human' }
    $sys = Get-LotusPetInstructions $Idx 'help' ("You help $owner use Lotus. These are the Lotus commands, numbered:`n$($list.ToString())`n" +
        'Answer in exactly this form. First line: the numbers of the 1 to 3 commands that help most, separated by commas, or 0 when none fits. ' +
        'Then one or two short sentences in your voice that say what to do.')
    $sys = $sys.Replace('at most 35 words', 'at most 40 words')
    $who = if ($script:S['LOTUS_NAME']) { $script:S['LOTUS_NAME'] } else { 'Your human' }
    Start-LotusPetThought $sys "$who asks: $Question"
    $script:PetDrawn = 0
    $all = Wait-LotusPetThought $Idx
    if (-not $all) { return $null }
    # the numbers come first; anything else is what the pet says
    $first = [regex]::Match($all, '^[0-9 ,.;:–-]+').Value
    $picks = [System.Collections.Generic.List[int]]::new()
    foreach ($m in [regex]::Matches($first, '\d+')) {
        $v = 0
        if ([int]::TryParse($m.Value, [ref]$v) -and $v -ge 1 -and $v -le $cmds.Count -and -not $picks.Contains($v - 1)) { $picks.Add($v - 1) }
    }
    [pscustomobject]@{ Picks = @($picks | Select-Object -First 3); Text = ($all.Substring($first.Length) -replace '^[\s\p{P}\p{S}]+', '').TrimEnd() }
}

# /help: the pet asks, you say what you need, it shows the right commands → $true when it was handled
function script:Invoke-LotusPetHelp {
    Import-LotusLangGroup pets
    Initialize-LotusPets
    if (-not $script:PetN.Count) { return $false }
    $cmds = Get-LotusPetCommands
    $idx = Get-Random -Maximum $script:PetN.Count
    if (-not (Enter-LotusPetScreen)) { return $false }
    try {
        Write-LotusLine ''
        $script:PetDrawn = 0
        Show-LotusPetSpeech $idx ((T pt_help_ask).Replace('%s', [string]$script:S['LOTUS_NAME']))
        $first = ''
        while (-not $script:PetInt) {
            Write-LotusLine ''
            Write-LotusDim "  $(T pt_help_hint)"
            Write-LotusRaw "$([char]27)[?25h"
            $q = Read-LotusLine (T pt_ask) $first
            Write-LotusRaw "$([char]27)[?25l"
            if ($null -eq $q) { break }
            $first = ''
            if (-not $q.Trim()) {
                Exit-LotusPetScreen
                [void](Show-LotusCheatsheet)
                return $true
            }
            Write-LotusLine ''
            Write-LotusLog INFO pets 'Help asked'
            $picks = @(); $said = ''; $thought = $false
            if (Get-LotusPetBrain) {
                $thought = $true
                $answer = Get-LotusPetHelpThought $idx $q
                if ($answer) { $picks = @($answer.Picks); $said = $answer.Text }
            }
            if ($script:PetInt) { break }
            if (-not $picks.Count) { $picks = @(Get-LotusPetRank $q) }
            if (-not $thought) { $script:PetDrawn = 0 }
            if (-not $picks.Count) { Show-LotusPetSpeech $idx $(if ($said) { $said } else { T pt_help_none }); continue }
            Show-LotusPetSpeech $idx $(if ($said) { $said } else { T pt_help_found })
            # the commands, ready to be put on the command line
            Write-LotusLine ''
            $k = "$([char]27)[1;$($script:C['key'])m"; $d = E dim; $r = $script:R
            $dw = [Math]::Min(70, (Get-LotusColumns) - 10)
            $n = 0
            foreach ($i in $picks) {
                $c = $cmds[$i]
                $n++
                Write-LotusLine "    $k$n  $($c.Usage)$r"
                foreach ($l in (Split-LotusPetWords $c.Description $dw)) { Write-LotusLine "       $l" }
                if ($c.Example -cne $c.Usage) { Write-LotusLine "       $d$($c.Example)$r" }
            }
            Write-LotusLine ''
            Write-LotusDim "  $((T pt_help_pick).Replace('%s', [string]$n))"
            $key = Read-LotusPetKey
            if ($key -cmatch '^[1-9]\z' -and [int]$key -le $n) {
                Write-LotusFile (Join-Path $script:Paths.Cache 'ai-prompt') "$($cmds[$picks[[int]$key - 1]].Example)`n"
                Write-LotusSuccess (T pt_help_ready)
                break
            }
            if ($key -cin 'esc', 'interrupt') { break }
            if ($key.Length -eq 1 -and -not [char]::IsControl($key[0])) { $first = $key }
        }
    } finally { Exit-LotusPetScreen }
    Write-LotusLine ''
    $true
}

# ── /pets ─────────────────────────────────────────────────────

# Your pets side by side, with their names → lines
function script:Get-LotusPetLineup {
    param([string]$Frame = 'idle')
    $cols = [System.Collections.Generic.List[object]]::new()
    $widths = [System.Collections.Generic.List[int]]::new()
    $h = 0
    for ($i = 0; $i -lt $script:PetN.Count; $i++) {
        $block = Get-LotusPetBlock $i $Frame -1 'none'
        $cols.Add($block)
        $widths.Add([Math]::Max((Get-LotusPetArtWidth (Get-LotusPetKind $i)), $script:PetN[$i].Length) + 6)
        if ($block.Count -gt $h) { $h = $block.Count }
    }
    $out = [System.Collections.Generic.List[string]]::new()
    for ($j = 0; $j -lt $h; $j++) {
        $sb = [System.Text.StringBuilder]::new('  ')
        for ($i = 0; $i -lt $cols.Count; $i++) {
            $rows = $cols[$i]
            $pad = $h - $rows.Count
            if ($j -ge $pad) { [void]$sb.Append("$($rows[$j - $pad])$([char]27)[0m      ") }
            else { [void]$sb.Append([string]::new(' ', $widths[$i])) }
        }
        $out.Add($sb.ToString())
    }
    , $out.ToArray()
}

function script:Wait-LotusPetsKey { Write-LotusDim (T back '(press any key to go back)'); [void](Read-LotusKey) }
function script:Clear-LotusPetsScreen { Write-LotusRaw "$([char]27)[H$([char]27)[2J" }

function script:Show-LotusPetsScreen {
    Initialize-LotusPets
    if (-not ((Test-LotusOutTty) -and (Test-LotusTty))) {
        for ($i = 0; $i -lt $script:PetN.Count; $i++) { "$(PadR $script:PetN[$i] 16) $(PadR $script:PetK[$i] 10) $(Get-LotusPetStatus $i)" }
        return (St 0)
    }
    $sel = 1
    while ($true) {
        Clear-LotusPetsScreen
        Write-LotusHero (T pt_title) (T pt_sub)
        if ($script:PetN.Count) { foreach ($l in (Get-LotusPetLineup)) { Write-LotusLine $l }; Write-LotusBlank }
        $opts = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $script:PetN.Count; $i++) { $opts.Add("$($script:PetN[$i])|$(Get-LotusPetKindLabel $script:PetK[$i]) · $(Get-LotusPetStatus $i)") }
        $count = $script:PetN.Count
        if ($count) { $opts.Add("$(T pt_game)|$(T pt_game_d)") }
        if ($count -lt 3) { $opts.Add("$(T pt_adopt)|$((T pt_adopt_d).Replace('%s', [string]$count))") }
        $opts.Add("$(T pt_settings)|$(T pt_settings_d)")
        $pick = Read-LotusSelect $sel $opts.ToArray()
        if ($null -eq $pick) { break }
        $sel = $pick
        $extra = [int]($count -gt 0)
        if ($sel -le $count) { Show-LotusPetOne ($sel - 1) }
        elseif ($extra -and $sel -eq $count + 1) { Import-LotusCommand zetamac; [void](Invoke-LotusZetamac @()) }
        elseif ($sel -eq $count + $extra + 1 -and $count -lt 3) { Invoke-LotusPetAdoptFlow }
        else { Show-LotusPetsSettings }
        Initialize-LotusPets
    }
    Clear-LotusPetsScreen
    St 0
}

# One pet: talk, feed, rename, personality, say goodbye
function script:Show-LotusPetOne {
    param([int]$Idx)
    $name = $script:PetN[$Idx]
    $low = $name.ToLowerInvariant()
    $lbl = Get-LotusPetKindLabel $script:PetK[$Idx]
    Clear-LotusPetsScreen
    Write-LotusHero "$(T pt_title) · $name"
    Write-LotusPetLines (Get-LotusPetBlock $Idx 'happy' -1 'none')
    Write-LotusBlank
    $pick = Read-LotusSelect 1 @("$(T pt_talk)|$((T pt_talk_d).Replace('%s', $low))", "$(T pt_feed)|/feed $low", "$(T pt_rename)|",
        "$(T pt_persona)|$((T pt_persona_d).Replace('%s', $name))", "$(T pt_remove)|", "$(T pt_back)|")
    switch ($pick) {
        1 { Clear-LotusPetsScreen; [void](Invoke-LotusPetTalk $name @()); Wait-LotusPetsKey }
        2 { Clear-LotusPetsScreen; [void](Invoke-LotusPetFeed $name); Wait-LotusPetsKey }
        3 {
            Write-LotusBlank
            $typed = Read-LotusLine (T pt_name) $name
            if ($null -eq $typed) { return }
            $new = $typed.Trim(' ')
            if ($new -ceq $name -or -not $new) { return }
            if (-not (Test-LotusPetNameFree $new $Idx)) { Wait-LotusPetsKey; return }
            $newLow = $new.ToLowerInvariant()
            $fed = 0L
            if ($script:PetFed.TryGetValue($low, [ref]$fed)) {
                $c = 0L; [void]$script:PetCount.TryGetValue($low, [ref]$c)
                $script:PetFed[$newLow] = $fed; $script:PetCount[$newLow] = $c
            }
            $mem = Get-LotusPetMemoryFile $Idx
            $script:PetN[$Idx] = $new
            if ($newLow -cne $low -and (Test-Path -LiteralPath $mem)) { Move-Item -LiteralPath $mem -Destination (Get-LotusPetMemoryFile $Idx) -Force -ErrorAction SilentlyContinue }
            Save-LotusPets
            Write-LotusSuccess ((T pt_renamed).Replace('%s', $new)); Wait-LotusPetsKey
        }
        4 {
            Write-LotusBlank
            Write-LotusDim "  $(Get-LotusPetInfo $script:PetK[$Idx] 'personality')"
            $typed = Read-LotusLine ((T pt_persona_q).Replace('%s', $lbl)) $script:PetP[$Idx]
            if ($null -eq $typed) { return }
            $script:PetP[$Idx] = Cut ($typed -replace '\p{Cc}', ' ') 240
            Save-LotusPets
            Remove-Item -LiteralPath (Get-LotusPetMemoryFile $Idx) -Force -ErrorAction SilentlyContinue
            Write-LotusSuccess (T pt_saved); Wait-LotusPetsKey
        }
        5 {
            Write-LotusBlank
            if (-not (Read-LotusConfirm ((T pt_remove_q).Replace('%s', $name)) 'n')) { return }
            Remove-Item -LiteralPath (Get-LotusPetMemoryFile $Idx) -Force -ErrorAction SilentlyContinue
            $script:PetN.RemoveAt($Idx); $script:PetK.RemoveAt($Idx); $script:PetP.RemoveAt($Idx); $script:PetT.RemoveAt($Idx)
            [void]$script:PetFed.Remove($low); [void]$script:PetCount.Remove($low)
            Save-LotusPets
            Write-LotusInfo ((T pt_removed).Replace('%s', $name)); Wait-LotusPetsKey
        }
    }
}

# PowerShell's own words: a pet called like one could never be called by its name
$script:PetPsWords = @('begin', 'break', 'catch', 'class', 'clean', 'continue', 'data', 'define', 'do', 'dynamicparam', 'else', 'elseif', 'end', 'enum',
    'exit', 'filter', 'finally', 'for', 'foreach', 'from', 'function', 'hidden', 'if', 'in', 'inlinescript', 'parallel', 'param', 'process', 'return',
    'sequence', 'static', 'switch', 'throw', 'trap', 'try', 'until', 'using', 'var', 'while', 'workflow', 'configuration')

# Is a name free and usable? (a pet you call by typing its name must not be a command)
function script:Test-LotusPetNameFree {
    param([string]$Name, [int]$Except = -1)
    if (-not (Test-LotusPetName $Name)) { Write-LotusWarn (T pt_name_bad); return $false }
    $low = $Name.ToLowerInvariant()
    for ($i = 0; $i -lt $script:PetN.Count; $i++) {
        if ($i -ne $Except -and $script:PetN[$i].ToLowerInvariant() -ceq $low) { Write-LotusWarn ((T pt_name_taken).Replace('%s', $Name)); return $false }
    }
    if ((Get-Command -Name $Name -ErrorAction SilentlyContinue) -or $script:PetPsWords -ccontains $low -or $low -cin 'lotus', 'pet', 'pets', 'feed', 'help', 'ai', 'bg') {
        Write-LotusWarn ((T pt_name_cmd).Replace('%s', $Name)); return $false
    }
    $true
}

# Adopt: which kind, which name
function script:Invoke-LotusPetAdoptFlow {
    $kinds = @($script:PetKinds)
    $opts = @(foreach ($k in $kinds) { "$(Get-LotusPetKindLabel $k)|$(Get-LotusPetKindAbout $k)" }) + @("$(T pt_own)|$(T pt_own_d)")
    Clear-LotusPetsScreen
    Write-LotusHero (T pt_adopt) (T pt_species_q)
    $pick = Read-LotusSelect 1 $opts
    if ($null -eq $pick) { return }
    if ($pick -gt $kinds.Count) {
        Import-LotusProject
        Write-LotusBlank
        Write-LotusText (T pt_add_how)
        Write-LotusDim "  $($script:P['website'])pets.html"
        Write-LotusBlank
        if (Read-LotusConfirm (T pt_add_q) 'n') { [void](Add-LotusPetKind '') }
        return
    }
    if (-not (Invoke-LotusPetAdoptNamed $kinds[$pick - 1])) { Wait-LotusPetsKey }
}

# Asks for a name and adopts a <kind> (the pet says hi right away) → $false when the name or the adoption failed
function script:Invoke-LotusPetAdoptNamed {
    param([string]$Kind)
    $ideas = @((Get-LotusPetInfo $Kind 'names') -split ', ' | Where-Object { $_ })
    $idea = if ($ideas.Count) { $ideas[(Get-Random -Maximum $ideas.Count)] } else { 'Mochi' }
    Write-LotusBlank
    $typed = Read-LotusLine (T pt_name) $idea
    if ($null -eq $typed) { return $true }
    $name = $typed.Trim(' ')
    if (-not (Test-LotusPetNameFree $name)) { return $false }
    if (-not (Add-LotusPet $Kind $name -Quiet)) { return $false }
    Clear-LotusPetsScreen
    Show-LotusPetIntro $name
    Wait-LotusPetsKey
    $true
}

# lotus pets adopt <kind> <name>
function script:Invoke-LotusPetsAdopt {
    param([string[]]$Words)
    $kind = if ($Words.Count) { $Words[0] } else { '' }
    $name = if ($Words.Count -gt 1) { $Words[1] } else { '' }
    if (Add-LotusPet $kind $name -Quiet:($Words.Count -gt 2 -and $Words[2] -ceq 'quiet')) { St 0 } else { St 1 }
}

# Adopts a <kind> called <name> → $true, or $false after saying what is wrong (the setup wizard adopts with it too)
function script:Add-LotusPet {
    param([string]$Kind, [string]$Name, [switch]$Quiet)
    Import-LotusLangGroup pets
    Initialize-LotusPets
    $k = ([string]$Kind).ToLowerInvariant()
    if (-not $script:PetArt.ContainsKey("$k,idle")) { Write-LotusError (T pt_kind_bad) $Kind @($script:PetKinds -join ', '); return $false }
    if ($script:PetN.Count -ge 3) { Write-LotusError (T pt_full); return $false }
    if (-not (Test-LotusPetNameFree $Name)) { return $false }
    $now = Get-LotusEpoch
    $script:PetN.Add($Name); $script:PetK.Add($k); $script:PetP.Add(''); $script:PetT.Add([string]$now)
    $script:PetFed[$Name.ToLowerInvariant()] = $now; $script:PetCount[$Name.ToLowerInvariant()] = 0
    Save-LotusPets
    Write-LotusLog INFO pets "Adopted $Name ($k)"
    if (-not $Quiet) { Write-LotusSuccess (Format-LotusPetText (T pt_adopted) @($Name, $Name.ToLower())) }
    $true
}

# A new pet introduces itself
function script:Show-LotusPetIntro {
    param([string]$Name)
    Import-LotusLangGroup pets
    Initialize-LotusPets
    $idx = Find-LotusPet $Name
    if ($idx -lt 0) { return }
    $text = Format-LotusPetText (T pt_intro) @([string]$script:S['LOTUS_NAME'], $script:PetN[$idx])
    [void](Enter-LotusPetScreen)
    try {
        Write-LotusLine ''
        $script:PetDrawn = 0
        Show-LotusPetSpeech $idx $text 'happy'
    } finally { Exit-LotusPetScreen }
    Write-LotusLine ''
}

# Start screen, /help, reactions, how they think (on Windows: the AI of /ai, or nothing)
function script:Show-LotusPetsSettings {
    $sel = 1
    $onoff = { param($v) if (Test-LotusOn $v) { T pt_on } else { T pt_off } }
    while ($true) {
        Clear-LotusPetsScreen
        Write-LotusHero "$(T pt_title) · $(T pt_settings)"
        $brain = if ([string]$script:S['LOTUS_PET_BRAIN'] -ceq 'off') { T pt_brain_off } else { T pt_brain_ai }
        $pick = Read-LotusSelect $sel @("$(T pt_s_start)|$(& $onoff $script:S['LOTUS_PET_START'])", "$(T pt_s_help)|$(& $onoff $script:S['LOTUS_PET_HELP'])",
            "$(T pt_s_react)|$(& $onoff $script:S['LOTUS_PET_REACT'])", "$(T pt_on_brain)|$brain")
        if ($null -eq $pick) { break }
        $sel = $pick
        switch ($sel) {
            1 { $script:S['LOTUS_PET_START'] = if (Test-LotusOn $script:S['LOTUS_PET_START']) { '0' } else { '1' } }
            2 { $script:S['LOTUS_PET_HELP'] = if (Test-LotusOn $script:S['LOTUS_PET_HELP']) { '0' } else { '1' } }
            3 { $script:S['LOTUS_PET_REACT'] = if (Test-LotusOn $script:S['LOTUS_PET_REACT']) { '0' } else { '1' } }
            4 { $script:S['LOTUS_PET_BRAIN'] = if ([string]$script:S['LOTUS_PET_BRAIN'] -ceq 'off') { 'ai' } else { 'off' }; $script:PetBrain = '' }
        }
        Save-LotusSettings
    }
}

# ── Your own kind of pet: lotus pets add [file] ───────────────

function script:Add-LotusPetKind {
    param([string]$Source)
    Initialize-LotusPets
    Write-LotusHeader (T pt_add_title)
    if ($Source) {
        $path = ConvertTo-LotusCleanPath $Source
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-LotusError 'File not found' $Source; return (St 1) }
        $text = [string](Read-LotusFile $path)
    } else {
        $clip = Get-LotusClipboardText
        $text = if ($clip.Code -eq 0) { [string]$clip.Value } else { '' }
    }
    # what an AI answers often sits in a code block
    $text = $text -creplace '```[a-z]*', ''
    $builtin = @{}
    foreach ($k in $script:PetKinds) { $builtin[$k] = (Get-LotusPetInfo $k 'file').StartsWith((Get-LotusRoot)) }
    $tmp = Join-Path $script:Paths.Cache 'pets/new.pet'
    Write-LotusFile $tmp "$text`n"
    $r = Read-LotusPetFile $tmp
    if ($r.Code) {
        Write-LotusError (T pt_add_bad) "$($r.Msg)" @((T pt_add_bad_hint), (T pt_add_how))
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return (St 1)
    }
    $kind = $r.Value
    if ($builtin[$kind] -or (Test-Path -LiteralPath (Join-Path (Get-LotusRoot) "data/pets/$kind.pet"))) {
        Write-LotusError ((T pt_add_builtin).Replace('%s', $kind))
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return (St 1)
    }
    # a preview, then saved as clean text (what Lotus read, not what was pasted)
    $lbl = Get-LotusPetKindLabel $kind
    foreach ($line in (Get-LotusPetArtText $kind 'idle') -split "`n") { Write-LotusLine "    $(E logo)$line$($script:R)" }
    Write-LotusBlank
    Write-LotusKv $lbl (Get-LotusPetInfo $kind 'personality')
    Write-LotusBlank
    if ((Test-LotusTty) -and -not (Read-LotusConfirm (T pt_add_q) 'y')) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; return (St 0) }
    $out = [System.Text.StringBuilder]::new("# Lotus pet, added with lotus pets add`n")
    foreach ($key in 'species', 'label', 'label_de', 'label_fr', 'label_es', 'about', 'about_de', 'about_fr', 'about_es', 'sound', 'sound_de', 'sound_fr', 'sound_es',
        'food', 'food_de', 'food_fr', 'food_es', 'snack', 'face', 'face_happy', 'names', 'personality') {
        $v = Get-LotusPetInfo $kind $key
        if ($v) { [void]$out.Append("$($key): $v`n") }
    }
    foreach ($fr in 'idle', 'blink', 'wag', 'talk', 'happy', 'eat', 'sleep') {
        $v = $null
        if ($script:PetArt.TryGetValue("$kind,$fr", [ref]$v) -and $v) { [void]$out.Append("[$fr]`n$v`n") }
    }
    Write-LotusFile (Join-Path $script:Paths.Conf "pets/$kind.pet") $out.ToString()
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Write-LotusLog INFO pets "New kind of pet: $kind"
    Write-LotusSuccess ((T pt_add_ok).Replace('%s', $lbl))
    if ($script:PetN.Count -lt 3 -and (Test-LotusTty) -and (Test-LotusOutTty)) {
        Write-LotusBlank
        if (Read-LotusConfirm "$(T pt_adopt)?" 'y') { [void](Invoke-LotusPetAdoptNamed $kind) }
    }
    St 0
}

# ── lotus doctor ──────────────────────────────────────────────

# The rows of the pets in lotus doctor: how many, how they think (<row> <ok> <opt> come from lotus doctor)
function script:Show-LotusPetDoctorRows {
    param($Row, $Ok, $Opt)
    Import-LotusLangGroup pets
    Initialize-LotusPets
    if ($script:PetN.Count) {
        for ($i = 0; $i -lt $script:PetN.Count; $i++) { & $Row $Ok $script:PetN[$i] "$($script:PetK[$i]) · $(Get-LotusPetStatus $i)" }
    } else { & $Row $Opt 'Pets' 'none adopted yet – /pets' }
    & $Row $Ok 'Kinds' "$($script:PetKinds -join ', ')  (data/pets, $(Format-LotusHomePath (Join-Path $script:Paths.Conf 'pets')))"
    if ([string]$script:S['LOTUS_PET_BRAIN'] -ceq 'off') { & $Row $Opt 'Thinking' 'off – pets answer with short phrases' }
    elseif (Get-LotusPetBrain) { & $Row $Ok 'Thinking' 'the AI of /ai' }
    else { & $Row $Opt 'Thinking' (T pt_noai_hint_ai) }
}
