# /icons on Windows (Public/icons.ps1 – the screens; Private/Platform.ps1 – the .ico, the desktop.ini and the marks on the folder), a port
# of lib/cmd/icons.zsh with its tests (tests/test-icons.zsh). What is the same on every system runs everywhere: the bytes of the .ico, the
# text of the desktop.ini, the files in a folder (a PNG that is small enough is the one picture of the icon where Windows' drawing library is
# not there), the commands, and the guided command with keys from a queue. What only Windows has – the drawing of the pictures in six sizes,
# the hidden and read-only marks – is checked on Windows.

BeforeDiscovery {
    # (Windows PowerShell 5.1 has no $IsWindows: the environment says it in both editions)
    $script:OnWindows = $env:OS -eq 'Windows_NT'
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-icons'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    InModuleScope Lotus { Initialize-Lotus; Import-LotusCommand icons }

    # three small pictures (PNG, made with Python's zlib: 32 × 32 red, 32 × 32 green, 64 × 32 blue) and a text that is no picture
    $script:Pics = Join-Path $script:Ctx.Tmp 'Pictures'
    New-Item -ItemType Directory -Force -Path $script:Pics | Out-Null
    $script:Red = Join-Path $script:Pics 'red.png'
    $script:Green = Join-Path $script:Pics 'green.png'
    $script:Wide = Join-Path $script:Pics 'wide.png'
    $script:SpacedPic = Join-Path $script:Pics 'my red.png'
    $script:Notes = Join-Path $script:Pics 'notes.txt'
    $script:RedBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKUlEQVR42u3NsQkAAAgDsB7W//Esr3AQAtmTaU9FIBAIBAKBQCAQfAkWAwwATPGfc7wAAAAASUVORK5CYII=')
    [IO.File]::WriteAllBytes($script:Red, $script:RedBytes)
    [IO.File]::WriteAllBytes($script:SpacedPic, $script:RedBytes)
    [IO.File]::WriteAllBytes($script:Green, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKUlEQVR42u3NsQkAAAgDsB7W//Esr3AQAtmTTk9FIBAIBAKBQCAQfAkW0t8ATIwC23YAAAAASUVORK5CYII='))
    [IO.File]::WriteAllBytes($script:Wide, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAIAAAAt/+nTAAAANklEQVR42u3PQQkAAAgEsAt2/TGWGXwKgxVY2nktAgICAgICAgICAgICAgICAgICAgICAgJXC8meAJf6bNn1AAAAAElFTkSuQmCC'))
    [IO.File]::WriteAllText($script:Notes, 'not a picture')

    # a Desktop with three folders and a file; Lotus is told where it is
    $script:Desktop = Join-Path $script:Ctx.Tmp 'Desktop'
    foreach ($n in 'Projects', 'Photos', 'My Games') { New-Item -ItemType Directory -Force -Path (Join-Path $script:Desktop $n) | Out-Null }
    [IO.File]::WriteAllText((Join-Path $script:Desktop 'notes.txt'), 'a file')
    [IO.File]::WriteAllText((Join-Path $script:Desktop 'Projects/one.txt'), 'x')
    [IO.File]::WriteAllText((Join-Path $script:Desktop 'Projects/two.txt'), 'x')
    $script:Elsewhere = Join-Path $script:Ctx.Tmp 'Elsewhere'
    foreach ($n in 'Deep Folder', 'Other', 'Meine [Spiele]') { New-Item -ItemType Directory -Force -Path (Join-Path $script:Elsewhere $n) | Out-Null }
    $env:LOTUS_DESKTOP_DIR = $script:Desktop

    # the keys of a typed line: one for each character, a space is "space", then Enter
    function Get-LineKeys { param([string]$Text) @(foreach ($c in $Text.ToCharArray()) { if ($c -eq ' ') { 'space' } else { [string]$c } }) + @('enter') }
    # the picture of a folder, as it is in its files: the name of the .ico (it follows what is in it), or '' when the folder has none
    function Get-IconName { param([string]$Folder) $f = @(Get-ChildItem -LiteralPath $Folder -Force -Filter 'lotus-icon-*.ico' -ErrorAction SilentlyContinue); if ($f.Count) { $f[0].Name } else { '' } }
    function Test-HasIcon { param([string]$Folder) [bool](Get-IconName $Folder) }
    function Reset-AllIcons {
        InModuleScope Lotus -Parameters @{ Desk = $script:Desktop; Else = $script:Elsewhere } {
            foreach ($f in @(Get-ChildItem -LiteralPath $Desk -Directory) + @(Get-ChildItem -LiteralPath $Else -Directory)) { [void](Reset-LotusFolderIcon $f.FullName) }
        }
    }
}

AfterAll {
    Remove-Item Env:LOTUS_DESKTOP_DIR -ErrorAction SilentlyContinue
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe '/icons – the commands of Lotus' {
    It 'is in the table of commands, with set, reset, list and check' {
        $rows = @(Get-Content -LiteralPath (Join-Path $script:Ctx.Repo 'data/commands.tsv') -Encoding UTF8)
        @($rows -match "^Desktop`t/icons`ticons`t/icons`t").Count | Should -Be 1
        foreach ($w in 'set', 'reset', 'list', 'check') { @($rows -match "^Desktop`t-`ticons $w`t").Count | Should -BeGreaterThan 0 }
    }
    It 'the help says what it needs, how to use it, and that nothing inside a folder is changed' {
        $out = lotus icons help 6>&1 | Out-String
        $out | Should -Match 'WHAT IT NEEDS'
        $out | Should -Match 'Windows 10 or 11'
        $out | Should -Match '/icons set <picture> <folders>'
        $out | Should -Match 'What is inside your folders stays as it is'
    }
    It 'a bare /icons without a keyboard is the help, and icon is the same command' {
        (lotus icons 6>&1 | Out-String) | Should -Match '/icons reset'
        (lotus icon help 6>&1 | Out-String) | Should -Match 'WHAT IT NEEDS'
    }
    It 'an unknown word is named, with what there is, and the status is 1' {
        $out = lotus icons frobnicate 6>&1 | Out-String
        $out | Should -Match 'Unknown: /icons frobnicate'
        $out | Should -Match '/icons reset'
        $LASTEXITCODE | Should -Be 1
    }
    It 'check lists what it needs, with the picture types, and says it is ready' {
        $out = lotus icons check 6>&1 | Out-String
        $out | Should -Match 'WHAT IT NEEDS'
        $out | Should -Match 'Nothing to install'
        $out | Should -Match 'PNG · JPEG · BMP · GIF · TIFF · ICO'
        $out | Should -Match 'Ready – run /icons'
        $LASTEXITCODE | Should -Be 0
    }
}

Describe '/icons – the bytes of an .ico file' {
    It 'one PNG: the directory (reserved, icon, one picture, 32 × 32, 32 bits, its size, where it starts), then the PNG itself' {
        $r = InModuleScope Lotus -Parameters @{ P = $script:RedBytes } {
            $ico = ConvertTo-LotusIco @(, [byte[]]$P)
            [pscustomobject]@{ Head = [BitConverter]::ToString($ico, 0, 22); Length = $ico.Length; Same = ([BitConverter]::ToString($ico, 22) -eq [BitConverter]::ToString($P)) }
        }
        $r.Head | Should -Be '00-00-01-00-01-00-20-20-00-00-01-00-20-00-62-00-00-00-16-00-00-00'
        $r.Length | Should -Be (22 + $script:RedBytes.Length)
        $r.Same | Should -BeTrue
    }
    It 'two PNGs: both in the directory, the second one starts after the first' {
        $r = InModuleScope Lotus -Parameters @{ A = $script:RedBytes; B = [IO.File]::ReadAllBytes($script:Wide) } {
            $ico = ConvertTo-LotusIco ([byte[][]]@([byte[]]$A, [byte[]]$B))
            [pscustomobject]@{ Count = $ico[4]; Second = [BitConverter]::ToString($ico, 22, 2); Start = [BitConverter]::ToUInt32($ico, 34); Length = $ico.Length }
        }
        $r.Count | Should -Be 2
        $r.Second | Should -Be '40-20'
        $r.Start | Should -Be (38 + $script:RedBytes.Length)
        $r.Length | Should -Be (38 + $script:RedBytes.Length + (Get-Item -LiteralPath $script:Wide).Length)
    }
    It 'a width of 256 is written as 0 – that is how the format says it' {
        $r = InModuleScope Lotus -Parameters @{ P = $script:RedBytes } {
            $big = [byte[]]$P.Clone(); $big[18] = 1; $big[19] = 0          # the width in the header of the PNG: 256
            [BitConverter]::ToString((ConvertTo-LotusIco @(, $big)), 6, 2)
        }
        $r | Should -Be '00-20'
    }
    It 'what is no PNG, or is bigger than 256 pixels, makes no .ico' {
        $r = InModuleScope Lotus -Parameters @{ P = $script:RedBytes } {
            $huge = [byte[]]$P.Clone(); $huge[18] = 1; $huge[19] = 44      # 300 pixels wide
            [pscustomobject]@{ Huge = ($null -eq (ConvertTo-LotusIco @(, $huge))); Text = ($null -eq (ConvertTo-LotusIco @(, [byte[]](1..40)))); None = ($null -eq (ConvertTo-LotusIco ([byte[][]]@()))) }
        }
        $r.Huge | Should -BeTrue
        $r.Text | Should -BeTrue
        $r.None | Should -BeTrue
    }
}

Describe '/icons – the text of a desktop.ini' {
    BeforeAll {
        function Get-Ini { param([string]$Text, [string]$Icon) InModuleScope Lotus -Parameters @{ T = $Text; I = $Icon } { $r = Update-LotusDesktopIniText $T $I; if ($null -eq $r) { '<nothing>' } else { $r -replace "`r`n", '|' } } }
    }
    It 'a new file: the heading, IconResource, IconFile and IconIndex – with the line ends of Windows' {
        Get-Ini '' 'lotus-icon-abcd1234.ico' | Should -Be '[.ShellClassInfo]|IconResource=lotus-icon-abcd1234.ico,0|IconFile=lotus-icon-abcd1234.ico|IconIndex=0|'
    }
    It 'taking the icon away from a file that was only for it leaves nothing' {
        $set = InModuleScope Lotus { Update-LotusDesktopIniText '' 'a.ico' }
        Get-Ini $set '' | Should -Be '<nothing>'
        Get-Ini '' '' | Should -Be '<nothing>'
    }
    It 'an existing file keeps every other line and group, blank lines too – the old icon keys go' {
        $old = "[.ShellClassInfo]`r`nLocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21770`r`nIconResource=C:\old.dll,3`r`n`r`n[ViewState]`r`nMode=`r`n"
        $new = Get-Ini $old 'lotus-icon-1111aaaa.ico'
        $new | Should -Be '[.ShellClassInfo]|IconResource=lotus-icon-1111aaaa.ico,0|IconFile=lotus-icon-1111aaaa.ico|IconIndex=0|LocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21770||[ViewState]|Mode=|'
        $back = Get-Ini ((InModuleScope Lotus -Parameters @{ O = $old } { Update-LotusDesktopIniText $O 'lotus-icon-1111aaaa.ico' })) ''
        $back | Should -Be '[.ShellClassInfo]|LocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21770||[ViewState]|Mode=|'
    }
    It 'a second picture replaces the first: one set of keys; case does not matter in the heading and the keys' {
        $once = InModuleScope Lotus { Update-LotusDesktopIniText '' 'a.ico' }
        $twice = InModuleScope Lotus -Parameters @{ O = $once } { Update-LotusDesktopIniText $O 'b.ico' }
        ([regex]::Matches($twice, 'IconResource=')).Count | Should -Be 1
        $twice | Should -Match 'b\.ico'
        Get-Ini "[.shellclassinfo]`r`niconresource=x.ico,0`r`nInfoTip=hello`r`n" '' | Should -Be '[.shellclassinfo]|InfoTip=hello|'
    }
    It 'a file without the group gets it first' {
        Get-Ini "[ViewState]`r`nMode=`r`n" 'i.ico' | Should -Be '[.ShellClassInfo]|IconResource=i.ico,0|IconFile=i.ico|IconIndex=0|[ViewState]|Mode=|'
    }
}

Describe '/icons – an icon on a folder: the files' {
    BeforeEach { Reset-AllIcons }
    It 'a picture becomes lotus-icon-<8 letters>.ico and a desktop.ini that names it – and the folder has an icon of its own' {
        $folder = Join-Path $script:Desktop 'Projects'
        $r = InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Red } { Set-LotusFolderIcon $F $P }
        $r.Code | Should -Be 0
        $name = Get-IconName $folder
        $name | Should -Match '^lotus-icon-[0-9a-f]{8}\.ico$'
        $ini = (Get-Content -LiteralPath (Join-Path $folder 'desktop.ini') -Raw)
        ($ini -replace "`r`n", '|') | Should -Be "[.ShellClassInfo]|IconResource=$name,0|IconFile=$name|IconIndex=0|"
        ([IO.File]::ReadAllBytes((Join-Path $folder $name)))[0..3] -join ' ' | Should -Be '0 0 1 0'
        (InModuleScope Lotus -Parameters @{ F = $folder } { Test-LotusFolderIcon $F }) | Should -BeTrue
        (InModuleScope Lotus -Parameters @{ F = (Join-Path $script:Desktop 'Photos') } { Test-LotusFolderIcon $F }) | Should -BeFalse
    }
    It 'another picture replaces the first: one .ico, another name – so that Explorer looks again' {
        $folder = Join-Path $script:Desktop 'Projects'
        InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Red } { [void](Set-LotusFolderIcon $F $P) }
        $first = Get-IconName $folder
        InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Green } { [void](Set-LotusFolderIcon $F $P) }
        @(Get-ChildItem -LiteralPath $folder -Force -Filter 'lotus-icon-*.ico').Count | Should -Be 1
        (Get-IconName $folder) | Should -Not -Be $first
        ([regex]::Matches((Get-Content -LiteralPath (Join-Path $folder 'desktop.ini') -Raw), 'IconResource=')).Count | Should -Be 1
    }
    It 'reset takes everything away again: the .ico and the desktop.ini – and doing it twice is fine' {
        $folder = Join-Path $script:Desktop 'Projects'
        InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Red } { [void](Set-LotusFolderIcon $F $P) }
        (InModuleScope Lotus -Parameters @{ F = $folder } { (Reset-LotusFolderIcon $F).Code }) | Should -Be 0
        @(Get-ChildItem -LiteralPath $folder -Force | Where-Object Name -in 'desktop.ini', 'lotus-icon-*.ico').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $folder -Force -Filter '*.txt').Count | Should -Be 2
        (InModuleScope Lotus -Parameters @{ F = $folder } { (Reset-LotusFolderIcon $F).Code }) | Should -Be 0
    }
    It 'a folder with brackets in its name is a folder like any other' {
        $folder = Join-Path $script:Elsewhere 'Meine [Spiele]'
        (InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Red } { (Set-LotusFolderIcon $F $P).Code }) | Should -Be 0
        Test-HasIcon $folder | Should -BeTrue
        (InModuleScope Lotus -Parameters @{ F = $folder } { (Reset-LotusFolderIcon $F).Code }) | Should -Be 0
        Test-HasIcon $folder | Should -BeFalse
    }
    It 'an .ico file is used as it is' {
        $folder = Join-Path $script:Desktop 'Photos'
        $mine = Join-Path $script:Pics 'mine.ico'
        [IO.File]::WriteAllBytes($mine, (InModuleScope Lotus -Parameters @{ P = $script:RedBytes } { ConvertTo-LotusIco @(, [byte[]]$P) }))
        (InModuleScope Lotus -Parameters @{ F = $folder; P = $mine } { (Set-LotusFolderIcon $F $P).Code }) | Should -Be 0
        [IO.File]::ReadAllBytes((Join-Path $folder (Get-IconName $folder))).Length | Should -Be ([IO.File]::ReadAllBytes($mine)).Length
    }
    It 'what is not an icon file, and a folder that is not there, are refused with a reason' {
        $notIco = Join-Path $script:Pics 'not.ico'
        [IO.File]::WriteAllText($notIco, 'hello hello hello hello hello hello')
        $r = InModuleScope Lotus -Parameters @{ F = (Join-Path $script:Desktop 'Photos'); P = $notIco; Nowhere = (Join-Path $script:Ctx.Tmp 'nowhere') } {
            $a = Set-LotusFolderIcon $F $P
            $b = Set-LotusFolderIcon $Nowhere $P
            "$($a.Code)|$($a.Msg[0])|$($b.Code)|$($b.Msg[0])"
        }
        $r | Should -Be '1|This is not an icon file|1|This is not a folder'
        Test-HasIcon (Join-Path $script:Desktop 'Photos') | Should -BeFalse
    }
    It 'a desktop.ini that Explorer wrote (UTF-16, other keys, umlauts) keeps its encoding and everything else – and comes back as it was' {
        $folder = Join-Path $script:Desktop 'Photos'
        $text = "[.ShellClassInfo]`r`nLocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21779`r`nInfoTip=Meine Bilder – schöne`r`n"
        $enc = New-Object System.Text.UnicodeEncoding($false, $true)
        $ini = Join-Path $folder 'desktop.ini'
        [IO.File]::WriteAllBytes($ini, [byte[]]($enc.GetPreamble() + $enc.GetBytes($text)))
        InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Red } { [void](Set-LotusFolderIcon $F $P) }
        $bytes = [IO.File]::ReadAllBytes($ini)
        ('{0:X2}{1:X2}' -f $bytes[0], $bytes[1]) | Should -Be 'FFFE'
        $now = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        $now | Should -Match 'InfoTip=Meine Bilder – schöne'
        $now | Should -Match 'IconResource=lotus-icon-[0-9a-f]{8}\.ico,0'
        InModuleScope Lotus -Parameters @{ F = $folder } { [void](Reset-LotusFolderIcon $F) }
        $bytes = [IO.File]::ReadAllBytes($ini)
        [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) | Should -Be $text
        Test-HasIcon $folder | Should -BeFalse
        InModuleScope Lotus -Parameters @{ P = $ini } { Remove-LotusHiddenFile $P }
    }
}

