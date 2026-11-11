# The terminal UI: the same screens as lib/ui.zsh (themed, no emoji). Every command builds its screens from these.
# Keys come from the console – or from $script:KeyQueue, which the tests fill (a keyboard that runs dry counts as esc).

$script:R = "$([char]27)[0m"
$script:B = "$([char]27)[1m"
$script:KeyQueue = [System.Collections.Generic.Queue[string]]::new()
$script:KeyQueueActive = $false
$script:Toggles = [System.Collections.Generic.List[int]]::new()

function Write-LotusLine { param([AllowEmptyString()][AllowNull()][string]$Text = '') Write-Host $Text }
function Write-LotusRaw { param([AllowEmptyString()][AllowNull()][string]$Text = '') if ($Text) { Write-Host $Text -NoNewline } }

# zsh's ${(r:n:)s} and ${(l:n:)s}: padded with spaces to n characters – and cut when longer
function PadR { param([AllowEmptyString()][AllowNull()][string]$s, [int]$n) if ($n -le 0) { return '' }; $s = [string]$s; if ($s.Length -ge $n) { $s.Substring(0, $n) } else { $s + [string]::new(' ', $n - $s.Length) } }
function PadL { param([AllowEmptyString()][AllowNull()][string]$s, [int]$n) if ($n -le 0) { return '' }; $s = [string]$s; if ($s.Length -ge $n) { $s.Substring($s.Length - $n) } else { [string]::new(' ', $n - $s.Length) + $s } }
function Cut { param([AllowEmptyString()][AllowNull()][string]$s, [int]$n) $s = [string]$s; if ($n -le 0) { '' } elseif ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }
# n times ─ (lotus_line)
function Get-LotusLine { param([int]$n) if ($n -le 0) { '' } else { [string]::new([char]0x2500, $n) } }

# The window size → @(columns, rows); without a console 80 × 24 (or COLUMNS and LINES)
function Get-LotusSize {
    $w = 0; $h = 0
    try { $w = [Console]::WindowWidth; $h = [Console]::WindowHeight } catch { }
    if ($w -le 0) { $w = Get-LotusInt $env:COLUMNS 80 }
    if ($h -le 0) { $h = Get-LotusInt $env:LINES 24 }
    @([int]$w, [int]$h)
}
function Get-LotusColumns { (Get-LotusSize)[0] }

# Is there a keyboard to ask? (not in scripts, pipes, CI and non-interactive sessions)
function Test-LotusTty {
    if ($script:KeyQueueActive) { return $true }
    if ($env:LOTUS_NO_TTY -eq '1') { return $false }
    try { -not [Console]::IsInputRedirected -and [Environment]::UserInteractive } catch { $false }
}
function Test-LotusOutTty {
    if ($script:KeyQueueActive) { return $true }
    try { -not [Console]::IsOutputRedirected } catch { $false }
}

# One key, by name (ui_keyx): up down left right home end pgup pgdn enter space tab back esc, else the character.
# With a timeout in seconds also "timeout"; Ctrl-C (while it counts as a key) is "interrupt".
function Read-LotusKeyX {
    param([double]$Timeout = -1)
    if ($script:KeyQueueActive) {
        if ($script:KeyQueue.Count) { return $script:KeyQueue.Dequeue() }
        return 'esc'
    }
    try {
        if ($Timeout -ge 0) {
            $deadline = [datetime]::UtcNow.AddSeconds($Timeout)
            while (-not [Console]::KeyAvailable) {
                if ([datetime]::UtcNow -ge $deadline) { return 'timeout' }
                Start-Sleep -Milliseconds 15
            }
        }
        $k = [Console]::ReadKey($true)
    } catch { return 'esc' }
    if (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C -or $k.KeyChar -eq [char]3)) { return 'interrupt' }
    switch ($k.Key) {
        'UpArrow' { return 'up' } 'DownArrow' { return 'down' } 'LeftArrow' { return 'left' } 'RightArrow' { return 'right' }
        'Home' { return 'home' } 'End' { return 'end' } 'PageUp' { return 'pgup' } 'PageDown' { return 'pgdn' }
        'Enter' { return 'enter' } 'Spacebar' { return 'space' } 'Backspace' { return 'back' } 'Escape' { return 'esc' }
        'Tab' { if ($k.Modifiers -band [ConsoleModifiers]::Shift) { return 'backtab' } return 'tab' }
    }
    if ($k.KeyChar -eq "`r" -or $k.KeyChar -eq "`n") { return 'enter' }
    if ($k.KeyChar -eq [char]0) { return 'ignore' }
    [string]$k.KeyChar
}

