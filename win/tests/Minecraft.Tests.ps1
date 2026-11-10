# /minecraft on Windows (Public/minecraft.ps1, Public/mcc.ps1, mc/run.ps1): the files of a new server, the runner in
# the background with a server of its own (fixtures/FakeServer.java, built here with javac: the lines a Minecraft
# server prints, a few console commands), the control center with keys, deleting, plugins from a Modrinth on this
# computer (tests/fake-modrinth.py), the little world and finding Java. The real server is the job "Minecraft on real
# Windows" of windows.yml.

BeforeDiscovery {
    $script:HasJdk = [bool]((Get-Command javac -CommandType Application -ErrorAction SilentlyContinue) -and (Get-Command java -CommandType Application -ErrorAction SilentlyContinue))
    $script:Py = $null
    foreach ($n in 'python3', 'python') {
        foreach ($c in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) {
            if ($c.Source -match '[\\/]WindowsApps[\\/]') { continue }
            $v = & $c.Source -c 'import sys; print(sys.version_info[0])' 2>$null
            if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq '3') { $script:Py = $c.Source; break }
        }
        if ($script:Py) { break }
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-mc'
    $script:McHomeWas = $env:LOTUS_MC_HOME
    $env:LOTUS_MC_HOME = Join-Path $script:Ctx.Tmp 'Minecraft'
    New-Item -ItemType Directory -Force -Path $env:LOTUS_MC_HOME | Out-Null
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    $script:Py = $null
    foreach ($n in 'python3', 'python') {
        foreach ($c in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) {
            if ($c.Source -match '[\\/]WindowsApps[\\/]') { continue }
            $v = & $c.Source -c 'import sys; print(sys.version_info[0])' 2>$null
            if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq '3') { $script:Py = $c.Source; break }
        }
        if ($script:Py) { break }
    }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    # a zip (a .jar) with these files: @{ name = text }
    function New-TestJar {
        param([string]$Path, [hashtable]$Files)
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        $z = [System.IO.Compression.ZipFile]::Open($Path, 'Create')
        try {
            foreach ($k in $Files.Keys) {
                $e = $z.CreateEntry($k)
                $s = $e.Open()
                try { $b = if ($Files[$k] -is [byte[]]) { $Files[$k] } else { [Text.Encoding]::UTF8.GetBytes([string]$Files[$k]) }; $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
            }
        } finally { $z.Dispose() }
    }
    # the server of the tests: FakeServer.java built into a server.jar
    $script:ServerJar = $null
    $javac = Get-Command javac -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($javac) {
        $classes = Join-Path $script:Ctx.Tmp 'fake-classes'
        New-Item -ItemType Directory -Force -Path $classes | Out-Null
        & $javac.Source -d $classes (Join-Path $PSScriptRoot 'fixtures/FakeServer.java') 2>$null
        $script:ServerJar = Join-Path $script:Ctx.Tmp 'fake-server.jar'
        New-TestJar $script:ServerJar @{ 'META-INF/MANIFEST.MF' = "Manifest-Version: 1.0`r`nMain-Class: FakeServer`r`n`r`n"; 'FakeServer.class' = [IO.File]::ReadAllBytes((Join-Path $classes 'FakeServer.class')) }
        # the Java home of that javac (its java runs the server)
        $script:JavaHome = Split-Path -Parent (Split-Path -Parent ((Get-Item -LiteralPath $javac.Source).ResolvedTarget ?? $javac.Source))
        if (-not (Test-Path -LiteralPath (Join-Path $script:JavaHome 'bin'))) { $script:JavaHome = Split-Path -Parent (Split-Path -Parent $javac.Source) }
    }
    # a new server folder in the test's Minecraft folder, made as the setup makes it
    function New-TestServer {
        param([string]$Name, [bool]$Eula = $true)
        $path = Join-Path $env:LOTUS_MC_HOME $Name
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        if ($script:ServerJar) { Copy-Item -LiteralPath $script:ServerJar -Destination (Join-Path $path 'server.jar') -Force }
        InModuleScope Lotus -Parameters @{ Dir = $path; JavaHome = $script:JavaHome; Eula = $Eula } {
            Initialize-Lotus
            Import-LotusCommand minecraft
            Write-LotusMcServerFiles $Dir 'vanilla' '1.21.4' $JavaHome '256M' $Eula 'Grüße aus Lotus ✓' 10 'easy'
        }
        $path
    }
    # the server of a folder stopped and its runner ended (after a test that left it running)
    function Stop-TestServer {
        param([string]$Dir)
        InModuleScope Lotus -Parameters @{ Dir = $Dir } {
            Initialize-LotusMcc $Dir
            Update-LotusMccProbe
            if ($script:Mcc.State -cnotin 'stopped', 'crashed') {
                Stop-LotusMccServer
                for ($i = 0; $i -lt 100 -and $script:Mcc.State -cnotin 'stopped', 'crashed'; $i++) { Start-Sleep -Milliseconds 200; Update-LotusMccProbe }
            }
            Close-LotusMccLog
        }
    }
    function Get-Plain { param([string]$Text) $Text -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '' }
}