Describe '/icons – the drawing and the marks of Windows' -Skip:(-not $script:OnWindows) {
    BeforeEach { Reset-AllIcons }
    It 'a picture becomes six sizes in the .ico: 256, 128, 64, 48, 32 and 16 pixels, each a PNG' {
        $folder = Join-Path $script:Desktop 'Projects'
        (InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Red } { (Set-LotusFolderIcon $F $P).Code }) | Should -Be 0
        $ico = [IO.File]::ReadAllBytes((Join-Path $folder (Get-IconName $folder)))
        $ico[4] | Should -Be 6
        (0..5 | ForEach-Object { $ico[6 + 16 * $_] }) -join ',' | Should -Be '0,128,64,48,32,16'
        foreach ($i in 0..5) {
            $at = [BitConverter]::ToUInt32($ico, 6 + 16 * $i + 12)
            [BitConverter]::ToString($ico, [int]$at, 8) | Should -Be '89-50-4E-47-0D-0A-1A-0A'
        }
    }
    It 'a picture that is not square keeps its shape: the frames are square, with a see-through margin' {
        Add-Type -AssemblyName System.Drawing
        $folder = Join-Path $script:Desktop 'Photos'
        (InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Wide } { (Set-LotusFolderIcon $F $P).Code }) | Should -Be 0
        $ico = [IO.File]::ReadAllBytes((Join-Path $folder (Get-IconName $folder)))
        $at = [int][BitConverter]::ToUInt32($ico, 6 + 12)
        $size = [int][BitConverter]::ToUInt32($ico, 6 + 8)
        $stream = New-Object System.IO.MemoryStream(, [byte[]]($ico[$at..($at + $size - 1)]))
        $bmp = New-Object System.Drawing.Bitmap($stream)
        try {
            $bmp.Width | Should -Be 256
            $bmp.Height | Should -Be 256
            $bmp.GetPixel(128, 2).A | Should -Be 0
            $bmp.GetPixel(128, 128).A | Should -Be 255
            $bmp.GetPixel(128, 128).B | Should -BeGreaterThan 150
        } finally { $bmp.Dispose(); $stream.Dispose() }
    }
    It 'JPEG, BMP and GIF pictures work too' {
        Add-Type -AssemblyName System.Drawing
        $folder = Join-Path $script:Desktop 'My Games'
        $source = New-Object System.Drawing.Bitmap(48, 24)
        try {
            foreach ($kind in 'Jpeg', 'Bmp', 'Gif') {
                $file = Join-Path $script:Pics "made.$($kind.ToLower())"
                $source.Save($file, [System.Drawing.Imaging.ImageFormat]::$kind)
                (InModuleScope Lotus -Parameters @{ F = $folder; P = $file } { (Set-LotusFolderIcon $F $P).Code }) | Should -Be 0
                (Get-IconName $folder) | Should -Match '^lotus-icon-[0-9a-f]{8}\.ico$'
            }
        } finally { $source.Dispose() }
    }
    It 'the files are hidden system files, and the folder is marked read-only – for Explorer; reset takes the marks away too' {
        $folder = Join-Path $script:Desktop 'Projects'
        InModuleScope Lotus -Parameters @{ F = $folder; P = $script:Red } { [void](Set-LotusFolderIcon $F $P) }
        # (whole numbers: Hidden is 2, System is 4, ReadOnly is 1)
        ([int][IO.File]::GetAttributes((Join-Path $folder 'desktop.ini')) -band 6) | Should -Be 6
        ([int][IO.File]::GetAttributes((Join-Path $folder (Get-IconName $folder))) -band 6) | Should -Be 6
        ([int][IO.File]::GetAttributes($folder) -band 1) | Should -Be 1
        InModuleScope Lotus -Parameters @{ F = $folder } { [void](Reset-LotusFolderIcon $F) }
        ([int][IO.File]::GetAttributes($folder) -band 1) | Should -Be 0
        Test-Path -LiteralPath (Join-Path $folder 'desktop.ini') | Should -BeFalse
    }
    It 'a picture that Windows cannot read says so, and nothing is written' {
        $folder = Join-Path $script:Desktop 'Photos'
        $fake = Join-Path $script:Pics 'fake.png'
        [IO.File]::WriteAllText($fake, 'this is not a PNG')
        $r = InModuleScope Lotus -Parameters @{ F = $folder; P = $fake } { $x = Set-LotusFolderIcon $F $P; "$($x.Code)|$($x.Msg[0])" }
        $r | Should -Be '1|Windows cannot read this picture'
        Test-HasIcon $folder | Should -BeFalse
    }
    It 'Explorer is told to look at the icons again without a complaint' {
        { InModuleScope Lotus { Update-LotusExplorer } } | Should -Not -Throw
    }
}

