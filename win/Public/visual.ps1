# /lotus visual – the audio visualizer, a port of lib/cmd/visual.zsh. No system gives terminal programs the levels of
# what plays, so the motion is simulated and follows the playback state: lively when music plays, calm otherwise.

$script:VisModes = @('bars', 'wave', 'spectrum', 'particles', 'minimal', 'circular', 'retro', 'matrix')
$script:VisLabels = @{ bars = 'Bars'; wave = 'Wave'; spectrum = 'Spectrum'; particles = 'Particles'; minimal = 'Minimal'; circular = 'Circular'; retro = 'Retro terminal'; matrix = 'Matrix' }

function script:Invoke-Lotusvisual {
    param([string]$Cmd, [string[]]$Rest)
    if (-not ((Test-LotusTty) -and (Test-LotusOutTty))) { Write-LotusError 'The visualizer needs a terminal window'; return (St 1) }
    Import-LotusCommand audio
    $mi = [Array]::IndexOf($script:VisModes, [string]$script:S['LOTUS_VISUAL_MODE']); if ($mi -lt 0) { $mi = 0 }
    $v = @{ Gain = 1.0; Energy = 0.3; Target = 0.3; LastNp = -10.0; Np = ''; L = @(); P = @{}; PX = @{}; PY = @{}; PV = @{}; MY = @{}; MS = @{}; Rnd = [System.Random]::new() }
    $esc = [char]27
    $c = @{ logo = (E logo); key = (E key); acc = (E accent); k2 = (E key2); dim = (E dim); r = "$esc[0m" }
    $t0 = [datetime]::UtcNow
    $sizeWas = $null
    Enter-LotusKeys
    Write-LotusRaw "$esc[?1049h$esc[?25l$esc[2J"
    try {
        while ($true) {
            $size = Get-LotusSize
            if (-not $sizeWas -or $size[0] -ne $sizeWas[0] -or $size[1] -ne $sizeWas[1]) {
                $v.W = $size[0]; $v.H = [Math]::Max(8, $size[1] - 3); $v.N = [Math]::Truncate($v.W / 3)
                $v.L = [double[]]::new($v.N + 1); $v.P = @{}; $v.PX = @{}; $v.PY = @{}; $v.PV = @{}; $v.MY = @{}; $v.MS = @{}
                Write-LotusRaw "$esc[2J"; $sizeWas = $size
            }
            $t = ([datetime]::UtcNow - $t0).TotalSeconds
            $mode = $script:VisModes[$mi]
            # the playback state every 2 seconds (one short fastfetch call)
            if ($t - $v.LastNp -gt 2) {
                $v.LastNp = $t
                $np = Get-LotusMediaState
                if ($np) {
                    $v.Np = "$($np.Title)$(if ($np.Artist) { " — $($np.Artist)" })"
                    $v.Target = if ($np.Status -eq 'Playing') { 1.0 } else { 0.25 }
                } else { $v.Np = 'nothing playing'; $v.Target = 0.15 }
            }
            $v.Energy += ($v.Target - $v.Energy) * 0.08
            Update-LotusVisLevels $v $t
            $out = [System.Text.StringBuilder]::new("$esc[H")
            & "Add-LotusVis$mode" $v $out $c $t
            $label = "$($script:VisLabels[$mode])  ·  intensity $(PadL ([string][int]($v.Gain * 100)) 3)%  ·  ♫ $(Cut $v.Np 40)"
            [void]$out.Append("$esc[$($v.H + 2);1H$esc[K  $($c.acc)$label$($c.r)")
            [void]$out.Append("$esc[$($v.H + 3);1H$esc[K  $($c.dim)space mode   + / - intensity   q quit   ·   motion simulated from playback$($c.r)")
            Write-LotusRaw $out.ToString()
            $k = Read-LotusKeyX 0.066
            switch -Regex ($k) {
                '^(space|tab|n)$' { $mi = ($mi + 1) % $script:VisModes.Count; Write-LotusRaw "$esc[2J"; $v.P = @{}; $v.PX = @{}; $v.MY = @{}; break }
                '^[+=]$' { $v.Gain = [Math]::Min(2.0, $v.Gain + 0.2); break }
                '^[-_]$' { $v.Gain = [Math]::Max(0.2, $v.Gain - 0.2); break }
                '^(q|Q|esc|interrupt)$' { $script:VisQuit = $true; break }
            }
            if ($script:VisQuit) { $script:VisQuit = $false; break }
        }
    } finally {
        Write-LotusRaw "$esc[?25h$esc[?1049l"
        Exit-LotusKeys
    }
    $script:S['LOTUS_VISUAL_MODE'] = $script:VisModes[$mi]
    Save-LotusSettings
    St 0
}

