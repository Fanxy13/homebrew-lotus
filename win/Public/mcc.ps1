# The Minecraft control center on Windows (/minecraft → open a server, /mc <name>) – a port of lib/mc/control.zsh.
# One full-screen window with three pages, Tab switches between them:
#   Stats     the server's state, players online with their ping, TPS, memory, CPU, the world's size, the newest
#             events – and a little Minecraft world drifting by (the port of lib/mc/world.zsh, below)
#   Settings  the server icon, the description (MOTD), the folder, plugins: search Modrinth for the server's
#             version, install with one key, or drag your own .jar in; and deleting the server: stopped first,
#             then its folder goes to the Recycle Bin
#   Log       the console, filtered and colored, with a command line (/ like in Minecraft, t to chat)
# The server runs in the background (win/mc/run.ps1, a hidden PowerShell of its own): leaving the control center can
# keep it running, and opening it again later finds it. Windows has no named pipe zsh could use as the console, so
# the runner reads commands from .lotus\input (lines added to the end) and writes the console to .lotus\console.log.
# A server started some other way (start.cmd in its own window) is shown too, from its logs\latest.log – without the
# command line; it is stopped in its own window, by typing stop there.
# Ping, TPS and tick time come from LotusBridge, a tiny plugin the runner builds for Paper servers with the JDK.

Import-LotusLangGroup mc

$script:Mcc = @{}
$script:McUtf8 = [System.Text.UTF8Encoding]::new($false)

# ── Entry ─────────────────────────────────────────────────────

function script:Invoke-LotusMcc {
    param([string]$Dir)
    Import-LotusLangGroup mc
    $Dir = [IO.Path]::GetFullPath($Dir)
    if (-not (Test-Path -LiteralPath (Join-Path $Dir 'start.cmd') -PathType Leaf)) { Write-LotusError (T mc_noserver 'This is not a Lotus Minecraft server') $Dir; return (St 1) }
    Initialize-LotusMcc $Dir
    $m = $script:Mcc
    if (-not ((Test-LotusOutTty) -and (Test-LotusTty))) {
        # no terminal: one line about the server
        Update-LotusMccProbe
        "$($m.Name): $($m.State)"
        return (St 0)
    }
    Update-LotusMccProbe
    # a stopped server starts when its control center opens
    if ($m.State -cin 'stopped', 'crashed') { [void](Start-LotusMccServer) }
    $esc = [char]27
    $live = -not $script:KeyQueueActive
    Enter-LotusKeys
    if ($live) { Write-LotusRaw "$esc[?1049h$esc[?25l$esc[2J" }
    try { Invoke-LotusMccLoop }
    finally {
        # also after an error: the terminal comes back as it was
        if ($live) { Write-LotusRaw "$esc[?2026l$esc[2J$esc[?1049l$esc[?25h" }
        Exit-LotusKeys
        Close-LotusMccLog
    }
    if ($m.Delete) {
        Write-LotusBlank
        if ($m.Deleted) { Write-LotusSuccess (Get-LotusMccDeletedText) }
        else { Write-LotusError ((T mc_err_del 'Lotus could not delete %s').Replace('%s', $m.Name)) $script:McpErr }
        Write-LotusBlank
        return (St 0)
    }
    if ($m.State -cin 'running', 'starting', 'preparing') {
        Write-LotusBlank
        Write-LotusInfo ((T mc_bg_running '%s keeps running in the background.').Replace('%s', $m.Name))
        Write-LotusDim "  $((T mc_bg_back 'Back to it: /mc %s').Replace('%s', $m.Name))"
        Write-LotusBlank
    }
    St 0
}

function script:Initialize-LotusMcc {
    param([string]$Dir)
    $s = Join-Path $Dir '.lotus'
    New-LotusDir $s | Out-Null
    $script:Mcc = @{
        Dir = $Dir; S = $s; Name = Split-Path -Leaf $Dir; Type = ''; Ver = ''; Mode = ''; State = 'stopped'; Problem = ''
        LogF = ''; Stream = $null; Dec = $null; Off = 0L; Part = ''; Filter = 'all'; In = ''; InText = ''; InLabel = ''; Ask = ''
        Toast = ''; ToastK = 'ok'; ToastAt = 0L; Deleted = ''; Sub = ''; Q = ''; QSent = '-'; QTask = $null; QAt = 0.0; RState = 'idle'
        Lan = Get-LotusLanIp; PropStamp = ''; IconKey = ''; Tps = '-'; Mspt = '-'
        Pid = 0; XPid = 0; Wrap = 0; Ready = $false; Progress = 0; LogStop = $false; Exit = -1
        Page = 1; Sel = 1; SSel = 1; PSel = 1; Back = 0; HistI = 0
        Rss = 0; Cpu = 0; Up = 0; Xmx = 0; WorldKb = -1L; Bridge = $false; BrAt = 0L; RTotal = 0; RLoading = $false
        StopAt = 0L; Restart = $false; Leave = $false; WantStop = $false; Changed = $false; Delete = $false; H = 24; W = 80
        T1 = 0.0; T2 = 0.0; T30 = 0.0; T5 = 0.0; CpuAt = $null; CpuTot = $null
        Log = [System.Collections.Generic.List[string]]::new(); Events = [System.Collections.Generic.List[string]]::new()
        Players = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        POrder = [System.Collections.Generic.List[string]]::new(); Hist = [System.Collections.Generic.List[string]]::new()
        Br = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        Prop = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        Res = [System.Collections.Generic.List[object]]::new(); Inst = [System.Collections.Generic.List[object]]::new(); Icon = @()
        C = @{}; Fails = 0
    }
    Set-LotusMccColors
    Get-LotusMccDetect
    Get-LotusMccXmx
    Update-LotusMccProps
    Read-LotusMccHistory
}

function script:Get-LotusMccNow { [datetime]::UtcNow.Ticks / 1e7 }
function script:Get-LotusMccEpoch { [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

# Theme colors as escape codes, by short name
function script:Set-LotusMccColors {
    $esc = [char]27
    $c = @{}
    foreach ($k in 'logo', 'key', 'accent', 'key2', 'salute', 'border', 'dim') { $c[$k] = "$esc[$($script:C[$k])m" }
    $c['r'] = "$esc[0m"; $c['B'] = "$esc[1m"; $c['red'] = "$esc[38;5;203m"
    $c['tab'] = "$esc[1;30;48$($script:C['key'].Substring(2))m"
    $script:Mcc.C = $c
}

# ── The server: what it is, whether it runs ──────────────────

# Type and version: from .lotus\server.conf (written when Lotus made the server), else worked out once
function script:Get-LotusMccDetect {
    $m = $script:Mcc
    $m.Type = ''; $m.Ver = ''
    $conf = Read-LotusFile (Join-Path $m.S 'server.conf')
    if ($conf) {
        foreach ($line in $conf -split "`n") {
            if ($line.StartsWith('type=')) { $m.Type = $line.Substring(5) }
            if ($line.StartsWith('version=')) { $m.Ver = $line.Substring(8) }
        }
    }
    if ($m.Type) { return }
    if ($m.Name -match '^(vanilla|paper)-([0-9.]+)') { $m.Type = $Matches[1]; $m.Ver = $Matches[2] }
    elseif ((Test-Path -LiteralPath (Join-Path $m.Dir 'libraries/io/papermc')) -or (Test-Path -LiteralPath (Join-Path $m.Dir 'config/paper-global.yml')) -or (Test-Path -LiteralPath (Join-Path $m.Dir 'paper.yml'))) { $m.Type = 'paper' }
    else {
        $m.Type = 'vanilla'
        $names = @(Get-LotusZipNames (Join-Path $m.Dir 'server.jar'))
        if ($names | Where-Object { $_ -like '*paperclip*' }) { $m.Type = 'paper' }
    }
    if (-not $m.Ver) {
        $vj = Get-LotusZipText (Join-Path $m.Dir 'server.jar') 'version.json'
        if ($vj) { try { $m.Ver = [string]($vj | ConvertFrom-Json).id } catch { } }
    }
    Save-LotusMccConf
}
function script:Save-LotusMccConf { Write-LotusFile (Join-Path $script:Mcc.S 'server.conf') "type=$($script:Mcc.Type)`nversion=$($script:Mcc.Ver)`n" }

# The names in a zip file (a .jar), and the text of one of them
function script:Get-LotusZipNames {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $z = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { foreach ($e in $z.Entries) { $e.FullName } } finally { $z.Dispose() }
    } catch { }
}
function script:Get-LotusZipText {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $z = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $e = $z.GetEntry($Name)
            if (-not $e) { return $null }
            $r = [IO.StreamReader]::new($e.Open(), $script:McUtf8)
            try { $r.ReadToEnd() } finally { $r.Dispose() }
        } finally { $z.Dispose() }
    } catch { $null }
}

# The memory the server may use, from start.cmd (-Xmx4G) → MB
function script:Get-LotusMccXmx {
    $m = $script:Mcc
    $m.Xmx = 0
    $sc = Read-LotusFile (Join-Path $m.Dir 'start.cmd')
    if ($sc -cmatch '-Xmx([0-9]+)([GgMm])') { $m.Xmx = if ($Matches[2] -cin 'G', 'g') { [int]$Matches[1] * 1024 } else { [int]$Matches[1] } }
}

# server.properties → $Mcc.Prop (read again when the file changed)
function script:Update-LotusMccProps {
    $m = $script:Mcc
    $f = Join-Path $m.Dir 'server.properties'
    $i = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
    if (-not $i) { $m.Prop.Clear(); $m.PropStamp = ''; return }
    $stamp = "$($i.LastWriteTimeUtc.Ticks) $($i.Length)"
    if ($m.PropStamp -ceq $stamp) { return }
    $m.PropStamp = $stamp
    $m.Prop.Clear()
    foreach ($line in ([string](Read-LotusFile $f)) -split "`n") {
        if ($line -match '^\s*[#!]' -or -not $line.Contains('=')) { continue }
        $k = $line.Substring(0, $line.IndexOf('='))
        $m.Prop[$k] = $line.Substring($line.IndexOf('=') + 1)
    }
}

# A value for server.properties: \ and everything outside ASCII as Java writes it (\uXXXX)
function script:ConvertTo-LotusPropValue {
    param([string]$Text)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Text.ToCharArray()) {
        $cp = [int]$ch
        if ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ($cp -lt 32) { continue }
        elseif ($cp -lt 127) { [void]$sb.Append($ch) }
        else { [void]$sb.Append('\u').Append($cp.ToString('x4')) }     # (.NET strings are UTF-16: a pair stays a pair)
    }
    $sb.ToString()
}
# …and back: \uXXXX (pairs too), \\ and \:
function script:ConvertFrom-LotusPropValue {
    param([string]$Text)
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($ch -eq '\' -and $i -lt $Text.Length - 1) {
            if ($Text[$i + 1] -eq 'u' -and $i + 5 -lt $Text.Length -and $Text.Substring($i + 2, 4) -match '^[0-9A-Fa-f]{4}$') {
                [void]$sb.Append([char][Convert]::ToInt32($Text.Substring($i + 2, 4), 16)); $i += 5
            } else { $i++; [void]$sb.Append($Text[$i]) }
        } else { [void]$sb.Append($ch) }
    }
    $sb.ToString()
}

# Changes one setting in server.properties (or adds it), the rest stays as it is
function script:Set-LotusMccProp {
    param([string]$Key, [string]$Value)
    $m = $script:Mcc
    $f = Join-Path $m.Dir 'server.properties'
    $v = ConvertTo-LotusPropValue $Value
    $out = [System.Text.StringBuilder]::new(); $done = $false
    $text = Read-LotusFile $f
    if ($text) {
        foreach ($line in $text.TrimEnd("`n") -split "`n") {
            if ($line.StartsWith("$Key=")) { [void]$out.Append("$Key=$v`n"); $done = $true } else { [void]$out.Append("$line`n") }
        }
    }
    if (-not $done) { [void]$out.Append("$Key=$v`n") }
    Write-LotusFile $f $out.ToString()
    $m.PropStamp = ''
    Update-LotusMccProps
}

# The description as Minecraft shows it: escapes undone, § color codes left out
function script:Get-LotusMccMotd {
    $v = if ($script:Mcc.Prop.ContainsKey('motd')) { $script:Mcc.Prop['motd'] } else { 'A Minecraft Server' }
    (ConvertFrom-LotusPropValue $v) -replace '§.', ''
}

# A process that is still there, and is what the pid file says it is: a pid file from before a restart of Windows can
# name another program (the name, and it started after Lotus started the server)
function script:Test-LotusMccProc {
    param([int]$ProcessId, [string[]]$Names, [long]$Since = 0)
    if ($ProcessId -le 0) { return $false }
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p -or $p.HasExited) { return $false }
    if ($Names -and $p.ProcessName -notin $Names) { return $false }
    if ($Since) { try { if ((Get-LotusEpoch $p.StartTime.ToUniversalTime()) -lt $Since - 10) { return $false } } catch { } }
    $true
}

# The java of a server started some other way: its command line names this folder's server.jar (start.cmd gives it
# with its full path) → its process id, or 0
function script:Find-LotusMccExternal {
    if (-not $IsWindows) { return 0 }
    $jar = (Join-Path $script:Mcc.Dir 'server.jar').ToLowerInvariant()
    try {
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)) {
            if ([string]$p.CommandLine -and ([string]$p.CommandLine).ToLowerInvariant().Contains($jar)) { return [int]$p.ProcessId }
        }
    } catch { }
    0
}

# What runs, once a second: our server (the runner's pid files), or one started elsewhere
function script:Update-LotusMccProbe {
    $m = $script:Mcc
    $since = Get-LotusInt (Read-LotusFile (Join-Path $m.S 'started')) 0
    $pid_ = Get-LotusInt (Read-LotusFile (Join-Path $m.S 'pid')) 0
    $wrap = Get-LotusInt (Read-LotusFile (Join-Path $m.S 'wrapper')) 0
    if (-not (Test-LotusMccProc $pid_ @('java', 'javaw') $since)) { $pid_ = 0 }
    if (-not (Test-LotusMccProc $wrap @('pwsh', 'powershell') $since)) { $wrap = 0 }
    $m.Pid = $pid_; $m.Wrap = $wrap
    if ($pid_ -or $wrap) {
        if ($m.Mode -cne 'ours') { $m.Mode = 'ours'; Open-LotusMccLog (Join-Path $m.S 'console.log') }
        if ($m.WantStop -or $m.LogStop) { $m.State = 'stopping' }
        elseif (-not $pid_) { $m.State = 'preparing' }
        elseif ($m.Ready) { $m.State = 'running' }
        else { $m.State = 'starting' }
        return
    }
    # started some other way: a java with this folder's server.jar (asking Windows takes a moment – every 10 s, and once
    # found, the process alone is watched)
    if ($m.Mode -ceq 'external' -and (Test-LotusMccProc $m.XPid @('java', 'javaw'))) {
        $m.Pid = $m.XPid
        $m.State = if ($m.WantStop) { 'stopping' } else { 'running' }
        return
    }
    $now = Get-LotusMccNow
    if ($m.Mode -cnotin 'ours', 'external' -and $now - $m.T5 -gt 10) {
        $m.T5 = $now
        $x = Find-LotusMccExternal
        if ($x) {
            $m.Pid = $x; $m.XPid = $x
            if ($m.Mode -cne 'external') { $m.Mode = 'external'; Open-LotusMccLog (Join-Path $m.Dir 'logs/latest.log') }
            $m.State = if ($m.WantStop) { 'stopping' } else { 'running' }
            return
        }
    }
    # nothing runs
    if ($m.State -cnotin 'stopped', 'crashed' -or -not $m.Mode) {
        $exitFile = Join-Path $m.S 'exit'
        $m.Exit = Get-LotusInt (Read-LotusFile $exitFile) -1
        if ($m.WantStop -or $m.Exit -le 0 -or $m.Exit -eq 130 -or $m.Exit -eq 143) { $m.State = 'stopped' } else { $m.State = 'crashed' }
        if (-not $m.Mode -and -not (Test-Path -LiteralPath $exitFile)) { $m.State = 'stopped' }
        $m.Players.Clear(); $m.POrder.Clear(); $m.Br.Clear(); $m.Bridge = $false; $m.Rss = 0; $m.Cpu = 0
        $m.WantStop = $false
        if (-not $m.Mode -or $m.Mode -ceq 'external') { Open-LotusMccLog (Join-Path $m.S 'console.log') }
        $m.Mode = 'stopped'
    }
}