Describe '/icons – without questions' {
    BeforeEach { Reset-AllIcons; Push-Location $script:Pics }
    AfterEach { Pop-Location }
    It 'set: names of folders on the Desktop, the picture in this folder' {
        $out = lotus icons set red.png Projects 'My Games' 6>&1 | Out-String
        $out | Should -Match '2 folders have a new icon'
        $out | Should -Match '✓ My Games'
        $out | Should -Match '/icons reset'
        $LASTEXITCODE | Should -Be 0
        Test-HasIcon (Join-Path $script:Desktop 'Projects') | Should -BeTrue
        Test-HasIcon (Join-Path $script:Desktop 'My Games') | Should -BeTrue
        Test-HasIcon (Join-Path $script:Desktop 'Photos') | Should -BeFalse
    }
    It 'list names the folders with what they hold and which have a picture of their own – and not the files' {
        lotus icons set red.png Projects 6>&1 | Out-Null
        $out = lotus icons list 6>&1 | Out-String
        $out | Should -Match 'Projects\s+2 items · has a picture of its own'
        $out | Should -Match 'Photos\s+empty'
        $out | Should -Not -Match 'notes\.txt'
    }
    It 'set --all: every folder on the Desktop – a folder named too is done once' {
        $out = lotus icons set green.png --all 6>&1 | Out-String
        $out | Should -Match '3 folders have a new icon'
        $out = lotus icons set green.png Photos Photos --all 6>&1 | Out-String
        $out | Should -Match '3 folders have a new icon'
        foreach ($n in 'Projects', 'Photos', 'My Games') { Test-HasIcon (Join-Path $script:Desktop $n) | Should -BeTrue }
    }
    It 'reset: one folder by name; --all only the folders that have a picture of their own; and then there is nothing to do' {
        lotus icons set red.png --all 6>&1 | Out-Null
        (lotus icons reset Photos 6>&1 | Out-String) | Should -Match '1 folder has the normal icon again'
        Test-HasIcon (Join-Path $script:Desktop 'Photos') | Should -BeFalse
        Test-HasIcon (Join-Path $script:Desktop 'Projects') | Should -BeTrue
        (lotus icons reset --all 6>&1 | Out-String) | Should -Match '2 folders have the normal icon again'
        (lotus icons reset --all 6>&1 | Out-String) | Should -Match 'None of the folders on your Desktop has a picture of its own'
    }
    It 'a picture as the first word is the same as set; paths with spaces that were not quoted are put together again' {
        (lotus icons red.png Projects 6>&1 | Out-String) | Should -Match '1 folder has a new icon'
        $deep = Join-Path $script:Elsewhere 'Deep Folder'
        $pieces = @($script:SpacedPic -split ' ') + @($deep -split ' ')
        $out = lotus icons set @pieces 6>&1 | Out-String
        $out | Should -Match '1 folder has a new icon'
        Test-HasIcon $deep | Should -BeTrue
    }
    It 'a picture on its own may have spaces in its path, typed without quotes – the words are joined until it is found' {
        $pieces = @($script:SpacedPic -split ' ') + @('Projects')
        (lotus icons @pieces 6>&1 | Out-String) | Should -Match '1 folder has a new icon'
        Test-HasIcon (Join-Path $script:Desktop 'Projects') | Should -BeTrue
    }
    It 'a folder from outside the Desktop, by its path' {
        $other = Join-Path $script:Elsewhere 'Other'
        (lotus icons set red.png $other 6>&1 | Out-String) | Should -Match '1 folder has a new icon'
        Test-HasIcon $other | Should -BeTrue
    }
    It 'what is wrong is said: no picture, an empty one, none found, no folders, a folder that is not there, a file for a folder' {
        $out = lotus icons set notes.txt Projects 6>&1 | Out-String
        $out | Should -Match 'notes\.txt cannot be an icon'
        $out | Should -Match 'it is not a picture file'
        $LASTEXITCODE | Should -Be 1
        $empty = Join-Path $script:Pics 'empty.png'
        [IO.File]::WriteAllBytes($empty, [byte[]]@())
        (lotus icons set empty.png Projects 6>&1 | Out-String) | Should -Match 'the file is empty'
        (lotus icons set nope.png Projects 6>&1 | Out-String) | Should -Match 'Not found: nope\.png'
        $out = lotus icons set red.png 6>&1 | Out-String
        $out | Should -Match 'Which folders\?'
        $out | Should -Match '/icons set red\.png --all'
        $LASTEXITCODE | Should -Be 1
        (lotus icons red.png 6>&1 | Out-String) | Should -Match 'Which folders\?'
        (lotus icons set 6>&1 | Out-String) | Should -Match 'Which picture\?'
        (lotus icons set red.png Nowhere 6>&1 | Out-String) | Should -Match 'Not found: Nowhere'
        (lotus icons set red.png green.png 6>&1 | Out-String) | Should -Match 'Not a folder: green\.png'
        $out = lotus icons reset Nowhere 6>&1 | Out-String
        $out | Should -Match 'Not found: Nowhere'
        $LASTEXITCODE | Should -Be 1
        (lotus icons reset 6>&1 | Out-String) | Should -Match 'Which folders\?'
        Test-HasIcon (Join-Path $script:Desktop 'Projects') | Should -BeFalse
    }
}