# One key with the short names of ui_key: up down left right (also k j l h), enter (also space), quit (esc, q)
function Read-LotusKey {
    $k = Read-LotusKeyX
    switch -CaseSensitive ($k) {
        'k' { return 'up' } 'j' { return 'down' } 'l' { return 'right' } 'h' { return 'left' }
        'space' { return 'enter' } 'esc' { return 'quit' } 'interrupt' { return 'quit' } 'q' { return 'quit' } 'Q' { return 'quit' }
    }
    $k
}

# Ctrl-C as a key while a screen is open (so the screen can clean up), restored afterwards
function Enter-LotusKeys { try { $script:CtrlCWas = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true } catch { } }
function Exit-LotusKeys { try { if ($null -ne $script:CtrlCWas) { [Console]::TreatControlCAsInput = $script:CtrlCWas } } catch { } }

# ── Lines ─────────────────────────────────────────────────────

# Header:  lotus / Weather   (optional dim subtitle on the right)
function Write-LotusHeader {
    param([string]$Title, [string]$Sub)
    Write-LotusLine ''
    Write-LotusLine "  $(E '1')$(E accent)lotus$($script:R)$(E dim) / $($script:R)$($script:B)$Title$($script:R)$(if ($Sub) { "$(E dim)  $Sub$($script:R)" })"
    Write-LotusLine ''
}
function Write-LotusText { param([string]$Text) Write-LotusLine "  $(Convert-LotusHere $Text)" }
function Write-LotusDim { param([string]$Text) Write-LotusLine "  $(E dim)$(Convert-LotusHere $Text)$($script:R)" }
function Write-LotusBlank { Write-LotusLine '' }
function Write-LotusSuccess { param([string]$Text) Write-LotusLine "  $(E '1')$(E key)✓$($script:R) $(Convert-LotusHere $Text)" }
function Write-LotusInfo { param([string]$Text) Write-LotusLine "  $(E accent)›$($script:R) $(Convert-LotusHere $Text)" }
function Write-LotusStep { param([string]$Text) Write-LotusLine "  $(E dim)…$($script:R) $(Convert-LotusHere $Text)" }
function Write-LotusWarn {
    param([string]$Text)
    $t = Convert-LotusHere $Text
    Write-LotusLine "  $(E '1')$(E key2)!$($script:R) $t"
    Write-LotusLog WARN $(if ($script:LogComp) { $script:LogComp } else { 'ui' }) $t
}

# Error screen: title, message, then optional hint lines (also written to the log)
function Write-LotusError {
    param([string]$Title, [string]$Message, [string[]]$Hints)
    $t = Convert-LotusHere $Title
    $m = Convert-LotusHere $Message
    Write-LotusLog ERROR $(if ($script:LogComp) { $script:LogComp } else { 'ui' }) "$t$(if ($m) { " – $m" })"
    Write-LotusLine ''
    Write-LotusLine "  $(E '1;38;5;203')✗ $t$($script:R)"
    if ($m) { Write-LotusLine "    $m" }
    foreach ($h in $Hints) { if ($null -ne $h) { Write-LotusLine "    $(E dim)$(Convert-LotusHere $h)$($script:R)" } }
    Write-LotusLine ''
}

# Border pieces left and right of a centered title (lotus_box_parts) → @(left, right)
function Get-LotusBoxParts {
    param([string]$Title)
    $t = " $Title "
    $nl = [Math]::Truncate((42 - $t.Length) / 2)
    @("┌$(Get-LotusLine $nl)", "$(Get-LotusLine (42 - $t.Length - $nl))┐")
}

# Box in the start screen style:  Write-LotusCard "Title" "KEY|value" …
function Write-LotusCard {
    param([string]$Title, [string[]]$Rows)
    $b = E border; $key = "$(E '1')$(E key)"
    $p = Get-LotusBoxParts $Title
    Write-LotusLine "  $b$($p[0])$(E accent) $Title $b$($p[1])$($script:R)"
    foreach ($row in $Rows) {
        if (-not $row -or $row -eq '|') { Write-LotusLine "  $b│$($script:R)"; continue }
        $i = $row.IndexOf('|')
        $k = if ($i -ge 0) { $row.Substring(0, $i) } else { $row }
        $v = if ($i -ge 0) { $row.Substring($i + 1) } else { $row }
        Write-LotusLine "  $b├─$($script:R) $key$(PadR $k 10)$($script:R) $v"
    }
    Write-LotusLine "  $b└$(Get-LotusLine 42)┘$($script:R)"
}

