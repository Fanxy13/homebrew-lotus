# /bg on Windows – remove image backgrounds on this PC with BiRefNet or InSPyReNet; the image never leaves it. A port
# of lib/cmd/bg.zsh and lib/bg/{runtime,progress,manage}.zsh. The work is done by the same Python program as on the Mac
# (lib/bg/worker.py), in Lotus' own Python environment (runtime\bg in Lotus' data folder) with PyTorch's Windows build,
# on the processor. Its events come through a pipe. Windows has no signal Lotus could send it, so ctrl-c writes
# "cancel" to it instead. PyTorch has no build for Windows on Arm yet: there /bg says so instead of failing later.
# Drawing what to keep by hand needs the Mac's editor (Swift) – Windows gets the AI's result as it is.
#   /bg remove <image|folder>…   ·   /bg remove (drop images; an empty ⏎ takes the clipboard)   ·   /bg paste
#   /bg models · /bg output · /bg setup [--yes] [model] · /bg doctor · /bg help
# Nothing is downloaded without a yes: the runtime (about 1 GB, from pypi.org) and a model (checked with SHA-256).

$script:BgExt = @('png', 'jpg', 'jpeg', 'webp', 'heic', 'heif', 'avif', 'tif', 'tiff', 'bmp', 'gif')
$script:BgTb = 'transparent-background==1.3.4'      # InSPyReNet's model code (installed without extras)
$script:BgDefaultOut = '~/Pictures/Lotus/Background Removed'
$script:BgWorker = Join-Path (Get-LotusRoot) 'lib/bg/worker.py'
$script:BgRegistryFile = Join-Path (Get-LotusRoot) 'data/bg-models.tsv'
$script:BgRand = [Random]::new()
$script:Bg = @{ Session = ''; Log = ''; Err = @(); ErrLogged = $false; Proc = $null; LastModel = ''; LastBackend = '' }
$script:Bu = @{ On = $false; Live = $false }

function script:Invoke-Lotusbg {
    param([string]$Cmd, [string[]]$Rest)
    Import-LotusLangGroup bg
    try { Invoke-LotusBgCommand $Rest }
    catch [System.OperationCanceledException] {
        # ctrl-c in a screen: the worker was told to stop (in a finally), the screen and the session are closed
        Stop-LotusBgUi
        Remove-LotusBgSession
        Write-LotusLog INFO bg 'Cancelled'
        Write-LotusLine ''
        Write-LotusInfo (T cancelled 'Cancelled.')
        St 130
    }
}

function script:Invoke-LotusBgCommand {
    param([string[]]$Rest)
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    $more = [string[]]@($Rest | Select-Object -Skip 1)
    switch -CaseSensitive ($sub) {
        { $_ -cin '', 'help', '-h', '--help' } { Show-LotusBgHelp; return (St 0) }
        { $_ -cin 'remove', 'rm', 'cut' } { return Invoke-LotusBgRemove $more }
        'edit' {
            Write-LotusWarn (Get-LotusBgText bg_no_editor 'Drawing what to keep needs the editor of the Mac – here the AI result is saved as it is.')
            return Invoke-LotusBgRemove $more
        }
        { $_ -cin 'paste', 'clipboard' } { return Invoke-LotusBgRemove (@('--clipboard') + $more) }
        { $_ -cin 'setup', 'install' } {
            if (-not (Test-LotusBgSystem)) { return (St 1) }
            if ($more -ccontains '--yes') {
                $id = @($more | Where-Object { $_ -cne '--yes' }) | Select-Object -First 1
                return (St $(if (Install-LotusBg (Resolve-LotusBgModel $id) -Yes) { 0 } else { 1 }))
            }
            return (St $(if (Start-LotusBgFirstUse) { 0 } else { 1 }))
        }
        { $_ -cin 'models', 'model', 'cache' } { Show-LotusBgModels; return (St 0) }
        { $_ -cin 'output', 'folder' } {
            Write-LotusHero (T bg_title 'Remove BG') (T bg_q_output 'Output folder')
            if (Select-LotusBgOutput) { Save-LotusSettings; Write-LotusSuccess (T saved '✓ saved').TrimStart('✓ '); return (St 0) }
            return (St 1)
        }
        'doctor' {
            Write-LotusHero "$(T bg_title 'Remove BG') · Doctor"
            $ok = "$(E '1')$(E key)✓$($script:R)"; $bad = "$(E '1;38;5;203')✗$($script:R)"; $opt = "$(E dim)·$($script:R)"
            Show-LotusBgDoctorRows { param($mark, $name, $text) Write-LotusLine "  $mark $(PadR $name 17) $text" } $ok $bad $opt
            Write-LotusBlank
            return (St 0)
        }
    }
    if ((Test-Path -LiteralPath (ConvertTo-LotusCleanPath $sub)) -or $sub -like 'file://*') { return Invoke-LotusBgRemove $Rest }
    Write-LotusError (T bg_unknown 'Unknown /bg command') $sub @('/bg remove <image>   ·   /bg help')
    St 1
}

# A text in this system's words: the Windows one (key_win) when the language files have it
function script:Get-LotusBgText {
    param([string]$Key, [string]$Default = '')
    $w = T "${Key}_win" ''
    if ($w) { return $w }
    T $Key $Default
}

function script:Show-LotusBgHelp {
    Write-LotusHero (T bg_title 'Remove BG') (T bg_tagline)
    $k = E key; $d = E dim; $r = $script:R
    foreach ($row in @("/bg remove <image>|$(T bg_h_remove)", "/bg remove <folder>|$(T bg_h_folder)", "/bg remove|$(T bg_h_drop)",
            "/bg paste|$(T bg_h_paste)", "/bg models|$(T bg_h_models)", "/bg output|$(T bg_h_output)")) {
        $p = $row -split '\|', 2
        Write-LotusLine "    $k$(PadR $p[0] 28)$r$($p[1])"
    }
    Write-LotusBlank
    Write-LotusSection (T bg_h_examples 'Examples'); Write-LotusBlank
    Write-LotusLine "    $d/bg remove ~\Pictures\photo.png$r"
    Write-LotusLine "    $d/bg remove `"~\Desktop\My Photos\beach.heic`"$r"
    Write-LotusLine "    $d/bg remove ~\Pictures\shoot$r"
    Write-LotusBlank
    Write-LotusDim "  $(T bg_h_local)"
    $out = if ([string]$script:S['LOTUS_BG_OUTPUT'] -ceq '@source') { T bg_o_source } else { Format-LotusPath (Expand-LotusBgDir $script:S['LOTUS_BG_OUTPUT']) }
    Write-LotusDim "  $(T bg_model 'Model'): $(Get-LotusBgModelLabel $script:S['LOTUS_BG_MODEL']) · $(T bg_output 'Output folder'): $out"
    if (-not (Test-LotusBgSystem -Quiet)) { Write-LotusBlank; Write-LotusWarn (Get-LotusBgText 'bg_t_BG-008') }
    Write-LotusBlank
}

# ── The models (data/bg-models.tsv) ──────────────────────────

function script:Get-LotusBgModels {
    if ($script:BgModels -and $script:BgModelsFrom -ceq $script:BgRegistryFile) { return $script:BgModels }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($f in Read-LotusTsv $script:BgRegistryFile -Path) {
        if ($f.Count -lt 8) { continue }
        $files = @(foreach ($spec in $f[7] -split ';') { $p = $spec -split '\|'; [pscustomobject]@{ Name = $p[0]; Url = $p[1]; Sha = $p[2]; Bytes = [long]$p[3] } })
        $list.Add([pscustomobject]@{ Id = $f[0]; Engine = $f[1]; Label = $f[2]; Mb = [int]$f[3]; Input = [int]$f[4]; License = $f[5]; Home = $f[6]; Files = $files })
    }
    $script:BgModels = $list.ToArray()
    $script:BgModelsFrom = $script:BgRegistryFile
    $script:BgModels
}
function script:Get-LotusBgModel { param([string]$Id) @(Get-LotusBgModels) | Where-Object { $_.Id -ceq $Id } | Select-Object -First 1 }

function script:Get-LotusBgDirs {
    $d = $script:Paths.Data
    [pscustomobject]@{ Runtime = Join-Path (Join-Path $d 'runtime') 'bg'; Models = Join-Path $d 'models'; Cache = Join-Path $script:Paths.Cache 'bg' }
}

# Installed state of a model: ok, missing or partial (quick: names and sizes)
function script:Get-LotusBgModelState {
    param([string]$Id)
    $m = Get-LotusBgModel $Id
    if (-not $m) { return 'missing' }
    $dir = Join-Path (Get-LotusBgDirs).Models $Id
    $have = 0
    foreach ($f in $m.Files) {
        $i = Get-Item -LiteralPath (Join-Path $dir $f.Name) -ErrorAction SilentlyContinue
        if ($i -and -not $i.PSIsContainer -and $i.Length -eq $f.Bytes) { $have++ }
    }
    if ($have -eq $m.Files.Count) { 'ok' } elseif ($have -or (Test-Path -LiteralPath $dir)) { 'partial' } else { 'missing' }
}

# What "Auto" means on this PC → a model id. The processor does the work on Windows, as on an Intel Mac: BiRefNet Lite,
# unless another model is downloaded already (Auto never downloads a second model on its own).
function script:Get-LotusBgAutoModel {
    $best = 'birefnet-lite'
    if ((Get-LotusBgModelState $best) -eq 'ok') { return $best }
    foreach ($id in 'birefnet', 'birefnet-lite', 'inspyrenet') { if ((Get-LotusBgModelState $id) -eq 'ok') { return $id } }
    $best
}
function script:Resolve-LotusBgModel {
    param([string]$Want)
    if (-not $Want) { $Want = [string]$script:S['LOTUS_BG_MODEL'] }
    if ($Want -ceq 'auto' -or -not (Get-LotusBgModel $Want)) { return Get-LotusBgAutoModel }
    $Want
}
function script:Get-LotusBgModelLabel {
    param([string]$Id)
    if ($Id -ceq 'auto' -or -not $Id) { return "$(T col_auto 'Automatic') · $((Get-LotusBgModel (Get-LotusBgAutoModel)).Label)" }
    $m = Get-LotusBgModel $Id
    if ($m) { $m.Label } else { $Id }
}
function script:Get-LotusBgSizeMb {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = 0L
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $sum += $f.Length }
    [long][Math]::Truncate($sum / 1MB)
}

# ── The runtime: Lotus' own Python environment ───────────────

# Can this PC run it? PyTorch is built for Windows on x64 processors only. → $true, or the error screen and $false
function script:Test-LotusBgSystem {
    param([switch]$Quiet)
    if (-not $IsWindows -or $script:Os.Arch -eq 'x86_64') { return $true }
    if (-not $Quiet) { Show-LotusBgError 'BG-008' 'PyTorch has no build for Windows on Arm yet.' "$(Get-LotusOsDescription)" }
    $false
}

function script:Get-LotusBgPythonExe {
    $rt = (Get-LotusBgDirs).Runtime
    if ($IsWindows) { Join-Path $rt 'Scripts\python.exe' } else { Join-Path $rt 'bin/python3' }
}
# How to start the runtime's Python: without your site-packages and PYTHON* variables, no bytecode, UTF-8
function script:Get-LotusBgPython { , @((Get-LotusBgPythonExe), '-s', '-E', '-B', '-X', 'utf8') }
function script:Get-LotusBgRequirements { Join-Path (Get-LotusRoot) 'lib/bg/requirements-windows-x86_64.txt' }

# The requirements as a hash (their line ends do not count: a checkout may have changed them)
function script:Get-LotusBgReqStamp {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string](Read-LotusFile (Get-LotusBgRequirements)))) | ForEach-Object { $_.ToString('x2') }) -join '' }
    finally { $sha.Dispose() }
}
# The runtime is there and matches this Lotus version's requirements
function script:Test-LotusBgRuntime {
    $stamp = Join-Path (Get-LotusBgDirs).Runtime 'lotus-runtime'
    if (-not (Test-Path -LiteralPath (Get-LotusBgPythonExe) -PathType Leaf) -or -not (Test-Path -LiteralPath $stamp -PathType Leaf)) { return $false }
    ((Read-LotusFile $stamp) -split '\s+')[0] -ceq (Get-LotusBgReqStamp)
}

# A Python for the runtime: 3.10 – 3.14 on x64, with venv → @{ Exe; Args; Version }, or $null. The py launcher first
# (python.org's Pythons), then the PATH. The Microsoft Store's Python keeps what it writes into AppData in a folder of its
# own, where the environment could not be found again – it is left out (as is Windows' stand-in that opens the Store).
function script:Find-LotusBgPython {
    $order = '3.13', '3.12', '3.11', '3.14', '3.10'
    $tries = [System.Collections.Generic.List[object]]::new()
    $py = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($py) { foreach ($v in $order) { $tries.Add(@($py.Source, "-$v")) } }
    foreach ($n in @($order | ForEach-Object { "python$_" }) + @('python3', 'python')) {
        foreach ($c in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) { $tries.Add(@($c.Source)) }
    }
    $seen = @{}
    foreach ($t in $tries) {
        $key = $t -join ' '
        if ($seen[$key] -or $t[0] -match '[\\/]WindowsApps[\\/]') { continue }
        $seen[$key] = $true
        $pre = @($t | Select-Object -Skip 1)
        $v = Invoke-LotusBgProbe $t[0] (@($pre) + @('-c', 'import sys, venv, ensurepip, platform; print("%d.%d %s" % (sys.version_info[:2] + (platform.machine(),)))'))
        if ("$v".Trim() -notmatch '^(3\.1[0-4]) (AMD64|x86_64|amd64)$') { continue }
        return [pscustomobject]@{ Exe = $t[0]; Args = $pre; Version = $Matches[1] }
    }
    $null
}

# What a program prints when it answers at once: no input (a launcher that would ask something gets none), at most 15
# seconds → its output, or '' when it failed
function script:Invoke-LotusBgProbe {
    param([string]$Exe, [string[]]$Arguments)
    $p = Start-LotusBgProcess $Exe $Arguments @{}
    if (-not $p) { return '' }
    try {
        $err = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEndAsync()
        if (-not $p.WaitForExit(15000)) { try { $p.Kill($true) } catch { }; return '' }
        $p.WaitForExit()
        $null = $err.Result
        if ($p.ExitCode -ne 0) { return '' }
        [string]$out.Result
    } catch { '' } finally { $p.Dispose() }
}

# Free space where Lotus keeps its data → GB
function script:Get-LotusBgFreeGb {
    $dir = $script:Paths.Data
    while ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { $dir = Split-Path -Parent $dir }
    try { [long][Math]::Truncate([IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($dir))).AvailableFreeSpace / 1GB) } catch { 999 }
}

# A folder of the settings ("~/Pictures/…") → the real one. Windows' Pictures folder may live elsewhere (OneDrive).
function script:Expand-LotusBgDir {
    param([string]$Dir)
    if ($IsWindows -and $Dir -match '^~[\\/]Pictures(?=$|[\\/])') {
        $pics = [Environment]::GetFolderPath('MyPictures')
        if ($pics) { return ConvertTo-LotusCleanPath ($pics + $Dir.Substring(10)) }
    }
    ConvertTo-LotusCleanPath $Dir
}
function script:Test-LotusBgWritable {
    param([string]$Dir)
    try {
        New-LotusDir $Dir | Out-Null
        $probe = Join-Path $Dir ".lotus-write-test-$PID"
        [IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe -Force
        $true
    } catch { $false }
}

# ── A session: the worker's folder and log for one run ───────

function script:New-LotusBgSession {
    $c = (Get-LotusBgDirs).Cache
    New-LotusDir $c | Out-Null
    $old = (Get-Date).AddHours(-24)
    foreach ($s in @(Get-ChildItem -LiteralPath $c -Directory -Filter 'session.*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $old })) {
        Remove-Item -LiteralPath $s.FullName -Recurse -Force -ErrorAction SilentlyContinue      # left over from a crash
    }
    $script:Bg.Session = Join-Path $c ('session.' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-LotusDir $script:Bg.Session | Out-Null
    $script:Bg.Log = Join-Path $c 'worker.log'
    [IO.File]::WriteAllText($script:Bg.Log, '')
}
function script:Remove-LotusBgSession {
    $s = $script:Bg.Session
    if ($s -and (Split-Path -Leaf $s) -like 'session.*') { Remove-Item -LiteralPath $s -Recurse -Force -ErrorAction SilentlyContinue }
    $script:Bg.Session = ''
}
function script:Add-LotusBgLog {
    param([string]$Text)
    if (-not $Text -or -not $script:Bg.Log) { return }
    try { [IO.File]::AppendAllText($script:Bg.Log, $Text.TrimEnd() + "`n") } catch { }
}

