# The interface texts: the same files as the zsh engine (lib/lang/<lang>.zsh, lib/lang/<group>.<lang>.zsh), read as data.
# English first, then the chosen language on top. The texts were written on a Mac: on Windows "this Mac" becomes
# "this PC" and "Finder" becomes File Explorer, in the language the texts are in.

$script:L = @{}
$script:LangGroups = [System.Collections.Generic.List[string]]::new()
$script:LangFileCache = @{}

# The words of a language file → hashtable (cached per file and modification time, for the whole session)
function Read-LotusLangFile {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { return @{} }
    $stamp = "$($item.LastWriteTimeUtc.Ticks) $($item.Length)"
    $hit = $script:LangFileCache[$Path]
    if ($hit -and $hit.Stamp -eq $stamp) { return $hit.Map }
    $words = Get-LotusZshArray -Text (Read-LotusFile $Path) -Name 'LOTUS_L' -All
    $map = @{}
    if ($words) { for ($i = 0; $i + 1 -lt $words.Count; $i += 2) { $map[$words[$i]] = $words[$i + 1] } }
    $script:LangFileCache[$Path] = @{ Stamp = $stamp; Map = $map }
    $map
}

function Add-LotusLangFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $map = Read-LotusLangFile $Path
    foreach ($k in $map.Keys) { $script:L[$k] = $map[$k] }
}

# What this system calls the computer and the file manager (lib/platform.zsh has the Linux words)
function Get-LotusHereWords {
    if ($IsWindows) { return @{ This = 'this PC'; The = 'the PC'; Your = 'your PC'; Files = 'File Explorer' } }
    if ($IsMacOS) { return $null }
    @{ This = 'this computer'; The = 'the computer'; Your = 'your computer'; Files = 'the file manager' }
}

# The replacements for one language, in the order zsh makes them (_lotus_lang_here in lib/core.zsh)
function Get-LotusHerePairs {
    param([string]$Lang)
    $w = Get-LotusHereWords
    if (-not $w) { return @() }
    if ($IsWindows) {
        switch ($Lang) {
            'de' { return @(@('diesem Mac', 'diesem PC'), @('diesen Mac', 'diesen PC'), @('deinem Mac', 'deinem PC'), @('Dein Mac', 'Dein PC'), @('dein Mac', 'dein PC'),
                    @('deinen Mac', 'deinen PC'), @('dem Mac', 'dem PC'), @('der Mac', 'der PC'), @('den Mac', 'den PC'), @('Am Mac', 'Am PC'), @('Finder', 'Explorer')) }
            'fr' { return @(@('ce Mac', 'ce PC'), @('ton Mac', 'ton PC'), @('votre Mac', 'votre PC'), @('le Mac', 'le PC'), @('du Mac', 'du PC'), @('Finder', "l’Explorateur de fichiers")) }
            'es' { return @(@('este Mac', 'este PC'), @('tu Mac', 'tu PC'), @('el Mac', 'el PC'), @('del Mac', 'del PC'), @('en el Finder', 'en el Explorador de archivos'), @('Finder', 'Explorador de archivos')) }
        }
    } else {
        switch ($Lang) {
            'de' { return @(@('diesem Mac', 'diesem Computer'), @('diesen Mac', 'diesen Computer'), @('deinem Mac', 'deinem Computer'), @('Dein Mac', 'Dein Computer'), @('dein Mac', 'dein Computer'),
                    @('deinen Mac', 'deinen Computer'), @('dem Mac', 'dem Computer'), @('der Mac', 'der Computer'), @('den Mac', 'den Computer'), @('Am Mac', 'Am Computer'), @('Finder', 'Dateimanager')) }
            'fr' { return @(@('ce Mac', 'cet ordinateur'), @('ton Mac', 'ton ordinateur'), @('votre Mac', 'votre ordinateur'), @('le Mac', "l’ordinateur"), @('du Mac', "de l’ordinateur"), @('Finder', 'le gestionnaire de fichiers')) }
            'es' { return @(@('este Mac', 'este ordenador'), @('tu Mac', 'tu ordenador'), @('el Mac', 'el ordenador'), @('del Mac', 'del ordenador'), @('en el Finder', 'en el gestor de archivos'), @('Finder', 'gestor de archivos')) }
        }
    }
    @(@('this Mac', $w.This), @('your Mac', $w.Your), @('the Mac', $w.The), @('Finder', $w.Files))
}

function Convert-LotusLangHere {
    $pairs = Get-LotusHerePairs $script:S['LOTUS_LANG']
    if (-not $pairs.Count) { return }
    foreach ($k in @($script:L.Keys)) {
        $v = $script:L[$k]
        # (and each at the start of a sentence: "Your Mac stays awake", "Ton Mac", "Tu Mac")
        foreach ($p in $pairs) { $v = $v.Replace($p[0], $p[1]).Replace((Get-LotusCapital $p[0]), (Get-LotusCapital $p[1])) }
        $script:L[$k] = $v
    }
}
function Get-LotusCapital { param([string]$Text) if ($Text) { $Text.Substring(0, 1).ToUpperInvariant() + $Text.Substring(1) } else { $Text } }

# An English text written in the code ("this Mac", "Finder") in this system's words (_ui_here in lib/ui.zsh)
function Convert-LotusHere {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $w = Get-LotusHereWords
    if (-not $w -or -not $Text) { return [string]$Text }
    $Text = $Text.Replace('this Mac', $w.This).Replace('your Mac', $w.Your).Replace('the Mac', $w.The).Replace('Finder', $w.Files)
    $Text.Replace('This Mac', (Get-LotusCapital $w.This)).Replace('Your Mac', (Get-LotusCapital $w.Your)).Replace('The Mac', (Get-LotusCapital $w.The))
}

# English first, then the language of the settings on top
function Import-LotusLang {
    $script:L = @{}
    $script:LangGroups = [System.Collections.Generic.List[string]]::new()
    $dir = Join-Path (Get-LotusRoot) 'lib/lang'
    Add-LotusLangFile (Join-Path $dir 'en.zsh')
    $lang = $script:S['LOTUS_LANG']
    if ($lang -and $lang -ne 'en' -and $lang -match '^[a-z]{2}$') { Add-LotusLangFile (Join-Path $dir "$lang.zsh") }
    Convert-LotusLangHere
}

# Texts of a bigger screen (setup, bg, log, mc, pets), loaded when it opens:  Import-LotusLangGroup pets
function Import-LotusLangGroup {
    param([Parameter(Mandatory)][string]$Group)
    if ($script:LangGroups.Contains($Group)) { return }
    $script:LangGroups.Add($Group)
    $dir = Join-Path (Get-LotusRoot) 'lib/lang'
    Add-LotusLangFile (Join-Path $dir "$Group.en.zsh")
    $lang = $script:S['LOTUS_LANG']
    if ($lang -and $lang -ne 'en' -and $lang -match '^[a-z]{2}$') { Add-LotusLangFile (Join-Path $dir "$Group.$lang.zsh") }
    Convert-LotusLangHere
}

# One text: LOTUS_L[key], or the default when it is missing or empty (zsh: ${LOTUS_L[key]:-default})
function T {
    param([Parameter(Mandatory)][string]$Key, [AllowEmptyString()][string]$Default = '')
    $v = $script:L[$Key]
    if ([string]::IsNullOrEmpty($v)) { $Default } else { $v }
}