# Starts the server in the background: a hidden PowerShell of its own (win/mc/run.ps1) – closing the terminal does not
# stop it
function script:Start-LotusMccServer {
    $m = $script:Mcc
    Update-LotusMccProps
    # without the EULA the server would stop at once – ask first
    if ([string](Read-LotusFile (Join-Path $m.Dir 'eula.txt')) -notmatch 'eula=true') { $m.Problem = 'eula'; $m.Ask = 'eula'; return $false }
    $m.Problem = ''; $m.Ready = $false; $m.LogStop = $false; $m.Progress = 0; $m.WantStop = $false; $m.Exit = -1
    Remove-Item -LiteralPath (Join-Path $m.S 'exit') -Force -ErrorAction SilentlyContinue
    Close-LotusMccLog
    try {
        [IO.File]::WriteAllText((Join-Path $m.S 'console.log'), '')
        [IO.File]::WriteAllText((Join-Path $m.S 'input'), '')
    } catch { Show-LotusMccToast err (Get-LotusMcText mc_err_fifo 'Lotus could not prepare the console of the server.'); return $false }
    Open-LotusMccLog (Join-Path $m.S 'console.log')
    $p = Start-LotusDetached (Join-Path $script:LotusModuleRoot 'mc/run.ps1') @($m.Dir)
    if (-not $p) { Show-LotusMccToast err (Get-LotusMcText mc_err_fifo 'Lotus could not prepare the console of the server.'); return $false }
    $m.Mode = 'ours'; $m.State = 'preparing'; $m.Up = 0
    Write-LotusLog INFO minecraft "Server started: $($m.Name)"
    # the pid files take a moment
    for ($i = 0; $i -lt 40 -and -not (Test-Path -LiteralPath (Join-Path $m.S 'wrapper')); $i++) { Start-Sleep -Milliseconds 50 }
    $m.T1 = 0
    $true
}

# stop: in the console for our server. One started in its own window is stopped there (Windows cannot ask a program
# of another window to save and stop – only end it at once).
function script:Stop-LotusMccServer {
    $m = $script:Mcc
    if ($m.Mode -ceq 'external') { Show-LotusMccToast info (T mc_ext_stop_win 'This server runs in a window of its own – type stop there.'); return }
    $m.WantStop = $true; $m.StopAt = Get-LotusMccEpoch; $m.State = 'stopping'
    if ($m.Pid) { [void](Send-LotusMccCommand 'stop') }
    elseif ($m.Wrap) {
        # still preparing (the Paper patcher, javac): the runner and what it started end – no world is open yet
        try { (Get-Process -Id $m.Wrap -ErrorAction Stop).Kill($true) } catch { }
    }
    Write-LotusLog INFO minecraft "Server stopped: $($m.Name)"
}

# A command into the server's console: a line at the end of .lotus\input, which the runner hands on (and shows in
# the log as "[Lotus] > …")
function script:Send-LotusMccCommand {
    param([string]$Line)
    $m = $script:Mcc
    if ($m.Mode -cne 'ours' -or -not $m.Pid) { return $false }
    try {
        $fs = [IO.FileStream]::new((Join-Path $m.S 'input'), [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]'ReadWrite, Delete')
        try { $b = $script:McUtf8.GetBytes("$Line`n"); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
        $true
    } catch { $false }
}

# Memory and CPU (every 2 s), the world's size (every 30 s)
function script:Update-LotusMccSample {
    $m = $script:Mcc
    if ($m.Pid) {
        $p = Get-Process -Id $m.Pid -ErrorAction SilentlyContinue
        if ($p) {
            $m.Rss = [int]($p.WorkingSet64 / 1MB)
            try {
                $now = [datetime]::UtcNow; $tot = $p.TotalProcessorTime
                # (as ps counts it: 100 is one core)
                if ($m.CpuAt) { $m.Cpu = [int][Math]::Max(0, ($tot - $m.CpuTot).TotalSeconds / [Math]::Max(0.1, ($now - $m.CpuAt).TotalSeconds) * 100) }
                $m.CpuAt = $now; $m.CpuTot = $tot
                $m.Up = [long]($now - $p.StartTime.ToUniversalTime()).TotalSeconds
            } catch { }
        }
    } else { $m.CpuAt = $null }
    $now2 = Get-LotusMccNow
    if ($now2 - $m.T30 -gt 30) {
        $m.T30 = $now2
        $lvl = if ($m.Prop.ContainsKey('level-name') -and $m.Prop['level-name']) { $m.Prop['level-name'] } else { 'world' }
        $lvl = $lvl -replace '[^A-Za-z0-9._ -]', ''
        $sum = -2L
        foreach ($d in @($lvl, "$($lvl)_nether", "$($lvl)_the_end")) {
            $p2 = Join-Path $m.Dir $d
            if (-not (Test-Path -LiteralPath $p2 -PathType Container)) { continue }
            if ($sum -lt 0) { $sum = 0 }
            try { foreach ($f in [IO.Directory]::EnumerateFiles($p2, '*', [IO.SearchOption]::AllDirectories)) { $sum += ([IO.FileInfo]::new($f)).Length } } catch { }
        }
        $m.WorldKb = if ($sum -lt 0) { -2 } else { [long]($sum / 1024) }
    }
}

# What LotusBridge wrote (plugins\LotusBridge\status.tsv): fresh means less than 8 seconds old
function script:Update-LotusMccBridge {
    $m = $script:Mcc
    $f = Join-Path $m.Dir 'plugins/LotusBridge/status.tsv'
    $i = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
    $mt = if ($i) { Get-LotusEpoch $i.LastWriteTimeUtc } else { 0 }
    if (-not $i -or (Get-LotusMccEpoch) - $mt -gt 8 -or -not $m.Pid) { $m.Bridge = $false; $m.Tps = '-'; $m.Mspt = '-'; return }
    if ($mt -eq $m.BrAt) { return }
    $m.BrAt = $mt; $m.Bridge = $true
    $m.Br.Clear()
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ([string](Read-LotusFile $f)) -split "`n") {
        $f2 = $line -split "`t"
        if ($f2[0] -ceq 'tps' -and $f2.Count -ge 3) { $m.Tps = $f2[1]; $m.Mspt = $f2[2] }
        elseif ($f2[0] -ceq 'player' -and $f2.Count -ge 3) { $m.Br[$f2[1]] = ($f2[2..($f2.Count - 1)]) -join "`t"; $names.Add($f2[1]) }
    }
    # the plugin knows who is online, also those who joined before the log Lotus read
    $hms = [datetime]::Now.ToString('HH:mm:ss')
    foreach ($n in $names) { if (-not $m.Players.ContainsKey($n)) { $m.Players[$n] = $hms; $m.POrder.Add($n) } }
    foreach ($n in @($m.POrder)) { if (-not $names.Contains($n)) { Remove-LotusMccPlayer $n } }
}

# ── The console log ──────────────────────────────────────────

function script:Close-LotusMccLog {
    $m = $script:Mcc
    if ($m.Stream) { try { $m.Stream.Dispose() } catch { } }
    $m.Stream = $null
}

