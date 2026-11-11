# /minecraft and /mc on Windows – the Minecraft server setup assistant, a port of lib/cmd/minecraft.zsh. Server files
# come only from the official sources: Mojang (Vanilla) and PaperMC (Paper), each checked against its checksum. Java
# comes from what is installed, or – after a yes – from Eclipse Temurin (adoptium.net), into Lotus' own folder: no
# administrator rights, its SHA-256 checked before anything is unpacked. A server runs in its control center
# (Public/mcc.ps1): /mc <name> opens it directly.
# A server is a folder in %USERPROFILE%\Minecraft (or LOTUS_MC_HOME) with server.jar, eula.txt, server.properties and
# start.cmd – double-click start.cmd to run it in a window of its own, or open it in Lotus.

Import-LotusCommand mcc

function script:Invoke-Lotusminecraft {
    param([string]$Cmd, [string[]]$Rest)
    Import-LotusLangGroup mc
    $mcHome = Get-LotusMcHome
    # /mc <name>: straight into that server's control center
    $name = $Rest -join ' '
    if ($name -and $name -match '^[A-Za-z0-9._ -]+$' -and $name -notlike '*..*' -and (Test-Path -LiteralPath (Join-Path (Join-Path $mcHome $name) 'start.cmd') -PathType Leaf)) {
        return Invoke-LotusMcc (Join-Path $mcHome $name)
    }
    if ($name -and $name -cnotin 'new', 'open', 'guide', 'delete') { Write-LotusWarn "There is no server called $name in $(Format-LotusHomePath $mcHome)." }
    Write-LotusHeader 'Minecraft' 'server assistant'
    $pick = switch -CaseSensitive ($name) { 'new' { 1 } 'open' { 2 } 'guide' { 3 } 'delete' { 4 } default { $null } }
    if (-not $pick) { $pick = Read-LotusChoice 'What do you want to do?' @('Set up a new server', 'Open a server – control center', 'Port forwarding and firewall guide', 'Delete a server', 'Cancel') }
    switch ($pick) {
        1 { return New-LotusMcServer }
        2 { $dir = Select-LotusMcServer 'Which server?'; if ($dir) { return Invoke-LotusMcc $dir }; return (St 0) }
        3 { Show-LotusMcGuide; return (St 0) }
        4 { $dir = Select-LotusMcServer 'Which server should be deleted?'; if ($dir) { return Remove-LotusMcServer $dir }; return (St 0) }
    }
    St 0
}

function script:Write-LotusMcStep {
    param([int]$N, [string]$Title)
    Write-LotusBlank
    Write-LotusLine "  $(E dim)$N/8$($script:R)  $($script:B)$Title$($script:R)"
}

# JSON from the internet (Mojang, PaperMC, Adoptium) → the object, or $null
function script:Get-LotusMcJson {
    param([string]$Url)
    try { Invoke-RestMethod -Uri $Url -TimeoutSec 15 -UserAgent "lotus/$(Get-LotusVersion) (minecraft setup)" -ErrorAction Stop } catch { Write-LotusLog DEBUG minecraft "No answer from ${Url}: $($_.Exception.Message)"; $null }
}

