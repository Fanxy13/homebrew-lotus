# /convert on Windows – a video saved as MP3 or MP4 with yt-dlp and ffmpeg: a port of lib/cmd/convert.zsh. Only for
# content you have the right to download: Lotus does not bypass DRM, paywalls, logins or private content – yt-dlp runs
# with its default behavior. yt-dlp and ffmpeg come from winget (yt-dlp.yt-dlp, Gyan.FFmpeg) after a yes. The questions,
# yt-dlp's arguments and what a failure means are the Mac's; the progress is shown as steps with a bar of real bytes
# (the Mac's blooming lotus is not on Windows yet). Esc or Ctrl-C stops it – yt-dlp picks up there the next time.

$script:YtdlpOld = 30       # days behind the newest yt-dlp – then /convert offers it (sites change often)
$script:YtdlpQuiet = 7      # days without asking again after a "no"
$script:ConvertPause = 2    # seconds before the second try – YouTube often fails once and then works

function script:Invoke-Lotusconvert {
    param([string]$Cmd, [string[]]$Rest)
    Import-LotusCommand web
    $link = if ($Rest.Count) { $Rest[0] } else { '' }
    Write-LotusHeader 'Convert' 'MP3 or MP4'
    if (-not $link) {
        if (-not (Test-LotusTty)) { Write-LotusError 'Which video?' '' @('/convert <link>'); return (St 1) }
        $link = Read-LotusInput 'Link'
        if (-not $link) { return (St 0) }
    }
    $url = ConvertTo-LotusUrl $link
    if (-not $url) { Write-LotusError 'That is not a valid link' $link @('Example: /convert https://www.youtube.com/watch?v=…'); return (St 1) }
    $tools = Get-LotusConvertTools
    if (-not $tools) { return (St 1) }
    Test-LotusYtdlpAge $tools
    Write-LotusDim 'Only download videos you have the right to save (your own, licensed or free to use).'
    Write-LotusDim 'Lotus does not bypass DRM, paywalls or private videos.'
    Write-LotusBlank
    if (-not (Test-LotusTty)) { Write-LotusError 'MP3 or MP4?' 'The questions need a keyboard.' @('Run /convert in a terminal window'); return (St 1) }
    $want = Read-LotusChoice 'What do you want?' @('MP3 – audio only', 'MP4 – video')
    if ($null -eq $want) { return (St 0) }
    $downloads = if ($env:LOTUS_DOWNLOADS) { $env:LOTUS_DOWNLOADS } else { Join-Path (Get-LotusHome) 'Downloads/Lotus' }
    $tpl = Join-Path $downloads '%(title).150B.%(ext)s'
    $argv = [System.Collections.Generic.List[string]]::new(); $argv.Add('--no-playlist')
    $fps = ''; $ext = 'mp3'; $quality = 'best quality'
    if ($want -eq 1) { foreach ($a in '-x', '--audio-format', 'mp3', '--audio-quality', '0') { $argv.Add($a) } }
    else {
        $ext = 'mp4'
        $res = @('360', '480', '720', '1080', 'best')
        $pick = Read-LotusChoice 'Resolution' @('360p', '480p', '720p', '1080p', 'Best available')
        if ($null -eq $pick) { return (St 0) }
        $h = $res[$pick - 1]
        if ($h -ceq 'best') { $argv.Add('-f'); $argv.Add('bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b'); $quality = 'best resolution' }
        else {
            # the last "/b" covers plain video files without size information
            $argv.Add('-f'); $argv.Add("bv*[height<=$h][ext=mp4]+ba[ext=m4a]/bv*[height<=$h]+ba/b[height<=$h]/b"); $quality = "$($h)p"
        }
        foreach ($a in '--merge-output-format', 'mp4', '--remux-video', 'mp4') { $argv.Add($a) }
        $pick = Read-LotusChoice 'Frames per second' @('Keep the original', '24 FPS', '30 FPS', '60 FPS')
        if ($null -eq $pick) { return (St 0) }
        $fps = @('', '24', '30', '60')[$pick - 1]
        if ($fps) { $quality += " · $fps FPS"; Write-LotusDim 'Changing the frame rate re-encodes the video, which takes a while.' }
    }
    New-LotusDir $downloads | Out-Null
    $probe = Get-LotusConvertProbe $tools $url $tpl $argv.ToArray()
    if (-not $probe) { return (St 1) }
    $file = [IO.Path]::ChangeExtension($probe.File, $ext)
    if (Test-Path -LiteralPath $file) {
        $pick = Read-LotusChoice "$(Split-Path -Leaf $file) already exists" @('Keep both (new name)', 'Replace it', 'Cancel')
        if ($null -eq $pick -or $pick -eq 3) { return (St 0) }
        if ($pick -eq 1) {
            $base = [IO.Path]::Combine((Split-Path -Parent $file), [IO.Path]::GetFileNameWithoutExtension($file)); $n = 2
            while (Test-Path -LiteralPath "$base ($n).$ext") { $n++ }
            $tpl = "$($base.Replace('%', '%%')) ($n).%(ext)s"; $file = "$base ($n).$ext"
        } else { $argv.Add('--force-overwrites') }
    }
    $done = Invoke-LotusConvertDownload $tools $url $tpl $ext $fps $quality $probe $argv.ToArray()
    if (-not $done) { return (St 1) }
    if ($done.File -and (Test-Path -LiteralPath $done.File)) { $file = $done.File }
    if ($done.Warn) { Write-LotusWarn $done.Warn }
    $size = if (Test-Path -LiteralPath $file) { $b = (Get-Item -LiteralPath $file).Length; if ($b -lt 1048576) { "$([Math]::Truncate(($b + 512) / 1024)) KB" } else { '{0:0.0} MB' -f ($b / 1048576.0) } } else { '' }
    Write-LotusSuccess "Done: $(Format-LotusHomePath $file)$(if ($size) { "  ($size)" })"
    Show-LotusPetReact done
    if ((Read-LotusConfirm 'Show it in File Explorer?' 'y') -and (Test-Path -LiteralPath $file)) { [void](Show-LotusInFolder $file) }
    St 0
}