# One level (0…1) per band: layered waves, a beat and a little noise, smoothed
function script:Update-LotusVisLevels {
    param($V, [double]$T)
    $n = $V.N
    $beat = if ([Math]::Sin($T * 7.3) -gt 0.75) { 0.35 } else { 0 }
    for ($i = 1; $i -le $n; $i++) {
        $x = 0.45 + 0.3 * [Math]::Sin($T * (1.7 + $i * 0.13) + $i * 0.7) + 0.2 * [Math]::Sin($T * 4.1 - $i * 0.31) + $V.Rnd.Next(100) / 600.0 + $beat * [Math]::Exp(- [Math]::Pow($i - $n * 0.25, 2) / ($n * 3.0))
        $x = $x * $V.Energy * $V.Gain * (1.05 - 0.45 * $i / $n)
        $x = [Math]::Max(0, [Math]::Min(1, $x))
        $prev = $V.L[$i]
        $V.L[$i] = if ($prev -gt $x) { $prev * 0.82 + $x * 0.18 } else { $prev * 0.4 + $x * 0.6 }
    }
}

function script:Add-LotusVisbars {
    param($V, $Out, $C, $T)
    $esc = [char]27
    for ($r = 1; $r -le $V.H; $r++) {
        $col = if ($r -lt $V.H / 3) { $C.logo } elseif ($r -lt 2 * $V.H / 3) { $C.acc } else { $C.key }
        [void]$Out.Append("$col ")
        for ($i = 1; $i -le $V.N; $i++) {
            $h = [int][Math]::Truncate($V.L[$i] * $V.H + 0.5)
            [void]$Out.Append($(if ($V.H - $r -lt $h) { '██ ' } else { '   ' }))
        }
        [void]$Out.Append("$($C.r)$esc[K`n")
    }
}

function script:Add-LotusVisspectrum {
    param($V, $Out, $C, $T)
    $esc = [char]27
    $blocks = @(' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█')
    $n = [Math]::Truncate($V.W / 2)
    for ($i = 1; $i -le $n; $i++) {
        $lv = $V.L[[Math]::Truncate(($i - 1) * $V.N / $n) + 1]
        $p = [double]$V.P[$i]
        $V.P[$i] = if ($p - 0.015 -gt $lv) { $p - 0.015 } else { $lv }
    }
    for ($r = 1; $r -le $V.H; $r++) {
        [void]$Out.Append($C.acc)
        for ($i = 1; $i -le $n; $i++) {
            $lv = $V.L[[Math]::Truncate(($i - 1) * $V.N / $n) + 1] * $V.H * 8
            $full = [Math]::Truncate($lv / 8); $part = [int][Math]::Truncate($lv) % 8
            if ($V.H - $r -lt $full) { [void]$Out.Append('█ ') }
            elseif ($V.H - $r -eq $full -and $part -gt 0) { [void]$Out.Append("$($blocks[$part + 1]) ") }
            elseif ($V.H - $r -eq [Math]::Truncate([double]$V.P[$i] * $V.H)) { [void]$Out.Append("$($C.logo)▔$($C.acc) ") }
            else { [void]$Out.Append('  ') }
        }
        [void]$Out.Append("$($C.r)$esc[K`n")
    }
}

