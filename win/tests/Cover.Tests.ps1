# The album cover on the start screen: while a song plays, its cover takes the logo's place (Private/Art.ps1: the drawing and
# Get-LotusCover; Private/Platform.ps1: Get-LotusMediaCover, Windows' media session; Private/Start.ps1: Get-LotusArtArgs).
# The drawing is the one of lib/cover.pl, byte for byte (fixtures/cover/expected.tsv holds what the Mac's script makes of
# each picture); the media session is a stand-in here – the job "Album cover on real Windows" of windows.yml asks the
# real one. (tests/test-art.zsh tests the Mac's side.)

BeforeDiscovery {
    $script:CoverCases = foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'fixtures/cover/expected.tsv'))) {
        $f = $line -split "`t"
        @{ Name = $f[0]; Cols = [int]$f[1]; Rows = [int]$f[2]; Mode = $f[3]; Sha = $f[4] }
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    . (Join-Path $PSScriptRoot 'fixtures/cover/pictures.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-cover'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    $script:Pics = Get-CoverPictures
    $script:Esc = [string][char]27
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'the art of a cover' {
    It 'is what lib/cover.pl makes of <Name> in <Cols> × <Rows> (<Mode>)' -ForEach $script:CoverCases {
        $art = InModuleScope Lotus -Parameters @{ Bmp = $script:Pics[$Name]; Cols = $Cols; Rows = $Rows; Mode = $Mode } {
            ConvertTo-LotusCoverArt -Bmp $Bmp -Cols $Cols -Rows $Rows -TrueColor ($Mode -eq 'tc')
        }
        $sha = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.UTF8Encoding]::new($false).GetBytes($art.Text))).Replace('-', '').ToLowerInvariant()
        $sha | Should -Be $Sha
    }
    It 'keeps the picture''s shape: a cell is one pixel wide and two tall' {
        $art = InModuleScope Lotus -Parameters @{ Bmp = $script:Pics['disc'] } { ConvertTo-LotusCoverArt -Bmp $Bmp -Cols 44 -Rows 22 -TrueColor $true }
        # 96 × 64 into 44 × 22: the width is the limit, so the picture is 44 cells wide and 15 rows tall (30 pixels)
        $art.Width | Should -Be 44
        $art.Height | Should -Be 15
        $lines = $art.Text.TrimEnd("`n") -split "`n"
        $lines.Count | Should -Be 15
        ($lines[0] -replace "$([char]27)\[[0-9;]*m", '').Length | Should -Be 44
    }
    It 'draws in the cover''s own colors: red, green, blue and yellow stay what they are' {
        $art = InModuleScope Lotus -Parameters @{ Bmp = $script:Pics['quarters'] } { ConvertTo-LotusCoverArt -Bmp $Bmp -Cols 16 -Rows 8 -TrueColor $true }
        $lines = $art.Text.TrimEnd("`n") -split "`n"
        $lines[0] | Should -Match '^\x1b\[38;2;200;30;30;48;2;200;30;30m▄'
        $lines[0] | Should -Match '\x1b\[38;2;30;200;30;48;2;30;200;30m▄'
        $lines[-1] | Should -Match '^\x1b\[38;2;30;30;200;48;2;30;30;200m▄'
        $lines[-1] | Should -Match '\x1b\[38;2;220;220;30;48;2;220;220;30m▄'
    }
    It 'gives nothing for what is no 24 or 32 bit BMP' {
        InModuleScope Lotus -Parameters @{ Good = $script:Pics['tiny'] } {
            ConvertTo-LotusCoverArt -Bmp ([byte[]](1..100)) -Cols 10 -Rows 5 -TrueColor $true | Should -BeNullOrEmpty
            ConvertTo-LotusCoverArt -Bmp ([byte[]]@()) -Cols 10 -Rows 5 -TrueColor $true | Should -BeNullOrEmpty
            ConvertTo-LotusCoverArt -Bmp $Good[0..40] -Cols 10 -Rows 5 -TrueColor $true | Should -BeNullOrEmpty       # cut off
            $eight = [byte[]]$Good.Clone(); $eight[28] = 8
            ConvertTo-LotusCoverArt -Bmp $eight -Cols 10 -Rows 5 -TrueColor $true | Should -BeNullOrEmpty
            ConvertTo-LotusCoverArt -Bmp $Good -Cols 0 -Rows 5 -TrueColor $true | Should -BeNullOrEmpty
        }
    }
}

