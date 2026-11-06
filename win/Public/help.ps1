# lotus help, cheatsheet, themes, suggestions for unknown commands – a port of lib/cmd/help.zsh

function script:Invoke-Lotushelp {
    param([string]$Cmd, [string[]]$Rest)
    switch -CaseSensitive ($Cmd) {
        'themes' {
            $sub = if ($Rest.Count) { $Rest[0] } else { '' }
            $more = [string[]]@($Rest | Select-Object -Skip 1)
            if ($sub -ceq 'add') { return Add-LotusTheme $more }
            if ($sub -cin 'remove', 'rm', 'delete') { return Remove-LotusTheme $more }
            return Show-LotusThemesPreview
        }
        'suggest' { return Invoke-LotusSuggest $(if ($Rest.Count) { $Rest[0] } else { '' }) ([string[]]@($Rest | Select-Object -Skip 1)) }
        { $_ -cin 'help', '-h', '--help' } {
            # with a pet: it asks what you need (/help all shows every command)
            $all = $Rest.Count -and $Rest[0] -cin 'all', '--all', '-a'
            $pets = Join-Path $script:Paths.Conf 'pets.tsv'
            if (-not $all -and (Test-LotusOn $script:S['LOTUS_PET_HELP']) -and (Test-LotusFeature 'pets') -and (Test-Path -LiteralPath $pets) -and
                (Get-Item -LiteralPath $pets).Length -gt 0 -and (Test-LotusOutTty) -and (Test-LotusTty)) {
                Import-LotusCommand pets
                Import-LotusLangGroup pets
                $r = Invoke-LotusPetHelp
                if ($r) { return (St 0) }
            }
            return Show-LotusCheatsheet
        }
        default { return Show-LotusCheatsheet }
    }
}

# Is the command of a commands.tsv row part of a feature that is on?
function script:Test-LotusCommandOn {
    param([string]$Command)
    Test-LotusFeature (Get-LotusFeatureOf (($Command -split ' ')[0]))
}

# Commands of the AI that are the AI program's – the terminal app, models on this computer, the web chat: not on Windows yet
$script:AiNotHere = @('ai local', 'ai local restart', 'ai server', 'ai server port', 'ai stats')

# Words of data/commands.tsv (written for macOS and Linux) in the words of Windows, in this order
$script:CommandWordsHere = @(
    @('Search Homebrew formulae and casks', 'Search winget for apps and tools'), @('Search Homebrew, explicitly', 'Search winget, explicitly'),
    @('Homebrew', 'winget'), @("macOS' caffeinate", "Windows' SetThreadExecutionState"), @('from the Finder', 'from File Explorer'))

# The rows of data/commands.tsv this system has, in its words: on Windows the commands of what is not here yet are left
# out, and "Homebrew" is winget
function script:Get-LotusCommandsHere {
    foreach ($c in Get-LotusCommands) {
        if ($IsWindows -or $env:LOTUS_AS_WINDOWS -eq '1') {
            $first = ($c.Command -split ' ')[0]
            $module = $null
            if ($script:Modules.TryGetValue($first, [ref]$module) -and -not (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot "Public/$module.ps1"))) { continue }
            if ($script:AiNotHere -ccontains $c.Command) { continue }
            foreach ($p in $script:CommandWordsHere) {
                $c.Category = $c.Category.Replace($p[0], $p[1]); $c.Description = $c.Description.Replace($p[0], $p[1])
            }
        }
        $c.Description = Convert-LotusHere $c.Description
        $c
    }
}

function script:Show-LotusCheatsheet {
    $d = E dim; $r = $script:R; $k = E key
    $wide = (Get-LotusColumns) -ge 118
    $off = @(foreach ($id in $script:FeatureIds) { if (-not (Test-LotusFeature $id)) { Get-LotusFeatureLabel $id } })
    Write-LotusHeader 'Cheatsheet' 'every command, with an example'
    $last = $null
    foreach ($c in Get-LotusCommandsHere) {
        if ($c.Hidden -or -not (Test-LotusCommandOn $c.Command)) { continue }
        if ($c.Category -cne $last) {
            if ($null -ne $last) { Write-LotusLine '' }
            Write-LotusCategory $c.Category
            $last = $c.Category
        }
        if ($wide) { Write-LotusLine "    $k$(PadR $c.Usage 34)$r $(PadR $c.Description 52) $d$($c.Example)$r" }
        else {
            Write-LotusLine "    $k$($c.Usage)$r"
            Write-LotusLine "      $($c.Description)  $d$($c.Example)$r"
        }
    }
    if ($script:Shortcuts.Count) {
        Write-LotusLine ''
        Write-LotusCategory 'Your shortcuts' "$($script:Shortcuts.Count)"
        foreach ($kv in $script:Shortcuts.GetEnumerator()) {
            $target = ($kv.Value -split '\|')[1]
            Write-LotusLine "    $k$(PadR "/$($kv.Key)" 34)$r $d$target$r"
        }
    }
    Write-LotusLine ''
    if ($off.Count) { Write-LotusDim "Turned off: $($off -join ', ') – lotus features"; Write-LotusLine '' }
    Write-LotusDim "Typos are fine: Lotus suggests the closest command. Website: $($script:P['website'])"
    Write-LotusLine ''
    St 0
}

