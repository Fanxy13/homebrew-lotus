# The album cover on real Windows (the job "Album cover on real Windows" of windows.yml): a player shows a song with a cover
# in Windows' media controls (fixtures/fake-player.ps1), Lotus asks for it, decodes the picture with Windows' own image
# component and draws it – and the four colors of the cover are where they were. Status 1 when something does not hold.
#   pwsh win/tests/cover-real.ps1
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) "lotus-cover-real-$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$env:LOTUS_ROOT = $repo
$env:LOTUS_CONF = "$tmp\conf"; $env:LOTUS_CACHE = "$tmp\cache"; $env:LOTUS_DATA = "$tmp\data"; $env:LOTUS_STATE = "$tmp\state"
$failed = [System.Collections.Generic.List[string]]::new()
function Check { param([bool]$Ok, [string]$What) Write-Host ($(if ($Ok) { '  ok    ' } else { '  FAIL  ' }) + $What); if (-not $Ok) { $failed.Add($What) } }
Import-Module (Join-Path $repo 'win/Lotus.psd1') -Force
$mod = Get-Module Lotus
lotus settings set LOTUS_CONFIGURED 1 | Out-Null
lotus settings set LOTUS_LOG_LEVEL debug | Out-Null

# the cover: four colors in four quarters, 300 × 300
Add-Type -AssemblyName System.Drawing
$cover = Join-Path $tmp 'cover.png'
$img = [System.Drawing.Bitmap]::new(300, 300)
$g = [System.Drawing.Graphics]::FromImage($img)
$g.FillRectangle([System.Drawing.Brushes]::Red, 0, 0, 150, 150); $g.FillRectangle([System.Drawing.Brushes]::Lime, 150, 0, 150, 150)
$g.FillRectangle([System.Drawing.Brushes]::Blue, 0, 150, 150, 150); $g.FillRectangle([System.Drawing.Brushes]::Yellow, 150, 150, 150, 150)
$g.Dispose(); $img.Save($cover, [System.Drawing.Imaging.ImageFormat]::Png); $img.Dispose()
# a second of silence, for the player that plays a file
$wav = Join-Path $tmp 'silence.wav'
$pcm = [byte[]]::new(16000 * 2 * 2)
$ms = [IO.MemoryStream]::new(); $w = [IO.BinaryWriter]::new($ms)
$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([uint32](36 + $pcm.Length)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $w.Write([uint32]16)
$w.Write([uint16]1); $w.Write([uint16]1); $w.Write([uint32]16000); $w.Write([uint32]32000); $w.Write([uint16]2); $w.Write([uint16]16)
$w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([uint32]$pcm.Length); $w.Write($pcm); $w.Flush()
[IO.File]::WriteAllBytes($wav, $ms.ToArray())

$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$asked = {
    param($out) & $mod { param($o) Get-LotusMediaCover $o } $out
}
$player = $null
$found = $null
foreach ($mode in 'manual', 'source') {
    $log = Join-Path $tmp "player-$mode.log"
    Write-Host "A player in the mode '$mode' …"
    $player = Start-Process -FilePath $ps51 -ArgumentList @('-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'fixtures/fake-player.ps1'), '-Cover', $cover, '-Wav', $wav, '-Mode', $mode, '-Seconds', '240') -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -PassThru
    $deadline = [datetime]::UtcNow.AddSeconds(40)
    while ([datetime]::UtcNow -lt $deadline -and -not $player.HasExited -and -not ((Test-Path $log) -and (Get-Content $log -Raw -ErrorAction SilentlyContinue) -match 'ready')) { Start-Sleep -Milliseconds 500 }
    "  player says: $((Get-Content $log -ErrorAction SilentlyContinue) -join ' | ')"
    $e = Get-Content "$log.err" -ErrorAction SilentlyContinue
    if ($e) { "  player errors: $($e -join ' | ')" }
    for ($i = 1; $i -le 10 -and -not $found; $i++) {
        $out = Join-Path $tmp "asked-$mode-$i.img"
        $r = & $asked $out
        "  attempt ${i}: $(if ($r) { "$($r.Status) / $($r.Title) / $($r.Artist) / $($r.Album) / cover=$($r.HasCover) ($($r.Detail))" } else { 'no session' })"
        if ($r -and $r.Title -eq 'Lotus Test Song') { $found = [pscustomobject]@{ Mode = $mode; Result = $r; File = $out } }
        elseif (-not $r) { Start-Sleep -Seconds 2 }
    }
    if ($found) { break }
    try { $player.Kill($true) } catch { }
}
if (-not $found) {
    Write-Host "::warning::No media session could be made on this runner: the cover was not checked against Windows' real media controls"
    Check $false 'a player shows up in Windows'' media controls'
    Get-Content (Join-Path $env:LOTUS_STATE 'lotus.log') -Tail 30 -ErrorAction SilentlyContinue
    exit 1
}
$r = $found.Result
Check ($r.Status -eq 'Playing') "the session is Playing ($($r.Status)), made in the mode '$($found.Mode)'"
Check ($r.Title -eq 'Lotus Test Song' -and $r.Artist -eq 'Lotus Test Artist' -and $r.Album -eq 'Lotus Test Album') "title, artist and album arrive whole: $($r.Title) / $($r.Artist) / $($r.Album)"
Check $r.HasCover 'the session has a cover'
$bytes = [IO.File]::ReadAllBytes($found.File)
$kind = & $mod { param($b) Get-LotusPictureKind $b } $bytes
Write-Host "  the picture Windows hands out: $($bytes.Length) bytes, $kind"
Check ($kind -in 'png', 'jpeg', 'bmp', 'gif') 'it is a picture Lotus opens'

# decoded and drawn: the four colors are where they were
$art = & $mod { param($song) Initialize-Lotus; $script:NpOn = $true; Get-LotusCover 40 20 $song } '♫ Lotus Test Song — Lotus Test Artist'
Check ($null -ne $art) 'Lotus draws the cover'
if ($art) {
    Write-Host "  drawn: $($art.Width) × $($art.Height) in $($art.File)"
    $lines = ([IO.File]::ReadAllText($art.File)).TrimEnd("`n") -split "`n"
    Check ($art.Width -eq 40 -and $art.Height -eq 20) 'a square cover is as tall as half its width'
    $rgb = { param($line, $left) $m = [regex]::Matches($line, '\x1b\[(?:[0-9;]*;)?38;2;(\d+);(\d+);(\d+)'); $x = if ($left) { $m[2] } else { $m[$m.Count - 3] }; @([int]$x.Groups[1].Value, [int]$x.Groups[2].Value, [int]$x.Groups[3].Value) }
    $tl = & $rgb $lines[0] $true; $tr = & $rgb $lines[0] $false; $bl = & $rgb $lines[-1] $true; $br = & $rgb $lines[-1] $false
    Write-Host "  corners: top left $($tl -join ','), top right $($tr -join ','), bottom left $($bl -join ','), bottom right $($br -join ',')"
    Check ($tl[0] -gt 200 -and $tl[1] -lt 60 -and $tl[2] -lt 60) 'red at the top left'
    Check ($tr[1] -gt 200 -and $tr[0] -lt 60 -and $tr[2] -lt 60) 'green at the top right'
    Check ($bl[2] -gt 200 -and $bl[0] -lt 60 -and $bl[1] -lt 60) 'blue at the bottom left'
    Check ($br[0] -gt 200 -and $br[1] -gt 200 -and $br[2] -lt 60) 'yellow at the bottom right'
}
try { $player.Kill($true) } catch { }
if ($failed.Count) { Write-Host "`n$($failed.Count) failed"; Get-Content (Join-Path $env:LOTUS_STATE 'lotus.log') -Tail 30 -ErrorAction SilentlyContinue; exit 1 }
Write-Host "`nall held"