# Reads a log file from its start (the last 400 kB of a long one); what was read before is forgotten
function script:Open-LotusMccLog {
    param([string]$Path)
    $m = $script:Mcc
    Close-LotusMccLog
    $m.Off = 0L; $m.Part = ''; $m.LogF = $Path
    $m.Log.Clear(); $m.Events.Clear(); $m.Players.Clear(); $m.POrder.Clear()
    $m.Ready = $false; $m.LogStop = $false; $m.Progress = 0; $m.Back = 0
    $m.Dec = $script:McUtf8.GetDecoder()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try { $m.Stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete') } catch { $m.Stream = $null; return }
    if ($m.Stream.Length -gt 400000) {
        $m.Stream.Position = $m.Stream.Length - 400000
        # the rest of a cut line
        $b = [byte[]]::new(4096)
        while ($true) {
            $n = $m.Stream.Read($b, 0, 1)
            if ($n -le 0 -or $b[0] -eq 10) { break }
        }
    }
    $m.Off = $m.Stream.Position
}

# New lines since last time (a file that became shorter was started again)
function script:Read-LotusMccLog {
    $m = $script:Mcc
    if (-not $m.LogF) { return }
    $i = Get-Item -LiteralPath $m.LogF -ErrorAction SilentlyContinue
    if (-not $i) { return }
    if (-not $m.Stream -or $i.Length -lt $m.Off) { Open-LotusMccLog $m.LogF; if (-not $m.Stream) { return } }
    if ($i.Length -le $m.Off) { return }
    $m.Stream.Position = $m.Off
    $buf = [byte[]]::new(65536)
    $chars = [char[]]::new(65537)
    $sb = [System.Text.StringBuilder]::new($m.Part)
    for ($k = 0; $k -lt 64; $k++) {
        $n = $m.Stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        $c = $m.Dec.GetChars($buf, 0, $n, $chars, 0)
        [void]$sb.Append($chars, 0, $c)
    }
    $m.Off = $m.Stream.Position
    $text = $sb.ToString()
    $cut = $text.LastIndexOf("`n")
    if ($cut -lt 0) { $m.Part = $text; return }
    $m.Part = $text.Substring($cut + 1)
    foreach ($l in $text.Substring(0, $cut).Split("`n")) { Add-LotusMccLine $l }
}

# One line of the console: kept for the Log page, and what it says about players and the server
function script:Add-LotusMccLine {
    param([string]$Line)
    $m = $script:Mcc
    $l = ($Line -replace "`r", '' -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '').Replace("`t", '    ')
    $m.Log.Add($l)
    if ($m.Log.Count -gt 5000) { $m.Log.RemoveRange(0, 1000) }
    $msg = $l; $hms = ''
    if ($l -match '^\[([0-2][0-9]:[0-5][0-9]:[0-5][0-9])[^\]]*\][^:]*: (.*)$') { $hms = $Matches[1]; $msg = $Matches[2] }
    if (-not $hms) { $hms = [datetime]::Now.ToString('HH:mm:ss') }
    if ($msg -cmatch '^([A-Za-z0-9_.*-]+) joined the game$') {
        $who = $Matches[1]
        if (-not $m.Players.ContainsKey($who)) { $m.POrder.Add($who) }
        $m.Players[$who] = $hms
        Add-LotusMccEvent $hms join (T mc_ev_join '%s joined').Replace('%s', $who)
    } elseif ($msg -cmatch '^([A-Za-z0-9_.*-]+) (left the game|lost connection:.*)$') {
        $who = $Matches[1]
        if ($m.Players.ContainsKey($who)) { Remove-LotusMccPlayer $who; Add-LotusMccEvent $hms leave (T mc_ev_leave '%s left').Replace('%s', $who) }
    } elseif ($msg -cmatch '^(\[Not Secure\] |)<([^>]+)> (.*)$') {
        Add-LotusMccEvent $hms chat "<$($Matches[2])> $($Matches[3])"
    } elseif ($msg -cmatch '^([A-Za-z0-9_.*-]+) has (made the advancement|completed the challenge|reached the goal) \[(.*)\]$') {
        Add-LotusMccEvent $hms goal (T mc_ev_goal '%s: %a').Replace('%s', $Matches[1]).Replace('%a', $Matches[3])
    } elseif ($msg -cmatch '^Done \(' -or $msg -cmatch 'For help, type') {
        if (-not $m.Ready) { Add-LotusMccEvent $hms ready (T mc_ev_ready 'Server ready') }
        $m.Ready = $true; $m.Progress = 100
    } elseif ($msg -cmatch '^Starting minecraft server version ([^ ]+)') {
        if ($m.Ver -cne $Matches[1]) { $m.Ver = $Matches[1]; Save-LotusMccConf }
    } elseif ($msg -cmatch 'Preparing spawn area: ([0-9]+)%') {
        $m.Progress = [int]$Matches[1]
    } elseif ($msg -cmatch '^Stopping (the )?server') {
        $m.LogStop = $true
        Add-LotusMccEvent $hms stop (T mc_ev_stop 'Server stopping')
    } elseif ($msg -cmatch 'You need to agree to the EULA') { $m.Problem = 'eula' }
    elseif ($msg -cmatch 'FAILED TO BIND TO PORT') { $m.Problem = 'port' }
}

function script:Remove-LotusMccPlayer {
    param([string]$Name)
    $m = $script:Mcc
    [void]$m.Players.Remove($Name); [void]$m.Br.Remove($Name); [void]$m.POrder.Remove($Name)
}
function script:Add-LotusMccEvent {
    param([string]$Hms, [string]$Kind, [string]$Text)
    $m = $script:Mcc
    $m.Events.Add("$($Hms.Substring(0, [Math]::Min(5, $Hms.Length)))`t$Kind`t$Text")
    if ($m.Events.Count -gt 60) { $m.Events.RemoveRange(0, 20) }
}

# Commands typed before, for ↑ on the command line
function script:Read-LotusMccHistory {
    $m = $script:Mcc
    $m.Hist.Clear()
    $t = Read-LotusFile (Join-Path $m.S 'history')
    if ($t) { foreach ($l in $t -split "`n") { if ($l) { $m.Hist.Add($l) } } }
}
function script:Add-LotusMccHistory {
    param([string]$Line)
    $m = $script:Mcc
    [void]$m.Hist.Remove($Line); $m.Hist.Add($Line)
    if ($m.Hist.Count -gt 100) { $m.Hist.RemoveRange(0, $m.Hist.Count - 100) }
    Write-LotusFile (Join-Path $m.S 'history') (($m.Hist -join "`n") + "`n")
}

# ── Small helpers for drawing ────────────────────────────────

# Plain text cut to a width, with … when it was longer
function script:Get-LotusMccCut { param([string]$Text, [int]$N) if ($N -lt 1) { return '' }; if ($Text.Length -gt $N) { $Text.Substring(0, $N - 1) + '…' } else { $Text } }
# What is being typed: its end when it is too long (that is where the cursor is)
function script:Get-LotusMccTail { param([string]$Text, [int]$N) if ($N -lt 2) { $N = 2 }; if ($Text.Length -gt $N) { '…' + $Text.Substring($Text.Length - ($N - 1)) } else { $Text } }
# Plain text padded (and cut) to exactly a width
function script:Get-LotusMccPad { param([string]$Text, [int]$N) PadR (Get-LotusMccCut $Text $N) $N }
# Visible width of a line with color codes
function script:Get-LotusMccVw { param([string]$Text) ($Text -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '').Length }
# A line with color codes cut to a width, with … at the end
function script:Get-LotusMccClip {
    param([string]$Text, [int]$W)
    $sb = [System.Text.StringBuilder]::new(); $n = 0; $i = 0
    while ($i -lt $Text.Length -and $n -lt $W - 1) {
        if ($Text[$i] -eq [char]27) {
            $mm = [regex]::Match($Text.Substring($i, [Math]::Min(32, $Text.Length - $i)), "^$([char]27)\[[0-9;?]*[A-Za-z]")
            if ($mm.Success) { [void]$sb.Append($mm.Value); $i += $mm.Length; continue }
        }
        [void]$sb.Append($Text[$i]); $i++; $n++
    }
    $sb.ToString() + "…$([char]27)[0m"
}
# A bar of ■ and ·:  <percent> <width> <color>
function script:Get-LotusMccBar {
    param([int]$P, [int]$W, [string]$Color)
    $P = [Math]::Max(0, [Math]::Min(100, $P))
    $n = [Math]::Truncate(($P * $W + 50) / 100)
    "$Color$([string]::new([char]0x25A0, $n))$($script:Mcc.C['dim'])$([string]::new([char]0x00B7, $W - $n))$($script:Mcc.C['r'])"
}
# Ping as four bars in a color for how good it is (plain width 4)
function script:Get-LotusMccPingBars {
    param([int]$P)
    $c = $script:Mcc.C
    if ($P -lt 0) { return "$($c['dim'])····$($c['r'])" }
    $n = if ($P -lt 60) { 4 } elseif ($P -lt 150) { 3 } elseif ($P -lt 300) { 2 } else { 1 }
    $col = switch ($n) { 2 { $c['key2'] } 1 { $c['red'] } default { $c['key'] } }
    "$col$('▂▄▆█'.Substring(0, $n))$($c['dim'])$([string]::new([char]0x00B7, 4 - $n))$($c['r'])"
}
# Seconds as 3h 12m, 12m, 40s
function script:Get-LotusMccDur {
    param([long]$S)
    if ($S -ge 86400) { "$([Math]::Truncate($S / 86400))d $([Math]::Truncate($S % 86400 / 3600))h" }
    elseif ($S -ge 3600) { "$([Math]::Truncate($S / 3600))h $([Math]::Truncate($S % 3600 / 60))m" }
    elseif ($S -ge 60) { "$([Math]::Truncate($S / 60))m" }
    else { "$($S)s" }
}
# MB as "812 MB" or "1.4 GB"
function script:Get-LotusMccMb {
    param([long]$Mb)
    if ($Mb -ge 1024) { ($Mb / 1024.0).ToString('0.0', [cultureinfo]::InvariantCulture).Replace('.0', '') + ' GB' } else { "$Mb MB" }
}
# How long someone is online, from the time of their join
function script:Get-LotusMccOnlineFor {
    param([string]$Hms)
    $p = $Hms -split ':'
    if ($p.Count -lt 3) { return '' }
    $a = [int]$p[0] * 3600 + [int]$p[1] * 60 + [int]$p[2]
    $n = [datetime]::Now
    $b = $n.Hour * 3600 + $n.Minute * 60 + $n.Second
    Get-LotusMccDur (($b - $a + 86400) % 86400)
}
function script:Show-LotusMccToast { param([string]$Kind, [string]$Text) $m = $script:Mcc; $m.ToastK = $Kind; $m.Toast = $Text; $m.ToastAt = Get-LotusMccEpoch }
# The server's address for friends
function script:Get-LotusMccAddr {
    $m = $script:Mcc
    $port = if ($m.Prop.ContainsKey('server-port') -and $m.Prop['server-port']) { $m.Prop['server-port'] } else { '25565' }
    if ($port -ceq '25565' -and $m.Lan) { return $m.Lan }
    "$(if ($m.Lan) { $m.Lan } else { 'localhost' }):$port"
}

# ── The window ───────────────────────────────────────────────

function script:Invoke-LotusMccLoop {
    $m = $script:Mcc
    while ($true) {
        $now = Get-LotusMccNow
        Read-LotusMccLog
        if ($now - $m.T1 -ge 1) {
            $m.T1 = $now
            $size = Get-LotusSize
            $m.W = $size[0]; $m.H = $size[1]
            Update-LotusMccProbe
            Update-LotusMccBridge
            Update-LotusMccProps
            # after a stop: leave, or start again for a restart
            if ($m.State -cin 'stopped', 'crashed') {
                if ($m.Delete) { Remove-LotusMccNow; break }
                if ($m.Leave) { break }
                if ($m.Restart) { $m.Restart = $false; [void](Start-LotusMccServer) }
            }
            if ($m.State -ceq 'stopping' -and $m.StopAt -and (Get-LotusMccEpoch) - $m.StopAt -eq 60) { Show-LotusMccToast info (T mc_still_stopping 'Still stopping – s ends it now') }
        }
        if ($now - $m.T2 -ge 2) { $m.T2 = $now; Update-LotusMccSample }
        Update-LotusMccSearch
        if ($m.ToastAt -and (Get-LotusMccEpoch) - $m.ToastAt -gt 6) { $m.Toast = ''; $m.ToastAt = 0 }
        Show-LotusMccFrame
        # the world moves on the stats page; elsewhere the window only changes with the server
        $wait = if ($m.Page -eq 1 -and -not $m.Ask -and -not $m.In) { 0.12 } elseif ($m.In -or $m.RLoading) { 0.2 } else { 0.5 }
        $key = Read-LotusMccKey $wait
        if ($key -ceq 'timeout') { continue }
        if ((Invoke-LotusMccKey $key) -eq 9) { break }
    }
}

# One key, by name (Read-LotusKeyX), Ctrl-C as "ctrlc"; a keyboard that runs dry (the tests) leaves at once
function script:Read-LotusMccKey {
    param([double]$Wait)
    $m = $script:Mcc
    if ($script:KeyQueueActive) {
        if ($script:KeyQueue.Count) { $k = $script:KeyQueue.Dequeue() }
        else { $m.Fails++; if ($m.Fails -gt 3) { return 'ctrlc' }; Start-Sleep -Milliseconds 50; return 'timeout' }
    } else { $k = Read-LotusKeyX $Wait }
    switch -CaseSensitive ($k) {
        'interrupt' { return 'ctrlc' }
        'backtab' { return 'btab' }
    }
    $k
}

# A key → 9 = leave the control center
function script:Invoke-LotusMccKey {
    param([string]$Key)
    $m = $script:Mcc
    if ($m.In) { Invoke-LotusMccInputKey $Key; return 0 }
    if ($m.Ask) { return Invoke-LotusMccAskKey $Key }
    switch -CaseSensitive ($Key) {
        'ctrlc' { return Exit-LotusMcc }
        { $_ -cin 'q', 'Q' } { if ($m.Page -eq 2 -and $m.Sub) { $m.Sub = ''; return 0 }; return Exit-LotusMcc }
        'tab' { $m.Page = $m.Page % 3 + 1; return 0 }
        'btab' { $m.Page = ($m.Page + 1) % 3 + 1; return 0 }
        { $_ -cin '1', '2', '3' } { if (-not $m.Sub -or $m.Page -ne 2) { $m.Page = [int]$Key; return 0 } }
    }
    switch ($m.Page) {
        1 { Invoke-LotusMccStatsKey $Key }
        2 { if ($m.Sub -ceq 'plugins') { Invoke-LotusMccPluginsKey $Key } else { Invoke-LotusMccSettingsKey $Key } }
        3 { Invoke-LotusMccLogKey $Key }
    }
    $inPlugins = $m.Page -eq 2 -and $m.Sub -ceq 'plugins'
    if ($Key -cin 's', 'S' -and -not $inPlugins) {
        if ($m.State -cin 'stopped', 'crashed') { [void](Start-LotusMccServer) }
        elseif ($m.State -ceq 'stopping') {
            # still stopping after a while: s ends it (the stop command saved the world first)
            if ($m.Pid -and (Get-LotusMccEpoch) - $m.StopAt -gt 20) { Stop-Process -Id $m.Pid -Force -ErrorAction SilentlyContinue; Show-LotusMccToast info (T mc_forced 'Ended') }
        }
        elseif ($m.POrder.Count) { $m.Ask = 'stop' }
        else { Stop-LotusMccServer }
    } elseif ($Key -cin 'r', 'R' -and -not $inPlugins) {
        if ($m.State -cin 'stopped', 'crashed') { [void](Start-LotusMccServer) }
        elseif ($m.State -cin 'running', 'starting', 'preparing') {
            if ($m.POrder.Count) { $m.Ask = 'restart' } elseif ($m.Mode -ceq 'external') { Stop-LotusMccServer } else { $m.Restart = $true; Stop-LotusMccServer }
        }
    } elseif ($Key -cin 'o', 'O' -and -not $inPlugins) { Open-LotusMccFolder }
    elseif ($Key -cin 'e', 'E' -and $m.Problem -ceq 'eula') { $m.Ask = 'eula' }
    0
}

function script:Exit-LotusMcc {
    $m = $script:Mcc
    # leaving while a delete waits for the stop: the delete is called off, the server stays stopped
    if ($m.Delete) { $m.Delete = $false; $m.Leave = $false; Show-LotusMccToast info (T mc_del_off 'Deleting called off'); return 0 }
    if ($m.Mode -ceq 'ours' -and $m.State -cin 'running', 'starting', 'preparing') { $m.Ask = 'quit'; return 0 }
    if ($m.State -ceq 'stopping') { $m.Leave = $true; return 0 }
    9
}

function script:Open-LotusMccFolder {
    if ((Open-LotusTarget $script:Mcc.Dir) -eq 0) { Show-LotusMccToast ok (T mc_opened 'Opened') }
    else { Show-LotusMccToast err (T mc_err_open 'The folder could not be opened') }
}

# The question in the bottom line → 9 = leave
function script:Invoke-LotusMccAskKey {
    param([string]$Key)
    $m = $script:Mcc
    $ask = $m.Ask
    $m.Ask = ''
    $yes = $Key -cin 'y', 'Y', 'j', 'J'
    switch -Wildcard -CaseSensitive ($ask) {
        'quit' {
            if ($Key -cin 'enter', 'q', 'y') { return 9 }
            if ($Key -cin 's', 'S') { $m.Leave = $true; Stop-LotusMccServer }
        }
        'stop' { if ($yes -or $Key -ceq 'enter') { Stop-LotusMccServer } }
        'restart' { if ($yes -or $Key -ceq 'enter') { if ($m.Mode -cne 'external') { $m.Restart = $true }; Stop-LotusMccServer } }
        'eula' {
            if ($yes) {
                Write-LotusFile (Join-Path $m.Dir 'eula.txt') "eula=true`n"
                Write-LotusLog INFO minecraft "EULA accepted for $($m.Name)"
                $m.Problem = ''
                [void](Start-LotusMccServer)
            }
        }
        'icondel' {
            if ($yes) {
                Remove-Item -LiteralPath (Join-Path $m.Dir 'server-icon.png') -Force -ErrorAction SilentlyContinue
                Set-LotusMccChanged
                Show-LotusMccToast ok (T mc_icon_removed 'Icon removed')
            }
        }
        'remove:*' {
            if ($yes) {
                $name = $ask.Substring(7)
                if (Remove-LotusMcPlugin $m.Dir $name) { Set-LotusMccChanged; Show-LotusMccToast ok (T mc_pl_removed '%s removed').Replace('%s', $name) }
                else { Show-LotusMccToast err (T mc_err_remove 'It could not be removed') }
                Update-LotusMccInstalled
            }
        }
        'player:*' {
            $p = $ask.Substring(7)
            $cmd = switch -CaseSensitive ($Key) { '1' { "op $p" } '2' { "deop $p" } '3' { "kick $p" } '4' { "ban $p" } '5' { "gamemode creative $p" } '6' { "gamemode survival $p" } '7' { "whitelist add $p" } default { '' } }
            if ($cmd) { if (Send-LotusMccCommand $cmd) { Show-LotusMccToast ok "› $cmd" } else { Show-LotusMccToast err (T mc_err_cmd 'The command could not be sent') } }
        }
    }
    0
}

# Something that only counts after a restart
function script:Set-LotusMccChanged { if ($script:Mcc.State -cin 'running', 'starting', 'preparing') { $script:Mcc.Changed = $true } }

# ── Text input in the bottom area: commands, the description, dropped files, the search ──

function script:Start-LotusMccInput {
    param([string]$Kind, [string]$Label, [string]$Text = '')
    $m = $script:Mcc
    $m.In = $Kind; $m.InLabel = $Label; $m.InText = $Text; $m.HistI = $m.Hist.Count
}

function script:Invoke-LotusMccInputKey {
    param([string]$Key)
    $m = $script:Mcc
    $kind = $m.In
    switch -CaseSensitive -Regex ($Key) {
        '^(timeout|ignore|tab|btab|left|right|home|end|pgup|pgdn|del)$' { break }
        '^(esc|ctrlc)$' { $m.In = ''; break }
        '^back$' { if ($m.InText.Length) { $m.InText = $m.InText.Substring(0, $m.InText.Length - 1) }; break }
        '^space$' { $m.InText += ' '; break }
        '^up$' {
            if ($kind -ceq 'cmd' -and $m.HistI -gt 0) { $m.HistI--; $m.InText = $m.Hist[$m.HistI] }
            elseif ($kind -ceq 'search') { $m.In = ''; Invoke-LotusMccPluginsKey up }
            break
        }
        '^down$' {
            if ($kind -ceq 'cmd' -and $m.HistI -lt $m.Hist.Count) { $m.HistI++; $m.InText = if ($m.HistI -lt $m.Hist.Count) { $m.Hist[$m.HistI] } else { '' } }
            elseif ($kind -ceq 'search') { $m.In = ''; Invoke-LotusMccPluginsKey down }
            break
        }
        '^enter$' { $m.In = ''; Complete-LotusMccInput $kind $m.InText; break }
        default { if ($Key.Length -eq 1 -and -not [char]::IsControl($Key[0]) -and $m.InText.Length -lt 400) { $m.InText += $Key } }
    }
    # keys that are already waiting (a pasted or dropped path) come in before the next frame
    if ($m.In -and $Key -cnotin 'timeout', 'enter', 'esc' -and -not $script:KeyQueueActive) {
        try {
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Enter') { $kind = $m.In; $m.In = ''; Complete-LotusMccInput $kind $m.InText; break }
                elseif ($k.Key -eq 'Backspace') { if ($m.InText.Length) { $m.InText = $m.InText.Substring(0, $m.InText.Length - 1) } }
                elseif ($k.Key -eq 'Escape') { $m.In = ''; break }
                elseif ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) { $m.InText += $k.KeyChar }
            }
        } catch { }
    }
    if ($m.In -ceq 'search') { $m.Q = $m.InText; $m.QAt = Get-LotusMccNow }
}

function script:Complete-LotusMccInput {
    param([string]$Kind, [string]$Text)
    $m = $script:Mcc
    switch -CaseSensitive ($Kind) {
        'cmd' {
            $Text = $Text -replace '^[\s/]+', ''
            if (-not $Text) { return }
            Add-LotusMccHistory $Text
            if (Send-LotusMccCommand $Text) { $m.Back = 0 } else { Show-LotusMccToast err (T mc_err_cmd 'The command could not be sent') }
        }
        'motd' {
            $Text = $Text -replace '[\p{Cc}]', ''
            Set-LotusMccProp 'motd' $Text
            Set-LotusMccChanged
            Show-LotusMccToast ok (T mc_motd_saved 'Description saved')
            Write-LotusLog INFO minecraft "Description changed for $($m.Name)"
        }
        'icon' {
            if (-not $Text.Trim()) { return }
            $w = @(Split-LotusShellWords $Text)
            if ($w.Count) { Set-LotusMccIcon (ConvertTo-LotusCleanPath $w[0]) }
        }
        'drop' {
            if (-not $Text.Trim()) { return }
            if (Add-LotusMcPluginJars $m.Dir $Text) {
                Set-LotusMccChanged
                Show-LotusMccToast ok (T mc_pl_added '%s added').Replace('%s', ($script:McpDone -join ', '))
                if ($script:McpErr) { Show-LotusMccToast err "$($script:McpDone -join ', ') ✓ · $($script:McpErr)" }
            } else { Show-LotusMccToast err $(if ($script:McpErr) { $script:McpErr } else { T mc_err_drop 'That is not a plugin (.jar)' }) }
            Update-LotusMccInstalled
        }
        'search' { $m.Q = $Text; $m.QAt = 0 }
        'delete' {
            # only the exact name deletes – anything else changes nothing
            if ($Text -cne $m.Name) { Show-LotusMccToast info (T mc_del_wrong 'Not deleted – the name did not match'); return }
            $m.Delete = $true; $m.Leave = $true; $m.Restart = $false; $m.T1 = 0
            if ($m.State -cin 'stopped', 'crashed') { return }
            Show-LotusMccToast info (T mc_del_stopping 'Stopping the server first …')
            if ($m.Mode -ceq 'external') { $m.Delete = $false; $m.Leave = $false; Stop-LotusMccServer; return }
            Stop-LotusMccServer
        }
    }
}

# ── Deleting a server ────────────────────────────────────────

function script:Get-LotusMcHome {
    if ($env:LOTUS_MC_HOME) { return [IO.Path]::GetFullPath((ConvertTo-LotusCleanPath $env:LOTUS_MC_HOME)) }
    Join-Path (Get-LotusHome) 'Minecraft'
}