# sparse drawing: erase the points of the last frame, draw the new ones
function script:Add-LotusViswave {
    param($V, $Out, $C, $T)
    $esc = [char]27
    $mid = [Math]::Truncate($V.H / 2)
    for ($x = 1; $x -le $V.W; $x++) {
        if ($V.PY.ContainsKey($x)) { [void]$Out.Append("$esc[$($V.PY[$x]);$($x)H ") }
        $a = [Math]::Sin($x * 0.09 + $T * 3.1) * 0.6 + [Math]::Sin($x * 0.023 - $T * 1.7) * 0.4
        $y = $mid + [int][Math]::Truncate($a * ($V.H / 2 - 1) * (0.15 + $V.Energy * $V.Gain * 0.85))
        $y = [Math]::Max(1, [Math]::Min($V.H, $y))
        $V.PY[$x] = $y
        [void]$Out.Append("$esc[$y;$($x)H$($C.acc)•$($C.r)")
    }
    [void]$Out.Append("$esc[$($V.H + 1);1H")
}

function script:Add-LotusVisparticles {
    param($V, $Out, $C, $T)
    $esc = [char]27
    for ($i = 1; $i -le 70; $i++) {
        if (-not $V.PX.ContainsKey($i)) { $V.PX[$i] = $V.Rnd.Next($V.W) + 1; $V.PY[$i] = [double]($V.H + $V.Rnd.Next($V.H)); $V.PV[$i] = 0.3 + $V.Rnd.Next(100) / 100.0 }
        $y = [int][Math]::Truncate($V.PY[$i])
        if ($y -ge 1 -and $y -le $V.H) { [void]$Out.Append("$esc[$y;$($V.PX[$i])H ") }
        $V.PY[$i] -= $V.PV[$i] * (0.3 + $V.Energy * $V.Gain * 1.6)
        if ($V.PY[$i] -lt 1) { $V.PX[$i] = $V.Rnd.Next($V.W) + 1; $V.PY[$i] = [double]$V.H; $V.PV[$i] = 0.3 + $V.Rnd.Next(100) / 100.0 }
        $y = [int][Math]::Truncate($V.PY[$i])
        if ($y -ge 1 -and $y -le $V.H) {
            if ($V.PV[$i] -gt 0.9) { [void]$Out.Append("$esc[$y;$($V.PX[$i])H$($C.logo)•$($C.r)") } else { [void]$Out.Append("$esc[$y;$($V.PX[$i])H$($C.acc)·$($C.r)") }
        }
    }
    [void]$Out.Append("$esc[$($V.H + 1);1H")
}

function script:Add-LotusVisminimal {
    param($V, $Out, $C, $T)
    $esc = [char]27
    $blocks = @('▁', '▂', '▃', '▄', '▅', '▆', '▇', '█')
    $n = [Math]::Min(64, [Math]::Truncate($V.W / 2)); $y = [Math]::Truncate($V.H / 2)
    $line = -join (1..$n | ForEach-Object { "$($blocks[[int][Math]::Truncate($V.L[[Math]::Truncate(($_ - 1) * $V.N / $n) + 1] * 7)]) " })
    $pad = [string]::new(' ', [Math]::Max(0, [Math]::Truncate(($V.W - $n * 2) / 2)))
    [void]$Out.Append("$esc[$y;1H$esc[K$pad$($C.acc)$line$($C.r)")
    [void]$Out.Append("$esc[$($y + 2);1H$esc[K$pad$($C.dim)$(Cut $V.Np ($n * 2))$($C.r)")
}

