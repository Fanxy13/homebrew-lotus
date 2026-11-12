# /img on Windows – a picture cropped, turned, straightened and converted in the browser like the iPhone's Photos
# (lib/edit – the same program as on the Mac and on Linux; this file is only its glue), and images and whole folders into
# PNG, JPEG, HEIC, AVIF, WebP, TIFF, GIF, BMP, PDF or ICO: a port of lib/cmd/img.zsh with ImageMagick (magick.exe – its
# winget package is ImageMagick.ImageMagick), the way Lotus converts off the Mac. Photos come out the right way up,
# smaller but never larger; transparency becomes white in JPEG and BMP. The originals are never changed: an image gets a
# new file next to it, a folder gets a folder for the new format inside, nothing is written over ("name (2).jpg").
# Nothing is uploaded.
#   /img   ·   /img edit <image>
#   /img convert [<image|folder>…] [--to <format>] [--quality <1–100>] [--max <pixels>]   ·   /img formats

$script:ImgExt = @('png', 'jpg', 'jpeg', 'jpe', 'heic', 'heif', 'avif', 'webp', 'gif', 'tif', 'tiff', 'bmp', 'psd', 'jp2', 'jxl', 'svg', 'tga', 'ico',
    'dng', 'cr2', 'cr3', 'nef', 'arw', 'raf', 'orf', 'rw2')
# key | label | file extension | ImageMagick's name | lossy | what it is good for
$script:ImgFormats = @(
    'jpeg|JPEG|jpg|JPEG|1|small, for photos and everywhere – no transparency'
    'png|PNG|png|PNG|0|lossless, keeps transparency – screenshots, graphics'
    'heic|HEIC|heic|HEIC|1|about half the size of JPEG – iPhone, Mac'
    'avif|AVIF|avif|AVIF|1|the smallest – modern browsers and apps'
    'webp|WebP|webp|WEBP|1|small, for websites – keeps transparency'
    'tiff|TIFF|tiff|TIFF|0|lossless and large – for print and editing'
    'gif|GIF|gif|GIF|0|256 colors – simple graphics'
    'bmp|BMP|bmp|BMP|0|uncompressed – old programs'
    'pdf|PDF|pdf|PDF|0|a page for each image – to send or print'
    'ico|ICO|ico|ICO|0|an icon for websites (favicon) – square, at most 256 px'
)

function script:Invoke-Lotusimg {
    param([string]$Cmd, [string[]]$Rest)
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    $more = [string[]]@($Rest | Select-Object -Skip 1)
    if ($sub -cin 'edit', 'crop', 'e') { return Invoke-LotusImgEdit $more }
    if ($sub -cin 'convert', 'conv', 'c') { return Invoke-LotusImgConvert $more }
    if ($sub -ceq 'formats') { return Show-LotusImgFormats }
    if ($sub -ceq '') { if ((Test-LotusTty) -and (Test-LotusOutTty)) { return Invoke-LotusImgEdit @() } else { return Show-LotusImgHelp } }
    if ($sub -cin 'help', '-h', '--help') { return Show-LotusImgHelp }
    if (Test-Path -LiteralPath (ConvertTo-LotusCleanPath $sub)) { return Invoke-LotusImgConvert $Rest }
    Write-LotusError "Unknown: /img $sub" '' @('/img edit <image>   ·   /img convert <image|folder>   ·   /img help')
    St 1
}

