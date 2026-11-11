# The files that Lotus shares between systems (data/*.tsv, lib/core.zsh) – the same ones the zsh engine reads.

function Read-LotusTsv {
    # the rows of data/<name>.tsv (or of a path), comments and empty lines left out → string arrays
    param([Parameter(Mandatory)][string]$Name, [switch]$Path)
    $file = if ($Path) { $Name } else { Join-Path (Get-LotusRoot) "data/$Name.tsv" }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return }
    foreach ($line in [System.IO.File]::ReadAllLines($file, [System.Text.UTF8Encoding]::new($false))) {
        if ($line.Length -eq 0 -or $line[0] -eq '#') { continue }
        , ($line.TrimEnd("`r") -split "`t")
    }
}

function Get-LotusVersion {
    # one source for the version: the line "typeset -g LOTUS_VERSION=x.y.z" of lib/core.zsh
    if ($script:LotusVersionCache) { return $script:LotusVersionCache }
    $core = Join-Path (Get-LotusRoot) 'lib/core.zsh'
    foreach ($line in [System.IO.File]::ReadLines($core)) {
        if ($line -match '^typeset -g LOTUS_VERSION=(\S+)') { $script:LotusVersionCache = $Matches[1]; return $Matches[1] }
    }
    throw "No LOTUS_VERSION in $core"
}

# Project constants (website, GitHub, …) from data/project.tsv → $script:P
function Import-LotusProject {
    if ($script:P) { return }
    $script:P = @{}
    foreach ($row in Read-LotusTsv 'project') { if ($row.Count -ge 2) { $script:P[$row[0]] = $row[1] } }
}

function Get-LotusCommands {
    # category, trigger, command, usage, description, example, hidden
    foreach ($row in Read-LotusTsv 'commands') {
        [pscustomobject]@{ Category = $row[0]; Trigger = $row[1]; Command = $row[2]; Usage = $row[3]; Description = $row[4]
            Example = $(if ($row.Count -gt 5) { $row[5] } else { '' }); Hidden = ($row.Count -gt 6 -and $row[6] -eq '1') }
    }
}

# The themes: data/themes.tsv, then your own ones in themes.tsv next to the settings (same columns – lotus themes add,
# the Theme Studio on the website). A theme of yours never replaces a built-in one.
#   name, label, then the colors as r;g;b: logo key accent key2 salute border dim music
function Get-LotusThemes {
    $roles = 'logo', 'key', 'accent', 'key2', 'salute', 'border', 'dim', 'music'
    $seen = @{}
    $files = @((Join-Path (Get-LotusRoot) 'data/themes.tsv'))
    if ($script:Paths) { $files += Join-Path $script:Paths.Conf 'themes.tsv' }
    $first = $true
    foreach ($file in $files) {
        foreach ($row in Read-LotusTsv $file -Path) {
            if ($row.Count -lt 10) { continue }
            if (-not $first -and $seen.ContainsKey($row[0])) { continue }
            $seen[$row[0]] = $true
            $colors = [ordered]@{}
            for ($i = 0; $i -lt $roles.Count; $i++) { $colors[$roles[$i]] = $row[2 + $i] }
            [pscustomobject]@{ Name = $row[0]; Label = $row[1]; Colors = $colors; Rgb = @($row[2..9]); Own = -not $first }
        }
        $first = $false
    }
}
