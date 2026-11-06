# The first-time setup (lotus setup) and the features page (lotus features) – a port of lib/cmd/setup.zsh.
#
#                       (a lotus that opens a little with every step)
#                   ━━━━━  ━━━━━  ━━━━━  ─────  ─────
#         What should Lotus call you?
#         ╭─ Name ─────────────────────────────────────────╮
#         │ Gabriel                                        │
#         ╰────────────────────────────────────────────────╯
#                          ⏎ continue   esc back
#
# Welcome (language) → You (name, theme, start) → Features → setup of the chosen features → Review. Always in the
# Matcha colors; on the theme page the flower takes the colors of the theme you point at, on the welcome page the texts
# switch to the language you point at. Every line is placed by cursor position. Esc goes back a page; nothing is
# saved before Finish. The flower comes from data/lotus-setup.txt.

function script:Invoke-Lotussetup {
    param([string]$Cmd, [string[]]$Rest)
    if ($Cmd -ceq 'features') { return Invoke-LotusFeaturesPage $Rest }
    Invoke-LotusSetupWizard
}

# Features that Windows does not have (yet): what the features page says about them
$script:FeatureNotHere = @{ ios = 'macOS only'; minecraft = 'not on Windows yet'; bg = 'not on Windows yet'; plugins = 'not on Windows yet' }
function script:Get-LotusFeatureAbout {
    param([string]$Id)
    $about = T "featd_$Id" $script:FeatureRow[$Id][3]
    if ($IsWindows -and $Id -ceq 'homebrew') { $about = 'Search winget and install apps from the catalog' }
    if ($IsWindows -and $script:FeatureNotHere.ContainsKey($Id)) { $about += " ($($script:FeatureNotHere[$Id]))" }
    $about
}

# ── The page ──────────────────────────────────────────────────

$script:Sw = @{}
$script:SwBuf = [System.Text.StringBuilder]::new()

function script:SwPut { param([int]$Row, [int]$Col, [string]$Text) [void]$script:SwBuf.Append("$([char]27)[$Row;$($Col)H").Append($Text) }
function script:SwFlush { if ($script:SwBuf.Length) { Write-LotusRaw $script:SwBuf.ToString(); [void]$script:SwBuf.Clear() } }

function script:Initialize-LotusWizard {
    $th = $script:Themes['matcha']
    $script:Sw = @{
        C = @{ pink = (ConvertTo-LotusSgr $th[0]); green = (ConvertTo-LotusSgr $th[1]); yellow = (ConvertTo-LotusSgr $th[3]); dim = (ConvertTo-LotusSgr $th[6]) }
        Step = 1; Stage = 1; Y = 0; X = 0; CW = 0; Foot = 0; AY = 0; PY = 0; QY = 0; ArtOn = $false
        Q = ''; Sub = ''; Hint = ''; Detail = ''; ArtTheme = 'matcha'; OnMove = $null; Paint = $null; ArtFn = $null
        DL = 1; LH = 0; LW = 0; Tick = 0; PF = @{}; Rows = @{}; Art = @(); PetShow = ''
    }
    # the five stages of the flower: rows of pixel codes, one stage per block ending with %
    $cur = [System.Collections.Generic.List[string]]::new()
    $art = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ([string](Read-LotusFile (Join-Path (Get-LotusRoot) 'data/lotus-setup.txt'))) -split "`n") {
        if ($line.StartsWith('#')) { continue }
        if ($line -ceq '%') { $art.Add($cur.ToArray()); $cur.Clear() } elseif ($line) { $cur.Add($line) }
    }
    if ($cur.Count) { $art.Add($cur.ToArray()) }
    $script:Sw.Art = $art.ToArray()
}

# Where everything goes, for the window size (_sw_layout)
function script:Update-LotusWizardLayout {
    $size = Get-LotusSize
    $W = $size[0]; $H = $size[1]
    $sw = $script:Sw
    $sw.LH = $H; $sw.LW = $W
    if ($W -lt 20) { $W = 80 }; if ($H -lt 12) { $H = 24 }
    $sw.CW = [Math]::Min(72, $W - 8)
    if ($sw.CW -lt 30) { $sw.CW = $W - 2 }
    $sw.X = [Math]::Truncate(($W - $sw.CW) / 2) + 1
    $sw.ArtOn = $H -ge 22 -and $W -ge 34
    # designed for 80 × 24; bigger windows get the same picture, a little above the middle
    $top = if ($H -gt 24) { [Math]::Truncate(($H - 24) * 2 / 5) + 1 } else { 1 }
    $sw.Foot = [Math]::Min($top + 23, $H)
    if ($sw.ArtOn) { $sw.AY = $top; $sw.PY = $top + 8 } else { $sw.PY = $top + 1 }
    $sw.QY = $sw.PY + 2
    $sw.W = $W
}

# Was the window resized? Asked about once a second while no key comes
function script:Test-LotusWizardResized {
    $script:Sw.Tick++
    if ($script:Sw.Tick % 3) { return $false }
    $size = Get-LotusSize
    -not ($size[1] -eq $script:Sw.LH -and $size[0] -eq $script:Sw.LW)
}

# Word wrap → lines
function script:Split-LotusWrap {
    param([string]$Text, [int]$Width)
    $lines = [System.Collections.Generic.List[string]]::new()
    $line = ''
    foreach ($word in ($Text -split ' ' | Where-Object { $_ })) {
        if ($line.Length -and $line.Length + $word.Length + 1 -gt $Width) { $lines.Add($line); $line = $word }
        else { $line += $(if ($line) { ' ' }) + $word }
    }
    if ($line) { $lines.Add($line) }
    , $lines.ToArray()
}

# ── The flower ────────────────────────────────────────────────

# One color of a theme's flower (_bgu_ramp: dark below 0.6, light above) → "r;g;b"
function script:Get-LotusRamp {
    param([string]$Rgb, [double]$K)
    $c = @($Rgb -split ';' | ForEach-Object { [double]$_ })
    $m = ($c[0] + $c[1] + $c[2]) / 3.0
    $deep = foreach ($x in $c) { $v = $x * 0.58 - ($m - $x) * 0.7; Get-LotusF10 ([Math]::Max(0, [Math]::Min(255, $v))) }
    $tip = foreach ($x in $c) { $x + (255 - $x) * 0.62 }
    if ($K -lt 0.6) { $a = $deep; $b = $c; $f = $K / 0.6 } else { $a = $c; $b = $tip; $f = ($K - 0.6) / 0.4 }
    (0..2 | ForEach-Object { [long][Math]::Truncate($a[$_] + ($b[$_] - $a[$_]) * $f) }) -join ';'
}

# Pixel codes → colors of a theme: petals from its logo color, the pad from its key color
function script:Get-LotusWizardPalette {
    param([string]$Theme)
    $pf = $script:Sw.PF
    if ($pf.ContainsKey("$Theme,0")) { return }
    $th = $script:Themes[$Theme]; if (-not $th) { $th = $script:Themes['matcha'] }
    for ($n = 0; $n -le 9; $n++) { $pf["$Theme,$n"] = ConvertTo-LotusSgr (Get-LotusRamp $th[0] ($n / 9.0)) }
    $pf["$Theme,g"] = ConvertTo-LotusSgr (Get-LotusRamp $th[1] 0.25)
    $pf["$Theme,G"] = ConvertTo-LotusSgr (Get-LotusRamp $th[1] 0.55)
}

