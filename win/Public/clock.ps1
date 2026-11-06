# /clock – a clock in the colors of your theme, a port of lib/cmd/clock.zsh
#   lotus clock [minimal|big|retro|matrix|analog|world]
# ←/→ or space switch the design, s seconds on/off, z a second time zone, q or esc leaves. The zones are the IANA names
# of the settings (America/New_York …): .NET knows them on Windows too.

$script:ClkDesigns = @('minimal', 'big', 'retro', 'matrix', 'analog', 'world')
# big digits: 5 pixels wide, 7 high; the colon is 1 wide
$script:ClkFont = @{
    '0' = '.###. #...# #..## #.#.# ##..# #...# .###.'; '1' = '..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.'
    '2' = '.###. #...# ....# ...#. ..#.. .#... #####'; '3' = '##### ...#. ..#.. ...#. ....# #...# .###.'
    '4' = '...#. ..##. .#.#. #..#. ##### ...#. ...#.'; '5' = '##### #.... ####. ....# ....# #...# .###.'
    '6' = '..##. .#... #.... ####. #...# #...# .###.'; '7' = '##### ....# ...#. ..#.. .#... .#... .#...'
    '8' = '.###. #...# #...# .###. #...# #...# .###.'; '9' = '.###. #...# #...# .#### ....# ...#. .##..'
    ':' = '. # . . # . .'
}
# seven segments: a top, b top right, c bottom right, d bottom, e bottom left, f top left, g middle
$script:ClkSeg = @{ '0' = 'abcdef'; '1' = 'bc'; '2' = 'abged'; '3' = 'abgcd'; '4' = 'fgbc'; '5' = 'afgcd'; '6' = 'afgedc'; '7' = 'abc'; '8' = 'abcdefg'; '9' = 'abcdfg' }

function script:Invoke-Lotusclock {
    param([string]$Cmd, [string[]]$Rest)
    $want = if ($Rest.Count) { $Rest[0] } else { [string]$script:S['LOTUS_CLOCK_DESIGN'] }
    if ($want -cnotin $script:ClkDesigns) { $want = 'big' }
    if (-not ((Test-LotusOutTty) -and (Test-LotusTty))) { [datetime]::Now.ToString('HH:mm:ss'); return (St 0) }
    Initialize-LotusClock
    $d = [Array]::IndexOf($script:ClkDesigns, $want)
    $secs = Test-LotusOn $script:S['LOTUS_CLOCK_SECONDS']
    $zones = @(([string]$script:S['LOTUS_CLOCK_ZONES']) -split '\s+' | Where-Object { $_ -match '^[A-Za-z0-9_/+-]+$' })
    $zi = 0
    if ($script:S['LOTUS_CLOCK_ZONE']) { $zi = [Array]::IndexOf($zones, [string]$script:S['LOTUS_CLOCK_ZONE']) + 1 }
    $changed = $false; $last = -1
    $esc = [char]27
    Enter-LotusKeys
    Write-LotusRaw "$esc[?1049h$esc[?25l$esc[2J"
    try {
        while ($true) {
            $now = [datetime]::Now
            $sec = Get-LotusEpoch
            if ($sec -ne $last -or $script:ClkDesigns[$d] -eq 'matrix') {
                if ($sec -ne $last) { $size = Get-LotusSize; $last = $sec }
                Show-LotusClockFrame $script:ClkDesigns[$d] $size[1] $size[0] $secs $(if ($zi -gt 0) { $zones[$zi - 1] } else { '' })
            }
            $wait = if ($script:ClkDesigns[$d] -eq 'matrix') { 0.12 } else { 1.0 - $now.Millisecond / 1000.0 + 0.01 }
            $k = Read-LotusKeyX $wait
            switch -CaseSensitive -Regex ($k) {
                '^(right|space|tab|l|n)$' { $d = ($d + 1) % $script:ClkDesigns.Count; $last = -1; $changed = $true; break }
                '^(left|h|p)$' { $d = ($d + $script:ClkDesigns.Count - 1) % $script:ClkDesigns.Count; $last = -1; $changed = $true; break }
                '^[sS]$' { $secs = -not $secs; $last = -1; $changed = $true; break }
                '^[zZ]$' { if ($zones.Count) { $zi = ($zi + 1) % ($zones.Count + 1); $last = -1; $changed = $true }; break }
                '^[1-6]$' { $d = [int]$k - 1; $last = -1; $changed = $true; break }
                '^(q|Q|esc|enter|interrupt)$' { $script:ClkQuit = $true; break }
            }
            if ($script:ClkQuit) { $script:ClkQuit = $false; break }
        }
    } finally {
        Write-LotusRaw "$esc[?2026l$esc[2J$esc[?1049l$esc[?25h"
        Exit-LotusKeys
    }
    if ($changed) {
        # the last design, seconds and time zone are what the clock opens with next time
        $script:S['LOTUS_CLOCK_DESIGN'] = $script:ClkDesigns[$d]
        $script:S['LOTUS_CLOCK_SECONDS'] = if ($secs) { '1' } else { '0' }
        $script:S['LOTUS_CLOCK_ZONE'] = if ($zi -gt 0) { $zones[$zi - 1] } else { '' }
        Save-LotusSettings
    }
    St 0
}