Describe '/icons – the guided command' {
    BeforeAll { InModuleScope Lotus { $script:Toggles = @() } }
    BeforeEach { Reset-AllIcons }
    It 'all folders, one picture: what it needs and how it works, three steps, the drop zone, the check – then every folder has it' {
        $keys = @('enter', 'enter') + (Get-LineKeys $script:Red) + @('y')
        $out = Invoke-LotusWithKeys $keys { Invoke-LotusIconsGuided 'set' '' }
        $out | Should -Match 'WHAT IT NEEDS'
        $out | Should -Match '1  Choose the folders – one, a few or all of them'
        $out | Should -Match 'Step 1 of 3 · Which folders\?'
        $out | Should -Match '● All 3 folders on the Desktop'
        $out | Should -Match 'Step 2 of 3 · The picture'
        $out | Should -Match 'Drop the picture here'
        $out | Should -Match 'Step 3 of 3 · Check'
        $out | Should -Match 'My Games\s+→ red\.png'
        $out | Should -Match 'Change the icon of 3 folders\?'
        $out | Should -Match '3 folders have a new icon'
        foreach ($n in 'Projects', 'Photos', 'My Games') { Test-HasIcon (Join-Path $script:Desktop $n) | Should -BeTrue }
    }
    It 'choose which ones, and a different picture for each: only the ticked folders, each with its own' {
        $keys = @('down', 'enter', 'space', 'down', 'down', 'space', 'enter', 'down', 'enter') + (Get-LineKeys $script:Red) + (Get-LineKeys $script:Green) + @('y')
        $out = Invoke-LotusWithKeys $keys { Invoke-LotusIconsGuided 'set' '' }
        $out | Should -Match 'Tick the folders with Space'
        $out | Should -Match 'Drop the picture for “My Games”'
        $out | Should -Match 'Drop the picture for “Projects”'
        $out | Should -Match 'Projects\s+→ green\.png'
        $out | Should -Match '2 folders have a new icon'
        Test-HasIcon (Join-Path $script:Desktop 'Photos') | Should -BeFalse
        (Get-IconName (Join-Path $script:Desktop 'My Games')) | Should -Not -Be (Get-IconName (Join-Path $script:Desktop 'Projects'))
        Test-HasIcon (Join-Path $script:Desktop 'My Games') | Should -BeTrue
        Test-HasIcon (Join-Path $script:Desktop 'Projects') | Should -BeTrue
    }
    It 'q at the drop zone, and Esc at a question, go back – nothing is changed' {
        $out = Invoke-LotusWithKeys @('enter', 'enter', 'q', 'enter') { Invoke-LotusIconsGuided 'set' '' }
        $out | Should -Match 'Nothing was changed\.'
        $out = Invoke-LotusWithKeys @('esc') { Invoke-LotusIconsGuided 'set' '' }
        $out | Should -Match 'Nothing was changed\.'
        foreach ($n in 'Projects', 'Photos', 'My Games') { Test-HasIcon (Join-Path $script:Desktop $n) | Should -BeFalse }
    }
    It 'other folders: dropped as the terminal types them, with quotes – what is not there is named' {
        $deep = Join-Path $script:Elsewhere 'Deep Folder'
        $keys = @('down', 'down', 'enter') + (Get-LineKeys ('"' + $deep + '" ' + (Join-Path $script:Ctx.Tmp 'nowhere'))) + (Get-LineKeys $script:Red) + @('y')
        $out = Invoke-LotusWithKeys $keys { Invoke-LotusIconsGuided 'set' '' }
        $out | Should -Match 'Drop folders here'
        $out | Should -Match 'Not found: '
        $out | Should -Match '1 folder has a new icon'
        Test-HasIcon $deep | Should -BeTrue
    }
    It 'with the picture given, step 2 is done already – the question is only for the folders' {
        $out = Invoke-LotusWithKeys @('enter', 'y') ([scriptblock]::Create("Invoke-LotusIconsGuided 'set' '$($script:Green)'"))
        $out | Should -Match '2  The picture: green\.png'
        $out | Should -Not -Match 'Drop the picture here'
        $out | Should -Match '3 folders have a new icon'
        $names = @('Projects', 'Photos', 'My Games' | ForEach-Object { Get-IconName (Join-Path $script:Desktop $_) } | Select-Object -Unique)
        $names.Count | Should -Be 1
        $names[0] | Should -Match '^lotus-icon-'
    }
    It 'reset: the folders that have a picture are offered, and come back to normal' {
        lotus icons set $script:Red --all 6>&1 | Out-Null
        $out = Invoke-LotusWithKeys @('enter', 'y') { Invoke-LotusIconsGuided 'reset' '' }
        $out | Should -Match 'Give the folders on your Desktop their normal icon back'
        $out | Should -Match '● All 3 folders that have a picture of their own'
        $out | Should -Match '3 folders have the normal icon again'
        foreach ($n in 'Projects', 'Photos', 'My Games') { Test-HasIcon (Join-Path $script:Desktop $n) | Should -BeFalse }
    }
}