# ImageMagick → @{ Convert = <program and the words before the image>; Identify = …; List = … }, or $null. On Windows
# magick.exe only – its convert.exe would be Windows' own tool for disks; elsewhere also ImageMagick 6 (convert and
# identify). The first one that can write a PNG: other programs bring a magick.exe without the parts that read and
# write images, and it may come first in the PATH. When none can, the first one found – /img then says what it lacks.
function script:Find-LotusMagick {
    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($c in @(Get-Command magick -CommandType Application -All -ErrorAction SilentlyContinue)) { $found.Add([pscustomobject]@{ Convert = @($c.Source); Identify = @($c.Source, 'identify'); List = @($c.Source, '-list', 'format') }) }
    if ($IsWindows -and $env:ProgramFiles) {
        foreach ($f in @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'ImageMagick-*\magick.exe') -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)) {
            if (-not ($found | Where-Object { $_.Convert[0] -eq $f.FullName })) { $found.Add([pscustomobject]@{ Convert = @($f.FullName); Identify = @($f.FullName, 'identify'); List = @($f.FullName, '-list', 'format') }) }
        }
    }
    if (-not $IsWindows) {
        $c = Find-LotusProgram @('convert'); $i = Find-LotusProgram @('identify')
        if ($c -and $i) { $found.Add([pscustomobject]@{ Convert = @($c); Identify = @($i); List = @($c, '-list', 'format') }) }
    }
    foreach ($m in $found) { if (@(Get-LotusImgWritable $m) -ccontains 'png') { return $m } }
    if ($found.Count) { $found[0] } else { $null }
}

# A format by its key or extension → its row, or $null
function script:Get-LotusImgFormat {
    param([string]$Word)
    $k = ([string]$Word).ToLowerInvariant().TrimStart('.')
    if ($k -cin 'jpg', 'jpe') { $k = 'jpeg' }
    if ($k -ceq 'tif') { $k = 'tiff' }
    foreach ($f in $script:ImgFormats) { $p = $f -split '\|'; if ($p[0] -ceq $k) { return [pscustomobject]@{ Key = $p[0]; Label = $p[1]; Ext = $p[2]; Im = $p[3]; Lossy = $p[4] -eq '1'; About = $p[5] } } }
    $null
}

# What ImageMagick here can write → keys (its list says rw for each format it was built with)
function script:Get-LotusImgWritable {
    param($Magick)
    if (-not $Magick) { return @() }
    $list = Invoke-LotusNativeText $Magick.List[0] @($Magick.List | Select-Object -Skip 1)
    $can = @{}
    foreach ($line in $list -split "`n") { if ($line -match '^\s*([A-Z0-9-]+)\*?\s+\S+\s+([r-][w-][+-])') { if ($Matches[2][1] -eq 'w') { $can[$Matches[1]] = $true } } }
    @(foreach ($f in $script:ImgFormats) { $p = $f -split '\|'; if ($can[$p[3]]) { $p[0] } })
}

function script:Show-LotusImgHelp {
    Write-LotusHero 'Images' 'Crop, straighten and convert pictures – on this PC'
    $k = E key; $d = E dim; $r = $script:R
    foreach ($row in @('/img|the editor: drop a picture into the window – or ⏎ for the clipboard', '/img edit <image>|crop, turn, straighten, hide faces and convert this picture, in your browser',
            '/img convert|drop images or a folder into the window', '/img convert <image or folder>|one or more images, every image in a folder',
            '  --to <format>|jpeg png heic avif webp tiff gif bmp pdf ico – no questions', '  --quality <1–100>|for JPEG, HEIC, AVIF and WebP (85 when not given)',
            '  --max <pixels>|at most this wide and high – never larger', '/img formats|what this PC reads and writes')) {
        $p = $row -split '\|', 2
        Write-LotusLine "    $k$(PadR $p[0] 30)$r$($p[1])"
    }
    Write-LotusBlank
    Write-LotusSection 'Examples'; Write-LotusBlank
    Write-LotusLine "    $d/img edit ~\Desktop\IMG_2041.HEIC$r"
    Write-LotusLine "    $d/img convert ~\Desktop\IMG_2041.HEIC --to jpeg$r"
    Write-LotusLine "    $d/img convert ~\Desktop\shoot --to webp --max 1920$r"
    Write-LotusBlank
    Write-LotusDim '  The originals stay as they are. The editor saves a new picture next to it; a folder gets a folder for the new format inside it.'
    Write-LotusBlank
    St 0
}