# One row of a stage as half blocks, two pixels per cell
function script:Get-LotusWizardArtRow {
    param([int]$Stage, [int]$Row, [string]$Theme)
    $key = "$Theme,$Stage,$Row"
    $cache = $script:Sw.Rows
    if ($cache.ContainsKey($key)) { return $cache[$key] }
    Get-LotusWizardPalette $Theme
    $pf = $script:Sw.PF
    $px = $script:Sw.Art[$Stage - 1]
    $top = $px[2 * $Row - 2]; $bot = $px[2 * $Row - 1]
    $sb = [System.Text.StringBuilder]::new()
    $cur = 'x'
    for ($c = 0; $c -lt $top.Length; $c++) {
        $t = [string]$top[$c]; $b = [string]$bot[$c]
        if ($t -eq '.' -and $b -eq '.') { $want = '0'; $ch = ' ' }
        elseif ($b -eq '.') { $want = $pf["$Theme,$t"]; $ch = '▀' }
        elseif ($t -eq '.') { $want = $pf["$Theme,$b"]; $ch = '▄' }
        elseif ($t -ceq $b) { $want = $pf["$Theme,$t"]; $ch = '█' }
        else { $want = "$($pf["$Theme,$t"]);48$($pf["$Theme,$b"].Substring(2))"; $ch = '▀' }
        if ($want -cne $cur) { [void]$sb.Append("$([char]27)[0;$($want)m"); $cur = $want }
        [void]$sb.Append($ch)
    }
    $cache[$key] = $sb.ToString() + "$([char]27)[0m"
    $cache[$key]
}

function script:Show-LotusWizardArtAt {
    param([int]$Top, [int]$Stage, [string]$Theme)
    if (-not $script:Sw.Art.Count) { return }
    $x = [Math]::Truncate(($script:Sw.W - 25) / 2) + 1
    for ($r = 1; $r -le 7; $r++) { SwPut ($Top + $r - 1) $x (Get-LotusWizardArtRow $Stage $r $Theme) }
}

function script:Show-LotusWizardArt {
    if (-not $script:Sw.ArtOn) { return }
    if ($script:Sw.ArtFn) { & $script:Sw.ArtFn; return }
    Show-LotusWizardArtAt $script:Sw.AY $script:Sw.Stage $script:Sw.ArtTheme
}

# The five steps: done in green, the current one in pink, the rest thin and dim
function script:Show-LotusWizardProgress {
    $c = $script:Sw.C; $esc = [char]27
    $out = ''
    for ($i = 1; $i -le 5; $i++) {
        if ($i -lt $script:Sw.Step) { $out += "$esc[$($c.green)m━━━━━" }
        elseif ($i -eq $script:Sw.Step) { $out += "$esc[$($c.pink)m━━━━━" }
        else { $out += "$esc[$($c.dim)m─────" }
        if ($i -lt 5) { $out += '  ' }
    }
    SwPut $script:Sw.PY ([Math]::Truncate(($script:Sw.W - 33) / 2) + 1) "$out$esc[0m"
}

function script:Show-LotusWizardHint {
    $h = $script:Sw.Hint; $esc = [char]27
    SwPut $script:Sw.Foot 1 "$esc[2K"
    SwPut $script:Sw.Foot ([Math]::Truncate(($script:Sw.W - $h.Length) / 2) + 1) "$esc[$($script:Sw.C.dim)m$h$esc[0m"
}

# The description of what is highlighted, above the hints (two lines when it needs them)
function script:Show-LotusWizardDetail {
    param([string]$Text)
    $sw = $script:Sw; $esc = [char]27
    $sw.Detail = $Text
    $l = @()
    if ($Text) { $l = @(Split-LotusWrap $Text $sw.CW | Select-Object -First 2) }
    if ($sw.DL -gt 1 -or $l.Count -gt 1) { SwPut ($sw.Foot - 2) 1 "$esc[2K" }
    SwPut ($sw.Foot - 1) 1 "$esc[2K"
    for ($i = 0; $i -lt $l.Count; $i++) { SwPut ($sw.Foot - $l.Count + $i) $sw.X "$esc[$($sw.C.dim)m$($l[$i])$esc[0m" }
    $sw.DL = $l.Count
}

# The whole page: flower, steps, question and explanation; .Y = the first row for the answer
function script:Show-LotusWizardFrame {
    Update-LotusWizardLayout
    $sw = $script:Sw; $esc = [char]27
    [void]$script:SwBuf.Append("$esc[?2026h$esc[0m$esc[2J")
    Show-LotusWizardArt
    Show-LotusWizardProgress
    SwPut $sw.QY $sw.X "$esc[1m$(Cut $sw.Q $sw.CW)$esc[0m"
    $y = $sw.QY + 1; $n = 0
    if ($sw.Sub) {
        foreach ($l in Split-LotusWrap $sw.Sub $sw.CW) { SwPut $y $sw.X "$esc[$($sw.C.dim)m$l$esc[0m"; $y++; $n++ }
    }
    # the answer starts on the same row on every page and in every language
    if ($sw.ArtOn -and $n -lt 2) { $n = 2 }
    $sw.Y = $sw.QY + $n + 2
    Show-LotusWizardHint
    Show-LotusWizardDetail $sw.Detail
    if ($sw.Paint) { & $sw.Paint }
    [void]$script:SwBuf.Append("$esc[?2026l")
    SwFlush
}

function script:Get-LotusWizardRoom { $script:Sw.Foot - 2 - $script:Sw.Y + 1 }

# ── Answers ───────────────────────────────────────────────────

