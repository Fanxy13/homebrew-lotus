# /meshchat – one chat with everyone nearby over Bluetooth, no internet, no server. On Windows it is a program of its own,
# meshchat.exe (win/meshchat): the same protocol as the Macs' MeshChat, byte for byte, in the same chat. Lotus starts it
# with what you typed after /meshchat (demo, doctor, history, nick, relay …), or offers its installer – the one that
# checks the program's SHA-256 against its release before anything runs.

function script:Invoke-Lotusmeshchat {
    param([string]$Cmd, [string[]]$Rest)
    $exe = Find-LotusMeshChat
    if (-not $exe) {
        Write-LotusHero 'MeshChat' 'One chat with everyone nearby over Bluetooth – no internet, no server.'
        if (-not $IsWindows) {
            Write-LotusText 'On a Mac MeshChat comes with Lotus (lotus meshchat in zsh); Linux has none yet.'
            Write-LotusBlank
            return (St 2)
        }
        Write-LotusText 'MeshChat for Windows is a program of its own, meshchat.exe – in the same chat as the Macs.'
        Write-LotusText 'It needs Windows 10 version 2004 or newer and Bluetooth LE.'
        $url = "https://raw.githubusercontent.com/$($script:P['repo'])/main/win/meshchat/install.ps1"
        Write-LotusDim "Its installer: $url"
        Write-LotusDim 'It checks the SHA-256 of meshchat.exe against its release, and puts it into %LOCALAPPDATA%\Programs\MeshChat (no administrator rights).'
        Write-LotusBlank
        if (-not (Test-LotusTty) -or -not (Read-LotusConfirm 'Install MeshChat now?' 'n')) { return (St 1) }
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "meshchat-install-$([guid]::NewGuid().ToString('N')).ps1"
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $rc = Invoke-LotusInTheOpen (Get-Process -Id $PID).Path @('-NoProfile', '-File', $tmp)
        } catch { Write-LotusError 'The download failed' $url; return (St 1) }
        finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        if ($rc -ne 0) { return (St 1) }
        $exe = Find-LotusMeshChat
        if (-not $exe) { Write-LotusError 'MeshChat is not where its installer puts it'; return (St 1) }
    }
    Write-LotusLog INFO meshchat "MeshChat: $exe $($Rest -join ' ')"
    St (Invoke-LotusInTheOpen $exe $Rest)
}

# meshchat.exe: on the PATH, or where its installer puts it
function script:Find-LotusMeshChat {
    $p = Find-LotusProgram @('meshchat')
    if ($p) { return $p }
    if ($IsWindows -and $env:LOCALAPPDATA) {
        $f = Join-Path $env:LOCALAPPDATA 'Programs\MeshChat\meshchat.exe'
        if (Test-Path -LiteralPath $f) { return $f }
    }
    $null
}