# ── The tools ─────────────────────────────────────────────────

# A program on the PATH – or where winget links what it installed (that folder may not be in this window's PATH yet)
function script:Find-LotusConvertTool {
    param([string]$Name)
    $p = Find-LotusProgram @($Name)
    if ($p) { return $p }
    if ($IsWindows -and $env:LOCALAPPDATA) {
        $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\$Name.exe"
        if (Test-Path -LiteralPath $link) { return $link }
    }
    $null
}

# yt-dlp and ffmpeg → @{ Ytdlp; Ffmpeg; Ffprobe }, after offering what is missing – or $null
function script:Get-LotusConvertTools {
    $y = Find-LotusConvertTool 'yt-dlp'; $f = Find-LotusConvertTool 'ffmpeg'
    if (-not ($y -and $f)) {
        $missing = @($(if (-not $y) { 'yt-dlp' }), $(if (-not $f) { 'ffmpeg' }) | Where-Object { $_ })
        $ids = @($(if (-not $y) { 'yt-dlp.yt-dlp' }), $(if (-not $f) { 'Gyan.FFmpeg' }) | Where-Object { $_ })
        Write-LotusError "Missing tools: $($missing -join ', ')" '/convert uses yt-dlp to download and ffmpeg to convert.' @(
            'Both are free and open source and come from winget:'
            @($ids | ForEach-Object { "  winget install --id $_ -e" }))
        if (-not ($IsWindows -and (Test-LotusTty) -and (Get-Command winget -ErrorAction SilentlyContinue))) { return $null }
        if (-not (Read-LotusConfirm "Install $($missing -join ' and ') with winget?" 'y')) { return $null }
        foreach ($id in $ids) {
            $rc = Invoke-LotusInTheOpen 'winget' @('install', '--id', $id, '-e', '--accept-source-agreements')
            if ($rc -ne 0) { Write-LotusError 'Installation failed' "winget's message is shown above (exit code $rc)."; return $null }
        }
        $y = Find-LotusConvertTool 'yt-dlp'; $f = Find-LotusConvertTool 'ffmpeg'
        if (-not ($y -and $f)) { Write-LotusInfo 'Installed – open a new window, then run /convert again.'; return $null }
    }
    [pscustomobject]@{ Ytdlp = $y; Ffmpeg = $f; Ffprobe = (Find-LotusConvertTool 'ffprobe') }
}