# ── Programs Lotus waits for: the worker, pip, curl ──────────

# A program with its output for Lotus to read – no window and no console of its own, so ctrl-c reaches only Lotus. Its
# input is Lotus' (-WithInput: the worker's "cancel"), or closed at once: nothing it runs can wait for a key.
function script:Start-LotusBgProcess {
    param([string]$Exe, [string[]]$Arguments, [hashtable]$Environment = @{}, [switch]$WithInput)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $psi.CreateNoWindow = $true
    foreach ($k in $Environment.Keys) { $psi.Environment[$k] = [string]$Environment[$k] }
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $WithInput) { $p.StandardInput.Close() }
        $p
    } catch { Write-LotusLog ERROR bg "Could not start ${Exe}: $($_.Exception.Message)"; $null }
}

# The end of a program Lotus started: the worker is asked to stop (it does at its next step and cleans up after itself),
# anything else is stopped with what it started
function script:Stop-LotusBgProc {
    param($P, [switch]$Gently)
    if (-not $P) { return }
    try {
        if (-not $P.HasExited) {
            if ($Gently) {
                try { $P.StandardInput.WriteLine('cancel'); $P.StandardInput.Close() } catch { }
                [void]$P.WaitForExit(3000)
            } else { $P.Kill($true); [void]$P.WaitForExit(3000) }
        }
    } catch { }
    finally { $script:Bg.Proc = $null }
}

# Runs a program and feeds its lines to the progress screen (pip, venv) → its exit code
function script:Invoke-LotusBgFollow {
    param([string]$Tag, [string]$Exe, [string[]]$Arguments)
    $p = Start-LotusBgProcess $Exe $Arguments @{ PYTHONDONTWRITEBYTECODE = '1'; PIP_NO_INPUT = '1'; PYTHONUTF8 = '1' }
    if (-not $p) { return 127 }
    $script:Bg.Proc = $p
    try {
        $streams = @($p.StandardOutput, $p.StandardError)
        $reads = @($streams[0].ReadLineAsync(), $streams[1].ReadLineAsync())
        $open = @($true, $true)
        while ($open[0] -or $open[1]) {
            for ($s = 0; $s -lt 2; $s++) {
                while ($open[$s] -and $reads[$s].IsCompleted) {
                    $line = $null
                    try { $line = $reads[$s].Result } catch { }
                    if ($null -eq $line) { $open[$s] = $false; break }
                    Write-LotusLog TRACE bg "${Tag}: $line"
                    if ($line -like 'Collecting *') { Set-LotusBgNote $line.Substring(11) }
                    elseif ($line -match 'Downloading (.+)$') { Set-LotusBgNote (($Matches[1] -split '\?')[0]) }
                    elseif ($line -like 'Installing collected*') { Set-LotusBgNote (T bg_n_unpack 'unpacking …') }
                    elseif ($line -like 'Successfully installed*') { Set-LotusBgNote '' }
                    elseif ($line -cmatch '^(ERROR|error):') { Write-LotusLog ERROR bg "${Tag}: $line"; Add-LotusBgLog $line }
                    $reads[$s] = $streams[$s].ReadLineAsync()
                }
            }
            Show-LotusBgFrame
            if ($open[0] -or $open[1]) { Wait-LotusBgTick 80 }
        }
        $p.WaitForExit()
        $p.ExitCode
    } finally { Stop-LotusBgProc $p }
}

# curl, with the size of the file it writes as the progress → its exit code
function script:Invoke-LotusBgCurl {
    param([string]$Curl, [string[]]$Arguments, [string]$Part, [long]$Have, [long]$Total)
    $p = Start-LotusBgProcess $Curl $Arguments
    if (-not $p) { return 127 }
    $script:Bg.Proc = $p
    try {
        $err = $p.StandardError.ReadToEndAsync()
        $null = $p.StandardOutput.ReadToEndAsync()
        while (-not $p.HasExited) {
            $i = Get-Item -LiteralPath $Part -ErrorAction SilentlyContinue
            Set-LotusBgProgress ($Have + $(if ($i) { $i.Length } else { 0 })) $Total
            Show-LotusBgFrame
            Wait-LotusBgTick 100
        }
        $p.WaitForExit()
        Add-LotusBgLog $err.Result
        $p.ExitCode
    } finally { Stop-LotusBgProc $p }
}

