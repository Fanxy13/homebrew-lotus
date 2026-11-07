# The platform layer for Windows – the functions of lib/platform/*.zsh, by their PowerShell names. A function that this
# system cannot offer returns status 2 and prints nothing; the command says in words what is not possible. Nothing is
# faked. A function with more to say than a status returns a result: Code (the status), Value, Msg (why it failed).
#
# Windows API calls are made with Reflection.Emit (P/Invoke without a compiler: milliseconds instead of the half second
# Add-Type needs); only the volume, a COM interface, is compiled – once per session, when it is first used.

$script:Native = @{}

# A result: the status (0 done · 1 failed · 2 not possible on this system), what came out, and why it failed
function Lr { param([int]$Code, $Value = $null, [string[]]$Msg = @()) [pscustomobject]@{ Code = $Code; Value = $Value; Msg = $Msg } }

# ── This system ───────────────────────────────────────────────

function Initialize-LotusPlatform {
    if ($script:Os) { return }
    $os = [ordered]@{ Name = 'other'; Version = ''; Build = 0; Release = ''; Product = ''; Arch = 'unknown'; Terminal = '' }
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $os.Arch = switch ($arch) { 'X64' { 'x86_64' } 'Arm64' { 'arm64' } 'X86' { 'x86' } default { $arch.ToLowerInvariant() } }
    if ($IsWindows) {
        $os.Name = 'windows'
        $v = [Environment]::OSVersion.Version
        $os.Build = $v.Build
        $os.Version = "$($v.Major).$($v.Minor).$($v.Build)"
        try {
            $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $os.Product = [string]$cv.ProductName
            $os.Release = [string]$cv.DisplayVersion
            if ($cv.UBR) { $os.Version += ".$($cv.UBR)" }
        } catch { }
        # Windows 11 still says "Windows 10" in ProductName – its build number tells
        if (-not $os.Product) { $os.Product = 'Windows' }
        if ($os.Build -ge 22000) { $os.Product = $os.Product -replace 'Windows 10', 'Windows 11' }
        $os.Terminal = if ($env:WT_SESSION) { 'Windows Terminal' } elseif ($env:TERM_PROGRAM -eq 'vscode') { 'VS Code' } elseif ($env:TERM_PROGRAM) { $env:TERM_PROGRAM } else { 'Console' }
    } elseif ($IsMacOS) {
        $os.Name = 'macos'; $os.Product = 'macOS'
    } elseif ($IsLinux) {
        $os.Name = 'linux'; $os.Product = 'Linux'
        try {
            foreach ($line in [System.IO.File]::ReadAllLines('/etc/os-release')) {
                if ($line -match '^PRETTY_NAME=(.*)$') { $os.Product = $Matches[1].Trim('"') }
                if ($line -match '^VERSION_ID=(.*)$') { $os.Version = $Matches[1].Trim('"') }
            }
        } catch { }
    }
    $script:Os = [pscustomobject]$os
}

# "Windows 11 Pro 24H2 · x86_64" for messages
function Get-LotusOsDescription {
    Initialize-LotusPlatform
    $o = $script:Os
    "$($o.Product)$(if ($o.Release) { " $($o.Release)" }) · $($o.Arch)"
}

# The package managers that are installed, in the order Lotus prefers them: winget, Scoop, Chocolatey
function Get-LotusPackageManagers {
    if ($null -ne $script:PkgManagers) { return $script:PkgManagers }
    $script:PkgManagers = @(foreach ($m in 'winget', 'scoop', 'choco') { if (Get-Command $m -CommandType Application, ExternalScript -ErrorAction SilentlyContinue) { $m } })
    $script:PkgManagers
}

# ── Native calls ──────────────────────────────────────────────

