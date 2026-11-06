# /lotus log – what Lotus did, a port of lib/cmd/log.zsh
#   lotus log              the viewer (a plain list without a terminal) · lotus log live   the viewer, following new lines
#   lotus log clear        empty it · lotus log level [lvl]   off, warn, info, debug, trace · lotus log path

$script:LogAlias = @{ off = 'off'; quiet = 'off'; error = 'warn'; errors = 'warn'; warn = 'warn'; warnings = 'warn'; info = 'info'; normal = 'info'
    debug = 'debug'; detailed = 'debug'; trace = 'trace'; everything = 'trace'; all = 'trace' }
$script:LogSev = @{ ERROR = 1; WARN = 2; INFO = 3; DEBUG = 4; TRACE = 5 }

function script:Invoke-Lotuslog {
    param([string]$Cmd, [string[]]$Rest)
    Import-LotusLangGroup log
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    switch -Regex ($sub) {
        '^(|show|view)$' { if ((Test-LotusOutTty) -and (Test-LotusTty)) { return Show-LotusLogViewer $false } else { return Show-LotusLogTail 100 } }
        '^(live|follow|-f)$' { return Show-LotusLogViewer $true }
        '^(tail|print|cat)$' { return Show-LotusLogTail $(if ($Rest.Count -gt 1 -and $Rest[1] -match '^\d+$') { [int]$Rest[1] } else { 100 }) }
        '^(clear|reset)$' { return Clear-LotusLog }
        '^level$' { return Set-LotusLogLevel $(if ($Rest.Count -gt 1) { $Rest[1] } else { '' }) }
        '^(path|where)$' { $script:Paths.Log; return (St 0) }
        '^(help|-h|--help)$' { return Show-LotusLogHelp }
        default { Write-LotusError (T log_unknown 'Unknown log command') $sub @('lotus log · lotus log clear · lotus log level debug'); return (St 1) }
    }
}

function script:Show-LotusLogHelp {
    Write-LotusHero (T log_title 'Log')
    foreach ($r in @("/lotus log|$(T log_h_view)", "/lotus log live|$(T log_h_live)", "/lotus log level <level>|$(T log_h_level)", "/lotus log clear|$(T log_h_clear)", "/lotus log path|$(T log_h_path)")) {
        $p = $r -split '\|', 2
        Write-LotusLine "    $(E key)$(PadR $p[0] 28)$($script:R)$($p[1])"
    }
    Write-LotusBlank
    Write-LotusDim "  $(T log_h_file 'The file:') $($script:Paths.Log)"
    Write-LotusBlank
    St 0
}

function script:Get-LotusLogLevelLabels {
    @{ off = (T log_off 'off'); warn = (T log_warn 'errors and warnings'); info = (T log_info 'normal'); debug = (T log_debug 'detailed'); trace = (T log_trace 'everything') }
}

function script:Set-LotusLogLevel {
    param([string]$Level)
    $label = Get-LotusLogLevelLabels
    if (-not $Level) {
        Write-LotusInfo "$(T log_level 'Log level'): $($label[$script:S['LOTUS_LOG_LEVEL']]) ($($script:S['LOTUS_LOG_LEVEL']))"
        Write-LotusDim '  lotus log level off|warn|info|debug|trace'
        return (St 0)
    }
    $want = $script:LogAlias[$Level.ToLowerInvariant()]
    if (-not $want) { Write-LotusError (T log_bad_level 'Not a log level') $Level @('off · warn · info · debug · trace'); return (St 1) }
    $script:S['LOTUS_LOG_LEVEL'] = $want
    Save-LotusSettings
    Reset-LotusLog
    Write-LotusLog INFO log "Log level set to $want"
    Write-LotusSuccess "$(T log_level 'Log level'): $($label[$want]) ($want)"
    St 0
}

function script:Get-LotusLogFiles {
    $log = $script:Paths.Log
    @(foreach ($i in 9..1) { if (Test-Path -LiteralPath "$log.$i") { "$log.$i" } }) + @(if (Test-Path -LiteralPath $log) { $log })
}

function script:Clear-LotusLog {
    $files = Get-LotusLogFiles
    if (-not $files.Count) { Write-LotusInfo (T log_empty_short 'The log is empty.'); return (St 0) }
    if (-not (Read-LotusConfirm (T log_clear_q 'Delete the log?') 'n')) { return (St 0) }
    foreach ($f in $files) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    Write-LotusLog INFO log 'Log cleared'
    Write-LotusSuccess (T log_cleared 'The log is empty now.')
    St 0
}