# The theme's colors, dark versions for unlit segments and the rain, and the language of the day and month names
function script:Initialize-LotusClock {
    $th = $script:Themes[[string]$script:S['LOTUS_THEME']]; if (-not $th) { $th = $script:Themes['matcha'] }
    $names = 'logo', 'key', 'accent', 'key2', 'salute', 'border', 'dim'
    $esc = [char]27
    $script:ClkC = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $script:ClkC[$names[$i]] = "$esc[$(ConvertTo-LotusSgr $th[$i])m" }
    foreach ($k in 'key2', 'key', 'logo') {
        $c = @($th[[Array]::IndexOf($names, $k)] -split ';' | ForEach-Object { [int]$_ })
        $script:ClkC["${k}_off"] = "$esc[$(ConvertTo-LotusSgr (($c | ForEach-Object { [Math]::Truncate($_ * 22 / 100) }) -join ';'))m"
        $script:ClkC["${k}_mid"] = "$esc[$(ConvertTo-LotusSgr (($c | ForEach-Object { [Math]::Truncate($_ * 55 / 100) }) -join ';'))m"
    }
    $script:ClkC['r'] = "$esc[0m"; $script:ClkC['b'] = "$esc[1m"; $script:ClkC['w'] = "$esc[97m"
    $script:ClkCulture = [cultureinfo]::GetCultureInfo($(switch ($script:S['LOTUS_LANG']) { 'de' { 'de-DE' } 'fr' { 'fr-FR' } 'es' { 'es-ES' } default { 'en-US' } }))
    $script:ClkZones = @{}
    $script:ClkRain = $null
}

# The time in a zone, or $null when the zone is unknown (asked again once an hour, for daylight saving time)
function script:Get-LotusClockZoneTime {
    param([string]$Zone, [datetime]$Utc)
    $z = $script:ClkZones[$Zone]
    if (-not $z -or ([datetime]::UtcNow - $z.At).TotalHours -gt 1) {
        $tz = try { [TimeZoneInfo]::FindSystemTimeZoneById($Zone) } catch { $null }
        $z = @{ Tz = $tz; At = [datetime]::UtcNow }
        $script:ClkZones[$Zone] = $z
    }
    if (-not $z.Tz) { return $null }
    [TimeZoneInfo]::ConvertTimeFromUtc($Utc, $z.Tz)
}

# "Tokyo 22:07 · tomorrow" for a zone
function script:Get-LotusClockZoneLine {
    param([string]$Zone, [bool]$Secs)
    $utc = [datetime]::UtcNow
    $t = Get-LotusClockZoneTime $Zone $utc
    if (-not $t) { return "$Zone ?" }
    $here = [datetime]::Now
    $dz = ($t.Date - $here.Date).Days
    $city = (Split-Path -Leaf $Zone).Replace('_', ' ')
    $day = if ($dz -gt 0) { " · $(T clk_tomorrow 'tomorrow')" } elseif ($dz -lt 0) { " · $(T clk_yesterday 'yesterday')" } else { '' }
    "$city $($t.ToString($(if ($Secs) { 'HH:mm:ss' } else { 'HH:mm' })))$day"
}