function script:Show-LotusImgFormats {
    Write-LotusHero 'Image converter' 'What this PC reads and writes'
    $magick = Find-LotusMagick
    $can = @(Get-LotusImgWritable $magick)
    Write-LotusSection 'Writes'; Write-LotusBlank
    foreach ($f in $script:ImgFormats) {
        $p = $f -split '\|'
        if ($can -ccontains $p[0]) { Write-LotusLine "    $(E key)✓$($script:R) $(PadR $p[1] 6) $(E dim)$($p[5])$($script:R)" }
        elseif (-not $magick) { Write-LotusLine "    $(E dim)· $(PadR $p[1] 6) needs ImageMagick: winget install --id ImageMagick.ImageMagick -e$($script:R)" }
        else { Write-LotusLine "    $(E dim)· $(PadR $p[1] 6) not with the ImageMagick here$($script:R)" }
    }
    Write-LotusBlank
    Write-LotusSection 'Reads'; Write-LotusBlank
    Write-LotusDim '  What ImageMagick reads: JPEG, PNG, GIF, TIFF, BMP, ICO, WebP, HEIC, AVIF, SVG, PSD, TGA … and RAW photos'
    Write-LotusBlank
    St 0
}

# ImageMagick is missing: the winget command, then a question – nothing is installed without a yes
function script:Install-LotusMagick {
    Write-LotusError 'The image converter needs ImageMagick' 'ImageMagick is free and open source; Lotus uses it to read and write the images.' @(
        'winget install --id ImageMagick.ImageMagick -e')
    if (-not ($IsWindows -and (Test-LotusTty) -and (Get-Command winget -ErrorAction SilentlyContinue))) { return $null }
    if (-not (Read-LotusConfirm 'Install it with winget now?' 'y')) { return $null }
    $rc = Invoke-LotusInTheOpen 'winget' @('install', '--id', 'ImageMagick.ImageMagick', '-e', '--accept-source-agreements')
    if ($rc -ne 0) { Write-LotusError 'Installation failed' "winget's message is shown above (exit code $rc)."; return $null }
    Find-LotusMagick
}

# The paths given (a path with spaces that was not quoted is put together again) → @{ In; From; Missing }
function script:Get-LotusImgInputs {
    param([string[]]$Words)
    $found = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $p = ConvertTo-LotusCleanPath $Words[$i]
        if (Test-Path -LiteralPath $p) { $found.Add($p); continue }
        $ok = $false
        for ($j = $i + 1; $j -lt $Words.Count; $j++) {
            $q = ConvertTo-LotusCleanPath (($Words[$i..$j]) -join ' ')
            if (Test-Path -LiteralPath $q) { $found.Add($q); $i = $j; $ok = $true; break }
        }
        if (-not $ok) { $missing.Add($Words[$i]) }
    }
    $in = [System.Collections.Generic.List[string]]::new(); $from = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $found) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $p -File | Where-Object { $script:ImgExt -contains $_.Extension.TrimStart('.').ToLowerInvariant() } | Sort-Object Name)) { $in.Add($f.FullName); $from.Add($p) }
        } else { $in.Add($p); $from.Add('') }
    }
    [pscustomobject]@{ In = $in.ToArray(); From = $from.ToArray(); Missing = $missing.ToArray() }
}

# Next to an image on its own; a folder gets "<folder>\<Format>". Never over an original or another new file.
function script:Get-LotusImgPlan {
    param([string[]]$In, [string[]]$From, $Format)
    $taken = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt $In.Count; $i++) {
        $dir = if ($From[$i]) { Join-Path $From[$i] $Format.Label } else { Split-Path -Parent $In[$i] }
        $name = [IO.Path]::GetFileNameWithoutExtension($In[$i])
        $try = Join-Path $dir "$name.$($Format.Ext)"; $n = 2
        while ((Test-Path -LiteralPath $try) -or $taken.Contains($try)) { $try = Join-Path $dir "$name ($n).$($Format.Ext)"; $n++ }
        [void]$taken.Add($try)
        $try
    }
}