# One worker command, its events turned into the progress screen → the worker's status (1 with $script:Bg.Err set)
#   stage <name> · info <key> <value> · image <n> <total> <path> · done <in> <out> <s> · skip · warn · error · end <status>
function script:Invoke-LotusBgWorker {
    param([string[]]$Arguments)
    $b = $script:Bg
    $b.Err = @(); $b.ErrLogged = $false; $b.Info = @{}
    $b.Done = [System.Collections.Generic.List[object]]::new()
    $b.Skip = [System.Collections.Generic.List[object]]::new()
    $b.Warn = [System.Collections.Generic.List[object]]::new()
    $py = Get-LotusBgPython
    New-LotusDir $script:Paths.State | Out-Null
    $vars = @{ LOTUS_LOG = $script:Paths.Log; LOTUS_LOG_LEVEL = [string]$script:S['LOTUS_LOG_LEVEL']; LOTUS_VERBOSE = [string]$env:LOTUS_VERBOSE
        PYTHONDONTWRITEBYTECODE = '1'; HF_HUB_OFFLINE = '1'; LOTUS_BG_CANCEL = 'stdin'
    }
    $p = Start-LotusBgProcess $py[0] (@($py | Select-Object -Skip 1) + @($script:BgWorker) + $Arguments) $vars -WithInput
    if (-not $p) { $b.Err = @('BG-011', 'Lotus could not start the background remover.', $py[0]); return 1 }
    $b.Proc = $p
    Write-LotusLog DEBUG bg "Worker: $($Arguments[0]) (pid $($p.Id))"
    $rc = -1
    try {
        $err = $p.StandardError.ReadToEndAsync()
        $read = $p.StandardOutput.ReadLineAsync()
        $open = $true
        while ($open) {
            while ($read.IsCompleted) {
                $line = $null
                try { $line = $read.Result } catch { }
                if ($null -eq $line) { $open = $false; break }
                $f = $line -split "`t"
                switch -CaseSensitive ($f[0]) {
                    'end' { $rc = Get-LotusInt $f[1] 2 }
                    'stage' { Set-LotusBgStage $f[1] }
                    'info' {
                        $b.Info[$f[1]] = $(if ($f.Count -gt 2) { $f[2] } else { '' })
                        if ($f[1] -cin 'model', 'backend', 'resolution') { Set-LotusBgInfo $f[1] $f[2] }
                    }
                    'image' {
                        $n = Get-LotusInt $f[1] 1; $all = Get-LotusInt $f[2] 1
                        Set-LotusBgBatch $n $all
                        $name = if ($f.Count -gt 3 -and $f[3]) { Split-Path -Leaf $f[3] } else { '' }
                        if ($all -gt 1) { Set-LotusBgSub "$n / $all · $name"; Reset-LotusBgFrom 'load_image' }
                        Set-LotusBgInfo 'image' $name
                    }
                    'done' { $b.Done.Add(@($f[1], $f[2], $f[3])) }
                    'skip' { $b.Skip.Add(@($f[1], $(if ($f.Count -gt 3) { $f[3] } else { '' }))) }
                    'warn' { $b.Warn.Add(@($f[1], $f[2])); Write-LotusLog WARN bg $f[2] }
                    'error' { $b.Err = @($f[1], $f[2], $(if ($f.Count -gt 3) { $f[3] } else { '' })); $b.ErrLogged = $true }
                }
                $read = $p.StandardOutput.ReadLineAsync()
            }
            Show-LotusBgFrame
            if ($open) { Wait-LotusBgTick 80 }
        }
        $p.WaitForExit()
        $st = $p.ExitCode
        Add-LotusBgLog $err.Result
    } finally { Stop-LotusBgProc $p -Gently }
    if ($rc -lt 0) { $rc = $st }
    if ($rc -and -not $b.Err.Count -and $rc -ne 130) {
        $tail = @(Get-Content -LiteralPath $b.Log -Tail 3 -ErrorAction SilentlyContinue) -join ' '
        $b.Err = @('BG-011', "The background remover stopped unexpectedly (status $rc).", $tail)
    }
    if ($b.Err.Count) { return 1 }
    $rc
}

# ── The progress screen: a lotus that blooms while the work gets done ──
# The flower opens with the steps that are really done (and with real download bytes); while a step runs it only drifts
# a little further and pollen rises – never a made-up percentage. The pixels are data/bloom.txt in the theme's colors.
# Without a terminal (scripts, -V) one plain line per step.

function script:Get-LotusBgNow { [datetime]::UtcNow.Ticks / 1e7 }

function script:Start-LotusBgUi {
    param([string]$Title, [string[]]$Stages)
    $now = Get-LotusBgNow
    $b = @{ Title = $Title; Cur = ''; Note = ''; Sub = ''; Info = @{}; Done = 0L; Total = 0L; Img = 0; Imgs = 0; Finished = $false
        Bloom = 0.0; Frame = 0; Size = ''; T0 = $now; Ts = $now; On = $true; Live = $false
        Keys = [System.Collections.Generic.List[string]]::new(); Labels = [System.Collections.Generic.List[string]]::new()
        Short = [System.Collections.Generic.List[string]]::new(); Times = [System.Collections.Generic.List[string]]::new()
        InfoKeys = [System.Collections.Generic.List[string]]::new()
        Px = [System.Collections.Generic.List[double]]::new(); Py = [System.Collections.Generic.List[double]]::new()
        Pv = [System.Collections.Generic.List[double]]::new(); Pl = [System.Collections.Generic.List[int]]::new()
    }
    $script:Bu = $b
    foreach ($s in $Stages) { Add-LotusBgStage $s }
    $b.Live = (Test-LotusOutTty) -and (Test-LotusTty) -and -not $script:KeyQueueActive -and $env:LOTUS_VERBOSE -ne '1'
    if ($b.Live) {
        Import-LotusBloom
        Enter-LotusKeys
        Write-LotusRaw "$([char]27)[?1049h$([char]27)[?25l$([char]27)[?7l$([char]27)[2J"
    } else { Write-LotusHeader $Title }
}

# Back to the normal terminal (safe to call more than once)
function script:Stop-LotusBgUi {
    $b = $script:Bu
    if (-not $b.On) { return }
    $b.On = $false
    if ($b.Live) { Write-LotusRaw "$([char]27)[0m$([char]27)[?7h$([char]27)[?25h$([char]27)[?1049l"; Exit-LotusKeys }
}

# "key|Label[|Short]" – Short is the word in the line of steps (default bg_ss_<key>)
function script:Add-LotusBgStage {
    param([string]$Spec)
    $b = $script:Bu
    $f = $Spec -split '\|'
    if ($b.Keys.Contains($f[0])) { return }
    $b.Keys.Add($f[0]); $b.Labels.Add($f[1])
    $b.Short.Add($(if ($f.Count -gt 2 -and $f[2]) { $f[2] } else { T "bg_ss_$($f[0])" $f[1] }))
    $b.Times.Add('')
}

# <key> – the stages before it count as done
function script:Set-LotusBgStage {
    param([string]$Key)
    $b = $script:Bu
    if ($Key -ceq $b.Cur) { return }
    $now = Get-LotusBgNow
    for ($i = 0; $i -lt $b.Keys.Count; $i++) { if ($b.Keys[$i] -ceq $b.Cur -and -not $b.Times[$i]) { $b.Times[$i] = [string]([Math]::Max(0.01, $now - $b.Ts)) } }
    $b.Cur = $Key; $b.Ts = $now; $b.Note = ''; $b.Done = 0L; $b.Total = 0L
    if (-not $b.Live -and $b.On -and $Key -cne '__end') {
        $i = $b.Keys.IndexOf($Key)
        Write-LotusStep $(if ($i -ge 0) { $b.Labels[$i] } else { $Key })
    }
    if ($Key -cne '__end') { Write-LotusLog DEBUG bg "Stage: $Key" }
}
function script:Set-LotusBgInfo { param([string]$Key, [string]$Value) $b = $script:Bu; if (-not $b.InfoKeys.Contains($Key)) { $b.InfoKeys.Add($Key) }; $b.Info[$Key] = $Value }
# Next image of a batch: the stages from <key> on start again
function script:Reset-LotusBgFrom {
    param([string]$Key)
    $b = $script:Bu
    $i = $b.Keys.IndexOf($Key)
    if ($i -lt 0) { return }
    for (; $i -lt $b.Keys.Count; $i++) { $b.Times[$i] = '' }
    $b.Cur = ''
}
function script:Set-LotusBgNote { param([string]$Text) $script:Bu.Note = $Text }
function script:Set-LotusBgSub { param([string]$Text) $script:Bu.Sub = $Text }
function script:Set-LotusBgBatch { param([int]$N, [int]$All) $script:Bu.Img = $N; $script:Bu.Imgs = $All }
function script:Set-LotusBgProgress { param([long]$Done, [long]$Total) $script:Bu.Done = $Done; $script:Bu.Total = $Total }

# All stages done: the flower opens fully, a short moment, then back
function script:Complete-LotusBgUi {
    Set-LotusBgStage '__end'
    $script:Bu.Cur = ''; $script:Bu.Finished = $true
    if (-not $script:Bu.Live) { return }
    for ($i = 0; $i -lt 14; $i++) { Show-LotusBgFrame; Wait-LotusBgTick 60 }
}

# A short pause that notices ctrl-c while the screen is up: it stops the work (thrown, so every finally runs)
function script:Wait-LotusBgTick {
    param([int]$Ms = 80)
    $end = [datetime]::UtcNow.AddMilliseconds($Ms)
    do {
        if ($script:Bu.Live) {
            $stop = $false
            try {
                while ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C -or $k.KeyChar -eq [char]3)) { $stop = $true }
                }
            } catch { }
            if ($stop) { throw [System.OperationCanceledException]::new('ctrl-c') }
        }
        Start-Sleep -Milliseconds 15
    } while ([datetime]::UtcNow -lt $end)
}

# The frames of data/bloom.txt (once) and their colors for the theme
function script:Import-LotusBloom {
    $theme = [string]$script:S['LOTUS_THEME']
    if ($script:Bloom -and $script:Bloom.Theme -ceq $theme) { return }
    if (-not $script:Bloom) {
        $frames = [System.Collections.Generic.List[string[]]]::new()
        $cur = [System.Collections.Generic.List[string]]::new()
        foreach ($l in [IO.File]::ReadAllLines((Join-Path (Get-LotusRoot) 'data/bloom.txt'))) {
            $l = $l.TrimEnd("`r")
            if ($l.StartsWith('#')) { continue }
            if ($l -ceq '%') { $frames.Add($cur.ToArray()); $cur.Clear(); continue }
            $cur.Add($l)
        }
        $script:Bloom = @{ Frames = $frames; W = $frames[0][0].Length; H = [Math]::Truncate($frames[0].Count / 2) }
    }
    $bl = $script:Bloom
    $bl.Theme = $theme
    # (pixel codes are case-sensitive: y and Y, g and G are different shades)
    $bl.Fg = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $bl.Bg = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $bl.Rows = @{}
    $th = $script:Themes[$theme]; if (-not $th) { $th = $script:Themes['matcha'] }
    $shade = { param($code, $rgb, $kk) $sgr = ConvertTo-LotusSgr (Get-LotusRamp $rgb $kk); $bl.Fg[$code] = $sgr; $bl.Bg[$code] = ConvertTo-LotusBackground $sgr }
    for ($n = 0; $n -le 9; $n++) { & $shade ([string]$n) $th[0] ($n / 9.0) }
    & $shade 'y' $th[3] 0.45; & $shade 'Y' $th[3] 0.8
    & $shade 'g' $th[1] 0.25; & $shade 'G' $th[1] 0.55
}

# One frame as terminal rows: two pixels per cell (▀ ▄ █), colors change only when needed → @{ Rows; Mask }
function script:Get-LotusBloomRows {
    param([int]$F)
    $bl = $script:Bloom
    if ($bl.Rows.ContainsKey($F)) { return $bl.Rows[$F] }
    $px = $bl.Frames[$F]
    $rows = [string[]]::new($bl.H); $masks = [string[]]::new($bl.H)
    $esc = [char]27
    for ($r = 0; $r -lt $bl.H; $r++) {
        $top = $px[2 * $r]; $bot = $px[2 * $r + 1]
        $out = [System.Text.StringBuilder]::new(); $mask = [System.Text.StringBuilder]::new(); $cur = 'x'
        for ($c = 0; $c -lt $bl.W; $c++) {
            $t = [string]$top[$c]; $u = [string]$bot[$c]
            if ($t -ceq '.' -and $u -ceq '.') { $want = '0'; $ch = ' '; [void]$mask.Append(' ') }
            elseif ($u -ceq '.') { $want = $bl.Fg[$t]; $ch = '▀'; [void]$mask.Append('x') }
            elseif ($t -ceq '.') { $want = $bl.Fg[$u]; $ch = '▄'; [void]$mask.Append('x') }
            elseif ($t -ceq $u) { $want = $bl.Fg[$t]; $ch = '█'; [void]$mask.Append('x') }
            else { $want = "$($bl.Fg[$t]);$($bl.Bg[$u])"; $ch = '▀'; [void]$mask.Append('x') }
            if ($want -cne $cur) { [void]$out.Append("$esc[0;$($want)m"); $cur = $want }
            [void]$out.Append($ch)
        }
        $rows[$r] = $out.ToString() + "$esc[0m"
        $masks[$r] = $mask.ToString()
    }
    $res = @{ Rows = $rows; Mask = $masks }
    $bl.Rows[$F] = $res
    $res
}

