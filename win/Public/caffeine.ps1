# lotus caffeine – keep the computer awake for a while, a port of lib/cmd/caffeine.zsh. On Windows a hidden PowerShell
# holds SetThreadExecutionState (system and display required) and ends by itself when the time is up; closing the
# terminal does not stop it. Lotus keeps its process id, start and end time in the state folder (caffeine) and only ever
# stops a process that it started itself.
#   lotus caffeine [on [minutes] | off | status]

function script:Invoke-Lotuscaffeine {
    param([string]$Cmd, [string[]]$Rest)
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    switch -Regex ($sub) {
        '^(on|start)$' { return Start-LotusCaffeine $(if ($Rest.Count -gt 1) { $Rest[1] } else { '' }) }
        '^(off|stop)$' { return Stop-LotusCaffeine }
        '^status$' { return Show-LotusCaffeineStatus }
        '^$' { return Show-LotusCaffeineMenu }
        '^\d+$' { return Start-LotusCaffeine $sub }
        default { Write-LotusError "Unknown option: $sub" '' @('lotus caffeine on [minutes] · off · status'); return (St 2) }
    }
}

# The running keep-awake of Lotus → @{ Pid; Start; End } (End 0 = until stopped), or $null
function script:Get-LotusCaffeineState {
    $f = Join-Path $script:Paths.State 'caffeine'
    $text = Read-LotusFile $f
    if ($null -eq $text) { return $null }
    $v = @($text.Trim() -split '\s+')
    if ($v.Count -lt 3 -or $v[0] -notmatch '^\d+$' -or $v[1] -notmatch '^\d+$' -or $v[2] -notmatch '^\d+$') { Remove-Item -LiteralPath $f -Force; return $null }
    # gone, or the number now belongs to another program: forget it
    if (-not (Test-LotusAwake ([int]$v[0]) ([long]$v[1]))) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue; return $null }
    [pscustomobject]@{ Pid = [int]$v[0]; Start = [long]$v[1]; End = [long]$v[2] }
}

# "42 min", "1 h 5 min"
function script:Format-LotusLeft {
    param([long]$Seconds)
    $m = [Math]::Truncate(($Seconds + 59) / 60)
    if ($m -ge 60) { "$([Math]::Truncate($m / 60)) h $($m % 60) min" } else { "$m min" }
}

function script:Start-LotusCaffeine {
    param([string]$Minutes)
    $arg = if ($Minutes) { $Minutes } else { '60' }
    if ($arg -notmatch '^\d+$') { Write-LotusError 'Minutes must be a number' $arg @('Example: lotus caffeine on 90'); return (St 2) }
    $min = [int]$arg
    if ($min -gt 1440) { Write-LotusError 'At most 24 hours (1440 minutes)' '' @('For longer: lotus caffeine on 0 – until you turn it off'); return (St 2) }
    if (Get-LotusCaffeineState) { Stop-LotusCaffeine -Quiet | Out-Null }
    New-LotusDir $script:Paths.State | Out-Null
    $r = Start-LotusAwake ($min * 60)
    if ($r.Code -eq 2) { Write-LotusError 'Lotus cannot keep this system awake' 'Keeping the computer awake needs Windows.'; return (St 1) }
    if ($r.Code -ne 0) { Write-LotusError "$(Get-LotusAwakeName) did not start" 'Windows did not start the hidden PowerShell that keeps it awake.'; return (St 1) }
    $procId = [int]$r.Value
    $now = Get-LotusEpoch
    $start = try { Get-LotusEpoch (Get-Process -Id $procId).StartTime } catch { $now }
    Write-LotusFile (Join-Path $script:Paths.State 'caffeine') "$procId $start $(if ($min) { $now + $min * 60 } else { 0 })`n"
    Write-LotusLog INFO caffeine "Keeping the system awake$(if ($min) { " for $min min" }) ($(Get-LotusAwakeName) $procId)"
    if ($min) {
        $until = [datetime]::Now.AddMinutes($min).ToString('HH:mm')
        Write-LotusSuccess "$(T caf_on 'Your Mac stays awake') – $(Format-LotusLeft ($min * 60)) ($(T caf_until 'until') $until)"
    } else {
        Write-LotusSuccess "$(T caf_on 'Your Mac stays awake') – $(T caf_forever 'until you turn it off'): lotus caffeine off"
    }
    St 0
}

function script:Stop-LotusCaffeine {
    param([switch]$Quiet)
    $s = Get-LotusCaffeineState
    if (-not $s) {
        if (-not $Quiet) { Write-LotusInfo (T caf_was_off 'Keep awake is not on') }
        return (St 0)
    }
    Stop-LotusAwake $s.Pid
    Remove-Item -LiteralPath (Join-Path $script:Paths.State 'caffeine') -Force -ErrorAction SilentlyContinue
    Write-LotusLog INFO caffeine "Stopped keeping the system awake (pid $($s.Pid))"
    if (-not $Quiet) { Write-LotusSuccess (T caf_off 'Your Mac may sleep again') }
    St 0
}

function script:Show-LotusCaffeineStatus {
    $s = Get-LotusCaffeineState
    if (-not $s) { T caf_status_off 'Keep awake: off'; return (St 0) }
    if ($s.End) {
        $until = [DateTimeOffset]::FromUnixTimeSeconds($s.End).LocalDateTime.ToString('HH:mm')
        "$(T caf_status_on 'Keep awake: on') – $(Format-LotusLeft ($s.End - (Get-LotusEpoch))) $(T caf_left 'left') ($(T caf_until 'until') $until)"
    } else {
        "$(T caf_status_on 'Keep awake: on') – $(T caf_forever 'until you turn it off')"
    }
    St 0
}

function script:Show-LotusCaffeineMenu {
    if (-not (Test-LotusTty)) { return Show-LotusCaffeineStatus }
    Write-LotusHeader (T caf_title 'Keep awake') (T caf_sub_win (T caf_sub 'Your Mac does not sleep while this is on – for downloads, renders or a Minecraft server'))
    if (Get-LotusCaffeineState) {
        foreach ($o in Show-LotusCaffeineStatus) { if (-not (Test-LotusStatus $o)) { Write-LotusLine $o } }
        Write-LotusLine ''
        if (Read-LotusConfirm (T caf_stop_q 'Let your Mac sleep again?') 'y') { return Stop-LotusCaffeine }
        return (St 0)
    }
    $mins = @(30, 60, 120, 240, 0)
    $pick = Read-LotusChoice (T caf_how_long 'For how long?') @('30 min', '1 h', '2 h', '4 h', (T caf_forever 'until you turn it off'))
    if ($null -eq $pick) { return (St 0) }
    Start-LotusCaffeine ([string]$mins[$pick - 1])
}
