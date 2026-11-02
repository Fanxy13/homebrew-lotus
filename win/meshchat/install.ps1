# Install MeshChat for Windows (meshchat.exe) without a browser. In PowerShell - the Windows PowerShell 5.1 every
# Windows 10 and 11 has, or PowerShell 7 - in Windows Terminal, or Win+X > Terminal:
#   irm https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/win/meshchat/install.ps1 | iex
# A browser warns about a program it has not seen often, and meshchat.exe is not signed. PowerShell downloads it
# without a question, so this script checks it instead: the newest MeshChat for Windows from the releases of
# github.com/Fanxy13/homebrew-lotus, with its SHA-256 compared to the release's SHA256SUMS.txt - a file that does not
# match is deleted, never run. No administrator rights: the program goes to %LOCALAPPDATA%\Programs\MeshChat, that
# folder into your PATH (yours only), and "MeshChat" into the Start menu. Run it again for the newest version.
# Options are environment variables, so that the script also works piped into iex:
#   MESHCHAT_UNINSTALL=1   take it away again (the program, the PATH entry, the Start menu entry - not your history)
#   MESHCHAT_DIR           where to put it (default %LOCALAPPDATA%\Programs\MeshChat)
#   MESHCHAT_TAG           a release to take instead of the newest one, e.g. meshchat-windows-v2.0.0
# Only ASCII in here: Windows PowerShell 5.1 reads a script file without a byte order mark as ANSI.

function Install-MeshChat {
    $repo = 'Fanxy13/homebrew-lotus'
    $say = { param($m) Write-Host '  meshchat  ' -ForegroundColor Magenta -NoNewline; Write-Host $m }
    $note = { param($m) Write-Host "  .         $m" -ForegroundColor DarkGray }
    $fail = { param($m) Write-Host "  x         $m" -ForegroundColor Red; throw $m }

    if ($env:OS -ne 'Windows_NT') { & $fail 'This installs MeshChat for Windows. On a Mac, MeshChat comes with Lotus: lotus meshchat' }
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 19041) { & $fail "This is Windows build $build. MeshChat needs Windows 10 version 2004 (build 19041) or newer." }
    $dir = if ($env:MESHCHAT_DIR) { $env:MESHCHAT_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\MeshChat' }
    $exe = Join-Path $dir 'meshchat.exe'
    $link = Join-Path ([Environment]::GetFolderPath('Programs')) 'MeshChat.lnk'

    # your PATH as it is in the registry: %VARIABLES% in it stay as they are
    $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $rawPath = [string]$envKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $pathKind = if ($envKey.GetValueNames() -contains 'Path') { $envKey.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
    $parts = @($rawPath -split ';' | Where-Object { $_ -ne '' })
    $hasDir = [bool]($parts | Where-Object { $_.TrimEnd('\') -eq $dir.TrimEnd('\') })
    $setPath = {
        param($list)
        $envKey.SetValue('Path', ($list -join ';'), $pathKind)
        # tell Windows the environment changed, so that new windows see it (setting a variable with .NET says so)
        [Environment]::SetEnvironmentVariable('MESHCHAT_INSTALL_REFRESH', '1', 'User')
        [Environment]::SetEnvironmentVariable('MESHCHAT_INSTALL_REFRESH', $null, 'User')
    }

    if ($env:MESHCHAT_UNINSTALL -eq '1') {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        if ($hasDir) { & $setPath @($parts | Where-Object { $_.TrimEnd('\') -ne $dir.TrimEnd('\') }) }
        & $say 'MeshChat is removed.'
        & $note 'Your name, identity and history are still in %LOCALAPPDATA%\lotus\data\meshchat - delete that folder too if you like.'
        # in this window, the line installs again
        Remove-Item -LiteralPath Env:MESHCHAT_UNINSTALL -ErrorAction SilentlyContinue
        return
    }

    # TLS 1.2 also for Windows PowerShell 5.1 on older systems
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
    $asset = "meshchat-windows-$arch.exe"

    # the release: the one named, or the newest of MeshChat for Windows (the releases of Lotus itself are others)
    $headers = @{ 'User-Agent' = 'meshchat-install'; 'Accept' = 'application/vnd.github+json' }
    $release = $null
    try {
        if ($env:MESHCHAT_TAG) {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/tags/$($env:MESHCHAT_TAG)" -Headers $headers -UseBasicParsing
        } else {
            $all = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases?per_page=50" -Headers $headers -UseBasicParsing
            $release = $all | Where-Object { $_.tag_name -like 'meshchat-windows-v*' -and -not $_.draft } | Select-Object -First 1
        }
    } catch {
        & $fail "GitHub could not be asked for MeshChat: $($_.Exception.Message)"
    }
    if (-not $release) { & $fail "There is no release of MeshChat for Windows yet: https://github.com/$repo/releases" }
    $exeAsset = $release.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1
    $sumAsset = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
    if (-not $exeAsset -or -not $sumAsset) { & $fail "The release $($release.tag_name) has no $asset or no SHA256SUMS.txt" }
    foreach ($a in @($exeAsset, $sumAsset)) {
        if ($a.browser_download_url -notlike "https://github.com/$repo/releases/download/*") { & $fail "Not a download of github.com/$repo - $($a.browser_download_url)" }
    }
    & $say ("{0} - {1}, {2} MB" -f $release.name, $asset, [math]::Round($exeAsset.size / 1MB))

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('meshchat-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $file = Join-Path $tmp $asset
        $sums = Join-Path $tmp 'SHA256SUMS.txt'
        $progress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'        # its progress bar makes Windows PowerShell 5.1 download slowly
        try {
            Invoke-WebRequest -Uri $exeAsset.browser_download_url -OutFile $file -UseBasicParsing
            Invoke-WebRequest -Uri $sumAsset.browser_download_url -OutFile $sums -UseBasicParsing
        } catch {
            & $fail "The download failed: $($_.Exception.Message)"
        } finally {
            $ProgressPreference = $progress
        }
        $want = $null
        foreach ($line in (Get-Content -LiteralPath $sums)) {
            if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$' -and $Matches[2] -eq $asset) {
                $want = $Matches[1].ToLowerInvariant()
                break
            }
        }
        if (-not $want) { & $fail "SHA256SUMS.txt names no $asset" }
        $have = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($have -ne $want) { & $fail "The download does not match its SHA-256 - it was deleted, not run. (got $have, want $want)" }
        & $say "SHA-256 checked: $have"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        try {
            Copy-Item -LiteralPath $file -Destination $exe -Force
        } catch {
            & $fail 'MeshChat is open and holds its program - close the chat (ctrl-c) and run this again.'
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    # meshchat in every new terminal: the folder in your PATH (yours only) - and in this window too
    if (-not $hasDir) {
        & $setPath @($parts + $dir)
        & $note "Added to your PATH: $dir"
    }
    if (-not (($env:Path -split ';') -contains $dir)) { $env:Path = "$env:Path;$dir" }
    # and in the Start menu
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($link)
        $shortcut.TargetPath = $exe
        $shortcut.WorkingDirectory = $dir
        $shortcut.Description = 'MeshChat - one chat with everyone nearby over Bluetooth'
        $shortcut.Save()
    } catch {
        & $note "No Start menu entry: $($_.Exception.Message)"
    }
    & $say ("MeshChat {0} is installed: {1}" -f ($release.tag_name -replace '^meshchat-windows-v', ''), $exe)
    & $say 'Type  meshchat  here or in a new terminal window - or Start > MeshChat. To try it first:  meshchat demo'
}

Install-MeshChat