Describe '/icons – when the system says no' {
    It 'a folder that fails is named with the reason, once for all; the others are done; the status is 1' {
        Mock -ModuleName Lotus Set-LotusFolderIcon {
            if ((Split-Path -Leaf $Folder) -in 'Photos', 'Projects') { Lr 1 $null @('The system said no', 'It is locked.', 'Unlock it.') } else { Lr 0 }
        }
        $out = lotus icons set (Join-Path $script:Pics 'red.png') --all 6>&1 | Out-String
        $out | Should -Match '✓ My Games'
        $out | Should -Match '✗ Photos – The system said no'
        ([regex]::Matches($out, 'It is locked\.')).Count | Should -Be 1
        $out | Should -Match '1 folder has a new icon'
        $out | Should -Match '2 folders could not be changed'
        $LASTEXITCODE | Should -Be 1
    }
    It 'when this system cannot at all it says so and shows what it needs' {
        Mock -ModuleName Lotus Set-LotusFolderIcon { Lr 2 }
        $out = lotus icons set (Join-Path $script:Pics 'red.png') Photos 6>&1 | Out-String
        $out | Should -Match 'Folder icons do not work here yet'
        $out | Should -Match 'WHAT IT NEEDS'
        $LASTEXITCODE | Should -Be 1
    }
}
