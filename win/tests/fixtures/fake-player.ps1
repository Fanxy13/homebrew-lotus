# A music player for the tests of the album cover, in Windows PowerShell (the Windows Runtime is not in PowerShell 7): it
# shows up in Windows' media controls with a song, an artist, an album and a cover – the way Spotify or a browser does –
# and stays until -Seconds are over. It prints "ready" (and what Windows' media controls list) when it is there.
#   powershell.exe -NoProfile -File fake-player.ps1 -Cover cover.png [-Mode manual|source] [-Wav silence.wav] [-Seconds 120]
# manual: the player fills the media controls itself · source: a MediaPlayer plays a (silent) file and describes it
param(
    [Parameter(Mandatory)][string]$Cover,
    [string]$Mode = 'manual',
    [string]$Wav = '',
    [string]$Title = 'Lotus Test Song',
    [string]$Artist = 'Lotus Test Artist',
    [string]$Album = 'Lotus Test Album',
    [int]$Seconds = 120
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$await = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Wait($op, $type) { $t = $await.MakeGenericMethod($type).Invoke($null, @($op)); if (-not $t.Wait(10000)) { throw 'no answer' }; $t.Result }
foreach ($n in 'Windows.Media.Playback.MediaPlayer', 'Windows.Media.Playback.MediaPlaybackItem', 'Windows.Media.MediaPlaybackType', 'Windows.Media.MediaPlaybackStatus',
    'Windows.Media.Core.MediaSource', 'Windows.Storage.StorageFile', 'Windows.Storage.Streams.RandomAccessStreamReference') {
    $null = Invoke-Expression "[$n, $($n.Substring(0, $n.LastIndexOf('.'))), ContentType = WindowsRuntime]"
}
$file = Wait ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Cover)) ([Windows.Storage.StorageFile])
$thumb = [Windows.Storage.Streams.RandomAccessStreamReference]::CreateFromFile($file)
$player = [Windows.Media.Playback.MediaPlayer]::new()
if ($Mode -eq 'source') {
    $wav = Wait ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Wav)) ([Windows.Storage.StorageFile])
    $item = [Windows.Media.Playback.MediaPlaybackItem]::new([Windows.Media.Core.MediaSource]::CreateFromStorageFile($wav))
    $props = $item.GetDisplayProperties()
    $props.Type = [Windows.Media.MediaPlaybackType]::Music
    $props.MusicProperties.Title = $Title; $props.MusicProperties.Artist = $Artist; $props.MusicProperties.AlbumTitle = $Album
    $props.Thumbnail = $thumb
    $item.ApplyDisplayProperties($props)
    $player.Volume = 0
    $player.Source = $item
    $player.Play()
} else {
    $player.CommandManager.IsEnabled = $false
    $smtc = $player.SystemMediaTransportControls
    $smtc.IsEnabled = $true
    $smtc.IsPlayEnabled = $true
    $smtc.IsPauseEnabled = $true
    $smtc.PlaybackStatus = [Windows.Media.MediaPlaybackStatus]::Playing
    $du = $smtc.DisplayUpdater
    $du.Type = [Windows.Media.MediaPlaybackType]::Music
    $du.MusicProperties.Title = $Title; $du.MusicProperties.Artist = $Artist; $du.MusicProperties.AlbumTitle = $Album
    $du.Thumbnail = $thumb
    $du.Update()
}
# what Windows' media controls list now
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$manager = Wait ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
Start-Sleep -Milliseconds 1500
$sessions = @($manager.GetSessions())
"sessions: $($sessions.Count)" + $(if ($sessions.Count) { ' – ' + (($sessions | ForEach-Object { $_.SourceAppUserModelId }) -join ', ') } else { '' })
'ready'
Start-Sleep -Seconds $Seconds