# One frame of a design, centered, with its name on top and the keys at the bottom
function script:Show-LotusClockFrame {
    param([string]$Design, [int]$H, [int]$W, [bool]$Secs, [string]$Zone)
    $now = [datetime]::Now
    $t = $now.ToString($(if ($Secs) { 'HH:mm:ss' } else { 'HH:mm' }))
    $date = $now.ToString('dddd, d MMMM yyyy', $script:ClkCulture)
    $r = switch ($Design) {
        'minimal' { Get-LotusClockMinimal $t $date $Secs }
        'big' { Get-LotusClockBig $t $date $W }
        'retro' { Get-LotusClockRetro $t $date }
        'matrix' { Get-LotusClockMatrix $t $H $W }
        'analog' { Get-LotusClockAnalog $H $W $Secs $date $now }
        'world' { Get-LotusClockWorld $Secs }
    }
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($l in $r.Lines) { $out.Add($l) }
    $w = $r.Width
    $C = $script:ClkC
    if ($Zone -and $Design -ne 'world') {
        $zl = Get-LotusClockZoneLine $Zone $Secs
        $out.Add(''); $out.Add("$($C['dim'])$(PadL $zl ([Math]::Truncate(($w + $zl.Length) / 2)))$($C['r'])")
    }
    $h = $out.Count
    $label = T "clk_$Design" $Design
    $keys = T clk_keys '←→ design · s seconds · z time zone · q quit'
    $top = [Math]::Max(2, [Math]::Truncate(($H - $h) / 2))
    $left = [Math]::Max(0, [Math]::Truncate(($W - $w) / 2))
    $esc = [char]27
    $buf = [System.Text.StringBuilder]::new("$esc[?2026h$esc[H")
    [void]$buf.Append("  $($C['dim'])lotus clock · $($C['r'])$($C['key'])$label$($C['r'])$esc[K`n")
    for ($i = 2; $i -lt $top; $i++) { [void]$buf.Append("$esc[K`n") }
    $pad = [string]::new(' ', $left)
    for ($i = 1; $i -le $h -and $top + $i -lt $H; $i++) { [void]$buf.Append("$pad$($out[$i - 1])$($C['r'])$esc[K`n") }
    [void]$buf.Append("$esc[J$esc[$H;3H$($C['dim'])$keys$($C['r'])$esc[?2026l")
    Write-LotusRaw $buf.ToString()
}

# ── The designs: each gives @{ Lines; Width } ────────────────

function script:Get-LotusClockMinimal {
    param([string]$T, [string]$Date, [bool]$Secs)
    $C = $script:ClkC
    $spaced = ($T.ToCharArray() | ForEach-Object { [string]$_ }) -join ' '
    $w = [Math]::Max($spaced.Length, $Date.Length)
    $line = PadL $spaced ([Math]::Truncate(($w + $spaced.Length) / 2))
    # the seconds quieter than the hours and minutes
    if ($T.Length -eq 5) { $main = $line; $tail = '' } else { $main = $line.Substring(0, $line.Length - 6); $tail = $line.Substring($line.Length - 6) }
    [pscustomobject]@{ Lines = @("$($C['b'])$($C['key'])$main$($C['r'])$($C['dim'])$tail", '', "$($C['accent'])$(PadL $Date ([Math]::Truncate(($w + $Date.Length) / 2)))"); Width = $w }
}

# big digits from the font; two columns per pixel when there is room → 7 rows
function script:Get-LotusClockBigRows {
    param([string]$T, [int]$Pw)
    $rows = @('', '', '', '', '', '', '')
    foreach ($ch in $T.ToCharArray()) {
        $g = $script:ClkFont[[string]$ch] -split ' '
        for ($r = 0; $r -lt 7; $r++) {
            $px = $g[$r].Replace('.', ' ')
            $px = if ($Pw -eq 2) { $px.Replace('#', '██').Replace(' ', '  ') } else { $px.Replace('#', '█') }
            $rows[$r] += $px + [string]::new(' ', $Pw)
        }
    }
    $rows
}