# How far the flower should be open: the share of steps really done. While a step runs it may drift up to half a step
# further (slowing down); real download bytes count exactly.
function script:Get-LotusBgTarget {
    $b = $script:Bu
    if ($b.Finished) { return 1.0 }
    $n = $b.Keys.Count
    $done = @($b.Times | Where-Object { $_ }).Count
    $within = 0.0
    if ($b.Cur) {
        if ($b.Total -gt 0) { $within = [double]$b.Done / $b.Total }
        else { $within = 0.5 * (1 - [Math]::Exp(-((Get-LotusBgNow) - $b.Ts) / 6.0)) }
    }
    $frac = ($done + $within) / [Math]::Max(1, $n)
    if ($b.Imgs -gt 1) { $frac = ($b.Img - 1 + $frac) / $b.Imgs }
    [Math]::Min(1.0, $frac)
}

# Pollen: specks that leave the petal tips once the flower opens and drift up and outwards
function script:Update-LotusBgPollen {
    param([bool]$Burst)
    $b = $script:Bu; $W = $script:Bloom.W; $H = $script:Bloom.H; $rnd = $script:BgRand
    if ($Burst -or ($b.Bloom -gt 0.4 -and $rnd.Next(100) -lt 30)) {
        for ($j = 0; $j -lt $(if ($Burst) { 6 } else { 1 }); $j++) {
            $side = $rnd.Next(1000) / 1000.0 - 0.5
            $b.Px.Add($W / 2.0 + $side * 18 * $b.Bloom); $b.Py.Add($H * (0.55 - 0.3 * $b.Bloom) + $rnd.Next(100) / 100.0)
            $b.Pv.Add($side * 0.35); $b.Pl.Add(0)
        }
    }
    $nx = [System.Collections.Generic.List[double]]::new(); $ny = [System.Collections.Generic.List[double]]::new()
    $nv = [System.Collections.Generic.List[double]]::new(); $nl = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $b.Px.Count; $i++) {
        if ($b.Pl[$i] -ge 26 -or $b.Py[$i] -le 0) { continue }
        $nx.Add($b.Px[$i] + $b.Pv[$i] + [Math]::Sin($b.Frame * 0.4 + $i + 1) * 0.15); $ny.Add($b.Py[$i] - 0.14)
        $nv.Add($b.Pv[$i]); $nl.Add($b.Pl[$i] + 1)
    }
    $b.Px = $nx; $b.Py = $ny; $b.Pv = $nv; $b.Pl = $nl
}

function script:Format-LotusBgSecs {
    param([double]$S)
    if ($S -lt 60) { return $S.ToString('0.0', [cultureinfo]::InvariantCulture) + 's' }
    '{0}m {1:00}s' -f [Math]::Truncate($S / 60), [Math]::Truncate($S % 60)
}

# One frame: every line placed by cursor position with line wrap off, so nothing can run through the drawing
function script:Show-LotusBgFrame {
    $b = $script:Bu
    if (-not $b.Live -or -not $b.On) { return }
    $b.Frame++
    $size = Get-LotusSize
    $W = $size[0]; $H = $size[1]
    $esc = [char]27
    $sb = [System.Text.StringBuilder]::new()
    if ("$W $H" -cne $b.Size) { [void]$sb.Append("$esc[2J"); $b.Size = "$W $H" }
    $d = "$esc[$($script:C['dim'])m"; $a = "$esc[$($script:C['accent'])m"; $k = "$esc[$($script:C['key'])m"; $bo = "$esc[1m"; $R = "$esc[0m"
    $now = Get-LotusBgNow
    $t = $now - $b.T0
    $bl = $script:Bloom
    $art = $W -ge $bl.W + 8 -and $H -ge $bl.H + 14
    $y0 = if ($H -ge 14) { 2 } else { 1 }
    $block = 9 + $(if ($art) { $bl.H + 2 } else { 0 })
    $free = [Math]::Max(0, $H - $y0 - 1 - $block)
    $line = { param([int]$row, [string]$text, [int]$col) [void]$sb.Append("$esc[$row;1H$esc[2K"); if ($col -gt 0) { [void]$sb.Append("$esc[$row;$($col)H") }; [void]$sb.Append($text) }
    $center = { param([int]$len) [Math]::Max(1, [Math]::Truncate(($W - $len) / 2) + 1) }

    # the title, and the image on the right
    & $line $y0 "$a◇$R $($bo)lotus$R$d / $R$bo$($b.Title)$R" 5
    $sub = if ($b.Sub) { $b.Sub } else { [string]$b.Info['image'] }
    $room = $W - $b.Title.Length - 20
    if ($sub -and $room -gt 8) {
        if ($sub.Length -gt $room) { $sub = '…' + $sub.Substring($sub.Length - ($room - 1)) }
        [void]$sb.Append("$esc[$y0;$($W - $sub.Length - 3)H$d$sub$R")
    }
    $y = $y0 + 2 + [Math]::Truncate($free / 2)

    # the flower, its pollen and its water
    if ($art) {
        $target = Get-LotusBgTarget
        if ($target -gt $b.Bloom) { $b.Bloom += ($target - $b.Bloom) * $(if ($b.Finished) { 0.3 } else { 0.1 }) }
        $f = [int][Math]::Truncate($b.Bloom * ($bl.Frames.Count - 1) + 0.5)
        $rows = Get-LotusBloomRows $f
        $x = [Math]::Truncate(($W - $bl.W) / 2) + 1
        for ($i = 0; $i -lt $bl.H; $i++) { & $line ($y + $i) $rows.Rows[$i] $x }
        Update-LotusBgPollen ($b.Finished -and $b.Frame % 5 -eq 0)
        $y2 = "$esc[$($script:C['key2'])m"
        for ($i = 0; $i -lt $b.Px.Count; $i++) {
            $px = [int][Math]::Truncate($b.Px[$i]) + 1; $py = [int][Math]::Truncate($b.Py[$i]) + 1
            if ($px -lt 1 -or $px -gt $bl.W -or $py -lt 1 -or $py -gt $bl.H) { continue }
            if ($rows.Mask[$py - 1][$px - 1] -ne ' ') { continue }
            $glyph = if ($b.Pl[$i] -lt 12) { '•' } else { '·' }
            [void]$sb.Append("$esc[$($y + $py - 1);$($x + $px - 1)H$y2$glyph$R")
        }
        $water = [System.Text.StringBuilder]::new()
        $reach = [int][Math]::Truncate(6 + 13 * $b.Bloom); $half = [Math]::Truncate($bl.W / 2)
        for ($c = 0; $c -lt $bl.W; $c++) {
            $v = [Math]::Sin($c * 0.55 - $t * 2.6) + 0.6 * [Math]::Sin($c * 0.21 + $t * 1.3)
            if ([Math]::Abs($c - $half) -gt $reach + 2) { [void]$water.Append(' ') }
            elseif ($v -gt 1.05) { [void]$water.Append("$a~") }
            elseif ($v -gt 0.55) { [void]$water.Append("$d~") }
            else { [void]$water.Append(' ') }
        }
        & $line ($y + $bl.H) "$($water.ToString())$R" $x
        $y += $bl.H + 2
    }

    # the current step, its bar, a note
    $idx = $b.Keys.IndexOf($b.Cur)
    $bw = [Math]::Max(8, [Math]::Min(36, $W - 12))
    if ($b.Finished) { $done = T bg_done 'Done'; $lab = "$k✓$R $bo$done$R"; $n = $done.Length + 2 }
    elseif ($idx -ge 0) { $g = @('◇', '◈', '◆', '◈')[[Math]::Truncate($b.Frame / 3) % 4]; $lab = "$a$g$R $bo$($b.Labels[$idx])$R"; $n = $b.Labels[$idx].Length + 2 }
    else { $lab = ''; $n = 0 }
    & $line $y $lab (& $center $n)
    $bar = [System.Text.StringBuilder]::new()
    if ($b.Finished) { [void]$bar.Append("$k$([string]::new([char]0x2501, $bw))$R") }
    elseif ($b.Total -gt 0) {
        $fill = [int][Math]::Min($bw, [Math]::Truncate($b.Done * $bw / $b.Total))
        [void]$bar.Append("$k$([string]::new([char]0x2501, $fill))$d$([string]::new([char]0x2501, $bw - $fill))$R")
    } else {
        # a light that glides back and forth – activity, not a percentage
        $span = $bw - 6; $pos = $b.Frame % (2 * $span); if ($pos -gt $span) { $pos = 2 * $span - $pos }
        for ($i = 0; $i -lt $bw; $i++) {
            if ($i -ge $pos -and $i -lt $pos + 6) { [void]$bar.Append("$k━") }
            elseif ($i -eq $pos - 1 -or $i -eq $pos + 6) { [void]$bar.Append("$a━") }
            else { [void]$bar.Append("$d━") }
        }
        [void]$bar.Append($R)
    }
    & $line ($y + 1) $bar.ToString() (& $center $bw)
    $note = $b.Note
    if ($b.Total -gt 0) {
        $note = "$([Math]::Truncate($b.Done * 100 / $b.Total))% · $([Math]::Truncate($b.Done / 1MB)) / $([Math]::Truncate($b.Total / 1MB)) MB$(if ($note) { " · $note" })"
    }
    if ($note.Length -gt $W - 8) { $note = $note.Substring(0, [Math]::Max(0, $W - 9)) + '…' }
    & $line ($y + 2) "$d$note$R" (& $center $note.Length)

    # all steps in one line (or "3 / 5" when it does not fit)
    $strip = [System.Text.StringBuilder]::new(); $plain = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $b.Keys.Count; $i++) {
        $s = $b.Short[$i]
        if ($i) { [void]$strip.Append('   '); [void]$plain.Append('   ') }
        if ($b.Times[$i] -or $b.Finished) { [void]$strip.Append("$k✓$R $s") }
        elseif ($i -eq $idx) { [void]$strip.Append("$a◆$R $bo$s$R") }
        else { [void]$strip.Append("$d· $s$R") }
        [void]$plain.Append("x $s")
    }
    $ps = $plain.ToString(); $ss = $strip.ToString()
    if ($ps.Length -gt $W - 6) { $ps = "$(if ($idx -ge 0) { $idx + 1 } else { $b.Keys.Count }) / $($b.Keys.Count)"; $ss = "$d$ps$R" }
    & $line ($y + 4) $ss (& $center $ps.Length)

    # model · backend · size · time, and how to stop
    $info = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @('model', 'backend', 'resolution', 'python') + @($b.InfoKeys | Where-Object { $_ -cnotin 'model', 'backend', 'resolution', 'python', 'image' })) {
        if ($b.Info[$key]) { $info.Add([string]$b.Info[$key]) }
    }
    $info.Add((Format-LotusBgSecs $t))
    $it = $info -join ' · '
    if ($it.Length -gt $W - 8) { $it = $it.Substring(0, [Math]::Max(0, $W - 9)) + '…' }
    & $line ($y + 6) "$d$it$R" (& $center $it.Length)
    $cc = T bg_ctrl_c 'ctrl-c cancels'
    & $line ($y + 8) "$d$cc$R" (& $center $cc.Length)
    Write-LotusRaw $sb.ToString()
}

