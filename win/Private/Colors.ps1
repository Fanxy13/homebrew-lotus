# Colors: 24-bit when the terminal has it, else the nearest of the 256 – the same numbers as lotus_sgr in lib/core.zsh.
# $script:C[role] = the SGR code of a theme color (logo key accent key2 salute border dim music), $script:Mode = tc | 256

$script:C = @{}
$script:TC = $true
$script:Mode = 'tc'
$script:ESC = [string][char]27

# lotus_detect_tc. Windows: Windows Terminal, and the console of Windows 10 1703 (build 15063) and newer, draw 24-bit color.
function Test-LotusTrueColor {
    switch ($script:S['LOTUS_COLORS']) { 'truecolor' { return $true } '256' { return $false } }
    if ($env:COLORTERM -in 'truecolor', '24bit') { return $true }
    if ($env:TERM_PROGRAM -in 'iTerm.app', 'WezTerm', 'ghostty', 'vscode', 'WarpTerminal', 'Hyper', 'Tabby', 'kitty', 'zed') { return $true }
    if ($env:WT_SESSION -or $env:KONSOLE_VERSION -or $env:KITTY_WINDOW_ID -or $env:ALACRITTY_LOG) { return $true }
    if ($env:TERM -like '*-direct' -or $env:TERM -in 'xterm-kitty', 'alacritty', 'foot', 'foot-extra') { return $true }
    $vte = 0
    if ([int]::TryParse([string]$env:VTE_VERSION, [ref]$vte) -and $vte -ge 3600) { return $true }
    if ($IsWindows) { return [Environment]::OSVersion.Version.Build -ge 15063 }
    $false
}

# "r;g;b" → the SGR code (lotus_sgr): truecolor, or the nearest of the 256 colors
function ConvertTo-LotusSgr {
    param([Parameter(Mandatory)][string]$Rgb, [Nullable[bool]]$TrueColor)
    $tc = if ($null -ne $TrueColor) { $TrueColor } else { $script:TC }
    if ($tc) { return "38;2;$Rgb" }
    $c = $Rgb -split ';'
    $r = [int]$c[0]; $g = [int]$c[1]; $b = [int]$c[2]
    $hi = [Math]::Max($r, [Math]::Max($g, $b))
    $lo = [Math]::Min($r, [Math]::Min($g, $b))
    if ($hi - $lo -lt 12) {
        $n = if ($r -lt 8) { 16 } elseif ($r -gt 238) { 231 } else { 232 + [Math]::Truncate(($r - 8) / 10) }
        return "38;5;$n"
    }
    $q = { param($v) [Math]::Truncate(($v * 5 + 127) / 255) }
    "38;5;$(16 + 36 * (& $q $r) + 6 * (& $q $g) + (& $q $b))"
}

# The SGR code as a background color (38;… → 48;…)
function ConvertTo-LotusBackground { param([string]$Sgr) '48' + $Sgr.Substring(2) }

function Import-LotusThemes {
    # $script:Themes[name] = 8 colors "r;g;b", $script:ThemeNames in order, $script:ThemeLabels[name]
    $script:Themes = @{}
    $script:ThemeLabels = @{}
    $script:ThemeNames = [System.Collections.Generic.List[string]]::new()
    foreach ($t in Get-LotusThemes) {
        $script:Themes[$t.Name] = $t.Rgb
        $script:ThemeLabels[$t.Name] = $t.Label
        $script:ThemeNames.Add($t.Name)
    }
}

# lotus_colors
function Initialize-LotusColors {
    $script:TC = Test-LotusTrueColor
    $script:Mode = if ($script:TC) { 'tc' } else { '256' }
    Import-LotusThemes
    $rgb = $script:Themes[[string]$script:S['LOTUS_THEME']]
    if (-not $rgb) { $rgb = $script:Themes['matcha'] }
    $roles = 'logo', 'key', 'accent', 'key2', 'salute', 'border', 'dim', 'music'
    $script:C = @{}
    for ($i = 0; $i -lt 8; $i++) { $script:C[$roles[$i]] = ConvertTo-LotusSgr $rgb[$i] }
}

# An escape sequence for a theme role, or for a code:  E key → ESC[38;2;…m   E 1 → ESC[1m
function E {
    param([Parameter(Mandatory)][string]$Code)
    $v = $script:C[$Code]
    if ($null -eq $v) { $v = $Code }
    "$([char]27)[$($v)m"
}
