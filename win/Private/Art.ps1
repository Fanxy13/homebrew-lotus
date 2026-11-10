# The art left of the start screen – a port of lib/art.zsh. logos/*.txt hold shapes only; Lotus paints them into the
# cache: in the theme's colors (a gradient from its second key color over the logo color to its key color, mixed in
# OKLab, or the logo color alone) or in their own colors. The painted file is byte for byte the one the zsh engine
# makes (the contract tests compare them), and both engines share the cache.

# Own colors of the built-in logos:  fade <colors…> · stripes <first row> <colors…> · box <front> <back>
$script:LogoOwn = @{
    lotus    = 'fade 255;222;234 247;150;188 226;96;150'
    minimal  = 'fade 255;222;234 247;150;188 226;96;150'
    large    = 'fade 255;222;234 247;150;188 226;96;150'
    terminal = 'fade 255;222;234 247;150;188 226;96;150'
    apple    = 'stripes 6 97;187;70 253;184;39 245;130;31 224;58;62 150;61;151 0;157;220'
    earth    = 'box 255;255;255 1;58;167'
}
# Block characters by their lit quarters: top left 1, top right 2, bottom left 4, bottom right 8
$script:Quads = @(' ', '▘', '▝', '▀', '▖', '▌', '▞', '▛', '▗', '▚', '▐', '▜', '▄', '▙', '▟', '█')
$script:QuadIndex = @{}
for ($qi = 0; $qi -lt 16; $qi++) { $script:QuadIndex[$script:Quads[$qi]] = $qi }

$script:LogoNames = @('lotus', 'minimal', 'large', 'terminal', 'apple', 'earth', 'custom', 'none')
$script:LogoLabels = @{ lotus = 'Lotus Classic'; minimal = 'Lotus Minimal'; large = 'Lotus Large'; terminal = 'Lotus Terminal'
    apple = 'Apple'; earth = 'Flag of Earth'; custom = 'Custom'; none = 'None' }

# The file of a logo ("" for none or missing)
function Get-LotusLogoFile {
    param([string]$Name)
    $f = switch ($Name) { 'none' { '' } 'custom' { Join-Path $script:Paths.Conf 'logo.txt' } default { Join-Path (Get-LotusRoot) "logos/$Name.txt" } }
    if ($f -and -not (Test-Path -LiteralPath $f -PathType Leaf)) { $f = '' }
    $f
}

# A number as zsh writes a float variable in ${x} (typeset -F: 10 places) and reads it back
function Get-LotusF10 { param([double]$x) [double]::Parse($x.ToString('F10', [cultureinfo]::InvariantCulture), [cultureinfo]::InvariantCulture) }

# OKLab (Björn Ottosson), a color space where mixing two colors looks even to the eye
function ConvertTo-LotusOklab {
    param([string]$Rgb)
    $v = foreach ($c in ($Rgb -split ';')) {
        $x = [double][int]$c / 255.0
        $x = if ($x -le 0.04045) { $x / 12.92 } else { [Math]::Pow(($x + 0.055) / 1.055, 2.4) }
        Get-LotusF10 $x
    }
    $l = [Math]::Pow(0.4122214708 * $v[0] + 0.5363325363 * $v[1] + 0.0514459929 * $v[2], 1.0 / 3)
    $m = [Math]::Pow(0.2119034982 * $v[0] + 0.6806995451 * $v[1] + 0.1073969566 * $v[2], 1.0 / 3)
    $s = [Math]::Pow(0.0883024619 * $v[0] + 0.2817188376 * $v[1] + 0.6299787005 * $v[2], 1.0 / 3)
    @(
        (0.2104542553 * $l + 0.7936177850 * $m - 0.0040720468 * $s),
        (1.9779984951 * $l - 2.4285922050 * $m + 0.4505937099 * $s),
        (0.0259040371 * $l + 0.7827717662 * $m - 0.8086757660 * $s)
    )
}
function ConvertFrom-LotusOklab {
    # (PowerShell names are not case-sensitive: the lightness is $Lk, not $L, which would be the same variable as $l)
    param([double]$Lk, [double]$Ak, [double]$Bk)
    $l = [Math]::Pow($Lk + 0.3963377774 * $Ak + 0.2158037573 * $Bk, 3)
    $m = [Math]::Pow($Lk - 0.1055613458 * $Ak - 0.0638541728 * $Bk, 3)
    $s = [Math]::Pow($Lk - 0.0894841775 * $Ak - 1.2914855480 * $Bk, 3)
    $out = foreach ($x in @((4.0767416621 * $l - 3.3077115913 * $m + 0.2309699292 * $s), (-1.2684380046 * $l + 2.6097574011 * $m - 0.3413193965 * $s), (-0.0041960863 * $l - 0.7034186147 * $m + 1.7076147010 * $s))) {
        $y = if ($x -le 0.0031308) { 12.92 * $x } else { 1.055 * [Math]::Pow($x, 1 / 2.4) - 0.055 }
        $i = [long][Math]::Truncate($y * 255 + 0.5)
        if ($i -lt 0) { $i = 0 } elseif ($i -gt 255) { $i = 255 }
        $i
    }
    $out -join ';'
}

