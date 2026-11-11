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

# ── Album cover ───────────────────────────────────────────────
# The cover of the song that plays, in the logo's place (lotus_cover in lib/art.zsh, lib/cover.pl). Windows' media
# controls hand the picture over (Get-LotusMediaCover); the art is two pixels per character (▄) in the cover's own
# colors – never the theme's – 24-bit or the nearest of the 256. It is cached per song and size in the cache's covers
# folder: a song that was shown before needs neither the media controls nor the picture's decoder again.

# What kind of picture the first bytes of a file are: jpeg, png, gif, webp or bmp; '' for anything else. Nothing else is
# opened: a cover can come from a web page (browsers hand a page's artwork to the media controls).
function Get-LotusPictureKind {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -lt 12) { return '' }
    if ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return 'jpeg' }
    if ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47 -and $Bytes[4] -eq 0x0D -and $Bytes[5] -eq 0x0A -and $Bytes[6] -eq 0x1A -and $Bytes[7] -eq 0x0A) { return 'png' }
    if ($Bytes[0] -eq 0x47 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46 -and $Bytes[3] -eq 0x38) { return 'gif' }
    if ($Bytes[0] -eq 0x52 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46 -and $Bytes[3] -eq 0x46 -and $Bytes[8] -eq 0x57 -and $Bytes[9] -eq 0x45 -and $Bytes[10] -eq 0x42 -and $Bytes[11] -eq 0x50) { return 'webp' }
    if ($Bytes[0] -eq 0x42 -and $Bytes[1] -eq 0x4D) { return 'bmp' }
    ''
}

# The header of a 24 or 32 bit BMP → @{ Width; Height; Bits; TopDown; Offset; Stride }, or $null for anything else
function Get-LotusBmpInfo {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -lt 54 -or $Bytes[0] -ne 0x42 -or $Bytes[1] -ne 0x4D) { return $null }
    $bits = [int][BitConverter]::ToUInt16($Bytes, 28)
    if ($bits -ne 24 -and $bits -ne 32) { return $null }
    $w = [long][BitConverter]::ToInt32($Bytes, 18)
    $h = [long][BitConverter]::ToInt32($Bytes, 22)
    $top = $h -lt 0
    if ($top) { $h = -$h }
    $stride = [long][Math]::Truncate(($w * ($bits / 8) + 3) / 4) * 4
    $offset = [long][BitConverter]::ToUInt32($Bytes, 10)
    if ($w -lt 1 -or $h -lt 1 -or $Bytes.Length -lt $offset + $stride * $h) { return $null }
    [pscustomobject]@{ Width = [int]$w; Height = [int]$h; Bits = $bits; TopDown = $top; Offset = $offset; Stride = $stride }
}