# Can this folder be deleted at all? Only a server folder right in the Minecraft folder (start.cmd in it), no link or
# junction: never the Minecraft folder itself, the home folder or anything else. Asked before anything is stopped.
# → $true, or $false with $script:McpErr
function script:Test-LotusMccCanDelete {
    param([string]$Dir)
    $script:McpErr = ''
    $home_ = (Get-LotusMcHome).TrimEnd('\', '/')
    $ok = $false
    try {
        $i = Get-Item -LiteralPath $Dir -Force -ErrorAction Stop
        $full = $i.FullName.TrimEnd('\', '/')
        $parent = (Split-Path -Parent $full).TrimEnd('\', '/')
        $ok = $i.PSIsContainer -and -not ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            [string]::Equals($parent, $home_, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath (Join-Path $full 'start.cmd') -PathType Leaf)
    } catch { }
    if (-not $ok) { $script:McpErr = (T mc_del_notserver 'Only a server folder right in %s can be deleted (no link)').Replace('%s', (Format-LotusHomePath $home_)) }
    $ok
}

# Does something of the server still run? Its java or the runner (by the pid files), a java with this server.jar, a
# window that runs its start.cmd
function script:Test-LotusMccBusy {
    param([string]$Dir)
    $s = Join-Path $Dir '.lotus'
    foreach ($f in @(@('pid', @('java', 'javaw')), @('wrapper', @('pwsh', 'powershell')))) {
        $n = Get-LotusInt (Read-LotusFile (Join-Path $s $f[0])) 0
        if (Test-LotusMccProc $n $f[1]) { return $true }
    }
    if (-not $IsWindows) { return $false }
    $needle = $Dir.TrimEnd('\').ToLowerInvariant() + '\'
    try {
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)) {
            if ($p.ProcessId -eq $PID) { continue }
            $cl = ([string]$p.CommandLine).ToLowerInvariant()
            if ($cl.Contains($needle) -and ($cl -match 'server\.jar|start\.cmd|run\.ps1|paperclip')) { return $true }
        }
    } catch { }
    $false
}

# The folder of a server goes to the Recycle Bin (it can come back from there). A folder too large for it is never
# deleted for good instead: Windows asks first, and a no deletes nothing. → $true, or $false with $script:McpErr
function script:Remove-LotusMccFolder {
    param([string]$Dir)
    if (-not (Test-LotusMccCanDelete $Dir)) { return $false }
    if (Test-LotusMccBusy $Dir) { $script:McpErr = T mc_del_busy_win 'Something of the server still runs – stop it (or close the window of its start.cmd), then delete again.'; return $false }
    $r = Remove-LotusFolderToRecycleBin $Dir
    if ($r -eq 0 -and -not (Test-Path -LiteralPath $Dir)) { return $true }
    $script:McpErr = if ($r -eq 2) { T mc_del_norecycle_win 'This system has no Recycle Bin Lotus can use – delete the folder yourself.' } else { T mc_del_nomove_win 'It could not be moved to the Recycle Bin – nothing was deleted.' }
    $false
}

# Deletes the server of this control center once it is stopped → $Mcc.Deleted
function script:Remove-LotusMccNow {
    $m = $script:Mcc
    Close-LotusMccLog
    if (Remove-LotusMccFolder $m.Dir) {
        $m.Deleted = 'trash'
        Write-LotusLog INFO minecraft "Server deleted: $($m.Name) (Recycle Bin)"
    } else {
        $m.Deleted = ''
        Write-LotusLog WARN minecraft "Server $($m.Name) not deleted: $($script:McpErr)"
    }
}
function script:Get-LotusMccDeletedText { (T mc_del_trash_win '%s is in the Recycle Bin').Replace('%s', $script:Mcc.Name) }

# Without the control center (/minecraft → Delete a server): what goes, the name typed to be sure, a running server
# stopped first, then the folder to the Recycle Bin
function script:Remove-LotusMcServer {
    param([string]$Dir)
    Import-LotusLangGroup mc
    $Dir = [IO.Path]::GetFullPath($Dir)
    if (-not (Test-Path -LiteralPath (Join-Path $Dir 'start.cmd') -PathType Leaf)) { Write-LotusError (T mc_noserver 'This is not a Lotus Minecraft server') $Dir; return (St 1) }
    $name = Split-Path -Leaf $Dir
    if (-not (Test-LotusMccCanDelete $Dir)) { Write-LotusError ((T mc_err_del 'Lotus could not delete %s').Replace('%s', $name)) $script:McpErr; return (St 1) }
    Initialize-LotusMcc $Dir
    $m = $script:Mcc
    Update-LotusMccProbe
    $mb = 0L
    try { foreach ($f in [IO.Directory]::EnumerateFiles($Dir, '*', [IO.SearchOption]::AllDirectories)) { $mb += ([IO.FileInfo]::new($f)).Length } } catch { }
    Write-LotusHeader 'Minecraft' (T mc_del_title 'Delete %s').Replace('%s', $name)
    Write-LotusText (T mc_del_what 'The server %s with its worlds, settings and plugins:').Replace('%s', $name)
    Write-LotusDim "  $(Format-LotusPath $Dir)  ·  $(Get-LotusMccMb ([long]($mb / 1MB)))"
    if ($m.State -cin 'running', 'starting', 'preparing', 'stopping') { Write-LotusWarn (T mc_del_running 'It is running – Lotus stops it first.') }
    Write-LotusDim "  $(T mc_del_where_win 'It goes to the Recycle Bin – you can put it back from there.')"
    Write-LotusBlank
    if (-not (Test-LotusTty)) { Write-LotusDim '  (no keyboard – nothing was deleted)'; return (St 1) }
    $typed = Read-LotusInput ((T mc_del_type 'Type %s to delete it').Replace('%s', $name))
    if ($typed -cne $name) { Write-LotusInfo (T mc_del_wrong 'Not deleted – the name did not match'); return (St 1) }
    if ($m.State -cin 'running', 'starting', 'preparing', 'stopping') {
        if ($m.Mode -ceq 'external') { Write-LotusError ((T mc_err_del 'Lotus could not delete %s').Replace('%s', $name)) (T mc_ext_stop_win 'This server runs in a window of its own – type stop there.'); return (St 1) }
        Write-LotusStep (T mc_del_stopping 'Stopping the server first …')
        $m.Delete = $true
        Stop-LotusMccServer
        for ($i = 0; $i -lt 900; $i++) {
            Start-Sleep -Milliseconds 100
            Update-LotusMccProbe
            if ($m.State -cin 'stopped', 'crashed') { break }
            # after a minute: ended now (the stop command saved the world first)
            if ($i -eq 600 -and $m.Pid) { Stop-Process -Id $m.Pid -Force -ErrorAction SilentlyContinue }
        }
        if ($m.State -cnotin 'stopped', 'crashed') { Write-LotusError ((T mc_err_del 'Lotus could not delete %s').Replace('%s', $name)) (T mc_del_still 'The server did not stop.'); return (St 1) }
    }
    Close-LotusMccLog
    $m.Delete = $true
    Remove-LotusMccNow
    if (-not $m.Deleted) { Write-LotusError ((T mc_err_del 'Lotus could not delete %s').Replace('%s', $name)) $script:McpErr; return (St 1) }
    Write-LotusSuccess (Get-LotusMccDeletedText)
    Write-LotusBlank
    St 0
}

# ── Page 1: Stats ────────────────────────────────────────────

function script:Invoke-LotusMccStatsKey {
    param([string]$Key)
    $m = $script:Mcc
    $n = $m.POrder.Count
    switch -CaseSensitive ($Key) {
        'up' { if ($n) { $m.Sel = if ($m.Sel -gt 1) { $m.Sel - 1 } else { $n } } }
        'down' { if ($n) { $m.Sel = if ($m.Sel -lt $n) { $m.Sel + 1 } else { 1 } } }
        'enter' {
            if (-not $n) { return }
            if ($m.Sel -gt $n) { $m.Sel = $n }
            if ($m.Mode -ceq 'ours') { $m.Ask = "player:$($m.POrder[$m.Sel - 1])" } else { Show-LotusMccToast info (T mc_external_cmd 'Started elsewhere – commands go into its own window') }
        }
    }
}

# The state of the server in a few words, with its color
function script:Get-LotusMccStateText {
    $m = $script:Mcc; $c = $m.C
    $sp = @('◐', '◓', '◑', '◒')[[long][Math]::Truncate((Get-LotusMccNow) * 4) % 4]
    $t = switch ($m.State) {
        'running' {
            "$($c['key'])● $(T mc_st_running 'running')$($c['r'])$($c['dim']) · $(Get-LotusMccDur $m.Up)$($c['r'])" + $(if ($m.Mode -ceq 'external') { "$($c['dim']) · $(T mc_st_external 'started elsewhere')$($c['r'])" })
        }
        'starting' { "$($c['key2'])$sp $(T mc_st_starting 'starting')$($c['r'])" + $(if ($m.Progress) { "$($c['dim']) · $($m.Progress) %$($c['r'])" }) }
        'preparing' { "$($c['key2'])$sp $(T mc_st_preparing 'preparing')$($c['r'])" }
        'stopping' { "$($c['key2'])$sp $(T mc_st_stopping 'stopping')$($c['r'])" }
        'crashed' { "$($c['red'])✗ $(T mc_st_crashed 'stopped with an error')$($c['r'])" }
        default { "$($c['dim'])○ $(T mc_st_stopped 'stopped')$($c['r'])" }
    }
    if ($m.Problem -ceq 'eula') { $t = "$($c['red'])✗ $(T mc_pr_eula 'EULA not accepted')$($c['r'])" }
    elseif ($m.Problem -ceq 'port' -and $m.State -cne 'running') {
        $port = if ($m.Prop.ContainsKey('server-port')) { $m.Prop['server-port'] } else { '25565' }
        $t = "$($c['red'])✗ $((T mc_pr_port 'Port %s is in use').Replace('%s', $port))$($c['r'])"
    }
    $t
}

# The info column: label and value lines
function script:Get-LotusMccInfoRows {
    $m = $script:Mcc; $c = $m.C
    $k = "$([char]27)[1;$($script:C['key'])m"; $r = $c['r']; $d = $c['dim']
    $rows = [System.Collections.Generic.List[string]]::new()
    $maxp = Get-LotusInt $(if ($m.Prop.ContainsKey('max-players')) { $m.Prop['max-players'] }) 20
    $n = $m.POrder.Count
    $lab = { param($key, $def) "$k$(PadR (T $key $def) 9)$r" }
    $rows.Add("$(& $lab mc_i_status 'Status') $(Get-LotusMccStateText)")
    $type = if ($m.Type) { $m.Type.Substring(0, 1).ToUpperInvariant() + $m.Type.Substring(1) } else { '' }
    $rows.Add("$(& $lab mc_i_server 'Server') $type $(if ($m.Ver) { $m.Ver } else { '?' })")
    $rows.Add("$(& $lab mc_i_players 'Players') $(PadR "$n / $maxp" 8) $(Get-LotusMccBar $(if ($maxp) { [Math]::Truncate($n * 100 / $maxp) } else { 0 }) 10 $c['key'])")
    if ($m.Bridge -and $m.Tps -cne '-') {
        $tp = Get-LotusInt (($m.Tps -split '[.,]')[0]) 20
        $col = if ($tp -lt 12) { $c['red'] } elseif ($tp -lt 18) { $c['key2'] } else { $c['key'] }
        $rows.Add("$(& $lab mc_i_tps 'TPS') $(PadR $m.Tps 8) $(Get-LotusMccBar ($tp * 5) 10 $col) $d$($m.Mspt) ms$r")
    } elseif ($m.Type -ceq 'paper') { $rows.Add("$(& $lab mc_i_tps 'TPS') $d–  $(if ($m.Pid) { T mc_tps_wait 'waiting for LotusBridge' })$r") }
    else { $rows.Add("$(& $lab mc_i_tps 'TPS') $d–  $(T mc_tps_paper 'with Paper')$r") }
    if ($m.Pid -and $m.Rss) {
        $used = Get-LotusMccMb $m.Rss
        if ($m.Xmx) { $rows.Add("$(& $lab mc_i_memory 'Memory') $(PadR $used 8) $(Get-LotusMccBar ([Math]::Truncate($m.Rss * 100 / $m.Xmx)) 10 $c['accent']) $d$(T mc_of 'of') $(Get-LotusMccMb $m.Xmx)$r") }
        else { $rows.Add("$(& $lab mc_i_memory 'Memory') $used") }
        $rows.Add("$(& $lab mc_i_cpu 'CPU') $($m.Cpu) %")
    } else {
        $rows.Add("$(& $lab mc_i_memory 'Memory') $d–$r")
        $rows.Add("$(& $lab mc_i_cpu 'CPU') $d–$r")
    }
    if ($m.WorldKb -ge 0) { $rows.Add("$(& $lab mc_i_world 'World') $(Get-LotusMccMb ([long]($m.WorldKb / 1024)))") }
    else { $rows.Add("$(& $lab mc_i_world 'World') $d$(if ($m.WorldKb -eq -2) { '–' } else { '…' })$r") }
    $rows.Add("$(& $lab mc_i_address 'Address') $(Get-LotusMccAddr)$d  · localhost $(T mc_on_mac 'on this Mac')$r")
    , $rows.ToArray()
}

function script:Add-LotusMccStatsPage {
    param($Out, [int]$W, [int]$H)
    $m = $script:Mcc; $c = $m.C
    $d = $c['dim']; $r = $c['r']; $b = $c['border']
    $base = $Out.Count
    $info = Get-LotusMccInfoRows
    $players = $m.POrder.Count
    $moving = $m.State -cin 'running', 'starting'
    if ($W -ge 78 -and $H -ge 15) {
        # the world on the left, the numbers next to it
        $aw = [Math]::Max(16, [Math]::Min(64, $W - 62)); $ar = [Math]::Max(6, [Math]::Min(12, $H - 9))
        $art = Get-LotusMcWorldFrame $aw $ar $players $moving
        $label = " $(T mc_world 'World') "
        $Out.Add("  $b╭─$label$([string]::new([char]0x2500, [Math]::Max(0, $aw - 1 - $label.Length)))╮$r")
        for ($i = 0; $i -lt $ar; $i++) { $Out.Add("  $b│$r$($art[$i])$b│$r   $(if ($i -lt $info.Count) { $info[$i] })") }
        $Out.Add("  $b╰$([string]::new([char]0x2500, $aw))╯$r   $(if ($ar -lt $info.Count) { $info[$ar] })")
        for ($i = $ar + 1; $i -lt $info.Count; $i++) { $Out.Add("  $(PadR '' ($aw + 2))   $($info[$i])") }
    } else {
        foreach ($row in $info) { $Out.Add("  $row") }
        $ar = $H - $info.Count - 9
        if ($ar -ge 3) {
            $art = Get-LotusMcWorldFrame ($W - 4) ([Math]::Min(6, $ar)) $players $moving
            $Out.Add('')
            foreach ($row in $art) { $Out.Add("  $row") }
        }
    }
    $Out.Add('')
    # players online, with ping
    $a = "$([char]27)[1;$($script:C['accent'])m"
    $Out.Add("  $a$((T mc_players_online 'Players online').ToUpper())$r$d  $players$r")
    $left = $H - ($Out.Count - $base) - 1
    if ($players -eq 0) {
        if ($m.State -ceq 'running') { $Out.Add("    $d$((T mc_nobody 'Nobody yet – friends join with %s').Replace('%s', (Get-LotusMccAddr)))$r") } else { $Out.Add("    $d–$r") }
    } else {
        if ($m.Sel -gt $players) { $m.Sel = $players }
        $maxrows = [Math]::Max(1, $(if ($left -gt 8) { $left - 4 } else { $left }))
        $shown = 0
        for ($i = 1; $i -le $players -and $shown -lt $maxrows; $i++) {
            $p = $m.POrder[$i - 1]
            if ($m.Br.ContainsKey($p)) {
                $bf = $m.Br[$p] -split "`t"
                $pingtxt = "$(Get-LotusMccPingBars (Get-LotusInt $bf[0] -1)) $(PadL $bf[0] 4) ms"
                $extra = "$($bf[3]) · ♥ $($bf[2]) · $($bf[1])"
            } else { $pingtxt = "$(Get-LotusMccPingBars -1)    – ms"; $extra = '' }
            $since = Get-LotusMccOnlineFor $m.Players[$p]
            $nm = Get-LotusMccPad $p 18
            $mark = if ($i -eq $m.Sel -and $m.Page -eq 1) { "$($c['accent'])›$r $($c['B'])$nm$r" } else { "  $nm" }
            $Out.Add("   $mark $pingtxt   $(PadL $since 7)   $d$(Get-LotusMccCut $extra ($W - 52))$r")
            $shown++
        }
        if ($players -gt $shown) { $Out.Add("     $d+ $($players - $shown)$r") }
        if (-not $m.Bridge) { $Out.Add("    $d$(if ($m.Type -ceq 'paper') { T mc_ping_restart 'Ping and TPS: after the next start' } else { T mc_ping_paper 'Ping and TPS come with Paper' })$r") }
    }
    # the newest events, as many as fit
    $left = $H - ($Out.Count - $base) - 2
    if ($left - 2 -gt $m.Events.Count) { $left = $m.Events.Count + 2 }
    if ($left -ge 3 -and $m.Events.Count) {
        $Out.Add('')
        $Out.Add("  $a$((T mc_latest 'Latest').ToUpper())$r")
        $from = [Math]::Max(0, $m.Events.Count - ($left - 2))
        for ($i = $from; $i -lt $m.Events.Count; $i++) {
            $e = $m.Events[$i] -split "`t", 3
            $col = switch ($e[1]) { { $_ -cin 'join', 'ready' } { $c['key'] } { $_ -cin 'leave', 'stop' } { $d } 'goal' { $c['salute'] } 'chat' { $c['accent'] } default { '' } }
            $Out.Add("    $d$($e[0])$r  $col$(Get-LotusMccCut $e[2] ($W - 14))$r")
        }
    }
}

# ── Page 2: Settings ─────────────────────────────────────────

function script:Invoke-LotusMccSettingsKey {
    param([string]$Key)
    $m = $script:Mcc
    switch -CaseSensitive -Regex ($Key) {
        '^up$' { $m.SSel = if ($m.SSel -gt 1) { $m.SSel - 1 } else { 5 }; break }
        '^down$' { $m.SSel = if ($m.SSel -lt 5) { $m.SSel + 1 } else { 1 }; break }
        '^(enter|right)$' {
            switch ($m.SSel) {
                1 { Start-LotusMccInput icon (T mc_icon_drop 'Drop a picture into the window, or type its path') }
                2 { Start-LotusMccInput motd (T mc_motd_label 'Description') (Get-LotusMccMotd) }
                3 { $m.Sub = 'plugins'; $m.PSel = 1; Update-LotusMccInstalled; if ($m.Type -ceq 'paper' -and $m.QSent -ceq '-') { $m.Q = ''; $m.QAt = 0 } }
                4 { Open-LotusMccFolder }
                5 {
                    if ($m.Delete) { break }
                    # a folder that cannot be deleted is said so before anything is stopped
                    if (Test-LotusMccCanDelete $m.Dir) { Start-LotusMccInput delete ((T mc_del_type 'Type %s to delete it').Replace('%s', $m.Name)) }
                    else { Show-LotusMccToast err $script:McpErr }
                }
            }
            break
        }
        '^(x|X|del|back)$' { if ($m.SSel -eq 1 -and (Test-Path -LiteralPath (Join-Path $m.Dir 'server-icon.png'))) { $m.Ask = 'icondel' }; break }
    }
}

# A picture as the server icon: the middle square, 64 × 64 pixels, PNG (Windows' own drawing library)
function script:Set-LotusMccIcon {
    param([string]$Src)
    $m = $script:Mcc
    if (-not (Test-Path -LiteralPath $Src -PathType Leaf)) { Show-LotusMccToast err (T mc_err_nofile 'There is no file %s').Replace('%s', (Split-Path -Leaf $Src)); return }
    $tmp = Join-Path $m.S 'icon-new.png'
    $st = Save-LotusImageSquare $Src 64 $tmp
    if ($st -eq 0) {
        Move-Item -LiteralPath $tmp -Destination (Join-Path $m.Dir 'server-icon.png') -Force
        $m.IconKey = ''
        Set-LotusMccChanged
        Show-LotusMccToast ok (T mc_icon_saved 'Icon saved')
        Write-LotusLog INFO minecraft "Server icon set for $($m.Name) from $(Split-Path -Leaf $Src)"
    } else {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Show-LotusMccToast err (T mc_err_image 'Lotus could not read %s as a picture').Replace('%s', (Split-Path -Leaf $Src))
    }
}

# The icon as character art, 12 × 6 (the grass block when there is none)
function script:Update-LotusMccIconArt {
    $m = $script:Mcc
    $f = Join-Path $m.Dir 'server-icon.png'
    $i = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
    $key = if ($i) { "$($i.LastWriteTimeUtc.Ticks) $($i.Length) $($script:Mode)" } else { 'none' }
    if ($key -ceq $m.IconKey -and $m.Icon.Count) { return }
    $m.IconKey = $key
    if ($i) {
        $art = @(Get-LotusImageArt $f 12 6)
        if ($art.Count) { $m.Icon = $art; return }
    }
    $m.Icon = @(Get-LotusMcWorldIcon)
}

# The server as it shows in Minecraft's server list → lines into $Out
function script:Add-LotusMccPreview {
    param($Out, [int]$W)
    $m = $script:Mcc; $c = $m.C
    if ($W -gt 70) { $W = 70 }
    $b = $c['border']; $r = $c['r']; $d = $c['dim']
    Update-LotusMccIconArt
    $ml = @((Get-LotusMccMotd).Replace('\n', "`n") -split "`n")
    $maxp = Get-LotusInt $(if ($m.Prop.ContainsKey('max-players')) { $m.Prop['max-players'] }) 20
    $inner = $W - 4
    $count = if ($m.State -ceq 'running') { "$($m.POrder.Count)/$maxp" } else { T mc_offline 'offline' }
    $ping = Get-LotusMccPingBars $(if ($m.State -ceq 'running') { 20 } else { -1 })
    $tw = $inner - 14 - $count.Length - 8
    $text = @("$($c['B'])$(Get-LotusMccPad $m.Name $tw)$r  $d$count$r  $ping", (Get-LotusMccPad $ml[0] ($inner - 14)), "$d$(Get-LotusMccPad $(if ($ml.Count -gt 1) { $ml[1] } else { '' }) ($inner - 14))$r")
    $title = " $(T mc_preview 'In the server list') "
    $Out.Add("  $b╭─$r$d$title$r$b$([string]::new([char]0x2500, [Math]::Max(0, $inner + 1 - $title.Length)))╮$r")
    for ($i = 1; $i -le 6; $i++) {
        $ic = if ($i - 1 -lt $m.Icon.Count) { $m.Icon[$i - 1] } else { PadR '' 12 }
        if ($i -ge 2 -and $i -le 4) {
            $t = $text[$i - 2]
            $Out.Add("  $b│$r $ic$r  $t$(PadR '' ($inner - 13 - (Get-LotusMccVw $t)))$b│$r")
        } else { $Out.Add("  $b│$r $ic$r  $(PadR '' ($inner - 13))$b│$r") }
    }
    $Out.Add("  $b╰$([string]::new([char]0x2500, $inner + 2))╯$r")
}

function script:Add-LotusMccSettingsPage {
    param($Out, [int]$W, [int]$H)
    $m = $script:Mcc; $c = $m.C
    if ($m.Sub -ceq 'plugins') { Add-LotusMccPluginsPage $Out $W $H; return }
    $r = $c['r']; $d = $c['dim']; $a = "$([char]27)[1;$($script:C['accent'])m"
    $base = $Out.Count
    $nplug = @(Get-ChildItem -LiteralPath (Join-Path $m.Dir 'plugins') -Filter '*.jar' -File -ErrorAction SilentlyContinue).Count
    $motd = Get-LotusMccCut (Get-LotusMccMotd) ($W - 30)
    $icon = if (Test-Path -LiteralPath (Join-Path $m.Dir 'server-icon.png')) { 'server-icon.png · 64 × 64' } else { T mc_icon_none 'none – the grass block' }
    $plug = if ($m.Type -ceq 'paper') { (T mc_pl_count '%d installed').Replace('%d', [string]$nplug) } else { T mc_pl_vanilla 'only with Paper' }
    # (commas: without them the rows would run together into one list of words)
    $items = @(
        @((T mc_s_icon 'Icon'), $icon, (T mc_s_icon_d 'a picture, made 64 × 64 – x removes it')),
        @((T mc_s_motd 'Description'), $motd, (T mc_s_motd_d 'the line under the name in the server list')),
        @((T mc_s_plugins 'Plugins'), $plug, (T mc_s_plugins_d 'search Modrinth, install with one key')),
        @((T mc_s_folder 'Folder'), (Format-LotusPath $m.Dir ($W - 30)), (Get-LotusMcText mc_s_folder_d 'opens it in File Explorer')),
        @((T mc_s_delete 'Delete the server'), '', (Get-LotusMcText mc_s_delete_d 'stops it, then the folder goes to the Recycle Bin'))
    )
    $Out.Add("  $a$((T mc_server 'Server').ToUpper())$r")
    $Out.Add('')
    # the label column as wide as the longest label (some languages need more than 14)
    $lw = 14
    foreach ($it in $items) { if ($it[0].Length -gt $lw) { $lw = $it[0].Length } }
    for ($i = 1; $i -le 5; $i++) {
        $f = $items[$i - 1]
        $lc = if ($i -eq 5) { $c['red'] } else { '' }
        if ($i -eq $m.SSel) {
            $Out.Add("  $($c['accent'])›$r $($c['B'])$lc$(PadR $f[0] $lw)$r $($f[1])")
            $Out.Add("$(PadR '' ($lw + 5))$d$($f[2])$r")
        } else { $Out.Add("    $lc$(PadR $f[0] $lw)$r $d$($f[1])$r") }
    }
    $Out.Add('')
    if ($m.Changed) { $Out.Add("  $($c['key2'])↻ $(T mc_restart_needed 'Restart the server for the changes – r')$r"); $Out.Add('') }
    if ($H - ($Out.Count - $base) -ge 8) { Add-LotusMccPreview $Out ($W - 4) }
}

# A text in this system's words: the Windows one (key_win) when the language files have it
function script:Get-LotusMcText {
    param([string]$Key, [string]$Default = '')
    $w = T "${Key}_win" ''
    if ($w) { return $w }
    T $Key $Default
}

# ── Settings → Plugins ───────────────────────────────────────

function script:Update-LotusMccInstalled { $script:Mcc.Inst = [System.Collections.Generic.List[object]]@(Get-LotusMcPluginsInstalled $script:Mcc.Dir) }

# The search: started a moment after the last key, read when it is there (an HTTP request of .NET, waited for here)
function script:Update-LotusMccSearch {
    $m = $script:Mcc
    if ($m.Sub -cne 'plugins' -or $m.Type -cne 'paper') { return }
    if ($m.Q -cne $m.QSent -and (Get-LotusMccNow) - $m.QAt -gt 0.35) {
        $m.QSent = $m.Q
        $m.RLoading = $true; $m.RState = 'loading'; $m.Res.Clear(); $m.RTotal = 0
        $m.QTask = Start-LotusMcSearch $m.Q $m.Ver 0
        return
    }
    if ($m.RLoading -and $m.QTask -and $m.QTask.IsCompleted) {
        $t = $m.QTask; $m.QTask = $null; $m.RLoading = $false
        $res = Read-LotusMcSearch $t
        if (-not $res) { $m.RState = 'error'; return }
        $m.RState = 'idle'
        $m.RTotal = $res.Total
        foreach ($h in $res.Hits) { $m.Res.Add($h) }
    }
}

# More results when the list reaches its end
function script:Update-LotusMccSearchMore {
    $m = $script:Mcc
    if ($m.RLoading -or $m.Res.Count -ge $m.RTotal -or $m.Res.Count -ge 300) { return }
    $m.RLoading = $true
    $m.QTask = Start-LotusMcSearch $m.Q $m.Ver $m.Res.Count
}

function script:Invoke-LotusMccPluginsKey {
    param([string]$Key)
    $m = $script:Mcc
    $ni = $m.Inst.Count; $n = $ni + $m.Res.Count
    switch -CaseSensitive -Regex ($Key) {
        '^(esc|left)$' { $m.Sub = ''; break }
        '^up$' { if ($n) { $m.PSel = if ($m.PSel -gt 1) { $m.PSel - 1 } else { $n } }; break }
        '^down$' { if ($n) { $m.PSel = if ($m.PSel -lt $n) { $m.PSel + 1 } else { 1 } }; break }
        '^pgup$' { $m.PSel = [Math]::Max(1, $m.PSel - 10); break }
        '^pgdn$' { $m.PSel = [Math]::Max(1, [Math]::Min($n, $m.PSel + 10)); break }
        '^home$' { $m.PSel = 1; break }
        '^end$' { $m.PSel = [Math]::Max(1, $n); break }
        '^(/|f)$' { if ($m.Type -ceq 'paper') { Start-LotusMccInput search (T mc_search 'Search') $m.Q }; break }
        '^(d|D)$' { if ($m.Type -ceq 'paper') { Start-LotusMccInput drop (T mc_drop_label 'Drop a .jar into the window, or type its path') }; break }
        '^(x|X|del)$' {
            if ($m.PSel -le $ni -and $ni) {
                $f = $m.Inst[$m.PSel - 1]
                if ($f.From -ceq 'lotus') { Show-LotusMccToast info (T mc_bridge_keep 'LotusBridge belongs to Lotus – it gives ping and TPS'); break }
                $m.Ask = "remove:$($f.File)"
            }
            break
        }
        '^enter$' {
            if ($m.PSel -gt $ni -and $m.PSel -le $n) { $h = $m.Res[$m.PSel - $ni - 1]; Install-LotusMccPlugin $h.Id $h.Slug $h.Title }
            elseif ($m.PSel -le $ni -and $n) { Show-LotusMccToast info "plugins/$($m.Inst[$m.PSel - 1].File)" }
            break
        }
        default {
            # typing starts the search right away
            if ($m.Type -ceq 'paper' -and $Key.Length -eq 1 -and -not [char]::IsControl($Key[0]) -and $Key -cnotin 'q', 'Q', 's', 'S', 'r', 'R', 'o', 'O', '1', '2', '3') {
                Start-LotusMccInput search (T mc_search 'Search') "$($m.Q)$Key"
                $m.Q = $m.InText; $m.QAt = Get-LotusMccNow
            }
        }
    }
    if ($n -and $m.PSel -ge $n - 2 -and $m.PSel -gt $ni) { Update-LotusMccSearchMore }
}

# Installs, with a frame that says so first (the download takes a moment)
function script:Install-LotusMccPlugin {
    param([string]$Id, [string]$Slug, [string]$Title)
    $m = $script:Mcc
    $m.Toast = (T mc_installing 'Installing %s …').Replace('%s', $Title); $m.ToastK = 'info'; $m.ToastAt = Get-LotusMccEpoch
    Show-LotusMccFrame
    $script:McpDone = [System.Collections.Generic.List[string]]::new(); $script:McpErr = ''
    if (Install-LotusMcPlugin $m.Dir $Id $Slug $Title $m.Ver) {
        Set-LotusMccChanged
        Show-LotusMccToast ok (T mc_installed '%s installed').Replace('%s', ($script:McpDone -join ', '))
        if ($script:McpErr) { Show-LotusMccToast err "$($script:McpDone -join ', ') ✓ · $($script:McpErr)" }
    } else { Show-LotusMccToast err $script:McpErr }
    Update-LotusMccInstalled
}

function script:Add-LotusMccPluginsPage {
    param($Out, [int]$W, [int]$H)
    $m = $script:Mcc; $c = $m.C
    $r = $c['r']; $d = $c['dim']; $a = "$([char]27)[1;$($script:C['accent'])m"; $k = $c['key']
    $base = $Out.Count
    $type = if ($m.Type) { $m.Type.Substring(0, 1).ToUpperInvariant() + $m.Type.Substring(1) } else { '' }
    $Out.Add("  $a$((T mc_s_plugins 'Plugins').ToUpper())$r$d  $type $(if ($m.Ver) { $m.Ver } else { '?' }) · Modrinth$r")
    $Out.Add('')
    if ($m.Type -cne 'paper') {
        $Out.Add("    $(T mc_pl_vanilla_1 'Plugins need a Paper server.')")
        $Out.Add("    $d$(T mc_pl_vanilla_2 'Set up a Paper server with /minecraft – your world can move along.')$r")
        return
    }
    # the search field
    $q = $m.Q; $cursor = ''
    if ($m.In -ceq 'search') { $q = $m.InText; $cursor = "$k▏$r" }
    $stat = switch ($m.RState) {
        'loading' { "$d$(T mc_searching 'Searching …')$r" }
        'error' { "$($c['red'])$(T mc_err_search 'Modrinth did not answer')$r" }
        default { "$d$((T mc_found '%d of %t').Replace('%d', [string]$m.Res.Count).Replace('%t', (Format-LotusMcCount $m.RTotal)))$r" }
    }
    if (-not $q -and $m.In -cne 'search') { $Out.Add("    $(PadR (T mc_search 'Search') 8) $d$(Get-LotusMccCut "/ $(T mc_search_hint 'type to search')" ($W - 18))$r") }
    else { $Out.Add("    $(PadR (T mc_search 'Search') 8) $($c['accent'])›$r $(Get-LotusMccTail $q ($W - 40))$cursor") }
    $Out.Add("             $stat")
    $Out.Add('')
    # one list: installed first, then what Modrinth found
    $ni = $m.Inst.Count; $nr = $m.Res.Count; $n = $ni + $nr
    if ($m.PSel -gt $n) { $m.PSel = $n }
    if ($m.PSel -lt 1) { $m.PSel = 1 }
    $have = @{}
    foreach ($x in $m.Inst) { $have[([string]$x.Name).ToLowerInvariant()] = $true }
    $mine = Get-LotusMcPluginsMine $m.Dir
    $rows = [System.Collections.Generic.List[object]]::new()
    $rows.Add(@('H', "$((T mc_installed_h 'Installed').ToUpper())  $ni"))
    if (-not $ni) { $rows.Add(@('T', (T mc_none_yet 'none yet'))) }
    for ($i = 1; $i -le $ni; $i++) {
        $f = $m.Inst[$i - 1]
        $from = switch ($f.From) { 'lotus' { T mc_from_lotus 'from Lotus' } 'modrinth' { 'Modrinth' } default { T mc_from_you 'yours' } }
        $rows.Add(@([string]$i, "$k●$r $(Get-LotusMccPad $f.Name 24)", "$d$(Get-LotusMccPad $f.Version 12)  $from$r"))
    }
    $rows.Add(@('B', ''))
    if (-not $m.QSent -or $m.QSent -ceq '-') { $rows.Add(@('H', (T mc_popular 'Popular for %s').Replace('%s', $m.Ver).ToUpper())) } else { $rows.Add(@('H', (T mc_results 'Results').ToUpper())) }
    for ($i = 1; $i -le $nr; $i++) {
        $hit = $m.Res[$i - 1]
        $mark = if ($mine.ContainsKey($hit.Id) -or $have.ContainsKey(([string]$hit.Title).ToLowerInvariant())) { "$k●$r" } else { ' ' }
        $rows.Add(@([string]($ni + $i), "$mark $(Get-LotusMccPad $hit.Title 24)", "$d$(PadL (Format-LotusMcCount $hit.Downloads) 6)$r  $(Get-LotusMccCut $hit.About ($W - 44))"))
    }
    if ($m.RLoading -and $nr) { $rows.Add(@('T', (T mc_searching 'Searching …'))) }
    # a window around the selection
    $room = [Math]::Max(3, $H - ($Out.Count - $base) - 1)
    $sel = 0
    for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i][0] -ceq [string]$m.PSel) { $sel = $i + 1 } }
    $top = 1
    if ($sel -gt $room - 1) { $top = $sel - $room + 2 }
    for ($i = $top; $i -lt $top + $room -and $i -le $rows.Count; $i++) {
        $row = $rows[$i - 1]
        switch -CaseSensitive ($row[0]) {
            'H' { $Out.Add("  $a$($row[1])$r") }
            'B' { $Out.Add('') }
            'T' { $Out.Add("    $d$($row[1])$r") }
            default { if ($row[0] -ceq [string]$m.PSel) { $Out.Add("  $($c['accent'])›$r $($row[1]) $($row[2])") } else { $Out.Add("    $($row[1]) $($row[2])") } }
        }
    }
}

