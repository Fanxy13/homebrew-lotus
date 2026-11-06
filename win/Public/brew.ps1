# /brew on Windows: search, details and installs with winget, the package manager of Windows – a port of
# lib/cmd/brew.zsh. The same cards and the same rule: the exact command is shown, nothing is installed without a yes,
# and winget runs in the open – its own questions (licenses, administrator rights) are answered by you, not by Lotus.
#   /brew <words>   search · /brew info <id>   one package · /brew install <id>   install after a preview

function script:Invoke-Lotusbrew {
    param([string]$Cmd, [string[]]$Rest)
    if (-not (Test-LotusWinget)) { return (St 1) }
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    $more = [string[]]@($Rest | Select-Object -Skip 1)
    switch -CaseSensitive ($sub) {
        'search' { return Invoke-LotusPkgSearch ($more -join ' ') }
        'info' { return Show-LotusPkgCard $(if ($more.Count) { $more[0] } else { '' }) }
        'install' { return Show-LotusPkgCard $(if ($more.Count) { $more[0] } else { '' }) }
        '' { Write-LotusError 'What should Lotus look for?' '' @('Example: /brew firefox   or   /brew install Mozilla.Firefox'); return (St 1) }
        default { return Invoke-LotusPkgSearch ($Rest -join ' ') }
    }
}

# winget is there – else what it is and where it comes from (it ships with Windows 11, as "App Installer")
function script:Test-LotusWinget {
    if (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue) { return $true }
    Write-LotusError 'winget is not installed' 'winget is the package manager of Windows: Lotus installs apps with it.' @(
        'It comes with Windows 11 as "App Installer" – from the Microsoft Store: ms-windows-store://pdp/?productid=9NBLGGH4NNS1')
    if ((Test-LotusTty) -and $IsWindows -and (Read-LotusConfirm 'Open App Installer in the Microsoft Store?' 'n')) { [void](Open-LotusTarget 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1') }
    $false
}

# A package id or search text Lotus hands to winget: letters, digits and . _ - + only (and spaces in a search)
function script:Test-LotusPkgName {
    param([string]$Name, [switch]$Search)
    if ($Search) { $Name -match '^[\p{L}\p{Nd}._+\- ]{1,60}$' } else { $Name -match '^[A-Za-z0-9][A-Za-z0-9._+\-]{0,127}$' -and $Name -notmatch '\.\.' }
}

# winget's own output as text (it draws progress with \r and box characters: those go)
function script:Invoke-LotusWingetText {
    param([string[]]$Arguments)
    $raw = Invoke-LotusNativeText 'winget' ($Arguments + @('--accept-source-agreements', '--disable-interactivity'))
    $lines = foreach ($l in $raw -split "`n") {
        $l = ($l -split "`r")[-1]
        if ($l -match '^\s*[-\\|/]\s*$' -or $l -match '[█▒]') { continue }
        $l.TrimEnd()
    }
    , @($lines)
}

# A table winget printed (search, list) → rows of objects: the columns start where the header's words start. The header
# is in the language of Windows, so the columns are taken by position: name, id, version, then the rest.
function script:ConvertFrom-LotusWingetTable {
    param([string[]]$Lines)
    $sep = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^-{10,}\s*$') { $sep = $i; break } }
    if ($sep -lt 1) { return @() }
    $header = $Lines[$sep - 1]
    $starts = @([regex]::Matches($header, '\S+') | ForEach-Object Index)
    if ($starts.Count -lt 3) { return @() }
    foreach ($line in $Lines[($sep + 1)..($Lines.Count - 1)]) {
        if (-not $line.Trim() -or $line.Length -le $starts[1]) { continue }
        $cell = {
            param($k)
            $a = $starts[$k]
            if ($a -ge $line.Length) { return '' }
            $b = if ($k + 1 -lt $starts.Count) { [Math]::Min($starts[$k + 1], $line.Length) } else { $line.Length }
            $line.Substring($a, $b - $a).Trim()
        }
        $id = & $cell 1
        if (-not $id -or $id -match '\s') { continue }
        [pscustomobject]@{ Name = (& $cell 0); Id = $id; Version = (& $cell 2); Source = $(if ($starts.Count -gt 3) { & $cell ($starts.Count - 1) } else { '' }) }
    }
}

# Is it installed? (winget list knows what Windows installed, also without winget)
function script:Test-LotusPkgInstalled {
    param([string]$Id)
    $lines = Invoke-LotusWingetText @('list', '--id', $Id, '--exact')
    @(ConvertFrom-LotusWingetTable $lines | Where-Object { $_.Id -eq $Id }).Count -gt 0
}

# Details of one package (winget show) → @{ Id; Name; Version; Publisher; Description; Homepage } or $null. winget prints
# them in the language of Windows: the English names are read, the first line names the package in every language.
function script:Get-LotusPkgDetails {
    param([string]$Id)
    $lines = Invoke-LotusWingetText @('show', '--id', $Id, '--exact')
    $first = $lines | Where-Object { $_ -match "\[$([regex]::Escape($Id))\]" } | Select-Object -First 1
    if (-not $first) { return $null }
    $get = { param($keys) foreach ($l in $lines) { foreach ($k in $keys) { if ($l -match "^\s*$([regex]::Escape($k)):\s*(.+)$") { return $Matches[1].Trim() } } }; '' }
    [pscustomobject]@{
        Id = $Id
        Name = ($first -replace '^\S+\s+', '' -replace "\s*\[$([regex]::Escape($Id))\]\s*$", '').Trim()
        Version = & $get @('Version')
        Publisher = & $get @('Publisher', 'Herausgeber', 'Éditeur', 'Editor')
        Description = & $get @('Description', 'Short Description', 'Beschreibung', 'Descripción')
        Homepage = & $get @('Homepage', 'Publisher Url', 'Startseite', "Page d’accueil", 'Página principal')
    }
}

# Packages for a search → objects (Name, Id, Version, Source): with the WinGet PowerShell module when it is installed,
# else from winget's table. Ids winget had to cut (…) are left out; the Microsoft Store has no ids Lotus can check.
function script:Find-LotusPkg {
    param([string]$Query)
    if (Get-Command Find-WinGetPackage -ErrorAction SilentlyContinue) {
        try {
            return @(Find-WinGetPackage -Query $Query -ErrorAction Stop | Where-Object { $_.Source -eq 'winget' } | Select-Object -First 40 |
                    ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Id = [string]$_.Id; Version = [string]$_.Version; Source = [string]$_.Source } })
        } catch { }
    }
    @(ConvertFrom-LotusWingetTable (Invoke-LotusWingetText @('search', '--query', $Query)) |
            Where-Object { $_.Source -ne 'msstore' -and $_.Id -notmatch '(…|\.\.\.)$' } | Select-Object -First 40)
}

