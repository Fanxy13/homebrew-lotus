# lotus – runs one Minecraft server in the background for the control center (win/Public/mcc.ps1): the PowerShell
# version of lib/mc/run.zsh, started in a hidden window of its own (Start-LotusDetached), so closing the terminal does
# not stop the server.
#   pwsh -File run.ps1 <server folder>
# Windows has no named pipe like zsh's mkfifo makes: the control center adds commands to the end of .lotus\input, and
# this script hands every new line to the server's console (shown in the log as "[Lotus] > …"). Everything the server
# prints goes to .lotus\console.log. While the server runs, Windows does not go to sleep (SetThreadExecutionState; the
# display may still turn off).
# A Paper server first gets the LotusBridge plugin (ping and TPS), built here with the JDK's javac.
param([Parameter(Mandatory)][string]$Dir)
$ErrorActionPreference = 'Stop'
$Dir = [IO.Path]::GetFullPath($Dir)
$s = Join-Path $Dir '.lotus'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$utf8 = [Text.UTF8Encoding]::new($false)
Set-Location -LiteralPath $Dir

$log = [IO.FileStream]::new((Join-Path $s 'console.log'), [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]'ReadWrite, Delete')
function Write-RunLog { param([string]$Text) $b = $utf8.GetBytes($Text + "`n"); $log.Write($b, 0, $b.Length); $log.Flush() }
function Write-RunNote { param([string]$Text) Write-RunLog "[Lotus] $Text" }
function Set-RunFile { param([string]$Name, [string]$Text) [IO.File]::WriteAllText((Join-Path $s $Name), $Text) }

Set-RunFile 'wrapper' "$PID"
Set-RunFile 'started' "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Remove-Item -LiteralPath (Join-Path $s 'exit'), (Join-Path $s 'pid') -Force -ErrorAction SilentlyContinue

# The words of a Windows command line (CommandLineToArgvW for what start.cmd holds: blanks separate, quotes keep together)
function Split-RunWords {
    param([string]$Text)
    $words = [System.Collections.Generic.List[string]]::new()
    $cur = [System.Text.StringBuilder]::new(); $q = $false; $has = $false
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq '"') { $q = -not $q; $has = $true; continue }
        if (-not $q -and [char]::IsWhiteSpace($ch)) { if ($has) { $words.Add($cur.ToString()); [void]$cur.Clear(); $has = $false }; continue }
        [void]$cur.Append($ch); $has = $true
    }
    if ($has) { $words.Add($cur.ToString()) }
    , $words.ToArray()
}

# The java of start.cmd and its words: "C:\…\bin\java.exe" -Xms4G -Xmx4G -jar "%~dp0server.jar" nogui
$java = $null; $argv = @()
foreach ($line in [IO.File]::ReadAllLines((Join-Path $Dir 'start.cmd'))) {
    if ($line -match '^\s*"([^"]*java[^"]*)"\s+(.*)$') {
        $java = $Matches[1]
        $argv = Split-RunWords ($Matches[2].Replace('%~dp0', "$Dir$([IO.Path]::DirectorySeparatorChar)"))
        break
    }
}
if (-not $java -or -not (Test-Path -LiteralPath $java -PathType Leaf)) {
    Write-RunNote "start.cmd names no java Lotus can find$(if ($java) { ": $java" }) – set the server up again with /minecraft"
    Set-RunFile 'exit' '1'
    Remove-Item -LiteralPath (Join-Path $s 'wrapper') -Force -ErrorAction SilentlyContinue
    exit 1
}

# A program in this folder, its output into the log (the Paper patcher) → its exit code
function Invoke-RunLogged {
    param([string]$Exe, [string[]]$Words)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($w in $Words) { $psi.ArgumentList.Add($w) }
    $psi.WorkingDirectory = $Dir; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $err = $p.StandardError.ReadToEndAsync()
    while ($null -ne ($l = $p.StandardOutput.ReadLine())) { Write-RunLog $l }
    $p.WaitForExit()
    foreach ($l in ($err.Result -split "`r?`n")) { if ($l) { Write-RunLog $l } }
    $p.ExitCode
}