# ── Page 3: Log ──────────────────────────────────────────────

function script:Invoke-LotusMccLogKey {
    param([string]$Key)
    $m = $script:Mcc
    $live = $m.Mode -ceq 'ours' -and $m.Pid
    switch -CaseSensitive -Regex ($Key) {
        '^up$' { $m.Back++; break }
        '^down$' { if ($m.Back -gt 0) { $m.Back-- }; break }
        '^pgup$' { $m.Back += [Math]::Max(1, $m.H - 12); break }
        '^pgdn$' { $m.Back = [Math]::Max(0, $m.Back - [Math]::Max(1, $m.H - 12)); break }
        '^home$' { $m.Back = 999999; break }
        '^(end|G)$' { $m.Back = 0; break }
        '^(f|F)$' { $m.Filter = switch ($m.Filter) { 'all' { 'chat' } 'chat' { 'warn' } default { 'all' } }; $m.Back = 0; break }
        '^(/|enter|:)$' { if ($live) { Start-LotusMccInput cmd '/' } else { Show-LotusMccToast info (T mc_external_cmd 'Started elsewhere – commands go into its own window') }; break }
        '^(t|T)$' { if ($live) { Start-LotusMccInput cmd '/' 'say ' } else { Show-LotusMccToast info (T mc_external_cmd 'Started elsewhere – commands go into its own window') }; break }
    }
}

