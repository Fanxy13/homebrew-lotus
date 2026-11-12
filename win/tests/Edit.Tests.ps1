# /img edit on Windows (Public/img.ps1 – the glue) and the editor program itself (lib/edit – Python's standard library: the same
# page, server and geometry as on the Mac and on Linux). The glue finds the picture and the programs it needs and starts the
# server; the test programs of tests/edit (plain Python that prints ✓ and ✗, and Node for the geometry of the crop) run here
# with the Python this module finds – on this system. (tests/test-edit.zsh and test-editserver.zsh run them on Mac and Linux.)

BeforeDiscovery {
    # (the tests that start the editor need a Python – the runners of the CI have one; a WindowsApps python.exe is only Windows' stand-in)
    $script:HasPython = [bool](@(Get-Command py, python3, python -CommandType Application -ErrorAction SilentlyContinue) | Where-Object { $_.Source -notmatch 'WindowsApps' })
    $script:HasNode = [bool](Get-Command node -CommandType Application -ErrorAction SilentlyContinue)
    # an ImageMagick that works: it makes a picture of one pixel. (A magick.exe that came with another program may lack the parts
    # that read and write images – the CI's Arm64 machine has one, and no winget to install a real one.)
    $script:HasMagick = $false
    $tries = @(@(Get-Command magick -CommandType Application -All -ErrorAction SilentlyContinue) | ForEach-Object Source)
    if ($IsWindows -and $env:ProgramFiles) { $tries += @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'ImageMagick-*\magick.exe') -ErrorAction SilentlyContinue | ForEach-Object FullName) }
    if (-not $IsWindows) { $tries += @(@(Get-Command convert -CommandType Application -ErrorAction SilentlyContinue) | ForEach-Object Source) }
    $probe = Join-Path ([IO.Path]::GetTempPath()) "lotus-magick-probe-edit-$PID.png"
    foreach ($t in $tries) {
        & $t -size 1x1 'xc:white' $probe *> $null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $probe)) { $script:HasMagick = $true; Remove-Item -LiteralPath $probe -Force; break }
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-edit'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    $script:Py = InModuleScope Lotus { Initialize-Lotus; Import-LotusCommand img; Find-LotusPython }
    $script:Magick = InModuleScope Lotus { Find-LotusMagick }
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '../Lotus.psd1')).Path
    # a picture to edit: made by ImageMagick itself when it is there – the tests of the glue only need a file with a picture's name
    $script:Dir = Join-Path $script:Ctx.Tmp 'pictures'
    New-Item -ItemType Directory -Force -Path $script:Dir | Out-Null
    $script:Png = Join-Path $script:Dir 'photo.png'
    if ($script:Magick) { & $script:Magick.Convert[0] @($script:Magick.Convert | Select-Object -Skip 1) -size 300x200 'xc:#ff3366' $script:Png *> $null }
    if (-not (Test-Path -LiteralPath $script:Png) -or (Get-Item -LiteralPath $script:Png).Length -lt 64) { [IO.File]::WriteAllBytes($script:Png, [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) }
    # the ImageMagick that was tried out here is the one the editor gets
    $script:UseMagick = ''
    if ($script:Magick -and $script:Magick.Convert.Count -eq 1 -and (Split-Path -Leaf $script:Magick.Convert[0]) -match '^magick(\.exe)?$') { $script:UseMagick = $script:Magick.Convert[0] }

    # a program of tests/edit (or Node's) in a process of its own → @{ Rc; Out } – its output and its errors
    function Invoke-EditProgram {
        param([string]$Program, [string[]]$Arguments, [string]$Name)
        $out = Join-Path $script:Ctx.Tmp "$Name.out"; $err = Join-Path $script:Ctx.Tmp "$Name.err"
        $line = InModuleScope Lotus -Parameters @{ A = $Arguments } { ConvertTo-LotusCommandLine $A }
        $was = $env:LOTUS_MAGICK
        if ($script:UseMagick) { $env:LOTUS_MAGICK = $script:UseMagick }
        try {
            $p = Start-Process -FilePath $Program -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
            $null = $p.Handle
            if (-not $p.WaitForExit(280000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; return [pscustomobject]@{ Rc = -1; Out = 'timed out' } }
            $p.WaitForExit()
            [pscustomobject]@{ Rc = $p.ExitCode; Out = ((Get-Content -LiteralPath $out -Raw -Encoding UTF8) + (Get-Content -LiteralPath $err -Raw -Encoding UTF8)) }
        } finally { $env:LOTUS_MAGICK = $was }
    }
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe '/img – the editor first' {
    It 'the help names the editor and still the converter' {
        $out = lotus img help 6>&1 | Out-String
        $out | Should -Match '/img edit <image>'
        $out | Should -Match 'crop, turn, straighten and convert this picture'
        $out | Should -Match '/img convert <image or folder>'
        $out | Should -Match '/img formats'
    }
    It 'without a keyboard a bare /img is the help, not an editor that waits for a picture' {
        $out = lotus img 6>&1 | Out-String
        $out | Should -Match 'the editor: drop a picture into the window'
        $LASTEXITCODE | Should -Be 0
    }
    It 'an unknown word says where to go' {
        $out = lotus img nonsense 6>&1 | Out-String
        $out | Should -Match 'Unknown: /img nonsense'
        $out | Should -Match '/img edit <image>'
        $LASTEXITCODE | Should -Be 1
    }
    It 'the cheat sheet lists the editor – it is on Windows now' {
        $out = lotus cheatsheet *>&1 | Out-String
        $out | Should -Match '/img edit <image>'
        $out | Should -Match 'Crop, turn, straighten and convert a picture'
    }
}

Describe '/img edit – the glue' {
    BeforeEach {
        # (the glue is what is tested here: a Python and an ImageMagick that are found, none of them is started)
        Mock -ModuleName Lotus Find-LotusPython { [pscustomobject]@{ Exe = 'python-is-not-started'; Args = @(); Version = '3.12' } }
        Mock -ModuleName Lotus Find-LotusMagick { [pscustomobject]@{ Convert = @('magick-is-not-started'); Identify = @('magick-is-not-started', 'identify'); List = @('magick-is-not-started', '-list', 'format') } }
    }
    It 'without Python: the command to install it' {
        Mock -ModuleName Lotus Find-LotusPython { $null }
        $out = lotus img edit $script:Png 6>&1 | Out-String
        $out | Should -Match 'The editor needs Python 3.9 or newer'
        $out | Should -Match 'winget install --id Python.Python.3.13 -e'
        $LASTEXITCODE | Should -Be 1
    }
    It 'without ImageMagick: the command to install it' {
        Mock -ModuleName Lotus Find-LotusMagick { $null }
        $out = lotus img edit $script:Png 6>&1 | Out-String
        $out | Should -Match 'needs ImageMagick'
        $out | Should -Match 'winget install --id ImageMagick.ImageMagick -e'
        $LASTEXITCODE | Should -Be 1
    }
    It 'without a picture and without a keyboard it asks which' {
        $out = lotus img edit 6>&1 | Out-String
        $out | Should -Match 'Which picture\?'
        $out | Should -Match '/img edit <picture>'
        $LASTEXITCODE | Should -Be 1
    }
    It 'a picture that is not there' {
        $out = lotus img edit (Join-Path $script:Dir 'nothing.png') 6>&1 | Out-String
        $out | Should -Match 'Not found: '
        $out | Should -Match 'No picture to edit'
        $LASTEXITCODE | Should -Be 1
    }
    It 'a folder is for /img convert – the editor opens one picture at a time' {
        $folder = Join-Path $script:Dir 'shoot'
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        Copy-Item -LiteralPath $script:Png -Destination (Join-Path $folder 'one.png')
        $out = lotus img edit $folder 6>&1 | Out-String
        $out | Should -Match 'The editor opens one picture at a time'
        $out | Should -Match '/img convert <folder>'
        $LASTEXITCODE | Should -Be 1
    }
    It 'the other names of the command reach the same place' {
        foreach ($word in 'crop', 'e') {
            $out = lotus img $word 6>&1 | Out-String
            $out | Should -Match 'Which picture\?' -Because "/img $word"
        }
    }
    It 'a typed or dropped path (quotes, spaces) is read like a path of /img convert, and nothing is run' {
        $spaced = Join-Path $script:Dir 'my holiday photo.png'
        Copy-Item -LiteralPath $script:Png -Destination $spaced
        # the drop zone's line, as the terminal types it for a file with spaces in its name
        $got = InModuleScope Lotus -Parameters @{ Path = $spaced } {
            $inputs = Get-LotusImgInputs @(Split-LotusShellWords "`"$Path`"")
            [pscustomobject]@{ In = @($inputs.In); Missing = @($inputs.Missing) }
        }
        $got.In | Should -Be @($spaced)
        $got.Missing.Count | Should -Be 0
    }
}

Describe '/img edit – the editor itself, started by the glue' -Skip:(-not ($script:HasPython -and $script:HasMagick)) {
    It 'serves its page and the picture to this computer only, saves nothing, and ends with Cancel' {
        $out = Join-Path $script:Ctx.Tmp 'edit.out'; $err = Join-Path $script:Ctx.Tmp 'edit.err'
        $names = 'LOTUS_EDIT_NO_OPEN', 'LOTUS_EDIT_NO_SHOW', 'LOTUS_EDIT_FIRST', 'LOTUS_MAGICK'
        $was = @{}; foreach ($n in $names) { $was[$n] = [Environment]::GetEnvironmentVariable($n) }
        $env:LOTUS_EDIT_NO_OPEN = '1'; $env:LOTUS_EDIT_NO_SHOW = '1'; $env:LOTUS_EDIT_FIRST = '120'     # (no browser; it ends by itself if the test does not)
        $env:LOTUS_MAGICK = $null
        $server = $null
        try {
            $cmd = "Import-Module '$($script:Module)'; lotus img edit '$($script:Png)'; exit `$LASTEXITCODE"
            $server = Start-Process -FilePath $script:Pwsh -ArgumentList @('-NoProfile', '-Command', $cmd) -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
            $null = $server.Handle
            $url = $null
            $deadline = (Get-Date).AddSeconds(60)
            while (-not $url -and (Get-Date) -lt $deadline -and -not $server.HasExited) {
                $text = if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Raw -Encoding UTF8 } else { '' }
                if ($text -match '(http://127\.0\.0\.1:\d+/[A-Za-z0-9_-]+/)') { $url = $Matches[1] } else { Start-Sleep -Milliseconds 300 }
            }
            $why = "stdout:`n$(Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue)`nstderr:`n$(Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)"
            $url | Should -Not -BeNullOrEmpty -Because $why
            $page = InModuleScope Lotus -Parameters @{ Url = $url } { Get-LotusHttpText -Uri $Url -TimeoutSec 5 -NoProxy $true }
            $page | Should -Match '<title>.*Lotus</title>' -Because $why
            $page | Should -Match 'editor\.js'
            # the picture, upright, for the browser
            $img = InModuleScope Lotus -Parameters @{ Url = "$($url)image" } { Get-LotusHttpStatus -Uri $Url -NoProxy $true }
            $img.StatusCode | Should -Be 200
            $img.Headers['Content-Type'] | Should -Be 'image/png'
            # a page of another address does not get it: not without the secret in the address, not as another host name
            (InModuleScope Lotus -Parameters @{ Url = (($url -replace '/[A-Za-z0-9_-]+/$', '/not-the-secret/') + 'image') } { (Get-LotusHttpStatus -Uri $Url -NoProxy $true).StatusCode }) | Should -Be 404
            # Cancel (what the page sends) ends the editor: it says nothing was saved and leaves with 0
            $quit = InModuleScope Lotus -Parameters @{ Url = "$($url)api/quit" } { Get-LotusHttpStatus -Uri $Url -Method POST -Headers @{ 'X-Lotus-Edit' = '1' } -NoProxy $true }
            $quit.StatusCode | Should -Be 200
            $server.WaitForExit(30000) | Should -BeTrue -Because 'the editor ends after Cancel'
            $server.WaitForExit()
            $server.ExitCode | Should -Be 0 -Because $why
            (Get-Content -LiteralPath $out -Raw -Encoding UTF8) | Should -Match 'nothing was saved'
        } finally {
            if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $was[$n]) }
        }
        # the working folder of the editor is gone with it
        $left = @(Get-ChildItem -LiteralPath (Join-Path $env:LOTUS_CACHE 'img/edit') -Directory -ErrorAction SilentlyContinue)
        $left.Count | Should -Be 0
    }
}

Describe 'the editor program, on this system' -Skip:(-not $script:HasPython) {
    It '<_> passes' -ForEach 'page_test.py', 'engine_test.py', 'server_test.py' {
        $name = $_
        $r = Invoke-EditProgram $script:Py.Exe (@($script:Py.Args) + @('-B', '-X', 'utf8', (Join-Path $script:Ctx.Repo "tests/edit/$name"))) $name
        $r.Rc | Should -Be 0 -Because $r.Out
        $r.Out | Should -Not -Match '✗' -Because $r.Out
        $r.Out | Should -Match '✓|skipped'
    }
}

Describe 'the geometry of the crop, on this system' -Skip:(-not $script:HasNode) {
    It 'passes in Node – the same pure functions the page runs in every browser' {
        $node = (Get-Command node -CommandType Application | Select-Object -First 1).Source
        $r = Invoke-EditProgram $node @((Join-Path $script:Ctx.Repo 'tests/edit/geometry.test.js')) 'geometry'
        $r.Rc | Should -Be 0 -Because $r.Out
        $r.Out | Should -Not -Match '✗' -Because $r.Out
        $r.Out | Should -Match '✓'
    }
}
