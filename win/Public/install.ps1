# /install – the app catalog (data/apps.tsv) by category, a port of lib/cmd/install.zsh. On Windows the apps come from
# winget, by the id in the catalog's winget column (checked against winget by the CI); apps that are for macOS only
# have none and are left out. An app that is not in the catalog is looked for in winget itself.

$script:Categories = @('Browsers', 'Communication', 'Microsoft', 'Development', 'Media', 'Utilities', 'Games', 'Productivity', 'Free alternatives', 'Open-source software')

function script:Invoke-Lotusinstall {
    param([string]$Cmd, [string[]]$Rest)
    Import-LotusCommand brew
    if (-not (Test-LotusWinget)) { return (St 1) }
    $cat = Get-LotusCatalog
    if ($Rest.Count) { return Find-LotusCatalogApp ($Rest -join ' ') $cat }
    Show-LotusCatalog $cat
}

# The apps of data/apps.tsv that Windows can install → objects in catalog order
function script:Get-LotusCatalog {
    foreach ($f in Read-LotusTsv 'apps') {
        if ($f.Count -lt 6 -or -not $f[5] -or $f[5] -eq '-') { continue }
        [pscustomobject]@{ Name = $f[0]; Cask = $f[1]; Categories = @($f[2] -split ','); About = $f[4]; Winget = $f[5] }
    }
}

function script:Show-LotusCatalog {
    param($Catalog)
    $Catalog = @($Catalog)
    Write-LotusHeader 'Install' "$($Catalog.Count) apps · winget"
    $labels = foreach ($c in $script:Categories) { "$(PadR $c 22) $(@($Catalog | Where-Object { $_.Categories -contains $c }).Count) apps" }
    $pick = Read-LotusChoice 'Pick a category' (@('Search all apps') + @($labels))
    if ($null -eq $pick) { return (St 0) }
    if ($pick -eq 1) {
        $q = Read-LotusInput 'Search'
        if ($q) { return Find-LotusCatalogApp $q $Catalog }
        return (St 0)
    }
    $cat = $script:Categories[$pick - 2]
    $apps = @($Catalog | Where-Object { $_.Categories -contains $cat })
    $k = E key; $d = E dim; $r = $script:R
    Write-LotusRaw "$([char]27)[H$([char]27)[2J"
    Write-LotusHeader 'Install' "$cat  ·  $k●$r$d installed"
    Write-LotusStep 'Asking winget what is installed …'
    $installed = Get-LotusInstalledIds
    Write-LotusRaw "$([char]27)[1A$([char]27)[K"
    $rows = foreach ($a in $apps) {
        $mark = if ($installed.Contains($a.Winget)) { "$k●$r" } else { ' ' }
        "$mark $(PadR $a.Name 22)$r $d$(Cut $a.About ((Get-LotusColumns) - 40))$r"
    }
    $pick = Read-LotusChoice '' @($rows)
    if ($null -eq $pick) { return (St 0) }
    Show-LotusCatalogCard $apps[$pick - 1]
}

# The ids of what Windows has installed, as winget lists them (one call for the whole category)
function script:Get-LotusInstalledIds {
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in ConvertFrom-LotusWingetTable (Invoke-LotusWingetText @('list'))) { [void]$set.Add($row.Id) }
    , $set
}

function script:Find-LotusCatalogApp {
    param([string]$Query, $Catalog)
    $Catalog = @($Catalog)
    $name = Select-LotusPick $Query 'app' @($Catalog | ForEach-Object Name)
    if ($name) { return Show-LotusCatalogCard ($Catalog | Where-Object Name -eq $name | Select-Object -First 1) }
    # not in the catalog: winget itself
    Write-LotusInfo "`"$Query`" is not in the Lotus catalog – searching winget …"
    Invoke-LotusPkgSearch $Query
}

function script:Show-LotusCatalogCard {
    param($App)
    Show-LotusPkgCard $App.Winget $App.About
}