# ── Errors ────────────────────────────────────────────────────

# What happened, why, what helps; the details stay in the log
function script:Show-LotusBgError {
    param([string]$Code = 'BG-011', [string]$Reason, [string]$Detail)
    if (-not $Code) { $Code = 'BG-011' }
    if (-not $script:Bg.ErrLogged) { Write-LotusLog ERROR bg "$Code $Reason$(if ($Detail) { " – $Detail" })" }
    $script:Bg.ErrLogged = $false
    $cols = Get-LotusColumns; if ($cols -le 20) { $cols = 100 }
    $d = E dim; $e = E '1;38;5;203'; $r = $script:R
    Write-LotusHero (T bg_failed 'Background removal failed')
    Write-LotusLine "    $($script:B)$(Get-LotusBgText "bg_e_$Code" (T 'bg_e_BG-011'))$r"
    Write-LotusBlank
    if ($Reason) {
        Write-LotusSection (T bg_reason 'Reason')
        Write-LotusLine "    $(Convert-LotusHere $Reason)"
        if ($Detail) { Write-LotusLine "    $d$(Cut ((Convert-LotusHere $Detail).Replace((Get-LotusHome), '~')) ($cols - 8))$r" }
        Write-LotusBlank
    }
    Write-LotusSection (T bg_try 'Try')
    foreach ($t in @(@((Get-LotusBgText "bg_t_$Code" '') -split '\|') + @(T bg_t_doctor 'Run /lotus doctor')) | Where-Object { $_ }) { Write-LotusLine "    • $t" }
    Write-LotusBlank
    Write-LotusLine "    $d$(T bg_error_id 'Error ID'): $r$e$Code$r$d   ·   $(T bg_details 'details'): /lotus log$r"
    Write-LotusBlank
}

# The error the worker (or an install step) reported
function script:Show-LotusBgLastError {
    $e = @($script:Bg.Err) + @('', '', '')
    Show-LotusBgError $e[0] $e[1] $e[2]
}

# After a failure: another installed model, when the model was the problem → "model <id>", or $null
function script:Get-LotusBgFallback {
    param([string]$Code, [string]$Model)
    if (-not (Test-LotusTty) -or $Code -cnotin 'BG-004', 'BG-009') { return $null }
    foreach ($id in 'birefnet', 'inspyrenet', 'birefnet-lite') {
        if ($id -ceq $Model -or (Get-LotusBgModelState $id) -ne 'ok') { continue }
        $q = (T bg_fb_model '%1 failed. Try %2 instead?').Replace('%1', (Get-LotusBgModelLabel $Model)).Replace('%2', (Get-LotusBgModelLabel $id))
        if (Read-LotusConfirm $q 'y') { return "model $id" }
        return $null
    }
    $null
}

# ── Paths, the drop zone, the clipboard ──────────────────────

# The words given → @{ Images; Missing }: a path typed with spaces but without quotes is put back together, a folder
# becomes the images in it (not the cut-outs made before)
function script:Get-LotusBgImages {
    param([string[]]$Words)
    $found = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $p = ConvertTo-LotusCleanPath $Words[$i]
        if (Test-Path -LiteralPath $p) { $found.Add($p); continue }
        $ok = $false
        for ($j = $i + 1; $j -lt $Words.Count; $j++) {
            $q = ConvertTo-LotusCleanPath (($Words[$i..$j]) -join ' ')
            if (Test-Path -LiteralPath $q) { $found.Add($q); $i = $j; $ok = $true; break }
        }
        if (-not $ok) { $missing.Add($Words[$i]) }
    }
    $images = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $found) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $p -File | Where-Object { $script:BgExt -contains $_.Extension.TrimStart('.').ToLowerInvariant() -and $_.Name -notmatch '_no_bg(_\d+)?\.png$' } | Sort-Object Name)) { $images.Add($f.FullName) }
        } else { $images.Add($p) }
    }
    [pscustomobject]@{ Images = $images.ToArray(); Missing = $missing.ToArray() }
}

# The drop zone: File Explorer types the path of what is dropped into the window, Lotus reads it without running
# anything. An empty ⏎ takes the clipboard. → the words (none: cancelled)
function script:Read-LotusBgPaths {
    Write-LotusHero (T bg_title 'Remove BG') (T bg_tagline)
    $W = Get-LotusColumns
    if ($W -ge 44) { Write-LotusDropZone ([Math]::Min(60, $W - 8)) (T bg_drop_here 'Drop images here') (T bg_drop_types) }
    else { Write-LotusText (T bg_drop); Write-LotusDim "  $(T bg_drop_hint)" }
    $clip = Get-LotusBgClipboard -Peek
    if ($clip -like 'image *') { Write-LotusLine "    $(E key)✓$($script:R) $((T bg_clip_image).Replace('%s', ($clip.Substring(6) -replace 'x', ' × ')))" }
    elseif ($clip -like 'files *') { Write-LotusLine "    $(E key)✓$($script:R) $((T bg_clip_files).Replace('%s', $clip.Substring(6)))" }
    Write-LotusDim "  $(if ($clip -ceq 'none') { T bg_drop_keys } else { T bg_drop_keys_clip })"
    Write-LotusBlank
    $line = Read-LotusLine '' ''
    if ($null -eq $line) { return }
    if (-not $line.Trim() -or $line.Trim().ToLowerInvariant() -cin 'v', 'paste', 'clipboard') {
        if ($clip -cne 'none') { Save-LotusBgClipboard }
        return
    }
    Split-LotusShellWords $line
}

# What the clipboard holds: "files <n>", "image <w>x<h>" or "none" (Windows Forms, which needs a single-threaded
# apartment – PowerShell 7 has one; else Windows PowerShell answers)
function script:Get-LotusBgClipboard {
    param([switch]$Peek)
    if (-not $IsWindows) { return 'none' }
    $r = Invoke-LotusBgClipboard ''
    if ($r.Count) { return [string]$r[0] }
    'none'
}

# The clipboard as input → paths: copied files as they are, an image saved as a PNG in Lotus' cache (removed after a
# day) – with its transparency when the program that copied it put a PNG there
function script:Save-LotusBgClipboard {
    if (-not $IsWindows) { return @() }
    $dir = Join-Path (Get-LotusBgDirs).Cache 'clipboard'
    New-LotusDir $dir | Out-Null
    $old = (Get-Date).AddHours(-24)
    Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $old } | Remove-Item -Force -ErrorAction SilentlyContinue
    $png = Join-Path $dir "Clipboard $((Get-Date).ToString('yyyy-MM-dd HH.mm.ss', [cultureinfo]::InvariantCulture)).png"
    $r = @(Invoke-LotusBgClipboard $png)
    if (-not $r.Count -or $r[0] -ceq 'none') { return @() }
    $paths = @($r | Select-Object -Skip 1 | Where-Object { $_ })
    if ($paths.Count) { Write-LotusLog INFO bg "From the clipboard: $($paths.Count) item(s)" }
    $paths
}

# The clipboard, read (and an image written to <png> when given) → @(what it holds, paths…)
function script:Invoke-LotusBgClipboard {
    param([string]$Png)
    $code = {
        param([string]$Png)
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $cb = [System.Windows.Forms.Clipboard]
        if ($cb::ContainsFileDropList()) {
            $files = @($cb::GetFileDropList())
            "files $($files.Count)"
            if ($Png) { $files }
            return
        }
        $bytes = $null
        if ($cb::ContainsData('PNG')) { $s = $cb::GetData('PNG'); if ($s -is [IO.MemoryStream]) { $bytes = $s.ToArray() } }
        if ($bytes -and $bytes.Length -gt 24) {
            $w = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
            $h = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
            "image $($w)x$h"
            if ($Png) { [IO.File]::WriteAllBytes($Png, $bytes); $Png }
            return
        }
        if ($cb::ContainsImage()) {
            $img = $cb::GetImage()
            "image $($img.Width)x$($img.Height)"
            if ($Png) { $img.Save($Png, [System.Drawing.Imaging.ImageFormat]::Png); $Png }
            return
        }
        'none'
    }
    try {
        if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') { return @(& $code $Png) }
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("& {$code} `$env:LOTUS_CLIP_PNG"))
        $env:LOTUS_CLIP_PNG = $Png
        try { @(& $ps -STA -NoProfile -NonInteractive -EncodedCommand $enc 2>$null) } finally { Remove-Item Env:LOTUS_CLIP_PNG -ErrorAction SilentlyContinue }
    } catch { Write-LotusLog DEBUG bg "Clipboard: $($_.Exception.Message)"; @('none') }
}

# ── /bg remove ────────────────────────────────────────────────