# An unknown command: an error with the closest commands, and the offer to run the best one (lotus_cmd_suggest)
function script:Invoke-LotusSuggest {
    param([string]$Typed, [string[]]$Rest)
    $word = $Typed.TrimStart('/')
    $targetOf = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($c in Get-LotusCommandsHere) {
        if ($c.Hidden -or -not (Test-LotusCommandOn $c.Command)) { continue }
        if ($c.Trigger -cne '-') { $name = $c.Trigger }
        else {
            $name = ($c.Usage -split ' ')[0]
            if ($name -cin 'lotus', '/lotus') { $name = '/lotus ' + (($c.Usage -split ' ', 2)[1] -split ' ')[0] }
        }
        if ($targetOf.ContainsKey($name)) { continue }
        $targetOf[$name] = $c.Command
        $names.Add($name)
    }
    foreach ($kv in $script:Shortcuts.GetEnumerator()) { $targetOf["/$($kv.Key)"] = "run $($kv.Key)"; $names.Add("/$($kv.Key)") }
    # the typed word is compared with the command word (without "/" or "/lotus ")
    $words = [System.Collections.Generic.List[string]]::new()
    $nameOf = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($n in $names) {
        $w = $n
        if ($w.StartsWith('/lotus ')) { $w = $w.Substring(7) }
        $w = $w.TrimStart('/')
        if (-not $nameOf.ContainsKey($w)) { $words.Add($w) }
        $nameOf[$w] = $n
    }
    $rank = Get-LotusRank $word 50 $words.ToArray()
    $best = if ($rank.Scores.Count) { $rank.Scores[0] } else { 0 }
    Write-LotusError 'Command not found' "/$word"
    if (Get-Command Invoke-LotusPetReact -ErrorAction SilentlyContinue) { Invoke-LotusPetReact typo }
    if (-not $rank.Names.Count) {
        Write-LotusDim 'Type /lotus cheatsheet to see every command.'
        Write-LotusLine ''
        return (St 1)
    }
    $top = $nameOf[$rank.Names[0]]
    Write-LotusLine '  Did you mean:'
    foreach ($h in ($rank.Names | Select-Object -First 3)) { Write-LotusLine "    $(E key)$($nameOf[$h])$($script:R)" }
    Write-LotusLine ''
    if ((Test-LotusTty) -and (Read-LotusConfirm "Run $top$(if ($Rest.Count) { ' ' + ($Rest -join ' ') }) now?" $(if ($best -ge 60) { 'y' } else { 'n' }))) {
        Write-LotusLine ''
        $argv = @(($targetOf[$top] -split ' ') + $Rest)
        Initialize-Lotus
        return Invoke-LotusDispatch $argv[0] ([string[]]@($argv | Select-Object -Skip 1))
    }
    St 1
}

# A sample of a theme's colors: four squares (_lotus_swatch)
function script:Get-LotusSwatch {
    param([string]$Name)
    $rgb = $script:Themes[$Name]
    ((0..3 | ForEach-Object { "$([char]27)[$(ConvertTo-LotusSgr $rgb[$_])m■■" }) -join ' ') + "$([char]27)[0m"
}

function script:Show-LotusThemesPreview {
    $was = $script:S['LOTUS_THEME']
    $names = @($script:ThemeNames)
    Write-LotusHeader 'Themes' "$($names.Count) themes"
    $labels = foreach ($n in $names) { "$(PadR $script:ThemeLabels[$n] 10) $(Get-LotusSwatch $n)$(if ($n -ceq $was) { '  (current)' })" }
    if (-not (Test-LotusTty)) {
        # no keyboard to choose with: the list, and how to set one
        foreach ($l in $labels) { Write-LotusLine "    $l" }
        Write-LotusBlank
        Write-LotusDim 'Choose one in /settings, or: lotus settings set LOTUS_THEME ocean'
        return (St 0)
    }
    $pick = Read-LotusChoice 'Apply a theme' @($labels)
    if ($null -ne $pick) {
        $script:S['LOTUS_THEME'] = $names[$pick - 1]
        Save-LotusSettings
        Initialize-LotusColors
        Write-LotusSuccess "Theme: $($script:ThemeLabels[$script:S['LOTUS_THEME']])"
    }
    St 0
}