function script:Add-LotusViscircular {
    param($V, $Out, $C, $T)
    $esc = [char]27
    $n = 64; $cx = [Math]::Truncate($V.W / 2); $cy = [Math]::Truncate($V.H / 2); $r0 = $V.H / 2.0 - 2
    for ($k = 1; $k -le $n; $k++) {
        if ($V.PX.ContainsKey($k)) { [void]$Out.Append("$esc[$($V.PY[$k]);$($V.PX[$k])H ") }
        $th = $k * 6.2832 / $n + $T * 0.2
        $r = $r0 * (0.45 + 0.55 * $V.L[[Math]::Truncate(($k - 1) * $V.N / $n) + 1])
        $x = [Math]::Max(1, $cx + [int][Math]::Truncate([Math]::Cos($th) * $r * 2.1)); $y = [Math]::Max(1, [Math]::Min($V.H, $cy + [int][Math]::Truncate([Math]::Sin($th) * $r)))
        $V.PX[$k] = $x; $V.PY[$k] = $y
        [void]$Out.Append("$esc[$y;$($x)H$($C.logo)●$($C.r)")
    }
    [void]$Out.Append("$esc[$cy;$($cx - 2)H$($C.dim)lotus$($C.r)$esc[$($V.H + 1);1H")
}

function script:Add-LotusVisretro {
    param($V, $Out, $C, $T)
    $esc = [char]27
    $segs = [Math]::Min(60, $V.W - 16)
    $edge = Get-LotusLine ($segs + 6)
    [void]$Out.Append("$esc[$([Math]::Truncate($V.H / 2) - 3);1H$esc[K  $($C.k2)┌$edge┐$($C.r)`n")
    foreach ($ch in 1, 2) {
        $lv = ($V.L[$ch] + $V.L[[Math]::Truncate($V.N / 2)] + $V.L[$V.N - $ch]) / 3.0
        $lit = [Math]::Truncate($lv * $segs)
        $line = "  $($C.k2)│ $(if ($ch -eq 1) { 'L' } else { 'R' }) "
        for ($seg = 1; $seg -le $segs; $seg++) {
            $col = if ($seg -gt $segs * 0.85) { "$esc[38;5;203m" } elseif ($seg -gt $segs * 0.65) { $C.k2 } else { $C.key }
            $line += if ($seg -le $lit) { "$col▮" } else { "$($C.dim)·" }
        }
        [void]$Out.Append("$line $($C.k2)│$($C.r)$esc[K`n")
    }
    [void]$Out.Append("  $($C.k2)└$edge┘$($C.r)$esc[K`n")
    [void]$Out.Append("    $($C.dim)-40     -20     -10     -5      0  dB$($C.r)$esc[K")
}

function script:Add-LotusVismatrix {
    param($V, $Out, $C, $T)
    $esc = [char]27
    $glyphs = '01ｱｲｳｴｵｶｷｸｹｺ#*+=-:.'
    $n = [Math]::Truncate($V.W / 2)
    for ($col = 1; $col -le $n; $col++) {
        if (-not $V.MY.ContainsKey($col)) { $V.MY[$col] = [double](- $V.Rnd.Next($V.H)); $V.MS[$col] = 0.4 + $V.Rnd.Next(100) / 100.0 }
        $V.MY[$col] += $V.MS[$col] * (0.3 + $V.Energy * $V.Gain * 1.4)
        $y = [int][Math]::Truncate($V.MY[$col])
        if ($y - 8 -ge 1 -and $y - 8 -le $V.H) { [void]$Out.Append("$esc[$($y - 8);$($col * 2)H ") }
        if ($y - 1 -ge 1 -and $y - 1 -le $V.H) { [void]$Out.Append("$esc[$($y - 1);$($col * 2)H$($C.key)$($glyphs[$V.Rnd.Next($glyphs.Length)])") }
        if ($y -ge 1 -and $y -le $V.H) { [void]$Out.Append("$esc[$y;$($col * 2)H$esc[1;97m$($glyphs[$V.Rnd.Next($glyphs.Length)])$($C.r)") }
        if ($y - 8 -gt $V.H) { $V.MY[$col] = [double](- $V.Rnd.Next(10)); $V.MS[$col] = 0.4 + $V.Rnd.Next(100) / 100.0 }
    }
    [void]$Out.Append("$esc[$($V.H + 1);1H")
}