# A list of "Label|Description" entries: labels in one column, descriptions wrapped in the next (_sw_select)
#   → the index, or $null for back. .OnMove hears about the highlighted entry and may change the page's texts.
function script:Read-LotusWizardSelect {
    param([int]$Default, [string[]]$Options)
    $sw = $script:Sw; $esc = [char]27
    $n = $Options.Count
    $sel = if ($Default -lt 1 -or $Default -gt $n) { 1 } else { $Default }
    $p = "$esc[$($sw.C.pink)m"; $g = "$esc[1;$($sw.C.green)m"; $d = "$esc[$($sw.C.dim)m"; $r = "$esc[0m"
    $redraw = $true
    Write-LotusRaw "$esc[?25l"
    while ($true) {
        if ($redraw) {
            $sw.Hint = T ui_select_hint '↑↓ choose   ⏎ continue   esc back'; $sw.Detail = ''
            Show-LotusWizardFrame; $redraw = $false
            $lw = 0
            foreach ($o in $Options) { $lab = ($o -split '\|', 2)[0]; if ($lab.Length -gt $lw) { $lw = $lab.Length } }
            $dw = $sw.CW - 4 - $lw
            $descs = [System.Collections.Generic.List[object]]::new(); $total = 0
            foreach ($o in $Options) {
                $parts = $o -split '\|', 2
                $desc = if ($parts.Count -gt 1) { $parts[1] } else { '' }
                $lines = if ($desc -and $dw -ge 16) { @(Split-LotusWrap $desc $dw) } else { @($desc) }
                if (-not $lines.Count) { $lines = @('') }
                $descs.Add($lines); $total += $lines.Count
            }
            $room = Get-LotusWizardRoom
            $gap = if ($total + $n - 1 -le $room) { 1 } else { 0 }
            if ($total + $gap * ($n - 1) -gt $room) {
                # no room for whole descriptions: one line each, cut
                for ($i = 0; $i -lt $n; $i++) { if ($descs[$i].Count -gt 1) { $descs[$i] = @((Cut $descs[$i][0] ($dw - 1)) + '…') } }
                $gap = if (2 * $n - 1 -le $room) { 1 } else { 0 }
            }
            $pad = [string]::new(' ', $lw + 4)
        }
        $y = $sw.Y
        for ($i = 1; $i -le $n; $i++) {
            $lab = ($Options[$i - 1] -split '\|', 2)[0]; $dl = $descs[$i - 1]
            if ($i -eq $sel) { SwPut $y $sw.X "$esc[K$p❯$r $g$(PadR $lab $lw)$r  $d$($dl[0])$r" }
            else { SwPut $y $sw.X "$esc[K  $(PadR $lab $lw)  $d$($dl[0])$r" }
            for ($j = 1; $j -lt $dl.Count; $j++) { SwPut ($y + $j) $sw.X "$esc[K$pad$d$($dl[$j])$r" }
            $y += $dl.Count + $gap
        }
        SwFlush
        $was = $sel
        $k = Read-LotusKeyX 0.3
        switch -Regex ($k) {
            '^timeout$' { if (Test-LotusWizardResized) { $redraw = $true }; continue }
            '^up$' { $sel = if ($sel -gt 1) { $sel - 1 } else { $n } }
            '^(down|tab)$' { $sel = if ($sel -lt $n) { $sel + 1 } else { 1 } }
            '^(enter|space|right)$' { return $sel }
            '^(esc|left|q|interrupt)$' { if ($k -eq 'interrupt') { $script:SwInt = $true }; return $null }
            '^[1-9]$' { if ([int]$k -le $n) { $sel = [int]$k } }
        }
        if ($sel -ne $was -and $sw.OnMove) { & $sw.OnMove $sel; $redraw = $true }
    }
}

# A grid of short entries, filled column by column (_sw_grid radio|check <columns> <default> "Label|Description|Extra" …)
#   radio: ⏎ picks → the index · check: space turns on and off ($script:Toggles), ⏎ continues → $true; $null = back
function script:Read-LotusWizardGrid {
    param([string]$Mode, [int]$Cols, [int]$Default, [string[]]$Items)
    $sw = $script:Sw; $esc = [char]27
    $n = $Items.Count
    $sel = if ($Default -lt 1 -or $Default -gt $n) { 1 } else { $Default }
    $p = "$esc[$($sw.C.pink)m"; $g = "$esc[1;$($sw.C.green)m"; $kc = "$esc[$($sw.C.green)m"; $d = "$esc[$($sw.C.dim)m"; $r = "$esc[0m"
    $redraw = $true
    Write-LotusRaw "$esc[?25l"
    while ($true) {
        if ($redraw) {
            $rows = [Math]::Truncate(($n + $Cols - 1) / $Cols); $cw = [Math]::Truncate($sw.CW / $Cols)
            $sw.Hint = if ($Mode -eq 'check') { T ui_toggle_hint '↑↓ move   space on/off   ⏎ continue   esc back' } else { T ui_select_hint '↑↓ choose   ⏎ continue   esc back' }
            $sw.Hint = $sw.Hint.Replace('↑↓', '←↑↓→')
            Show-LotusWizardFrame; $redraw = $false
            $lw = 0; foreach ($it in $Items) { $l = ($it -split '\|')[0]; if ($l.Length -gt $lw) { $lw = $l.Length } }
        }
        for ($i = 1; $i -le $n; $i++) {
            $f = $Items[$i - 1] -split '\|'
            $x = $sw.X + [Math]::Truncate(($i - 1) / $rows) * $cw; $y = $sw.Y + ($i - 1) % $rows
            if ($Mode -eq 'check') {
                $mark = if ($script:Toggles[$i - 1]) { "$kc◉$r" } else { "$d○$r" }
                $cell = if ($i -eq $sel) { "$p❯$r $mark $g$(PadR $f[0] $lw)$r" } else { "  $mark $(PadR $f[0] $lw)" }
            } else {
                $extra = if ($f.Count -gt 2) { $f[2] } else { '' }
                $cell = if ($i -eq $sel) { "$p❯$r $g$(PadR $f[0] $lw)$r $extra" } else { "  $(PadR $f[0] $lw) $extra" }
            }
            SwPut $y $x $cell
        }
        $f = $Items[$sel - 1] -split '\|'
        Show-LotusWizardDetail $(if ($f.Count -gt 1) { $f[1] } else { '' })
        SwFlush
        $was = $sel
        $k = Read-LotusKeyX 0.3
        switch -Regex ($k) {
            '^timeout$' { if (Test-LotusWizardResized) { $redraw = $true }; continue }
            '^up$' { $sel = if ($sel -gt 1) { $sel - 1 } else { $n } }
            '^(down|tab)$' { $sel = if ($sel -lt $n) { $sel + 1 } else { 1 } }
            '^left$' { if ($sel -gt $rows) { $sel -= $rows } }
            '^right$' { if ($sel + $rows -le $n) { $sel += $rows } }
            '^(space|x)$' { if ($Mode -eq 'check') { $script:Toggles[$sel - 1] = [int](-not $script:Toggles[$sel - 1]) } }
            '^a$' { if ($Mode -eq 'check') { for ($i = 0; $i -lt $n; $i++) { $script:Toggles[$i] = 1 } } }
            '^enter$' { if ($Mode -eq 'check') { return $true }; return $sel }
            '^(esc|q|interrupt)$' { if ($k -eq 'interrupt') { $script:SwInt = $true }; return $null }
        }
        if ($sel -ne $was -and $sw.OnMove) { & $sw.OnMove $sel }
    }
}

# One line of text in a rounded box (_sw_input): the text shown first is a suggestion (dim) – ⏎ keeps it, typing
# replaces it, ⌫ edits it → the text, or $null for back
function script:Read-LotusWizardInput {
    param([string]$Label, [string]$Text)
    $sw = $script:Sw; $esc = [char]27
    $fresh = $Text.Length -gt 0
    $k = "$esc[$($sw.C.green)m"; $b = "$esc[1m"; $r = "$esc[0m"
    $redraw = $true
    while ($true) {
        if ($redraw) {
            Write-LotusRaw "$esc[?25l"
            $hint = T ui_select_hint '↑↓ choose   ⏎ continue   esc back'
            $sw.Hint = if ($hint.Contains('   ')) { $hint.Substring($hint.IndexOf('   ') + 3) } else { $hint }
            $sw.Detail = ''
            Show-LotusWizardFrame; $redraw = $false
            $bw = [Math]::Min(52, $sw.CW); $inner = $bw - 4
            SwPut $sw.Y $sw.X "$k╭─ $r$b$Label$r $k$(Get-LotusLine ([Math]::Max(1, $bw - 5 - $Label.Length)))╮$r"
            SwPut ($sw.Y + 1) $sw.X "$k│$r"; SwPut ($sw.Y + 1) ($sw.X + $bw - 1) "$k│$r"
            SwPut ($sw.Y + 2) $sw.X "$k╰$(Get-LotusLine ($bw - 2))╯$r"
        }
        $shown = $Text
        if ($shown.Length -gt $inner - 1) { $shown = '…' + $shown.Substring($shown.Length - ($inner - 2)) }
        if ($fresh) { SwPut ($sw.Y + 1) ($sw.X + 2) "$esc[$($sw.C.dim)m$(PadR $shown $inner)$r" }
        else { SwPut ($sw.Y + 1) ($sw.X + 2) (PadR $shown $inner) }
        [void]$script:SwBuf.Append("$esc[$($sw.Y + 1);$($sw.X + 2 + $shown.Length)H$esc[?25h")
        SwFlush
        $key = Read-LotusKeyX 0.3
        switch -Regex ($key) {
            '^timeout$' { if (Test-LotusWizardResized) { $redraw = $true }; continue }
            '^enter$' { Write-LotusRaw "$esc[?25l"; return $Text }
            '^(esc|interrupt)$' { if ($key -eq 'interrupt') { $script:SwInt = $true }; Write-LotusRaw "$esc[?25l"; return $null }
            '^back$' { if ($Text.Length) { $Text = $Text.Substring(0, $Text.Length - 1) }; $fresh = $false; continue }
            '^space$' { if ($fresh) { $Text = ''; $fresh = $false }; $Text += ' '; continue }
            '^(up|down|left|right|home|end|pgup|pgdn|tab|backtab|ignore)$' { continue }
            default {
                if ($key.Length -eq 1 -and -not [char]::IsControl($key[0])) {
                    if ($fresh) { $Text = ''; $fresh = $false }
                    if ($Text.Length -lt 200) { $Text += $key }
                }
            }
        }
    }
}

