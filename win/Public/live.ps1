# /liveserver on Windows – the folder you are in, served to the browser with a reload on every save, like Live Server in
# VS Code: lib/live/liveserver.py, the same server as on the Mac (Python's standard library), run with Python 3.9 or
# newer. On Windows it is for this PC: the phones and computers in the Wi-Fi and their QR code need the Mac's list of its
# networks and are not on Windows yet. It serves nothing outside the folder and no hidden files.
#   /liveserver [<folder|page>] [--port <n>] [--no-open]   ·   /liveserver stop

function script:Invoke-Lotuslive {
    param([string]$Cmd, [string[]]$Rest)
    $py = Find-LotusPython
    if (-not $py) {
        Write-LotusError 'Live Server needs Python 3.9 or newer' 'Python is free; Lotus uses only its standard library.' @(
            'winget install --id Python.Python.3.13 -e   then open a new window')
        return (St 1)
    }
    $data = Join-Path $script:Paths.State 'live'
    New-LotusDir $data | Out-Null
    Write-LotusLog INFO live "liveserver$(if ($Rest.Count) { ' ' + ($Rest -join ' ') })"
    # the folder you are in, Lotus' colors, and where the servers that run leave a note (for stop and /html)
    $vars = @{
        LOTUS_PWD = (Get-Location).ProviderPath; LOTUS_LIVE_DATA = $data
        LOTUS_COLOR_KEY = $script:C['key']; LOTUS_COLOR_ACCENT = $script:C['accent']; LOTUS_COLOR_DIM = $script:C['dim']; LOTUS_COLOR_LOGO = $script:C['logo']
    }
    $server = Join-Path (Get-LotusRoot) 'lib/live/liveserver.py'
    if ($Rest.Count -and $Rest[0] -ceq 'stop') {
        # a short answer: through PowerShell, so that a script can read it too
        $out = Invoke-LotusPythonText $py $server $Rest $vars
        $rc = $LASTEXITCODE
        if ($out) { Write-LotusLine $out }
        return (St $rc)
    }
    St (Invoke-LotusPython $py $server $Rest $vars)
}