function script:Invoke-LotusBgRemove {
    param([string[]]$Words)
    $model = ''; $backend = [string]$script:S['LOTUS_BG_BACKEND']; $out = ''; $next = $false; $clip = $false
    $args_ = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $w = $Words[$i]
        if ($w -cin '-m', '--model' -and $i + 1 -lt $Words.Count) { $model = $Words[++$i] }
        elseif ($w.StartsWith('--model=')) { $model = $w.Substring(8) }
        elseif ($w -cin '-b', '--backend' -and $i + 1 -lt $Words.Count) { $backend = $Words[++$i] }
        elseif ($w.StartsWith('--backend=')) { $backend = $w.Substring(10) }
        elseif ($w -ceq '--cpu') { $backend = 'cpu' }
        elseif ($w -cin '-o', '--out' -and $i + 1 -lt $Words.Count) { $out = $Words[++$i] }
        elseif ($w.StartsWith('--out=')) { $out = $w.Substring(6) }
        elseif ($w -cin '--next-to-source', '--here') { $next = $true }
        elseif ($w -cin '-c', '--clipboard', '--paste') { $clip = $true }
        elseif ($w -cin '-e', '--edit') { Write-LotusWarn (Get-LotusBgText bg_no_editor 'Drawing what to keep needs the editor of the Mac – here the AI result is saved as it is.') }
        elseif ($w -cin '-h', '--help') { Show-LotusBgHelp; return (St 0) }
        elseif ($w -ceq '--') { for ($j = $i + 1; $j -lt $Words.Count; $j++) { $args_.Add($Words[$j]) }; break }
        else { $args_.Add($w) }
    }
    if ($model -and $model -cne 'auto' -and -not (Get-LotusBgModel $model)) {
        Write-LotusError (T bg_bad_model 'Unknown model') $model @("auto · $((@(Get-LotusBgModels) | ForEach-Object Id) -join ' · ')"); return (St 1)
    }
    if ($backend -ceq 'mps' -and $script:S['LOTUS_BG_BACKEND'] -ceq 'mps' -and $IsWindows) { $backend = 'auto' }    # (a setting from a Mac)
    if ($backend -cnotin 'auto', 'cpu') { Write-LotusError (T bg_bad_backend 'Unknown backend') $backend @('auto · cpu'); return (St 1) }
    if (-not (Test-LotusBgSystem)) { return (St 1) }
    $interactive = (Test-LotusOutTty) -and (Test-LotusTty)

    if ($clip) {
        $got = @(Save-LotusBgClipboard)
        if (-not $got.Count) { Write-LotusError (T bg_clip_none 'There is no image in the clipboard') '' @(Get-LotusBgText bg_clip_none_hint); return (St 1) }
        foreach ($g in $got) { $args_.Add($g) }
    } elseif (-not $args_.Count) {
        if (-not $interactive) { Write-LotusError (T bg_which 'Which image?') '' @('/bg remove <image>   ·   /bg paste'); return (St 1) }
        $got = @(Read-LotusBgPaths)
        if (-not $got.Count) { Write-LotusInfo (T cancelled 'Cancelled.'); return (St 1) }
        foreach ($g in $got) { $args_.Add($g) }
    }
    $sel = Get-LotusBgImages $args_.ToArray()
    foreach ($m in $sel.Missing) { Write-LotusError (T bg_notfound 'File not found') $m @(T bg_notfound_hint) }
    $images = @($sel.Images)
    if (-not $images.Count) {
        if (-not $sel.Missing.Count) { Write-LotusError (T bg_noimages 'No images found') ($args_ -join ', ') @(T bg_types) }
        return (St 1)
    }
    Write-LotusLog INFO bg "Remove BG requested for $($images.Count) image(s)"

    # first use, or something missing (runtime or model)
    if (-not (Test-LotusOn $script:S['LOTUS_BG_READY'])) {
        if (-not $interactive) { Show-LotusBgError 'BG-014' (T bg_e_notty 'This needs a terminal window once.') ''; return (St 1) }
        if (-not (Start-LotusBgFirstUse)) { return (St 1) }
    }
    $model = Resolve-LotusBgModel $model
    if (-not (Test-LotusBgRuntime) -or (Get-LotusBgModelState $model) -ne 'ok') {
        if (-not (Install-LotusBg $model)) { return (St 1) }
    }

    # where the PNGs go – an image from the clipboard has no folder of its own: the Lotus folder in Pictures
    $clipDir = Join-Path (Get-LotusBgDirs).Cache 'clipboard'
    $onlyClip = -not @($images | Where-Object { -not $_.StartsWith($clipDir) }).Count
    if (-not $onlyClip -and ($next -or (-not $out -and [string]$script:S['LOTUS_BG_OUTPUT'] -ceq '@source'))) { $dest = @('--next-to-source') }
    else {
        $dir = if ($out) { $out } else { [string]$script:S['LOTUS_BG_OUTPUT'] }
        if (-not $dir -or $dir -ceq '@source') { $dir = $script:BgDefaultOut }
        $dir = Expand-LotusBgDir $dir
        if (-not (Test-LotusBgWritable $dir)) { Show-LotusBgError 'BG-006' (T bg_o_nowrite 'Lotus cannot write into this folder') $dir; return (St 1) }
        $dest = @('--out', $dir)
    }

    New-LotusBgSession
    try {
        $tries = 0
        while ($true) {
            Start-LotusBgUi (T bg_title 'Remove BG') @("load_model|$((T bg_s_load 'Loading %s').Replace('%s', (Get-LotusBgModelLabel $model)))",
                "load_image|$(T bg_s_image 'Reading the image')", "segment|$(T bg_s_segment 'Finding the subject')",
                "refine|$(T bg_s_refine 'Refining edges')", "write|$(T bg_s_write 'Writing the PNG')")
            if ($images.Count -gt 1) { Set-LotusBgSub "$($images.Count) $(T bg_images 'images')" }
            $rc = Invoke-LotusBgWorker (@('run', '--model', $model, '--models-dir', (Get-LotusBgDirs).Models, '--backend', $backend) + $dest + @('--session', $script:Bg.Session, '--') + $images)
            if ($rc -eq 0) { Complete-LotusBgUi; Stop-LotusBgUi; break }
            Stop-LotusBgUi
            if ($script:Bg.Done.Count) { break }       # some images done before the error: show them
            Show-LotusBgLastError
            $fb = if ($tries++ -lt 2) { Get-LotusBgFallback $script:Bg.Err[0] $model } else { $null }
            if (-not $fb) { return (St 1) }
            $model = $fb.Substring(6)
            Write-LotusLog INFO bg "Trying again with $fb"
        }
        if ($images.Count -eq 1 -and $script:Bg.Done.Count) { Show-LotusBgResult }
        else { Show-LotusBgBatch $images.Count }
        if ($script:Bg.Done.Count -and $interactive -and (Test-LotusFeature 'pets') -and (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/pets.ps1'))) {
            Import-LotusCommand pets
            try { Invoke-LotusPetReact done } catch { }
        }
        St 0
    } finally {
        Stop-LotusBgUi
        Remove-LotusBgSession
    }
}

# ── Results ───────────────────────────────────────────────────

function script:Show-LotusBgResult {
    $b = $script:Bg
    $in = [string]$b.Done[0][0]; $output = [string]$b.Done[0][1]; $secs = [string]$b.Done[0][2]
    $b.LastModel = [string]$b.Info['model']; $b.LastBackend = [string]$b.Info['backend']
    if (-not ((Test-LotusOutTty) -and (Test-LotusTty))) { return $output }        # scripts: the path of the PNG
    if (Test-LotusOn $script:S['LOTUS_BG_PREVIEW']) { [void](Open-LotusTarget $output) }
    $d = E dim; $k = E key; $r = $script:R; $esc = [char]27
    $alt = -not $script:KeyQueueActive
    $fromClip = $in.StartsWith((Join-Path (Get-LotusBgDirs).Cache 'clipboard'))
    if ($alt) { Write-LotusRaw "$esc[?1049h" }
    try {
        while ($true) {
            if ($alt) { Write-LotusRaw "$esc[H$esc[2J" }
            Write-LotusHero (T bg_removed_title 'Background removed')
            Write-LotusKv (T bg_i_input 'Input') $(if ($fromClip) { T bg_clip_input 'Image from the clipboard' } else { Format-LotusPath $in })
            if (Test-Path -LiteralPath $output) { Write-LotusKv (T bg_i_output 'Output') (Format-LotusPath $output) }
            else { Write-LotusKv (T bg_i_output 'Output') "$d$(T bg_discarded 'discarded')$r" }
            Write-LotusBlank
            Write-LotusKv (T bg_i_model 'Model') $b.LastModel
            Write-LotusKv (T bg_i_backend 'Backend') $b.LastBackend
            Write-LotusKv (T bg_i_resolution 'Resolution') ([string]$b.Info['resolution'])
            Write-LotusKv (T bg_i_time 'Time') "$($secs)s"
            Write-LotusBlank
            if (Test-Path -LiteralPath $output) {
                Write-LotusSuccess (T bg_png_ok 'Transparent PNG created')
                if ($b.Warn.Count -and $b.Warn[0][0] -ceq 'BG-W01') { Write-LotusWarn (Get-LotusBgText bg_w_empty) }
            }
            Write-LotusBlank
            Write-LotusLine "    $($k)o$r $(T bg_k_open 'open')   $($k)f$r $(T bg_k_finder 'show the folder')   $($k)d$r $(T bg_k_discard 'discard')   $($k)q$r $(T bg_k_done 'done')"
            $key = Read-LotusKeyX
            if ($key -cin 'o', 'O') { if (Test-Path -LiteralPath $output) { [void](Open-LotusTarget $output) } }
            elseif ($key -cin 'f', 'F') { if (Test-Path -LiteralPath $output) { [void](Show-LotusInFolder $output) } else { [void](Open-LotusTarget (Split-Path -Parent $output)) } }
            elseif ($key -cin 'd', 'D') {
                if (-not (Test-Path -LiteralPath $output)) { continue }
                Write-LotusBlank
                if (Read-LotusConfirm (T bg_discard_q 'Delete this PNG again?') 'n') {
                    if ((Remove-LotusToTrash $output) -ne 0) { Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue }
                    Write-LotusLog INFO bg "Discarded $output"
                }
            }
            elseif ($key -cin 'q', 'Q', 'esc', 'enter', 'interrupt') { break }
        }
    } finally { if ($alt) { Write-LotusRaw "$esc[?1049l" } }
    # what stays in the terminal afterwards
    if (Test-Path -LiteralPath $output) {
        Write-LotusSuccess "$(T bg_png_ok 'Transparent PNG created')  $d$($b.LastModel) · $($b.LastBackend) · $($secs)s$r"
        Write-LotusDim "  $(Format-LotusPath $output)"
    } else { Write-LotusInfo (T bg_discarded 'discarded') }
    Write-LotusBlank
}

function script:Show-LotusBgBatch {
    param([int]$N)
    $b = $script:Bg
    $ok = $b.Done.Count
    $secs = 0.0
    foreach ($x in $b.Done) { $v = 0.0; if ([double]::TryParse([string]$x[2], 'Float', [cultureinfo]::InvariantCulture, [ref]$v)) { $secs += $v } }
    if (-not (Test-LotusOutTty)) {
        foreach ($x in $b.Done) { [string]$x[1] }
        foreach ($x in $b.Skip) { Write-LotusLine "skipped: $($x[0]) – $($x[1])" }
        return
    }
    $k = E key; $d = E dim; $r = $script:R
    Write-LotusHero (T bg_batch_title 'Backgrounds removed') "$ok / $N · $($secs.ToString('0.0', [cultureinfo]::InvariantCulture))s · $($b.Info['model']) · $($b.Info['backend'])"
    foreach ($x in $b.Done) { Write-LotusLine "    $k✓$r $(PadR (Cut (Split-Path -Leaf $x[0]) 28) 28) $d→$r $(Split-Path -Leaf $x[1])" }
    foreach ($x in $b.Skip) { Write-LotusLine "    $(E '1')$(E key2)!$r $(PadR (Cut (Split-Path -Leaf $x[0]) 28) 28) $d$($x[1])$r" }
    if ($b.Err.Count) { Write-LotusBlank; Show-LotusBgLastError }
    Write-LotusBlank
    if ($ok) {
        $dir = Split-Path -Parent ([string]$b.Done[0][1])
        Write-LotusKv (T bg_i_output 'Output') (Format-LotusPath $dir)
        Write-LotusBlank
        Write-LotusLine "    $($k)f$r $(T bg_k_finder 'show the folder')   $($k)q$r $(T bg_k_done 'done')"
        if (Test-LotusTty) {
            $key = Read-LotusKeyX
            if ($key -cin 'f', 'F') { [void](Open-LotusTarget $dir) }
        }
    }
    Write-LotusBlank
}

# ── First use, choices, installing, the model cache, doctor ──

# Model choice (radio list) → LOTUS_BG_MODEL; $false = back
function script:Select-LotusBgModel {
    $ids = @('auto') + @(@(Get-LotusBgModels) | ForEach-Object Id)
    $opts = @("$(T col_auto 'Automatic')|$((Get-LotusBgText bg_m_auto '%s').Replace('%s', (Get-LotusBgModel (Get-LotusBgAutoModel)).Label))")
    foreach ($m in @(Get-LotusBgModels)) {
        $state = if ((Get-LotusBgModelState $m.Id) -eq 'ok') { T bg_installed 'on this PC' } else { "$($m.Mb) MB" }
        $opts += "$($m.Label)|$(Get-LotusBgText "bg_m_$($m.Id)") · $state"
    }
    $sel = Read-LotusSelect ([Array]::IndexOf($ids, [string]$script:S['LOTUS_BG_MODEL']) + 1) $opts
    if ($null -eq $sel) { return $false }
    $script:S['LOTUS_BG_MODEL'] = $ids[$sel - 1]
    $true
}