# The version of yt-dlp ("2026.10.21") and the day it came out, and the newest – from its release page on GitHub, once a day
function script:Get-LotusYtdlpVersion { param($Tools) ([string](Invoke-LotusNativeText $Tools.Ytdlp @('--version'))).Trim() }
function script:ConvertTo-LotusYtdlpDate { param([string]$Version) if ($Version -match '^(\d{4})\.(\d{1,2})\.(\d{1,2})') { [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) } else { $null } }
function script:Get-LotusYtdlpLatest {
    $f = Join-Path $script:Paths.Cache 'ytdlp-latest'
    if (Test-Path -LiteralPath $f) {
        $age = ([datetime]::UtcNow - (Get-Item -LiteralPath $f).LastWriteTimeUtc).TotalSeconds
        $v = ([string](Read-LotusFile $f)).Trim()
        if ($v -and $age -lt 86400) { return $v }
        if (-not $v -and $age -lt 3600) { return $null }
    }
    $v = ''
    try {
        $r = Get-LotusHttpStatus -Uri 'https://github.com/yt-dlp/yt-dlp/releases/latest' -Method HEAD -Redirect $false -TimeoutSec 4
        $loc = if ($r) { [string]@($r.Headers['Location'])[0] } else { '' }
        if ($loc -match '/tag/(\d+\.\d+\.\d+(\.\d+)?)$') { $v = $Matches[1] }
    } catch { }
    try { Write-LotusFile $f "$v`n" } catch { }
    if ($v) { $v } else { $null }
}

# Before a download: a yt-dlp a month behind the newest gets an offer to update – not again for a week after a "no"
function script:Test-LotusYtdlpAge {
    param($Tools)
    $have = Get-LotusYtdlpVersion $Tools
    $haveDay = ConvertTo-LotusYtdlpDate $have
    if (-not $haveDay) { return }
    $newest = Get-LotusYtdlpLatest
    $behind = if ($newest) { $nd = ConvertTo-LotusYtdlpDate $newest; if ($nd -and $newest -cne $have) { [Math]::Max(0, ($nd - $haveDay).Days) } else { 0 } } else { ([datetime]::Today - $haveDay).Days }
    if ($newest) { if ($behind -lt $script:YtdlpOld) { return } } elseif ($behind -le 60) { return }
    $askedFile = Join-Path $script:Paths.State 'ytdlp-asked'
    $asked = Get-LotusInt ([string](Read-LotusFile $askedFile)).Trim() 0
    if ((Get-LotusEpoch) - $asked -lt $script:YtdlpQuiet * 86400) { return }
    Write-LotusLog INFO convert "yt-dlp $have is $behind days behind $(if ($newest) { $newest } else { 'today' })"
    if ($newest) { Write-LotusWarn "A newer yt-dlp is out: $newest – yours is $behind days older ($have)." } else { Write-LotusWarn "Your yt-dlp is $behind days old ($have)." }
    Write-LotusDim '  Old versions often fail on YouTube.'
    if (-not (Test-LotusTty)) { return }
    if ((Read-LotusConfirm 'Update yt-dlp first?' 'y') -and (Update-LotusYtdlp $Tools)) { Write-LotusBlank; return }
    try { Write-LotusFile $askedFile "$(Get-LotusEpoch)`n" } catch { }
    Write-LotusDim "  /convert asks again in $($script:YtdlpQuiet) days – or when a download fails because of it."
    Write-LotusBlank
}

# Updates yt-dlp the way it came: winget's with winget, the official program by itself (yt-dlp -U)
function script:Update-LotusYtdlp {
    param($Tools)
    $was = Get-LotusYtdlpVersion $Tools
    Write-LotusStep 'Updating yt-dlp …'
    $byWinget = $Tools.Ytdlp -match '\\(WinGet|Microsoft\\WinGet)\\' -and (Get-Command winget -ErrorAction SilentlyContinue)
    $rc = if ($byWinget) { Invoke-LotusInTheOpen 'winget' @('upgrade', '--id', 'yt-dlp.yt-dlp', '-e', '--accept-source-agreements') } else { Invoke-LotusInTheOpen $Tools.Ytdlp @('-U') }
    $now = Get-LotusYtdlpVersion $Tools
    if ($now -and $now -cne $was) { Write-LotusLog INFO convert "yt-dlp updated: $was → $now"; Write-LotusSuccess "yt-dlp $now"; return $true }
    if ($rc -eq 0) { Write-LotusInfo "yt-dlp $now is already the newest version."; return $true }
    Write-LotusError 'yt-dlp could not be updated' '' @($(if ($byWinget) { 'Try: winget upgrade --id yt-dlp.yt-dlp -e' } else { "Try: $(Format-LotusHomePath $Tools.Ytdlp) -U" }))
    $false
}

