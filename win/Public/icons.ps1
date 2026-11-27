# /icons on Windows – the icon of the folders on your Desktop: one, a few or all of them (a port of lib/cmd/icons.zsh)
#   /icons                                      guided: choose the folders, drop a picture into the window, check, done
#   /icons <picture>                            the same with the picture already chosen
#   /icons set <picture> <folder…>|--all        without questions: this picture for these folders – a name on the Desktop, or a path
#   /icons reset [<folder…>|--all]              the normal icons again (without folders: choose them from a list)
#   /icons list                                 the folders on your Desktop, and which have a picture of their own
#   /icons check                                what it needs, and whether this PC has it
# What is inside a folder is never changed – only the picture of the folder: File Explorer keeps it in a hidden desktop.ini and
# a hidden .ico in the folder (Private/Platform.ps1: Set-LotusFolderIcon, Reset-LotusFolderIcon). This file is the screens.

# What a picture may be called – the system decides in the end (Windows draws PNG, JPEG, BMP, GIF and TIFF; ImageMagick the rest)
$script:IconsExt = @('png', 'jpg', 'jpeg', 'jpe', 'heic', 'heif', 'avif', 'gif', 'tif', 'tiff', 'bmp', 'icns', 'webp', 'svg', 'ico')

function script:Invoke-Lotusicons {
    param([string]$Cmd, [string[]]$Rest)
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    $more = [string[]]@($Rest | Select-Object -Skip 1)
    if ($sub -ceq '') { if ((Test-LotusTty) -and (Test-LotusOutTty)) { return Invoke-LotusIconsGuided 'set' '' } else { return Show-LotusIconsHelp } }
    if ($sub -cin 'set', 'change') { return Invoke-LotusIconsSet $more }
    if ($sub -cin 'reset', 'undo', 'normal') { return Invoke-LotusIconsReset $more }
    if ($sub -cin 'list', 'ls') { return Show-LotusIconsList }
    if ($sub -cin 'check', 'needs', 'requirements') { return Show-LotusIconsCheck }
    if ($sub -cin 'help', '-h', '--help') { return Show-LotusIconsHelp }
    # a picture on its own: /icons star.png – also a path with spaces that was typed without quotes (the first words, joined)
    for ($k = 1; $k -le $Rest.Count; $k++) {
        $own = ConvertTo-LotusCleanPath (($Rest[0..($k - 1)]) -join ' ')
        if ((Test-LotusIconsPath $own) -and (Test-Path -LiteralPath $own -PathType Leaf) -and ($script:IconsExt -contains [IO.Path]::GetExtension($own).TrimStart('.').ToLowerInvariant())) { return Invoke-LotusIconsSet $Rest }
    }
    Write-LotusError "Unknown: /icons $sub" '' @('/icons   ·   /icons set <picture> <folders>   ·   /icons reset   ·   /icons check   ·   /icons help')
    St 1
}

# Text in the width of the window, every line indented: a long line that wraps on its own would start at the left edge
function script:Write-LotusIconsWrapped {
    param([string]$Indent, [string]$Text, [bool]$Dim = $false)
    $width = Get-LotusColumns
    if ($width -le 30) { $width = 80 }
    $max = $width - $Indent.Length - 2
    $on = if ($Dim) { E dim } else { '' }
    $off = if ($Dim) { $script:R } else { '' }
    $line = ''
    foreach ($word in ((Convert-LotusHere $Text) -split '\s+')) {
        if (-not $word) { continue }
        if ($line -and ($line.Length + $word.Length + 1) -gt $max) { Write-LotusLine "$Indent$on$line$off"; $line = $word }
        else { $line = if ($line) { "$line $word" } else { $word } }
    }
    if ($line) { Write-LotusLine "$Indent$on$line$off" }
}

