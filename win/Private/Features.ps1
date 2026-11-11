# Features: the parts of Lotus you can turn off (data/features.tsv, LOTUS_FEATURES_OFF) – a feature that is off has no
# command, no settings and downloads nothing; its commands explain how to turn it back on.

function Import-LotusFeatures {
    # $script:FeatureIds (in order), $script:FeatureRow[id] = fields, $script:FeatureOf[command] = id
    if ($script:FeatureIds) { return }
    $ids = [System.Collections.Generic.List[string]]::new()
    $script:FeatureRow = @{}
    $script:FeatureOf = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($f in Read-LotusTsv 'features') {
        $ids.Add($f[0])
        $script:FeatureRow[$f[0]] = $f
        if ($f.Count -gt 2) { foreach ($c in ($f[2] -split '\s+')) { if ($c) { $script:FeatureOf[$c] = $f[0] } } }
    }
    $script:FeatureIds = $ids.ToArray()
}

function Test-LotusFeature {
    param([Parameter(Mandatory)][string]$Id)
    " $($script:S['LOTUS_FEATURES_OFF']) " -notlike "* $Id *"
}

# The feature a lotus subcommand belongs to (core when none)
function Get-LotusFeatureOf {
    param([string]$Command)
    Import-LotusFeatures
    $id = $null
    if ($script:FeatureOf.TryGetValue($Command, [ref]$id)) { $id } else { 'core' }
}

# The name of a feature in the interface language
function Get-LotusFeatureLabel {
    param([Parameter(Mandatory)][string]$Id)
    Import-LotusFeatures
    $row = $script:FeatureRow[$Id]
    # the feature of /install and /brew installs with winget on Windows
    if ($IsWindows -and $Id -ceq 'homebrew') { return 'winget' }
    T "feat_$Id" $(if ($row) { $row[1] } else { $Id })
}

function Set-LotusFeature {
    param([Parameter(Mandatory)][string]$Id, [bool]$On)
    $off = [System.Collections.Generic.List[string]]::new()
    foreach ($x in ([string]$script:S['LOTUS_FEATURES_OFF'] -split '\s+')) { if ($x -and $x -cne $Id -and -not $off.Contains($x)) { $off.Add($x) } }
    if (-not $On) { $off.Add($Id) }
    $arr = $off.ToArray()
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    $script:S['LOTUS_FEATURES_OFF'] = $arr -join ' '
    Write-LotusLog INFO features "$Id turned $(if ($On) { 'on' } else { 'off' })"
}
