# /img on Windows (Public/img.ps1): images and folders converted with ImageMagick – the magick.exe of Windows, or (off
# Windows, for these tests) ImageMagick 6. The originals stay, nothing is written over, photos get smaller but never larger.

BeforeDiscovery {
    # an ImageMagick that works: it makes a picture of one pixel. (A magick.exe that came with another program may lack
    # the parts that read and write images – the CI's Arm64 machine has one, and no winget to install a real one.)
    $script:HasMagick = $false
    $tries = @(@(Get-Command magick -CommandType Application -All -ErrorAction SilentlyContinue) | ForEach-Object Source)
    if ($IsWindows -and $env:ProgramFiles) { $tries += @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'ImageMagick-*\magick.exe') -ErrorAction SilentlyContinue | ForEach-Object FullName) }
    if (-not $IsWindows) { $tries += @(@(Get-Command convert -CommandType Application -ErrorAction SilentlyContinue) | ForEach-Object Source) }
    $probe = Join-Path ([IO.Path]::GetTempPath()) "lotus-magick-probe-$PID.png"
    foreach ($t in $tries) {
        & $t -size 1x1 'xc:white' $probe *> $null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $probe)) { $script:HasMagick = $true; Remove-Item -LiteralPath $probe -Force; break }
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-img'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    $script:Magick = InModuleScope Lotus { Initialize-Lotus; Import-LotusCommand img; Find-LotusMagick }
    $script:Dir = Join-Path $script:Ctx.Tmp 'pictures'
    New-Item -ItemType Directory -Force -Path $script:Dir | Out-Null
    # a picture made by ImageMagick itself: <name> <width>x<height>
    function New-TestImage {
        param([string]$Name, [string]$Size)
        $path = Join-Path $script:Dir $Name
        & $script:Magick.Convert[0] @($script:Magick.Convert | Select-Object -Skip 1) -size $Size 'xc:#ff3366' $path
        $path
    }
    function Get-TestSize { param([string]$Path) & $script:Magick.Identify[0] @($script:Magick.Identify | Select-Object -Skip 1) -format '%wx%h' "$Path[0]" }
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'ImageMagick' {
    It 'is found the way Windows has it – never the convert.exe of Windows' {
        if ($IsWindows -and $script:Magick) { $script:Magick.Convert[0] | Should -Match 'magick(\.exe)?$' }
        $true | Should -BeTrue
    }
    It 'without it, the command to install it' {
        $out = InModuleScope Lotus {
            $real = (Get-Item function:Find-LotusMagick).ScriptBlock
            Set-Item function:script:Find-LotusMagick { $null }
            $png = Join-Path ([IO.Path]::GetTempPath()) "lotus-img-$PID.png"
            [IO.File]::WriteAllBytes($png, [byte[]](0x89, 0x50, 0x4E, 0x47))
            try { Invoke-LotusImgConvert @($png, '--to', 'jpeg') } finally { Set-Item function:script:Find-LotusMagick $real; Remove-Item -LiteralPath $png -Force }
        } 6>&1 | Out-String
        $out | Should -Match 'needs ImageMagick'
        $out | Should -Match 'winget install --id ImageMagick.ImageMagick -e'
    }
}

Describe 'converting' -Skip:(-not $script:HasMagick) {
    It 'an image becomes a smaller JPEG next to it – the original stays' {
        $png = New-TestImage 'banner.png' '300x200'
        $before = (Get-FileHash $png).Hash
        lotus img convert $png --to jpeg --max 100 --quality 80 | Out-Null
        $LASTEXITCODE | Should -Be 0
        $jpg = Join-Path $script:Dir 'banner.jpg'
        Test-Path $jpg | Should -BeTrue
        Get-TestSize $jpg | Should -Be '100x67'
        (Get-FileHash $png).Hash | Should -Be $before
        [IO.File]::ReadAllBytes($jpg)[0..2] | Should -Be @(0xFF, 0xD8, 0xFF)
    }
    It 'never larger, and never over a file that is there' {
        $png = Join-Path $script:Dir 'banner.png'
        lotus img convert $png --to jpeg --max 4000 | Out-Null
        $second = Join-Path $script:Dir 'banner (2).jpg'
        Test-Path $second | Should -BeTrue
        Get-TestSize $second | Should -Be '300x200'
    }
    It 'a folder gets a folder for the new format' {
        $folder = Join-Path $script:Dir 'shoot'
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        foreach ($n in 'a', 'b') { Move-Item -LiteralPath (New-TestImage "$n.png" '64x64') -Destination (Join-Path $folder "$n.png") }
        Set-Content -LiteralPath (Join-Path $folder 'notes.txt') -Value 'not an image'
        $out = lotus img convert $folder --to bmp 6>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 images'
        foreach ($n in 'a', 'b') { Test-Path (Join-Path $folder "BMP/$n.bmp") | Should -BeTrue }
        Test-Path (Join-Path $folder 'BMP/notes.bmp') | Should -BeFalse
    }
    It 'an icon is square and at most 256 px' {
        $png = New-TestImage 'logo.png' '600x300'
        lotus img convert $png --to ico | Out-Null
        Test-Path (Join-Path $script:Dir 'logo.ico') | Should -BeTrue
        Get-TestSize (Join-Path $script:Dir 'logo.ico') | Should -Be '256x256'
    }
    It 'says what is wrong' {
        $png = Join-Path $script:Dir 'banner.png'
        lotus img convert $png --to xyz 6>&1 | Out-String | Should -Match 'Unknown format: xyz'
        lotus img convert $png --to jpeg --quality 101 6>&1 | Out-String | Should -Match 'from 1 to 100'
        lotus img convert $png 6>&1 | Out-String | Should -Match 'Into which format'
        lotus img convert (Join-Path $script:Dir 'missing.png') --to png 6>&1 | Out-String | Should -Match 'Not found'
    }
    It 'passes over a magick that cannot write images, when one that can is there' {
        $dir = Join-Path $script:Ctx.Tmp 'broken-magick'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        if ($IsWindows) { Set-Content -LiteralPath (Join-Path $dir 'magick.cmd') -Value '@exit /b 1' }
        else { Set-Content -LiteralPath (Join-Path $dir 'magick') -Value "#!/bin/sh`nexit 1"; & chmod +x (Join-Path $dir 'magick') }
        $old = $env:PATH
        $env:PATH = "$dir$([IO.Path]::PathSeparator)$env:PATH"
        try { $m = InModuleScope Lotus { Find-LotusMagick } } finally { $env:PATH = $old }
        $m.Convert[0] | Should -Not -BeLike "$dir*"
        InModuleScope Lotus -Parameters @{ M = $m } { @(Get-LotusImgWritable $M) } | Should -Contain 'png'
    }
    It 'lists what it writes' {
        $out = lotus img formats 6>&1 | Out-String
        $out | Should -Match '✓ JPEG'
        $out | Should -Match '✓ PNG'
    }
}