# Category line:  Write-LotusCategory "Browsers" 9
function Write-LotusCategory {
    param([string]$Name, [string]$Count)
    Write-LotusLine "  $(E '1')$(E accent)$($Name.ToUpper())$($script:R)$(E dim)  $Count$($script:R)"
}

# Search result row:  <index> <name> <meta> <description> [installed]
function Write-LotusResult {
    param([int]$Index, [string]$Name, [string]$Meta, [string]$Description, [string]$Installed)
    $d = E dim; $k = E key
    $mark = if ($Installed) { "$k●$($script:R)" } else { ' ' }
    Write-LotusLine "  $d$(PadL ([string]$Index) 2)$($script:R) $mark $($script:B)$(PadR (Cut $Name 24) 24)$($script:R) $d$(PadR $Meta 12)$($script:R) $(Cut $Description ((Get-LotusColumns) - 46))"
}

# Progress bar that redraws its line:  Write-LotusProgress <label> <percent>
function Write-LotusProgress {
    param([string]$Label, [int]$Percent)
    $pct = [Math]::Max(0, [Math]::Min(100, $Percent))
    $n = [Math]::Truncate($pct * 24 / 100)
    Write-LotusRaw "`r$([char]27)[K  $Label [$([string]::new([char]0x25A0, $n))$([string]::new([char]0x00B7, 24 - $n))] $pct%"
    if ($pct -eq 100) { Write-LotusLine '' }
}

# Yes/no question, one key (ui_confirm) → $true / $false
function Read-LotusConfirm {
    param([string]$Question, [string]$Default = 'n')
    $hint = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    Write-LotusRaw "  $(Convert-LotusHere $Question) $(E dim)$hint$($script:R) "
    if (-not (Test-LotusTty)) { Write-LotusLine "(no keyboard: $Default)"; return $Default -eq 'y' }
    $k = Read-LotusKeyX
    if ($k -eq 'enter') { $k = $Default }
    if ($k -cmatch '^[yYjJ]$') { Write-LotusLine 'yes'; return $true }
    Write-LotusLine 'no'
    $false
}

# Free text with an optional default (ui_input) → the text; $null without a keyboard
function Read-LotusInput {
    param([string]$Label, [string]$Default)
    $hint = if ($Default) { " $(E dim)($Default)$($script:R)" } else { '' }
    Write-LotusRaw "  $Label${hint}: "
    if (-not (Test-LotusTty)) { Write-LotusLine ''; return $null }
    if ($script:KeyQueueActive) {
        $text = ''
        while ($true) { $k = Read-LotusKeyX; if ($k -eq 'enter' -or $k -eq 'esc') { break }; if ($k -eq 'space') { $k = ' ' }; if ($k.Length -eq 1) { $text += $k } }
        Write-LotusLine $text
    } else {
        $text = [Console]::ReadLine()
        if ($null -eq $text) { return $null }
    }
    if ($text) { $text } else { [string]$Default }
}

# Pick one entry with arrows, Enter or its number; q/Esc cancels; long lists scroll (ui_choose) → index from 1, or $null
function Read-LotusChoice {
    param([string]$Title, [string[]]$Options)
    $n = $Options.Count
    if (-not $n) { return $null }
    $h = [Math]::Max(5, (Get-LotusSize)[1] - 7); if ($h -gt $n) { $h = $n }
    $a = E accent; $d = E dim; $r = $script:R; $esc = [char]27
    if ($Title) { Write-LotusLine "  $($script:B)$Title$r" }
    if (-not (Test-LotusTty)) { Write-LotusDim '(no keyboard – cancelled)'; return $null }
    $sel = 1; $top = 1
    Write-LotusRaw "$esc[?25l"
    try {
        while ($true) {
            if ($sel -lt $top) { $top = $sel }
            if ($sel -gt $top + $h - 1) { $top = $sel - $h + 1 }
            $buf = [System.Text.StringBuilder]::new()
            for ($i = $top; $i -lt $top + $h; $i++) {
                if ($i -eq $sel) { [void]$buf.Append("$esc[K  $a›$r $d$(PadL ([string]$i) 2)$r  $($script:B)$($Options[$i - 1])$r`n") }
                else { [void]$buf.Append("$esc[K    $d$(PadL ([string]$i) 2)$r  $($Options[$i - 1])`n") }
            }
            [void]$buf.Append("$esc[K  $d↑↓ select   ⏎ choose   q cancel$(if ($n -gt $h) { "   $sel/$n" })$r")
            Write-LotusRaw $buf.ToString()
            $k = Read-LotusKey
            switch -Regex ($k) {
                '^up$' { $sel = if ($sel -gt 1) { $sel - 1 } else { $n }; break }
                '^down$' { $sel = if ($sel -lt $n) { $sel + 1 } else { 1 }; break }
                '^enter$' { Write-LotusRaw "`r$esc[K$esc[?25h`n"; return $sel }
                '^quit$' { Write-LotusRaw "`r$esc[K$esc[?25h`n"; return $null }
                '^[1-9]$' { if ([int]$k -le $n) { Write-LotusRaw "`r$esc[K$esc[?25h`n"; return [int]$k }; break }
            }
            Write-LotusRaw "`r$esc[$($h)A"
        }
    } finally { Write-LotusRaw "$esc[?25h" }
}