# A static method that calls a function of a Windows DLL, made once:  Get-LotusNative user32.dll keybd_event ([void]) @([byte],[byte],[uint32],[UIntPtr])
function Get-LotusNative {
    param([string]$Dll, [string]$Name, [type]$Return, [type[]]$Parameters = @())
    $key = "$Dll!$Name"
    if ($script:Native.ContainsKey($key)) { return $script:Native[$key] }
    if (-not $script:NativeModule) {
        $asm = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly([System.Reflection.AssemblyName]::new('LotusNative'), 'Run')
        $script:NativeModule = $asm.DefineDynamicModule('LotusNative')
    }
    $tb = $script:NativeModule.DefineType("LotusNative.N$($script:Native.Count)", 'Public, Class, Sealed')
    $m = $tb.DefinePInvokeMethod($Name, $Dll, 'Public, Static, PinvokeImpl', 'Standard', $Return, $Parameters, 'Winapi', 'Unicode')
    $m.SetImplementationFlags('PreserveSig')
    $method = $tb.CreateType().GetMethod($Name)
    $script:Native[$key] = $method
    $method
}

# ── Open things ───────────────────────────────────────────────

# A link or a path in its default application, without waiting (lotus_os_open) → 0, or 2 when nothing can open it here
function Open-LotusTarget {
    param([Parameter(Mandatory)][string]$Target)
    if ($IsWindows) {
        try { Start-Process -FilePath $Target -ErrorAction Stop | Out-Null; return 0 } catch { return 1 }
    }
    foreach ($tool in 'xdg-open', 'open') {
        if (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue) {
            try { Start-Process -FilePath $tool -ArgumentList $Target -ErrorAction Stop | Out-Null; return 0 } catch { return 1 }
        }
    }
    2
}