function script:Show-LotusIconsHelp {
    Write-LotusHero 'Folder icons' 'Change the icon of the folders on your Desktop – one, a few or all of them'
    $k = E key; $d = E dim; $r = $script:R
    foreach ($row in @('/icons|guided: choose the folders, drop a picture into the window, done', '/icons <picture>|the same with the picture already chosen',
            '/icons set <picture> <folders>|without questions – a folder is a name on the Desktop, or a path', '  --all|every folder on the Desktop',
            '/icons reset [<folders>]|the normal icons again – without folders: choose them from a list', '  --all|every folder on the Desktop that has a picture of its own',
            '/icons list|the folders on your Desktop, and which have a picture of their own', '/icons check|what it needs, and whether this PC has it')) {
        $p = $row -split '\|', 2
        Write-LotusLine "    $k$(PadR $p[0] 32)$r$($p[1])"
    }
    Write-LotusBlank
    Write-LotusSection 'What it needs'; Write-LotusBlank
    Write-LotusText '  Windows 10 or 11. Nothing to install, no administrator rights – Windows draws the icon itself.'
    Write-LotusText '  A picture: PNG, JPEG, BMP, GIF, TIFF or ICO; WebP, HEIC and SVG with ImageMagick (optional).'
    Write-LotusDim '  /icons check shows what this PC has.'
    Write-LotusBlank
    Write-LotusSection 'Examples'; Write-LotusBlank
    Write-LotusLine "    $d/icons$r"
    Write-LotusLine "    $d/icons ~\Pictures\star.png$r"
    Write-LotusLine "    $d/icons set ~\Pictures\star.png Projects Photos$r"
    Write-LotusLine "    $d/icons set ~\Pictures\star.png --all$r"
    Write-LotusLine "    $d/icons reset --all$r"
    Write-LotusBlank
    Write-LotusDim '  What is inside your folders stays as it is – only the picture of the folder changes. The original picture stays where it is.'
    Write-LotusBlank
    St 0
}

# ── What it needs ─────────────────────────────────────────────

# The list of what it needs, with a ✓ for what this PC has → $true, or $false when something is missing.
# A ! is something that is good to have; a ✗ has to be fixed first, and says how.
function script:Write-LotusIconsNeeds {
    $needs = Get-LotusFolderIconNeeds
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $needs.Value) { $rows.Add($row) }
    $rows.Add("ok|A picture|$(Get-LotusFolderIconTypes)|")
    $d = E dim; $r = $script:R
    $width = Get-LotusColumns
    if ($width -le 40) { $width = 80 }
    $labelWidth = 0; $detailWidth = 0
    foreach ($row in $rows) {
        $f = $row -split '\|'
        if ($f[1].Length -gt $labelWidth) { $labelWidth = $f[1].Length }
        if ($f.Count -gt 2 -and $f[2].Length -gt $detailWidth) { $detailWidth = $f[2].Length }
    }
    $wide = ($labelWidth + $detailWidth + 10) -le $width      # the details in a column next to the labels – or under them when the window is narrow
    Write-LotusSection 'What it needs'; Write-LotusBlank
    foreach ($row in $rows) {
        $f = $row -split '\|', 4
        $detail = if ($f.Count -gt 2) { $f[2] } else { '' }
        $fix = if ($f.Count -gt 3) { $f[3] } else { '' }
        $mark = switch ($f[0]) { 'ok' { "$(E '1')$(E key)✓$r" } 'warn' { "$(E '1')$(E key2)!$r" } default { "$(E '1;38;5;203')✗$r" } }
        if ($wide) { Write-LotusLine "    $mark $(PadR $f[1] $labelWidth)$(if ($detail) { "  $d$detail$r" })" }
        else {
            Write-LotusLine "    $mark $($f[1])"
            if ($detail) { Write-LotusIconsWrapped '      ' $detail $true }
        }
        if ($f[0] -cne 'ok' -and $fix) { Write-LotusIconsWrapped '      ' $fix $true }
    }
    $needs.Code -eq 0
}

function script:Show-LotusIconsCheck {
    Write-LotusHero 'Folder icons' 'What it needs, and whether this PC has it'
    Write-LotusBlank
    if (Write-LotusIconsNeeds) {
        Write-LotusBlank
        Write-LotusSuccess 'Ready – run /icons'
        Write-LotusBlank
        return (St 0)
    }
    Write-LotusBlank
    Write-LotusDim '  Fix what is marked ✗, then run /icons check again.'
    Write-LotusBlank
    St 1
}

