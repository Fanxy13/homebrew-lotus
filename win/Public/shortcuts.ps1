# Your own commands: lotus shortcut add yt https://youtube.com → /yt – a port of lib/cmd/shortcuts.zsh. Stored in
# settings.zsh as LOTUS_SHORTCUTS[name]="type|target|on/off". Types: url (with {q} for search words), app, path (a
# folder or file), lotus (a Lotus command). Shell commands are deliberately not possible.

function script:Invoke-Lotusshortcuts {
    param([string]$Cmd, [string[]]$Rest)
    Import-LotusCommand web
    switch -CaseSensitive ($Cmd) {
        'run' { return Invoke-LotusShortcut $(if ($Rest.Count) { $Rest[0] } else { '' }) ([string[]]@($Rest | Select-Object -Skip 1)) }
        'shortcuts' { return Show-LotusShortcutsManage }
        'shortcut' {
            $sub = if ($Rest.Count) { $Rest[0] } else { '' }
            $more = [string[]]@($Rest | Select-Object -Skip 1)
            $first = if ($more.Count) { $more[0] } else { '' }
            switch -Regex ($sub) {
                '^add$' { return Add-LotusShortcut $more }
                '^edit$' { return Add-LotusShortcut $more -Edit }
                '^(rm|remove|delete)$' { return Remove-LotusShortcut $first }
                '^(on|enable)$' { return Set-LotusShortcutState $first 'on' }
                '^(off|disable)$' { return Set-LotusShortcutState $first 'off' }
                '^(list|)$' { return Show-LotusShortcutsList }
                default { Write-LotusError 'Unknown shortcut action' $sub @('Use: add, edit, rm, on, off, list'); return (St 1) }
            }
        }
    }
}

function script:Get-LotusTriggers { @(Read-LotusTsv 'commands' | ForEach-Object { if ($_.Count -gt 1 -and $_[1].StartsWith('/')) { $_[1] } }) }

# What a target is → @{ Type; Target }, or $null
function script:Get-LotusShortcutKind {
    param([string]$Text)
    if (ConvertTo-LotusUrl ($Text.Replace('{q}', 'x'))) {
        return [pscustomobject]@{ Type = 'url'; Target = $(if ($Text -match '^(?i)https?://') { $Text } else { "https://$Text" }) }
    }
    $p = if ($Text.StartsWith('~')) { (Get-LotusHome) + $Text.Substring(1) } else { $Text }
    if ($p -and (Test-Path -LiteralPath $p)) { return [pscustomobject]@{ Type = 'path'; Target = (Resolve-Path -LiteralPath $p).ProviderPath } }
    if ($Text.StartsWith('/') -and (Get-LotusTriggers) -ccontains ($Text -split ' ')[0]) { return [pscustomobject]@{ Type = 'lotus'; Target = $Text } }
    $found = Get-LotusInstalledApps
    if ($found.Code -eq 0) {
        foreach ($name in $found.Value.Keys) { if ($name -eq $Text) { return [pscustomobject]@{ Type = 'app'; Target = $name } } }
    }
    $null
}

function script:Add-LotusShortcut {
    param([string[]]$Words, [switch]$Edit)
    $name = if ($Words.Count) { $Words[0].TrimStart('/').ToLowerInvariant() } else { '' }
    $target = ($Words | Select-Object -Skip 1) -join ' '
    if (-not $name) {
        Write-LotusHeader 'Shortcuts' 'new shortcut'
        $name = ([string](Read-LotusInput 'Name (you will type /name)')).TrimStart('/').ToLowerInvariant()
    }
    if ($name -cnotmatch '^[a-z0-9][a-z0-9_-]{0,23}$') {
        Write-LotusError 'Invalid name' $name @('Use 1-24 lowercase letters, numbers, - or _')
        return (St 1)
    }
    if ((Get-LotusTriggers) -ccontains "/$name") { Write-LotusError "/$name is a Lotus command" '' @('Pick another name.'); return (St 1) }
    if ($Edit -and -not $script:Shortcuts.ContainsKey($name)) { Write-LotusError "No shortcut called /$name" '' @("Add it with: lotus shortcut add $name <target>"); return (St 1) }
    if (-not $Edit -and $script:Shortcuts.ContainsKey($name) -and -not (Read-LotusConfirm "/$name exists. Replace it?" 'n')) { return (St 0) }
    if (-not $target) {
        Write-LotusDim 'A link (https://… – {q} is replaced by search words), an app, a folder or a Lotus command like /weather Zurich'
        $target = [string](Read-LotusInput 'Target')
    }
    $kind = if ($target) { Get-LotusShortcutKind $target } else { $null }
    if (-not $kind) {
        Write-LotusError 'Lotus does not know what to open' $target @('Use a link, an installed app''s exact name, an existing folder or file, or a Lotus command.', 'Shell commands are not allowed in shortcuts.')
        return (St 1)
    }
    $script:Shortcuts[$name] = "$($kind.Type)|$($kind.Target)|on"
    Save-LotusSettings
    Write-LotusSuccess "/$name → $($kind.Target)  ($($kind.Type))"
    Write-LotusDim 'Works in new PowerShell windows right away, in this one at once'
    St 0
}