# Shown in File Explorer, selected (lotus_os_reveal)
function Show-LotusInFolder {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 1 }
    if (-not $IsWindows) { return Open-LotusTarget (Split-Path -Parent $Path) }
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$((Resolve-Path -LiteralPath $Path).ProviderPath)`"" | Out-Null; 0 } catch { 1 }
}

# The installed apps → a result with the Value @{ name = how to start it } (lotus_os_apps): the Applications folder of the Start
# menu – what Get-StartApps lists, the Store apps by their AppUserModelID, the others by their path
function Get-LotusInstalledApps {
    $apps = @{}
    if ($IsWindows) {
        try {
            $folder = (New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
            foreach ($item in $folder.Items()) {
                $name = [string]$item.Name
                if ($name -and -not $apps.ContainsKey($name)) { $apps[$name] = [string]$item.Path }
            }
        } catch { }
        if (-not $apps.Count) {
            # the shortcuts of the Start menu, yours first
            foreach ($dir in @([Environment]::GetFolderPath('StartMenu'), [Environment]::GetFolderPath('CommonStartMenu'))) {
                if (-not $dir) { continue }
                foreach ($lnk in Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.lnk' -File -ErrorAction SilentlyContinue) {
                    $name = $lnk.BaseName
                    if ($name -match '(?i)uninstall|readme|help') { continue }
                    if (-not $apps.ContainsKey($name)) { $apps[$name] = $lnk.FullName }
                }
            }
        }
    }
    Lr $(if ($apps.Count) { 0 } elseif ($IsWindows) { 1 } else { 2 }) $apps
}

# Starts an app found by Get-LotusInstalledApps (lotus_os_open_app)
function Start-LotusApp {
    param([Parameter(Mandatory)][string]$Id)
    if (-not $IsWindows) { return 2 }
    try {
        if ($Id -match '^[A-Za-z]:\\|^\\\\') { Start-Process -FilePath $Id -ErrorAction Stop | Out-Null }
        else { Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$Id" -ErrorAction Stop | Out-Null }
        0
    } catch { 1 }
}

# ── Clipboard ─────────────────────────────────────────────────

function Set-LotusClipboardText {
    param([AllowEmptyString()][string]$Text)
    if (-not $IsWindows) { return 2 }
    try { Set-Clipboard -Value $Text -ErrorAction Stop; 0 } catch { 1 }
}
function Get-LotusClipboardText {
    if (-not $IsWindows) { return (Lr 2) }
    try { Lr 0 ([string](Get-Clipboard -Raw -ErrorAction Stop)) } catch { Lr 1 }
}

# ── Notifications, keep awake ─────────────────────────────────

# A toast (lotus_os_notify). PowerShell 7 has no Windows Runtime types, so Windows PowerShell shows it; the texts reach it
# through the environment, never inside the command.
function Send-LotusNotification {
    param([string]$Title, [string]$Text)
    if (-not $IsWindows) { return 2 }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps)) { return 2 }
    $script = @'
$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$e = [System.Security.SecurityElement]
$x = New-Object Windows.Data.Xml.Dom.XmlDocument
$x.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>$($e::Escape($env:LOTUS_TOAST_TITLE))</text><text>$($e::Escape($env:LOTUS_TOAST_TEXT))</text></binding></visual></toast>")
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new($x))
'@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $env:LOTUS_TOAST_TITLE = $Title; $env:LOTUS_TOAST_TEXT = $Text
    try { Start-Process -FilePath $ps -ArgumentList '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc -WindowStyle Hidden | Out-Null; 0 }
    catch { 1 }
    finally { Remove-Item Env:LOTUS_TOAST_TITLE, Env:LOTUS_TOAST_TEXT -ErrorAction SilentlyContinue }
}

# Keeps Windows awake for <seconds> (0 = until stopped): a hidden PowerShell that holds SetThreadExecutionState
# (system and display required) and ends when the time is up – closing the terminal does not stop it.
# → a result with the process id (lotus_os_awake_start)
function Start-LotusAwake {
    param([long]$Seconds)
    if (-not $IsWindows) { return (Lr 2) }
    if ($Seconds -le 0) { $Seconds = [int]::MaxValue }
    $script = @"
`$asm = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly([System.Reflection.AssemblyName]::new('LotusAwake'), 'Run')
`$tb = `$asm.DefineDynamicModule('LotusAwake').DefineType('LotusAwake', 'Public, Class')
`$m = `$tb.DefinePInvokeMethod('SetThreadExecutionState', 'kernel32.dll', 'Public, Static, PinvokeImpl', 'Standard', [uint32], [type[]]@([uint32]), 'Winapi', 'Unicode')
`$m.SetImplementationFlags('PreserveSig')
`$f = `$tb.CreateType().GetMethod('SetThreadExecutionState')
[void]`$f.Invoke(`$null, @([uint32]2147483651))
`$end = [datetime]::UtcNow.AddSeconds($Seconds)
while ([datetime]::UtcNow -lt `$end) { Start-Sleep -Seconds 30; [void]`$f.Invoke(`$null, @([uint32]2147483651)) }
"@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $pwsh = (Get-Process -Id $PID).Path
    try {
        $p = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc -WindowStyle Hidden -PassThru -ErrorAction Stop
    } catch { return (Lr 1) }
    Start-Sleep -Milliseconds 300
    if ($p.HasExited) { return (Lr 1) }
    Lr 0 $p.Id
}
function Get-LotusAwakeName { 'SetThreadExecutionState' }
# Is <pid> still the keep-awake process Lotus started at <start> (epoch seconds)? A number that belongs to another
# program now is not it.
function Test-LotusAwake {
    param([int]$ProcessId, [long]$Start)
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p -or $p.ProcessName -notin 'pwsh', 'powershell') { return $false }
    try { [Math]::Abs((Get-LotusEpoch $p.StartTime) - $Start) -le 5 } catch { $false }
}
function Stop-LotusAwake {
    param([int]$ProcessId)
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

# ── Sound ─────────────────────────────────────────────────────

# The volume of the default output, through Core Audio → a result: the percent (up, down, get) or 1/0 = muted/sound (mute)
function Invoke-LotusVolume {
    param([ValidateSet('up', 'down', 'mute', 'get')][string]$Action)
    if (-not $IsWindows) { return (Lr 2) }
    if (-not ('LotusAudio' -as [type])) {
        try {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int f(); int g(); int h(); int i();
    int SetMasterVolumeLevelScalar(float level, Guid context);
    int j();
    int GetMasterVolumeLevelScalar(out float level);
    int k(); int l(); int m(); int n();
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, Guid context);
    int GetMute(out bool mute);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid id, int clsCtx, int activationParams, out IAudioEndpointVolume aev); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int f(); int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
public static class LotusAudio {
    static IAudioEndpointVolume Endpoint() {
        var e = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice dev;
        Marshal.ThrowExceptionForHR(e.GetDefaultAudioEndpoint(0, 1, out dev));
        IAudioEndpointVolume v;
        var id = typeof(IAudioEndpointVolume).GUID;
        Marshal.ThrowExceptionForHR(dev.Activate(ref id, 23, 0, out v));
        return v;
    }
    public static float Volume {
        get { float v; Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out v)); return v; }
        set { Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(Math.Max(0f, Math.Min(1f, value)), Guid.Empty)); }
    }
    public static bool Mute {
        get { bool m; Marshal.ThrowExceptionForHR(Endpoint().GetMute(out m)); return m; }
        set { Marshal.ThrowExceptionForHR(Endpoint().SetMute(value, Guid.Empty)); }
    }
}
'@
        } catch { return (Lr 2) }
    }
    try {
        switch ($Action) {
            'up' { [LotusAudio]::Volume = [Math]::Min(1.0, [LotusAudio]::Volume + 0.06) }
            'down' { [LotusAudio]::Volume = [Math]::Max(0.0, [LotusAudio]::Volume - 0.06) }
            'mute' { [LotusAudio]::Mute = -not [LotusAudio]::Mute; return (Lr 0 ([int][LotusAudio]::Mute)) }
        }
        Lr 0 ([int][Math]::Round([LotusAudio]::Volume * 100))
    } catch { Lr 1 $null @('The volume did not change', $_.Exception.Message, '') }
}

# Media control (lotus_os_media play|pause|next|previous|repeat <status> <player>): the media keys of the keyboard, which
# every player with Windows' media controls answers – no permission needed. Play and pause share one key, so the state
# of the player decides whether it is pressed. Repeat goes through Windows' media session (Windows PowerShell).
#   → a result: Code 0 done (Value: the player) · 1 failed (Msg: title, detail, hint) · 2 this system cannot do it
function Invoke-LotusMedia {
    param([string]$Action, [string]$Status, [string]$Player)
    if (-not $IsWindows) { return (Lr 2) }
    if ($Action -eq 'repeat') { return Invoke-LotusMediaRepeat $Player }
    $vk = switch ($Action) { 'next' { 0xB0 } 'previous' { 0xB1 } 'play' { 0xB3 } 'pause' { 0xB3 } default { 0 } }
    if (-not $vk) { return (Lr 2) }
    $label = if ($Player) { $Player } else { 'player' }
    if (($Action -eq 'play' -and $Status -eq 'Playing') -or ($Action -eq 'pause' -and $Status -and $Status -ne 'Playing')) { return (Lr 0 $label) }
    try {
        $f = Get-LotusNative 'user32.dll' 'keybd_event' ([void]) @([byte], [byte], [uint32], [UIntPtr])
        [void]$f.Invoke($null, @([byte]$vk, [byte]0, [uint32]1, [UIntPtr]::Zero))
        [void]$f.Invoke($null, @([byte]$vk, [byte]0, [uint32]3, [UIntPtr]::Zero))
        Lr 0 $label
    } catch {
        Lr 1 $null @('The player did not respond', "Windows did not take the media key ($($_.Exception.Message)).", '')
    }
}

function Invoke-LotusMediaRepeat {
    param([string]$Player)
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps)) { return (Lr 2) }
    $script = @'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$await = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Wait($op, $type) { $t = $await.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$m = Wait ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
$s = $m.GetCurrentSession()
if (-not $s) { 'none'; exit }
$pb = $s.GetPlaybackInfo()
if (-not $pb.Controls.IsRepeatEnabled) { 'unsupported'; exit }
$now = $pb.AutoRepeatMode
$next = if ([string]$now -eq 'None') { [Windows.Media.MediaPlaybackAutoRepeatMode]::List } else { [Windows.Media.MediaPlaybackAutoRepeatMode]::None }
$ok = Wait ($s.TryChangeAutoRepeatModeAsync($next)) ([bool])
if ($ok) { "set $next" } else { 'refused' }
'@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $out = (& $ps -NoProfile -NonInteractive -EncodedCommand $enc 2>$null | Select-Object -Last 1)
    $label = if ($Player) { $Player } else { 'player' }
    switch -Regex ([string]$out) {
        '^set None' { return (Lr 0 "Repeat off  $label") }
        '^set ' { return (Lr 0 "Repeat on  $label") }
        default { return (Lr 2) }
    }
}

# ── Secrets ───────────────────────────────────────────────────
# Windows: a file only you can read – protected by Windows (DPAPI: only your account on this PC can decrypt it), in
# secrets\ next to the settings. Elsewhere (the tests): a file with mode 600, as the zsh engine keeps it without a keyring.

function Get-LotusSecretFile {
    param([string]$Service)
    Join-Path (Join-Path $script:Paths.Conf 'secrets') ($Service -replace '[^A-Za-z0-9._-]', '_')
}
function Get-LotusSecret {
    param([Parameter(Mandatory)][string]$Service)
    $f = Get-LotusSecretFile $Service
    $text = Read-LotusFile $f
    if (-not $text) { return $null }
    if ($IsWindows) {
        try { return [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString $text.Trim() -ErrorAction Stop)).Password } catch { return $null }
    }
    $text
}
function Set-LotusSecret {
    param([Parameter(Mandatory)][string]$Service, [Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9._~+/=:-]+$') { return 1 }
    $f = Get-LotusSecretFile $Service
    New-LotusDir (Split-Path -Parent $f) | Out-Null
    try {
        if ($IsWindows) {
            Write-LotusFile $f ((ConvertTo-SecureString $Value -AsPlainText -Force | ConvertFrom-SecureString) + "`n")
        } else {
            Write-LotusFile $f $Value
            & chmod 700 (Split-Path -Parent $f) 2>$null; & chmod 600 $f 2>$null
        }
        0
    } catch { 1 }
}
function Remove-LotusSecret {
    param([Parameter(Mandatory)][string]$Service)
    $f = Get-LotusSecretFile $Service
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force; return 0 }
    1
}
function Get-LotusSecretStoreName {
    if ($IsWindows) { 'a file only your Windows account can read (DPAPI)' } else { "a file only you can read ($(Format-LotusHomePath (Join-Path $script:Paths.Conf 'secrets')))" }
}