function script:Format-LotusMb { param([long]$Bytes) if ($Bytes -lt 1048576) { "$([Math]::Truncate(($Bytes + 512) / 1024)) KB" } else { '{0:0.0} MB' -f ($Bytes / 1048576.0) } }

# The width and height of an image ("4032x3024"), or ''
function script:Get-LotusImgSize {
    param($Magick, [string]$Path)
    $out = Invoke-LotusNativeText $Magick.Identify[0] (@($Magick.Identify | Select-Object -Skip 1) + @('-format', '%wx%h', "$Path[0]"))
    if ($out -match '^(\d+)x(\d+)') { $Matches[0] } else { '' }
}

# One image: upright, smaller but never larger, a JPEG without transparency → $true when it was written
function script:Convert-LotusImgOne {
    param($Magick, [string]$In, [string]$Out, $Format, [int]$Quality, [int]$Max)
    $dims = Get-LotusImgSize $Magick $In
    $side = 0
    if ($dims -match '^(\d+)x(\d+)$') { $side = [Math]::Max([int]$Matches[1], [int]$Matches[2]) }
    if ($Max -and ($Max -lt $side -or -not $side)) { $side = $Max }
    if ($Format.Key -ceq 'ico' -and ($side -gt 256 -or -not $side)) { $side = 256 }
    $argv = [System.Collections.Generic.List[string]]::new()
    foreach ($w in @($Magick.Convert | Select-Object -Skip 1)) { $argv.Add($w) }
    $argv.Add("$In[0]"); $argv.Add('-auto-orient')
    if ($side) { $argv.Add('-resize'); $argv.Add("$($side)x$($side)>") }
    if ($Quality) { $argv.Add('-quality'); $argv.Add([string]$Quality) }
    if ($Format.Key -cin 'jpeg', 'bmp') { foreach ($w in '-background', 'white', '-alpha', 'remove', '-alpha', 'off') { $argv.Add($w) } }
    if ($Format.Key -ceq 'ico' -and $side) { foreach ($w in '-background', 'none', '-gravity', 'center', '-extent', "$($side)x$($side)") { $argv.Add($w) } }
    $tmp = "$Out.lotus-tmp"
    $argv.Add("$($Format.Im):$tmp")
    & $Magick.Convert[0] @argv *> $null
    $ok = $LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmp) -and (Get-Item -LiteralPath $tmp).Length -gt 0
    if ($ok) { Move-Item -LiteralPath $tmp -Destination $Out -Force }
    else { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    $ok
}