AfterAll {
    foreach ($d in @(Get-ChildItem -LiteralPath $env:LOTUS_MC_HOME -Directory -ErrorAction SilentlyContinue)) { try { Stop-TestServer $d.FullName } catch { } }
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    $env:LOTUS_MC_HOME = $script:McHomeWas
    Restore-LotusTestEnv $script:Ctx
}

Describe 'A Minecraft server on Windows' {
    It 'is made of its files: the EULA, server.properties with the description as Java writes it, start.cmd with its java' {
        $dir = New-TestServer 'files'
        (Get-Content -Raw (Join-Path $dir 'eula.txt')) | Should -Match 'eula=true'
        $props = Get-Content -Raw (Join-Path $dir 'server.properties')
        $props | Should -Match 'motd=Gr\\u00fc\\u00dfe aus Lotus \\u2713'
        $props | Should -Match 'max-players=10'
        $props | Should -Match 'difficulty=easy'
        $sc = Get-Content -Raw (Join-Path $dir 'start.cmd')
        $sc | Should -Match 'cd /d "%~dp0"'
        $sc | Should -Match '-Xms256M -Xmx256M -jar "%~dp0server.jar" nogui'
        (Get-Content -Raw (Join-Path $dir '.lotus/server.conf')) | Should -Match 'type=vanilla'
        InModuleScope Lotus -Parameters @{ Dir = $dir } { Initialize-LotusMcc $Dir; Get-LotusMccMotd } | Should -Be 'Grüße aus Lotus ✓'
    }

    It 'runs in the background: ready, commands with umlauts, a player joins, stop saves and ends with 0' -Skip:(-not $script:HasJdk) {
        $dir = New-TestServer 'background'
        $r = InModuleScope Lotus -Parameters @{ Dir = $dir } {
            Initialize-LotusMcc $Dir
            $m = $script:Mcc
            $started = Start-LotusMccServer
            for ($i = 0; $i -lt 150 -and $m.State -cne 'running'; $i++) { Start-Sleep -Milliseconds 200; Read-LotusMccLog; Update-LotusMccProbe }
            $running = $m.State
            [void](Send-LotusMccCommand 'join Steve')
            [void](Send-LotusMccCommand 'say Grüße aus Lotus')
            for ($i = 0; $i -lt 50 -and -not $m.POrder.Count; $i++) { Start-Sleep -Milliseconds 100; Read-LotusMccLog }
            $players = @($m.POrder)
            Update-LotusMccSample
            $rss = $m.Rss
            Stop-LotusMccServer
            for ($i = 0; $i -lt 150 -and $m.State -cnotin 'stopped', 'crashed'; $i++) { Start-Sleep -Milliseconds 200; Read-LotusMccLog; Update-LotusMccProbe }
            Close-LotusMccLog
            [pscustomobject]@{ Started = $started; Running = $running; Players = $players; Rss = $rss; State = $m.State; Exit = $m.Exit; Events = @($m.Events) }
        }
        $r.Started | Should -BeTrue
        $r.Running | Should -Be 'running'
        $r.Players | Should -Be @('Steve')
        $r.Rss | Should -BeGreaterThan 0
        $r.State | Should -Be 'stopped'
        $r.Exit | Should -Be 0
        ($r.Events -join "`n") | Should -Match 'Steve'
        $log = Get-Content -Raw -Encoding utf8 (Join-Path $dir '.lotus/console.log')
        $log | Should -Match '\[Lotus\] > say Grüße aus Lotus'
        $log | Should -Match '\[Server\] Grüße aus Lotus'
        $log | Should -Match 'The server stopped \(exit code 0\)'
        Test-Path -LiteralPath (Join-Path $dir '.lotus/pid') | Should -BeFalse
    }

    It 'without the EULA it does not start, and asks for it' {
        $dir = New-TestServer 'no-eula' $false
        $r = InModuleScope Lotus -Parameters @{ Dir = $dir } { Initialize-LotusMcc $Dir; @((Start-LotusMccServer), $script:Mcc.Ask, $script:Mcc.Problem) }
        $r[0] | Should -BeFalse
        $r[1] | Should -Be 'eula'
        $r[2] | Should -Be 'eula'
    }

    It 'the control center with keys: the stats, the settings, the log – and leaving keeps the server running' -Skip:(-not $script:HasJdk) {
        $dir = New-TestServer 'window'
        $out = Get-Plain (Invoke-LotusWithKeys @('tab', 'tab', 'q', 'enter') -ScriptBlock ([scriptblock]::Create("Initialize-Lotus; Import-LotusCommand minecraft; Invoke-LotusMcc '$($dir -replace "'", "''")'")))
        try {
            $out | Should -Match 'lotus / Minecraft  ·  window'
            $out | Should -Match '1  Stats   2  Settings   3  Log'
            $out | Should -Match 'Grüße aus Lotus'
            $out | Should -Match 'CONSOLE'
            $out | Should -Match 'Leave the control center\? The server keeps running\.'
            $out | Should -Match 'keeps running in the background'
            $out | Should -Not -Match 'Finder|Trash|start\.command'
            [int]("0" + (Get-Content -Raw (Join-Path $dir '.lotus/wrapper') -ErrorAction SilentlyContinue)).Trim() | Should -BeGreaterThan 0
        } finally { Stop-TestServer $dir }
    }

    It 'deletes only a server folder right in the Minecraft folder, and only by its exact name' {
        $dir = New-TestServer 'to-delete'
        $r = InModuleScope Lotus -Parameters @{ Dir = $dir; McHome = $env:LOTUS_MC_HOME } {
            Initialize-Lotus; Import-LotusCommand minecraft
            @((Test-LotusMccCanDelete $Dir), (Test-LotusMccCanDelete $McHome), (Test-LotusMccCanDelete (Split-Path -Parent $McHome)))
        }
        $r | Should -Be @($true, $false, $false)
        # a wrong name deletes nothing
        $out = Get-Plain (Invoke-LotusWithKeys @('n', 'o', 'p', 'e', 'enter') -ScriptBlock ([scriptblock]::Create("Initialize-Lotus; Import-LotusCommand minecraft; Remove-LotusMcServer '$($dir -replace "'", "''")'")))
        $out | Should -Match 'That was not the name – nothing was deleted'
        Test-Path -LiteralPath $dir | Should -BeTrue
        if ($IsWindows) {
            $out = Get-Plain (Invoke-LotusWithKeys @('t', 'o', '-', 'd', 'e', 'l', 'e', 't', 'e', 'enter') -ScriptBlock ([scriptblock]::Create("Initialize-Lotus; Import-LotusCommand minecraft; Remove-LotusMcServer '$($dir -replace "'", "''")'")))
            $out | Should -Match 'Recycle Bin'
            Test-Path -LiteralPath $dir | Should -BeFalse
        }
    }

    It 'never deletes a link to a folder, even one with a start.cmd' -Skip:(-not $IsWindows) {
        $real = Join-Path $script:Ctx.Tmp 'elsewhere'
        New-Item -ItemType Directory -Force -Path $real | Out-Null
        Set-Content -LiteralPath (Join-Path $real 'start.cmd') -Value '@echo off'
        $link = Join-Path $env:LOTUS_MC_HOME 'linked'
        New-Item -ItemType Junction -Path $link -Target $real | Out-Null
        try { InModuleScope Lotus -Parameters @{ Dir = $link } { Initialize-Lotus; Import-LotusCommand minecraft; Test-LotusMccCanDelete $Dir } | Should -BeFalse }
        finally { [IO.Directory]::Delete($link) }
        Test-Path -LiteralPath (Join-Path $real 'start.cmd') | Should -BeTrue
    }

    It 'keeps a description with umlauts and emoji as \u in server.properties, and reads it back' {
        $dir = New-TestServer 'props'
        $r = InModuleScope Lotus -Parameters @{ Dir = $dir } {
            Initialize-LotusMcc $Dir
            Set-LotusMccProp 'motd' 'Grüne Wiese 🌿 \ §aBunt'
            @((Get-Content -Raw (Join-Path $Dir 'server.properties')), (Get-LotusMccMotd))
        }
        $r[0] | Should -Match 'motd=Gr\\u00fcne Wiese \\ud83c\\udf3f \\\\ \\u00a7aBunt'
        $r[0] | Should -Match 'max-players=10'
        $r[1] | Should -Be 'Grüne Wiese 🌿 \ Bunt'
    }

    It 'draws the little world: as wide and high as asked, and the grass block as the icon' {
        $r = InModuleScope Lotus {
            Initialize-Lotus; Import-LotusCommand minecraft
            $plain = { param($l) ($l -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '').Length }
            $a = Get-LotusMcWorldFrame 40 8 0 $true
            Start-Sleep -Milliseconds 300
            $b = Get-LotusMcWorldFrame 40 8 3 $true
            $icon = @(Get-LotusMcWorldIcon)
            @($a.Count, (@($a | ForEach-Object { & $plain $_ }) | Sort-Object -Unique), $b.Count, $icon.Count, (@($icon | ForEach-Object { & $plain $_ }) | Sort-Object -Unique))
        }
        $r[0] | Should -Be 8
        $r[1] | Should -Be 40
        $r[2] | Should -Be 8
        $r[3] | Should -Be 6
        $r[4] | Should -Be 12
    }

    It 'speaks of Windows in its guide: Windows Defender Firewall, no macOS' {
        $out = Get-Plain (InModuleScope Lotus { Initialize-Lotus; Import-LotusCommand minecraft; Show-LotusMcGuide } 6>&1 | Out-String)
        $out | Should -Match 'Windows Defender Firewall'
        $out | Should -Match 'forward TCP port 25565'
        $out | Should -Not -Match 'macOS|System Settings|Mac\b'
    }

    It 'finds Java by its release file – JAVA_HOME first when it is new enough' {
        $j = Join-Path $script:Ctx.Tmp 'jdks'
        foreach ($v in '17.0.9', '99.0.1') {
            $h = Join-Path $j "jdk-$v"
            New-Item -ItemType Directory -Force -Path (Join-Path $h 'bin') | Out-Null
            Set-Content -LiteralPath (Join-Path $h $(if ($IsWindows) { 'bin/java.exe' } else { 'bin/java' })) -Value ''
            Set-Content -LiteralPath (Join-Path $h 'release') -Value "JAVA_VERSION=`"$v`""
        }
        $was = $env:JAVA_HOME
        try {
            $env:JAVA_HOME = Join-Path $j 'jdk-17.0.9'
            $r = InModuleScope Lotus -Parameters @{ J = $j } {
                Initialize-Lotus; Import-LotusCommand minecraft
                $env:JAVA_HOME = Join-Path $J 'jdk-17.0.9'
                $a = Find-LotusJava 17
                $env:JAVA_HOME = Join-Path $J 'jdk-99.0.1'
                $b = Find-LotusJava 99
                $env:JAVA_HOME = Join-Path $J 'jdk-17.0.9'
                $c = Find-LotusJava 99
                @($a, $b, $c, (Get-LotusJavaLabel $a))
            }
        } finally { $env:JAVA_HOME = $was }
        $r[0] | Should -Match 'jdk-17\.0\.9$'
        $r[1] | Should -Match 'jdk-99\.0\.1$'
        $r[2] | Should -BeNullOrEmpty
        $r[3] | Should -Match 'Java 17\.0\.9'
    }
}

Describe 'Plugins for a Paper server' -Skip:(-not $script:Py) {
    BeforeAll {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $script:Port = $l.LocalEndpoint.Port; $l.Stop()
        $script:Fake = Start-Process -FilePath $script:Py -ArgumentList @((Join-Path $script:Ctx.Repo 'tests/fake-modrinth.py'), $script:Port) -PassThru -NoNewWindow
        for ($i = 0; $i -lt 50; $i++) {
            try { $c = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $script:Port); $c.Dispose(); break } catch { Start-Sleep -Milliseconds 100 }
        }
        $script:PDir = Join-Path $env:LOTUS_MC_HOME 'paper-plugins'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:PDir '.lotus') | Out-Null
        InModuleScope Lotus -Parameters @{ Port = $script:Port } {
            Initialize-Lotus; Import-LotusCommand minecraft
            $script:McpApi = "http://127.0.0.1:$Port/v2"
            $script:McpCdn = "http://127.0.0.1:$Port/files/"
            $script:McpHttp = $null
        }
    }
    AfterAll {
        if ($script:Fake -and -not $script:Fake.HasExited) { $script:Fake.Kill() }
        InModuleScope Lotus { $script:McpApi = 'https://api.modrinth.com/v2'; $script:McpCdn = 'https://cdn.modrinth.com/'; $script:McpHttp = $null }
    }

    It 'searches Modrinth for the server version and reads the results' {
        $r = InModuleScope Lotus {
            $t = Start-LotusMcSearch '' '1.21.4' 0
            for ($i = 0; $i -lt 100 -and -not $t.IsCompleted; $i++) { Start-Sleep -Milliseconds 50 }
            Read-LotusMcSearch $t
        }
        $r.Total | Should -Be 42
        @($r.Hits).Count | Should -Be 2
        $r.Hits[0].Title | Should -Be 'Good Plugin'
        $r.Hits[0].About | Should -Be 'Does good things well'
        InModuleScope Lotus { Format-LotusMcCount 1234567 } | Should -Be '1.2M'
    }

    It 'installs with the SHA-512 checked, a dependency comes along, and removes again' {
        $r = InModuleScope Lotus -Parameters @{ Dir = $script:PDir } {
            $script:McpDone = [System.Collections.Generic.List[string]]::new(); $script:McpErr = ''
            $a = Install-LotusMcPlugin $Dir 'good' 'good-plugin' 'Good Plugin' '1.21.4'
            $b = Install-LotusMcPlugin $Dir 'needsdep' 'needs-dep' 'Needs Dep' '1.21.4'
            $done = @($script:McpDone)
            $c = Install-LotusMcPlugin $Dir 'broken' 'broken' 'Broken' '1.21.4'
            $err = $script:McpErr
            $files = @(Get-ChildItem -LiteralPath (Join-Path $Dir 'plugins') -File | ForEach-Object Name | Sort-Object)
            $mine = Get-LotusMcPluginsMine $Dir
            $removed = Remove-LotusMcPlugin $Dir 'good.jar'
            @($a, $b, $c, ($done -join ', '), $err, ($files -join ','), (@($mine.Keys | Sort-Object) -join ','), $removed, (Test-Path -LiteralPath (Join-Path $Dir 'plugins/good.jar')))
        }
        $r[0] | Should -BeTrue
        $r[1] | Should -BeTrue
        $r[2] | Should -BeFalse
        $r[3] | Should -Match 'Good Plugin'
        $r[3] | Should -Match 'Needs Dep'
        $r[4] | Should -Match 'checksum mismatch – nothing was installed'
        $r[5] | Should -Be 'dep.jar,good.jar,needsdep.jar'
        $r[6] | Should -Be 'dep,good,needsdep'
        $r[7] | Should -BeTrue
        $r[8] | Should -BeFalse
    }

    It 'takes a .jar of your own when it is a plugin – not a Fabric mod' {
        $own = Join-Path $script:Ctx.Tmp 'MyPlugin.jar'
        New-TestJar $own @{ 'plugin.yml' = "name: MyPlugin`nversion: '2.1'`nmain: my.Plugin`n" }
        $mod = Join-Path $script:Ctx.Tmp 'SomeMod.jar'
        New-TestJar $mod @{ 'fabric.mod.json' = '{}' }
        $r = InModuleScope Lotus -Parameters @{ Dir = $script:PDir; Own = $own; Mod = $mod } {
            $a = Add-LotusMcPluginJars $Dir "`"$Own`""
            $done = @($script:McpDone) -join ','
            $b = Add-LotusMcPluginJars $Dir "`"$Mod`""
            $err = $script:McpErr
            $inst = @(Get-LotusMcPluginsInstalled $Dir | Where-Object { $_.File -eq 'MyPlugin.jar' })
            @($a, $done, $b, $err, $inst[0].Name, $inst[0].Version, $inst[0].From)
        }
        $r[0] | Should -BeTrue
        $r[1] | Should -Be 'MyPlugin'
        $r[2] | Should -BeFalse
        $r[3] | Should -Match 'Fabric mod'
        $r[4] | Should -Be 'MyPlugin'
        $r[5] | Should -Be '2.1'
        $r[6] | Should -Be 'own'
    }
}