# Output choice → LOTUS_BG_OUTPUT (a folder, or @source = next to the original); $false = back. -Quiet: no lines of its
# own (the setup's page is up)
function script:Select-LotusBgOutput {
    param([switch]$Quiet)
    $def = $script:BgDefaultOut; $cur = [string]$script:S['LOTUS_BG_OUTPUT']
    $sel = 1
    if ($cur -ceq '@source') { $sel = 2 } elseif ($cur -and $cur -cne $def) { $sel = 3 }
    $custom = Get-LotusBgText bg_o_other_d
    if ($sel -eq 3) { $custom = Format-LotusPath (Expand-LotusBgDir $cur) 40 }
    $r = Read-LotusSelect $sel @("$(T bg_o_default)|$(Format-LotusPath (Expand-LotusBgDir $def) 50)", "$(T bg_o_source)|$(T bg_o_source_d)", "$(T bg_o_other)|$custom")
    if ($null -eq $r) { return $false }
    switch ($r) {
        1 {
            $dir = Expand-LotusBgDir $def
            if (-not (Test-LotusBgWritable $dir)) { if (-not $Quiet) { Write-LotusWarn "$(T bg_o_nocreate) $dir" }; return $false }
            $script:S['LOTUS_BG_OUTPUT'] = $def
            if (-not $Quiet) { Write-LotusSuccess "$(T bg_o_ready 'Folder ready:') $(Format-LotusPath $dir)" }
        }
        2 { $script:S['LOTUS_BG_OUTPUT'] = '@source' }
        3 {
            $start = if ($cur -and $cur -cne '@source') { Expand-LotusBgDir $cur } else { Expand-LotusBgDir $def }
            # (a dialog cannot be answered by keys from a test)
            $pick = if ($script:KeyQueueActive) { Lr 2 } else { Select-LotusFolder (T bg_o_prompt 'Where should Lotus save the cut-outs?') $start }
            if ($pick.Code -eq 0) { $dir = $pick.Value }
            else {
                $typed = Read-LotusLine (T bg_o_type 'Folder') (Format-LotusHomePath $start)
                if (-not $typed) { return $false }
                $dir = ConvertTo-LotusCleanPath $typed
            }
            if (-not (Test-LotusBgWritable $dir)) { if (-not $Quiet) { Write-LotusWarn "$(T bg_o_nowrite) $dir" }; return $false }
            $script:S['LOTUS_BG_OUTPUT'] = Format-LotusHomePath $dir
        }
    }
    Write-LotusLog INFO bg "Output folder: $($script:S['LOTUS_BG_OUTPUT'])"
    $true
}

# Install now or on first use → $true (now), $false (later), $null = back
function script:Select-LotusBgWhen {
    param([bool]$Now)
    $r = Read-LotusSelect $(if ($Now) { 2 } else { 1 }) @("$(T bg_w_later)|$(T bg_w_later_d)", "$(T bg_w_now)|$(T bg_w_now_d)")
    if ($null -eq $r) { return $null }
    $r -eq 2
}

function script:Show-LotusBgSummary {
    param($Model, [bool]$Rt, [bool]$Md)
    $d = E dim; $r = $script:R
    Write-LotusSection (T bg_dl_what 'What Lotus downloads'); Write-LotusBlank
    if ($Rt) { Write-LotusLine "    $(PadR (T bg_dl_runtime) 22)$(PadR (T bg_dl_runtime_mb) 12)$d$(T bg_dl_runtime_d)$r" }
    if ($Md) { Write-LotusLine "    $(PadR $Model.Label 22)$(PadR "$($Model.Mb) MB" 12)$d$(T bg_dl_model_d)$r" }
    Write-LotusBlank
    Write-LotusKv (T bg_dl_where 'Folder') (Format-LotusPath $script:Paths.Data)
    $hostName = ([Uri]$Model.Files[0].Url).Host
    Write-LotusKv (T bg_dl_from 'From') $(if ($Rt) { "pypi.org · $hostName" } else { $hostName })
    Write-LotusBlank
    Write-LotusDim "  $(T bg_dl_after)"
    Write-LotusBlank
}

# Installs what is missing for a model, with the progress screen and a short test at the end → $true when ready.
# -Yes: no question (lotus bg setup --yes, for scripts)
function script:Install-LotusBg {
    param([string]$Id, [switch]$Yes)
    if (-not $Id) { $Id = Resolve-LotusBgModel }
    $m = Get-LotusBgModel $Id
    $rt = -not (Test-LotusBgRuntime); $md = (Get-LotusBgModelState $Id) -ne 'ok'
    if (-not $rt -and -not $md) { $script:S['LOTUS_BG_READY'] = '1'; Save-LotusSettings; return $true }
    if (-not $Yes -and -not ((Test-LotusTty) -and (Test-LotusOutTty))) { Show-LotusBgError 'BG-014' (T bg_e_notty 'This needs a terminal window once.') ''; return $false }
    if (-not (Test-LotusBgSystem)) { return $false }
    $need = $(if ($rt) { 1300 } else { 0 }) + $(if ($md) { $m.Mb } else { 0 }) + 500
    $free = Get-LotusBgFreeGb
    if ($free * 1024 -lt $need) { Show-LotusBgError 'BG-012' ((T bg_e_space 'Remove BG needs about %s GB of free space.').Replace('%s', [string]([Math]::Truncate($need / 1024) + 1))) "$free GB free"; return $false }
    if (-not $Yes) {
        Show-LotusBgSummary $m $rt $md
        if (-not (Read-LotusConfirm (T bg_dl_q 'Download and set up now?') 'y')) { Write-LotusInfo (T cancelled 'Cancelled.'); return $false }
    }
    $stages = [System.Collections.Generic.List[string]]::new()
    if ($rt) { $stages.Add("python|$(T bg_s_python 'Python environment')"); $stages.Add("packages|$(T bg_s_packages 'Installing PyTorch & co.')") }
    if ($md) { $stages.Add("download|$((T bg_s_download 'Downloading %s').Replace('%s', $m.Label))"); $stages.Add("verify|$(T bg_s_verify 'Checking the files')") }
    $stages.Add("load_model|$(T bg_s_test_load 'Loading the model')"); $stages.Add("segment|$(T bg_s_test 'Test run')|$(T bg_ss_test 'Test')")
    $script:Bg.Err = @()
    $ok = $true
    New-LotusBgSession
    Write-LotusLog INFO bg "Installing: $(if ($rt) { 'runtime ' })$(if ($md) { $Id })"
    try {
        Start-LotusBgUi "$(T bg_title 'Remove BG') · $(T bg_setup 'Setup')" $stages.ToArray()
        if ($rt -and -not (Install-LotusBgRuntime)) { $ok = $false }
        if ($ok -and $md -and -not (Save-LotusBgModel $Id)) { $ok = $false }
        if ($ok) {
            Set-LotusBgStage load_model
            if ((Invoke-LotusBgWorker @('selftest', '--model', $Id, '--models-dir', (Get-LotusBgDirs).Models, '--backend', 'auto')) -ne 0) { $ok = $false }
        }
        if ($ok) { Complete-LotusBgUi }
    } finally {
        Stop-LotusBgUi
        Remove-LotusBgSession
    }
    if (-not $ok) { Show-LotusBgLastError; return $false }
    $script:S['LOTUS_BG_READY'] = '1'
    Save-LotusSettings
    Write-LotusHero "$(T bg_title 'Remove BG') · $(T bg_setup 'Setup')"
    $label = if ($script:Bg.Info['model']) { $script:Bg.Info['model'] } else { $m.Label }
    Write-LotusSuccess "$((T bg_ready '%s is ready').Replace('%s', $label)) ($(if ($script:Bg.Info['backend']) { $script:Bg.Info['backend'] } else { 'CPU' }), $(if ($script:Bg.Info['seconds']) { $script:Bg.Info['seconds'] } else { '?' })s)"
    Write-LotusBlank
    $true
}

# Creates the Python environment and installs the packages (about 1 GB, once)
function script:Install-LotusBgRuntime {
    Set-LotusBgStage python
    $py = Find-LotusBgPython
    if (-not $py) { $script:Bg.Err = @('BG-001', 'No suitable Python 3 was found.', ''); return $false }
    Write-LotusLog INFO bg "Runtime: Python $($py.Version) from $($py.Exe)"
    Set-LotusBgInfo python "Python $($py.Version)"
    $rt = (Get-LotusBgDirs).Runtime
    Remove-Item -LiteralPath $rt -Recurse -Force -ErrorAction SilentlyContinue
    New-LotusDir (Split-Path -Parent $rt) | Out-Null
    $rc = Invoke-LotusBgFollow venv $py.Exe (@($py.Args) + @('-m', 'venv', $rt))
    if ($rc -ne 0 -or -not (Test-Path -LiteralPath (Get-LotusBgPythonExe))) {
        Remove-Item -LiteralPath $rt -Recurse -Force -ErrorAction SilentlyContinue
        $script:Bg.Err = @('BG-002', 'Python could not create an environment.', "$($py.Exe) -m venv"); return $false
    }
    Set-LotusBgStage packages
    $exe = Get-LotusBgPythonExe
    $pip = @('-s', '-E', '-m', 'pip', '--disable-pip-version-check', '--no-input', 'install', '--progress-bar', 'off')
    foreach ($step in @(@('--upgrade', 'pip'), @('-r', (Get-LotusBgRequirements)), @('--no-deps', $script:BgTb))) {
        if ((Invoke-LotusBgFollow pip $exe ($pip + $step)) -ne 0) {
            Remove-Item -LiteralPath $rt -Recurse -Force -ErrorAction SilentlyContinue
            $script:Bg.Err = @('BG-002', 'The Python packages could not be installed.', 'pip failed – details in /lotus log'); return $false
        }
    }
    Write-LotusFile (Join-Path $rt 'lotus-runtime') "$(Get-LotusBgReqStamp) $((Get-Date).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture))`n"
    Write-LotusLog INFO bg "Runtime installed ($(Get-LotusBgSizeMb $rt) MB)"
    $true
}