# Buttons on the line above the hints, the chosen one filled (_sw_buttons) → the index, or $null
function script:Read-LotusWizardButtons {
    param([int]$Default, [string[]]$Labels)
    $sw = $script:Sw; $esc = [char]27
    $n = $Labels.Count; $sel = $Default
    $on = "$esc[1;$($sw.C.green);7m"; $off = "$esc[$($sw.C.dim)m"; $r = "$esc[0m"
    $redraw = $true
    Write-LotusRaw "$esc[?25l"
    while ($true) {
        if ($redraw) {
            $sw.Hint = (T ui_select_hint '↑↓ choose   ⏎ continue   esc back').Replace('↑↓', '←→'); $sw.Detail = ''
            Show-LotusWizardFrame; $redraw = $false
        }
        $out = ''; $w = 0
        for ($i = 1; $i -le $n; $i++) {
            $out += if ($i -eq $sel) { "$on  $($Labels[$i - 1])  $r" } else { "$off  $($Labels[$i - 1])  $r" }
            $w += $Labels[$i - 1].Length + 4
            if ($i -lt $n) { $out += '    '; $w += 4 }
        }
        SwPut ($sw.Foot - 1) 1 "$esc[2K"
        SwPut ($sw.Foot - 1) ([Math]::Truncate(($sw.W - $w) / 2) + 1) $out
        SwFlush
        $k = Read-LotusKeyX 0.3
        switch -Regex ($k) {
            '^timeout$' { if (Test-LotusWizardResized) { $redraw = $true } }
            '^(left|up)$' { $sel = if ($sel -gt 1) { $sel - 1 } else { $n } }
            '^(right|down|tab)$' { $sel = if ($sel -lt $n) { $sel + 1 } else { 1 } }
            '^(enter|space)$' { return $sel }
            '^(esc|q|interrupt)$' { if ($k -eq 'interrupt') { $script:SwInt = $true }; return $null }
        }
    }
}

# ── The pages ─────────────────────────────────────────────────

function script:Set-LotusWizardLang {
    param([string]$Lang)
    $script:S['LOTUS_LANG'] = $Lang
    Import-LotusLang
    Import-LotusLangGroup setup
    if (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/pets.ps1')) { Import-LotusLangGroup pets }
}

function script:Show-LotusWizardLang {
    $sw = $script:Sw
    $sw.Step = 1; $sw.Stage = 1
    $langs = @('en', 'de', 'fr', 'es')
    $sw.Q = T sw_welcome; $sw.Sub = T sw_welcome_sub
    # (a script block of this module, not a closure: it has to see the module's functions)
    $sw.OnMove = { param($i) $l = @('en', 'de', 'fr', 'es'); Set-LotusWizardLang $l[$i - 1]; $script:Sw.Q = T sw_welcome; $script:Sw.Sub = T sw_welcome_sub }
    $def = [Array]::IndexOf($langs, [string]$script:S['LOTUS_LANG']) + 1
    $r = Read-LotusWizardSelect $def @('English|Lotus speaks English', 'Deutsch|Lotus spricht Deutsch', 'Français|Lotus parle français', 'Español|Lotus habla español')
    $sw.OnMove = $null
    $null -ne $r
}

function script:Show-LotusWizardName {
    $sw = $script:Sw
    $sw.Step = 2; $sw.Stage = 2; $sw.Q = T sw_name_q; $sw.Sub = T sw_name_sub
    $r = Read-LotusWizardInput (T name 'Name') ([string]$script:S['LOTUS_NAME'])
    if ($null -eq $r) { return $false }
    if ($r.Trim()) { $script:S['LOTUS_NAME'] = $r.Trim() }
    $true
}

function script:Show-LotusWizardTheme {
    $sw = $script:Sw; $esc = [char]27
    $sw.Step = 2; $sw.Stage = 2; $sw.Q = T sw_theme_q; $sw.Sub = T sw_theme_sub
    $names = @($script:ThemeNames)
    $items = foreach ($n in $names) {
        $rgb = $script:Themes[$n]
        $swatch = (0, 1, 3 | ForEach-Object { "$esc[$(ConvertTo-LotusSgr $rgb[$_])m■" }) -join ''
        "$($script:ThemeLabels[$n])||$swatch$esc[0m"
    }
    $script:SwNames = $names
    $sw.OnMove = { param($i) $script:Sw.ArtTheme = $script:SwNames[$i - 1]; Show-LotusWizardArt; SwFlush }
    $sw.ArtTheme = $script:S['LOTUS_THEME']
    $def = [Array]::IndexOf($names, [string]$script:S['LOTUS_THEME']) + 1
    $r = Read-LotusWizardGrid 'radio' $(if ($sw.CW -ge 54) { 3 } else { 2 }) $def @($items)
    $sw.OnMove = $null; $sw.ArtTheme = 'matcha'
    if ($null -eq $r) { return $false }
    $script:S['LOTUS_THEME'] = $names[$r - 1]
    $true
}

function script:Show-LotusWizardStart {
    $sw = $script:Sw
    $sw.Step = 2; $sw.Stage = 2; $sw.Q = T sw_start_q; $sw.Sub = ''
    $r = Read-LotusWizardSelect $(if (Test-LotusOn $script:S['LOTUS_STARTUP']) { 1 } else { 2 }) @("$(T sw_start_yes)|$(T sw_start_yes_d)", "$(T sw_start_no)|$(T sw_start_no_d)")
    if ($null -eq $r) { return $false }
    $script:S['LOTUS_STARTUP'] = if ($r -eq 1) { '1' } else { '0' }
    $true
}

function script:Show-LotusWizardFeatures {
    $sw = $script:Sw
    $sw.Step = 3; $sw.Stage = 3; $sw.Q = T sw_feat_q; $sw.Sub = T sw_feat_wsub
    $ids = @($script:FeatureIds | Where-Object { $_ -cne 'core' })
    $items = foreach ($id in $ids) { "$(Get-LotusFeatureLabel $id)|$(Get-LotusFeatureAbout $id)" }
    $script:Toggles = [System.Collections.Generic.List[int]]::new()
    foreach ($id in $ids) { $script:Toggles.Add([int](Test-LotusFeature $id)) }
    $r = Read-LotusWizardGrid 'check' $(if ($sw.CW -ge 44) { 2 } else { 1 }) 1 @($items)
    if ($null -eq $r) { return $false }
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $on = Test-LotusFeature $ids[$i]
        if ($on -and -not $script:Toggles[$i]) { Set-LotusFeature $ids[$i] $false }
        if (-not $on -and $script:Toggles[$i]) { Set-LotusFeature $ids[$i] $true }
    }
    $true
}