function script:Invoke-LotusImgConvert {
    param([string[]]$Words)
    $to = ''; $quality = ''; $max = ''
    $paths = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $w = $Words[$i]
        if ($w -cin '--to', '-t' -and $i + 1 -lt $Words.Count) { $to = $Words[++$i] }
        elseif ($w -cin '--quality', '-q' -and $i + 1 -lt $Words.Count) { $quality = $Words[++$i] }
        elseif ($w -cin '--max', '-m' -and $i + 1 -lt $Words.Count) { $max = $Words[++$i] }
        elseif ($w.StartsWith('--to=')) { $to = $w.Substring(5) }
        elseif ($w.StartsWith('--quality=')) { $quality = $w.Substring(10) }
        elseif ($w.StartsWith('--max=')) { $max = $w.Substring(6) }
        else { $paths.Add($w) }
    }
    Write-LotusHero 'Image converter' 'PNG, JPEG, HEIC, AVIF, WebP, PDF and more – on this PC'
    $ask = (Test-LotusTty) -and (Test-LotusOutTty)
    if (-not $paths.Count) {
        if (-not $ask) { Write-LotusError 'Which images?' '' @('/img convert <image|folder> --to <format>'); return (St 1) }
        # Windows Terminal types the path of what is dropped into the window – Lotus reads it, nothing is run
        $width = [Math]::Min(60, (Get-LotusColumns) - 8)
        if ($width -ge 36) { Write-LotusDropZone $width 'Drop images or a folder here' 'HEIC · PNG · JPEG · WebP · RAW · folders' } else { Write-LotusText 'Drag images or a folder into this window' }
        Write-LotusDim '  Drop, then ⏎ · or type a path · esc goes back'
        Write-LotusBlank
        $line = Read-LotusLine 'Images' ''
        if (-not $line -or -not $line.Trim()) { return (St 0) }
        foreach ($w in (Split-LotusShellWords $line)) { $paths.Add($w) }
        Write-LotusBlank
    }
    $inputs = Get-LotusImgInputs $paths.ToArray()
    foreach ($m in $inputs.Missing) { Write-LotusWarn "Not found: $m" }
    if (-not $inputs.In.Count) { Write-LotusError 'No images to convert' '' @("Images: $((($script:ImgExt | Select-Object -First 12) | ForEach-Object { $_.ToUpper() }) -join ', ') … – or a folder with them"); return (St 1) }
    $magick = Find-LotusMagick
    if (-not $magick) { $magick = Install-LotusMagick; if (-not $magick) { return (St 1) } }

    # what came in
    $bytes = 0L
    $kinds = [ordered]@{}
    foreach ($f in $inputs.In) {
        $fmt0 = Get-LotusImgFormat ([IO.Path]::GetExtension($f))
        $label = if ($fmt0) { $fmt0.Label } else { [IO.Path]::GetExtension($f).TrimStart('.').ToUpper() }
        $kinds[$label] = 1 + [int]$kinds[$label]
        $bytes += (Get-Item -LiteralPath $f).Length
    }
    $folders = @($inputs.From | Where-Object { $_ } | Select-Object -Unique)
    $n = $inputs.In.Count
    Write-LotusLine "  $(E '1')$(E key)✓$($script:R) $n image$(if ($n -ne 1) { 's' })$(if ($folders.Count -eq 1) { " in $(Split-Path -Leaf $folders[0])" })  $(E dim)($(@($kinds.Keys | ForEach-Object { "$_ $($kinds[$_])" }) -join ' · ') · $(Format-LotusMb $bytes))$($script:R)"
    Write-LotusBlank

    # the format, the quality, the size – asked when not given, with the choice of last time first
    $can = @(Get-LotusImgWritable $magick)
    $lastFile = Join-Path $script:Paths.State 'img-last'
    $last = @(([string](Read-LotusFile $lastFile)).Trim() -split '\|')
    if ($to) {
        $format = Get-LotusImgFormat $to
        if (-not $format) { Write-LotusError "Unknown format: $to" '' @("Formats: $($can -join ' ')"); return (St 1) }
        if ($can -cnotcontains $format.Key) { Write-LotusError "The ImageMagick here cannot write $($format.Label)" '' @("Formats here: $($can -join ' ')"); return (St 1) }
    } else {
        if (-not $ask) { Write-LotusError 'Into which format?' '' @("--to $($can -join '|')"); return (St 1) }
        $keys = @($script:ImgFormats | ForEach-Object { ($_ -split '\|')[0] } | Where-Object { $can -ccontains $_ })
        $opts = @($keys | ForEach-Object { $f = Get-LotusImgFormat $_; "$($f.Label)|$($f.About)" })
        Write-LotusLine "  $($script:B)Into which format?$($script:R)"
        $sel = [Array]::IndexOf($keys, $(if ($last[0]) { $last[0] } else { 'jpeg' })) + 1
        $pick = Read-LotusSelect $(if ($sel -gt 0) { $sel } else { 1 }) $opts
        if ($null -eq $pick) { return (St 0) }
        $format = Get-LotusImgFormat $keys[$pick - 1]
    }
    if ($format.Lossy -and -not $quality) {
        if ($ask) {
            $qs = @(95, 85, 70, 50)
            Write-LotusLine "  $($script:B)Quality$($script:R)"
            $sel = [Array]::IndexOf($qs, [int](Get-LotusInt $(if ($last.Count -gt 1) { $last[1] } else { '' }) 85)) + 1
            $pick = Read-LotusSelect $(if ($sel -gt 0) { $sel } else { 2 }) @('Best – 95|almost no difference to the original, larger files', 'High – 85|the usual choice: looks the same, much smaller',
                'Medium – 70|for the web and messages', 'Small – 50|as small as possible – details get soft')
            if ($null -eq $pick) { return (St 0) }
            $quality = [string]$qs[$pick - 1]
        } else { $quality = '85' }
    }
    if ($quality -and ($quality -notmatch '^\d+$' -or [int]$quality -lt 1 -or [int]$quality -gt 100)) { Write-LotusError 'The quality is a number from 1 to 100' $quality; return (St 1) }
    $q = if ($format.Lossy) { [int]$quality } else { 0 }
    if ($format.Key -ceq 'ico') { $max = '256' }
    elseif (-not $max) {
        if ($ask) {
            $ms = @(0, 3840, 2560, 1920, 1280, 640)
            Write-LotusLine "  $($script:B)Size$($script:R)"
            $sel = [Array]::IndexOf($ms, [int](Get-LotusInt $(if ($last.Count -gt 2) { $last[2] } else { '' }) 0)) + 1
            $pick = Read-LotusSelect $(if ($sel -gt 0) { $sel } else { 1 }) @('Keep the size|as large as the original', '4K|at most 3840 px wide and high', '2560 px|for large screens',
                'Full HD|at most 1920 px – the web, presentations', '1280 px|for messages and mail', '640 px|thumbnails')
            if ($null -eq $pick) { return (St 0) }
            $max = [string]$ms[$pick - 1]
        } else { $max = '0' }
    }
    if ($max -notmatch '^\d+$') { Write-LotusError 'The size is a number of pixels' $max @('--max 1920'); return (St 1) }
    try { Write-LotusFile $lastFile "$($format.Key)|$(if ($quality) { $quality } else { 85 })|$max`n" } catch { }

    # the work – one image after the other; Esc stops after the one that is being written
    $out = @(Get-LotusImgPlan $inputs.In $inputs.From $format)
    foreach ($dir in @($out | ForEach-Object { Split-Path -Parent $_ } | Select-Object -Unique)) {
        try { New-LotusDir $dir | Out-Null } catch { Write-LotusError "Cannot write to $(Format-LotusHomePath $dir)"; return (St 1) }
    }
    Write-LotusLog INFO img "$n image(s) → $($format.Label) (quality $q, max $max)"
    $done = 0; $outBytes = 0L; $doneBytes = 0L; $stopped = $false
    $fail = [System.Collections.Generic.List[string]]::new()
    $listen = $ask
    if ($listen) { Enter-LotusKeys }
    try {
        for ($i = 0; $i -lt $n; $i++) {
            if ($listen -and -not $script:KeyQueueActive -and [Console]::KeyAvailable -and (Read-LotusKeyX 0) -cin 'esc', 'interrupt') { $stopped = $true; break }
            $name = Split-Path -Leaf $inputs.In[$i]
            if (Test-LotusOutTty) { Write-LotusProgress "$($i + 1)/$n $(Cut $name 24)" ([int]($doneBytes * 100 / [Math]::Max(1, $bytes))) }
            $size = (Get-Item -LiteralPath $inputs.In[$i]).Length
            if (Convert-LotusImgOne $magick $inputs.In[$i] $out[$i] $format $q ([int]$max)) {
                $done++; $outBytes += (Get-Item -LiteralPath $out[$i]).Length
            } else { $fail.Add("$name – not an image this PC can read") }
            $doneBytes += $size
        }
        if (Test-LotusOutTty) { Write-LotusRaw "`r$([char]27)[K" }
    } finally { if ($listen) { Exit-LotusKeys } }
    if ($stopped) { Write-LotusInfo "Stopped – $done of $n converted, the rest was left out." }

    # what came out, and where
    if ($done) {
        $change = if ($bytes -gt 0 -and $outBytes -gt 0) { $c = [Math]::Truncate(($outBytes - $bytes) * 100 / $bytes); " ($(if ($c -ge 0) { '+' })$c %)" } else { '' }
        Write-LotusLine "  $(E '1')$(E key)✓$($script:R) $done image$(if ($done -ne 1) { 's' }) → $($format.Label)   $(E dim)$(Format-LotusMb $bytes) → $(Format-LotusMb $outBytes)$change$($script:R)"
        $dirs = @($out | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Split-Path -Parent $_ } | Select-Object -Unique)
        if ($done -eq 1 -and $n -eq 1) { Write-LotusDim "  Saved: $(Format-LotusHomePath $out[0])" }
        elseif ($dirs.Count -eq 1) { Write-LotusDim "  Saved in $(Format-LotusHomePath $dirs[0])" }
        else { Write-LotusDim "  Saved in $($dirs.Count) places:"; foreach ($d in ($dirs | Select-Object -First 4)) { Write-LotusDim "    $(Format-LotusHomePath $d)" } }
    }
    if ($fail.Count) {
        Write-LotusWarn "$($fail.Count) could not be converted:"
        foreach ($f in ($fail | Select-Object -First 8)) { Write-LotusDim "    $f" }
        if ($fail.Count -gt 8) { Write-LotusDim "    … and $($fail.Count - 8) more" }
    }
    Write-LotusLog INFO img "Converted $done of $n to $($format.Label), $($fail.Count) failed"
    if (-not $done) { return (St 1) }
    Show-LotusPetReact done
    if ($ask) {
        Write-LotusBlank
        $first = @($out | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
        if ($first -and (Read-LotusConfirm "Show $(if ($done -eq 1) { 'it' } else { 'them' }) in File Explorer?" 'y')) { [void](Show-LotusInFolder $first[0]) }
    }
    St 0
}