# Downloads the files of a model with a real progress bar, then checks every SHA-256 and moves the files in place.
# Unfinished downloads continue where they stopped.
function script:Save-LotusBgModel {
    param([string]$Id)
    $m = Get-LotusBgModel $Id
    $dir = Join-Path (Get-LotusBgDirs).Models $Id
    $total = 0L; $have = 0L
    $todo = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $m.Files) {
        $total += $f.Bytes
        $i = Get-Item -LiteralPath (Join-Path $dir $f.Name) -ErrorAction SilentlyContinue
        if ($i -and $i.Length -eq $f.Bytes) { $have += $f.Bytes } else { $todo.Add($f) }
    }
    Set-LotusBgStage download
    Set-LotusBgInfo model $m.Label
    New-LotusDir $dir | Out-Null
    Write-LotusLog INFO bg "Downloading $($m.Label) ($([Math]::Truncate($total / 1MB)) MB, $($todo.Count) file(s))"
    $curl = Find-LotusProgram @('curl')
    if (-not $curl) { $script:Bg.Err = @('BG-003', "The download of $($m.Label) failed.", 'curl is missing'); return $false }
    foreach ($f in $todo) {
        $part = Join-Path $dir "$($f.Name).part"
        Set-LotusBgNote $f.Name
        $rc = Invoke-LotusBgCurl $curl @('-fsSL', '--retry', '3', '--retry-delay', '2', '--connect-timeout', '15', '-C', '-', '-o', $part, '--', $f.Url) $part $have $total
        if ($rc -ne 0) {
            # a part that cannot be continued (e.g. already complete) – that file once more from the start
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            $rc = Invoke-LotusBgCurl $curl @('-fsSL', '--retry', '3', '--connect-timeout', '15', '-o', $part, '--', $f.Url) $part $have $total
            if ($rc -ne 0) { $script:Bg.Err = @('BG-003', "The download of $($m.Label) failed.", $f.Url); return $false }
        }
        $have += $f.Bytes
    }
    Set-LotusBgProgress 0 0
    Set-LotusBgStage verify
    foreach ($f in $todo) {
        $part = Join-Path $dir "$($f.Name).part"
        Set-LotusBgNote $f.Name
        Show-LotusBgFrame
        $got = Get-LotusSha256 $part
        if ($got -cne $f.Sha) {
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            Write-LotusLog ERROR bg "Checksum mismatch for $Id/$($f.Name): $got"
            $script:Bg.Err = @('BG-009', "$($m.Label) did not arrive intact (checksum mismatch).", $f.Name); return $false
        }
        Move-Item -LiteralPath $part -Destination (Join-Path $dir $f.Name) -Force
    }
    Set-LotusBgNote ''
    Write-LotusLog INFO bg "$($m.Label) downloaded and verified"
    $true
}

# The first /bg remove: explain, choose, install → $true when ready
function script:Start-LotusBgFirstUse {
    Write-LotusLog INFO bg 'First use of Remove BG'
    if (-not (Test-LotusBgSystem)) { return $false }
    Write-LotusHero (T bg_title 'Remove BG') (T bg_tagline)
    Write-LotusText (T bg_intro)
    Write-LotusBlank
    Write-LotusSection (T bg_q_model 'Model'); Write-LotusBlank
    if (-not (Select-LotusBgModel)) { return $false }
    Write-LotusBlank
    Write-LotusSection (T bg_q_output 'Output folder'); Write-LotusBlank
    if (-not (Select-LotusBgOutput)) { return $false }
    Save-LotusSettings
    Write-LotusBlank
    Install-LotusBg (Resolve-LotusBgModel)
}

# /bg models – what is on this PC: download, remove, check
function script:Show-LotusBgModels {
    $d = E dim; $k = "$(E '1')$(E key)"; $r = $script:R
    $dirs = Get-LotusBgDirs
    while ($true) {
        Write-LotusHero "$(T bg_title 'Remove BG') · $(T bg_cache 'Model cache')"
        foreach ($m in @(Get-LotusBgModels)) {
            $state = Get-LotusBgModelState $m.Id
            $about = Get-LotusBgText "bg_m_$($m.Id)"
            if ($state -eq 'ok') { Write-LotusLine "    $k✓$r $(PadR $m.Label 16)$(PadL ([string](Get-LotusBgSizeMb (Join-Path $dirs.Models $m.Id))) 7) MB   $d$about · $($m.License)$r" }
            else { Write-LotusLine "    $d·$r $(PadR $m.Label 16)$d$(PadL ([string]$m.Mb) 7) MB   $about · $(if ($state -eq 'partial') { "$(T bg_partial 'incomplete') · " })$($m.License)$r" }
        }
        Write-LotusBlank
        if (Test-LotusBgRuntime) { Write-LotusKv (T bg_runtime 'Runtime') "$(T bg_installed 'on this PC') · $(Get-LotusBgSizeMb $dirs.Runtime) MB" }
        else { Write-LotusKv (T bg_runtime 'Runtime') (T bg_not_installed 'not downloaded') }
        Write-LotusKv (T bg_dl_where 'Folder') (Format-LotusPath $script:Paths.Data)
        Write-LotusBlank
        $r1 = Read-LotusSelect 1 @("$(T bg_a_done 'Done')|", "$(T bg_a_download 'Download a model')|", "$(T bg_a_remove 'Remove a model')|", "$(T bg_a_check)|", "$(T bg_a_remove_all)|$(T bg_a_remove_all_d)")
        if ($null -eq $r1 -or $r1 -eq 1) { return }
        switch ($r1) {
            2 { $id = Select-LotusBgModelId (T bg_a_download 'Download a model'); if ($id -and (Test-LotusBgSystem)) { [void](Install-LotusBg $id) } }
            3 {
                $id = Select-LotusBgModelId (T bg_a_remove 'Remove a model') -Installed
                if (-not $id) { break }
                if (Read-LotusConfirm ((T bg_rm_q 'Remove %s from this PC?').Replace('%s', (Get-LotusBgModelLabel $id))) 'n') {
                    Remove-Item -LiteralPath (Join-Path $dirs.Models $id) -Recurse -Force -ErrorAction SilentlyContinue
                    Write-LotusLog INFO bg "Removed model $id"
                    Write-LotusSuccess (T bg_removed 'Removed')
                }
            }
            4 { Test-LotusBgAll }
            5 {
                if (-not (Read-LotusConfirm (T bg_rm_all_q) 'n')) { break }
                Remove-Item -LiteralPath $dirs.Models, $dirs.Runtime -Recurse -Force -ErrorAction SilentlyContinue
                $script:S['LOTUS_BG_READY'] = '0'; Save-LotusSettings
                Write-LotusLog INFO bg 'Removed the Remove BG runtime and all models'
                Write-LotusSuccess (T bg_removed 'Removed')
            }
        }
        Write-LotusBlank; Write-LotusDim "  $(T back '(press any key to go back)')"
        [void](Read-LotusKeyX)
        if (-not $script:KeyQueueActive) { Write-LotusRaw "$([char]27)[H$([char]27)[2J" }
    }
}

# A model to download (not there yet) or to remove (there) → its id, or $null
function script:Select-LotusBgModelId {
    param([string]$Title, [switch]$Installed)
    $ids = @(foreach ($m in @(Get-LotusBgModels)) {
            $s = Get-LotusBgModelState $m.Id
            if ($Installed) { if ($s -ne 'missing') { $m.Id } } elseif ($s -ne 'ok') { $m.Id }
        })
    if (-not $ids.Count) { Write-LotusInfo (T bg_nothing 'Nothing to choose here.'); return $null }
    Write-LotusBlank; Write-LotusSection $Title; Write-LotusBlank
    $sel = Read-LotusSelect 1 @($ids | ForEach-Object { "$(Get-LotusBgModelLabel $_)|" })
    if ($null -eq $sel) { return $null }
    $ids[$sel - 1]
}

# The worker's answer to a quick command (probe, check) → its event lines
function script:Get-LotusBgWorkerLines {
    param([string[]]$Arguments)
    $py = Get-LotusBgPython
    $p = Start-LotusBgProcess $py[0] (@($py | Select-Object -Skip 1) + @($script:BgWorker) + $Arguments) @{ LOTUS_LOG = $script:Paths.Log; LOTUS_LOG_LEVEL = [string]$script:S['LOTUS_LOG_LEVEL'] }
    if (-not $p) { return @() }
    try {
        $err = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        $null = $err.Result
        @($out -split "`r?`n" | Where-Object { $_ })
    } finally { $p.Dispose() }
}

# Full check: every SHA-256 (a few seconds per model)
function script:Test-LotusBgAll {
    if (-not (Test-LotusBgRuntime)) { Write-LotusWarn (T bg_not_installed 'not downloaded'); return }
    Write-LotusStep (T bg_checking 'Checking …')
    foreach ($line in Get-LotusBgWorkerLines @('check', '--models-dir', (Get-LotusBgDirs).Models, '--full')) {
        $f = $line -split "`t"
        if ($f[0] -cne 'model') { continue }
        $label = Get-LotusBgModelLabel $f[1]
        if ($f[2] -ceq 'ok') { Write-LotusSuccess $label }
        elseif ($f[2] -ceq 'damaged') { Write-LotusWarn "$label – $(T bg_damaged 'damaged:') $($f[3])" }
    }
}

# Rows for lotus doctor (when the feature is on) and /bg doctor
function script:Show-LotusBgDoctorRows {
    param([scriptblock]$Row, [string]$Ok, [string]$Bad, [string]$Opt)
    if (Test-LotusFeature 'bg') { & $Row $Ok 'Feature' "$(T on 'on') (/bg remove)" } else { & $Row $Opt 'Feature' "$((T off 'Off').ToLower()) – lotus features" }
    $mem = [Math]::Round((Get-LotusMemBytes) / 1GB)
    if (Test-LotusBgSystem -Quiet) { & $Row $Ok 'PC' "$($script:Os.Arch) · $mem GB" }
    else { & $Row $Bad 'PC' "$($script:Os.Arch) – $(Get-LotusBgText 'bg_t_BG-008')" }
    $dirs = Get-LotusBgDirs
    if (Test-LotusBgRuntime) {
        $p = @{}; $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($line in Get-LotusBgWorkerLines @('probe')) {
            $f = $line -split "`t"
            if ($f[0] -cne 'info') { continue }
            if ($f[1] -ceq 'module') { if ($f[3] -cne 'ok') { $missing.Add($f[2]) } } else { $p[$f[1]] = $f[2] }
        }
        & $Row $Ok 'Python' "$(if ($p['python']) { $p['python'] } else { '?' }) ($(Format-LotusPath $dirs.Runtime 60))"
        if ($p['torch']) { & $Row $Ok 'PyTorch' $p['torch'] } else { & $Row $Bad 'PyTorch' (Get-LotusBgText bg_d_torch) }
        if ($missing.Count) { & $Row $Bad 'Packages' "missing: $($missing -join ' ') – /bg models → $(T bg_a_remove_all)" }
        & $Row $Opt 'GPU' (Get-LotusBgText bg_d_cpu)
    } else {
        $py = Find-LotusBgPython
        if ($py) { & $Row $Opt 'Python' "$(T bg_d_rt_later 'installed on first use') (Python $($py.Version) found)" } else { & $Row $Opt 'Python' (Get-LotusBgText bg_d_nopython) }
    }
    & $Row $Ok 'Model cache' "$(Format-LotusPath $dirs.Models 60) ($(Get-LotusBgSizeMb $dirs.Models) MB)"
    foreach ($m in @(Get-LotusBgModels)) {
        switch (Get-LotusBgModelState $m.Id) {
            'ok' { & $Row $Ok $m.Label (T bg_installed 'on this PC') }
            'partial' { & $Row $Bad $m.Label "$(T bg_partial 'incomplete') – /bg models" }
            default { & $Row $Opt $m.Label (T bg_not_installed 'not downloaded') }
        }
    }
    $out = [string]$script:S['LOTUS_BG_OUTPUT']
    if ($out -ceq '@source') { & $Row $Ok 'Output' (T bg_o_source 'Next to the original') }
    else {
        $dir = Expand-LotusBgDir $out
        if (Test-Path -LiteralPath $dir -PathType Container) { & $Row $Ok 'Output' (Format-LotusPath $dir 60) }
        else { & $Row $Opt 'Output' "$(Format-LotusPath $dir 60) ($(T bg_d_created 'created on first use'))" }
    }
    & $Row $Opt 'Editor' (Get-LotusBgText bg_d_noeditor)
}