function script:Show-LotusWizardWeather {
    $sw = $script:Sw
    $sw.Step = 4; $sw.Stage = 4; $sw.Q = T sw_weather_q; $sw.Sub = T sw_weather_sub
    $r = Read-LotusWizardInput (T sw_city 'City') ([string]$script:S['LOTUS_WEATHER_LOCATION'])
    if ($null -eq $r) { return $false }
    $script:S['LOTUS_WEATHER_LOCATION'] = $r.Trim()
    $true
}

function script:Show-LotusWizardAi {
    $sw = $script:Sw
    $sw.Step = 4; $sw.Stage = 4; $sw.Q = T sw_ai_q; $sw.Sub = T sw_ai_sub
    $r = Read-LotusWizardSelect $(if ($script:SwClaude) { 2 } else { 1 }) @("$(T sw_ai_later)|$(T sw_ai_later_d)", "$(T sw_ai_claude)|$(T sw_ai_claude_d)")
    if ($null -eq $r) { return $false }
    $script:SwClaude = $r -eq 2
    $true
}

# A pet moves in (when Pets is on and there is none yet): which kind, then its name. The lotus makes room for the
# pet you point at.
function script:Show-LotusWizardPetArt {
    $sw = $script:Sw; $esc = [char]27
    $kind = $sw.PetShow
    if (-not $kind) { Show-LotusWizardArtAt $sw.AY $sw.Stage 'matcha'; return }
    $rows = @(Get-LotusPetArtLines $kind 'idle')
    $x = [Math]::Truncate(($sw.W - (Get-LotusPetArtWidth $kind)) / 2) + 1
    for ($r = 0; $r -lt 7; $r++) { SwPut ($sw.AY + $r) 1 "$esc[2K" }
    $y = $sw.AY + [Math]::Truncate((7 - $rows.Count) / 2)
    for ($r = 0; $r -lt $rows.Count; $r++) { SwPut ($y + $r) $x "$esc[$($sw.C.pink)m$($rows[$r])$esc[0m" }
}

function script:Show-LotusWizardPet {
    $sw = $script:Sw
    $sw.Step = 4; $sw.Stage = 4; $sw.Q = T sw_pet_q; $sw.Sub = T sw_pet_sub
    $kinds = @($script:PetKinds | Select-Object -First 4)
    $opts = @(foreach ($k in $kinds) { "$(Get-LotusPetKindLabel $k)|$(Get-LotusPetKindAbout $k)" }) + @("$(T sw_pet_none)|$(T sw_pet_none_d)")
    $def = [Array]::IndexOf($kinds, [string]$script:SwPetKind) + 1
    if ($def -lt 1) { $def = $kinds.Count + 1 }
    if (-not $script:SwPetKind -and -not $script:SwPetSeen) { $def = 1 }
    $script:SwKinds = $kinds
    $sw.PetShow = if ($def -le $kinds.Count) { $kinds[$def - 1] } else { '' }
    $sw.ArtFn = { Show-LotusWizardPetArt }
    $sw.OnMove = { param($i) $script:Sw.PetShow = if ($i -le $script:SwKinds.Count) { $script:SwKinds[$i - 1] } else { '' } }
    $r = Read-LotusWizardSelect $def $opts
    $sw.OnMove = $null; $sw.ArtFn = $null
    if ($null -eq $r) { return $false }
    $script:SwPetSeen = $true
    $script:SwPetKind = if ($r -gt $kinds.Count) { '' } else { $kinds[$r - 1] }
    $true
}

function script:Show-LotusWizardPetName {
    if (-not $script:SwPetKind) { return $true }
    $sw = $script:Sw
    $sw.Step = 4; $sw.Stage = 4
    $sw.Q = (T sw_petname_q).Replace('%s', (Get-LotusPetKindLabel $script:SwPetKind).ToLower()); $sw.Sub = T sw_petname_sub
    $ideas = @((Get-LotusPetInfo $script:SwPetKind 'names') -split ', ' | Where-Object { $_ })
    $name = if ($script:SwPetName) { $script:SwPetName } elseif ($ideas.Count) { $ideas[0] } else { 'Mochi' }
    $sw.PetShow = $script:SwPetKind; $sw.ArtFn = { Show-LotusWizardPetArt }
    while ($true) {
        $r = Read-LotusWizardInput (T pt_name 'Name') $name
        if ($null -eq $r) { $sw.ArtFn = $null; $sw.Detail = ''; return $false }
        $name = $r.Trim()
        if (-not $name) { $name = if ($ideas.Count) { $ideas[0] } else { 'Mochi' } }
        if (-not (Test-LotusPetName $name)) { $sw.Detail = T pt_name_bad }
        elseif ((Get-Command $name -ErrorAction SilentlyContinue) -or $name.ToLowerInvariant() -cin 'lotus', 'pet', 'pets', 'feed', 'help', 'ai', 'bg') { $sw.Detail = (T pt_name_cmd).Replace('%s', $name) }
        else { break }
    }
    $sw.ArtFn = $null; $sw.Detail = ''
    $script:SwPetName = $name
    $true
}

# Review: everything at a glance, then Back or Finish
function script:Show-LotusWizardReviewPaint {
    $sw = $script:Sw; $esc = [char]27
    $d = "$esc[$($sw.C.dim)m"; $r = "$esc[0m"
    $on = @(); $off = @(); $total = 0
    foreach ($id in $script:FeatureIds) { if ($id -ceq 'core') { continue }; $total++; if (Test-LotusFeature $id) { $on += Get-LotusFeatureLabel $id } else { $off += Get-LotusFeatureLabel $id } }
    $rgb = $script:Themes[$script:S['LOTUS_THEME']]
    $swatch = (0, 1, 3 | ForEach-Object { "$esc[$(ConvertTo-LotusSgr $rgb[$_])m■" }) -join ''
    $lang = switch ($script:S['LOTUS_LANG']) { 'de' { 'Deutsch' } 'fr' { 'Français' } 'es' { 'Español' } default { 'English' } }
    $rows = [System.Collections.Generic.List[string]]::new()
    $rows.Add("$(T name 'Name')|$(if ($script:S['LOTUS_NAME']) { $script:S['LOTUS_NAME'] } else { '–' })")
    $rows.Add("$(T lang 'Language')|$lang")
    $rows.Add("$(T theme 'Theme')|$($script:ThemeLabels[$script:S['LOTUS_THEME']])  $swatch$r")
    $rows.Add("$(T sw_start)|$(if (Test-LotusOn $script:S['LOTUS_STARTUP']) { T sw_start_auto } else { T sw_start_manual })")
    $feat = (T sw_feat_sum).Replace('%s', "$($on.Count)").Replace('%t', "$total")
    if ($off.Count) { $feat += " · $(T sw_disabled): $($off -join ', ')" }
    $rows.Add("$(T sw_s3)|$feat")
    if ($script:SwPetKind -and $script:SwPetName -and (Test-LotusFeature 'pets')) { $rows.Add("$(T pt_title 'Pets')|$($script:SwPetName) · $(Get-LotusPetKindLabel $script:SwPetKind)") }
    if ((Test-LotusFeature 'weather') -and $script:S['LOTUS_WEATHER_LOCATION']) { $rows.Add("$(T sw_city)|$($script:S['LOTUS_WEATHER_LOCATION'])") }
    if ((Test-LotusFeature 'ai') -and $script:SwClaude) { $rows.Add("$(Get-LotusFeatureLabel ai)|$(T sw_ai_claude)") }
    $room = (Get-LotusWizardRoom) - 1
    $show = @($rows | Select-Object -First ([Math]::Max(0, $room)))
    $lw = 0; foreach ($x in $show) { $k = ($x -split '\|', 2)[0]; if ($k.Length -gt $lw) { $lw = $k.Length } }
    $i = 0
    foreach ($x in $show) {
        $p = $x -split '\|', 2
        $v = $p[1]
        if (-not $v.Contains([string][char]27) -and $v.Length -gt $sw.CW - $lw - 3) { $v = (Cut $v ($sw.CW - $lw - 4)) + '…' }
        SwPut ($sw.Y + $i) $sw.X "$d$(PadR $p[0] ($lw + 3))$r$v"
        $i++
    }
}

