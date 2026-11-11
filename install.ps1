# Install Lotus on Windows 11 - in the Windows PowerShell 5.1 that Windows 11 comes with, or in PowerShell 7, and Windows
# Terminal. No administrator rights, no WSL:
#   irm https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.ps1 | iex
# macOS and Linux have their own: install.sh
#
# What it does: copies Lotus into %LOCALAPPDATA%\lotus\app, puts lotus.cmd into your user PATH (for cmd.exe and the Run
# dialog), offers fastfetch (the command is shown first, nothing is installed without a yes) and puts a block into your
# PowerShell profile so that Lotus loads in every window. lotus update runs it again; lotus uninstall takes it all out.
# Options are environment variables, so that the script also works when it is piped into iex:
#   LOTUS_SRC        a folder to copy Lotus from instead of downloading it (a checkout)
#   LOTUS_DEST       where to put it (default %LOCALAPPDATA%\lotus\app)
#   LOTUS_PROFILE    the profile file to change (default $PROFILE.CurrentUserAllHosts)
#   LOTUS_NO_PROFILE=1  do not touch the profile - LOTUS_NO_PATH=1  do not touch your PATH
#   LOTUS_NO_SETUP=1    no start screen and no setup wizard at the end (lotus update)
#   LOTUS_FASTFETCH  winget (the default when winget is there) - pinned (Lotus' own copy: the version of data\vendor.tsv,
#                    checked against its SHA-256) - no
#   LOTUS_YES=1      yes to the questions (for scripts: fastfetch)
# (This file is read by Windows PowerShell 5.1 - and run with irm | iex, so it stays ASCII, without a byte order mark.)