# Every entry, oldest first (the rotated files first), at most the last 5000 → objects
function script:Get-LotusLogEntries {
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($f in Get-LotusLogFiles) { foreach ($l in [System.IO.File]::ReadAllLines($f)) { if ($l) { $lines.Add($l) } } }
    $start = [Math]::Max(0, $lines.Count - 5000)
    for ($i = $start; $i -lt $lines.Count; $i++) {
        $f = $lines[$i] -split "`t", 4
        if ($f.Count -ge 4 -and $f[0] -match '^\d+-\d+-\d+') { [pscustomobject]@{ Ts = $f[0]; Lv = $f[1]; Cp = $f[2]; Msg = $f[3] } }
        else { [pscustomobject]@{ Ts = ''; Lv = 'INFO'; Cp = ''; Msg = $lines[$i] } }
    }
}

# A plain list for pipes and scripts:  lotus log tail 50
function script:Show-LotusLogTail {
    param([int]$Count)
    $e = @(Get-LotusLogEntries)
    if (-not $e.Count) { T log_empty_short 'The log is empty.'; return (St 0) }
    foreach ($x in ($e | Select-Object -Last $Count)) {
        "$(($x.Ts -split '\.')[0])  $(PadR $x.Lv 5)  $(PadR $x.Cp 9) $($x.Msg.Replace('\n', ' ⏎ '))"
    }
    St 0
}

# Day heading: Today, Yesterday or the date
function script:Get-LotusLogDay {
    param([string]$Date)
    if ($Date -eq [datetime]::Now.ToString('yyyy-MM-dd')) { return (T log_today 'Today') }
    if ($Date -eq [datetime]::Now.AddDays(-1).ToString('yyyy-MM-dd')) { return (T log_yesterday 'Yesterday') }
    $Date
}

