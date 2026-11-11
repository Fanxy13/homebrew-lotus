# lotus setup, update, doctor, uninstall, unhook – a port of lib/cmd/system.zsh for Windows

function script:Invoke-Lotussystem {
    param([string]$Cmd, [string[]]$Rest)
    switch -CaseSensitive ($Cmd) {
        'setup' { return Invoke-LotusSetup $Rest }
        { $_ -cin 'update', 'upgrade' } { return Invoke-LotusUpdate }
        'doctor' { return Invoke-LotusDoctor $Rest }
        'uninstall' { return Invoke-LotusUninstall $Rest }
        'unhook' {
            $gone = 0
            foreach ($pp in (Get-LotusProfilePaths)) { if (Remove-LotusHook -ProfilePath $pp) { Write-LotusSuccess "$(T removed_from 'Removed from') $pp"; $gone++ } }
            if (-not $gone) { Write-LotusInfo 'There were no Lotus lines in your PowerShell profile.' }
            return (St 0)
        }
    }
}

# Put in place by install.ps1 (%LOCALAPPDATA%\lotus\app, or where LOTUS_DEST said): it can update and remove itself
function script:Test-LotusOwnInstall {
    $root = Get-LotusRoot
    (Test-Path -LiteralPath (Join-Path $root '.lotus-install')) -or ($IsWindows -and $env:LOCALAPPDATA -and $root -eq (Join-Path $env:LOCALAPPDATA 'lotus\app'))
}

# The wizard and the lines in the PowerShell profile
#   --hook   only the profile lines · --first  the wizard only when Lotus was never set up · --tty  the wizard
function script:Invoke-LotusSetup {
    param([string[]]$Rest)
    $opt = if ($Rest.Count) { $Rest[0] } else { '' }
    $wizard = switch -CaseSensitive ($opt) {
        '--hook' { $false }
        '--first' { -not (Test-LotusOn $script:S['LOTUS_CONFIGURED']) }
        '--tty' { $true }
        default { Test-LotusTty }
    }
    if ($wizard -and (Test-LotusTty)) {
        Import-LotusCommand setup
        $r = $null
        foreach ($o in (Invoke-LotusSetupWizard)) { if (Test-LotusStatus $o) { $r = $o.Code } }
        if ($r) { return (St 1) }
        Initialize-Lotus
    }
    # a settings file made new here is of this version: read as one of Lotus 1.x it would skip the first setup
    if (-not (Test-Path -LiteralPath $script:Paths.Settings)) { $script:S['LOTUS_CONFIG_VERSION'] = '3'; Save-LotusSettings -Quiet }
    Update-LotusFastfetchConfig -Force
    foreach ($pp in (Get-LotusProfilePaths)) { $path = Add-LotusHook -ProfilePath $pp; Write-LotusSuccess "$(T added_to 'Added to') $path" }
    Write-LotusInfo 'Open a new PowerShell window – or load it here: . $PROFILE.CurrentUserAllHosts'
    St 0
}

# The newest version on GitHub (the version line of lib/core.zsh on main) → the version, or $null when offline
function script:Get-LotusLatestVersion {
    try {
        $src = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$($script:P['repo'])/main/lib/core.zsh" -TimeoutSec 8 -ErrorAction Stop
        foreach ($line in ([string]$src) -split "`n") { if ($line -match '^typeset -g LOTUS_VERSION=(\S+)') { return $Matches[1] } }
    } catch { }
    $null
}