# ── A program whose lines are read while it runs ──────────────

function script:Start-LotusLines {
    param([string]$Program, [string[]]$Arguments)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Program)
    Set-LotusProcessArguments $psi $Arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false); $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    # yt-dlp is Python: its messages in UTF-8, whatever the code page of the console is
    $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'; $psi.EnvironmentVariables['PYTHONUTF8'] = '1'
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    [pscustomobject]@{ P = $p; Out = $p.StandardOutput.ReadLineAsync(); Err = $p.StandardError.ReadLineAsync(); OutEnd = $false; ErrEnd = $false }
}
# What came since the last look → @{ Out = lines; Err = lines }; .OutEnd and .ErrEnd when it is all read
function script:Read-LotusLines {
    param($Run)
    $got = @{ Out = [System.Collections.Generic.List[string]]::new(); Err = [System.Collections.Generic.List[string]]::new() }
    foreach ($side in 'Out', 'Err') {
        while (-not $Run."$($side)End" -and $Run.$side.IsCompleted) {
            $l = $Run.$side.GetAwaiter().GetResult()
            if ($null -eq $l) { $Run."$($side)End" = $true; break }
            $got[$side].Add($l.TrimEnd("`r"))
            $Run.$side = if ($side -ceq 'Out') { $Run.P.StandardOutput.ReadLineAsync() } else { $Run.P.StandardError.ReadLineAsync() }
        }
    }
    $got
}
function script:Stop-LotusLines { param($Run) try { if (-not $Run.P.HasExited) { Stop-LotusProcessTree $Run.P } } catch { }; try { [void]$Run.P.WaitForExit(5000) } catch { } }

# A program to its end, its lines kept apart → @{ Out; Err; Code }
function script:Invoke-LotusLines {
    param([string]$Program, [string[]]$Arguments)
    $run = Start-LotusLines $Program $Arguments
    $out = [System.Collections.Generic.List[string]]::new(); $err = [System.Collections.Generic.List[string]]::new()
    while (-not ($run.OutEnd -and $run.ErrEnd)) {
        $got = Read-LotusLines $run
        foreach ($l in $got.Out) { $out.Add($l) }; foreach ($l in $got.Err) { $err.Add($l) }
        if (-not ($run.OutEnd -and $run.ErrEnd)) { Start-Sleep -Milliseconds 30 }
    }
    $run.P.WaitForExit()
    [pscustomobject]@{ Out = $out.ToArray(); Err = $err.ToArray(); Code = $run.P.ExitCode }
}

# ── Asking yt-dlp first, and what went wrong ──────────────────

# What the file will be called, the title and the length – the first look at the video → @{ File; Title; Length }, or $null.
# A failure is explained, and tried once more.
function script:Get-LotusConvertProbe {
    param($Tools, [string]$Url, [string]$Template, [string[]]$Arguments)
    for ($try = 1; ; $try++) {
        Write-LotusStep $(if ($try -eq 1) { 'Checking the video …' } else { 'Checking the video again …' })
        $r = Invoke-LotusLines $Tools.Ytdlp (@('--no-update') + $Arguments + @('-o', $Template, '--print', '%(title)s', '--print', '%(duration_string)s', '--print', 'filename', '--skip-download', '--', $Url))
        $lines = @($r.Out | Where-Object { $_ -ne '' })
        if ($r.Code -eq 0 -and $lines.Count) {
            $len = if ($lines.Count -ge 3) { $lines[-2] } else { '' }
            if ($len -match '^\d+$') { $len = '0:{0:00}' -f [int]$len }     # 19 → 0:19
            return [pscustomobject]@{ File = $lines[-1]; Title = $(if ($lines.Count -ge 3 -and $lines[-3] -cne 'NA') { $lines[-3] } else { '' }); Length = $(if ($len -cne 'NA') { $len } else { '' }) }
        }
        if (-not (Test-LotusConvertRetry $Tools $r.Err $try 'check')) { return $null }
    }
}