# ── Folders and pictures ──────────────────────────────────────

# The folders on the Desktop: no hidden or system ones, no links – by name
function script:Get-LotusIconsDesktopFolders {
    $desktop = Get-LotusDesktopFolder
    if (-not (Test-Path -LiteralPath $desktop -PathType Container)) { return @() }
    $skip = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::ReparsePoint
    @(Get-ChildItem -LiteralPath $desktop -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band $skip) } | Sort-Object Name | ForEach-Object FullName)
}

function script:Test-LotusIconsPath {
    param([string]$Path)
    try { Test-Path -LiteralPath $Path } catch { $false }
}

# What was typed, dropped or given → @{ Found = paths; Missing = what is not there }. A bare name is looked for in the base folder
# first (Projects → the Desktop's Projects), then as a path; a path with spaces that was not quoted is put together again from
# its words.
function script:Get-LotusIconsPaths {
    param([string]$Base, [string[]]$Words)
    $found = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $ok = $false
        for ($j = $i; $j -lt $Words.Count; $j++) {
            $text = ($Words[$i..$j]) -join ' '
            $hit = $null
            if ($Base -and $text -notmatch '[\\/]' -and $text -notmatch '^(~|file://)' -and (Test-LotusIconsPath (Join-Path $Base $text))) { $hit = Join-Path $Base $text }
            else {
                $clean = ConvertTo-LotusCleanPath $text
                if (Test-LotusIconsPath $clean) { $hit = $clean }
            }
            if ($hit) { $found.Add($hit); $i = $j; $ok = $true; break }
        }
        if (-not $ok) { $missing.Add($Words[$i]) }
    }
    [pscustomobject]@{ Found = $found.ToArray(); Missing = $missing.ToArray() }
}

# Words → @{ Folders (each once); NotFolder; Missing }
function script:Get-LotusIconsFoldersFrom {
    param([string[]]$Words)
    $got = Get-LotusIconsPaths (Get-LotusDesktopFolder) $Words
    $folders = [System.Collections.Generic.List[string]]::new()
    $notFolder = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $got.Found) {
        if (Test-Path -LiteralPath $p -PathType Container) { if (-not $folders.Contains($p)) { $folders.Add($p) } } else { $notFolder.Add($p) }
    }
    [pscustomobject]@{ Folders = $folders.ToArray(); NotFolder = $notFolder.ToArray(); Missing = $got.Missing }
}

# Can this file be an icon? → @{ Ok; Why }
function script:Test-LotusIconsPicture {
    param([string]$Path)
    $why = ''
    if (-not (Test-Path -LiteralPath $Path)) { $why = 'it is not there' }
    elseif (Test-Path -LiteralPath $Path -PathType Container) { $why = 'it is a folder – a picture is a file' }
    elseif ($script:IconsExt -cnotcontains [IO.Path]::GetExtension($Path).TrimStart('.').ToLowerInvariant()) { $why = 'it is not a picture file (PNG, JPEG, HEIC, GIF, SVG …)' }
    else {
        $size = (Get-Item -LiteralPath $Path).Length
        if ($size -eq 0) { $why = 'the file is empty' } elseif ($size -gt 104857600) { $why = 'the file is over 100 MB' }
    }
    [pscustomobject]@{ Ok = (-not $why); Why = $why }
}

# What a folder holds, for the list: "12 items", "empty", plus "has a picture of its own"
function script:Get-LotusIconsFolderNote {
    param([string]$Folder)
    $count = @(Get-ChildItem -LiteralPath $Folder -ErrorAction SilentlyContinue | Where-Object { $_.Name -ine 'desktop.ini' -and $_.Name -notlike "$($script:IconFileName)-*.ico" }).Count
    $note = if (-not $count) { 'empty' } elseif ($count -eq 1) { '1 item' } else { "$count items" }
    if (Test-LotusFolderIcon $Folder) { $note += ' · has a picture of its own' }
    $note
}