function Install-Lotus {
    # Windows PowerShell 5.1: TLS 1.2 for the downloads (older systems offer only the old ones), and no progress bar (it makes
    # the download of a zip slow)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $ProgressPreference = 'SilentlyContinue'
    $repo = if ($env:LOTUS_REPO) { $env:LOTUS_REPO } else { 'Fanxy13/homebrew-lotus' }
    $say = { param($m) Write-Host '  lotus  ' -ForegroundColor Green -NoNewline; Write-Host $m }
    $note = { param($m) Write-Host "  .      $m" -ForegroundColor DarkGray }
    $warn = { param($m) Write-Host "  !      $m" -ForegroundColor Yellow }
    $fail = { param($m) Write-Host "  x      $m" -ForegroundColor Red; throw $m }
    $ask = {
        param($q)
        if ($env:LOTUS_YES -eq '1') { & $note "$q yes (LOTUS_YES=1)"; return $true }
        if ([Console]::IsInputRedirected) { return $false }
        (Read-Host "  ?      $q [y/N]") -match '^(y|yes|j|ja|o|oui|s|si)$'
    }

    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        & $fail 'Lotus needs Windows PowerShell 5.1 (Windows 10 and 11 have it) or PowerShell 7.'
    }
    # (Windows PowerShell has no $IsWindows: it is Windows only)
    $onWindows = if ($PSVersionTable.PSEdition -ne 'Core') { $true } else { $IsWindows }
    $windowsPowerShell = $onWindows -and $PSVersionTable.PSEdition -ne 'Core'
    # A new Windows 11 lets Windows PowerShell run no script files (the policy is Restricted). This installer was typed in, so it
    # runs - but Lotus' module and the profile that loads it are script files. For this installer's own work this window gets
    # a policy of its own (it ends with the window); what stays is asked about further down, the command first.
    $policy = ''
    if ($windowsPowerShell) { try { $policy = [string](Get-ExecutionPolicy -ErrorAction Stop) } catch { } }
    if ($windowsPowerShell -and $policy -in 'Restricted', 'AllSigned') {
        try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop }
        catch { & $warn "Your organization's policy does not let this window run Lotus' scripts: $($_.Exception.Message)" }
    }
    if ($onWindows) {
        $build = [Environment]::OSVersion.Version.Build
        if ($build -lt 22000) { & $note "This is Windows build $build. Lotus is built for Windows 11 (build 22000 or newer) and Windows Terminal." }
    }
    # (the processor: .NET says it; in one Windows PowerShell 5.1 console it said nothing - the environment is the second chance)
    $arch = ''
    try { $arch = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture } catch { }
    if (-not $arch) {
        $cpu = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        $arch = if ($cpu -eq 'ARM64') { 'Arm64' } elseif ($cpu -eq 'x86') { 'X86' } elseif ($cpu -eq 'AMD64') { 'X64' } elseif ([Environment]::Is64BitOperatingSystem) { 'X64' } else { 'X86' }
    }
    $osText = ''
    try { $osText = [string][System.Runtime.InteropServices.RuntimeInformation]::OSDescription } catch { }
    if (-not $osText) { $osText = [Environment]::OSVersion.VersionString }
    & $say "$osText - $arch"

    $dest = if ($env:LOTUS_DEST) { $env:LOTUS_DEST }
            elseif ($onWindows) { Join-Path $env:LOCALAPPDATA 'lotus/app' }
            else { Join-Path $HOME '.local/share/lotus-win' }

    # 1. Lotus itself: a folder you name, or the download of the repository (https from github.com only)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('lotus-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        if ($env:LOTUS_SRC) {
            $src = $env:LOTUS_SRC
        } else {
            if ($repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { & $fail "Not a repository name: $repo" }
            & $say 'Downloading Lotus ...'
            $zip = Join-Path $tmp 'lotus.zip'
            try { Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing }
            catch { & $fail 'The download failed. Check your internet connection.' }
            Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
            $src = (Get-ChildItem -LiteralPath $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'win/Lotus.psd1') } | Select-Object -First 1).FullName
        }
        if (-not $src -or -not (Test-Path (Join-Path $src 'win/Lotus.psd1')) -or -not (Test-Path (Join-Path $src 'data/commands.tsv'))) {
            & $fail "That does not look like Lotus ($src)."
        }
        # only what Windows needs: the module, the shared data, the logos, the shims, and from lib/ the file that holds the
        # version, the settings' keys and defaults, the texts in four languages and the Python of Live Server and /html
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($item in 'win', 'data', 'logos', 'lib/lang', 'lib/live', 'lib/html') {
            $from = Join-Path $src $item
            $target = Join-Path $dest $item
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            if (-not (Test-Path -LiteralPath $from)) { continue }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $from -Destination $target -Recurse
        }
        Copy-Item -LiteralPath (Join-Path $src 'lib/core.zsh') -Destination (Join-Path $dest 'lib/core.zsh') -Force
        New-Item -ItemType Directory -Force -Path (Join-Path $dest 'bin') | Out-Null
        foreach ($shim in 'lotus.cmd', 'lotus.ps1') { Copy-Item -LiteralPath (Join-Path $src "bin/$shim") -Destination (Join-Path $dest "bin/$shim") -Force }
        # the tests are not for users, nor the sources of meshchat.exe (its installer brings the program)
        Remove-Item -LiteralPath (Join-Path $dest 'win/tests') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $dest 'win/meshchat') -Recurse -Force -ErrorAction SilentlyContinue
        # the mark of an install of this script: lotus update and lotus uninstall may change this folder
        [System.IO.File]::WriteAllText((Join-Path $dest '.lotus-install'), "installed by install.ps1`n$((Get-Date).ToString('s'))`n", [System.Text.UTF8Encoding]::new($false))
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    & $say "Lotus is in $dest"

    # 2. fastfetch shows your system next to the logo: with winget, or Lotus' own pinned copy - the command first, then a question
    $vendorExe = Join-Path $dest 'vendor/fastfetch/fastfetch.exe'
    $want = [string]$env:LOTUS_FASTFETCH
    if ($want -eq 'no') {
        & $note 'fastfetch: not now (LOTUS_FASTFETCH=no) - the start screen shows the logo only.'
    } elseif ($want -ne 'pinned' -and (Get-Command fastfetch -CommandType Application -ErrorAction SilentlyContinue)) {
        & $say 'fastfetch is already installed.'
    } elseif (Test-Path -LiteralPath $vendorExe) {
        & $say 'fastfetch is there (Lotus'' own copy).'
    } else {
        $got = $false
        if ($want -ne 'pinned' -and $onWindows -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            & $note 'fastfetch (your system next to the logo) is not installed.'
            & $note 'The command: winget install --id Fastfetch-cli.Fastfetch -e'
            if (& $ask 'Install it now?') {
                & winget install --id Fastfetch-cli.Fastfetch -e
                $got = $LASTEXITCODE -eq 0
            }
        }
        if (-not $got -and $onWindows) {
            # the release asset data\vendor.tsv pins for this processor, checked against its SHA-256 before it is used
            $platform = if ($arch -eq 'Arm64') { 'windows-aarch64' } else { 'windows-amd64' }
            $pin = Get-Content -LiteralPath (Join-Path $dest 'data/vendor.tsv') | Where-Object { $_ -notmatch '^#' } |
                ForEach-Object { , ($_ -split "`t") } | Where-Object { $_[0] -eq 'fastfetch' -and $_[2] -eq $platform } | Select-Object -First 1
            if ($pin) {
                & $note "Or Lotus' own copy: fastfetch $($pin[1]) from $($pin[3])"
                & $note "  checked against SHA-256 $($pin[4]), into $(Split-Path -Parent $vendorExe)"
                if (& $ask 'Download it?') {
                    $ffTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('lotus-fastfetch-' + [guid]::NewGuid().ToString('N'))
                    New-Item -ItemType Directory -Force -Path $ffTmp | Out-Null
                    try {
                        $ffZip = Join-Path $ffTmp 'fastfetch.zip'
                        Invoke-WebRequest -Uri $pin[3] -OutFile $ffZip -UseBasicParsing
                        $sum = (Get-FileHash -LiteralPath $ffZip -Algorithm SHA256).Hash.ToLowerInvariant()
                        if ($sum -ne $pin[4]) {
                            & $warn "The download is not the file Lotus pinned (SHA-256 $sum) - it was deleted, nothing was installed."
                        } else {
                            Expand-Archive -LiteralPath $ffZip -DestinationPath (Join-Path $ffTmp 'x') -Force
                            $exe = Get-ChildItem -LiteralPath (Join-Path $ffTmp 'x') -Recurse -Filter 'fastfetch.exe' | Select-Object -First 1
                            if (-not $exe) { & $warn 'The download has no fastfetch.exe - nothing was installed.' }
                            else {
                                $vendor = Split-Path -Parent $vendorExe
                                if (Test-Path -LiteralPath $vendor) { Remove-Item -LiteralPath $vendor -Recurse -Force }
                                New-Item -ItemType Directory -Force -Path $vendor | Out-Null
                                Copy-Item -Path (Join-Path $exe.DirectoryName '*') -Destination $vendor -Recurse -Force
                                & $say "fastfetch $($pin[1]) is in $vendor"
                                $got = $true
                            }
                        }
                    } catch {
                        & $warn "fastfetch could not be downloaded: $($_.Exception.Message)"
                    } finally { Remove-Item -LiteralPath $ffTmp -Recurse -Force -ErrorAction SilentlyContinue }
                }
            }
        }
        if (-not $got) { & $note 'Without fastfetch the start screen shows the logo only - lotus doctor says how to add it.' }
    }

    # 3. lotus in cmd.exe and the Run dialog too: the shims' folder in your user PATH (never the system's)
    Import-Module (Join-Path $dest 'win/Lotus.psd1') -Force
    $bin = Join-Path $dest 'bin'
    if (-not $onWindows) { }
    elseif ($env:LOTUS_NO_PATH -eq '1') { & $note "Your PATH was not changed (LOTUS_NO_PATH=1). lotus.cmd is in $bin" }
    elseif (& (Get-Module Lotus) { param($d) Add-LotusUserPath $d } $bin) { & $say "lotus.cmd is in your PATH ($bin) - for cmd.exe and the Run dialog." }

    # 4. load Lotus in every PowerShell window (a block in your profile; lotus unhook takes it out again). Windows PowerShell on a
    # new Windows 11 would not run that profile at all (policy Restricted): RemoteSigned for your user - local scripts run,
    # downloaded ones need a signature; what PowerShell 7 has by default - is the usual setting, and it asks first.
    if ($windowsPowerShell -and $env:LOTUS_NO_PROFILE -ne '1') {
        $list = @()
        try { $list = @(Get-ExecutionPolicy -List -ErrorAction Stop) } catch { }
        $mine = [string]($list | Where-Object { $_.Scope -eq 'CurrentUser' }).ExecutionPolicy
        $machine = [string]($list | Where-Object { $_.Scope -eq 'LocalMachine' }).ExecutionPolicy
        $inForce = [string]($list | Where-Object { $_.Scope -in 'MachinePolicy', 'UserPolicy' -and $_.ExecutionPolicy -ne 'Undefined' } | Select-Object -First 1).ExecutionPolicy
        if ($inForce -in 'Restricted', 'AllSigned') {
            & $warn "A policy of your organization ($inForce) keeps Windows PowerShell from running Lotus' profile lines - ask your administrator, or use PowerShell 7."
        } elseif (($mine -in 'Undefined', 'Restricted', 'AllSigned') -and ($machine -in 'Undefined', 'Restricted', 'AllSigned')) {
            & $note 'Windows PowerShell runs no script files here (ExecutionPolicy Restricted) - not even the profile that loads Lotus.'
            & $note 'The command: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned'
            if (& $ask 'Set it now (for your user only)?') {
                $failed = $null
                try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop } catch { $failed = $_ }
                # This window runs under a policy of its own (Process, Bypass - set above). PowerShell then calls the new policy of
                # the user "overridden by a more specific scope" and reports it as an error ("Security error.") although it IS
                # set - so what is set is looked at, not the error.
                $now = ''
                try { $now = [string](Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop) } catch { }
                if ($now -eq 'RemoteSigned') { & $say 'ExecutionPolicy RemoteSigned for your user.' }
                else {
                    $why = ''
                    if ($failed) { $why = if ($failed.ErrorDetails -and $failed.ErrorDetails.Message) { $failed.ErrorDetails.Message } else { $failed.Exception.Message } }
                    & $warn "It did not work: $why"
                }
            } else {
                & $warn 'Without it a new window prints an error and does not load Lotus - run the command above when you want it.'
            }
        }
    }
    if ($env:LOTUS_NO_PROFILE -eq '1') {
        & $note ('Your profile was not changed (LOTUS_NO_PROFILE=1). Load Lotus with: Import-Module "' + (Join-Path $dest 'win/Lotus.psd1') + '"')
    } else {
        lotus setup --hook
    }
    & $say 'Done. Open a new PowerShell window.'
}

Install-Lotus
# the start screen - and the setup wizard the first time
if ($env:LOTUS_NO_SETUP -ne '1') { lotus }