function script:Show-LotusWizardReview {
    $sw = $script:Sw
    $sw.Step = 5; $sw.Stage = 5; $sw.Q = T sw_ready; $sw.Sub = ''
    $sw.Paint = { Show-LotusWizardReviewPaint }
    $r = Read-LotusWizardButtons 2 @((T sw_back 'Back'), (T sw_finish 'Finish'))
    $sw.Paint = $null
    $r -eq 2
}

# Esc on the first page: stay or leave → $true = leave
function script:Show-LotusWizardQuit {
    $sw = $script:Sw
    $sw.Q = T sw_quit_t
    $sw.Sub = if (Test-LotusOn $script:S['LOTUS_CONFIGURED']) { T sw_quit_cfg } else { T sw_quit_new }
    $r = Read-LotusWizardButtons 1 @((T sw_quit_stay 'Stay'), (T sw_quit_leave 'Leave'))
    $r -eq 2
}

# ── The end: pollen from the lotus writes "Hello" and your name ─────

$script:SwPlain = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
foreach ($p in @('âa', 'ãa', 'åa', 'ëe', 'îi', 'ìi', 'ïi', 'ôo', 'òo', 'õo', 'ûu', 'ùu', 'ýy', 'ÿy', 'ÀA', 'ÁA', 'ÂA', 'ÃA', 'ÄA', 'ÅA', 'ÇC', 'ÈE', 'ÉE', 'ÊE', 'ËE', 'ÌI', 'ÍI', 'ÎI', 'ÏI', 'ÑN', 'ÒO', 'ÓO', 'ÔO', 'ÕO', 'ÖO', 'ÙU', 'ÚU', 'ÛU', 'ÜU', 'ÝY')) { $script:SwPlain[$p.Substring(0, 1)] = $p.Substring(1) }

# data/dotfont.txt → character → 8 rows of . and #
function script:Get-LotusDotFont {
    if ($script:DotFont) { return $script:DotFont }
    $font = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::Ordinal)
    $ch = $null; $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ([string](Read-LotusFile (Join-Path (Get-LotusRoot) 'data/dotfont.txt'))) -split "`n") {
        if ($line.StartsWith('# ')) { continue }
        if ($line.StartsWith('= ')) {
            if ($null -ne $ch) { $font[$ch] = $rows.ToArray() }
            $ch = $line.Substring(2); $rows.Clear()
        } elseif ($line) { $rows.Add($line) }
    }
    if ($null -ne $ch) { $font[$ch] = $rows.ToArray() }
    $script:DotFont = $font
    $font
}

# The dots of a text → @{ X; Y; Width } (step 1: dense, 8 dots high · step 2: every second dot); $null when a letter is missing
function script:Get-LotusDots {
    param([string]$Text, [int]$Step)
    $font = Get-LotusDotFont
    $dx = [System.Collections.Generic.List[int]]::new(); $dy = [System.Collections.Generic.List[int]]::new()
    $x = 0
    foreach ($c in $Text.ToCharArray()) {
        $ch = [string]$c
        if ($script:SwPlain.ContainsKey($ch)) { $ch = $script:SwPlain[$ch] }
        if ($ch -eq ' ') { $x += 3 * $Step; continue }
        $g = $null
        if (-not $font.TryGetValue($ch, [ref]$g)) { return $null }
        $c0 = 6; $c1 = 0
        foreach ($row in $g) { for ($j = 1; $j -le 5 -and $j -le $row.Length; $j++) { if ($row[$j - 1] -eq '#') { if ($j -lt $c0) { $c0 = $j }; if ($j -gt $c1) { $c1 = $j } } } }
        for ($j = 1; $j -le 8 -and $j -le $g.Count; $j++) {
            $row = $g[$j - 1]
            for ($cc = $c0; $cc -le $c1; $cc++) { if ($cc -le $row.Length -and $row[$cc - 1] -eq '#') { $dx.Add($x + ($cc - $c0) * $Step); $dy.Add(($j - 1) * $Step) } }
        }
        $x += ($c1 - $c0 + 2) * $Step
    }
    $w = $x - 2 * $Step + 1
    if ($w -le 0) { return $null }
    [pscustomobject]@{ X = $dx.ToArray(); Y = $dy.ToArray(); Width = $w }
}