# What went wrong – in yt-dlp's own words – and what helps → $true: try again. A video that is private or gone ends it;
# a newer yt-dlp is offered when the site changed; anything else gets one more try by itself.
function script:Test-LotusConvertRetry {
    param($Tools, [string[]]$Errors, [int]$Try, [string]$What)
    $why = @($Errors) -join "`n"
    $first = @($Errors | Where-Object { $_ -like 'ERROR:*' } | Select-Object -First 1)
    $first = if ($first.Count) { $first[0] } else { @($Errors | Where-Object { $_.Trim() } | Select-Object -Last 1) -join '' }
    $first = $first -replace '^ERROR:\s*', ''
    $kind = 'other'
    if ($why -match 'ideo unavailable|ideo is unavailable|rivate video|video is private|been removed|members-only|Join this channel|confirm your age|age-restricted|copyright|not available in your country|not made this video available') { $kind = 'gone' }
    elseif ($why -match 'Unsupported URL') { $kind = 'unsupported' }
    elseif ($why -match 'HTTP Error 403|HTTP Error 429|Sign in to confirm|not a bot|nsig extraction|n challenge|Signature extraction|Unable to extract|Precondition check failed|Requested format is not available|PO Token') { $kind = 'outdated' }
    $title = if ($What -ceq 'check') { 'yt-dlp cannot read this link' } else { 'The download did not finish' }
    Write-LotusLog ERROR convert "yt-dlp failed ($What, try $Try, $kind): $(if ($first) { $first } else { 'no message' })"
    if ($kind -ceq 'gone') { Write-LotusError $title $first @('The video is private, removed, age-restricted or not available here.'); return $false }
    if ($kind -ceq 'unsupported') { Write-LotusError $title $first @('yt-dlp does not know this site.'); return $false }
    if ($kind -ceq 'outdated') {
        Write-LotusError $title $first @('YouTube and other sites change how they deliver videos – yt-dlp needs updates to keep up.', "Your yt-dlp: $(Get-LotusYtdlpVersion $Tools)")
        if ($Try -eq 1 -and (Test-LotusTty) -and (Read-LotusConfirm 'Update yt-dlp and try again?' 'y') -and (Update-LotusYtdlp $Tools)) { return $true }
    }
    if ($Try -eq 1) {
        if ($kind -cne 'outdated') { Write-LotusWarn "yt-dlp: $(if ($first) { $first } else { 'it stopped without a reason' }) – trying once more" }
        Start-Sleep -Seconds $script:ConvertPause
        return $true
    }
    if ($kind -cne 'outdated') { Write-LotusError $title $(if ($first) { $first } else { 'yt-dlp stopped without a reason.' }) }
    Write-LotusDim '  If it still fails: check that the video plays in your browser, or try again later.'
    Write-LotusBlank
    $false
}

# ── The download, while its steps fill ────────────────────────

# The screen of a download: the title, what it becomes, the steps (done ✓, now ›) and a bar of real bytes, drawn again in place
function script:Write-LotusConvertFrame {
    param($View)
    $esc = [char]27; $k = "$esc[1;$($script:C['key'])m"; $a = E accent; $d = E dim; $r = $script:R
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($View.Title) { $lines.Add("    $($script:B)$(Cut $View.Title ((Get-LotusColumns) - 8))$r") }
    $lines.Add("    $d$($View.Info)$r")
    $lines.Add('')
    $now = [Array]::IndexOf($View.Keys, $View.Stage)
    for ($i = 0; $i -lt $View.Keys.Count; $i++) {
        if ($i -lt $now -or $View.Complete) { $lines.Add("    $k✓$r $($View.Labels[$i])") }
        elseif ($i -eq $now) { $lines.Add("    $a›$r $($script:B)$($View.Labels[$i])$r") }
        else { $lines.Add("    $d· $($View.Labels[$i])$r") }
    }
    $lines.Add('')
    if ($View.Total -gt 0) {
        $pct = [Math]::Min(100, [int]($View.Done * 100 / $View.Total))
        $n = [Math]::Truncate($pct * 24 / 100)
        $lines.Add("    [$a$([string]::new([char]0x25A0, $n))$r$d$([string]::new([char]0x00B7, 24 - $n))$r] $pct%   $d$($View.Note)$r")
    } else { $lines.Add("    $d$($View.Note)$r") }
    $lines.Add("    $(E dim)esc stops$r")
    $sb = [System.Text.StringBuilder]::new("$esc[?2026h")
    if ($View.Drawn) { [void]$sb.Append("$esc[$($View.Drawn)A") }
    foreach ($l in $lines) { [void]$sb.Append("`r$l$esc[K`n") }
    for ($i = $lines.Count; $i -lt $View.Drawn; $i++) { [void]$sb.Append("`r$esc[K`n") }
    $View.Drawn = [Math]::Max($View.Drawn, $lines.Count)
    [void]$sb.Append("$esc[?2026l")
    Write-LotusRaw $sb.ToString()
}