# ── /img edit ─────────────────────────────────────────────────

# The drop zone of the editor: Windows Terminal types the path of what is dropped into the window, Lotus reads it without
# running anything. An empty ⏎ takes the clipboard – an image, or files copied in File Explorer. → the words (none:
# cancelled, or nothing in the clipboard)
function script:Read-LotusImgEditPaths {
    $width = [Math]::Min(60, (Get-LotusColumns) - 8)
    if ($width -ge 36) { Write-LotusDropZone $width 'Drop a picture here' 'HEIC · PNG · JPEG · WebP · RAW' } else { Write-LotusText 'Drag a picture into this window' }
    $clip = Get-LotusClipboardKind
    if ($clip -like 'image *') { Write-LotusLine "    $(E key)✓$($script:R) An image in the clipboard ($($clip.Substring(6) -replace 'x', ' × ')) – ⏎ takes it" }
    elseif ($clip -like 'files *') { Write-LotusLine "    $(E key)✓$($script:R) $($clip.Substring(6)) copied file(s) in the clipboard – ⏎ takes them" }
    Write-LotusDim '  Drop, then ⏎ · or type a path · esc goes back'
    Write-LotusBlank
    $line = Read-LotusLine 'Picture' ''
    if ($null -eq $line) { return }
    if (-not $line.Trim()) {
        if ($clip -ceq 'none') { return }
        return @(Save-LotusClipboardPicture (Join-Path $script:Paths.Cache 'img\clipboard'))
    }
    Split-LotusShellWords $line
}