function script:Show-LotusIconsList {
    $desktop = Get-LotusDesktopFolder
    Write-LotusHero 'Folder icons' "The folders on your Desktop – $(Format-LotusHomePath $desktop)"
    $folders = @(Get-LotusIconsDesktopFolders)
    if (-not $folders.Count) { Write-LotusInfo 'No folders on your Desktop'; Write-LotusBlank; return (St 0) }
    foreach ($f in $folders) { Write-LotusLine "    $(PadR (Split-Path -Leaf $f) 26) $(E dim)$(Get-LotusIconsFolderNote $f)$($script:R)" }
    Write-LotusBlank
    St 0
}

# ── The screens ───────────────────────────────────────────────

function script:Write-LotusIconsCancelled {
    Write-LotusBlank; Write-LotusDim '  Nothing was changed.'; Write-LotusBlank
}

# The drop zone: Windows Terminal types the path of what is dropped into the window, Lotus reads it without running anything
#   → @{ Status = ok | back (Esc, q) | empty; Words }
function script:Read-LotusIconsDrop {
    param([string]$Title, [string]$Types, [string[]]$Hints)
    $width = [Math]::Min(60, (Get-LotusColumns) - 8)
    if ($width -ge 36) { Write-LotusDropZone $width $Title $Types } else { Write-LotusText $Title }
    foreach ($hint in $Hints) { Write-LotusIconsWrapped '  ' $hint $true }
    Write-LotusBlank
    if (-not (Test-LotusTty)) { return [pscustomobject]@{ Status = 'back'; Words = @() } }       # (no keyboard: nobody can answer)
    $line = Read-LotusLine 'Drop here' ''
    if ($null -eq $line) { return [pscustomobject]@{ Status = 'back'; Words = @() } }
    $trimmed = $line.Trim()
    if ($trimmed -match '^(?i)(q|quit|back|exit|cancel)$') { return [pscustomobject]@{ Status = 'back'; Words = @() } }
    if (-not $trimmed) { return [pscustomobject]@{ Status = 'empty'; Words = @() } }
    $words = [System.Collections.Generic.List[string]]::new()
    foreach ($w in (Split-LotusShellWords $line)) { $words.Add($w) }
    [pscustomobject]@{ Status = 'ok'; Words = $words.ToArray() }
}

# The folders of the Desktop as a list to tick: Space ticks, A ticks all, ⏎ continues → the folders, or $null for back
function script:Read-LotusIconsToggleFolders {
    param([string]$Mode, [string[]]$Folders)
    $opts = [System.Collections.Generic.List[string]]::new()
    $script:Toggles = @()
    foreach ($f in $Folders) {
        $note = Get-LotusIconsFolderNote $f
        $opts.Add("$(Split-Path -Leaf $f)|$note")
        # to give the normal icon back, the folders that have a picture of their own start ticked
        $script:Toggles += $(if ($Mode -ceq 'reset' -and $note -like '*of its own*') { 1 } else { 0 })
    }
    while ($true) {
        if (-not (Test-LotusTty)) { return $null }
        Write-LotusDim '  Tick the folders with Space – A ticks all of them.'
        if (-not (Read-LotusToggles $opts.ToArray())) { return $null }
        $chosen = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $Folders.Count; $i++) { if ($script:Toggles[$i]) { $chosen.Add($Folders[$i]) } }
        if ($chosen.Count) { return , $chosen.ToArray() }
        Write-LotusWarn 'No folder is ticked – press Space on the ones you want.'
    }
}