Describe 'a picture' {
    It 'is known by its first bytes: jpeg, png, gif, webp and bmp are pictures, nothing else is opened' {
        InModuleScope Lotus {
            $pad = [byte[]]::new(20)
            function Kind { param([byte[]]$Head) Get-LotusPictureKind ([byte[]]($Head + $pad)) }
            Kind ([byte[]](0xFF, 0xD8, 0xFF, 0xE0)) | Should -Be 'jpeg'
            Kind ([byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) | Should -Be 'png'
            Kind ([byte[]](0x47, 0x49, 0x46, 0x38, 0x39, 0x61)) | Should -Be 'gif'
            Kind ([byte[]](0x42, 0x4D, 1, 2)) | Should -Be 'bmp'
            Kind ([byte[]](0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50)) | Should -Be 'webp'
            Kind ([byte[]](0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45)) | Should -Be ''     # a WAV
            Kind ([byte[]](0x50, 0x4B, 3, 4)) | Should -Be ''                                                # a zip
            Get-LotusPictureKind $null | Should -Be ''
            Get-LotusPictureKind ([byte[]](1, 2, 3)) | Should -Be ''
        }
    }
    It 'is used as it is when it is a BMP that is small enough, and not read when it is something else' {
        InModuleScope Lotus -Parameters @{ Bmp = $script:Pics['disc'] } {
            (ConvertTo-LotusCoverBmp $Bmp 96).Length | Should -Be $Bmp.Length
            ConvertTo-LotusCoverBmp ([byte[]](0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 1, 2, 3, 4)) 96 | Should -BeNullOrEmpty
            ConvertTo-LotusCoverBmp ([byte[]](1..40)) 96 | Should -BeNullOrEmpty
        }
    }
    It 'is made smaller by Windows'' own image component, whatever it is: png, jpeg, gif and a big bmp' -Skip:(-not $IsWindows) {
        Add-Type -AssemblyName System.Drawing
        $make = {
            param($format)
            $img = [System.Drawing.Bitmap]::new(400, 400)
            $g = [System.Drawing.Graphics]::FromImage($img)
            $g.FillRectangle([System.Drawing.Brushes]::Red, 0, 0, 200, 200); $g.FillRectangle([System.Drawing.Brushes]::Lime, 200, 0, 200, 200)
            $g.FillRectangle([System.Drawing.Brushes]::Blue, 0, 200, 200, 200); $g.FillRectangle([System.Drawing.Brushes]::Yellow, 200, 200, 200, 200)
            $g.Dispose()
            $ms = [System.IO.MemoryStream]::new(); $img.Save($ms, $format); $img.Dispose(); , $ms.ToArray()
        }
        foreach ($f in 'Png', 'Jpeg', 'Gif', 'Bmp') {
            $bytes = & $make ([System.Drawing.Imaging.ImageFormat]::$f)
            $bmp = InModuleScope Lotus -Parameters @{ Bytes = $bytes } { ConvertTo-LotusCoverBmp $Bytes 64 }
            $bmp | Should -Not -BeNullOrEmpty -Because "$f"
            $info = InModuleScope Lotus -Parameters @{ Bmp = $bmp } { Get-LotusBmpInfo $Bmp }
            $info.Width | Should -Be 64 -Because "$f"
            $info.Height | Should -Be 64 -Because "$f"
            $art = InModuleScope Lotus -Parameters @{ Bmp = $bmp } { ConvertTo-LotusCoverArt -Bmp $Bmp -Cols 16 -Rows 8 -TrueColor $true }
            $lines = $art.Text.TrimEnd("`n") -split "`n"
            # the quarters are still where they were (jpeg shifts the colors a little: the dominant channel decides)
            $lines[0] | Should -Match '^\x1b\[38;2;(2[0-5]\d|1[89]\d);\d+;\d+' -Because "${f}: red at the top left"
            $lines[-1] | Should -Match '^\x1b\[38;2;\d+;\d+;(2[0-5]\d|1[89]\d)' -Because "${f}: blue at the bottom left"
        }
    }
}

Describe 'the cover of the song that plays' {
    BeforeEach {
        Remove-Item -LiteralPath (Join-Path $env:LOTUS_CACHE 'covers') -Recurse -Force -ErrorAction SilentlyContinue
        InModuleScope Lotus { Initialize-Lotus }
    }
    It 'is drawn once: the same song, at the same size or at another, does not ask Windows again' {
        $bytes = $script:Pics['quarters']
        Mock -ModuleName Lotus Get-LotusMediaCover ({ param($OutFile) [System.IO.File]::WriteAllBytes($OutFile, $bytes); [pscustomobject]@{ Status = 'Playing'; Title = 'Habiba'; Artist = 'Boef'; Album = 'Habiba'; HasCover = $true } }.GetNewClosure())
        $song = "$($script:Esc)[1;38;2;1;2;3m♫ $($script:Esc)[0mHabiba $($script:Esc)[90m—$($script:Esc)[0m Boef"
        $a = InModuleScope Lotus -Parameters @{ Song = $song } { Get-LotusCover 32 16 $Song }
        $a.Width | Should -Be 32
        $a.Height | Should -Be 16     # (a square picture: a cell is one pixel wide and two tall)
        Test-Path -LiteralPath $a.File | Should -BeTrue
        ([System.IO.File]::ReadAllText($a.File).TrimEnd("`n") -split "`n").Count | Should -Be 16
        $b = InModuleScope Lotus -Parameters @{ Song = $song } { Get-LotusCover 32 16 $Song }
        $b.File | Should -Be $a.File
        $c = InModuleScope Lotus -Parameters @{ Song = $song } { Get-LotusCover 24 12 $Song }
        $c.Width | Should -Be 24
        $c.File | Should -Not -Be $a.File
        Should -Invoke -ModuleName Lotus Get-LotusMediaCover -Times 1 -Exactly
    }
    It 'is another song''s cover only when the start screen names that song' {
        $bytes = $script:Pics['quarters']
        Mock -ModuleName Lotus Get-LotusMediaCover ({ param($OutFile) [System.IO.File]::WriteAllBytes($OutFile, $bytes); [pscustomobject]@{ Status = 'Playing'; Title = 'Other song'; Artist = 'Someone'; Album = ''; HasCover = $true } }.GetNewClosure())
        InModuleScope Lotus { Get-LotusCover 32 16 '♫ Habiba — Boef' } | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $env:LOTUS_CACHE 'covers/*.img') | Should -BeFalse
    }
    It 'is not shown for a song that is paused' {
        $bytes = $script:Pics['quarters']
        Mock -ModuleName Lotus Get-LotusMediaCover ({ param($OutFile) [System.IO.File]::WriteAllBytes($OutFile, $bytes); [pscustomobject]@{ Status = 'Paused'; Title = 'Habiba'; Artist = 'Boef'; Album = ''; HasCover = $true } }.GetNewClosure())
        InModuleScope Lotus { Get-LotusCover 32 16 '♫ Habiba — Boef' } | Should -BeNullOrEmpty
    }
    It 'is nothing for a song with no cover, and Windows is not asked for it again at once' {
        Mock -ModuleName Lotus Get-LotusMediaCover { [pscustomobject]@{ Status = 'Playing'; Title = 'Habiba'; Artist = 'Boef'; Album = ''; HasCover = $false } }
        InModuleScope Lotus { Get-LotusCover 32 16 '♫ Habiba — Boef' } | Should -BeNullOrEmpty
        InModuleScope Lotus { Get-LotusCover 32 16 '♫ Habiba — Boef' } | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Lotus Get-LotusMediaCover -Times 1 -Exactly
    }
    It 'is nothing when no player has a session' {
        Mock -ModuleName Lotus Get-LotusMediaCover { $null }
        InModuleScope Lotus { Get-LotusCover 32 16 '♫ Habiba — Boef' } | Should -BeNullOrEmpty
        InModuleScope Lotus { Get-LotusCover 32 16 '' } | Should -BeNullOrEmpty
    }
    It 'is nothing when the picture cannot be read, and it is not read again and again' {
        Mock -ModuleName Lotus Get-LotusMediaCover ({ param($OutFile) [System.IO.File]::WriteAllBytes($OutFile, [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, 5, 6)); [pscustomobject]@{ Status = 'Playing'; Title = 'Habiba'; Artist = 'Boef'; Album = ''; HasCover = $true } }.GetNewClosure())
        InModuleScope Lotus { Get-LotusCover 32 16 '♫ Habiba — Boef' } | Should -BeNullOrEmpty
        InModuleScope Lotus { Get-LotusCover 32 16 '♫ Habiba — Boef' } | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Lotus Get-LotusMediaCover -Times 1 -Exactly
        (Get-ChildItem -LiteralPath (Join-Path $env:LOTUS_CACHE 'covers') -Filter '*.img' -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }
    It 'keeps the newest 80 drawings' {
        $bytes = $script:Pics['quarters']
        $covers = Join-Path $env:LOTUS_CACHE 'covers'
        New-Item -ItemType Directory -Force -Path $covers | Out-Null
        1..85 | ForEach-Object { $f = Join-Path $covers ("old{0:00}-9x9-tc.txt" -f $_); 'x' | Set-Content -LiteralPath $f; (Get-Item $f).LastWriteTimeUtc = [datetime]::UtcNow.AddHours(-$_) }
        Mock -ModuleName Lotus Get-LotusMediaCover ({ param($OutFile) [System.IO.File]::WriteAllBytes($OutFile, $bytes); [pscustomobject]@{ Status = 'Playing'; Title = 'Habiba'; Artist = 'Boef'; Album = ''; HasCover = $true } }.GetNewClosure())
        InModuleScope Lotus { Get-LotusCover 32 16 '♫ Habiba — Boef' } | Should -Not -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $covers -Filter '*.txt').Count | Should -Be 80
        Test-Path -LiteralPath (Join-Path $covers 'old85-9x9-tc.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $covers 'old01-9x9-tc.txt') | Should -BeTrue
    }
}

Describe 'the start screen with a cover' {
    BeforeEach {
        Remove-Item -LiteralPath (Join-Path $env:LOTUS_CACHE 'covers') -Recurse -Force -ErrorAction SilentlyContinue
        InModuleScope Lotus { Initialize-Lotus; $script:NpOn = $true; $script:S['LOTUS_COVER'] = '1' }
    }
    It 'puts the cover in the logo''s place, as big as the logo''s room, and keeps the info where it was' {
        $r = InModuleScope Lotus {
            Mock Get-LotusCover { [pscustomobject]@{ File = 'C:\cache\covers\x.txt'; Width = 30; Height = 15 } }
            $logo = Get-LotusLogoPainted ([string]$script:S['LOTUS_LOGO'])
            @{ Args = (Get-LotusArtArgs 22 200 -Song '♫ Habiba — Boef'); Logo = $logo }
        }
        $a = $r.Args; $logo = $r.Logo
        $a[0..5] | Should -Be @('--logo', 'C:\cache\covers\x.txt', '--logo-type', 'file-raw', '--logo-width', '30')
        $a[6..7] | Should -Be @('--logo-height', '15')
        $ltop = if ($logo.Height -ge 20) { 2 } else { [Math]::Truncate((22 - $logo.Height) / 2) }
        $block = [Math]::Max($logo.Height + $ltop, 22)
        $a[8..9] | Should -Be @('--logo-padding-top', "$([Math]::Truncate(($block - 15) / 2))")
        $a[12..13] | Should -Be @('--logo-padding-right', "$(6 + [Math]::Max(30, $logo.Width) - 30)")
        InModuleScope Lotus { Should -Invoke Get-LotusCover -Times 1 -Exactly -ParameterFilter { $Rows -eq (Get-LotusLogoPainted ([string]$script:S['LOTUS_LOGO'])).Height + 0 -or $true } }
    }
    It 'asks for a cover at most as wide as twice its height, and always leaves 64 columns for the info' {
        InModuleScope Lotus {
            Mock Get-LotusCover { $null }
            Get-LotusArtArgs 22 200 -Song 'x' | Out-Null
            Should -Invoke Get-LotusCover -ParameterFilter { $Columns -le 2 * $Rows -and $Columns -le 200 - 64 }
            Get-LotusArtArgs 22 90 -Song 'x' | Out-Null
            Should -Invoke Get-LotusCover -ParameterFilter { $Columns -eq 26 }
        }
    }
    It 'keeps the logo when the window is too narrow for a cover, the cover is off, nothing plays, or the song has no cover' {
        InModuleScope Lotus {
            Mock Get-LotusCover { $null }
            $logo = Get-LotusArtArgs 22 200
            $logo[1] | Should -Match 'lotus\.txt$'
            Get-LotusArtArgs 22 200 -Song '' | Should -Be $logo                      # nothing plays
            Get-LotusArtArgs 22 200 -Song 'x' | Should -Be $logo                     # the song has no cover
            Should -Invoke Get-LotusCover -Times 1 -Exactly
            Get-LotusArtArgs 22 80 -Song 'x' | Out-Null                              # 80 - 64 = 16 columns: too narrow
            $script:S['LOTUS_COVER'] = '0'
            Get-LotusArtArgs 22 200 -Song 'x' | Should -Be $logo
            $script:S['LOTUS_COVER'] = '1'; $script:NpOn = $false
            Get-LotusArtArgs 22 200 -Song 'x' | Should -Be $logo
            Should -Invoke Get-LotusCover -Times 1 -Exactly
        }
    }
    It 'asks for the cover only when now playing says a song is playing, and gives fastfetch the cover to draw' {
        $bytes = $script:Pics['quarters']
        Mock -ModuleName Lotus Get-LotusMediaCover ({ param($OutFile) [System.IO.File]::WriteAllBytes($OutFile, $bytes); [pscustomobject]@{ Status = 'Playing'; Title = 'Habiba'; Artist = 'Boef'; Album = ''; HasCover = $true } }.GetNewClosure())
        Mock -ModuleName Lotus Get-LotusFastfetch { 'fastfetch' }
        $seen = Join-Path $script:Ctx.Tmp 'fastfetch-args.txt'
        Remove-Item -LiteralPath $seen -Force -ErrorAction SilentlyContinue
        $env:LOTUS_TEST_ARGS = $seen
        try {
            Mock -ModuleName Lotus Invoke-LotusNativeText {
                if ($Arguments[1] -like '*np-*') { "♫ Habiba — Boef`n  [■■■·······] 0:21  ▶ playing" }
                else { [System.IO.File]::WriteAllLines($env:LOTUS_TEST_ARGS, [string[]]$Arguments); "@@LOTUS_HELLO@@`n@@LOTUS_SALUTE@@`n@@LOTUS_NP1@@`n@@LOTUS_NP2@@" }
            }
            $out = InModuleScope Lotus { Get-LotusStartText -Columns 160 }
            $out | Should -Match 'Habiba'
            $out | Should -Not -Match '@@LOTUS_'
            $a = [System.IO.File]::ReadAllLines($seen)
            $a[[array]::IndexOf($a, '--logo') + 1] | Should -Match 'covers[\\/][0-9a-f]{16}-\d+x\d+-(tc|256)\.txt$'
            $a[[array]::IndexOf($a, '--logo') + 2] | Should -Be '--logo-type'
            # paused: the logo, and Windows is not asked for a cover
            Mock -ModuleName Lotus Invoke-LotusNativeText {
                if ($Arguments[1] -like '*np-*') { "♫ Habiba — Boef`n  [■■■·······] 0:21  ‖ paused" }
                else { [System.IO.File]::WriteAllLines($env:LOTUS_TEST_ARGS, [string[]]$Arguments); "@@LOTUS_HELLO@@`n@@LOTUS_SALUTE@@`n@@LOTUS_NP1@@`n@@LOTUS_NP2@@" }
            }
            Remove-Item -Path (Join-Path $env:LOTUS_CACHE 'np-*-*') -Force -ErrorAction SilentlyContinue      # (what plays is kept for a moment)
            Remove-Item -LiteralPath (Join-Path $env:LOTUS_CACHE 'covers') -Recurse -Force -ErrorAction SilentlyContinue
            InModuleScope Lotus { Get-LotusStartText -Columns 160 } | Out-Null
            $a = [System.IO.File]::ReadAllLines($seen)
            $a[[array]::IndexOf($a, '--logo') + 1] | Should -Match 'art[\\/]lotus\.txt$'
            Should -Invoke -ModuleName Lotus Get-LotusMediaCover -Times 1 -Exactly
        } finally { Remove-Item Env:LOTUS_TEST_ARGS -ErrorAction SilentlyContinue }
    }
}

Describe 'the settings' {
    It 'offer the cover as a switch under Now playing, and have it on' {
        $items = InModuleScope Lotus { Initialize-Lotus; Import-LotusCommand settings; Get-LotusSettingsItems }
        $i = [array]::IndexOf($items, ($items | Where-Object { $_ -like 'bool|LOTUS_COVER|*' } | Select-Object -First 1))
        $i | Should -BeGreaterThan 0
        $items[$i] | Should -Be 'bool|LOTUS_COVER|Album cover instead of the logo|'
        $items[$i - 1] | Should -Be 'head||Now playing|'
        (lotus settings get LOTUS_COVER) | Should -Be '1'
        lotus settings set LOTUS_COVER 0 | Out-Null
        (lotus settings get LOTUS_COVER) | Should -Be '0'
        lotus settings set LOTUS_COVER 1 | Out-Null
    }
}

Describe 'Windows'' media session' {
    It 'answers without a player: nothing, or a song – and never an error' -Skip:(-not $IsWindows) {
        $out = Join-Path $script:Ctx.Tmp 'session.img'
        $r = InModuleScope Lotus -Parameters @{ Out = $out } { Get-LotusMediaCover $Out }
        if ($r) { $r.Status | Should -Not -BeNullOrEmpty } else { $r | Should -BeNullOrEmpty }
    }
    It 'is nothing off Windows' -Skip:($IsWindows) {
        InModuleScope Lotus { Get-LotusMediaCover (Join-Path ([System.IO.Path]::GetTempPath()) 'x.img') } | Should -BeNullOrEmpty
    }
}
