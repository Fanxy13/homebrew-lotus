# /np /play /pause /skip /back /repeat /mute /vu /vd – a port of lib/cmd/audio.zsh. What plays comes from fastfetch
# (Windows' media controls); the keys are the media keys every such player answers, the volume is Core Audio's.

function script:Invoke-Lotusaudio {
    param([string]$Cmd, [string[]]$Rest)
    $action = if ($Rest.Count) { $Rest[0] } else { 'now' }
    $np = Get-LotusMediaState
    switch -Regex ($action) {
        '^now$' { return Show-LotusNowPlayingCard $np }
        '^(play|pause|next|previous)$' { return Invoke-LotusTransport $action $np }
        '^repeat$' { return Invoke-LotusRepeat $np }
        '^mute$' { return Invoke-LotusMute }
        '^(up|down)$' { return Invoke-LotusVolumeStep $action }
        default { Write-LotusError "Unknown: $action" '' @('/np /play /pause /skip /back /repeat /mute /vu /vd'); return (St 2) }
    }
}

# What is playing right now → @{ Title; Artist; Album; Status; Player; Id; Pos; Len } (milliseconds), or $null
function script:Get-LotusMediaState {
    $ff = Get-LotusFastfetch
    if (-not $ff) { return $null }
    $json = Invoke-LotusNativeText $ff @('--logo', 'none', '-s', 'media', '--format', 'json')
    if ($json -notmatch '"song"') { return $null }
    try { $r = (@($json | ConvertFrom-Json)[0]).result } catch { return $null }
    if (-not $r.song.name) { return $null }
    [pscustomobject]@{
        Title = [string]$r.song.name; Artist = [string]$r.song.artist; Album = [string]$r.song.album; Status = [string]$r.song.status
        Player = [string]$r.player.name; Id = [string]$r.player.id; Pos = [double]$(if ($null -ne $r.song.position) { $r.song.position } else { 0 }); Len = [double]$(if ($null -ne $r.song.length) { $r.song.length } else { 0 })
    }
}

function script:Show-LotusNowPlayingCard {
    param($Np)
    if (-not $Np) {
        Write-LotusHeader 'Now playing'
        Write-LotusDim 'Nothing is playing right now.'
        Write-LotusBlank
        return (St 0)
    }
    $pos = [Math]::Truncate($Np.Pos / 1000); $len = [Math]::Truncate($Np.Len / 1000)
    $pct = if ($len -gt 0) { [Math]::Truncate($pos * 100 / $len) } else { 0 }
    $n = [Math]::Truncate($pct / 10)
    $bar = "[$([string]::new([char]0x25A0, $n))$([string]::new([char]0x00B7, 10 - $n))]"
    Write-LotusHeader 'Now playing' $Np.Player
    Write-LotusCard $Np.Status @("TITLE|$($Np.Title)", "ARTIST|$(if ($Np.Artist) { $Np.Artist } else { '-' })", "ALBUM|$(if ($Np.Album) { $Np.Album } else { '-' })",
        ('TIME|{0} {1}:{2:00} / {3}:{4:00}' -f $bar, [Math]::Truncate($pos / 60), ($pos % 60), [Math]::Truncate($len / 60), ($len % 60)))
    Write-LotusBlank
    St 0
}

function script:Invoke-LotusTransport {
    param([string]$Action, $Np)
    $label = switch ($Action) { 'next' { 'Next track' } 'previous' { 'Previous track' } 'play' { 'Play' } 'pause' { 'Pause' } }
    if (-not $Np) {
        Write-LotusWarn 'Nothing is playing right now'
        if ($Action -ne 'play') { return (St 1) }
    }
    $r = Invoke-LotusMedia $Action $(if ($Np) { $Np.Status } else { '' }) $(if ($Np) { $Np.Player } else { '' })
    switch ($r.Code) {
        0 { Write-LotusInfo "$label  $($r.Value)" }
        2 { Write-LotusError "This system cannot $Action here" "$(if ($Np -and $Np.Player) { $Np.Player } else { 'The player' }) cannot be controlled from the terminal."; return (St 1) }
        default { $m = @($r.Msg) + @('', '', ''); Write-LotusError $(if ($m[0]) { $m[0] } else { 'The player did not respond' }) $m[1] @($m[2]); return (St 1) }
    }
    if ($Action -in 'next', 'previous') {
        Start-Sleep -Milliseconds 600
        $after = Get-LotusMediaState
        if ($after) { Write-LotusDim "  ♫ $($after.Title)$(if ($after.Artist) { " — $($after.Artist)" })" }
    }
    St 0
}

function script:Invoke-LotusRepeat {
    param($Np)
    $r = Invoke-LotusMedia 'repeat' '' $(if ($Np) { $Np.Player } else { '' })
    if ($r.Code -eq 0) { Write-LotusInfo $r.Value; return (St 0) }
    Write-LotusError 'This player does not let Lotus change its repeat mode' "$(if ($Np -and $Np.Player) { $Np.Player } else { 'Nothing' }) is playing right now." @("Players that offer repeat in Windows’ media controls can be switched (the Media Player of Windows does).")
    St 1
}

function script:Invoke-LotusMute {
    $r = Invoke-LotusVolume 'mute'
    if ($r.Code -ne 0) { Write-LotusError 'The volume cannot be changed from here' '' @($(if (-not $IsWindows) { 'This needs Windows (Core Audio).' } else { 'Windows has no default output device.' })); return (St 1) }
    if ($r.Value -eq 1) { Write-LotusInfo 'Muted' } else { Write-LotusInfo 'Sound on' }
    St 0
}

function script:Invoke-LotusVolumeStep {
    param([string]$Direction)
    $r = Invoke-LotusVolume $Direction
    if ($r.Code -ne 0) { Write-LotusError 'The volume cannot be changed from here' '' @($(if (-not $IsWindows) { 'This needs Windows (Core Audio).' } else { 'Windows has no default output device.' })); return (St 1) }
    $vol = [int]$r.Value
    Write-LotusProgress 'Volume' $vol
    if ($vol -lt 100) { Write-LotusLine '' }
    St 0
}