# Step 1 – the folders → @{ Folders }, or $null for back
function script:Read-LotusIconsFolders {
    param([string]$Mode)
    $desk = @(Get-LotusIconsDesktopFolders)
    $own = @($desk | Where-Object { Test-LotusFolderIcon $_ })
    Write-LotusLine "  $($script:B)Step 1 of 3 · Which folders?$($script:R)"
    $opts = [System.Collections.Generic.List[string]]::new()
    $acts = [System.Collections.Generic.List[string]]::new()
    if ($Mode -ceq 'reset') {
        if ($own.Count -gt 1) { $opts.Add("All $($own.Count) folders that have a picture of their own|on the Desktop"); $acts.Add('own') }
        elseif ($own.Count -eq 1) { $opts.Add("$(Split-Path -Leaf $own[0])|the one folder on the Desktop that has a picture of its own"); $acts.Add('own') }
        else { Write-LotusDim '  None of the folders on your Desktop has a picture of its own.' }
        if ($desk.Count) { $opts.Add('Choose which ones|a list of the folders on your Desktop'); $acts.Add('choose') }
    } else {
        if ($desk.Count -gt 1) { $opts.Add("All $($desk.Count) folders on the Desktop|every folder you see there"); $acts.Add('all') }
        elseif ($desk.Count -eq 1) { $opts.Add("$(Split-Path -Leaf $desk[0])|the one folder on the Desktop"); $acts.Add('all') }
        if ($desk.Count -gt 1) { $opts.Add('Choose which ones|a list of the folders on your Desktop'); $acts.Add('choose') }
    }
    $opts.Add('Other folders|drop folders from anywhere into the window'); $acts.Add('other')
    if (-not $desk.Count -and $Mode -ceq 'set') { Write-LotusDim '  There are no folders on your Desktop – drop the folders you want to change.' }
    while ($true) {
        if ($opts.Count -eq 1) { $pick = 1 } else { $pick = Read-LotusSelect 1 $opts.ToArray(); if ($null -eq $pick) { return $null } }
        switch ($acts[$pick - 1]) {
            'all' { return [pscustomobject]@{ Folders = $desk } }
            'own' { return [pscustomobject]@{ Folders = $own } }
            'choose' {
                $chosen = Read-LotusIconsToggleFolders $Mode $desk
                if ($null -ne $chosen) { return [pscustomobject]@{ Folders = [string[]]$chosen } }
            }
            'other' {
                while ($true) {
                    $drop = Read-LotusIconsDrop 'Drop folders here' 'one or several · from anywhere' @('Drag the folders from Finder into this window, then press ⏎.', 'Or type a path. q goes back.')
                    if ($drop.Status -ceq 'back') { if ($opts.Count -eq 1) { return $null }; break }
                    if ($drop.Status -ceq 'empty') { Write-LotusDim '  Drop a folder first – or type q to go back.'; continue }
                    $got = Get-LotusIconsFoldersFrom $drop.Words
                    foreach ($m in $got.Missing) { Write-LotusWarn "Not found: $m" }
                    foreach ($m in $got.NotFolder) { Write-LotusWarn "Not a folder: $(Split-Path -Leaf $m)" }
                    if ($got.Folders.Count) { return [pscustomobject]@{ Folders = $got.Folders } }
                }
            }
        }
    }
}