function script:New-LotusMcServer {
    # 1. type
    Write-LotusMcStep 1 'Server type'
    $t = Read-LotusChoice '' @('Vanilla – the official Minecraft server', 'Paper – faster, supports plugins')
    if (-not $t) { return (St 0) }
    $type = if ($t -eq 1) { 'vanilla' } else { 'paper' }

    # 2. version
    Write-LotusMcStep 2 'Minecraft version'
    Write-LotusStep 'Asking Mojang for the versions …'
    $manifest = Get-LotusMcJson 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
    if (-not $manifest) { Write-LotusError 'No internet connection' 'Lotus could not reach Mojang.'; return (St 1) }
    $latest = [string]$manifest.latest.release
    $version = Read-LotusInput 'Version' $latest
    if (-not $version) { return (St 1) }
    $version = $version.Trim()
    $entry = @($manifest.versions) | Where-Object { $_.id -ceq $version -and $_.type -ceq 'release' } | Select-Object -First 1
    if (-not $entry) { Write-LotusError 'Unknown version' $version @("Latest release: $latest"); return (St 1) }
    $vjson = Get-LotusMcJson ([string]$entry.url)
    $need = if ($vjson -and $vjson.javaVersion.majorVersion) { [int]$vjson.javaVersion.majorVersion } else { 21 }

    # 3. Java
    Write-LotusMcStep 3 "Java $need"
    $javaHome = Find-LotusJava $need
    if (-not $javaHome) {
        Write-LotusWarn "Minecraft $version needs Java $need or newer – it is not installed."
        if (-not (Install-LotusMcJava $need)) { return (St 1) }
        $javaHome = Find-LotusJava $need
        if (-not $javaHome) { Write-LotusError 'Java is still missing' '' @('Open a new terminal window and try again.'); return (St 1) }
    }
    Write-LotusSuccess "Java: $(Get-LotusJavaLabel $javaHome)"

    # 4. folder
    Write-LotusMcStep 4 'Folder'
    $n = Read-LotusInput 'Server name' "$type-$version"
    if (-not $n) { return (St 1) }
    $name = ($n.Trim() -replace '[^A-Za-z0-9._-]', '-').Trim('.')
    if (-not $name) { $name = "$type-$version" }
    $dir = Join-Path (Get-LotusMcHome) $name
    if (Test-Path -LiteralPath $dir) {
        Write-LotusWarn "$(Format-LotusHomePath $dir) already exists."
        if (-not (Read-LotusConfirm 'Use it anyway (files with the same name are replaced)?' 'n')) { return (St 0) }
    }
    New-LotusDir $dir | Out-Null

    # 5. memory
    Write-LotusMcStep 5 'Memory (RAM)'
    $total = [Math]::Truncate((Get-LotusMemBytes) / 1GB)
    $opts = @(foreach ($g in 2, 4, 6, 8, 12) { if ($g -le $total / 2) { "$g GB" } })
    if (-not $opts.Count) { $opts = @('2 GB') }
    Write-LotusDim "Your PC has $total GB. Keep at least half for Windows. 4 GB is plenty for a few friends."
    $r = Read-LotusChoice '' $opts
    if (-not $r) { return (St 0) }
    $ram = ($opts[$r - 1] -replace ' GB', '') + 'G'

    # 6. download
    Write-LotusMcStep 6 'Download'
    if (-not (Save-LotusMcServerJar $dir $type $version $vjson)) { return (St 1) }

    # 7. EULA + basic settings
    Write-LotusMcStep 7 'Minecraft EULA and settings'
    Write-LotusText 'Running a server requires accepting the Minecraft End User License Agreement:'
    Write-LotusDim 'https://aka.ms/MinecraftEULA'
    $eula = Read-LotusConfirm 'Do you accept the EULA?' 'n'
    if (-not $eula) { Write-LotusWarn "The server will not start until you set eula=true in $(Format-LotusHomePath (Join-Path $dir 'eula.txt'))" }
    $motd = Read-LotusInput 'Server name in the list (MOTD)' 'A Lotus Minecraft server'
    if ($null -eq $motd) { return (St 1) }
    $p = Read-LotusInput 'Max players' '10'
    if ($null -eq $p) { return (St 1) }
    $players = Get-LotusInt ($p -replace '[^0-9]', '') 10
    if ($players -lt 1) { $players = 10 }
    $diffs = @('peaceful', 'easy', 'normal', 'hard')
    $d = Read-LotusChoice 'Difficulty' $diffs
    if (-not $d) { return (St 0) }

    # 8. start script
    Write-LotusMcStep 8 'Start script'
    Write-LotusMcServerFiles $dir $type $version $javaHome $ram $eula $motd $players $diffs[$d - 1]
    Write-LotusSuccess "Server ready in $(Format-LotusHomePath $dir)"
    Write-LotusBlank
    $lan = Get-LotusLanIp
    Write-LotusCard 'How to join' @('THIS PC|localhost', "SAME NETWORK|$(if ($lan) { "$($lan):25565" } else { "this PC's IP:25565" })", 'INTERNET|needs port forwarding (guide: /minecraft → 3)')
    Write-LotusBlank
    Write-LotusDim "Next time: /mc $name opens its control center."
    Write-LotusBlank
    if (Read-LotusConfirm 'Start the server now?' 'y') { return Invoke-LotusMcc $dir }
    St 0
}

# The server itself, from Mojang (Vanilla: the server of the version's own JSON, with its SHA-1) or PaperMC (the latest
# build of the version, with its SHA-256) → $true when server.jar is there and its checksum matched
function script:Save-LotusMcServerJar {
    param([string]$Dir, [string]$Type, [string]$Version, $VersionJson)
    $algo = 'SHA1'
    if ($Type -ceq 'vanilla') { $url = [string]$VersionJson.downloads.server.url; $sum = [string]$VersionJson.downloads.server.sha1 }
    else {
        $build = Get-LotusMcJson "https://fill.papermc.io/v3/projects/paper/versions/$Version/builds/latest"
        $dl = if ($build) { $build.downloads.'server:default' } else { $null }
        $url = [string]$dl.url; $sum = [string]$dl.checksums.sha256; $algo = 'SHA256'
    }
    if (-not $url) { Write-LotusError "No $Type server for $Version yet" '' @('Try another version or Vanilla.'); return $false }
    Write-LotusDim "From: $(([Uri]$url).Host)"
    $part = Join-Path $Dir 'server.jar.part'
    $curl = Find-LotusProgram @('curl')
    $ok = if ($curl) { (Invoke-LotusInTheOpen $curl @('-fL', '--progress-bar', '-o', $part, $url)) -eq 0 } else { try { Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -ErrorAction Stop; $true } catch { $false } }
    if (-not $ok) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue; Write-LotusError 'Download failed'; return $false }
    if ($sum) {
        $got = (Get-FileHash -LiteralPath $part -Algorithm $algo).Hash.ToLowerInvariant()
        if ($got -cne $sum.ToLowerInvariant()) { Remove-Item -LiteralPath $part -Force; Write-LotusError 'Checksum mismatch' 'The download was damaged or changed.' @('Nothing was installed. Try again.'); return $false }
        Write-LotusSuccess 'Checksum verified'
    }
    Move-Item -LiteralPath $part -Destination (Join-Path $Dir 'server.jar') -Force
    $true
}