# One key, if one was pressed (Esc and Ctrl-C stop)
function script:Test-LotusConvertStop {
    if ($script:KeyQueueActive) { return ($script:KeyQueue.Count -and $script:KeyQueue.Peek() -cin 'esc', 'interrupt' -and $script:KeyQueue.Dequeue()) }
    try { [Console]::KeyAvailable -and (Read-LotusKeyX 0) -cin 'esc', 'interrupt' } catch { $false }
}

# The download with yt-dlp's progress: bytes, speed and time left move the bar, whether a video or a sound stream is coming
# picks the step. A failed try is explained and tried once more. → @{ File; Warn }, or $null (failed or stopped)
function script:Invoke-LotusConvertDownload {
    param($Tools, [string]$Url, [string]$Template, [string]$Ext, [string]$Fps, [string]$Quality, $Probe, [string[]]$Arguments)
    $site = ($Url -replace '^[a-z]+://', '' -replace '^www\.', '' -split '/')[0]
    $view = [pscustomobject]@{ Title = $Probe.Title; Info = "$($Ext.ToUpper()) · $Quality$(if ($Probe.Length) { " · $($Probe.Length)" }) · $site"
        Keys = @(); Labels = @(); Stage = ''; Done = 0L; Total = 0L; Note = ''; Drawn = 0; Complete = $false }
    if ($Ext -ceq 'mp3') { $view.Keys = @('sound', 'mp3'); $view.Labels = @('Downloading the sound', 'Making the MP3') }
    else {
        $view.Keys = @('video', 'audio', 'merge'); $view.Labels = @('Downloading the video', 'Downloading the sound', 'Putting it together')
        if ($Fps) { $view.Keys += 'fps'; $view.Labels += "Converting to $Fps FPS" }
    }
    $live = Test-LotusOutTty
    $listen = $live -and (Test-LotusTty)
    for ($try = 1; ; $try++) {
        $view.Stage = $view.Keys[0]; $view.Done = 0; $view.Total = 0; $view.Note = "Asking $site for it …"; $view.Drawn = 0; $view.Complete = $false
        if ($live) { Write-LotusBlank; Write-LotusConvertFrame $view }
        $file = ''; $errs = [System.Collections.Generic.List[string]]::new(); $stopped = $false
        $run = Start-LotusLines $Tools.Ytdlp (@('--no-update') + $Arguments + @('--newline', '--progress',
                '--progress-template', 'download:LOTUS %(progress.downloaded_bytes)s %(progress.total_bytes,progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s %(info.vcodec)s',
                '--progress-template', 'postprocess:LOTUS-PP %(progress.status)s %(progress.postprocessor)s',
                '--print', 'after_move:filepath', '-o', $Template, '--', $Url))
        if ($listen) { Enter-LotusKeys }
        try {
            while (-not ($run.OutEnd -and $run.ErrEnd)) {
                $got = Read-LotusLines $run
                foreach ($line in @($got.Out) + @($got.Err)) {
                    if ($line -like 'LOTUS *') {
                        $w = $line -split ' '
                        $view.Stage = if ($Ext -ceq 'mp3') { 'sound' } elseif ($w[5] -ceq 'none') { 'audio' } else { 'video' }
                        $b = 0L; $t = 0L
                        if ([long]::TryParse($w[1], [ref]$b) -and [long]::TryParse(($w[2] -replace '\..*$', ''), [ref]$t) -and $t -gt 0) { $view.Done = $b; $view.Total = $t }
                        $note = ''
                        $sp = 0.0; if ([double]::TryParse($w[3], [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$sp)) { $note = '{0:0.0} MB/s' -f ($sp / 1048576) }
                        $eta = 0; if ([int]::TryParse($w[4], [ref]$eta) -and $eta -gt 0) { $note += "$(if ($note) { ' · ' })$([Math]::Truncate($eta / 60)):$('{0:00}' -f ($eta % 60)) left" }
                        $view.Note = $note
                    } elseif ($line -like 'LOTUS-PP started *') {
                        if ($line -match 'ExtractAudio') { $view.Stage = 'mp3' } elseif ($line -match 'Merger|VideoRemuxer|VideoConvertor') { $view.Stage = 'merge' }
                        $view.Done = 0; $view.Total = 0; $view.Note = ''
                    } elseif ($line -like 'LOTUS-PP *') { }
                    elseif ([IO.Path]::IsPathRooted($line) -and (Test-Path -LiteralPath $line)) { $file = $line }     # where it ended up
                    elseif ($line.Trim()) { $errs.Add($line) }
                }
                if ($live) { Write-LotusConvertFrame $view }
                if ($listen -and (Test-LotusConvertStop)) { $stopped = $true; Stop-LotusLines $run; break }
                if (-not ($run.OutEnd -and $run.ErrEnd)) { Start-Sleep -Milliseconds 80 }
            }
        } finally { if ($listen) { Exit-LotusKeys } }
        if ($stopped) { Write-LotusLog INFO convert 'Stopped'; Write-LotusInfo 'Stopped – yt-dlp picks up where it was the next time.'; return $null }
        $run.P.WaitForExit()
        if ($run.P.ExitCode -eq 0) {
            $warn = ''
            if ($Ext -ceq 'mp4' -and $file) { $warn = Complete-LotusConvertMp4 $Tools $file $Fps $view }
            $view.Complete = $true; $view.Note = ''
            if ($live) { Write-LotusConvertFrame $view; Write-LotusBlank }
            return [pscustomobject]@{ File = $file; Warn = $warn }
        }
        if (-not (Test-LotusConvertRetry $Tools $errs.ToArray() $try 'download')) { return $null }
    }
}

# MP4 that plays everywhere: the new frame rate if asked, AAC sound (some players cannot play Opus in MP4). A failure
# keeps the downloaded video and says so → the warning, or ''
function script:Complete-LotusConvertMp4 {
    param($Tools, [string]$File, [string]$Fps, $View)
    $codec = if ($Tools.Ffprobe) { ([string](Invoke-LotusNativeText $Tools.Ffprobe @('-v', 'error', '-select_streams', 'a:0', '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', $File))).Trim() } else { 'aac' }
    $plainSound = $codec -cin 'aac', 'mp3', ''
    if (-not $Fps -and $plainSound) { return '' }
    $ff = [System.Collections.Generic.List[string]]::new()
    foreach ($a in '-hide_banner', '-loglevel', 'error', '-nostats', '-i', $File) { $ff.Add($a) }
    if ($Fps) { $ff.Add('-r'); $ff.Add($Fps); $View.Stage = 'fps' } else { $ff.Add('-c:v'); $ff.Add('copy') }
    if ($plainSound) { $ff.Add('-c:a'); $ff.Add('copy') } else { foreach ($a in '-c:a', 'aac', '-b:a', '192k') { $ff.Add($a) } }
    if (-not $Fps) { $View.Keys += 'aac'; $View.Labels += 'Making the sound play everywhere'; $View.Stage = 'aac' }
    $tmp = [IO.Path]::ChangeExtension($File, '.tmp.mp4')
    $ff.Add('-y'); $ff.Add($tmp)
    $View.Done = 0; $View.Total = 0; $View.Note = 'ffmpeg …'
    if (Test-LotusOutTty) { Write-LotusConvertFrame $View }
    $r = Invoke-LotusLines $Tools.Ffmpeg $ff.ToArray()
    if ($r.Code -eq 0 -and (Test-Path -LiteralPath $tmp) -and (Get-Item -LiteralPath $tmp).Length -gt 0) { Move-Item -LiteralPath $tmp -Destination $File -Force; return '' }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Write-LotusLog WARN convert "ffmpeg failed on $(Split-Path -Leaf $File) (status $($r.Code))"
    'The conversion did not work – the downloaded video was kept as it is.'
}