# Step 2 – the picture(s) → @{ Pictures } (one for each folder; '' leaves the folder as it is), or $null for back
function script:Read-LotusIconsPictures {
    param([string[]]$Folders)
    $n = $Folders.Count
    $types = Get-LotusFolderIconTypes
    $each = $false
    Write-LotusLine "  $($script:B)Step 2 of 3 · The picture$($script:R)"
    if ($n -gt 1) {
        Write-LotusDim "  One picture for all $n folders, or a different one for each?"
        $pick = Read-LotusSelect 1 @("The same picture for all $n folders|you drop one picture", 'A different picture for each folder|you drop one picture per folder')
        if ($null -eq $pick) { return $null }
        if ($pick -eq 2) { $each = $true }
    }
    if (-not $each) {
        while ($true) {
            $drop = Read-LotusIconsDrop 'Drop the picture here' $types @('Drag the picture from Finder into this window, then press ⏎.', 'Or type its path. q goes back.')
            if ($drop.Status -ceq 'back') { return $null }
            if ($drop.Status -ceq 'empty') { Write-LotusDim '  Drop a picture first – or type q to go back.'; continue }
            $got = Get-LotusIconsPaths '' $drop.Words
            if ($got.Found.Count -gt 1) { Write-LotusDim "  $($got.Found.Count) pictures dropped – the first one is used." }
            if (-not $got.Found.Count) { Write-LotusWarn "Not found: $($got.Missing[0])"; continue }
            $check = Test-LotusIconsPicture $got.Found[0]
            if (-not $check.Ok) { Write-LotusWarn "$(Split-Path -Leaf $got.Found[0]): $($check.Why)"; continue }
            return [pscustomobject]@{ Pictures = [string[]]@($Folders | ForEach-Object { $got.Found[0] }) }
        }
    }
    $pictures = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $n; $i++) {
        while ($true) {
            Write-LotusDim "  Folder $($i + 1) of $n"
            # (typographic quotes are quotes to PowerShell – these come from their character codes)
            $drop = Read-LotusIconsDrop "Drop the picture for $([char]0x201C)$(Split-Path -Leaf $Folders[$i])$([char]0x201D)" $types @('Drag the picture from Finder into this window, then press ⏎.', '⏎ alone leaves this folder as it is. q goes back.')
            if ($drop.Status -ceq 'back') { return $null }
            if ($drop.Status -ceq 'empty') { $pictures.Add(''); break }
            $got = Get-LotusIconsPaths '' $drop.Words
            if (-not $got.Found.Count) { Write-LotusWarn "Not found: $($got.Missing[0])"; continue }
            $check = Test-LotusIconsPicture $got.Found[0]
            if (-not $check.Ok) { Write-LotusWarn "$(Split-Path -Leaf $got.Found[0]): $($check.Why)"; continue }
            $pictures.Add($got.Found[0]); break
        }
    }
    if (-not @($pictures | Where-Object { $_ }).Count) { Write-LotusWarn 'No picture was dropped.'; return $null }
    [pscustomobject]@{ Pictures = $pictures.ToArray() }
}

# Step 3 – what will happen, and the question → $true: go
function script:Confirm-LotusIconsPlan {
    param([string]$Mode, [string[]]$Folders, [string[]]$Pictures)
    Write-LotusLine "  $($script:B)Step 3 of 3 · Check$($script:R)"
    Write-LotusBlank
    $todo = 0; $shown = 0
    for ($i = 0; $i -lt $Folders.Count; $i++) {
        if ($Mode -ceq 'set' -and -not $Pictures[$i]) { continue }
        $todo++
        if ($shown -ge 8) { continue }
        $shown++
        $name = Split-Path -Leaf $Folders[$i]
        if ($Mode -ceq 'set') { Write-LotusLine "    $(PadR (Cut $name 24) 24) $(E dim)→$($script:R) $(Split-Path -Leaf $Pictures[$i])" } else { Write-LotusLine "    $name" }
    }
    if ($todo -gt $shown) { Write-LotusDim "    … and $($todo - $shown) more" }
    Write-LotusBlank
    $s = if ($todo -ne 1) { 's' } else { '' }
    if ($Mode -ceq 'set') { Read-LotusConfirm "Change the icon of $todo folder${s}?" 'y' } else { Read-LotusConfirm "Give $todo folder$s the normal icon back?" 'y' }
}

# ── Doing it ──────────────────────────────────────────────────