# eula.txt, server.properties, start.cmd and .lotus\server.conf of a new server
function script:Write-LotusMcServerFiles {
    param([string]$Dir, [string]$Type, [string]$Version, [string]$JavaHome, [string]$Ram, [bool]$Eula, [string]$Motd, [int]$Players, [string]$Difficulty)
    Write-LotusFile (Join-Path $Dir 'eula.txt') "eula=$(if ($Eula) { 'true' } else { 'false' })`n"
    $Motd = $Motd -replace '[\p{Cc}]', ''
    Write-LotusFile (Join-Path $Dir 'server.properties') "# Created by Lotus – the server adds all other settings on first start`nmotd=$(ConvertTo-LotusPropValue $Motd)`nmax-players=$Players`ndifficulty=$Difficulty`nserver-port=25565`nonline-mode=true`nwhite-list=false`n"
    $name = Split-Path -Leaf $Dir
    $java = Join-Path $JavaHome $(if ($IsWindows) { 'bin\java.exe' } else { 'bin/java' })
    Write-LotusFile (Join-Path $Dir 'start.cmd') ("@echo off`r`nrem Made by Lotus. Double-click to start the server in a window of its own, or open it with: /mc $name`r`n" +
        "rem Stop it by typing: stop`r`ncd /d `"%~dp0`"`r`n`"$java`" -Xms$Ram -Xmx$Ram -jar `"%~dp0server.jar`" nogui`r`nif errorlevel 1 pause`r`n")
    New-LotusDir (Join-Path $Dir '.lotus') | Out-Null
    Write-LotusFile (Join-Path $Dir '.lotus/server.conf') "type=$Type`nversion=$Version`n"
    Write-LotusLog INFO minecraft "Server made: $name ($Type $Version, $Ram)"
}