function Get-RunHash {
    param([string[]]$Paths)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($f in $Paths) { $b = [IO.File]::ReadAllBytes($f); [void]$sha.TransformBlock($b, 0, $b.Length, $null, 0) }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        ($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally { $sha.Dispose() }
}

# LotusBridge: built once per source and server version, kept in plugins\LotusBridge.jar
function Build-RunBridge {
    $src = Join-Path $root 'lib/mc/bridge'
    $stamp = Join-Path $s 'bridge'
    $jarOut = Join-Path $Dir 'plugins/LotusBridge.jar'
    $want = "$(Get-RunHash @((Join-Path $src 'LotusBridge.java'), (Join-Path $src 'plugin.yml'))) $(Get-RunHash @((Join-Path $Dir 'server.jar')))"
    $have = if (Test-Path -LiteralPath $stamp) { ([IO.File]::ReadAllText($stamp)).Trim() } else { '' }
    if ((Test-Path -LiteralPath $jarOut) -and $have -ceq $want) { return }
    # it failed for this source and server before: not again on every start
    if ($have -ceq "failed $want") { return }
    Set-RunFile 'bridge' "failed $want"
    $bin = Split-Path -Parent $java
    $javac = Join-Path $bin $(if ($IsWindows) { 'javac.exe' } else { 'javac' })
    if (-not (Test-Path -LiteralPath $javac)) { Write-RunNote 'Ping and TPS need a JDK (javac) – skipped'; Remove-Item -LiteralPath $stamp -Force; return }
    $jars = { @(foreach ($d in 'libraries', 'versions', 'cache') { $p = Join-Path $Dir $d; if (Test-Path -LiteralPath $p) { Get-ChildItem -LiteralPath $p -Recurse -Filter '*.jar' -File | ForEach-Object FullName } }) }
    # Paper keeps its API in libraries\ and versions\ once it has been unpacked – the first time, unpack it now
    if (-not (& $jars).Count) {
        Write-RunNote 'Preparing Paper for its first start …'
        [void](Invoke-RunLogged $java @('-Dpaperclip.patchonly=true', '-jar', 'server.jar'))
    }
    $cp = & $jars
    if (-not $cp.Count) { Write-RunNote "Ping and TPS: Paper's libraries are missing – skipped"; Remove-Item -LiteralPath $stamp -Force; return }
    $tmp = Join-Path $s 'bridge-build'
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $classes = Join-Path $tmp 'classes'
    [void][IO.Directory]::CreateDirectory($classes)
    # the class path as an argument file: Paper has many libraries, a command line has a limit
    $q = { param($t) '"' + $t.Replace('\', '\\') + '"' }
    [IO.File]::WriteAllLines((Join-Path $tmp 'args.txt'), @('-nowarn', '-proc:none', '-encoding', 'UTF-8', '-d', (& $q $classes), '-cp', (& $q ($cp -join [IO.Path]::PathSeparator)), (& $q (Join-Path $src 'LotusBridge.java'))))
    $psi = [System.Diagnostics.ProcessStartInfo]::new($javac)
    $psi.ArgumentList.Add("@$(Join-Path $tmp 'args.txt')")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $e = $p.StandardError.ReadToEndAsync(); $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    [IO.File]::WriteAllText((Join-Path $tmp 'javac.log'), $o + $e.Result)
    if ($p.ExitCode -ne 0) { Write-RunNote 'Ping and TPS: the bridge plugin could not be built (see .lotus\bridge-build\javac.log)'; return }
    Copy-Item -LiteralPath (Join-Path $src 'plugin.yml') -Destination $classes
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $built = Join-Path $tmp 'LotusBridge.jar'
    try { [System.IO.Compression.ZipFile]::CreateFromDirectory($classes, $built) } catch { Write-RunNote 'Ping and TPS: packing the bridge plugin failed'; return }
    [void][IO.Directory]::CreateDirectory((Join-Path $Dir 'plugins'))
    Move-Item -LiteralPath $built -Destination $jarOut -Force
    Set-RunFile 'bridge' $want
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-RunNote 'LotusBridge ready – ping and TPS show in the control center'
}

$conf = if (Test-Path -LiteralPath (Join-Path $s 'server.conf')) { [IO.File]::ReadAllText((Join-Path $s 'server.conf')) } else { '' }
if ($conf -match 'type=paper') { try { Build-RunBridge } catch { Write-RunNote "Ping and TPS: $($_.Exception.Message)" } }

# The server: its console from .lotus\input, its output into the log – in UTF-8 both ways (Java on Windows would use
# the old code page of the system where nothing says otherwise)
$psi = [System.Diagnostics.ProcessStartInfo]::new($java)
foreach ($w in @('-Dfile.encoding=UTF-8', '-Dstdout.encoding=UTF-8', '-Dstderr.encoding=UTF-8') + $argv) { $psi.ArgumentList.Add($w) }
$psi.WorkingDirectory = $Dir; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.StandardInputEncoding = $utf8; $psi.StandardOutputEncoding = $utf8; $psi.StandardErrorEncoding = $utf8
try { $p = [System.Diagnostics.Process]::Start($psi) }
catch {
    Write-RunNote "Java could not be started: $($_.Exception.Message)"
    Set-RunFile 'exit' '1'
    Remove-Item -LiteralPath (Join-Path $s 'wrapper') -Force -ErrorAction SilentlyContinue
    exit 1
}
Set-RunFile 'pid' "$($p.Id)"

# Windows stays awake while the server runs (until this script ends)
if ($IsWindows) {
    try {
        $asm = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly([System.Reflection.AssemblyName]::new('LotusRunAwake'), 'Run')
        $tb = $asm.DefineDynamicModule('LotusRunAwake').DefineType('LotusRunAwake', 'Public, Class')
        $m = $tb.DefinePInvokeMethod('SetThreadExecutionState', 'kernel32.dll', 'Public, Static, PinvokeImpl', 'Standard', [uint32], [type[]]@([uint32]), 'Winapi', 'Unicode')
        $m.SetImplementationFlags('PreserveSig')
        [void]$tb.CreateType().GetMethod('SetThreadExecutionState').Invoke($null, @([uint32]2147483649))     # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
    } catch { }
}

$inputFile = Join-Path $s 'input'
$inOff = 0L; $inPart = ''
$reads = @($p.StandardOutput.ReadLineAsync(), $p.StandardError.ReadLineAsync())
$streams = @($p.StandardOutput, $p.StandardError)
$open = @($true, $true)
while ($open[0] -or $open[1] -or -not $p.HasExited) {
    $busy = $false
    for ($k = 0; $k -lt 2; $k++) {
        while ($open[$k] -and $reads[$k].IsCompleted) {
            $line = $null
            try { $line = $reads[$k].Result } catch { }
            if ($null -eq $line) { $open[$k] = $false; break }
            Write-RunLog $line
            $busy = $true
            $reads[$k] = $streams[$k].ReadLineAsync()
        }
    }
    # new lines at the end of .lotus\input → the server's console
    try {
        $fs = [IO.FileStream]::new($inputFile, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
        try {
            if ($fs.Length -lt $inOff) { $inOff = 0; $inPart = '' }
            if ($fs.Length -gt $inOff) {
                $fs.Position = $inOff
                $buf = [byte[]]::new($fs.Length - $inOff)
                $n = $fs.Read($buf, 0, $buf.Length)
                $inOff += $n
                $text = $inPart + $utf8.GetString($buf, 0, $n)
                $cut = $text.LastIndexOf("`n")
                if ($cut -ge 0) {
                    $inPart = $text.Substring($cut + 1)
                    foreach ($cmd in $text.Substring(0, $cut).Split("`n")) {
                        $cmd = $cmd.TrimEnd("`r")
                        if (-not $cmd -or $p.HasExited) { continue }
                        $p.StandardInput.WriteLine($cmd); $p.StandardInput.Flush()
                        if ($cmd -cne 'stop') { Write-RunLog "[Lotus] > $cmd" }
                    }
                } else { $inPart = $text }
                $busy = $true
            }
        } finally { $fs.Dispose() }
    } catch { }
    if (-not $busy) { Start-Sleep -Milliseconds 60 }
}
$p.WaitForExit()
$code = $p.ExitCode
Set-RunFile 'exit' "$code"
Remove-Item -LiteralPath (Join-Path $s 'pid'), (Join-Path $s 'wrapper') -Force -ErrorAction SilentlyContinue
Write-RunNote "The server stopped (exit code $code)"
$log.Dispose()