# The folders (and pictures) → the icons are changed, one folder after the other → @{ Done; Failed; Code }
function script:Invoke-LotusIconsApply {
    param([string]$Mode, [string[]]$Folders, [string[]]$Pictures)
    $done = 0; $failed = 0; $skipped = 0
    $said = @{}
    for ($i = 0; $i -lt $Folders.Count; $i++) {
        $name = Split-Path -Leaf $Folders[$i]
        if ($Mode -ceq 'set') {
            if (-not $Pictures[$i]) { $skipped++; continue }
            $r = Set-LotusFolderIcon $Folders[$i] $Pictures[$i]
        } else { $r = Reset-LotusFolderIcon $Folders[$i] }
        if ($r.Code -eq 0) { $done++; Write-LotusLine "  $(E '1')$(E key)✓$($script:R) $name"; continue }
        if ($r.Code -eq 2) {
            Write-LotusError 'Folder icons do not work here yet' 'This PC is missing something this needs.'
            [void](Write-LotusIconsNeeds)
            Write-LotusBlank
            return [pscustomobject]@{ Done = $done; Failed = $Folders.Count; Code = 1 }
        }
        $failed++
        $title = if ($r.Msg.Count) { $r.Msg[0] } else { 'it did not work' }
        Write-LotusLine "  $(E '1;38;5;203')✗$($script:R) $name – $title"
        if (-not $said.ContainsKey($title)) {
            $said[$title] = $true
            if ($r.Msg.Count -gt 1 -and $r.Msg[1]) { Write-LotusLine "      $(E dim)$($r.Msg[1])$($script:R)" }
            if ($r.Msg.Count -gt 2 -and $r.Msg[2]) { Write-LotusLine "      $(E dim)$($r.Msg[2])$($script:R)" }
        }
        Write-LotusLog WARN icons "${Mode}: $title"
    }
    Write-LotusBlank
    $s = if ($done -ne 1) { 's' } else { '' }
    $verb = if ($done -eq 1) { 'has' } else { 'have' }
    if ($done) {
        if ($Mode -ceq 'set') { Write-LotusSuccess "$done folder$s $verb a new icon$(if ($skipped) { " ($skipped left as they were)" })" }
        else { Write-LotusSuccess "$done folder$s $verb the normal icon again" }
    }
    if ($failed) { Write-LotusWarn "$failed folder$(if ($failed -ne 1) { 's' }) could not be changed" }
    Write-LotusLog INFO icons "${Mode}: $done done, $failed failed, $skipped left out"
    if ($done) {
        if ($Mode -ceq 'set') { Write-LotusDim '  The normal icons are back any time: /icons reset' }
        Write-LotusDim '  A window that is open shows the change after you open the folder again.'
        Write-LotusBlank
        Show-LotusPetReact done
    }
    [pscustomobject]@{ Done = $done; Failed = $failed; Code = $(if ($failed -eq 0 -and $done -gt 0) { 0 } else { 1 }) }
}

# ── The commands ──────────────────────────────────────────────

# /icons, /icons <picture>, /icons reset – with questions, in a terminal
function script:Invoke-LotusIconsGuided {
    param([string]$Mode, [string]$Picture)
    if ($Mode -ceq 'set') { Write-LotusHero 'Folder icons' 'Give the folders on your Desktop a new icon – one, a few or all of them' }
    else { Write-LotusHero 'Folder icons' 'Give the folders on your Desktop their normal icon back' }
    Write-LotusIconsWrapped '  ' 'What is inside your folders stays as it is – only the picture of the folder changes.' $true
    Write-LotusBlank
    if (-not (Write-LotusIconsNeeds)) { Write-LotusBlank; Write-LotusDim '  Fix what is marked ✗, then run /icons again.'; Write-LotusBlank; return (St 1) }
    Write-LotusBlank
    if ($Mode -ceq 'set') {
        Write-LotusSection 'How it works'; Write-LotusBlank
        Write-LotusLine '    1  Choose the folders – one, a few or all of them'
        if ($Picture) { Write-LotusLine "    2  The picture: $(Split-Path -Leaf $Picture)" } else { Write-LotusLine '    2  Drop a picture into this window' }
        Write-LotusLine '    3  Check it and press ⏎'
        Write-LotusBlank
    }
    $chosen = Read-LotusIconsFolders $Mode
    if ($null -eq $chosen) { Write-LotusIconsCancelled; return (St 0) }
    $folders = [string[]]@($chosen.Folders)
    Write-LotusBlank
    $pictures = @()
    if ($Mode -ceq 'set') {
        if ($Picture) { $pictures = [string[]]@($folders | ForEach-Object { $Picture }) }
        else {
            $got = Read-LotusIconsPictures $folders
            if ($null -eq $got) { Write-LotusIconsCancelled; return (St 0) }
            $pictures = [string[]]@($got.Pictures)
            Write-LotusBlank
        }
    }
    if (-not (Confirm-LotusIconsPlan $Mode $folders $pictures)) { Write-LotusIconsCancelled; return (St 0) }
    Write-LotusBlank
    $result = Invoke-LotusIconsApply $Mode $folders $pictures
    St $result.Code
}

