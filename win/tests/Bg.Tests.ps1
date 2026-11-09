# /bg on Windows (Public/bg.ps1): the screens, the models, the download with its checksum, the Python it picks and the
# events of the worker – with a stand-in for the worker (fixtures/fake-bg-worker.py: the same commands and events, no
# PyTorch) and a small list of models whose files are a few bytes, served from this disk. The real worker answers the
# commands that need no PyTorch. The real model run is the job "Remove BG on real Windows" of windows.yml.

BeforeDiscovery {
    $script:Py = $null
    foreach ($n in 'python3', 'python', 'py') {
        foreach ($c in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) {
            if ($c.Source -match '[\\/]WindowsApps[\\/]') { continue }
            $v = & $c.Source -c 'import sys; print(sys.version_info[0])' 2>$null
            if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq '3') { $script:Py = $c.Source; break }
        }
        if ($script:Py) { break }
    }
    $script:HasCurl = [bool](Get-Command curl -CommandType Application -ErrorAction SilentlyContinue)
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-bg'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    $script:Py = $null
    foreach ($n in 'python3', 'python', 'py') {
        foreach ($c in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) {
            if ($c.Source -match '[\\/]WindowsApps[\\/]') { continue }
            $v = & $c.Source -c 'import sys; print(sys.version_info[0])' 2>$null
            if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq '3') { $script:Py = $c.Source; break }
        }
        if ($script:Py) { break }
    }
    $script:Fake = Join-Path $PSScriptRoot 'fixtures/fake-bg-worker.py'
    $script:Srv = Join-Path $script:Ctx.Tmp 'srv'
    New-Item -ItemType Directory -Force -Path $script:Srv | Out-Null
    # three models of a few bytes each, downloaded from files on this disk
    $script:Reg = Join-Path $script:Ctx.Tmp 'bg-models.tsv'
    $rows = foreach ($m in @(@('birefnet', 'BiRefNet', 'model.safetensors'), @('birefnet-lite', 'BiRefNet Lite', 'model.safetensors'), @('inspyrenet', 'InSPyReNet', 'ckpt_base.pth'))) {
        $src = Join-Path $script:Srv "$($m[0]).bin"
        [IO.File]::WriteAllText($src, "weights of $($m[1]) – not really")
        $sha = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant()
        "$($m[0])`t$(if ($m[0] -eq 'inspyrenet') { 'inspyrenet' } else { 'birefnet' })`t$($m[1])`t1`t1024`tMIT`thttps://example.org`t$($m[2])|$([Uri]::new($src).AbsoluteUri)|$sha|$((Get-Item -LiteralPath $src).Length)"
    }
    [IO.File]::WriteAllText($script:Reg, "# test models`n" + ($rows -join "`n") + "`n")
    $script:Pics = Join-Path $script:Ctx.Tmp 'pictures'
    New-Item -ItemType Directory -Force -Path $script:Pics | Out-Null
    # a real PNG (one pixel) – the stand-in only copies it
    $script:PngBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
    function New-TestPicture { param([string]$Name, [string]$Dir = $script:Pics) $p = Join-Path $Dir $Name; [IO.File]::WriteAllBytes($p, $script:PngBytes); $p }

    # The module with the stand-ins: the small model list, the fake worker and this Python, a runtime that "is there"
    function Use-TestBg {
        param([switch]$RealWorker)
        InModuleScope Lotus -Parameters @{ Reg = $script:Reg; Worker = $(if ($RealWorker) { Join-Path $script:Ctx.Repo 'lib/bg/worker.py' } else { $script:Fake }); Py = $script:Py } {
            Initialize-Lotus
            Import-LotusCommand bg
            Import-LotusLangGroup bg
            $script:BgRegistryFile = $Reg
            $script:BgWorker = $Worker
            Set-Item function:script:Get-LotusBgPython ([scriptblock]::Create(", @('$($Py -replace "'", "''")', '-B')"))
            Set-Item function:script:Test-LotusBgRuntime { $true }
            Set-Item function:script:Test-LotusBgSystem { $true }
        }
    }
    function Set-TestModel {
        param([string]$Id)
        $dir = Join-Path $env:LOTUS_DATA "models/$Id"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $name = if ($Id -eq 'inspyrenet') { 'ckpt_base.pth' } else { 'model.safetensors' }
        Copy-Item -LiteralPath (Join-Path $script:Srv "$Id.bin") -Destination (Join-Path $dir $name) -Force
    }
    function Get-Plain { param([string]$Text) $Text -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '' }
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'Remove BG on Windows' {
    It 'explains itself in the words of this system – no Finder, no ⌘, no brew' {
        $out = Get-Plain (lotus bg help 6>&1 | Out-String)
        $out | Should -Match '/bg remove <image>'
        $out | Should -Match '/bg paste'
        $out | Should -Not -Match 'Finder|⌘|brew |xcode|\bMac\b|--edit'
    }

    It 'knows which models are here – by their names and sizes' {
        Use-TestBg
        Set-TestModel 'birefnet'
        New-Item -ItemType Directory -Force -Path (Join-Path $env:LOTUS_DATA 'models/inspyrenet') | Out-Null
        $states = InModuleScope Lotus { @('birefnet', 'birefnet-lite', 'inspyrenet' | ForEach-Object { Get-LotusBgModelState $_ }) }
        $states | Should -Be @('ok', 'missing', 'partial')
        # Auto takes the model that is here before it downloads another
        InModuleScope Lotus { Get-LotusBgAutoModel } | Should -Be 'birefnet'
        Remove-Item -LiteralPath (Join-Path $env:LOTUS_DATA 'models') -Recurse -Force
        InModuleScope Lotus { Get-LotusBgAutoModel } | Should -Be 'birefnet-lite'
    }

    It 'downloads a model, checks its SHA-256 and puts it in place' -Skip:(-not $script:HasCurl) {
        Use-TestBg
        $ok = InModuleScope Lotus { Start-LotusBgUi 'test' @('download|Downloading', 'verify|Checking'); try { Save-LotusBgModel 'birefnet-lite' } finally { Stop-LotusBgUi } }
        $ok | Should -BeTrue
        InModuleScope Lotus { Get-LotusBgModelState 'birefnet-lite' } | Should -Be 'ok'
        @(Get-ChildItem -LiteralPath (Join-Path $env:LOTUS_DATA 'models/birefnet-lite') -Filter '*.part') | Should -BeNullOrEmpty
    }

    It 'keeps nothing of a download that does not match its SHA-256' -Skip:(-not $script:HasCurl) {
        Use-TestBg
        [IO.File]::AppendAllText((Join-Path $script:Srv 'inspyrenet.bin'), ' – changed on the way')
        try {
            $r = InModuleScope Lotus { Start-LotusBgUi 'test' @('download|Downloading', 'verify|Checking'); try { @((Save-LotusBgModel 'inspyrenet'), $script:Bg.Err[0]) } finally { Stop-LotusBgUi } }
            $r[0] | Should -BeFalse
            $r[1] | Should -Be 'BG-009'
            @(Get-ChildItem -LiteralPath (Join-Path $env:LOTUS_DATA 'models/inspyrenet') -File) | Should -BeNullOrEmpty
        } finally {
            [IO.File]::WriteAllText((Join-Path $script:Srv 'inspyrenet.bin'), 'weights of InSPyReNet – not really')
        }
    }

    It 'cuts out one image – for a script, the path of the PNG is the output' -Skip:(-not $script:Py) {
        Use-TestBg
        Set-TestModel 'birefnet-lite'
        $outDir = Join-Path $script:Ctx.Tmp 'cut-outs'
        lotus settings set LOTUS_BG_READY 1 | Out-Null
        lotus settings set LOTUS_BG_OUTPUT $outDir | Out-Null
        $img = New-TestPicture 'portrait.png'
        $got = @(lotus bg remove $img 6>$null)
        $LASTEXITCODE | Should -Be 0
        $got.Count | Should -Be 1
        $got[0] | Should -Be (Join-Path $outDir 'portrait_no_bg.png')
        Test-Path -LiteralPath $got[0] | Should -BeTrue
        Test-Path -LiteralPath $img | Should -BeTrue
    }

    It 'a folder: every image in it, not the cut-outs made before – next to the originals with --here' -Skip:(-not $script:Py) {
        Use-TestBg
        Set-TestModel 'birefnet-lite'
        lotus settings set LOTUS_BG_READY 1 | Out-Null
        $dir = Join-Path $script:Ctx.Tmp 'shoot'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        New-TestPicture 'a.png' $dir | Out-Null
        New-TestPicture 'b.jpg' $dir | Out-Null
        New-TestPicture 'a_no_bg.png' $dir | Out-Null
        $got = @(lotus bg remove --here $dir 6>$null)
        $LASTEXITCODE | Should -Be 0
        @($got | ForEach-Object { Split-Path -Leaf $_ }) | Should -Be @('a_no_bg_2.png', 'b_no_bg.png')
    }

    It 'a picture it cannot read: the error with its code and what helps here' -Skip:(-not $script:Py) {
        Use-TestBg
        Set-TestModel 'birefnet-lite'
        lotus settings set LOTUS_BG_READY 1 | Out-Null
        $img = New-TestPicture 'broken.png'
        $out = Get-Plain (lotus bg remove $img *>&1 | Out-String)
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'This image could not be read'
        $out | Should -Match 'BG-005'
        $out | Should -Match 'opens in Photos'
        $out | Should -Not -Match 'Preview'
    }

    It 'a batch goes on past a picture it cannot read' -Skip:(-not $script:Py) {
        Use-TestBg
        Set-TestModel 'birefnet-lite'
        lotus settings set LOTUS_BG_READY 1 | Out-Null
        $dir = Join-Path $script:Ctx.Tmp 'mixed'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        New-TestPicture 'broken.png' $dir | Out-Null
        New-TestPicture 'fine.png' $dir | Out-Null
        $all = @(lotus bg remove --here $dir *>&1)
        $LASTEXITCODE | Should -Be 0
        @($all | Where-Object { $_ -is [string] -and $_ -like '*fine_no_bg.png' }).Count | Should -Be 1
        (Get-Plain ($all | Out-String)) | Should -Match 'skipped: .*broken\.png'
    }

    It 'installs a missing model after a yes: what it downloads, from where, then a test run' -Skip:(-not ($script:Py -and $script:HasCurl)) {
        Use-TestBg
        Remove-Item -LiteralPath (Join-Path $env:LOTUS_DATA 'models/birefnet') -Recurse -Force -ErrorAction SilentlyContinue
        $out = Get-Plain (Invoke-LotusWithKeys @('y') { Install-LotusBg 'birefnet' })
        $out | Should -Match 'What Lotus downloads'
        $out | Should -Match 'BiRefNet\s+1 MB'
        $out | Should -Match 'Downloading BiRefNet'
        $out | Should -Match 'Fake Lite is ready \(CPU, 0\.42s\)'
        InModuleScope Lotus { Get-LotusBgModelState 'birefnet' } | Should -Be 'ok'
        InModuleScope Lotus { $script:S['LOTUS_BG_READY'] } | Should -Be '1'
    }

    It 'shows the result in a window: open, show the folder, discard – a discarded PNG is gone' -Skip:(-not $script:Py) {
        Use-TestBg
        Set-TestModel 'birefnet-lite'
        lotus settings set LOTUS_BG_READY 1 | Out-Null
        $outDir = Join-Path $script:Ctx.Tmp 'shown'
        lotus settings set LOTUS_BG_OUTPUT $outDir | Out-Null
        $img = New-TestPicture 'cat.png'
        $out = Get-Plain (Invoke-LotusWithKeys @('d', 'y', 'q') -ScriptBlock ([scriptblock]::Create("Initialize-Lotus; Invoke-Lotusbg 'bg' @('remove', '$($img -replace "'", "''")')")))
        $out | Should -Match 'Background removed'
        $out | Should -Match 'Transparent PNG created'
        $out | Should -Match 'Fake Lite'
        $out | Should -Match 'd discard'
        $out | Should -Not -Match 'Finder'
        $out | Should -Match 'discarded'
        Test-Path -LiteralPath (Join-Path $outDir 'cat_no_bg.png') | Should -BeFalse
        Test-Path -LiteralPath $img | Should -BeTrue
    }

    It 'asks the worker to stop with a file – no signal Windows does not have, and no wait on its input' -Skip:(-not $script:Py) {
        Use-TestBg
        $r = InModuleScope Lotus -Parameters @{ Fake = $script:Fake; Tmp = $script:Ctx.Tmp } {
            $py = Get-LotusBgPython
            $cancel = Join-Path $Tmp 'cancel-test'
            $p = Start-LotusBgProcess $py[0] @('-B', $Fake, 'run', '--model', 'x', '--models-dir', '.', '--session', '.', '--out', '.', 'slow.png') @{ LOTUS_BG_CANCEL = $cancel; FAKE_BG_SLOW = '1' }
            $seen = $false
            while (-not $seen) { $l = $p.StandardOutput.ReadLine(); if ($null -eq $l) { break }; if ($l -eq "stage`tsegment") { $seen = $true } }
            $t0 = [datetime]::UtcNow
            Stop-LotusBgProc $p $cancel
            @($seen, $p.HasExited, $p.ExitCode, ([datetime]::UtcNow - $t0).TotalSeconds)
        }
        $r[0] | Should -BeTrue
        $r[1] | Should -BeTrue
        $r[2] | Should -Be 130
        $r[3] | Should -BeLessThan 3
    }

    It 'the real worker never waits on its input: a thread of its own watches the file' -Skip:(-not $script:Py) {
        # (a thread that read stdin made Windows hold up the import of PyTorch: every other question about that handle
        # waited for it – the self-test hung on GitHub's Windows machine)
        $code = Get-Content -Raw (Join-Path $script:Ctx.Repo 'lib/bg/worker.py')
        $code | Should -Not -Match 'sys\.stdin'
        $code | Should -Match 'LOTUS_BG_CANCEL'
    }

    It 'draws the blooming lotus: the title, the step, the flower, the keys' {
        Use-TestBg
        $out = InModuleScope Lotus {
            Start-LotusBgUi 'Remove BG' @('load_model|Loading BiRefNet Lite', 'segment|Finding the subject')
            $script:Bu.Live = $true
            Import-LotusBloom
            try {
                & {
                    Set-LotusBgStage 'segment'
                    Set-LotusBgInfo model 'BiRefNet Lite'
                    for ($i = 0; $i -lt 3; $i++) { Show-LotusBgFrame }
                    $script:Bu.Finished = $true
                    Show-LotusBgFrame
                } *>&1 | Out-String
            } finally { Stop-LotusBgUi }
        }
        $plain = Get-Plain $out
        $plain | Should -Match 'lotus / Remove BG'
        $plain | Should -Match 'Finding the subject'
        $plain | Should -Match 'Done'
        $plain | Should -Match 'BiRefNet Lite'
        $plain | Should -Match 'ctrl-c cancels'
        $out | Should -Match '[▀▄█]'
    }

    It 'finds a Python for the runtime – never the one of the Microsoft Store' {
        $store = Join-Path $script:Ctx.Tmp 'WindowsApps'
        $other = Join-Path $script:Ctx.Tmp 'py312'
        New-Item -ItemType Directory -Force -Path $store, $other | Out-Null
        if ($IsWindows) {
            [IO.File]::WriteAllText((Join-Path $store 'python3.cmd'), "@echo 3.13 AMD64`r`n")
            [IO.File]::WriteAllText((Join-Path $other 'python.cmd'), "@echo 3.12 AMD64`r`n")
        } else {
            foreach ($f in @(@((Join-Path $store 'python3'), '3.13 x86_64'), @((Join-Path $other 'python'), '3.12 x86_64'))) {
                [IO.File]::WriteAllText($f[0], "#!/bin/sh`necho $($f[1])`n")
                & chmod +x $f[0]
            }
        }
        $path = $env:PATH
        try {
            $env:PATH = "$store$([IO.Path]::PathSeparator)$other"
            $py = InModuleScope Lotus { Import-LotusCommand bg; Find-LotusBgPython }
        } finally { $env:PATH = $path }
        $py.Version | Should -Be '3.12'
        $py.Exe | Should -Match 'py312'
    }

    It 'the real worker runs here: its events, and the memory of this computer' -Skip:(-not $script:Py) {
        Use-TestBg -RealWorker
        $lines = InModuleScope Lotus -Parameters @{ Models = (Join-Path $script:Ctx.Tmp 'no-models') } {
            $script:BgRegistryFile = Join-Path (Get-LotusRoot) 'data/bg-models.tsv'
            @(Get-LotusBgWorkerLines @('check', '--models-dir', $Models)) + @('--') + @(Get-LotusBgWorkerLines @('probe'))
        }
        $lines | Should -Contain "model`tbirefnet`tmissing`t"
        $lines | Should -Contain "end`t0"
        # (probe stops at PyTorch, which is not here – after the memory, which Windows gives without sysconf)
        $mem = $lines | Where-Object { $_ -like "info`tmemory`t*" } | Select-Object -First 1
        $mem | Should -Not -BeNullOrEmpty
        [long]($mem -split "`t")[2] | Should -BeGreaterThan 100MB
    }

    It 'on Windows on Arm it says why it cannot run, before anything is downloaded' -Skip:(-not $IsWindows) {
        $out = InModuleScope Lotus {
            Initialize-Lotus
            Import-LotusCommand bg
            Remove-Item function:script:Test-LotusBgSystem -ErrorAction SilentlyContinue
            . (Join-Path $script:LotusModuleRoot 'Public/bg.ps1')
            $arch = $script:Os.Arch
            $script:Os.Arch = 'arm64'
            try { Invoke-Lotusbg 'bg' @('remove', 'x.png') *>&1 | Out-String } finally { $script:Os.Arch = $arch }
        }
        $plain = Get-Plain $out
        $plain | Should -Match 'BG-008'
        $plain | Should -Match 'x64'
    }
}