function script:Show-LotusLogViewer {
    param([bool]$Live)
    $esc = [char]27
    $filters = @('trace', 'error', 'warn', 'info', 'debug')
    $flabel = @{ trace = (T log_f_all 'all'); error = 'ERROR'; warn = 'WARN+'; info = 'INFO+'; debug = 'DEBUG+' }
    $c = @{ dim = (E dim); acc = (E accent); k2 = "$esc[1;$($script:C['key2'])m"; key = (E key); err = "$esc[1;38;5;203m"; r = "$esc[0m"; b = "$esc[1m" }
    $st = @{ Sel = 0; Top = 1; Fi = 0; Query = ''; Note = ''; Live = $Live; Entries = @(); Rows = @(); Sig = '' }
    $load = {
        $st.Entries = @(Get-LotusLogEntries)
        $rows = [System.Collections.Generic.List[object]]::new()
        $max = $script:LogSev[$filters[$st.Fi].ToUpperInvariant()]; if (-not $max) { $max = 5 }
        $day = ''
        for ($j = 0; $j -lt $st.Entries.Count; $j++) {
            $x = $st.Entries[$j]
            $sev = $script:LogSev[$x.Lv]; if (-not $sev) { $sev = 3 }
            if ($sev -gt $max) { continue }
            if ($st.Query -and -not $x.Msg.ToLowerInvariant().Contains($st.Query.ToLowerInvariant()) -and -not $x.Cp.ToLowerInvariant().Contains($st.Query.ToLowerInvariant())) { continue }
            $d = if ($x.Ts.Length -ge 10) { $x.Ts.Substring(0, 10) } else { '' }
            if ($d -and $d -ne $day) { $day = $d; $rows.Add(@('day', (Get-LotusLogDay $d))) }
            $rows.Add(@('e', $j))
        }
        $st.Rows = $rows.ToArray()
    }
    $sig = { $i = Get-Item -LiteralPath $script:Paths.Log -ErrorAction SilentlyContinue; if ($i) { "$($i.Length):$($i.LastWriteTimeUtc.Ticks)" } else { 'none' } }
    $step = {
        param($d)
        $j = $st.Sel
        for ($n = 0; $n -lt $st.Rows.Count; $n++) {
            $j += $d
            if ($j -lt 1 -or $j -gt $st.Rows.Count) { return }
            if ($st.Rows[$j - 1][0] -eq 'e') { $st.Sel = $j; return }
        }
    }
    & $load; $st.Sel = $st.Rows.Count; $st.Sig = & $sig
    Enter-LotusKeys
    Write-LotusRaw "$esc[?1049h$esc[?25l$esc[2J"
    try {
        while ($true) {
            $size = Get-LotusSize; $W = $size[0]; $screenH = $size[1]
            # the header
            $lvl = Get-LotusLogLevelLabels
            $span = ''
            if ($st.Entries.Count -and $st.Entries[0].Ts) {
                $first = $st.Entries[0].Ts; $lastTs = $st.Entries[-1].Ts
                $span = "$(Get-LotusLogDay $lastTs.Substring(0, 10)) · $($first.Substring(11, 5)) – $($lastTs.Substring(11, 5))"
                if ($first.Substring(0, 10) -ne $lastTs.Substring(0, 10)) { $span = "$($first.Substring(0, 10)) – $($lastTs.Substring(0, 10))" }
            }
            $info = "$(if ($span) { "$span · " })$($st.Entries.Count) $(T log_entries 'entries') · $(T log_level 'Log level'): $($lvl[$script:S['LOTUS_LOG_LEVEL']])"
            $out = [System.Text.StringBuilder]::new("$esc[H$esc[K`n    $($c.acc)◇$($c.r) $($c.b)lotus$($c.r)$($c.dim) / $($c.r)$($c.b)$(T log_title 'Log')$($c.r)")
            if ($st.Live) { [void]$out.Append("   $($c.key)● $(T log_live 'live')$($c.r)") }
            [void]$out.Append("$esc[K`n$esc[K`n    $($c.dim)$(Cut $info ($W - 6))$($c.r)$esc[K`n")
            [void]$out.Append("    $($c.dim)$(T log_filter 'Filter'): $($c.r)$($flabel[$filters[$st.Fi]])$(if ($st.Query) { "$($c.dim)   $(T log_search 'Search'): $($c.r)$($st.Query)" })$esc[K`n$esc[K`n")
            $body = [Math]::Max(3, $screenH - 9)
            if (-not $st.Rows.Count) {
                if ($st.Entries.Count) { [void]$out.Append("    $($c.dim)$(T log_nomatch 'Nothing matches.')$($c.r)$esc[K`n") }
                else { [void]$out.Append("    $(T log_empty 'The log is empty.')$esc[K`n$esc[K`n    $($c.dim)$(T log_empty_hint '')$($c.r)$esc[K`n") }
                [void]$out.Append("$esc[J")
            } else {
                if ($st.Sel -lt 1) { $st.Sel = $st.Rows.Count }
                if ($st.Sel -gt $st.Rows.Count) { $st.Sel = $st.Rows.Count }
                if ($st.Sel -lt $st.Top) { $st.Top = $st.Sel }
                if ($st.Sel -gt $st.Top + $body - 1) { $st.Top = $st.Sel - $body + 1 }
                $maxTop = [Math]::Max(1, $st.Rows.Count - $body + 1)
                if ($st.Top -gt $maxTop) { $st.Top = $maxTop }
                if ($st.Top -lt 1) { $st.Top = 1 }
                $i = $st.Top
                for (; $i -lt $st.Top + $body -and $i -le $st.Rows.Count; $i++) {
                    $row = $st.Rows[$i - 1]
                    if ($row[0] -eq 'day') { [void]$out.Append("    $($c.dim)── $($row[1]) ──$($c.r)$esc[K`n"); continue }
                    $x = $st.Entries[$row[1]]
                    $col = switch ($x.Lv) { 'ERROR' { $c.err } 'WARN' { $c.k2 } 'INFO' { $c.acc } default { $c.dim } }
                    $comp = if ($W -ge 70) { "$($c.dim)$(PadR (Cut $x.Cp 10) 10)$($c.r)" } else { '' }
                    $room = [Math]::Max(10, $W - 8 - 2 - 7 - $(if ($W -ge 70) { 10 } else { 0 }) - 6)
                    $msg = $x.Msg.Replace('\n', ' ⏎ ')
                    if ($msg.Length -gt $room) { $msg = $msg.Substring(0, $room - 1) + '…' }
                    if ($x.Lv -in 'DEBUG', 'TRACE') { $msg = "$($c.dim)$msg$($c.r)" }
                    $t = if ($x.Ts.Length -ge 19) { $x.Ts.Substring(11, 8) } else { '' }
                    $pre = if ($i -eq $st.Sel) { "  $($c.acc)›$($c.r) " } else { '    ' }
                    [void]$out.Append("$pre$($c.dim)$(PadR $t 8)$($c.r)  $col$(PadR $x.Lv 6)$($c.r) $comp$msg$esc[K`n")
                }
                for (; $i -lt $st.Top + $body; $i++) { [void]$out.Append("$esc[K`n") }
            }
            [void]$out.Append("$esc[K`n    $($c.dim)$(if ($st.Note) { $st.Note } else { T log_keys '↑↓ move   ⏎ details   f filter   / search   l live   y copy   c clear   q quit' })$($c.r)$esc[K$esc[J")
            $st.Note = ''
            Write-LotusRaw $out.ToString()
            $k = if ($st.Live) { Read-LotusKeyX 0.5 } else { Read-LotusKeyX }
            if ($k -eq 'timeout') {
                $now = & $sig
                if ($now -ne $st.Sig) { $st.Sig = $now; $atEnd = $st.Sel -ge $st.Rows.Count; & $load; if ($atEnd) { $st.Sel = $st.Rows.Count } }
                continue
            }
            switch -CaseSensitive -Regex ($k) {
                '^(up|k)$' { & $step -1; break }
                '^(down|j)$' { & $step 1; break }
                '^pgup$' { for ($n = 0; $n -lt $screenH - 10; $n++) { & $step -1 }; break }
                '^(pgdn|space)$' { for ($n = 0; $n -lt $screenH - 10; $n++) { & $step 1 }; break }
                '^(home|g)$' { $st.Sel = 0; & $step 1; break }
                '^(end|G)$' { $st.Sel = $st.Rows.Count; break }
                '^enter$' { Show-LotusLogDetail $st.Entries $st.Rows $st.Sel $W; break }
                '^f$' { $st.Fi = ($st.Fi + 1) % $filters.Count; & $load; $st.Sel = $st.Rows.Count; break }
                '^/$' {
                    Write-LotusRaw "$esc[$screenH;1H$esc[K$esc[?25h    $(T log_search 'Search'): "
                    $q = ''
                    while ($true) { $kk = Read-LotusKeyX; if ($kk -in 'enter', 'esc') { break }; if ($kk -eq 'back') { if ($q) { $q = $q.Substring(0, $q.Length - 1); Write-LotusRaw "`b `b" }; continue }; if ($kk -eq 'space') { $kk = ' ' }; if ($kk.Length -eq 1) { $q += $kk; Write-LotusRaw $kk } }
                    Write-LotusRaw "$esc[?25l"
                    $st.Query = $q; & $load; $st.Sel = $st.Rows.Count; break
                }
                '^l$' { $st.Live = -not $st.Live; & $load; break }
                '^r$' { & $load; break }
                '^y$' {
                    $lines = foreach ($row in $st.Rows) { if ($row[0] -eq 'e') { $x = $st.Entries[$row[1]]; "$($x.Ts)  $($x.Lv)  $($x.Cp)  $($x.Msg)" } }
                    if ((Set-LotusClipboardText (@($lines) -join "`n")) -eq 0) { $st.Note = (T log_copied '%d lines copied').Replace('%d', "$(@($lines).Count)") }
                    break
                }
                '^c$' {
                    Write-LotusRaw "$esc[$screenH;1H$esc[K$esc[?25h    $(T log_clear_q 'Delete the log?') [y/N] "
                    $kk = Read-LotusKeyX
                    Write-LotusRaw "$esc[?25l"
                    if ($kk -cmatch '^[yYjJ]$') {
                        foreach ($f in Get-LotusLogFiles) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
                        Write-LotusLog INFO log 'Log cleared'
                        $st.Note = T log_cleared 'The log is empty now.'
                    }
                    & $load; break
                }
                '^(esc|interrupt)$' { if ($st.Query -and $k -eq 'esc') { $st.Query = ''; & $load; $st.Sel = $st.Rows.Count } else { $st.Quit = $true }; break }
                '^[qQ]$' { $st.Quit = $true; break }
            }
            if ($st.Quit) { break }
        }
    } finally {
        Write-LotusRaw "$esc[?25h$esc[?1049l"
        Exit-LotusKeys
    }
    St 0
}

function script:Show-LotusLogDetail {
    param($Entries, $Rows, [int]$Sel, [int]$Width)
    if ($Sel -lt 1 -or $Rows[$Sel - 1][0] -ne 'e') { return }
    $x = $Entries[$Rows[$Sel - 1][1]]
    Write-LotusRaw "$([char]27)[H$([char]27)[2J"
    Write-LotusHero "$(T log_title 'Log') · $($x.Lv)"
    Write-LotusKv (T log_time 'Time') $x.Ts
    Write-LotusKv (T log_comp 'Part') $x.Cp
    Write-LotusBlank
    foreach ($l in $x.Msg.Replace('\n', "`n") -split "`n") {
        while ($l.Length -gt $Width - 8) { Write-LotusLine "    $($l.Substring(0, $Width - 8))"; $l = $l.Substring($Width - 8) }
        Write-LotusLine "    $l"
    }
    Write-LotusBlank
    Write-LotusDim "  $(T back '(press any key to go back)')"
    [void](Read-LotusKeyX)
    Write-LotusRaw "$([char]27)[2J"
}