# Picks one of the servers; the ones running are marked → its folder, or $null
function script:Select-LotusMcServer {
    param([string]$Title)
    $mcHome = Get-LotusMcHome
    $servers = @(Get-ChildItem -LiteralPath $mcHome -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'start.cmd') -PathType Leaf } | Sort-Object Name)
    if (-not $servers.Count) { Write-LotusError 'No server found' "Lotus looks in $(Format-LotusHomePath $mcHome)" @('Set one up first: /minecraft → 1'); return $null }
    $running = Get-LotusMcRunning
    $labels = @(foreach ($s in $servers) { if ($running.Contains($s.FullName)) { "$($s.Name)  $(E key)● running$($script:R)" } else { $s.Name } })
    $r = Read-LotusChoice $Title $labels
    if (-not $r) { return $null }
    $servers[$r - 1].FullName
}

# The server folders whose server runs: by the runner's pid files, or a java whose command line names its server.jar
function script:Get-LotusMcRunning {
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $javas = @()
    if ($IsWindows) { try { $javas = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop | ForEach-Object { ([string]$_.CommandLine).ToLowerInvariant() }) } catch { } }
    foreach ($s in @(Get-ChildItem -LiteralPath (Get-LotusMcHome) -Directory -ErrorAction SilentlyContinue)) {
        $pidf = Get-LotusInt (Read-LotusFile (Join-Path $s.FullName '.lotus/pid')) 0
        $jar = (Join-Path $s.FullName 'server.jar').ToLowerInvariant()
        if ((Test-LotusMccProc $pidf @('java', 'javaw')) -or @($javas | Where-Object { $_.Contains($jar) }).Count) { [void]$set.Add($s.FullName) }
    }
    , $set
}

function script:Show-LotusMcGuide {
    $lan = Get-LotusLanIp
    Write-LotusHeader 'Minecraft' 'port forwarding guide'
    Write-LotusCategory '1  Play on the same network'
    Write-LotusText "Friends on your network join with:  $(if ($lan) { $lan } else { "<your PC's IP>" }):25565"
    Write-LotusDim 'Find the IP any time in Settings → Network & internet → the network → Properties (IPv4 address).'
    Write-LotusBlank
    Write-LotusCategory '2  Allow the firewall'
    Write-LotusText 'When the server starts, Windows Defender Firewall may ask whether Java may communicate on networks.'
    Write-LotusText 'Allow it on private networks. To check: Windows Security → Firewall & network protection → Allow an app through firewall.'
    Write-LotusBlank
    Write-LotusCategory '3  Play over the internet (port forwarding)'
    Write-LotusText 'a) Give your PC a fixed IP in the router (DHCP reservation).'
    Write-LotusText "b) In the router, forward TCP port 25565 to $(if ($lan) { $lan } else { "your PC's IP" })."
    Write-LotusText "c) Friends join with your public IP – your router's status page shows it."
    Write-LotusDim '   Share it only with people you trust. Lotus does not look it up or store it.'
    Write-LotusBlank
    Write-LotusCategory '4  Safer alternatives'
    Write-LotusText 'Turn on white-list=true in server.properties and add friends with: whitelist add <name>'
    Write-LotusText 'Tools like Tailscale let friends join without opening router ports.'
    Write-LotusBlank
    Write-LotusDim "Full tutorial: $($script:P['website'])minecraft.html"
    Write-LotusBlank
}