# ── Your PATH ─────────────────────────────────────────────────
# The folder of lotus.cmd (bin\ of Lotus) in your user PATH – never the system's. The value is read and written as it is
# in the registry (an entry like %USERPROFILE%\bin stays one, the kind of value stays), then the change is announced,
# so that windows opened from now on have it. → $true when the PATH was changed

function Get-LotusUserPathValue {
    $key = Get-Item -LiteralPath 'HKCU:\Environment' -ErrorAction SilentlyContinue
    if (-not $key) { return @{ Value = ''; Kind = 'ExpandString' } }
    $kind = if ($key.GetValueNames() -contains 'Path') { [string]$key.GetValueKind('Path') } else { 'ExpandString' }
    @{ Value = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames'); Kind = $kind }
}
function Test-LotusSamePath {
    param([string]$A, [string]$B)
    [Environment]::ExpandEnvironmentVariables($A).TrimEnd('\') -eq [Environment]::ExpandEnvironmentVariables($B).TrimEnd('\')
}
function Set-LotusUserPathValue {
    param([string]$Value, [string]$Kind)
    if (-not (Test-Path -LiteralPath 'HKCU:\Environment')) { New-Item -Path 'HKCU:\Environment' -Force | Out-Null }
    Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -Value $Value -Type $(if ($Kind -eq 'String') { 'String' } else { 'ExpandString' })
    # (setting a variable through .NET tells the open windows that the environment changed – Explorer, Windows Terminal)
    [Environment]::SetEnvironmentVariable('LOTUS_PATH_CHANGED', $null, 'User')
}
function Add-LotusUserPath {
    param([Parameter(Mandatory)][string]$Dir)
    if (-not $IsWindows) { return $false }
    $cur = Get-LotusUserPathValue
    $parts = @($cur.Value -split ';' | Where-Object { $_ })
    if ($parts | Where-Object { Test-LotusSamePath $_ $Dir }) { return $false }
    Set-LotusUserPathValue (@($parts) + $Dir -join ';') $cur.Kind
    if (-not (@($env:Path -split ';') | Where-Object { $_ -and (Test-LotusSamePath $_ $Dir) })) { $env:Path = "$env:Path;$Dir" }
    $true
}
function Remove-LotusUserPath {
    param([Parameter(Mandatory)][string]$Dir)
    if (-not $IsWindows) { return $false }
    $cur = Get-LotusUserPathValue
    $parts = @($cur.Value -split ';' | Where-Object { $_ })
    $keep = @($parts | Where-Object { -not (Test-LotusSamePath $_ $Dir) })
    if ($keep.Count -eq $parts.Count) { return $false }
    Set-LotusUserPathValue ($keep -join ';') $cur.Kind
    $true
}

# ── This computer ─────────────────────────────────────────────

function Get-LotusCpuCount { [Environment]::ProcessorCount }
function Get-LotusMemBytes { [long][GC]::GetGCMemoryInfo().TotalAvailableMemoryBytes }
function Get-LotusChip {
    if ($IsWindows) {
        try { return ((Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name).Trim() } catch { }
        try { return [string](Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop).ProcessorNameString } catch { }
    } elseif ($IsLinux -and (Test-Path /proc/cpuinfo)) {
        foreach ($line in [IO.File]::ReadLines('/proc/cpuinfo')) { if ($line -match '^(model name|Model|Hardware)\s*:\s*(.+)$') { return $Matches[2] } }
    }
    $null
}

# The full name of this account (asked once, then kept in the cache: Windows asks a database for it)
function Get-LotusFullName {
    if ($null -ne $script:FullName) { return $script:FullName }
    $script:FullName = ''
    if ($IsWindows) {
        $cache = if ($script:Paths) { Join-Path $script:Paths.Cache 'fullname' } else { $null }
        if ($cache -and (Test-Path -LiteralPath $cache)) { $script:FullName = ([string](Read-LotusFile $cache)).Trim(); return $script:FullName }
        try {
            $u = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True AND Name='$($env:USERNAME -replace "'", "''")'" -ErrorAction Stop | Select-Object -First 1
            if ($u.FullName) { $script:FullName = [string]$u.FullName }
        } catch { }
        if ($cache) { try { Write-LotusFile $cache "$($script:FullName)`n" } catch { } }
    } elseif ($IsLinux -and (Get-Command getent -ErrorAction SilentlyContinue)) {
        $rec = & getent passwd ([Environment]::UserName) 2>$null
        if ($rec) { $script:FullName = (($rec -split ':')[4] -split ',')[0] }
    }
    $script:FullName
}

# The address of this computer in its local network (the interface that has the default route)
function Get-LotusLanIp {
    try {
        $best = $null
        foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($nic.OperationalStatus -ne 'Up' -or $nic.NetworkInterfaceType -eq 'Loopback') { continue }
            $props = $nic.GetIPProperties()
            $gw = @($props.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0' })
            foreach ($a in $props.UnicastAddresses) {
                if ($a.Address.AddressFamily -ne 'InterNetwork' -or $a.Address.ToString().StartsWith('169.254.')) { continue }
                if ($gw.Count) { return $a.Address.ToString() }
                if (-not $best) { $best = $a.Address.ToString() }
            }
        }
        $best
    } catch { $null }
}

# ── Files and folders ─────────────────────────────────────────

# To the Recycle Bin (it can be put back) → 0; 2 when this system has none a program can use
function Remove-LotusToTrash {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $IsWindows) { return 2 }
    if (-not (Test-Path -LiteralPath $Path)) { return 1 }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        $full = (Resolve-Path -LiteralPath $Path).ProviderPath
        if (Test-Path -LiteralPath $full -PathType Container) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($full, 'OnlyErrorDialogs', 'SendToRecycleBin')
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($full, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
        0
    } catch { 1 }
}

# A folder picker → a result with the path; 1 when cancelled, 2 without a desktop
function Select-LotusFolder {
    param([string]$Prompt, [string]$Start)
    if (-not $IsWindows) { return (Lr 2) }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $d = [System.Windows.Forms.FolderBrowserDialog]::new()
        $d.Description = $Prompt
        $d.UseDescriptionForTitle = $true
        if ($Start -and (Test-Path -LiteralPath $Start)) { $d.SelectedPath = $Start }
        if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return (Lr 1) }
        Lr 0 $d.SelectedPath
    } catch { Lr 2 }
}