# ── Larger screens: setup, features, the log ──────────────────

# A page title:   ◇ lotus / Remove BG     (optional dim line below)
function Write-LotusHero {
    param([string]$Title, [string]$Sub)
    Write-LotusLine ((Get-LotusHeroLines $Title $Sub) -join "`n")
}
# The lines of that page title (a screen that draws itself again and again, like the math game, keeps them)
function Get-LotusHeroLines {
    param([string]$Title, [string]$Sub)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('')
    $lines.Add("    $(E accent)◇$($script:R) $($script:B)lotus$($script:R)$(E dim) / $($script:R)$($script:B)$(Convert-LotusHere $Title)$($script:R)")
    if ($Sub) { $lines.Add(''); $lines.Add("    $(E dim)$(Convert-LotusHere $Sub)$($script:R)") }
    $lines.Add('')
    , $lines.ToArray()
}
function Write-LotusSection { param([string]$Text) Write-LotusLine "    $(E dim)$($Text.ToUpper())$($script:R)" }
function Write-LotusKv {
    param([string]$Key, [string]$Value)
    $w = if ($Key.Length -ge 12) { $Key.Length + 2 } else { 12 }
    Write-LotusLine "    $(E dim)$(PadR $Key $w)$($script:R)$Value"
}

# A path for display: ~ for the home folder, shortened in the middle when too long (ui_path)
function Format-LotusPath {
    param([string]$Path, [int]$Max = 0)
    $p = Format-LotusHomePath $Path
    if ($Max -le 0) { $Max = (Get-LotusColumns) - 18 }
    if ($Max -lt 20) { $Max = 20 }
    if ($p.Length -gt $Max) {
        $keep = [Math]::Truncate(($Max - 1) / 2)
        $p = $p.Substring(0, $keep) + '…' + $p.Substring($p.Length - ($Max - $keep - 1))
    }
    $p
}

# Radio list with a short description per entry (ui_select): Enter picks, Esc goes back → index, or $null
function Read-LotusSelect {
    param([int]$Default = 1, [string[]]$Options)
    if ($script:SelectHook) { return & $script:SelectHook $Default $Options }
    $n = $Options.Count
    $sel = if ($Default -lt 1 -or $Default -gt $n) { 1 } else { $Default }
    if (-not (Test-LotusTty)) { return $sel }
    $k = "$(E '1')$(E key)"; $d = E dim; $r = $script:R; $esc = [char]27
    $W = Get-LotusColumns
    $rows = 0
    Write-LotusRaw "$esc[?25l"
    try {
        while ($true) {
            $buf = [System.Text.StringBuilder]::new()
            if ($rows) { [void]$buf.Append("$esc[$($rows)A") }
            $rows = 0
            for ($i = 1; $i -le $n; $i++) {
                $o = $Options[$i - 1]; $j = $o.IndexOf('|')
                $lbl = if ($j -ge 0) { $o.Substring(0, $j) } else { $o }
                $desc = if ($j -ge 0) { $o.Substring($j + 1) } else { '' }
                $dt = if ($desc) { "$d  $(Cut $desc ($W - $lbl.Length - 12))$r" } else { '' }
                if ($i -eq $sel) { [void]$buf.Append("`r$esc[K    $k●$r $($script:B)$lbl$r$dt`n") }
                else { [void]$buf.Append("`r$esc[K    $d○$r $lbl$dt`n") }
                $rows++
            }
            [void]$buf.Append("`r$esc[K`n`r$esc[K    $d$(T ui_select_hint '↑↓ choose   ⏎ continue   esc back')$r")
            $rows++
            Write-LotusRaw $buf.ToString()
            $key = Read-LotusKeyX
            switch -Regex ($key) {
                '^up$' { $sel = if ($sel -gt 1) { $sel - 1 } else { $n }; break }
                '^(down|tab)$' { $sel = if ($sel -lt $n) { $sel + 1 } else { 1 }; break }
                '^(enter|space|right)$' { Write-LotusRaw "`r$esc[K$esc[?25h`n"; return $sel }
                '^(esc|left|q|interrupt)$' { Write-LotusRaw "`r$esc[K$esc[?25h`n"; return $null }
                '^[1-9]$' { if ([int]$key -le $n) { $sel = [int]$key }; break }
            }
            Write-LotusRaw "`r"
        }
    } finally { Write-LotusRaw "$esc[?25h" }
}