# ── Java ──────────────────────────────────────────────────────

# The major version of a Java home, from its release file (no Java started for that) → 0 when it is none
function script:Get-LotusJavaMajor {
    param([string]$JavaHome)
    $exe = Join-Path $JavaHome $(if ($IsWindows) { 'bin\java.exe' } else { 'bin/java' })
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return 0 }
    $rel = Read-LotusFile (Join-Path $JavaHome 'release')
    $v = ''
    if ($rel -and $rel -match 'JAVA_VERSION="([^"]+)"') { $v = $Matches[1] }
    else {
        $out = (& $exe -version 2>&1 | Select-Object -First 1) -join ''
        if ($out -match '"([^"]+)"') { $v = $Matches[1] }
    }
    if ($v -match '^1\.(\d+)') { return [int]$Matches[1] }      # 1.8.0 means Java 8
    if ($v -match '^(\d+)') { return [int]$Matches[1] }
    0
}

# A Java home for at least <major> → its folder, or $null. JAVA_HOME, the java of the PATH, the usual folders of the
# JDK builds (Temurin, Oracle, Microsoft, Zulu, Corretto, Liberica) and Lotus' own; JAVA_HOME first when it fits, else
# the newest.
function script:Find-LotusJava {
    param([int]$Need)
    $homes = [System.Collections.Generic.List[string]]::new()
    if ($env:JAVA_HOME) { $homes.Add($env:JAVA_HOME) }
    foreach ($c in @(Get-Command java -CommandType Application -All -ErrorAction SilentlyContinue)) { $homes.Add((Split-Path -Parent (Split-Path -Parent $c.Source))) }
    $dirs = [System.Collections.Generic.List[string]]::new()
    if ($IsWindows) {
        foreach ($pf in @($env:ProgramFiles, $env:LOCALAPPDATA + '\Programs')) {
            if (-not $pf) { continue }
            foreach ($v in 'Eclipse Adoptium', 'Java', 'Microsoft', 'Zulu', 'Amazon Corretto', 'BellSoft', 'OpenJDK', 'Semeru') { $dirs.Add((Join-Path $pf $v)) }
        }
    } else { foreach ($d in '/usr/lib/jvm', '/usr/lib64/jvm', '/opt/java') { $dirs.Add($d) } }
    $dirs.Add((Join-Path $script:Paths.Data 'java'))
    foreach ($d in $dirs) { foreach ($x in @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue)) { $homes.Add($x.FullName) } }
    $ok = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($h in $homes) {
        try { $full = [IO.Path]::GetFullPath($h).TrimEnd('\', '/') } catch { continue }
        if ($seen[$full.ToLowerInvariant()]) { continue }
        $seen[$full.ToLowerInvariant()] = $true
        $major = Get-LotusJavaMajor $full
        if ($major -ge $Need) { $ok.Add([pscustomobject]@{ Major = $major; Home = $full }) }
    }
    if (-not $ok.Count) { return $null }
    if ($env:JAVA_HOME -and [string]::Equals($ok[0].Home, [IO.Path]::GetFullPath($env:JAVA_HOME).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { return $ok[0].Home }
    ($ok | Sort-Object Major -Descending | Select-Object -First 1).Home
}

# "Java 21.0.4 (~\AppData\…)" for a message
function script:Get-LotusJavaLabel {
    param([string]$JavaHome)
    $rel = Read-LotusFile (Join-Path $JavaHome 'release')
    if ($rel -and $rel -match 'JAVA_VERSION="([^"]+)"') { return "Java $($Matches[1]) ($(Format-LotusHomePath $JavaHome))" }
    Format-LotusHomePath $JavaHome
}

# Java for the server: Eclipse Temurin (free, open source) from adoptium.net into Lotus' own folder – no administrator
# rights; the checksum from the same API is checked before anything is unpacked → $true when it is there
function script:Install-LotusMcJava {
    param([int]$Major)
    Write-LotusDim "Lotus can download Eclipse Temurin $Major (free, open source) from adoptium.net into its own folder – no administrator rights."
    if (-not (Read-LotusConfirm "Download Java $Major for Lotus?" 'y')) { Write-LotusInfo "Install Java $Major later and run /minecraft again."; return $false }
    Save-LotusJava $Major
}

function script:Save-LotusJava {
    param([int]$Major)
    $arch = if ($script:Os.Arch -eq 'arm64') { 'aarch64' } else { 'x64' }
    $os = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'mac' } else { 'linux' }
    Write-LotusStep "Looking up Eclipse Temurin $Major …"
    $list = Get-LotusMcJson "https://api.adoptium.net/v3/assets/latest/$Major/hotspot?architecture=$arch&image_type=jdk&os=$os&vendor=eclipse"
    $pkg = if ($list) { @($list)[0].binary.package } else { $null }
    if (-not $pkg -or -not $pkg.link) { Write-LotusError "Temurin $Major was not found for this system" "adoptium.net did not list a build for $os/$arch." @("winget install Microsoft.OpenJDK.$Major"); return $false }
    $url = [string]$pkg.link; $want = [string]$pkg.checksum; $size = [long]$pkg.size
    $ext = if ($IsWindows) { '.zip' } else { '.tar.gz' }
    if (-not $url.StartsWith('https://github.com/adoptium/') -or -not $url.EndsWith($ext) -or $want -notmatch '^[0-9a-f]{64}$') { Write-LotusError 'Unexpected answer from adoptium.net' $url; return $false }
    $javaDir = Join-Path $script:Paths.Data 'java'
    New-LotusDir $javaDir | Out-Null; New-LotusDir $script:Paths.Cache | Out-Null
    $tmp = Join-Path $script:Paths.Cache "java-$Major$ext"
    Write-LotusDim "From: github.com/adoptium · $([Math]::Truncate($size / 1MB)) MB"
    $curl = Find-LotusProgram @('curl')
    $ok = if ($curl) { (Invoke-LotusInTheOpen $curl @('-fL', '--progress-bar', '-o', $tmp, $url)) -eq 0 } else { try { Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop; $true } catch { $false } }
    if (-not $ok) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; Write-LotusError 'The download failed'; return $false }
    if ((Get-LotusSha256 $tmp) -cne $want) { Remove-Item -LiteralPath $tmp -Force; Write-LotusError 'Checksum mismatch' 'The download was damaged or changed.' @('Nothing was installed.'); return $false }
    Write-LotusSuccess 'Checksum verified'
    $dest = Join-Path $javaDir ([string]$Major)
    $unpack = Join-Path $script:Paths.Cache "java-$Major-unpack"
    Remove-Item -LiteralPath $dest, $unpack -Recurse -Force -ErrorAction SilentlyContinue
    try {
        if ($IsWindows) { Expand-Archive -LiteralPath $tmp -DestinationPath $unpack -Force -ErrorAction Stop }
        else { New-LotusDir $unpack | Out-Null; & tar -xzf $tmp -C $unpack; if ($LASTEXITCODE) { throw 'tar failed' } }
        # (the archive holds one folder: jdk-21.0.4+7)
        $inner = @(Get-ChildItem -LiteralPath $unpack -Directory)
        $src = if ($inner.Count -eq 1) { $inner[0].FullName } else { $unpack }
        Move-Item -LiteralPath $src -Destination $dest -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $dest, $unpack, $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-LotusError 'The download could not be unpacked' $_.Exception.Message
        return $false
    }
    Remove-Item -LiteralPath $unpack, $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Get-LotusJavaMajor $dest)) { Write-LotusError 'Java is not in the download'; return $false }
    Write-LotusLog INFO java "Temurin $Major in $(Format-LotusHomePath $dest)"
    Write-LotusSuccess "Java $Major is ready in $(Format-LotusHomePath $dest)"
    $true
}