# lotus_logo_paint <name> → @{ File; Width; Height }, or $null when there is no logo
function Get-LotusLogoPainted {
    param([string]$Name)
    $src = Get-LotusLogoFile $Name
    if (-not $src) { return $null }
    $mtime = Get-LotusMtime $src
    if ($null -eq $mtime) { return $null }
    $th = $script:Themes[[string]$script:S['LOTUS_THEME']]
    if (-not $th) { $th = $script:Themes['matcha'] }
    $rule = 'theme'
    if (Test-LotusOn $script:S['LOTUS_LOGO_FADE']) { $rule = "fade $($th[3]) $($th[0]) $($th[1])" }
    if (-not (Test-LotusOn $script:S['LOTUS_LOGO_THEME']) -and $script:LogoOwn.ContainsKey($Name)) { $rule = $script:LogoOwn[$Name] }
    $dir = Join-Path $script:Paths.Cache 'art'
    $out = Join-Path $dir "$Name.txt"
    $key = "$(Get-LotusVersion) $src $mtime $($script:Mode) $rule $($script:C['logo'])"
    if ((Test-Path -LiteralPath $out) -and (Test-Path -LiteralPath "$out.key")) {
        $k = ([string](Read-LotusFile "$out.key")) -split "`n"
        if ($k[0] -ceq $key -and $k.Count -ge 2) {
            $wh = $k[1] -split ' '
            return [pscustomobject]@{ File = $out; Width = [int]$wh[0]; Height = [int]$wh[1] }
        }
    }
    $painted = ConvertTo-LotusLogoArt -Text ([string](Read-LotusFile $src)) -Rule $rule
    if (-not $painted) { return $null }
    New-LotusDir $dir | Out-Null
    Write-LotusFile $out $painted.Text
    Write-LotusFile "$out.key" "$key`n$($painted.Width) $($painted.Height)`n"
    [pscustomobject]@{ File = $out; Width = $painted.Width; Height = $painted.Height }
}