# SHA-256 of a file → 64 hex characters (the same value on every system)
function Get-LotusSha256 {
    param([Parameter(Mandatory)][string]$Path)
    try { (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() } catch { $null }
}

# Arguments for a Windows command line, quoted the way programs split them again (CommandLineToArgvW): in quotes when
# they hold a blank or a quote, a quote as \", backslashes before a quote doubled
function ConvertTo-LotusCommandLine {
    param([string[]]$Arguments)
    (@(foreach ($a in $Arguments) {
                if ($a -and $a -notmatch '[\s"]') { $a; continue }
                $sb = [System.Text.StringBuilder]::new('"')
                $bs = 0
                foreach ($ch in $a.ToCharArray()) {
                    if ($ch -eq '\') { $bs++; continue }
                    if ($ch -eq '"') { [void]$sb.Append('\' * (2 * $bs + 1)).Append('"'); $bs = 0; continue }
                    if ($bs) { [void]$sb.Append('\' * $bs); $bs = 0 }
                    [void]$sb.Append($ch)
                }
                [void]$sb.Append('\' * (2 * $bs)).Append('"')
                $sb.ToString()
            })) -join ' '
}

# A program run in the open: its own output, questions and progress go straight to this window (not through
# PowerShell's pipeline, which would hold them back) → its exit code
function Invoke-LotusInTheOpen {
    param([Parameter(Mandatory)][string]$Program, [string[]]$Arguments = @())
    $p = if ($Arguments.Count) { Start-Process -FilePath $Program -ArgumentList (ConvertTo-LotusCommandLine $Arguments) -NoNewWindow -Wait -PassThru }
         else { Start-Process -FilePath $Program -NoNewWindow -Wait -PassThru }
    $p.ExitCode
}

# The first of these programs that is installed → its path, or $null
function Find-LotusProgram {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
    }
    $null
}

# Python 3.9 or newer, for Live Server and /html (lib/live, lib/html – its standard library only) → @{ Exe; Args;
# Version }, or $null. The py launcher first: it comes only with a real Python. A python.exe in WindowsApps is Windows'
# stand-in that sends you to the Microsoft Store – it counts only when it really answers. (Found once per session.)
function Find-LotusPython {
    if ($script:PythonFound) { return $script:PythonFound }
    $tries = [System.Collections.Generic.List[object]]::new()
    $launcher = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($launcher) { $tries.Add(@($launcher.Source, '-3')) }
    foreach ($n in 'python3', 'python') {
        foreach ($c in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) { $tries.Add(@($c.Source)) }
    }
    foreach ($t in $tries) {
        $pre = @($t | Select-Object -Skip 1)
        try { $v = & $t[0] @pre -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>$null } catch { continue }
        if ($LASTEXITCODE -ne 0 -or "$v".Trim() -notmatch '^(\d+)\.(\d+)$') { continue }
        if ([int]$Matches[1] -lt 3 -or ([int]$Matches[1] -eq 3 -and [int]$Matches[2] -lt 9)) { continue }
        $script:PythonFound = [pscustomobject]@{ Exe = $t[0]; Args = $pre; Version = "$v".Trim() }
        return $script:PythonFound
    }
    $null
}

# A Python program of Lotus, in the open (its output and keys go straight to the window), with these environment
# variables for it alone, no bytecode in Lotus' folder and UTF-8 throughout → its exit code
function Invoke-LotusPython {
    param([Parameter(Mandatory)]$Python, [Parameter(Mandatory)][string]$Script, [string[]]$Arguments = @(), [hashtable]$Environment = @{})
    $vars = @{ PYTHONDONTWRITEBYTECODE = '1'; PYTHONUTF8 = '1'; PYTHONIOENCODING = 'utf-8' }
    foreach ($k in $Environment.Keys) { $vars[$k] = [string]$Environment[$k] }
    $saved = @{}
    foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
    try { Invoke-LotusInTheOpen $Python.Exe (@($Python.Args) + @('-B', $Script) + @($Arguments)) }
    finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}

# The same, its output as text (for a program that answers, not one that talks to you)
function Invoke-LotusPythonText {
    param([Parameter(Mandatory)]$Python, [Parameter(Mandatory)][string]$Script, [string[]]$Arguments = @(), [hashtable]$Environment = @{})
    $vars = @{ PYTHONDONTWRITEBYTECODE = '1'; PYTHONUTF8 = '1'; PYTHONIOENCODING = 'utf-8' }
    foreach ($k in $Environment.Keys) { $vars[$k] = [string]$Environment[$k] }
    $saved = @{}
    foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
    try { Invoke-LotusNativeText $Python.Exe (@($Python.Args) + @('-B', $Script) + @($Arguments)) }
    finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}