# Your own theme, made in the Theme Studio on the website (lotus themes add <name> <8 colors>) – kept in themes.tsv
# next to the settings and used at once. Colors as ff8800, #ff8800 or 255;136;0.
function script:Add-LotusTheme {
    param([string[]]$Words)
    $label = if ($Words.Count) { $Words[0].Trim() } else { '' }
    $colors = @($Words | Select-Object -Skip 1)
    if (-not $label -or $colors.Count -ne 8) {
        Write-LotusError 'A theme needs a name and 8 colors' 'lotus themes add <name> <logo> <key> <accent> <key2> <salute> <border> <dim> <music>' @("Make one with a live preview in the Theme Studio: $($script:P['website'])studio.html")
        return (St 1)
    }
    if ($label -match '[\p{Cc}|]' -or $label.Length -gt 24) {
        Write-LotusError 'That name does not work for a theme' $label @('Up to 24 letters, digits and spaces.')
        return (St 1)
    }
    $rgb = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $colors) {
        $c = $c.TrimStart('#')
        if ($c -match '^[0-9A-Fa-f]{6}$') { $rgb.Add("$([Convert]::ToInt32($c.Substring(0, 2), 16));$([Convert]::ToInt32($c.Substring(2, 2), 16));$([Convert]::ToInt32($c.Substring(4, 2), 16))") }
        elseif ($c -match '^(\d{1,3})[;,](\d{1,3})[;,](\d{1,3})$' -and [int]$Matches[1] -le 255 -and [int]$Matches[2] -le 255 -and [int]$Matches[3] -le 255) { $rgb.Add("$([int]$Matches[1]);$([int]$Matches[2]);$([int]$Matches[3])") }
        else { Write-LotusError 'That is not a color' $c @('Colors look like ff8800 or 255;136;0.'); return (St 1) }
    }
    $id = ($label.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $id) { $id = 'own' }
    $builtin = @(Read-LotusTsv 'themes' | ForEach-Object { $_[0] })
    if ($builtin -ccontains $id) {
        Write-LotusError "$label is a built-in theme" '' @('Give yours another name.')
        return (St 1)
    }
    $file = Join-Path $script:Paths.Conf 'themes.tsv'
    $out = [System.Text.StringBuilder]::new()
    foreach ($line in ([string](Read-LotusFile $file)) -split "`n") { if ($line -and ($line -split "`t")[0] -cne $id) { [void]$out.Append("$line`n") } }
    [void]$out.Append("$id`t$label`t$($rgb -join "`t")`n")
    Write-LotusFile $file $out.ToString()
    $script:S['LOTUS_THEME'] = $id
    Save-LotusSettings
    Initialize-LotusColors
    Write-LotusSuccess "Theme: $label  $(Get-LotusSwatch $id)"
    Write-LotusDim "Change it again in /settings → Theme · lotus themes remove $(ConvertTo-LotusPsArg $label) takes it out"
    Write-LotusLog INFO themes "Own theme $id added"
    St 0
}

function script:Remove-LotusTheme {
    param([string[]]$Words)
    $name = $Words -join ' '
    $id = ($name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    $file = Join-Path $script:Paths.Conf 'themes.tsv'
    $out = [System.Text.StringBuilder]::new()
    $found = $null
    $mine = @()
    foreach ($line in ([string](Read-LotusFile $file)) -split "`n") {
        if (-not $line) { continue }
        $f = $line -split "`t"
        $mine += $f[1]
        if ($f[0] -ceq $id) { $found = $f[1] } else { [void]$out.Append("$line`n") }
    }
    if (-not $found) {
        Write-LotusError "No own theme called $(if ($name) { $name } else { 'that' })" '' @("Your themes: $($mine -join ', ')")
        return (St 1)
    }
    Write-LotusFile $file $out.ToString()
    if ($script:S['LOTUS_THEME'] -ceq $id) { $script:S['LOTUS_THEME'] = 'matcha' }
    Save-LotusSettings
    Initialize-LotusColors
    Write-LotusSuccess "Removed: $found"
    Write-LotusLog INFO themes "Own theme $id removed"
    St 0
}