# The painting itself: the shape and the rule → @{ Text; Width; Height }
function ConvertTo-LotusLogoArt {
    param([AllowEmptyString()][string]$Text, [string]$Rule)
    $esc = [char]27
    # $(<file) drops the new lines at the end; "$$" in a logo is a literal "$" (fastfetch's own escaping)
    $lines = @($Text.TrimEnd("`n") -split "`n" | ForEach-Object { $_.Replace('$$', '$') })
    if ($Text.TrimEnd("`n").Length -eq 0) { return $null }
    $w = 0
    foreach ($line in $lines) { if ($line.Length -gt $w) { $w = $line.Length } }
    $h = $lines.Count
    $r = $Rule -split ' '
    $codes = [System.Collections.Generic.List[string]]::new()
    $back = ''
    switch ($r[0]) {
        'fade' {
            $ok = @(foreach ($stop in $r[1..($r.Count - 1)]) { , (ConvertTo-LotusOklab $stop) })
            $n = $ok.Count - 1
            for ($k = 1; $k -le 2 * $h; $k++) {
                if ($n -lt 1) { $codes.Add((ConvertTo-LotusSgr $r[1])); continue }
                $t = ($k - 1.0) / (2 * $h - 1) * $n
                $s = [long][Math]::Truncate($t)
                $u = $t - $s
                if ($s -ge $n) { $s = $n - 1; $u = 1 }
                $a = $ok[$s]; $b = $ok[$s + 1]
                $codes.Add((ConvertTo-LotusSgr (ConvertFrom-LotusOklab ($a[0] + ($b[0] - $a[0]) * $u) ($a[1] + ($b[1] - $a[1]) * $u) ($a[2] + ($b[2] - $a[2]) * $u))))
            }
        }
        'stripes' {
            $first = [int]$r[1]
            $c = @($r[2..($r.Count - 1)])
            for ($i = 1; $i -le $h; $i++) {
                $k = if ($i -lt $first) { 1 } else { [Math]::Truncate(($i - $first) * $c.Count / ($h - $first + 1)) + 1 }
                $sgr = ConvertTo-LotusSgr $c[$k - 1]
                $codes.Add($sgr); $codes.Add($sgr)
            }
        }
        'box' {
            $back = ConvertTo-LotusSgr $r[2]
            $front = ConvertTo-LotusSgr $r[1]
            for ($i = 1; $i -le $h; $i++) { $codes.Add($front); $codes.Add($front) }
        }
        default {
            for ($i = 1; $i -le $h; $i++) { $codes.Add($script:C['logo']); $codes.Add($script:C['logo']) }
        }
    }
    # Every line as wide as the logo: fastfetch puts the info right after it. Block characters whose top half is lit
    # are drawn the other way round – the color as the background, the dark part as the character – so terminals that
    # leave a gap above each character do not cut the picture into stripes. A full block is ▄ in the bottom color on
    # the top color.
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 1; $i -le $h; $i++) {
        $line = $lines[$i - 1]
        $top = $codes[2 * $i - 2]; $bot = $codes[2 * $i - 1]
        if ($back) {
            $line = $line.PadRight($w)
            $norm = "1;$top;48$($back.Substring(2))"; $inv = "1;$back;48$($top.Substring(2))"; $full = $inv
        } else {
            $norm = "1;$bot"; $inv = "1;7;$top"; $full = "1;$bot;48$($top.Substring(2))"
        }
        $state = ''
        foreach ($chr in $line.ToCharArray()) {
            $ch = [string]$chr
            $want = $norm
            $q = if ($script:QuadIndex.ContainsKey($ch)) { $script:QuadIndex[$ch] } else { -1 }
            if ($q -eq 15 -and -not $back) { $want = $full; $ch = '▄' }
            elseif ($q -gt 0 -and ($q -band 3)) { $want = $inv; $ch = $script:Quads[15 - $q] }
            if ($want -cne $state) { [void]$sb.Append("$esc[0;$($want)m"); $state = $want }
            [void]$sb.Append($ch)
        }
        [void]$sb.Append("$esc[0m").Append([string]::new(' ', $w - $line.Length)).Append("`n")
    }
    [pscustomobject]@{ Text = $sb.ToString(); Width = $w; Height = $h }
}

# One color of a theme's flower (_bgu_ramp: dark below 0.6, light above; the setup's lotus and /bg's bloom) → "r;g;b"
function Get-LotusRamp {
    param([string]$Rgb, [double]$K)
    $c = @($Rgb -split ';' | ForEach-Object { [double]$_ })
    $m = ($c[0] + $c[1] + $c[2]) / 3.0
    $deep = foreach ($x in $c) { $v = $x * 0.58 - ($m - $x) * 0.7; Get-LotusF10 ([Math]::Max(0, [Math]::Min(255, $v))) }
    $tip = foreach ($x in $c) { $x + (255 - $x) * 0.62 }
    if ($K -lt 0.6) { $a = $deep; $b = $c; $f = $K / 0.6 } else { $a = $c; $b = $tip; $f = ($K - 0.6) / 0.4 }
    (0..2 | ForEach-Object { [long][Math]::Truncate($a[$_] + ($b[$_] - $a[$_]) * $f) }) -join ';'
}