function script:Remove-LotusShortcut {
    param([string]$Name)
    $key = $Name.TrimStart('/').ToLowerInvariant()
    if (-not $script:Shortcuts.ContainsKey($key)) { Write-LotusError "No shortcut called /$key"; return (St 1) }
    if (-not (Read-LotusConfirm "Delete /$key?" 'n')) { return (St 0) }
    [void]$script:Shortcuts.Remove($key)
    Save-LotusSettings
    Write-LotusSuccess "/$key deleted"
    St 0
}

function script:Set-LotusShortcutState {
    param([string]$Name, [string]$State)
    $key = $Name.TrimStart('/').ToLowerInvariant()
    if (-not $script:Shortcuts.ContainsKey($key)) { Write-LotusError "No shortcut called /$key"; return (St 1) }
    $v = $script:Shortcuts[$key]
    $script:Shortcuts[$key] = $v.Substring(0, $v.LastIndexOf('|')) + "|$State"
    Save-LotusSettings
    Write-LotusSuccess "/$key is $State"
    St 0
}

function script:Show-LotusShortcutsList {
    Write-LotusHeader 'Shortcuts' "$($script:Shortcuts.Count) saved"
    if (-not $script:Shortcuts.Count) {
        Write-LotusDim 'None yet. Example: lotus shortcut add yt https://youtube.com'
        Write-LotusBlank
        return (St 0)
    }
    foreach ($kv in $script:Shortcuts.GetEnumerator()) {
        $f = $kv.Value -split '\|'
        $col = if ($f[2] -eq 'on') { E key } else { E dim }
        Write-LotusLine "  $col$(PadR "/$($kv.Key)" 14)$($script:R) $(PadR $f[0] 6) $($f[1])$(if ($f[2] -ne 'on') { '  (off)' })"
    }
    Write-LotusBlank
    St 0
}

function script:Show-LotusShortcutsManage {
    while ($true) {
        Write-LotusRaw "$([char]27)[H$([char]27)[2J"
        Show-LotusShortcutsList | Out-Null
        $names = @($script:Shortcuts.Keys)
        $pick = Read-LotusChoice 'Manage' (@('Add a shortcut') + @($names | ForEach-Object { "/$_" }) + @('Done'))
        if ($null -eq $pick -or $pick -eq $names.Count + 2) { return (St 0) }
        if ($pick -eq 1) { Add-LotusShortcut @() | Out-Null; Write-LotusDim 'Press a key'; [void](Read-LotusKey); continue }
        $name = $names[$pick - 2]
        $state = ($script:Shortcuts[$name] -split '\|')[-1]
        $act = Read-LotusChoice "/$name" @('Run', 'Edit target', $(if ($state -eq 'on') { 'Disable' } else { 'Enable' }), 'Delete', 'Back')
        switch ($act) {
            1 { return Invoke-LotusShortcut $name @() }
            2 { Add-LotusShortcut @($name) -Edit | Out-Null }
            3 { Set-LotusShortcutState $name $(if ($state -eq 'on') { 'off' } else { 'on' }) | Out-Null }
            4 { Remove-LotusShortcut $name | Out-Null }
            default { continue }
        }
        Write-LotusDim 'Press a key'; [void](Read-LotusKey)
    }
}

function script:Invoke-LotusShortcut {
    param([string]$Name, [string[]]$Words)
    $key = $Name.TrimStart('/').ToLowerInvariant()
    if (-not $script:Shortcuts.ContainsKey($key)) {
        Import-LotusCommand help
        return Invoke-LotusSuggest $key $Words
    }
    $f = $script:Shortcuts[$key] -split '\|', 3
    if ($f[2] -eq 'off') { Write-LotusWarn "/$key is turned off – turn it on with: lotus shortcut on $key"; return (St 1) }
    switch ($f[0]) {
        'url' {
            $url = $f[1]
            if ($url.Contains('{q}')) { $url = $url.Replace('{q}', (ConvertTo-LotusUrlEncoded ($Words -join ' '))) }
            return Open-LotusUrl $url "/$key"
        }
        'app' {
            $found = Get-LotusInstalledApps
            if ($found.Code -eq 0 -and $found.Value.ContainsKey($f[1]) -and (Start-LotusApp $found.Value[$f[1]]) -eq 0) { Write-LotusInfo "Opening $($f[1])"; return (St 0) }
            Write-LotusError "Could not open $($f[1])"
            return (St 1)
        }
        'path' {
            if (Test-Path -LiteralPath $f[1]) { if ((Open-LotusTarget $f[1]) -eq 0) { Write-LotusInfo "Opening $(Format-LotusHomePath $f[1])"; return (St 0) } }
            Write-LotusError 'Not found' $f[1]
            return (St 1)
        }
        'lotus' {
            $parts = @($f[1] -split ' ' | Where-Object { $_ })
            foreach ($row in Read-LotusTsv 'commands') {
                if ($row.Count -gt 2 -and $row[1] -ceq $parts[0]) {
                    $argv = @(($row[2] -split ' ') + @($parts | Select-Object -Skip 1) + $Words | Where-Object { $_ -ne '' })
                    return Invoke-LotusDispatch $argv[0] ([string[]]@($argv | Select-Object -Skip 1))
                }
            }
            Write-LotusError "Unknown Lotus command in /$key" $f[1]
            return (St 1)
        }
    }
    St 1
}