# lib/cover.pl: a BMP → the art as big as fits into <Cols> × <Rows> and keeps the picture's shape (a cell is one pixel wide
# and two tall: the top pixel is the background, the bottom one the character ▄ – terminals that draw ▄ with the font leave
# a thin gap above it, and that gap then has the top pixel's color). The BMP is a few times bigger than the art: every
# pixel of the art is the average of a block of the picture's pixels, in linear light, so fine details blend instead of
# flickering. → @{ Text; Width; Height }, or $null when the BMP cannot be read
function ConvertTo-LotusCoverArt {
    param([byte[]]$Bmp, [int]$Cols, [int]$Rows, [Nullable[bool]]$TrueColor)
    $info = Get-LotusBmpInfo $Bmp
    if (-not $info -or $Cols -lt 1 -or $Rows -lt 1) { return $null }
    $tc = if ($null -ne $TrueColor) { [bool]$TrueColor } else { $script:TC }
    $w = $info.Width; $h = $info.Height
    $bytesPer = $info.Bits / 8
    $stride = $info.Stride; $offset = $info.Offset; $top = $info.TopDown
    $scale = [Math]::Min($Cols / [double]$w, 2.0 * $Rows / $h)
    $Cols = [int][Math]::Truncate($w * $scale + 0.5); if ($Cols -lt 1) { $Cols = 1 }
    $Rows = [int][Math]::Truncate($h * $scale / 2 + 0.5); if ($Rows -lt 1) { $Rows = 1 }
    $ph = $Rows * 2
    if (-not $script:CoverLin) {
        $t = [double[]]::new(256)
        for ($i = 0; $i -lt 256; $i++) { $c = $i / 255.0; $t[$i] = if ($c -le 0.04045) { $c / 12.92 } else { [Math]::Pow(($c + 0.055) / 1.055, 2.4) } }
        $script:CoverLin = $t
    }
    $lin = $script:CoverLin
    # the block of the picture each pixel of the art averages: [x0, x1) across, [y0, y1) down
    $xa = [int[]]::new($Cols); $xb = [int[]]::new($Cols)
    for ($i = 0; $i -lt $Cols; $i++) {
        $a = [int][Math]::Truncate([double]($i * $w) / $Cols); $b = [int][Math]::Truncate([double](($i + 1) * $w) / $Cols)
        if ($b -le $a) { $b = $a + 1 }
        $xa[$i] = $a; $xb[$i] = $b
    }
    $ya = [int[]]::new($ph); $yb = [int[]]::new($ph)
    for ($i = 0; $i -lt $ph; $i++) {
        $a = [int][Math]::Truncate([double]($i * $h) / $ph); $b = [int][Math]::Truncate([double](($i + 1) * $h) / $ph)
        if ($b -le $a) { $b = $a + 1 }
        $ya[$i] = $a; $yb[$i] = $b
    }
    $esc = [char]27
    $text = [System.Text.StringBuilder]::new()
    $seen = @{}
    for ($row = 0; $row -lt $Rows; $row++) {
        $fg = ''; $bg = ''
        $line = [System.Text.StringBuilder]::new()
        for ($col = 0; $col -lt $Cols; $col++) {
            $pair = @('', '')
            for ($half = 0; $half -lt 2; $half++) {
                $y = 2 * $row + $half
                $sr = 0.0; $sg = 0.0; $sb = 0.0; $n = 0
                for ($yy = $ya[$y]; $yy -lt $yb[$y]; $yy++) {
                    $p = $offset + $stride * $(if ($top) { $yy } else { $h - 1 - $yy }) + $xa[$col] * $bytesPer
                    for ($xx = $xa[$col]; $xx -lt $xb[$col]; $xx++) {
                        $sb += $lin[$Bmp[$p]]; $sg += $lin[$Bmp[$p + 1]]; $sr += $lin[$Bmp[$p + 2]]
                        $n++; $p += $bytesPer
                    }
                }
                # linear light → sRGB
                $rgb = [int[]]::new(3)
                $k = 0
                foreach ($v in @(($sr / $n), ($sg / $n), ($sb / $n))) {
                    $e = if ($v -le 0.0031308) { $v * 12.92 } else { 1.055 * [Math]::Pow($v, 1 / 2.4) - 0.055 }
                    $q = [int][Math]::Truncate($e * 255 + 0.5)
                    if ($q -lt 0) { $q = 0 } elseif ($q -gt 255) { $q = 255 }
                    $rgb[$k++] = $q
                }
                $layer = if ($half -eq 0) { 48 } else { 38 }
                $memo = ($rgb[0] -shl 16) -bor ($rgb[1] -shl 8) -bor $rgb[2] -bor ($layer -shl 24)
                $code = $seen[$memo]
                if ($null -eq $code) {
                    if ($tc) { $code = "$layer;2;$($rgb[0]);$($rgb[1]);$($rgb[2])" }
                    else {
                        $hi = [Math]::Max($rgb[0], [Math]::Max($rgb[1], $rgb[2])); $lo = [Math]::Min($rgb[0], [Math]::Min($rgb[1], $rgb[2]))
                        $idx = if ($hi - $lo -lt 12) { if ($rgb[0] -lt 8) { 16 } elseif ($rgb[0] -gt 238) { 231 } else { 232 + [int][Math]::Truncate(($rgb[0] - 8) / 10) } }
                        else { 16 + 36 * [int][Math]::Truncate(($rgb[0] * 5 + 127) / 255) + 6 * [int][Math]::Truncate(($rgb[1] * 5 + 127) / 255) + [int][Math]::Truncate(($rgb[2] * 5 + 127) / 255) }
                        $code = "$layer;5;$idx"
                    }
                    $seen[$memo] = $code
                }
                $pair[$half] = $code
            }
            $set = [System.Collections.Generic.List[string]]::new()
            if ($pair[1] -cne $fg) { $set.Add($pair[1]) }
            if ($pair[0] -cne $bg) { $set.Add($pair[0]) }
            if ($set.Count) { [void]$line.Append("$esc[").Append(($set -join ';')).Append('m') }
            $fg = $pair[1]; $bg = $pair[0]
            [void]$line.Append('▄')
        }
        [void]$text.Append($line.ToString()).Append("$esc[0m`n")
    }
    [pscustomobject]@{ Text = $text.ToString(); Width = $Cols; Height = $Rows }
}