function script:Get-LotusClockBig {
    param([string]$T, [string]$Date, [int]$W)
    $C = $script:ClkC
    $pw = if ($T.Length * 12 -gt $W - 4) { 1 } else { 2 }
    $rows = Get-LotusClockBigRows $T $pw
    $width = $rows[0].Length
    # a soft gradient from the theme's lotus color to its key color
    $col = @($C['logo'], $C['logo'], $C['accent'], $C['accent'], $C['key'], $C['key'], $C['key'])
    $lines = @(for ($r = 0; $r -lt 7; $r++) { "$($col[$r])$($rows[$r])" }) + @('', "$($C['dim'])$(PadL $Date ([Math]::Truncate(($width + $Date.Length) / 2)))")
    [pscustomobject]@{ Lines = $lines; Width = $width }
}

# seven segments, the unlit ones faintly visible like on a real display
function script:Get-LotusClockRetro {
    param([string]$T, [string]$Date)
    $C = $script:ClkC
    $on = $C['key2']; $off = $C['key2_off']; $sp = '     '
    $rows = @('', '', '', '', '', '', '')
    foreach ($ch in $T.ToCharArray()) {
        if ($ch -eq ':') {
            $rows[0] += '   '; $rows[1] += '   '; $rows[2] += " $on●$off "; $rows[3] += '   '; $rows[4] += " $on●$off "; $rows[5] += '   '; $rows[6] += '   '
            continue
        }
        $segs = $script:ClkSeg[[string]$ch]
        $s = @{}; foreach ($x in 'a', 'b', 'c', 'd', 'e', 'f', 'g') { $s[$x] = if ($segs.Contains($x)) { $on } else { $off } }
        $rows[0] += "$($s.a) ━━━━━  "
        $rows[1] += "$($s.f)┃$sp$($s.b)┃ "; $rows[2] += "$($s.f)┃$sp$($s.b)┃ "
        $rows[3] += "$($s.g) ━━━━━  "
        $rows[4] += "$($s.e)┃$sp$($s.c)┃ "; $rows[5] += "$($s.e)┃$sp$($s.c)┃ "
        $rows[6] += "$($s.d) ━━━━━  "
    }
    $digits = ($T -replace '[^0-9]', '').Length; $colons = ($T -replace '[0-9]', '').Length
    $w = $digits * 8 + $colons * 3
    $frame = $C['border']; $bar = Get-LotusLine ($w + 2)
    $lines = @("$frame╭$bar╮") + @(for ($r = 0; $r -lt 7; $r++) { "$frame│ $($rows[$r]) $frame│" }) + @("$frame╰$bar╯", '', "$($C['key2_mid'])$(PadL $Date ([Math]::Truncate(($w + 4 + $Date.Length) / 2)))")
    [pscustomobject]@{ Lines = $lines; Width = $w + 4 }
}