function script:Invoke-LotusPkgSearch {
    param([string]$Query)
    $q = $Query.Trim()
    if (-not $q -or -not (Test-LotusPkgName $q -Search)) {
        Write-LotusError 'Unusual search text' $q @('Use letters, numbers and - . + only')
        return (St 1)
    }
    Write-LotusHeader 'winget' "search: $q"
    Write-LotusStep 'Searching …'
    $rows = @(Find-LotusPkg $q)
    Write-LotusRaw "$([char]27)[1A$([char]27)[K"
    if (-not $rows.Count) {
        Write-LotusError "Nothing found for `"$q`"" '' @('Try a shorter word, or /install to browse apps by category')
        return (St 1)
    }
    # best matches first, by name and id
    $byKey = @{}
    foreach ($r in $rows) { $byKey["$($r.Name)`t$($r.Id)"] = $r }
    $scored = foreach ($r in $rows) { [pscustomobject]@{ R = $r; S = [Math]::Max((Get-LotusScore $q $r.Name), (Get-LotusScore $q $r.Id) - 2) } }
    $order = @($scored | Sort-Object -Property @{ Expression = 'S'; Descending = $true }, @{ Expression = { $_.R.Name } } | Select-Object -First 12 | ForEach-Object R)
    $i = 0
    foreach ($r in $order) { $i++; Write-LotusResult $i $r.Name $r.Version $r.Id '' }
    Write-LotusBlank
    $pick = Read-LotusChoice 'Show details' @($order | ForEach-Object { "$($_.Name)  ($($_.Id))" })
    if ($null -eq $pick) { return (St 0) }
    Show-LotusPkgCard $order[$pick - 1].Id
}

# The card of one package, then the offer to install it
function script:Show-LotusPkgCard {
    param([string]$Id, [string]$About)
    if (-not $Id) { Write-LotusError 'Which package?' '' @('Example: /brew info Mozilla.Firefox'); return (St 1) }
    if (-not (Test-LotusPkgName $Id)) { Write-LotusError 'Not a valid package id' $Id; return (St 1) }
    Write-LotusStep "Looking up $Id …"
    $d = Get-LotusPkgDetails $Id
    Write-LotusRaw "$([char]27)[1A$([char]27)[K"
    if (-not $d) {
        Write-LotusError "winget has no package with the id `"$Id`"" '' @("Search instead: /brew $Id")
        return (St 1)
    }
    $installed = Test-LotusPkgInstalled $Id
    Write-LotusBlank
    Write-LotusCard $(if ($d.Name) { $d.Name } else { $Id }) @(
        "ABOUT|$(if ($About) { $About } elseif ($d.Description) { $d.Description } else { '-' })"
        "VERSION|$(if ($d.Version) { $d.Version } else { '?' })"
        "PUBLISHER|$(if ($d.Publisher) { $d.Publisher } else { '-' })"
        "SOURCE|winget ($Id)"
        "WEBSITE|$(if ($d.Homepage) { $d.Homepage } else { '-' })"
        "METHOD|winget install --id $Id --exact"
        "STATUS|$(if ($installed) { 'installed' } else { 'not installed' })")
    Write-LotusBlank
    if ($installed) { Write-LotusSuccess "$(if ($d.Name) { $d.Name } else { $Id }) is already installed"; return (St 0) }
    if (-not (Read-LotusConfirm "Install $(if ($d.Name) { $d.Name } else { $Id })?" 'n')) { return (St 0) }
    Install-LotusPkg $Id $d.Name
}

# Runs the installation in the open – winget's own output, questions and errors stay visible
function script:Install-LotusPkg {
    param([string]$Id, [string]$Name)
    $args_ = @('install', '--id', $Id, '--exact', '--source', 'winget')
    Write-LotusBlank
    Write-LotusInfo "Running: winget $($args_ -join ' ')"
    Write-LotusDim 'winget may ask about the license, and Windows about administrator rights. Lotus never sees a password.'
    Write-LotusBlank
    Write-LotusLog INFO install "winget install $Id"
    $rc = Invoke-LotusInTheOpen 'winget' $args_
    Write-LotusBlank
    if ($rc -eq 0) {
        Write-LotusSuccess "$(if ($Name) { $Name } else { $Id }) is installed"
        return (St 0)
    }
    Write-LotusError "Installation of $(if ($Name) { $Name } else { $Id }) failed" "winget's message is shown above (exit code $rc)." @("You can retry with: winget install --id $Id --exact")
    St 1
}