# /icons set <picture> <folders…>|--all
function script:Invoke-LotusIconsSet {
    param([string[]]$Words)
    $all = $false
    $rest = [System.Collections.Generic.List[string]]::new()
    foreach ($w in $Words) { if ($w -cin '--all', '-a') { $all = $true } else { $rest.Add($w) } }
    if (-not $rest.Count) { Write-LotusError 'Which picture?' '' @('/icons set <picture> <folders>   ·   /icons set <picture> --all   ·   /icons <picture>'); return (St 1) }
    $desktop = Get-LotusDesktopFolder
    $got = Get-LotusIconsPaths $desktop $rest.ToArray()
    foreach ($m in $got.Missing) { Write-LotusWarn "Not found: $m" }
    if (-not $got.Found.Count) { Write-LotusError 'No picture found' '' @('/icons set <picture> <folders>'); return (St 1) }
    $picture = $got.Found[0]
    $check = Test-LotusIconsPicture $picture
    if (-not $check.Ok) { Write-LotusError "$(Split-Path -Leaf $picture) cannot be an icon" $check.Why @("A picture: $(Get-LotusFolderIconTypes)"); return (St 1) }
    $folders = [System.Collections.Generic.List[string]]::new()
    foreach ($p in ($got.Found | Select-Object -Skip 1)) {
        if (Test-Path -LiteralPath $p -PathType Container) { if (-not $folders.Contains($p)) { $folders.Add($p) } } else { Write-LotusWarn "Not a folder: $(Split-Path -Leaf $p)" }
    }
    if ($all) {
        $desk = @(Get-LotusIconsDesktopFolders)
        if (-not $desk.Count) { Write-LotusError 'No folders on your Desktop' '' @('Name the folders: /icons set <picture> <folders>'); return (St 1) }
        foreach ($f in $desk) { if (-not $folders.Contains($f)) { $folders.Add($f) } }
    }
    if (-not $folders.Count) {
        if ((Test-LotusTty) -and (Test-LotusOutTty)) { return Invoke-LotusIconsGuided 'set' $picture }
        $leaf = Split-Path -Leaf $picture
        Write-LotusError 'Which folders?' '' @("/icons set $leaf <folders>   ·   /icons set $leaf --all")
        return (St 1)
    }
    $pictures = [string[]]@($folders | ForEach-Object { $picture })
    $result = Invoke-LotusIconsApply 'set' $folders.ToArray() $pictures
    St $result.Code
}

# /icons reset [<folders…>|--all]
function script:Invoke-LotusIconsReset {
    param([string[]]$Words)
    $all = $false
    $rest = [System.Collections.Generic.List[string]]::new()
    foreach ($w in $Words) { if ($w -cin '--all', '-a') { $all = $true } else { $rest.Add($w) } }
    $folders = [System.Collections.Generic.List[string]]::new()
    if ($rest.Count) {
        $got = Get-LotusIconsFoldersFrom $rest.ToArray()
        foreach ($m in $got.Missing) { Write-LotusWarn "Not found: $m" }
        foreach ($m in $got.NotFolder) { Write-LotusWarn "Not a folder: $(Split-Path -Leaf $m)" }
        foreach ($f in $got.Folders) { $folders.Add($f) }
    }
    if ($all) {
        $desk = @(Get-LotusIconsDesktopFolders)
        if (-not $desk.Count) { Write-LotusError 'No folders on your Desktop' '' @('Name the folders: /icons reset <folders>'); return (St 1) }
        foreach ($f in $desk) { if ((Test-LotusFolderIcon $f) -and -not $folders.Contains($f)) { $folders.Add($f) } }
        if (-not $folders.Count -and -not $rest.Count) { Write-LotusInfo 'None of the folders on your Desktop has a picture of its own.'; return (St 0) }
    }
    if (-not $folders.Count) {
        if ($rest.Count) { return (St 1) }
        if ((Test-LotusTty) -and (Test-LotusOutTty)) { return Invoke-LotusIconsGuided 'reset' '' }
        Write-LotusError 'Which folders?' '' @('/icons reset <folders>   ·   /icons reset --all')
        return (St 1)
    }
    $result = Invoke-LotusIconsApply 'reset' $folders.ToArray() @()
    St $result.Code
}