# Finish: the lotus opens all the way, its pollen flies up and writes "Hello" (in big dots) and, a little smaller, your
# name – then the dots twinkle for a moment. Any key skips it. The dots are braille: two by four per cell.
function script:Show-LotusWizardFinale {
    Update-LotusWizardLayout
    $sw = $script:Sw; $esc = [char]27
    $W = $sw.W; $H = (Get-LotusSize)[1]; $art = $sw.ArtOn
    $hello = T sw_hello 'Hello'; $name = ([string]$script:S['LOTUS_NAME']).Trim(); $tip = T sw_done_hint
    $words = $true
    $hd = Get-LotusDots $hello 2
    if (-not $hd -or [Math]::Truncate(($hd.Width + 1) / 2) + 4 -gt $W -or $H -lt 14) { $words = $false }
    $nd = $null; $plainname = ''
    if ($name -and $words) {
        $nd = Get-LotusDots $name 1
        if (-not $nd -or [Math]::Truncate(($nd.Width + 1) / 2) + 4 -gt $W) { $nd = $null; $plainname = $name }
    }
    # rows: Hello (4) · the name (2) · the lotus (7) · the tip, centered as one block
    $hr = 1; $nr = $hr + 5; $below = if ($name) { $nr + 2 } else { $hr + 4 }; $ar = $below + 2; $tr = if ($art) { $ar + 8 } else { $below + 1 }
    $top = [Math]::Max(0, [Math]::Truncate(($H - $tr) / 2))
    $hr += $top; $nr += $top; $ar += $top; $tr += $top
    $green = "$esc[1;$($sw.C.green)m"; $dim = "$esc[$($sw.C.dim)m"; $r0 = "$esc[0m"
    [void]$script:SwBuf.Append("$esc[?25l$esc[0m$esc[2J")
    if (-not $words) {
        $msg = "$hello$(if ($name) { ", $name" })"
        if ($art) { Show-LotusWizardArtAt $ar 5 'matcha' }
        SwPut $hr ([Math]::Truncate(($W - $msg.Length) / 2) + 1) "$green$msg$r0"
        SwPut $tr ([Math]::Truncate(($W - $tip.Length) / 2) + 1) "$dim$tip$r0"
        SwFlush
        [void](Read-LotusKeyX 2)
        return
    }
    # every dot of the words is one grain of pollen: it starts just above the flower and flies to its place
    $rnd = [System.Random]::new()
    $px = [System.Collections.Generic.List[double]]::new(); $py = [System.Collections.Generic.List[double]]::new()
    $pdx = [System.Collections.Generic.List[double]]::new(); $pdy = [System.Collections.Generic.List[double]]::new()
    $pw = [System.Collections.Generic.List[double]]::new(); $pd = [System.Collections.Generic.List[double]]::new(); $pg = [System.Collections.Generic.List[int]]::new()
    $sy0 = if ($art) { ($ar - 1) * 4 - 2 } else { ($tr - 1) * 4 - 6 }
    $cx = $W
    $lx = [Math]::Truncate(($W - [Math]::Truncate(($hd.Width + 1) / 2)) / 2) * 2; $ly = ($hr - 1) * 4
    $cmin = [Math]::Min($lx, $cx - 10); $cmax = [Math]::Max($lx + $hd.Width, $cx + 10)
    $maxd = 0.0
    for ($i = 0; $i -lt $hd.X.Count; $i++) {
        $sx = $cx + $rnd.Next(21) - 10; $syy = $sy0 - $rnd.Next(3)
        $d = 0.3 + 0.55 * $hd.X[$i] / $hd.Width + $rnd.Next(15) / 100.0
        $px.Add($sx); $py.Add($syy); $pdx.Add($lx + $hd.X[$i] - $sx); $pdy.Add($ly + $hd.Y[$i] - $syy); $pw.Add($rnd.Next(13) - 6); $pd.Add($d); $pg.Add(2)
        if ($d -gt $maxd) { $maxd = $d }
    }
    # Hello in a soft gradient from the petal pink to peach
    $c1 = @($script:Themes['matcha'][0] -split ';' | ForEach-Object { [int]$_ }); $c2 = @($script:Themes['matcha'][4] -split ';' | ForEach-Object { [int]$_ })
    $hc0 = [Math]::Truncate($lx / 2); $hcs = [Math]::Truncate(($hd.Width + 1) / 2)
    $hg = @{}
    for ($c = 0; $c -lt $hcs; $c++) {
        $den = if ($hcs -gt 1) { $hcs - 1 } else { 1 }
        $mix = (0..2 | ForEach-Object { $c1[$_] + [Math]::Truncate(($c2[$_] - $c1[$_]) * $c / $den) }) -join ';'
        $hg[$hc0 + $c] = ConvertTo-LotusSgr $mix
    }
    if ($nd) {
        $lx = [Math]::Truncate(($W - [Math]::Truncate(($nd.Width + 1) / 2)) / 2) * 2; $ly = ($nr - 1) * 4
        $cmin = [Math]::Min($cmin, $lx); $cmax = [Math]::Max($cmax, $lx + $nd.Width)
        for ($i = 0; $i -lt $nd.X.Count; $i++) {
            $sx = $cx + $rnd.Next(21) - 10; $syy = $sy0 - $rnd.Next(3)
            $d = 0.8 + 0.45 * $nd.X[$i] / $nd.Width + $rnd.Next(15) / 100.0
            $px.Add($sx); $py.Add($syy); $pdx.Add($lx + $nd.X[$i] - $sx); $pdy.Add($ly + $nd.Y[$i] - $syy); $pw.Add($rnd.Next(13) - 6); $pd.Add($d); $pg.Add(3)
            if ($d -gt $maxd) { $maxd = $d }
        }
    }
    $n = $px.Count
    $cmin = [Math]::Max(0, [Math]::Truncate(($cmin - 7) / 2)); $cmax = [Math]::Min($W - 1, [Math]::Truncate(($cmax + 7) / 2))
    $rmin = $hr - 1; $rmax = [Math]::Truncate($sy0 / 4)
    if ($plainname) { SwPut $nr ([Math]::Truncate(($W - $plainname.Length) / 2) + 1) "$green$plainname$r0" }
    $t0 = [datetime]::UtcNow; $dur = 0.8; $tset = $maxd + $dur; $tend = $tset + 1.6
    $stage = 2; $hint = $false
    $bit = @(1, 2, 4, 64, 8, 16, 32, 128)
    $ycol = $sw.C.yellow; $gcol = "1;$($sw.C.green)"; $pink = $sw.C.pink
    while ($true) {
        $t = ([datetime]::UtcNow - $t0).TotalSeconds
        if ($art -and $stage -lt 5 -and $t -ge ($stage - 2) * 0.1) { $stage++; Show-LotusWizardArtAt $ar $stage 'matcha' }
        $dots = @{}; $dotColor = @{}
        for ($i = 0; $i -lt $n; $i++) {
            $p = ($t - $pd[$i]) / $dur
            if ($p -le 0) { continue }
            if ($p -ge 1) {
                if ($t -gt $tset - 0.3 -and $rnd.Next(40) -eq 0) { continue }        # landed dots twinkle
                $x = [int]($px[$i] + $pdx[$i]); $y = [int]($py[$i] + $pdy[$i])
            } else {
                $e = 1 - (1 - $p) * (1 - $p) * (1 - $p)
                $x = [int][Math]::Truncate($px[$i] + $pdx[$i] * $e + $pw[$i] * [Math]::Sin($p * 3.14159)); $y = [int][Math]::Truncate($py[$i] + $pdy[$i] * $e)
                if ($x -lt 0) { $x = 0 }
            }
            if ($y -lt 0) { continue }
            $k = ($y -shr 2) * $W + ($x -shr 1)
            $dots[$k] = [int]$dots[$k] -bor $bit[(($x -band 1) -shl 2) + ($y -band 3)]
            $dotColor[$k] = if ($p -lt 0.8) { 1 } else { $pg[$i] }
        }
        [void]$script:SwBuf.Append("$esc[?2026h")
        for ($row = $rmin; $row -le $rmax; $row++) {
            $line = [System.Text.StringBuilder]::new(); $cur = ''
            for ($c = $cmin; $c -le $cmax; $c++) {
                $k = $row * $W + $c
                $m = [int]$dots[$k]
                if ($m) {
                    $sgr = switch ($dotColor[$k]) { 1 { $ycol } 2 { if ($hg.ContainsKey($c)) { $hg[$c] } else { $pink } } default { $gcol } }
                    if ($sgr -cne $cur) { [void]$line.Append("$esc[0;$($sgr)m"); $cur = $sgr }
                    [void]$line.Append([char](0x2800 + $m))
                } else { [void]$line.Append(' ') }
            }
            SwPut ($row + 1) ($cmin + 1) "$($line.ToString())$r0"
        }
        if (-not $hint -and $t -gt $tset) { $hint = $true; SwPut $tr ([Math]::Truncate(($W - $tip.Length) / 2) + 1) "$dim$tip$r0" }
        [void]$script:SwBuf.Append("$esc[?2026l")
        SwFlush
        if ($t -gt $tend) { break }
        if ((Read-LotusKeyX 0.03) -ne 'timeout') { return }
    }
}