# A path typed or dropped in → absolute: file:// links, ~ and quotes from a drag and drop work (ui_clean_path)
function ConvertTo-LotusCleanPath {
    param([string]$Text)
    $p = $Text.Trim()
    if ($p.Length -ge 2 -and (($p[0] -eq '"' -and $p[-1] -eq '"') -or ($p[0] -eq "'" -and $p[-1] -eq "'"))) { $p = $p.Substring(1, $p.Length - 2) }
    if ($p -like 'file://*') {
        $p = $p.Substring(7); if ($p.StartsWith('localhost')) { $p = $p.Substring(9) }
        $p = [Uri]::UnescapeDataString($p)
        if ($IsWindows -and $p -match '^/[A-Za-z]:') { $p = $p.Substring(1) }
    }
    if ($p -eq '~' -or $p.StartsWith('~/') -or $p.StartsWith('~\')) { $p = (Get-LotusHome) + $p.Substring(1) }
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path (Get-Location).ProviderPath $p }
    [IO.Path]::GetFullPath($p)
}

# A dashed frame with a plus to drop files on (ui_drop_zone <width> <title> <types>)
function Write-LotusDropZone {
    param([int]$Width, [string]$Title, [string]$Types)
    $inner = $Width - 2
    $b = E border; $k = "$(E '1')$(E key)"; $d = E dim; $r = $script:R
    $dash = [string]::new([char]0x254C, $inner)
    if ($Title.Length -gt $inner - 2) { $Title = $Title.Substring(0, $inner - 3) + '…' }
    if ($Types.Length -gt $inner - 2) { $Types = $Types.Substring(0, $inner - 3) + '…' }
    $row = {
        param($plain, $shown)
        if (-not $shown) { $shown = $plain }
        $left = [Math]::Truncate(($inner - $plain.Length) / 2)
        Write-LotusLine "    $b┆$r$([string]::new(' ', [Math]::Max(0, $left)))$shown$([string]::new(' ', [Math]::Max(0, $inner - $left - $plain.Length)))$b┆$r"
    }
    Write-LotusLine "    $b╭$dash╮$r"
    & $row ''
    & $row '  ┃  ' "  $k┃$r  "
    & $row '━━╋━━' "$k━━╋━━$r"
    & $row '  ┃  ' "  $k┃$r  "
    & $row ''
    & $row $Title "$($script:B)$Title$r"
    & $row $Types "$d$Types$r"
    & $row ''
    Write-LotusLine "    $b╰$dash╯$r"
}

# Checklist (ui_toggles): Space turns entries on and off, Enter continues, Esc goes back.
#   options "Label|Description|locked", the states in $script:Toggles (1/0, changed in place) → $true, or $false for back
function Read-LotusToggles {
    param([string[]]$Options)
    $n = $Options.Count
    if (-not (Test-LotusTty)) { return $true }
    $size = Get-LotusSize
    $W = $size[0]
    $h = [Math]::Max(4, $size[1] - 12); if ($h -gt $n) { $h = $n }
    $k = "$(E '1')$(E key)"; $a = E accent; $d = E dim; $r = $script:R; $esc = [char]27
    $sel = 1; $top = 1; $rows = 0
    Write-LotusRaw "$esc[?25l"
    try {
        while ($true) {
            if ($sel -lt $top) { $top = $sel }
            if ($sel -gt $top + $h - 1) { $top = $sel - $h + 1 }
            $buf = [System.Text.StringBuilder]::new()
            if ($rows) { [void]$buf.Append("$esc[$($rows)A") }
            $rows = 0
            for ($i = $top; $i -lt $top + $h; $i++) {
                $f = $Options[$i - 1] -split '\|'
                $lbl = $f[0]; $desc = if ($f.Count -gt 1) { $f[1] } else { '' }; $lock = $f.Count -gt 2 -and $f[2]
                $mark = if ($lock) { "$d◉$r" } elseif ($script:Toggles[$i - 1]) { "$k◉$r" } else { "$d○$r" }
                if ($i -eq $sel) { [void]$buf.Append("`r$esc[K  $a›$r $mark $($script:B)$(PadR $lbl 20)$r $d$(Cut $desc ($W - 30))$r`n") }
                else { [void]$buf.Append("`r$esc[K    $mark $(PadR $lbl 20) $d$(Cut $desc ($W - 30))$r`n") }
                $rows++
            }
            [void]$buf.Append("`r$esc[K`n`r$esc[K    $d$(T ui_toggle_hint '↑↓ move   space on/off   ⏎ continue   esc back')$(if ($n -gt $h) { "   $sel/$n" })$r")
            $rows++
            Write-LotusRaw $buf.ToString()
            $key = Read-LotusKeyX
            switch -Regex ($key) {
                '^up$' { $sel = if ($sel -gt 1) { $sel - 1 } else { $n }; break }
                '^(down|tab)$' { $sel = if ($sel -lt $n) { $sel + 1 } else { 1 }; break }
                '^(space|right|left|x)$' {
                    $f = $Options[$sel - 1] -split '\|'
                    if (-not ($f.Count -gt 2 -and $f[2])) { $script:Toggles[$sel - 1] = [int](-not $script:Toggles[$sel - 1]) }
                    break
                }
                '^a$' { for ($i = 0; $i -lt $n; $i++) { $script:Toggles[$i] = 1 }; break }
                '^enter$' { Write-LotusRaw "`r$esc[K$esc[?25h`n"; return $true }
                '^(esc|q|interrupt)$' { Write-LotusRaw "`r$esc[K$esc[?25h`n"; return $false }
            }
            Write-LotusRaw "`r"
        }
    } finally { Write-LotusRaw "$esc[?25h" }
}

# Shown when a command belongs to a feature that is turned off → $true when it was turned on just now
function Show-LotusFeatureOff {
    param([string]$Id)
    $name = Get-LotusFeatureLabel $Id
    Write-LotusHero $name
    Write-LotusText ((T feat_is_off '%s is turned off.').Replace('%s', $name))
    Write-LotusBlank
    Write-LotusDim (T feat_turn_on 'Turn it on in /settings → Features, or with: lotus features')
    Write-LotusBlank
    if (-not ((Test-LotusOutTty) -and (Test-LotusTty))) { return $false }
    if (-not (Read-LotusConfirm (T feat_on_now 'Turn it on now?') 'n')) { Write-LotusBlank; return $false }
    Set-LotusFeature $Id $true
    Save-LotusSettings
    Write-LotusSuccess ((T feat_now_on '%s is on.').Replace('%s', $name))
    Write-LotusBlank
    $true
}

# One line of text with a default (ui_line): Enter accepts, Esc goes back → the text, or $null
function Read-LotusLine {
    param([string]$Label, [string]$Text = '')
    if ($script:LineHook) { return & $script:LineHook $Label $Text }
    if (-not (Test-LotusTty)) { return $Text }
    $d = E dim; $a = E accent; $esc = [char]27
    Write-LotusRaw "$esc[?25h"
    $shown = $null
    while ($true) {
        if ($shown -cne $Text) { Write-LotusRaw "`r$esc[K    $d$Label$($script:R)  $a›$($script:R) $Text"; $shown = $Text }
        $k = Read-LotusKeyX 0.3
        switch -Regex ($k) {
            '^timeout$' { continue }
            '^enter$' { Write-LotusLine ''; return $Text }
            '^(esc|interrupt)$' { Write-LotusLine ''; return $null }
            '^back$' { if ($Text.Length) { $Text = $Text.Substring(0, $Text.Length - 1) }; continue }
            '^space$' { $Text += ' '; continue }
            '^(up|down|left|right|home|end|pgup|pgdn|tab|backtab|ignore)$' { continue }
            default { if ($k.Length -eq 1 -and -not [char]::IsControl($k[0]) -and $Text.Length -lt 200) { $Text += $k } }
        }
    }
}
