# Install Lotus on Windows 11 (preview) – PowerShell 7 and Windows Terminal. No administrator rights, no WSL:
#   irm https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.ps1 | iex
# macOS and Linux have their own: install.sh
#
# What it does: copies Lotus into %LOCALAPPDATA%\lotus\app, offers fastfetch (the command is shown first, nothing is
# installed without a yes) and puts a block into your PowerShell profile so that Lotus loads in every window.
# Options are environment variables, so that the script also works when it is piped into iex:
#   LOTUS_SRC      a folder to copy Lotus from instead of downloading it (a checkout)
#   LOTUS_DEST     where to put it (default %LOCALAPPDATA%\lotus\app)
#   LOTUS_PROFILE  the profile file to change (default $PROFILE.CurrentUserAllHosts)
#   LOTUS_NO_PROFILE=1  do not touch the profile

function Install-Lotus {
    $repo = if ($env:LOTUS_REPO) { $env:LOTUS_REPO } else { 'Fanxy13/homebrew-lotus' }
    $say = { param($m) Write-Host '  lotus  ' -ForegroundColor Green -NoNewline; Write-Host $m }
    $note = { param($m) Write-Host "  .      $m" -ForegroundColor DarkGray }
    $fail = { param($m) Write-Host "  x      $m" -ForegroundColor Red; throw $m }

    if ($PSVersionTable.PSVersion.Major -lt 7 -or ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -lt 2)) {
        & $fail 'Lotus needs PowerShell 7.2 or newer. Install it with: winget install --id Microsoft.PowerShell -e   then open "PowerShell 7" and run this again.'
    }
    $onWindows = $IsWindows
    if ($onWindows) {
        $build = [Environment]::OSVersion.Version.Build
        if ($build -lt 22000) { & $note "This is Windows build $build. Lotus is built for Windows 11 (build 22000 or newer) and Windows Terminal." }
    }
    & $say "$([System.Runtime.InteropServices.RuntimeInformation]::OSDescription) - $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"

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
        # only what Windows needs: the module, the shared data, the logos and the file that holds the version
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($item in 'win', 'data', 'logos') {
            $target = Join-Path $dest $item
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            Copy-Item -LiteralPath (Join-Path $src $item) -Destination $target -Recurse
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $dest 'lib') | Out-Null
        Copy-Item -LiteralPath (Join-Path $src 'lib/core.zsh') -Destination (Join-Path $dest 'lib/core.zsh') -Force
        # the tests and the sample settings are not for users
        Remove-Item -LiteralPath (Join-Path $dest 'win/tests') -Recurse -Force -ErrorAction SilentlyContinue
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    & $say "Lotus is in $dest"

    # 2. fastfetch shows your system next to the logo: the command first, then a question
    if (-not (Get-Command fastfetch -ErrorAction SilentlyContinue)) {
        & $note 'fastfetch (your system next to the logo) is not installed.'
        if ($onWindows -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            $cmd = 'winget install --id Fastfetch-cli.Fastfetch -e'
            & $note "The command: $cmd"
            if (-not [Console]::IsInputRedirected -and (Read-Host '  ?      Install it now? [y/N]') -match '^(y|yes|j|ja)$') {
                & winget install --id Fastfetch-cli.Fastfetch -e
            }
        } else {
            & $note 'Install fastfetch with winget, Scoop or Chocolatey; without it the start screen shows the logo only.'
        }
    } else {
        & $say 'fastfetch is already installed.'
    }

    # 3. load Lotus in every PowerShell window (a block in your profile; `lotus unhook` takes it out again)
    Import-Module (Join-Path $dest 'win/Lotus.psd1') -Force
    if ($env:LOTUS_NO_PROFILE -eq '1') {
        & $note ('Your profile was not changed (LOTUS_NO_PROFILE=1). Load Lotus with: Import-Module "' + (Join-Path $dest 'win/Lotus.psd1') + '"')
    } else {
        lotus setup --hook
    }
    & $say 'Done. Open a new PowerShell window.'
}

Install-Lotus