# Does a line belong to the filter?
function script:Test-LotusMccLogMatch {
    param([string]$Line)
    switch ($script:Mcc.Filter) {
        'chat' { return ($Line -cmatch '\]: (<|\[Not Secure\]|.* joined the game|.* left the game|.* has made the advancement)' -or $Line.StartsWith('[Lotus] >')) }
        'warn' { return ($Line -cmatch 'WARN|ERROR|FATAL|Exception|Error:' -or $Line -cmatch '^\sat ') }
    }
    $true
}

# A console line in color, cut to the width
function script:Get-LotusMccLogColor {
    param([string]$Line, [int]$W)
    $c = $script:Mcc.C; $r = $c['r']; $d = $c['dim']
    $l = Get-LotusMccCut $Line $W
    if ($l.StartsWith('[Lotus]')) { return "$($c['logo'])$l$r" }
    $head = ''; $msg = $l; $col = ''
    if ($l -match '^(\[[0-2][0-9]:[0-5][0-9]:[0-5][0-9][^\]]*\][^:]*: )(.*)$') { $head = $Matches[1]; $msg = $Matches[2] }
    if ("$head$msg" -cmatch 'ERROR|FATAL|Exception' -or "$head$msg" -cmatch '^\sat ') { $col = $c['red'] }
    elseif ("$head$msg" -cmatch 'WARN') { $col = $c['key2'] }
    if ($msg -cmatch '^(\[Not Secure\] |)<([^>]+)>(.*)$') { $msg = "$d$($Matches[1])$r$($c['accent'])<$($Matches[2])>$r$($Matches[3])" }
    elseif ($msg -cmatch ' joined the game$| left the game$|^Done \(') { $msg = "$($c['key'])$msg$r" }
    elseif ($col) { $msg = "$col$msg$r" }
    "$d$head$r$msg"
}

function script:Add-LotusMccLogPage {
    param($Out, [int]$W, [int]$H)
    $m = $script:Mcc; $c = $m.C
    $r = $c['r']; $d = $c['dim']; $a = "$([char]27)[1;$($script:C['accent'])m"
    $base = $Out.Count
    $fl = @{ all = (T mc_f_all 'all'); chat = (T mc_f_chat 'chat & players'); warn = (T mc_f_warn 'warnings & errors') }
    $lines = if ($m.Filter -ceq 'all') { $m.Log.ToArray() } else { @($m.Log | Where-Object { Test-LotusMccLogMatch $_ }) }
    $lines = @($lines)
    $room = $H - 4; $n = $lines.Count
    if ($m.Back -gt $n - $room) { $m.Back = [Math]::Max(0, $n - $room) }
    $follow = if ($m.Back) { "$d$((T mc_back '%d lines back – End follows again').Replace('%d', [string]$m.Back))$r" } else { "$($c['key'])● $(T mc_live 'live')$r" }
    $src = if ($m.Mode -ceq 'external') { 'logs\latest.log' } else { 'console.log' }
    $Out.Add("  $a$((T mc_console 'Console').ToUpper())$r$d  $(Format-LotusMcCount $n) $(T mc_lines 'lines') · $src · $(T mc_filter 'filter'): $($fl[$m.Filter])$r   $follow")
    $Out.Add('')
    $from = [Math]::Max(1, $n - $m.Back - $room + 1); $to = $n - $m.Back
    if ($n -eq 0) { $Out.Add("    $d$(T mc_log_empty 'Nothing yet – the server writes here when it starts')$r") }
    for ($i = $from; $i -le $to; $i++) { $Out.Add("  $(Get-LotusMccLogColor $lines[$i - 1] ($W - 4))") }
    while ($Out.Count - $base -lt $H - 1) { $Out.Add('') }
    # the command line
    if ($m.In -ceq 'cmd') { $Out.Add("  $($c['accent'])›$r $($c['B'])/$r$(Get-LotusMccTail $m.InText ($W - 10))$($c['key'])▏$r") }
    elseif ($m.Mode -ceq 'ours' -and $m.Pid) { $Out.Add("  $d› $(T mc_cmd_hint '/ or ⏎ types a command, t chats')$r") }
    else { $Out.Add("  $d› $(T mc_cmd_off 'The command line works when Lotus started the server')$r") }
}

# ── The frame around the pages ───────────────────────────────

function script:Show-LotusMccFrame {
    $m = $script:Mcc; $c = $m.C
    $W = $m.W; $H = $m.H
    $esc = [char]27
    $r = $c['r']; $d = $c['dim']; $a = $c['accent']; $bo = $c['B']
    if ($W -lt 60 -or $H -lt 18) { Write-LotusRaw "$esc[?2026h$esc[H$esc[2J  $(T mc_too_small 'Make the window a little larger (at least 60 × 18)')$esc[?2026l"; return }
    $out = [System.Collections.Generic.List[string]]::new()
    # head: lotus / Minecraft · name, the state on the right
    $st = Get-LotusMccStateText
    $left = "    $a◇$r $($bo)lotus$r$d / $r$($bo)Minecraft$r$d  ·  $r$($m.Name)"
    $out.Add('')
    $out.Add("$left$(PadR '' ($W - (Get-LotusMccVw $left) - (Get-LotusMccVw $st) - 3))$st")
    $out.Add('')
    # tabs, the open one like the selected slot of the hotbar
    $tabs = @((T mc_tab_stats 'Stats'), (T mc_tab_settings 'Settings'), (T mc_tab_log 'Log'))
    $t = '    '
    for ($i = 1; $i -le 3; $i++) { if ($i -eq $m.Page) { $t += "$($c['tab']) $i  $($tabs[$i - 1]) $r " } else { $t += "$d $i  $($tabs[$i - 1]) $r " } }
    $out.Add($t)
    $out.Add('')
    $body = $H - 7
    $start = $out.Count
    switch ($m.Page) {
        1 { Add-LotusMccStatsPage $out $W $body }
        2 { Add-LotusMccSettingsPage $out $W $body }
        3 { Add-LotusMccLogPage $out $W $body }
    }
    # never more than the window has
    if ($out.Count -gt $start + $body) { $out.RemoveRange($start + $body, $out.Count - $start - $body) }
    while ($out.Count -lt $H) { $out.Add('') }
    # the bottom: a message, a question, an input – and the keys
    $msg = ''; $keys = ''
    if ($m.In -and $m.In -cnotin 'cmd', 'search') {
        $lab = Get-LotusMccCut $m.InLabel ([Math]::Truncate($W / 2))
        $msg = "  $a›$r $lab  $bo$(Get-LotusMccTail $m.InText ($W - $lab.Length - 10))$r$($c['key'])▏$r"
        $keys = "⏎ $(T mc_k_ok 'ok')   esc $(T mc_k_cancel 'cancel')"
    } elseif ($m.Ask) {
        $q = Get-LotusMccAskText
        $msg = "  $($c['key2'])?$r $($q[0])"; $keys = $q[1]
    } else {
        if ($m.Toast) {
            $msg = switch ($m.ToastK) { 'ok' { "  $($c['key'])✓$r $($m.Toast)" } 'err' { "  $($c['red'])✗$r $($m.Toast)" } default { "  $a›$r $($m.Toast)" } }
        }
        $keys = switch ($m.Page) {
            1 { T mc_k_stats '↑↓ players   ⏎ commands   s stop   r restart   o folder   tab pages   q leave' }
            2 { if ($m.Sub -ceq 'plugins') { T mc_k_plugins } else { T mc_k_settings } }
            3 { if ($m.In -ceq 'cmd') { T mc_k_cmd } else { T mc_k_log } }
        }
        if ($m.In -ceq 'search') { $keys = T mc_k_search }
        if ($m.Problem -ceq 'eula') { $keys = "e $(T mc_k_eula 'accept the EULA')   $keys" }
        if ($m.State -cin 'stopped', 'crashed' -and $m.Page -ne 2) { $keys = $keys.Replace("s $(T mc_k_stop 'stop')", "s $(T mc_k_start 'start')") }
    }
    if ((Get-LotusMccVw $msg) -gt $W - 2) { $msg = Get-LotusMccCut ($msg -replace "$esc\[[0-9;?]*[A-Za-z]", '') ($W - 2) }
    $out[$H - 2] = $msg
    $out[$H - 1] = "    $d$(Get-LotusMccCut ([string]$keys) ($W - 6))$r"
    # whatever is still too wide is cut, so nothing wraps and moves the window
    $sb = [System.Text.StringBuilder]::new("$esc[?2026h$esc[H")
    for ($i = 0; $i -lt $H; $i++) {
        $line = $out[$i]
        if ((Get-LotusMccVw $line) -gt $W) { $line = Get-LotusMccClip $line $W }
        [void]$sb.Append($line).Append($r).Append("$esc[K")
        if ($i -lt $H - 1) { [void]$sb.Append("`n") }
    }
    [void]$sb.Append("$esc[J$esc[?2026l")
    Write-LotusRaw $sb.ToString()
}

# The question being asked and its keys → @(question, keys)
function script:Get-LotusMccAskText {
    $m = $script:Mcc
    $yn = "y $(T mc_k_yes 'yes')   n $(T mc_k_no 'no')"
    switch -Wildcard -CaseSensitive ($m.Ask) {
        'quit' { return @((T mc_q_quit 'Leave the control center? The server keeps running.'), "⏎ $(T mc_k_leave 'leave')   s $(T mc_k_stopleave 'stop and leave')   esc $(T mc_k_stay 'stay')") }
        'stop' { return @((T mc_q_stop '%d players are online. Stop the server?').Replace('%d', [string]$m.POrder.Count), $yn) }
        'restart' { return @((T mc_q_restart '%d players are online. Restart the server?').Replace('%d', [string]$m.POrder.Count), $yn) }
        'eula' { return @((T mc_q_eula 'Accept the Minecraft EULA?'), "y $(T mc_k_accept 'accept')   n $(T mc_k_no 'no')   https://aka.ms/MinecraftEULA") }
        'icondel' { return @((T mc_q_icondel 'Remove the icon?'), $yn) }
        'remove:*' { return @((T mc_q_remove 'Remove %s?').Replace('%s', $m.Ask.Substring(7)), $yn) }
        'player:*' { return @("$($m.Ask.Substring(7)):  1 op · 2 deop · 3 kick · 4 ban · 5 creative · 6 survival · 7 whitelist", "1–7 $(T mc_k_choose 'choose')   esc $(T mc_k_cancel 'cancel')") }
    }
    @('', '')
}

# ── The little world on the stats page (lib/mc/world.zsh) ────
# A side view that drifts by: hills of grass, dirt and stone with ores above the bedrock, oak trees and flowers, water
# with lily pads and lotus flowers, blocky clouds, and the square sun and moon of a day that lasts two minutes, with
# stars at night. A little figure walks for every player online, a creeper waits when nobody is. While the server is
# stopped, the world stands still. Two pixels per character (half blocks), every color made from the theme's eight.
# Pixel rows and the world's columns count from 1, as in zsh (index 0 is unused).

$script:Mcw = @{ H = 0; Theme = ''; T = 0.0; Last = 0.0 }
$script:McwRand = [Random]::new()

function script:Get-LotusMcwScale { param([string]$Rgb, [int]$P) (@($Rgb -split ';') | ForEach-Object { [Math]::Min(255, [Math]::Truncate([int]$_ * $P / 100)) }) -join ';' }
function script:Get-LotusMcwMix {
    param([string]$A, [string]$B, [int]$P)
    $x = $A -split ';'; $y = $B -split ';'
    (0..2 | ForEach-Object { [Math]::Truncate(([int]$x[$_] * (100 - $P) + [int]$y[$_] * $P) / 100) }) -join ';'
}

