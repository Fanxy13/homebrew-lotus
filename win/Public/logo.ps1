# Logos: preview the built-in ones, paste your own ASCII art – a port of lib/cmd/logo.zsh
#   lotus logo · lotus logo import [--clipboard] · lotus logo reset · lotus logo preview <name>

$script:LogoMaxW = 80
$script:LogoMaxH = 40

function script:Invoke-Lotuslogo {
    param([string]$Cmd, [string[]]$Rest)
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    switch -CaseSensitive ($sub) {
        'import' { return Import-LotusLogo $(if ($Rest.Count -gt 1) { $Rest[1] } else { '' }) }
        'reset' { $script:S['LOTUS_LOGO'] = 'lotus'; Save-LotusSettings; Write-LotusSuccess 'Logo: Lotus Classic'; return (St 0) }
        'preview' { Show-LotusLogoPreview $(if ($Rest.Count -gt 1) { $Rest[1] } else { [string]$script:S['LOTUS_LOGO'] }); return (St 0) }
        default { return Select-LotusLogo }
    }
}

# A logo in the theme's color or its own (lib/art.zsh)
function script:Show-LotusLogoPreview {
    param([string]$Name)
    $p = Get-LotusLogoPainted $Name
    if (-not $p) { Write-LotusDim '(no logo)'; return }
    foreach ($line in ([string](Read-LotusFile $p.File)).TrimEnd("`n") -split "`n") { Write-LotusLine "  $line" }
}

function script:Select-LotusLogo {
    $names = @('lotus', 'minimal', 'large', 'terminal', 'apple', 'earth')
    if (Test-Path -LiteralPath (Join-Path $script:Paths.Conf 'logo.txt')) { $names += 'custom' }
    $names += 'none'
    $labels = foreach ($n in $names) { "$($script:LogoLabels[$n])$(if ($n -ceq $script:S['LOTUS_LOGO']) { '  (current)' })" }
    Write-LotusHeader 'Logos'
    Show-LotusLogoPreview 'minimal'
    Write-LotusBlank
    $pick = Read-LotusChoice 'Preview a logo' (@($labels) + @('Paste my own ASCII art'))
    if ($null -eq $pick) { return (St 0) }
    if ($pick -gt $names.Count) { return Import-LotusLogo '' }
    $name = $names[$pick - 1]
    Write-LotusRaw "$([char]27)[H$([char]27)[2J"
    Write-LotusHeader 'Logo' $script:LogoLabels[$name]
    Show-LotusLogoPreview $name
    Write-LotusBlank
    if (-not (Read-LotusConfirm "Use $($script:LogoLabels[$name])?" 'y')) { return (St 0) }
    $script:S['LOTUS_LOGO'] = $name
    Save-LotusSettings
    Write-LotusSuccess "Logo: $($script:LogoLabels[$name])"
    St 0
}

# Pasted art cleaned: no colors or control characters, tabs as spaces, no empty lines around it
function script:ConvertTo-LotusLogoLines {
    param([AllowEmptyString()][string]$Text)
    $t = [regex]::Replace($Text.Replace("`r`n", "`n"), "$([char]27)\[[0-9;?]*[a-zA-Z]", '').Replace("`t", '    ')
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $t -split "`n") { $out.Add(([regex]::Replace($line, '\p{Cc}', '')).TrimEnd()) }
    while ($out.Count -and -not $out[0].Trim()) { $out.RemoveAt(0) }
    while ($out.Count -and -not $out[$out.Count - 1].Trim()) { $out.RemoveAt($out.Count - 1) }
    , $out.ToArray()
}

function script:Import-LotusLogo {
    param([string]$From)
    Write-LotusHeader 'Logo' 'your own ASCII art'
    $text = ''
    if ($From -eq '--clipboard') {
        $clip = Get-LotusClipboardText
        if ($clip.Code -eq 0) { $text = [string]$clip.Value }
    } else {
        Write-LotusText 'Paste your ASCII art, then type a single . on its own line (or press Ctrl-Z, Enter).'
        Write-LotusDim 'Tip: the Lotus website has an ASCII art page with a prompt for AI tools.'
        Write-LotusBlank
        if (-not (Test-LotusTty)) { Write-LotusError 'Nothing to import' '' @('Without a keyboard: lotus logo import --clipboard'); return (St 1) }
        $sb = [System.Text.StringBuilder]::new()
        while ($true) {
            $line = [Console]::ReadLine()
            if ($null -eq $line -or $line -ceq '.') { break }
            [void]$sb.Append("$line`n")
        }
        $text = $sb.ToString()
    }
    $art = ConvertTo-LotusLogoLines $text
    if (-not $art.Count) { Write-LotusError 'Nothing to import' '' @('Copy ASCII art first or paste it here.'); return (St 1) }
    $w = ($art | Measure-Object -Property Length -Maximum).Maximum
    if ($w -gt $script:LogoMaxW -or $art.Count -gt $script:LogoMaxH) {
        Write-LotusError 'That logo is too big' "$w × $($art.Count) characters" @("Lotus logos can be up to $($script:LogoMaxW) wide and $($script:LogoMaxH) lines tall.")
        return (St 1)
    }
    Write-LotusBlank
    foreach ($line in $art) { Write-LotusLine "  $(E '1')$(E logo)$line$($script:R)" }
    Write-LotusBlank
    if (-not (Read-LotusConfirm 'Use this logo?' 'y')) { return (St 0) }
    Write-LotusFile (Join-Path $script:Paths.Conf 'logo.txt') ((($art | ForEach-Object { $_.Replace('$', '$$') }) -join "`n") + "`n")
    $script:S['LOTUS_LOGO'] = 'custom'
    Save-LotusSettings
    Write-LotusSuccess "Saved as your logo ($w × $($art.Count))"
    St 0
}