function script:Invoke-LotusUpdate {
    Write-LotusHeader 'Update'
    Write-LotusStep 'Checking for a new version …'
    $latest = Get-LotusLatestVersion
    if (-not $latest) {
        Write-LotusError 'Could not reach GitHub' 'Check your internet connection and try again.'
        return (St 1)
    }
    $own = Test-LotusOwnInstall
    Write-LotusCard 'Lotus' @("INSTALLED|$(Get-LotusVersion)", "AVAILABLE|$latest", "SOURCE|$(if ($own) { 'install script' } else { 'this folder' })")
    Write-LotusBlank
    if ($latest -ceq (Get-LotusVersion)) {
        Write-LotusSuccess "$(T up_to_date 'lotus is up to date') ($(Get-LotusVersion))"
        return (St 0)
    }
    if (-not $own) {
        Write-LotusInfo "Lotus runs from $(Get-LotusRoot) – a checkout or a folder of your own."
        Write-LotusDim 'Update it the way you put it there (git pull), or install the published version: irm https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.ps1 | iex'
        return (St 0)
    }
    # the installer of the newest version, saved to a file first: it is run as a program, never as text
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "lotus-install-$([guid]::NewGuid().ToString('N')).ps1"
    $url = "https://raw.githubusercontent.com/$($script:P['repo'])/main/install.ps1"
    try { Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop }
    catch { Write-LotusError 'The download failed' $url; return (St 1) }
    Write-LotusStep "Updating to $latest – your settings stay as they are"
    Write-LotusDim "The installer: $url"
    if ((Test-LotusTty) -and -not (Read-LotusConfirm "Update Lotus to $latest now?" 'y')) { Remove-Item -LiteralPath $tmp -Force; return (St 0) }
    $env:LOTUS_DEST = Get-LotusRoot
    $env:LOTUS_NO_SETUP = '1'
    try {
        $p = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-File', $tmp) -NoNewWindow -Wait -PassThru
        if ($p.ExitCode -ne 0) { Write-LotusError 'The update failed' 'The installer said why, above.'; return (St 1) }
    } finally {
        Remove-Item Env:LOTUS_DEST, Env:LOTUS_NO_SETUP -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    Write-LotusSuccess "Lotus $latest is installed. Open a new PowerShell window."
    St 0
}

function script:Invoke-LotusDoctor {
    param([string[]]$Rest)
    $ok = "$(E '1')$(E key)✓$($script:R)"; $bad = "$(E '1;38;5;203')✗$($script:R)"; $opt = "$(E dim)·$($script:R)"
    $row = { param($mark, $name, $text) Write-LotusLine "  $mark $(PadR $name 17) $text" }
    Write-LotusHeader 'Doctor' "lotus $(Get-LotusVersion)"
    $o = $script:Os
    & $row $ok $(if ($IsWindows) { 'Windows' } else { 'System' }) "$(Get-LotusOsDescription)$(if ($IsWindows) { " (build $($o.Build))" })"
    # (Windows PowerShell 5.1 – the one Windows 11 comes with – and PowerShell 7.2 or newer)
    $core = $PSVersionTable.PSEdition -eq 'Core'
    $psok = if ($core) { $PSVersionTable.PSVersion -ge [version]'7.2' } else { $PSVersionTable.PSVersion -ge [version]'5.1' }
    $psName = if ($core) { 'PowerShell' } else { 'Windows PowerShell' }
    & $row $(if ($psok) { $ok } else { $bad }) 'PowerShell' "$psName $($PSVersionTable.PSVersion)$(if (-not $psok) { ' – Lotus needs Windows PowerShell 5.1 or PowerShell 7.2 or newer: winget install Microsoft.PowerShell' })"
    & $row $ok 'Terminal' $(if ($o.Terminal) { $o.Terminal } else { T unknown_term 'unknown terminal' })
    if ($IsWindows) {
        $pk = Get-LotusPackageManagers
        if ($pk.Count) { & $row $ok 'Packages' (($pk) -join ', ') } else { & $row $opt 'Packages' 'no winget – /install needs it: get "App Installer" from the Microsoft Store' }
    }
    & $row $ok 'Lotus' (Get-LotusRoot)
    $ff = Get-LotusFastfetch
    if ($ff) { & $row $ok 'fastfetch' "$((Invoke-LotusNativeText $ff @('--version')) -replace '\s+$', '') ($ff)" }
    else { & $row $bad 'fastfetch' 'missing – install it again: lotus update, or winget install Fastfetch-cli.Fastfetch' }
    & $row $ok (T doc_colors 'Colors') "$($script:Mode) ($(if ($o.Terminal) { $o.Terminal } else { T unknown_term 'unknown terminal' }))"
    & $row $(if (Test-Path -LiteralPath $script:Paths.Settings) { $ok } else { $opt }) 'Settings' $script:Paths.Settings
    if (Test-LotusHook) { & $row $ok 'Profile' "$(T doc_rc_ok 'set up') ($(Get-LotusProfilePath))" }
    else { & $row $bad 'Profile' 'not set up – run: lotus setup' }
    if ($ff) {
        Update-LotusFastfetchConfig
        $np = (Update-LotusNowPlaying) -split "`n"
        & $row $ok (T doc_music 'Music') "$($np[0])$($script:R)"
    }
    Write-LotusBlank
    Write-LotusDim 'Optional, for single commands'
    $tool = { param($names) Find-LotusProgram $names }
    $y = & $tool @('yt-dlp'); $f = & $tool @('ffmpeg')
    if ($y -and $f) { & $row $ok 'yt-dlp' "$y with ffmpeg  (/convert)" } else { & $row $opt 'yt-dlp' 'yt-dlp and ffmpeg are needed for /convert – it offers them' }
    $m = & $tool @('magick')
    if ($m) { & $row $ok 'ImageMagick' "$m  (/img convert)" } else { & $row $opt 'ImageMagick' 'needed for /img convert: winget install ImageMagick.ImageMagick' }
    # (python.exe in WindowsApps only sends you to the Microsoft Store: Find-LotusPython counts a Python that answers)
    $py = Find-LotusPython
    if ($py) { & $row $ok 'Python' "$($py.Exe) $($py.Version)  (/liveserver, /html)" } else { & $row $opt 'Python' 'needed for /liveserver and /html: winget install Python.Python.3.13' }
    if (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/minecraft.ps1')) {
        Import-LotusCommand minecraft
        $jh = Find-LotusJava 17
        if ($jh) { & $row $ok 'Java' "$(Get-LotusJavaLabel $jh)  (/minecraft)" } else { & $row $opt 'Java' 'not installed – /minecraft can set it up' }
    }
    Import-LotusCommand meshchat
    $mc = Find-LotusMeshChat
    if ($mc) { & $row $ok 'MeshChat' "$mc  (/meshchat)" } else { & $row $opt 'MeshChat' 'meshchat.exe is not installed – /meshchat offers it' }
    if ($env:ANTHROPIC_API_KEY -or (Get-LotusSecret 'lotus-ai-claude')) { & $row $ok 'Claude' "API key in $(Get-LotusSecretStoreName)  (/ai)" }
    else { & $row $opt 'Claude' 'optional AI provider: lotus ai login' }
    $ol = & $tool @('ollama')
    if ($ol) { & $row $ok 'Ollama' "$ol  (/ai)" } else { & $row $opt 'Ollama' 'optional AI provider for /ai' }
    Write-LotusBlank
    if ((Test-LotusFeature 'pets') -and (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/pets.ps1'))) {
        Write-LotusDim 'Pets'
        Import-LotusCommand pets
        Show-LotusPetDoctorRows $row $ok $opt
        Write-LotusBlank
    }
    # Remove BG: when the feature is on, or on request (lotus doctor --bg)
    if (((Test-LotusFeature 'bg') -or $Rest -contains '--bg' -or $Rest -contains '--all') -and (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot 'Public/bg.ps1'))) {
        Write-LotusDim 'Remove BG'
        Import-LotusCommand bg
        Import-LotusLangGroup bg
        Show-LotusBgDoctorRows $row $ok $bad $opt
        Write-LotusBlank
    }
    Write-LotusDim 'Diagnostics'
    $size = 0
    if (Test-Path -LiteralPath $script:Paths.Log) { $size = [Math]::Truncate((Get-Item -LiteralPath $script:Paths.Log).Length / 1024) }
    & $row $ok 'Log' "$(Format-LotusPath $script:Paths.Log 60) ($size KB, level: $($script:S['LOTUS_LOG_LEVEL']))"
    $off = @($script:FeatureIds | Where-Object { -not (Test-LotusFeature $_) })
    & $row $ok 'Features' "$($script:FeatureIds.Count - $off.Count) of $($script:FeatureIds.Count) on$(if ($off.Count) { " (off: $($off -join ', '))" })"
    Write-LotusBlank
    Write-LotusLog DEBUG doctor 'Doctor run'
    St 0
}

# Removes everything Lotus made. With --yes nothing is asked.
function script:Invoke-LotusUninstall {
    param([string[]]$Rest)
    $paths = $script:Paths
    if ($Rest -notcontains '--yes') {
        Write-LotusHeader 'Uninstall'
        Write-LotusText 'Removes Lotus, its settings, pets, shortcuts, AI keys, the log, cache and the lines in your PowerShell profile:'
        foreach ($d in $paths.Conf, $paths.Cache, $paths.State) { Write-LotusDim "  $d" }
        Write-LotusBlank
        if (-not (Read-LotusConfirm 'Uninstall Lotus completely?' 'n')) { Write-LotusInfo (T cancelled 'Cancelled.'); return (St 1) }
    }
    foreach ($pp in (Get-LotusProfilePaths)) { if (Remove-LotusHook -ProfilePath $pp) { Write-LotusSuccess "$(T removed_from 'Removed from') $pp" } }
    # keep awake that Lotus started stops with it
    try { Import-LotusCommand caffeine; Stop-LotusCaffeine -Quiet | Out-Null } catch { }
    foreach ($s in 'lotus-ai', 'lotus-ai-claude', 'lotus-hf') { Remove-LotusSecret $s | Out-Null }
    foreach ($dir in @($paths.Conf, $paths.Cache, $paths.State)) {
        if ($dir -and (Test-Path -LiteralPath $dir) -and $dir.Length -gt 12) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($sub in 'runtime', 'models', 'llm', 'vendor', 'bin') {
        $p = Join-Path $paths.Data $sub
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if ((Test-Path -LiteralPath $paths.Data) -and -not (Get-ChildItem -LiteralPath $paths.Data -Force)) { Remove-Item -LiteralPath $paths.Data -Force }
    $root = Get-LotusRoot
    if (Test-LotusOwnInstall) {
        [void](Remove-LotusUserPath (Join-Path $root 'bin'))
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        $parent = Split-Path -Parent $root
        if ((Test-Path -LiteralPath $parent) -and -not (Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue }
    } else {
        Write-LotusInfo "$(T own_install 'Program files stay in place (custom install):') $root"
    }
    Write-LotusSuccess 'Lotus has been removed. Open a new PowerShell window and it is gone.'
    St 0
}