# One letter per kind of pixel; the colors come from the theme, once per theme and color mode
function script:Update-LotusMcwPalette {
    $w = $script:Mcw
    $key = "$($script:S['LOTUS_THEME']) $($script:Mode)"
    if ($w.Theme -ceq $key -and $w.Fg) { return }
    $w.Theme = $key
    $th = $script:Themes[[string]$script:S['LOTUS_THEME']]; if (-not $th) { $th = $script:Themes['matcha'] }
    $logo = $th[0]; $keyc = $th[1]; $accent = $th[2]; $key2 = $th[3]; $salute = $th[4]; $border = $th[5]; $dim = $th[6]; $music = $th[7]
    $white = '255;255;255'
    $water = Get-LotusMcwMix $accent '50;110;225' 55        # the accent with enough blue in it that it still reads as water
    # (pairs, not a hashtable: the letters are case-sensitive – c and C are different pixels)
    $rgb = @(
        @('.', (Get-LotusMcwMix $dim $white 30)), @(':', (Get-LotusMcwMix $salute $white 40)),    # stars
        @('c', (Get-LotusMcwMix $dim $white 72)), @('C', (Get-LotusMcwMix $dim $white 48)),    # clouds, their shade below
        @('U', ($salute)), @('u', (Get-LotusMcwMix $salute $white 55)),    # the sun, its bright middle
        @('M', (Get-LotusMcwMix $dim $white 78)), @('m', (Get-LotusMcwMix $dim $white 45)),    # the moon and its craters
        @('g', ($keyc)), @('q', (Get-LotusMcwScale $keyc 80)),    # grass, a darker blade
        @('d', (Get-LotusMcwScale $key2 50)), @('e', (Get-LotusMcwScale $key2 40)),    # dirt
        @('a', (Get-LotusMcwMix $key2 $white 25)),    # sand
        @('x', (Get-LotusMcwScale $dim 72)), @('y', (Get-LotusMcwScale $dim 58)),    # stone
        @('o', ($accent)), @('r', ($logo)), @('n', ($salute)),    # ores
        @('b', (Get-LotusMcwScale $dim 30)),    # bedrock
        @('w', (Get-LotusMcwScale $water 70)), @('W', (Get-LotusMcwScale $water 95)),    # water, its surface
        @('T', (Get-LotusMcwScale $key2 52)), @('L', (Get-LotusMcwScale $keyc 62)), @('l', (Get-LotusMcwScale $keyc 84)),    # oak
        @('f', ($logo)), @('F', ($salute)),    # flowers
        @('p', ($logo)), @('P', (Get-LotusMcwMix $logo $white 50)), @('k', (Get-LotusMcwScale $keyc 55)),    # the lotus, its lily pad
        @('H', (Get-LotusMcwMix $salute $white 35)), @('1', ($accent)), @('2', ($logo)), @('3', ($key2)), @('4', ($music)),    # players
        @('K', (Get-LotusMcwScale $border 70)),
        @('E', (Get-LotusMcwScale $keyc 92)), @('N', (Get-LotusMcwScale $keyc 28))    # the creeper and its face
    )
    $w.Fg = [System.Collections.Generic.Dictionary[char, string]]::new()
    $w.Bg = [System.Collections.Generic.Dictionary[char, string]]::new()
    foreach ($pair in $rgb) {
        $sgr = ConvertTo-LotusSgr $pair[1]
        $w.Fg[[char]$pair[0]] = $sgr; $w.Bg[[char]$pair[0]] = ConvertTo-LotusBackground $sgr
    }
}

# A new world for a new height
function script:Reset-LotusMcw {
    param([int]$H)
    $w = $script:Mcw
    $w.H = $H; $w.Sea = [Math]::Truncate($H * 64 / 100)
    $w.Col = [System.Collections.Generic.List[char[]]]::new(); $w.Col.Add($null)
    $w.Surf = [System.Collections.Generic.List[int]]::new(); $w.Surf.Add(0)
    $w.Cloud = [System.Collections.Generic.List[char[]]]::new(); $w.Cloud.Add($null)
    $w.Cp = [System.Collections.Generic.Dictionary[int, int]]::new()
    $w.Base = 0; $w.CBase = 0; $w.CLeft = 0; $w.CGap = 3; $w.CLen = 0; $w.CY = 2; $w.CPos = 0
    $w.StarKey = ''; $w.Stars = @()
}

# Height of the ground at a column: smooth hills through a random point every 12 columns (the pixel row of the
# surface, 1 = top)
function script:Get-LotusMcwHeight {
    param([int]$X)
    $w = $script:Mcw; $rnd = $script:McwRand
    $k = [Math]::Truncate($X / 12); $H = $w.H
    $lo = [Math]::Truncate($H * 40 / 100); $hi = [Math]::Truncate($H * 82 / 100)
    foreach ($j in @($k, ($k + 1))) {
        if ($w.Cp.ContainsKey($j)) { continue }
        # now and then a valley under the sea level, so there is water
        $v = if ($rnd.Next(4) -eq 0) { $w.Sea + 2 + $rnd.Next(4) } else { $lo + $rnd.Next([Math]::Max(1, $w.Sea - $lo)) }
        $w.Cp[$j] = [Math]::Min($v, $hi)
    }
    $t = ($X % 12) / 12.0
    $s = $t * $t * (3 - 2 * $t)
    [int][Math]::Truncate($w.Cp[$k] + ($w.Cp[$k + 1] - $w.Cp[$k]) * $s + 0.5)
}

# 16 more columns of ground, then trees, flowers and lotus flowers on them
function script:Add-LotusMcwColumns {
    $w = $script:Mcw; $rnd = $script:McwRand
    $n = $w.Col.Count - 1; $H = $w.H; $sea = $w.Sea
    for ($i = 1; $i -le 16; $i++) {
        $surf = Get-LotusMcwHeight ($w.Base + $n + $i)
        $col = [char[]]::new($H + 1)
        for ($y = 1; $y -le $H; $y++) {
            $ch = if ($y -eq $H) { 'b' }
            elseif ($y -lt $surf) { if ($y -gt $sea) { 'w' } elseif ($y -eq $sea -and $surf -gt $sea) { 'W' } else { ' ' } }
            elseif ($y -eq $surf) { if ($surf -gt $sea) { 'a' } elseif ($rnd.Next(5)) { 'g' } else { 'q' } }
            elseif ($y -le $surf + 2) { if ($surf -gt $sea) { 'a' } elseif ($rnd.Next(4)) { 'd' } else { 'e' } }
            elseif ($y -eq $H - 1 -and $rnd.Next(2)) { 'b' }
            else { $v = $rnd.Next(100); if ($v -eq 0) { 'o' } elseif ($v -eq 1) { 'r' } elseif ($v -eq 2) { 'n' } elseif ($v -le 16) { 'y' } else { 'x' } }
            $col[$y] = $ch
        }
        $w.Col.Add($col); $w.Surf.Add($surf)
    }
    # features, only where all their columns are in this chunk
    $set = { param($ci, $yy, $ch) if ($yy -ge 1 -and $yy -le $H) { $w.Col[$ci][$yy] = $ch } }
    $hasT = { param($ci) $ci -ge 1 -and ($w.Col[$ci] -ccontains [char]'T') }
    for ($i = $n + 3; $i -le $n + 14; $i++) {
        $surf = $w.Surf[$i]
        if ($surf -lt $sea -and $surf -eq $w.Surf[$i - 1] -and $surf -eq $w.Surf[$i + 1] -and $rnd.Next(7) -eq 0 -and -not (& $hasT ($i - 1)) -and -not (& $hasT ($i - 2))) {
            # an oak: trunk, then a wide crown and a narrow one on top
            $th = 3 + $rnd.Next(2); $top = $surf - $th
            if ($top -le 4) { continue }
            for ($y = $surf - 1; $y -ge $top; $y--) { & $set $i $y 'T' }
            for ($ci = $i - 2; $ci -le $i + 2; $ci++) { foreach ($y in @($top, ($top + 1))) { if ($w.Col[$ci][$y] -eq ' ') { & $set $ci $y $(if (($ci + $y) % 3) { 'L' } else { 'l' }) } } }
            for ($ci = $i - 1; $ci -le $i + 1; $ci++) { foreach ($y in @(($top - 1), ($top - 2))) { if ($w.Col[$ci][$y] -eq ' ') { & $set $ci $y $(if (($ci + $y) % 2) { 'l' } else { 'L' }) } } }
            $i += 3
        } elseif ($surf -lt $sea -and $rnd.Next(9) -eq 0 -and $w.Col[$i][$surf - 1] -eq ' ') {
            & $set $i ($surf - 1) $(if ($rnd.Next(2)) { 'f' } else { 'F' })
        } elseif ($surf -gt $sea + 1 -and $w.Surf[$i - 1] -gt $sea -and $w.Surf[$i + 1] -gt $sea -and $rnd.Next(6) -eq 0) {
            # a lotus on its lily pad
            & $set ($i - 1) $sea 'k'; & $set $i $sea 'k'; & $set ($i + 1) $sea 'k'
            & $set ($i - 1) ($sea - 1) 'p'; & $set $i ($sea - 1) 'P'; & $set ($i + 1) ($sea - 1) 'p'
            & $set $i ($sea - 2) 'p'
            $i += 2
        }
    }
}

# The cloud layer: blocky clouds of two rows with gaps between them – one column (rows 1 to 6)
function script:Get-LotusMcwCloudColumn {
    $w = $script:Mcw; $rnd = $script:McwRand
    $col = [char[]]::new(7); for ($y = 0; $y -le 6; $y++) { $col[$y] = ' ' }
    if ($w.CLeft -le 0) {
        if ($w.CGap -gt 0) { $w.CGap--; return , $col }
        $w.CLen = 7 + $rnd.Next(11); $w.CLeft = $w.CLen; $w.CY = 2 + $rnd.Next(3); $w.CGap = 6 + $rnd.Next(22); $w.CPos = 0
    }
    $w.CLeft--; $w.CPos++
    $col[$w.CY + 1] = 'C'
    if ($w.CPos -gt 2 -and $w.CPos -le $w.CLen - 2) { $col[$w.CY] = 'c' }
    , $col
}

# Where a figure stands at screen column <x>: on the ground, or swimming on the water
function script:Get-LotusMcwGround {
    param([int]$Off, [int]$X)
    $w = $script:Mcw
    $s1 = if ($Off + $X -lt $w.Surf.Count) { $w.Surf[$Off + $X] } else { $w.Sea }
    $s2 = if ($Off + $X + 1 -lt $w.Surf.Count) { $w.Surf[$Off + $X + 1] } else { $w.Sea }
    $s = [Math]::Min($s1, $s2)
    if ($s -gt $w.Sea) { $s = $w.Sea + 1 }
    $s
}

# The lines of a frame: <columns> <rows> <players> <moving>
function script:Get-LotusMcWorldFrame {
    param([int]$W, [int]$R, [int]$Players, [bool]$Moving)
    if ($W -le 0 -or $R -le 0) { return , @() }
    $mw = $script:Mcw
    $H = $R * 2
    if ($H -ne $mw.H) { Reset-LotusMcw $H }
    Update-LotusMcwPalette
    # the world's own time: it runs while the server does
    $now = Get-LotusMccNow
    if ($mw.Last -gt 0 -and $Moving) { $mw.T += $(if ($now - $mw.Last -gt 1) { 0.2 } else { $now - $mw.Last }) }
    $mw.Last = $now
    $scroll = [int][Math]::Truncate($mw.T * 2.6); $cscroll = [int][Math]::Truncate($mw.T * 1.3)
    while ($mw.Col.Count - 1 -lt $scroll - $mw.Base + $W + 2) { Add-LotusMcwColumns }
    # forget what has drifted out on the left
    $drop = $scroll - $mw.Base - 4
    if ($drop -gt 32) { $mw.Col.RemoveRange(1, $drop); $mw.Surf.RemoveRange(1, $drop); $mw.Base += $drop }
    while ($mw.Cloud.Count - 1 -lt $cscroll - $mw.CBase + $W + 2) { $mw.Cloud.Add((Get-LotusMcwCloudColumn)) }
    $drop = $cscroll - $mw.CBase - 4
    if ($drop -gt 32) { $mw.Cloud.RemoveRange(1, $drop); $mw.CBase += $drop }
    $rnd = $script:McwRand
    # stars sit still in the sky, a new set for every window size
    if ($mw.StarKey -cne "$W,$H") {
        $mw.StarKey = "$W,$H"
        $mw.Stars = @(for ($i = 0; $i -lt [Math]::Truncate($W / 4); $i++) { , @(($rnd.Next($W) + 1), ($rnd.Next([Math]::Max(1, $mw.Sea - 3)) + 1)) })
    }
    # the day: 120 seconds, the sun for the first 70, the moon for the rest
    $ph = (($mw.T + 20) % 120) / 120.0
    $night = $false; $body = [char]'U'; $core = [char]'u'
    if ($ph -lt 0.58) { $arc = $ph / 0.58 } else { $arc = ($ph - 0.58) / 0.42; $night = $true; $body = [char]'M'; $core = [char]'m' }
    $bx = [int][Math]::Truncate($arc * ($W + 4)) - 3
    $by = [int][Math]::Truncate(2 + ($mw.Sea * 0.45) * (1 - [Math]::Sin($arc * 3.14159)))
    $off = $scroll - $mw.Base
    $cols = [char[][]]::new($W + 1)
    for ($i = 1; $i -le $W; $i++) {
        $col = [char[]]$mw.Col[$off + $i].Clone()
        $cl = $mw.Cloud[$cscroll - $mw.CBase + $i]
        for ($y = 1; $y -le [Math]::Min(6, $H); $y++) { if ($cl[$y] -ne ' ' -and $col[$y] -eq ' ') { $col[$y] = $cl[$y] } }
        # sun or moon, behind the clouds
        if ($i -ge $bx -and $i -lt $bx + 4) {
            for ($y = $by; $y -lt $by + 4 -and $y -le $H; $y++) {
                if ($y -lt 1 -or $col[$y] -ne ' ') { continue }
                if (($i -eq $bx + 1 -or $i -eq $bx + 2) -and ($y -eq $by + 1 -or $y -eq $by + 2)) {
                    $col[$y] = if ($night) { if ($i -eq $bx + 1 -and $y -eq $by + 1) { [char]'m' } else { [char]'M' } } else { $core }
                } else { $col[$y] = $body }
            }
        }
        $cols[$i] = $col
    }
    if ($night) {
        $k = 0
        foreach ($st in $mw.Stars) {
            $k++
            $x = $st[0]; $y = $st[1]
            if ($x -gt $W -or $y -gt $H -or $cols[$x][$y] -ne ' ') { continue }
            # twinkling: a few are bright, a few gone, changing every second
            switch (($k * 7 + [int][Math]::Truncate($mw.T)) % 9) { 0 { $cols[$x][$y] = ':' } 1 { } default { $cols[$x][$y] = '.' } }
        }
    }
    # players, or a creeper when nobody is online
    $put = {
        param([int]$x, [int]$y, [string]$two)
        if ($y -lt 1 -or $y -gt $H) { return }
        if ($two[0] -ne ' ' -and $x -ge 1 -and $x -le $W) { $cols[$x][$y] = $two[0] }
        if ($two[1] -ne ' ' -and $x + 1 -ge 1 -and $x + 1 -le $W) { $cols[$x + 1][$y] = $two[1] }
    }
    $step = [int][Math]::Truncate($mw.T * 4) % 2
    $n = [Math]::Min(4, $Players)
    $spots = @(42, 58, 27, 72)
    if ($n -eq 0) {
        $fx = [Math]::Truncate($W * 66 / 100)
        $fy = Get-LotusMcwGround $off $fx
        & $put $fx ($fy - 4) 'EE'; & $put $fx ($fy - 3) 'NN'; & $put $fx ($fy - 2) 'EE'; & $put $fx ($fy - 1) 'EE'
    } else {
        for ($k = 1; $k -le $n; $k++) {
            $fx = [Math]::Truncate($W * $spots[$k - 1] / 100)
            $fy = Get-LotusMcwGround $off $fx
            & $put $fx ($fy - 4) 'HH'; & $put $fx ($fy - 3) "$k$k"; & $put $fx ($fy - 2) 'KK'
            & $put $fx ($fy - 1) $(if (($step + $k) % 2) { 'K ' } else { ' K' })
        }
    }
    , (Get-LotusMcwPaint $cols $W $R)
}