# The pages, one after the other → $true = Finish, $false = left (or Ctrl-C: $script:SwInt)
function script:Invoke-LotusWizardPages {
    $p = 1
    $petsHere = Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/pets.ps1')
    while ($true) {
        # the pages after "features" depend on what is turned on
        $pages = [System.Collections.Generic.List[string]]::new()
        foreach ($x in 'Lang', 'Name', 'Theme', 'Start', 'Features') { $pages.Add($x) }
        if (Test-LotusFeature 'weather') { $pages.Add('Weather') }
        if (Test-LotusFeature 'ai') { $pages.Add('Ai') }
        if ($petsHere -and (Test-LotusFeature 'pets') -and -not $script:PetNamesAdopted) { $pages.Add('Pet'); $pages.Add('PetName') }
        $pages.Add('Review')
        if ($p -gt $pages.Count) { return $true }
        if ($p -lt 1) {
            if (Show-LotusWizardQuit) { return $false }
            if ($script:SwInt) { return $false }
            $p = 1; continue
        }
        if (& "Show-LotusWizard$($pages[$p - 1])") { $p++ } else { $p-- }
        if ($script:SwInt) { return $false }
    }
}

function script:Invoke-LotusSetupWizard {
    if (-not (Test-LotusTty)) { return (St 1) }
    Import-LotusLangGroup setup
    $petsHere = Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/pets.ps1')
    $script:PetNamesAdopted = $false
    if ($petsHere) {
        Import-LotusCommand pets
        Import-LotusLangGroup pets
        Import-LotusPetKinds
        $script:PetNamesAdopted = @(Get-LotusPets).Count -gt 0
    }
    Write-LotusLog INFO setup 'Setup wizard started'
    $script:SwClaude = $false; $script:SwPetKind = ''; $script:SwPetName = ''; $script:SwPetSeen = $false; $script:SwInt = $false
    $saved = @{}; foreach ($k in $script:S.Keys) { $saved[$k] = $script:S[$k] }
    Initialize-LotusWizard
    Enter-LotusKeys
    Write-LotusRaw "$([char]27)[?1049h$([char]27)[?7l$([char]27)[?25l"
    $ok = $false
    try {
        $ok = Invoke-LotusWizardPages
        if ($ok) { Show-LotusWizardFinale }
    } finally {
        Write-LotusRaw "$([char]27)[0m$([char]27)[?7h$([char]27)[?25h$([char]27)[?1049l"
        Exit-LotusKeys
    }
    if (-not $ok) {
        # nothing is saved before Finish
        foreach ($k in $saved.Keys) { $script:S[$k] = $saved[$k] }
        Import-LotusLang
        if ($script:SwInt) { Write-LotusLog INFO setup 'Setup wizard interrupted'; return (St 130) }
        Write-LotusLog INFO setup 'Setup wizard cancelled'
        return (St 1)
    }
    $script:S['LOTUS_CONFIGURED'] = '1'; $script:S['LOTUS_CONFIG_VERSION'] = '3'
    Initialize-LotusColors
    Save-LotusSettings
    Update-LotusFastfetchConfig -Force
    Write-LotusLog INFO setup "Setup finished (features off: $(if ($script:S['LOTUS_FEATURES_OFF']) { $script:S['LOTUS_FEATURES_OFF'] } else { 'none' }))"
    $msg = T sw_done
    if ($script:S['LOTUS_NAME']) { $msg = $msg.Replace('%s', $script:S['LOTUS_NAME']) } else { $msg = $msg.Replace(', %s', '').Replace('%s', '') }
    Write-LotusBlank
    Write-LotusSuccess $msg
    Write-LotusDim "  $(T sw_done_hint)"
    Write-LotusBlank
    if ($script:SwPetKind -and $script:SwPetName -and (Test-LotusFeature 'pets') -and $petsHere) {
        if (Add-LotusPet $script:SwPetKind $script:SwPetName -Quiet) { Show-LotusPetIntro $script:SwPetName }
    }
    if ($script:SwClaude -and (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/ai.ps1'))) {
        Import-LotusCommand ai
        Invoke-LotusAiLogin | Out-Null
    }
    St 0
}

# lotus features: the checklist · lotus features <id> on|off: one feature (for scripts)
function script:Invoke-LotusFeaturesPage {
    param([string[]]$Rest)
    Import-LotusLangGroup setup
    if ($Rest.Count -ge 1) {
        $id = $Rest[0]
        if (-not $script:FeatureRow.ContainsKey($id) -or $id -ceq 'core') {
            Write-LotusError (T sw_feat_unknown 'There is no such feature') $id @((@($script:FeatureIds | Where-Object { $_ -cne 'core' })) -join ', ')
            return (St 1)
        }
        $state = if ($Rest.Count -gt 1) { $Rest[1] } else { '' }
        switch -Regex ($state) {
            '^(on|1|yes)$' { Set-LotusFeature $id $true }
            '^(off|0|no)$' { Set-LotusFeature $id $false }
            default { Write-LotusError (T sw_feat_onoff 'On or off?') $state @("lotus features $id on   ·   lotus features $id off"); return (St 1) }
        }
        Save-LotusSettings
        $label = Get-LotusFeatureLabel $id
        if (Test-LotusFeature $id) { Write-LotusSuccess ((T feat_now_on '%s is on.').Replace('%s', $label)) } else { Write-LotusInfo ((T feat_is_off '%s is turned off.').Replace('%s', $label)) }
        return (St 0)
    }
    if (-not ((Test-LotusOutTty) -and (Test-LotusTty))) {
        foreach ($id in $script:FeatureIds) {
            "$(PadR $id 12) $(PadR (Get-LotusFeatureLabel $id) 22) $(if (Test-LotusFeature $id) { 'on' } else { 'off' })"
        }
        return (St 0)
    }
    $before = [string]$script:S['LOTUS_FEATURES_OFF']
    Write-LotusHero (T sw_feat_title 'Features') (T sw_feat_sub '')
    $opts = foreach ($id in $script:FeatureIds) { "$(Get-LotusFeatureLabel $id)|$(Get-LotusFeatureAbout $id)|$(if ($id -ceq 'core') { 'locked' })" }
    $script:Toggles = [System.Collections.Generic.List[int]]::new()
    foreach ($id in $script:FeatureIds) { $script:Toggles.Add([int](Test-LotusFeature $id)) }
    if (-not (Read-LotusToggles @($opts))) { Write-LotusInfo (T cancelled 'Cancelled.'); return (St 0) }
    for ($i = 0; $i -lt $script:FeatureIds.Count; $i++) {
        $id = $script:FeatureIds[$i]
        if ($id -ceq 'core') { continue }
        $on = Test-LotusFeature $id
        if ($on -and -not $script:Toggles[$i]) { Set-LotusFeature $id $false }
        if (-not $on -and $script:Toggles[$i]) { Set-LotusFeature $id $true }
    }
    if ([string]$script:S['LOTUS_FEATURES_OFF'] -ceq $before) { Write-LotusInfo (T sw_feat_same 'Nothing changed.'); return (St 0) }
    Save-LotusSettings
    Write-LotusSuccess (T sw_feat_saved 'Saved.')
    Write-LotusBlank
    St 0
}