# The picture editor in the browser: lib/edit/editor.py, the program of every system (Python's standard library – the page,
# the server and the geometry of the crop know no operating system). This is its glue and nothing more: find the picture,
# make sure Python and ImageMagick are there, start the server with Lotus' environment, show what it printed.
function script:Invoke-LotusImgEdit {
    param([string[]]$Words)
    Write-LotusHero 'Image editor' 'Crop, straighten and convert – in your browser, on this PC'

    # Python 3.9 or newer (nothing to install but Python itself)
    $py = Find-LotusPython
    if (-not $py) {
        Write-LotusError 'The editor needs Python 3.9 or newer' 'Python is free; Lotus uses only its standard library.' @(
            'winget install --id Python.Python.3.13 -e   then open a new window')
        return (St 1)
    }

    # the picture
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($w in $Words) { $paths.Add($w) }
    if (-not $paths.Count) {
        if (-not ((Test-LotusTty) -and (Test-LotusOutTty))) { Write-LotusError 'Which picture?' '' @('/img edit <picture>'); return (St 1) }
        foreach ($w in @(Read-LotusImgEditPaths)) { $paths.Add($w) }
        if (-not $paths.Count) { return (St 0) }
        Write-LotusBlank
    }
    $inputs = Get-LotusImgInputs $paths.ToArray()
    foreach ($m in $inputs.Missing) { Write-LotusWarn "Not found: $m" }
    if (-not $inputs.In.Count) {
        Write-LotusError 'No picture to edit' '' @("Pictures: $((($script:ImgExt | Select-Object -First 12) | ForEach-Object { $_.ToUpper() }) -join ', ') …")
        return (St 1)
    }
    if (@($inputs.From | Where-Object { $_ }).Count) {
        Write-LotusError 'The editor opens one picture at a time' '' @('A whole folder: /img convert <folder>')
        return (St 1)
    }
    if ($inputs.In.Count -gt 1) { Write-LotusDim "  $($inputs.In.Count) pictures – the editor opens the first, $(Split-Path -Leaf $inputs.In[0]). All of them at once: /img convert" }

    # the image program (ImageMagick) – the editor uses the one that was tried out here
    $magick = Find-LotusMagick
    if (-not $magick) { $magick = Install-LotusMagick; if (-not $magick) { return (St 1) } }

    # a picture from the clipboard has no folder: the new one goes to Downloads\Lotus
    $image = $inputs.In[0]
    $downloads = if ($env:LOTUS_DOWNLOADS) { $env:LOTUS_DOWNLOADS } else { Join-Path (Get-LotusHome) 'Downloads\Lotus' }
    $fromClipboard = $image.StartsWith((Join-Path $script:Paths.Cache 'img\clipboard') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    $vars = @{
        LOTUS_LANG = [string]$script:S['LOTUS_LANG']; LOTUS_THIS = 'this PC'; LOTUS_FILES_APP = 'File Explorer'
        LOTUS_EDIT_DATA = (Join-Path $script:Paths.Cache 'img\edit'); LOTUS_IMG_LAST = (Join-Path $script:Paths.State 'img-last'); LOTUS_DOWNLOADS = $downloads
        LOTUS_COLOR_KEY = $script:C['key']; LOTUS_COLOR_ACCENT = $script:C['accent']; LOTUS_COLOR_DIM = $script:C['dim']
    }
    if ($magick.Convert.Count -eq 1 -and (Split-Path -Leaf $magick.Convert[0]) -match '^magick(\.exe)?$') { $vars['LOTUS_MAGICK'] = $magick.Convert[0] }
    New-LotusDir $vars['LOTUS_EDIT_DATA'] | Out-Null
    $args_ = @($image)
    if ($fromClipboard) { $args_ += @('--out-dir', $downloads) }
    Write-LotusLog INFO img "editor: $(Split-Path -Leaf $image)"
    $rc = Invoke-LotusPython $py (Join-Path (Get-LotusRoot) 'lib/edit/editor.py') $args_ $vars
    if ($rc -eq 130) { $rc = 0 }                  # Ctrl-C is how it is closed, not a failure
    Write-LotusLog INFO img "editor closed ($rc)"
    St $rc
}