# The pixel columns as lines. Half blocks: the top pixel as background, the bottom one as ▄; ▀ where only the top one
# is there.
function script:Get-LotusMcwPaint {
    param($Cols, [int]$W, [int]$R)
    $mw = $script:Mcw
    $esc = [char]27
    $lines = [string[]]::new($R)
    for ($y = 1; $y -le $R; $y++) {
        $sb = [System.Text.StringBuilder]::new(); $fg = ''; $bg = ''
        for ($i = 1; $i -le $W; $i++) {
            $c = $Cols[$i]
            $t = if (2 * $y - 1 -lt $c.Length) { $c[2 * $y - 1] } else { [char]' ' }
            $b = if (2 * $y -lt $c.Length) { $c[2 * $y] } else { [char]' ' }
            if ($t -eq [char]0) { $t = [char]' ' }
            if ($b -eq [char]0) { $b = [char]' ' }
            if ($t -eq ' ') {
                if ($b -eq ' ') { if ($bg) { [void]$sb.Append("$esc[49m"); $bg = '' }; [void]$sb.Append(' '); continue }
                $wantFg = $mw.Fg[$b]; $wantBg = ''; $ch = '▄'
            } elseif ($b -eq ' ') { $wantFg = $mw.Fg[$t]; $wantBg = ''; $ch = '▀' }
            else { $wantFg = $mw.Fg[$b]; $wantBg = $mw.Bg[$t]; $ch = '▄' }
            if ($wantBg -cne $bg) { [void]$sb.Append("$esc[$(if ($wantBg) { $wantBg } else { '49' })m"); $bg = $wantBg }
            if ($wantFg -cne $fg) { [void]$sb.Append("$esc[$($wantFg)m"); $fg = $wantFg }
            [void]$sb.Append($ch)
        }
        $lines[$y - 1] = $sb.ToString() + "$esc[0m"
    }
    $lines
}

# The server icon when there is none yet: a grass block, 12 × 12 pixels → 6 lines
function script:Get-LotusMcWorldIcon {
    Update-LotusMcwPalette
    $rows = @('gggqgggggqgg', 'ggggggqggggg', 'gqgggggggqgg', 'dgdgqgdggdgd', 'dddgdddgddde', 'ddeddddddedd',
        'ddddddeddddd', 'deddddddddde', 'dddddeddeddd', 'ddedddddddde', 'dddddddedddd', 'eddedddddddd')
    $cols = [char[][]]::new(13)
    for ($x = 1; $x -le 12; $x++) {
        $cols[$x] = [char[]]::new(13)
        for ($y = 1; $y -le 12; $y++) { $cols[$x][$y] = $rows[$y - 1][$x - 1] }
    }
    Get-LotusMcwPaint $cols 12 6
}

# ── Plugins for a Paper server (lib/mc/plugins.zsh) ──────────
# Search and download from Modrinth (modrinth.com): only plugins made for Paper, Spigot, Bukkit or Purpur and for the
# server's Minecraft version, only files from Modrinth's own download server, each one checked against its SHA-512
# before it goes into plugins\. Required dependencies come along. Plugins of your own: drag the .jar into the window.
# What Lotus installed is noted in .lotus\plugins.tsv (project id, slug, title, version, file), so updates replace the
# old file.

$script:McpApi = 'https://api.modrinth.com/v2'
$script:McpCdn = 'https://cdn.modrinth.com/'
$script:McpLoaders = @('paper', 'spigot', 'bukkit', 'purpur')
$script:McpDone = [System.Collections.Generic.List[string]]::new()
$script:McpErr = ''

# One HTTP client for Modrinth, which wants to know who asks
function script:Get-LotusMcpHttp {
    if ($script:McpHttp) { return $script:McpHttp }
    $h = [System.Net.Http.HttpClient]::new()
    $h.Timeout = [TimeSpan]::FromSeconds(30)
    [void]$h.DefaultRequestHeaders.UserAgent.TryParseAdd("Fanxy13/homebrew-lotus/$(Get-LotusVersion) (lotus minecraft control center)")
    $script:McpHttp = $h
    $h
}

# The search address: <query> <minecraft version> <offset>
function script:Get-LotusMcpSearchUrl {
    param([string]$Query, [string]$Version, [int]$Offset)
    $ors = ($script:McpLoaders | ForEach-Object { "`"categories:$_`"" }) -join ','
    $facets = "[[$ors],[`"versions:$Version`"]]"
    $index = if ($Query) { 'relevance' } else { 'downloads' }
    "$($script:McpApi)/search?query=$([Uri]::EscapeDataString($Query))&limit=30&offset=$Offset&index=$index&facets=$([Uri]::EscapeDataString($facets))"
}

# A search, started: the request of .NET runs while the window goes on (a task, read when it is done)
function script:Start-LotusMcSearch {
    param([string]$Query, [string]$Version, [int]$Offset)
    try { (Get-LotusMcpHttp).GetStringAsync((Get-LotusMcpSearchUrl $Query $Version $Offset)) } catch { $null }
}
# …its answer → @{ Total; Hits = @{ Id; Slug; Title; Downloads; Author; About } }, or $null
function script:Read-LotusMcSearch {
    param($Task)
    try {
        if ($Task.IsFaulted -or $Task.IsCanceled) { return $null }
        $j = $Task.Result | ConvertFrom-Json
        [pscustomobject]@{
            Total = [int]$j.total_hits
            Hits = @(foreach ($h in @($j.hits)) {
                    [pscustomobject]@{ Id = [string]$h.project_id; Slug = [string]$h.slug; Title = [string]$h.title; Downloads = [long]$h.downloads
                        Author = [string]$h.author; About = ([string]$h.description -replace '[\t\r\n]+', ' ') }
                })
        }
    } catch { $null }
}

# Big numbers short: 12345678 → 12.3M
function script:Format-LotusMcCount {
    param([long]$N)
    $t = if ($N -ge 1000000) { ($N / 1000000.0).ToString('0.0', [cultureinfo]::InvariantCulture) + 'M' }
         elseif ($N -ge 1000) { ($N / 1000.0).ToString('0.0', [cultureinfo]::InvariantCulture) + 'k' }
         else { [string]$N }
    $t.Replace('.0M', 'M').Replace('.0k', 'k')
}

# The newest file of a project for this server → @{ Version; Url; File; Sha512; Deps }, or $null
function script:Get-LotusMcpPick {
    param([string]$Id, [string]$Version)
    $ls = [Uri]::EscapeDataString('[' + (($script:McpLoaders | ForEach-Object { "`"$_`"" }) -join ',') + ']')
    $vs = [Uri]::EscapeDataString("[`"$Version`"]")
    try { $j = @((Get-LotusMcpHttp).GetStringAsync("$($script:McpApi)/project/$Id/version?loaders=$ls&game_versions=$vs").GetAwaiter().GetResult() | ConvertFrom-Json) } catch { return $null }
    $all = @($j | ForEach-Object { $_ })
    $v = @($all | Where-Object { $_.version_type -ceq 'release' }) + $all | Select-Object -First 1
    if (-not $v) { return $null }
    $files = @($v.files)
    $f = @($files | Where-Object { $_.primary }) + $files | Select-Object -First 1
    if (-not $f -or -not $f.url) { return $null }
    [pscustomobject]@{
        Version = [string]$v.version_number; Url = [string]$f.url; File = [string]$f.filename; Sha512 = [string]$f.hashes.sha512
        Deps = @(@($v.dependencies) | Where-Object { $_ -and $_.dependency_type -ceq 'required' -and $_.project_id } | ForEach-Object { [string]$_.project_id })
    }
}

# What Lotus installed: .lotus\plugins.tsv → @{ project id = @(slug, title, version, file) }
function script:Get-LotusMcPluginsMine {
    param([string]$Dir)
    $mine = @{}
    $t = Read-LotusFile (Join-Path $Dir '.lotus/plugins.tsv')
    if ($t) { foreach ($l in $t -split "`n") { $f = $l -split "`t"; if ($f.Count -ge 5) { $mine[$f[0]] = @($f[1], $f[2], $f[3], $f[4]) } } }
    $mine
}
function script:Save-LotusMcPluginsMine {
    param([string]$Dir, [hashtable]$Mine)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($id in $Mine.Keys) { [void]$sb.Append("$id`t$($Mine[$id] -join "`t")`n") }
    Write-LotusFile (Join-Path $Dir '.lotus/plugins.tsv') $sb.ToString()
}

# A file from the internet into <path>: through a .part, only when it arrived whole → $true
function script:Save-LotusMcDownload {
    param([string]$Url, [string]$Path)
    $part = "$Path.part"
    try {
        $resp = (Get-LotusMcpHttp).GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            if (-not $resp.IsSuccessStatusCode) { return $false }
            $in = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $out = [IO.File]::Create($part)
            try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
        } finally { $resp.Dispose() }
        Move-Item -LiteralPath $part -Destination $Path -Force
        $true
    } catch { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue; $false }
}

# Installs a project from Modrinth, with its required dependencies → $true and $script:McpDone, or $false and McpErr
function script:Install-LotusMcPlugin {
    param([string]$Dir, [string]$Id, [string]$Slug, [string]$Title, [string]$Version, [int]$Depth = 0)
    if ($Id -notmatch '^[A-Za-z0-9]+$') { $script:McpErr = "not a Modrinth project: $Id"; return $false }
    $pick = Get-LotusMcpPick $Id $Version
    if (-not $pick) { $script:McpErr = "$Title has no version for Minecraft $Version"; return $false }
    # only Modrinth's own download server, only a plain file name
    if (-not $pick.Url.StartsWith($script:McpCdn)) { $script:McpErr = "${Title}: unexpected download address"; return $false }
    $file = $pick.File
    if ($file -notmatch '^[A-Za-z0-9._+-]+\.jar$' -or $file.StartsWith('.')) { $file = ($Slug -replace '[^A-Za-z0-9._-]', '-') + '.jar' }
    $plug = Join-Path $Dir 'plugins'
    New-LotusDir $plug | Out-Null; New-LotusDir (Join-Path $Dir '.lotus') | Out-Null
    $tmp = Join-Path $plug ".$file"
    if (-not (Save-LotusMcDownload $pick.Url $tmp)) { $script:McpErr = "${Title}: the download failed"; return $false }
    $sum = (Get-FileHash -LiteralPath $tmp -Algorithm SHA512).Hash.ToLowerInvariant()
    if ($pick.Sha512 -and $sum -cne $pick.Sha512.ToLowerInvariant()) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        $script:McpErr = "${Title}: checksum mismatch – nothing was installed"; return $false
    }
    $mine = Get-LotusMcPluginsMine $Dir
    # an update: the file of the older version goes
    if ($mine.ContainsKey($Id)) {
        $old = $mine[$Id][3]
        if ($old -and $old -cne $file -and $old -notmatch '[\\/]' -and (Test-Path -LiteralPath (Join-Path $plug $old) -PathType Leaf)) { Remove-Item -LiteralPath (Join-Path $plug $old) -Force }
    }
    Move-Item -LiteralPath $tmp -Destination (Join-Path $plug $file) -Force
    $mine[$Id] = @($Slug, $Title, $pick.Version, $file)
    Save-LotusMcPluginsMine $Dir $mine
    $script:McpDone.Add("$Title $($pick.Version)")
    Write-LotusLog INFO minecraft "Plugin installed: $Title $($pick.Version) ($file) in $(Split-Path -Leaf $Dir)"
    # required dependencies that are not there yet (one level deep is enough in practice)
    if ($Depth -lt 2) {
        foreach ($dep in $pick.Deps) {
            if ((Get-LotusMcPluginsMine $Dir).ContainsKey($dep)) { continue }
            if (-not (Install-LotusMcPlugin $Dir $dep $dep $dep $Version ($Depth + 1))) { $script:McpErr = "$Title needs ${dep}: $($script:McpErr)" }
        }
    }
    $true
}

# Name and version from a plugin's plugin.yml (or paper-plugin.yml) → @(name, version)
function script:Get-LotusMcJarInfo {
    param([string]$Jar)
    $yml = Get-LotusZipText $Jar 'plugin.yml'
    if (-not $yml) { $yml = Get-LotusZipText $Jar 'paper-plugin.yml' }
    $name = ''; $ver = ''
    foreach ($line in ([string]$yml) -split "`r?`n") {
        if ($line -match '^name:\s*["'']?([^"'']+?)["'']?\s*$') { $name = $Matches[1] }
        if ($line -match '^version:\s*["'']?([^"'']+?)["'']?\s*$') { $ver = $Matches[1] }
    }
    @($(if ($name) { $name } else { [IO.Path]::GetFileNameWithoutExtension($Jar) }), $(if ($ver) { $ver } else { '?' }))
}

# The plugins in plugins\ → @{ File; Name; Version; From } – From: lotus (LotusBridge), modrinth (installed here) or own
function script:Get-LotusMcPluginsInstalled {
    param([string]$Dir)
    $byFile = @{}
    $mine = Get-LotusMcPluginsMine $Dir
    foreach ($id in $mine.Keys) { $byFile[$mine[$id][3]] = $mine[$id] }
    foreach ($jar in @(Get-ChildItem -LiteralPath (Join-Path $Dir 'plugins') -Filter '*.jar' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($jar.Name -ceq 'LotusBridge.jar') { [pscustomobject]@{ File = $jar.Name; Name = 'LotusBridge'; Version = '–'; From = 'lotus' }; continue }
        if ($byFile.ContainsKey($jar.Name)) { [pscustomobject]@{ File = $jar.Name; Name = $byFile[$jar.Name][1]; Version = $byFile[$jar.Name][2]; From = 'modrinth' }; continue }
        $info = Get-LotusMcJarInfo $jar.FullName
        [pscustomobject]@{ File = $jar.Name; Name = $info[0]; Version = $info[1]; From = 'own' }
    }
}

# Is this .jar a plugin? → $true, or $false with McpErr saying what it is instead
function script:Test-LotusMcJar {
    param([string]$Jar)
    $leaf = Split-Path -Leaf $Jar
    $names = @(Get-LotusZipNames $Jar)
    if (-not $names.Count) { $script:McpErr = "$leaf is not a .jar file"; return $false }
    if ($names -ccontains 'plugin.yml' -or $names -ccontains 'paper-plugin.yml') { return $true }
    if ($names -ccontains 'fabric.mod.json') { $script:McpErr = "$leaf is a Fabric mod – Paper runs plugins, not mods"; return $false }
    if (@($names | Where-Object { $_ -like '*mods.toml' }).Count) { $script:McpErr = "$leaf is a Forge mod – Paper runs plugins, not mods"; return $false }
    $script:McpErr = "$leaf has no plugin.yml – it is not a plugin"
    $false
}

# Dragged files → into plugins\. <server dir> <the dropped line> → $true when one came in (McpDone, McpErr)
function script:Add-LotusMcPluginJars {
    param([string]$Dir, [string]$Line)
    $script:McpDone = [System.Collections.Generic.List[string]]::new(); $script:McpErr = ''
    $plug = Join-Path $Dir 'plugins'
    New-LotusDir $plug | Out-Null
    foreach ($w in @(Split-LotusShellWords $Line)) {
        $p = ConvertTo-LotusCleanPath $w
        $leaf = Split-Path -Leaf $p
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $script:McpErr = "not a file: $leaf"; continue }
        if ($p -notlike '*.jar') { $script:McpErr = "$leaf is not a .jar"; continue }
        if (-not (Test-LotusMcJar $p)) { continue }
        try { Copy-Item -LiteralPath $p -Destination (Join-Path $plug $leaf) -Force -ErrorAction Stop } catch { $script:McpErr = "could not copy $leaf"; continue }
        $script:McpDone.Add((Get-LotusMcJarInfo (Join-Path $plug $leaf))[0])
        Write-LotusLog INFO minecraft "Plugin added by hand: $leaf in $(Split-Path -Leaf $Dir)"
    }
    $script:McpDone.Count -gt 0
}

# Takes a plugin out (its data folder stays, so it keeps its settings if it comes back)
function script:Remove-LotusMcPlugin {
    param([string]$Dir, [string]$File)
    if ($File -notmatch '^[^\\/]+\.jar$' -or $File.StartsWith('.')) { return $false }
    try { Remove-Item -LiteralPath (Join-Path $Dir "plugins/$File") -Force -ErrorAction Stop } catch { return $false }
    $mine = Get-LotusMcPluginsMine $Dir
    foreach ($id in @($mine.Keys)) { if ($mine[$id][3] -ceq $File) { $mine.Remove($id) } }
    Save-LotusMcPluginsMine $Dir $mine
    Write-LotusLog INFO minecraft "Plugin removed: $File from $(Split-Path -Leaf $Dir)"
    $true
}