# A picture as a 24 bit BMP no bigger than <Px> × <Px> (lotus_os_image_bmp; lib/cover.pl and ConvertTo-LotusCoverArt turn it
# into terminal art). Windows' own image component (GDI+) reads jpeg, png, gif and bmp. $null for anything else, and for a
# picture that cannot be read.
function ConvertTo-LotusCoverBmp {
    param([byte[]]$Bytes, [int]$Px)
    $kind = Get-LotusPictureKind $Bytes
    if ($kind -eq 'bmp') {
        $info = Get-LotusBmpInfo $Bytes
        if ($info -and $info.Width -le $Px -and $info.Height -le $Px) { return , $Bytes }
    }
    if (-not $IsWindows -or $kind -notin 'jpeg', 'png', 'gif', 'bmp' -or $Bytes.Length -gt 16MB) { return $null }
    $stream = $null; $image = $null; $canvas = $null; $gfx = $null; $out = $null
    try {
        Add-Type -AssemblyName System.Drawing
        $stream = [System.IO.MemoryStream]::new($Bytes)
        $image = [System.Drawing.Image]::FromStream($stream, $false, $true)
        $w = $image.Width; $h = $image.Height
        if ($w -lt 1 -or $h -lt 1 -or [long]$w * $h -gt 100000000) { return $null }
        $k = [Math]::Min(1.0, $Px / [double][Math]::Max($w, $h))
        $nw = [Math]::Max(1, [int][Math]::Round($w * $k)); $nh = [Math]::Max(1, [int][Math]::Round($h * $k))
        $canvas = [System.Drawing.Bitmap]::new($nw, $nh, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $gfx = [System.Drawing.Graphics]::FromImage($canvas)
        $gfx.Clear([System.Drawing.Color]::Black)    # what is see-through shows black
        $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gfx.DrawImage($image, 0, 0, $nw, $nh)
        $out = [System.IO.MemoryStream]::new()
        $canvas.Save($out, [System.Drawing.Imaging.ImageFormat]::Bmp)
        return , $out.ToArray()
    } catch {
        return $null
    } finally {
        foreach ($d in @($out, $gfx, $canvas, $image, $stream)) { if ($d) { $d.Dispose() } }
    }
}

# lotus_cover: the art of the cover of the song that plays, as big as fits into <Columns> × <Rows>. <Song> is the first line
# of now playing, which names the song: the same song at the same size is drawn once and kept (covers\), and the picture
# is kept too, so a window of another size does not ask Windows again. → @{ File; Width; Height }, or $null when nothing
# plays or the song has no cover that can be read
function Get-LotusCover {
    param([int]$Columns, [int]$Rows, [string]$Song)
    $plain = ([string]$Song -replace "$([char]27)\[[0-9;]*m", '').Trim()
    if (-not $plain) { return $null }
    $dir = Join-Path $script:Paths.Cache 'covers'
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($plain)) } finally { $sha.Dispose() }
    $key = -join ($hash[0..7] | ForEach-Object { $_.ToString('x2') })
    $art = Join-Path $dir "$key-$($Columns)x$($Rows)-$($script:Mode).txt"
    $img = Join-Path $dir "$key.img"
    $none = Join-Path $dir "$key.none"
    $drawn = (Test-Path -LiteralPath $art -PathType Leaf) -and (Get-Item -LiteralPath $art).Length -gt 0
    if (-not $drawn) {
        if (-not (Test-Path -LiteralPath $img -PathType Leaf)) {
            # a song without a cover is asked again after three minutes, not at every start
            $asked = if (Test-Path -LiteralPath $none) { Get-LotusMtime $none } else { $null }
            if ($null -ne $asked -and (Get-LotusEpoch) - $asked -lt 180) { return $null }
            New-LotusDir $dir | Out-Null
            $tmp = Join-Path $dir "$PID.tmp"
            try {
                $m = Get-LotusMediaCover $tmp
                # only the song now playing, and only if it is the one the start screen names
                $mine = $m -and $m.Status -eq 'Playing' -and $m.Title -and $plain.IndexOf([string]$m.Title, [StringComparison]::OrdinalIgnoreCase) -ge 0
                if (-not $mine) { return $null }
                if ($m.HasCover -and (Test-Path -LiteralPath $tmp -PathType Leaf) -and (Get-Item -LiteralPath $tmp -Force).Length -gt 0) {
                    Move-Item -LiteralPath $tmp -Destination $img -Force
                } else {
                    Write-LotusFile $none "$plain`n"
                    return $null
                }
            } finally {
                if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            }
        }
        $px = 4 * [Math]::Max($Columns, 2 * $Rows)
        $bmp = $null
        try { $bmp = ConvertTo-LotusCoverBmp ([System.IO.File]::ReadAllBytes($img)) $px } catch { }
        $cover = if ($bmp) { ConvertTo-LotusCoverArt -Bmp $bmp -Cols $Columns -Rows $Rows } else { $null }
        if (-not $cover) {
            Write-LotusLog DEBUG cover "Cover of ""$plain"" could not be read"
            Write-LotusFile $none "$plain`n"
            Remove-Item -LiteralPath $img -Force -ErrorAction SilentlyContinue
            return $null
        }
        Write-LotusFile $art $cover.Text
        Write-LotusLog DEBUG cover "Cover of ""$plain"" drawn ($($cover.Width)×$($cover.Height))"
        # keep the newest 80 of each
        foreach ($pattern in '*.txt', '*.img', '*.none') {
            try { Get-ChildItem -LiteralPath $dir -Filter $pattern -File -ErrorAction Stop | Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 80 | Remove-Item -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
    $lines = ([string](Read-LotusFile $art)).TrimEnd("`n") -split "`n"
    $first = $lines[0] -replace "$([char]27)\[[0-9;]*m", ''
    [pscustomobject]@{ File = $art; Width = $first.Length; Height = $lines.Count }
}
