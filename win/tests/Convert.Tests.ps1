# /convert on Windows (Public/convert.ps1): the questions, yt-dlp's first look, the download with its progress lines, the
# file it reports, the reasons a download fails – against small stand-ins for yt-dlp, ffmpeg and ffprobe (fixtures/
# fake-tools, Python scripts; they run as programs where a script with #! can, so not on Windows itself).

BeforeDiscovery {
    $script:CanFake = -not $IsWindows -and [bool](Get-Command python3 -CommandType Application -ErrorAction SilentlyContinue)
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-convert'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    InModuleScope Lotus { Initialize-Lotus; Import-LotusCommand convert }
    $env:LOTUS_DOWNLOADS = Join-Path $script:Ctx.Tmp 'Downloads'
    $script:Log = Join-Path $script:Ctx.Tmp 'yt-dlp.log'
    $env:FAKE_YTDLP_LOG = $script:Log
    function Get-Plain { param([string]$Text) $Text -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '' }
}

AfterAll {
    Remove-Item Env:FAKE_YTDLP_LOG -ErrorAction SilentlyContinue
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'what a failure means' {
    It 'a private video ends it, a site that changed offers a newer yt-dlp, anything else is tried once more' {
        InModuleScope Lotus {
            $tools = [pscustomobject]@{ Ytdlp = 'yt-dlp-that-is-not-there' }
            $script:ConvertPause = 0
            Test-LotusConvertRetry $tools @('ERROR: [youtube] x: Private video. Sign in') 1 'check' 6>$null | Should -BeFalse
            Test-LotusConvertRetry $tools @('ERROR: Unsupported URL: https://example.com') 1 'check' 6>$null | Should -BeFalse
            Test-LotusConvertRetry $tools @('ERROR: unable to download video data: HTTP Error 500') 1 'download' 6>$null | Should -BeTrue
            Test-LotusConvertRetry $tools @('ERROR: unable to download video data: HTTP Error 500') 2 'download' 6>$null | Should -BeFalse
            $script:ConvertPause = 2
        }
    }
    It 'without yt-dlp and ffmpeg: the winget commands' {
        $out = InModuleScope Lotus {
            $real = (Get-Item function:Find-LotusConvertTool).ScriptBlock
            Set-Item function:script:Find-LotusConvertTool { param($Name) $null }
            try { Get-LotusConvertTools } finally { Set-Item function:script:Find-LotusConvertTool $real }
        } 6>&1 | Out-String
        $out | Should -Match 'Missing tools: yt-dlp, ffmpeg'
        $out | Should -Match 'winget install --id yt-dlp.yt-dlp -e'
        $out | Should -Match 'winget install --id Gyan.FFmpeg -e'
    }
    It 'a link that is none' {
        lotus convert 'not a link' 6>&1 | Out-String | Should -Match 'not a valid link'
    }
}

Describe 'a download' -Skip:(-not $script:CanFake) {
    BeforeAll {
        $script:OldPath = $env:PATH
        $env:PATH = "$(Join-Path $PSScriptRoot 'fixtures/fake-tools')$([IO.Path]::PathSeparator)$env:PATH"
        # the newest yt-dlp is the one there (no question about an update, no call to GitHub)
        InModuleScope Lotus { Write-LotusFile (Join-Path $script:Paths.Cache 'ytdlp-latest') "2026.10.01`n" }
    }
    AfterAll { $env:PATH = $script:OldPath }

    It 'MP3: the sound with the progress of yt-dlp, the file where it says' {
        Remove-Item -LiteralPath $script:Log -ErrorAction SilentlyContinue
        $out = Invoke-LotusWithKeys @('1', 'n') { Invoke-Lotusconvert 'convert' @('https://www.youtube.com/watch?v=abc') }
        $plain = Get-Plain $out
        $plain | Should -Match 'Only download videos you have the right to save'
        $plain | Should -Match 'A Test Video'
        $plain | Should -Match 'MP3 · best quality · 3:33 · youtube.com'
        $plain | Should -Match '✓ Downloading the sound'
        $plain | Should -Match '100%|75%'
        $plain | Should -Match 'Done: .*A Test Video\.mp3'
        Test-Path (Join-Path $env:LOTUS_DOWNLOADS 'A Test Video.mp3') | Should -BeTrue
        $calls = @(Get-Content $script:Log)
        $calls[-1] | Should -Match "-x`t--audio-format`tmp3"
        $calls[-1] | Should -Match "--print`tafter_move:filepath"
        $calls[-1] | Should -Match "--`thttps://www.youtube.com/watch\?v=abc$"
    }
    It 'MP4 at 720p: the format of the Mac, and a second file of the same name is kept apart' {
        # MP4 · 720p · the frame rate kept · then no Explorer
        $out = Invoke-LotusWithKeys @('2', '3', '1', 'n') { Invoke-Lotusconvert 'convert' @('https://www.youtube.com/watch?v=abc') }
        $calls = @(Get-Content $script:Log)
        $calls[-1] | Should -Match ([regex]::Escape("bv*[height<=720][ext=mp4]+ba[ext=m4a]/bv*[height<=720]+ba/b[height<=720]/b"))
        $calls[-1] | Should -Match "--merge-output-format`tmp4"
        Test-Path (Join-Path $env:LOTUS_DOWNLOADS 'A Test Video.mp4') | Should -BeTrue
        # … and once more: the file is there – keep both
        $again = Invoke-LotusWithKeys @('2', '3', '1', '1', 'n') { Invoke-Lotusconvert 'convert' @('https://www.youtube.com/watch?v=abc') }
        Get-Plain $again | Should -Match 'already exists'
        Test-Path (Join-Path $env:LOTUS_DOWNLOADS 'A Test Video (2).mp4') | Should -BeTrue
    }
    It 'a private video: what yt-dlp says, and why' {
        $out = Invoke-LotusWithKeys @('1') { Invoke-Lotusconvert 'convert' @('https://www.youtube.com/watch?v=private') }
        $plain = Get-Plain $out
        $plain | Should -Match 'yt-dlp cannot read this link'
        $plain | Should -Match 'Private video'
        $plain | Should -Match 'private, removed, age-restricted'
    }
}
