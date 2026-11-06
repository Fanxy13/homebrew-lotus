# /app and "open <name>": an installed app by its name, typos included – a port of lib/cmd/app.zsh. The apps are the
# ones of the Start menu (the Applications folder Get-StartApps lists: Store apps and the others).

function script:Invoke-Lotusapp {
    param([string]$Cmd, [string[]]$Rest)
    $query = ($Rest -join ' ').Trim()
    if (-not $query) {
        Write-LotusError 'Which app?' '' @('Example: /app Spotify')
        return (St 1)
    }
    $found = Get-LotusInstalledApps
    $apps = $found.Value
    if ($found.Code -eq 2) {
        Write-LotusError 'Lotus cannot list the apps of this system' '' @('/app knows the apps of the Start menu on Windows.')
        return (St 1)
    }
    $name = Select-LotusPick $query 'app' @($apps.Keys)
    if (-not $name) {
        Write-LotusError "No app found for `"$query`"" '' @("Install new apps with: /install $query")
        return (St 1)
    }
    if ((Start-LotusApp $apps[$name]) -eq 0) {
        Write-LotusInfo "Opening $name"
        return (St 0)
    }
    Write-LotusError "Could not open $name" $apps[$name]
    St 1
}