# digits made of falling characters: rain everywhere, brighter where a digit is
function script:Get-LotusClockMatrix {
    param([string]$T, [int]$H, [int]$W)
    $C = $script:ClkC
    $glyphs = '01234567890ABCDEF:+*<>=#%$&ZXCVNMKLJH'
    $hgt = $H - 4
    if ($W -le 2) { $W = 80 }
    $W -= 2
    $rnd = if ($script:ClkRnd) { $script:ClkRnd } else { $script:ClkRnd = [System.Random]::new(); $script:ClkRnd }
    if (-not $script:ClkRain -or $script:ClkRainW -ne $W) {
        $script:ClkRain = [int[]]::new($W + 1); $script:ClkSpeed = [int[]]::new($W + 1)
        for ($x = 1; $x -le $W; $x++) { $script:ClkRain[$x] = $rnd.Next($hgt + 20) - 20; $script:ClkSpeed[$x] = $rnd.Next(2) + 1 }
        $script:ClkRainW = $W
    }
    $pw = if ($T.Length * 12 -gt $W - 4) { 1 } else { 2 }
    $big = Get-LotusClockBigRows $T $pw
    $bw = $big[0].Length
    $bx = [Math]::Truncate(($W - $bw) / 2); $by = [Math]::Truncate(($hgt - 7) / 2)
    $lines = [System.Collections.Generic.List[string]]::new()
    for ($y = 0; $y -lt $hgt; $y++) {
        $sb = [System.Text.StringBuilder]::new(); $cur = ''
        for ($x = 1; $x -le $W; $x++) {
            $d = $script:ClkRain[$x] - $y
            $inside = $y -ge $by -and $y -lt $by + 7 -and $x -gt $bx -and $x -le $bx + $bw -and $big[$y - $by][$x - $bx - 1] -eq '█'
            $g = $glyphs[$rnd.Next($glyphs.Length)]
            $want = if ($inside) { 'hot' } elseif ($d -eq 0) { 'head' } elseif ($d -gt 0 -and $d -lt 7) { 'tail' } elseif ($d -ge 7 -and $d -lt 16) { 'dark' } else { '' }
            if (-not $want) { [void]$sb.Append(' '); continue }
            if ($want -ne $cur) { [void]$sb.Append($(switch ($want) { 'hot' { $C['key'] } 'head' { $C['w'] } 'tail' { $C['key_mid'] } 'dark' { $C['key_off'] } })); $cur = $want }
            [void]$sb.Append($g)
        }
        $lines.Add($sb.ToString())
    }
    for ($x = 1; $x -le $W; $x++) {
        $script:ClkRain[$x] += $script:ClkSpeed[$x]
        if ($script:ClkRain[$x] - 16 -gt $hgt) { $script:ClkRain[$x] = - $rnd.Next(15); $script:ClkSpeed[$x] = $rnd.Next(2) + 1 }
    }
    [pscustomobject]@{ Lines = $lines.ToArray(); Width = $W }
}

# a round face drawn with braille dots (2 × 4 per character, close to square)
function script:Get-LotusClockAnalog {
    param([int]$H, [int]$W, [bool]$Secs, [string]$Date, [datetime]$Now)
    $C = $script:ClkC
    $ch = [Math]::Min(26, [Math]::Max(8, $H - 7))
    $cw = [Math]::Min($ch * 2, $W - 4)
    $R = [Math]::Truncate([Math]::Min($cw * 2, $ch * 4) / 2) - 2
    $centerX = $cw; $centerY = $ch * 2
    $dots = @{}; $cols = @{}
    $plot = {
        param([double]$px, [double]$py, [string]$color)
        $ix = [int][Math]::Round($px, [MidpointRounding]::ToEven); $iy = [int][Math]::Round($py, [MidpointRounding]::ToEven)
        if ($ix -lt 0 -or $iy -lt 0) { return }
        $bit = switch ("$($ix % 2)$($iy % 4)") { '00' { 1 } '01' { 2 } '02' { 4 } '03' { 64 } '10' { 8 } '11' { 16 } '12' { 32 } '13' { 128 } }
        $key = "$([Math]::Truncate($ix / 2)),$([Math]::Truncate($iy / 4))"
        $dots[$key] = [int]$dots[$key] -bor $bit
        $cols[$key] = $color
    }
    $line = {
        param([double]$x0, [double]$y0, [double]$angle, [double]$from, [double]$to, [string]$color)
        $a = ($angle - 90) * 3.14159265 / 180
        for ($rr = $from; $rr -le $to; $rr += 0.5) { & $plot ($x0 + [Math]::Cos($a) * $rr) ($y0 + [Math]::Sin($a) * $rr) $color }
    }
    for ($k = 0; $k -lt 120; $k++) { & $line $centerX $centerY ($k * 3) ($R - 0.5) $R 'border' }
    for ($k = 0; $k -lt 12; $k++) {
        $major = ($k % 3) -eq 0
        & $line $centerX $centerY ($k * 30) ($R * $(if ($major) { 0.76 } else { 0.86 })) ($R - 2) $(if ($major) { 'key' } else { 'dim' })
    }
    $hh = $Now.Hour; $mm = $Now.Minute; $ss = $Now.Second
    & $line $centerX $centerY (($hh % 12) * 30 + $mm * 0.5) 0 ($R * 0.5) 'logo'
    & $line ($centerX + 1) $centerY (($hh % 12) * 30 + $mm * 0.5) 0 ($R * 0.5) 'logo'
    & $line $centerX $centerY ($mm * 6 + $ss * 0.1) 0 ($R * 0.78) 'key'
    if ($Secs) { & $line $centerX $centerY ($ss * 6) 0 ($R * 0.86) 'salute' }
    $lines = [System.Collections.Generic.List[string]]::new()
    for ($y = 0; $y -lt $ch; $y++) {
        $sb = [System.Text.StringBuilder]::new(); $cur = ''
        for ($x = 0; $x -lt $cw; $x++) {
            $bits = [int]$dots["$x,$y"]
            if ($bits) {
                $col = $cols["$x,$y"]
                if ($col -ne $cur) { [void]$sb.Append($C[$col]); $cur = $col }
                [void]$sb.Append([char](0x2800 + $bits))
            } else { [void]$sb.Append(' ') }
        }
        $lines.Add($sb.ToString())
    }
    $t = $Now.ToString($(if ($Secs) { 'HH:mm:ss' } else { 'HH:mm' }))
    $lines.Add("$($C['b'])$($C['key'])$(PadL $t ([Math]::Truncate(($cw + $t.Length) / 2)))")
    $lines.Add("$($C['dim'])$(PadL $Date ([Math]::Truncate(($cw + $Date.Length) / 2)))")
    [pscustomobject]@{ Lines = $lines.ToArray(); Width = $cw }
}

