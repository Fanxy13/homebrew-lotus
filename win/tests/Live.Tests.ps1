# /liveserver and /html on Windows (Public/live.ps1, Public/html.ps1): the Python of lib/live and lib/html, the same as
# on the Mac, started by PowerShell – a server in a process of its own that serves a folder and stops with lotus
# liveserver stop, and documents made from a small site. (tests/test-liveserver.zsh and test-html.zsh test the Python.)

BeforeDiscovery {
    # (the tests need a Python – the runners of the CI have one; a WindowsApps python.exe is only Windows' stand-in)
    $script:HasPython = [bool](@(Get-Command py, python3, python -CommandType Application -ErrorAction SilentlyContinue) | Where-Object { $_.Source -notmatch 'WindowsApps' })
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-live'
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    $script:Py = InModuleScope Lotus { Initialize-Lotus; Find-LotusPython }
    $script:Site = Join-Path $script:Ctx.Tmp 'my-site'
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Site 'css') | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Site 'index.html') -Value '<!doctype html><html><head><title>Hi</title><link rel="stylesheet" href="css/site.css"></head><body><h1>Hello</h1><p>Lotus on Windows.</p></body></html>'
    Set-Content -LiteralPath (Join-Path $script:Site 'about.html') -Value '<!doctype html><html><body><h2>About</h2><ul><li>one</li><li>two</li></ul></body></html>'
    Set-Content -LiteralPath (Join-Path $script:Site 'css/site.css') -Value 'body { color: #333; }'
    Set-Content -LiteralPath (Join-Path $script:Site '.env') -Value 'SECRET=1'
    $script:Pwsh = (Get-Process -Id $PID).Path
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'Python' {
    It 'is found when it really answers – 3.9 or newer' {
        $script:Py | Should -Not -BeNullOrEmpty
        $script:Py.Version | Should -Match '^3\.\d+$'
        [int]($script:Py.Version -split '\.')[1] | Should -BeGreaterOrEqual 9
        $script:Py.Exe | Should -Not -Match 'WindowsApps'
    }
}

Describe '/html' -Skip:(-not $script:HasPython) {
    BeforeEach { Push-Location $script:Site }
    AfterEach { Pop-Location }
    It 'all of a folder as text, into a folder of its own' {
        lotus html all txt | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $script:Site 'Text/index.html.txt') | Should -BeTrue
        Test-Path (Join-Path $script:Site 'Text/css/site.css.txt') | Should -BeTrue
        Get-Content (Join-Path $script:Site 'Text/index.html.txt') -Raw | Should -Match '<h1>Hello</h1>'
        Test-Path (Join-Path $script:Site 'Text/.env.txt') | Should -BeFalse
    }
    It 'one page as a Word document and as a PDF, next to it' {
        lotus html about.html docx --page | Out-Null
        $LASTEXITCODE | Should -Be 0
        $docx = Join-Path $script:Site 'about.docx'
        Test-Path $docx | Should -BeTrue
        $zip = [IO.Compression.ZipFile]::OpenRead($docx)
        try { $zip.Entries.FullName | Should -Contain 'word/document.xml' } finally { $zip.Dispose() }
        lotus html about.html pdf --page | Out-Null
        $pdf = Join-Path $script:Site 'about.pdf'
        # (as code a page keeps its own name in the document's: about.html.pdf)
        lotus html about.html pdf --code | Out-Null
        Test-Path (Join-Path $script:Site 'about.html.pdf') | Should -BeTrue
        Test-Path $pdf | Should -BeTrue
        [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pdf), 0, 5) | Should -Be '%PDF-'
    }
    It 'without a keyboard it says what it needs' {
        $out = lotus html 6>&1 | Out-String
        $out | Should -Match 'Which file\?|Into which format\?'
        $LASTEXITCODE | Should -Be 1
        (lotus html 'nothing-here.html' txt 6>&1 | Out-String) | Should -Match 'Not found: nothing-here.html'
    }
    It 'never your whole home folder' {
        Push-Location (InModuleScope Lotus { Get-LotusHome })
        try { lotus html all txt 6>&1 | Out-String | Should -Match 'your whole home folder' } finally { Pop-Location }
    }
}

Describe '/liveserver' -Skip:(-not $script:HasPython) {
    It 'serves the folder with the reload in its pages, keeps hidden files out, and stops with lotus liveserver stop' {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
        $module = (Resolve-Path (Join-Path $PSScriptRoot '../Lotus.psd1')).Path
        $cmd = "Import-Module '$module'; Set-Location '$($script:Site)'; lotus liveserver --no-open --port $port"
        $server = Start-Process -FilePath $script:Pwsh -ArgumentList @('-NoProfile', '-Command', $cmd) -PassThru -RedirectStandardOutput (Join-Path $script:Ctx.Tmp 'live.out') -RedirectStandardError (Join-Path $script:Ctx.Tmp 'live.err')
        try {
            # (the pages come through Lotus' own request: Invoke-WebRequest -NoProxy is PowerShell 7's, and Windows PowerShell 5.1
            # would look for a proxy first)
            $get = { param($Path) InModuleScope Lotus -Parameters @{ Url = "http://127.0.0.1:$port$Path" } { Get-LotusHttpText -Uri $Url -TimeoutSec 2 -NoProxy $true } }
            $page = $null
            $deadline = (Get-Date).AddSeconds(20)
            while (-not $page -and (Get-Date) -lt $deadline) {
                $page = & $get '/'
                if (-not $page) { Start-Sleep -Milliseconds 300 }
            }
            $page | Should -Not -BeNullOrEmpty -Because (Get-Content (Join-Path $script:Ctx.Tmp 'live.err') -Raw)
            $page | Should -Match '<h1>Hello</h1>'
            $page | Should -Match '/__lotus/reload.js'
            (& $get '/css/site.css') | Should -Match 'color'
            $hidden = InModuleScope Lotus -Parameters @{ Url = "http://127.0.0.1:$port/.env" } { (Get-LotusHttpStatus -Uri $Url -NoProxy $true).StatusCode }
            $hidden | Should -Not -Be 200
            # the note it left for stop and /html: in Lotus' state folder
            Test-Path (Join-Path $env:LOTUS_STATE "live/running/$port") | Should -BeTrue
            lotus liveserver stop 6>&1 | Out-String | Should -Match "Stopped http://127.0.0.1:$port"
            $server.WaitForExit(10000) | Should -BeTrue
        } finally {
            if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
        }
        (lotus liveserver stop 6>&1 | Out-String) | Should -Match 'No live server is running'
    }
}
