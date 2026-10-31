# The files that Lotus shares between systems (data/*.tsv, lib/core.zsh) – the same ones the zsh engine reads.

function Read-LotusTsv {
    param([Parameter(Mandatory)][string]$Name)
    $path = Join-Path (Get-LotusRoot) "data/$Name.tsv"
    foreach ($line in Get-Content -LiteralPath $path -Encoding utf8) {
        if ($line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
        , ($line -split "`t")
    }
}

function Get-LotusVersion {
    # one source for the version: the line "typeset -g LOTUS_VERSION=x.y.z" of lib/core.zsh
    $core = Join-Path (Get-LotusRoot) 'lib/core.zsh'
    foreach ($line in Get-Content -LiteralPath $core -Encoding utf8) {
        if ($line -match '^typeset -g LOTUS_VERSION=(\S+)') { return $Matches[1] }
    }
    throw "No LOTUS_VERSION in $core"
}

function Get-LotusThemes {
    # name, label, then the colors as r;g;b: logo key accent key2 salute border dim music
    $roles = 'logo', 'key', 'accent', 'key2', 'salute', 'border', 'dim', 'music'
    foreach ($row in Read-LotusTsv 'themes') {
        $colors = [ordered]@{}
        for ($i = 0; $i -lt $roles.Count; $i++) { $colors[$roles[$i]] = $row[2 + $i] }
        [pscustomobject]@{ Name = $row[0]; Label = $row[1]; Colors = $colors }
    }
}

function Get-LotusCommands {
    # category, trigger, command, usage, description, example, hidden
    foreach ($row in Read-LotusTsv 'commands') {
        [pscustomobject]@{ Category = $row[0]; Trigger = $row[1]; Command = $row[2]; Usage = $row[3]; Description = $row[4] }
    }
}