# Here and the zones of the settings: time, day, offset and where the day stands
function script:Get-LotusClockWorld {
    param([bool]$Secs)
    $C = $script:ClkC
    $zones = @(([string]$script:S['LOTUS_CLOCK_ZONES']) -split '\s+' | Where-Object { $_ -match '^[A-Za-z0-9_/+-]+$' })
    $utc = [datetime]::UtcNow
    $here = [datetime]::Now
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($z in @('here') + $zones) {
        if ($z -eq 'here') { $t = $here; $name = T clk_here 'Here'; $off = [TimeZoneInfo]::Local.GetUtcOffset($utc) }
        else {
            $t = Get-LotusClockZoneTime $z $utc
            if (-not $t) { continue }
            $name = (Split-Path -Leaf $z).Replace('_', ' ')
            $off = $script:ClkZones[$z].Tz.GetUtcOffset($utc)
        }
        $tm = $t.ToString($(if ($Secs) { 'HH:mm:ss' } else { 'HH:mm' }))
        $dz = ($t.Date - $here.Date).Days
        $day = if ($dz -gt 0) { '+1' } elseif ($dz -lt 0) { '−1' } else { '' }
        $gmt = 'UTC{0}{1}' -f $(if ($off.TotalMinutes -lt 0) { '-' } else { '+' }), [Math]::Abs([Math]::Truncate($off.TotalHours))
        if ($off.Minutes) { $gmt += ":$([Math]::Abs($off.Minutes))" }
        # 24 hours: the day bright, the night dark, now marked
        $bar = -join (0..23 | ForEach-Object { if ($_ -eq $t.Hour) { "$($C['logo'])●" } elseif ($_ -ge 7 -and $_ -lt 19) { "$($C['key_mid'])▬" } else { "$($C['key_off'])▬" } })
        $color = if ($z -eq 'here') { $C['key'] } else { $C['w'] }
        $lines.Add("$($C['b'])$color$(PadR (Cut $name 16) 16)$($C['r'])  $($C['b'])$(PadR $tm 9)$($C['r'])$($C['salute'])$(PadR $day 3)$($C['dim'])$(PadR $gmt 9)$($C['r']) $bar")
        $lines.Add('')
    }
    if ($lines.Count) { $lines.RemoveAt($lines.Count - 1) }
    [pscustomobject]@{ Lines = $lines.ToArray(); Width = 64 }
}
