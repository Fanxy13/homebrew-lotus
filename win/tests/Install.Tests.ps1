# install.ps1 from start to end, into a temporary folder and a temporary profile (nothing of yours is touched). On
# Windows also: lotus.cmd in the user PATH (the PATH is put back as it was), cmd.exe running it, and Lotus' own pinned
# fastfetch – downloaded from GitHub and checked against data/vendor.tsv.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-install'
    # the installed copy has to find its files in its own folder, not in this checkout (the test kit points LOTUS_ROOT here)
    Remove-Item Env:LOTUS_ROOT -ErrorAction SilentlyContinue
    $script:Repo = $script:Ctx.Repo
    $script:Tmp = $script:Ctx.Tmp
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:Want = ((Get-Content (Join-Path $script:Repo 'lib/core.zsh') | Where-Object { $_ -match '^typeset -g LOTUS_VERSION=' } | Select-Object -First 1) -split '=')[1].Trim()
    # the installer in a PowerShell of its own, with these settings → what it said
    function Invoke-TestInstall {
        param([string]$Dest, [hashtable]$Env = @{})
        $vars = @{ LOTUS_SRC = $script:Repo; LOTUS_DEST = $Dest; LOTUS_PROFILE = (Join-Path $script:Tmp 'profile.ps1'); LOTUS_NO_PATH = '1'; LOTUS_NO_SETUP = '1'; LOTUS_FASTFETCH = 'no' }
        foreach ($k in $Env.Keys) { $vars[$k] = $Env[$k] }
        $saved = @{}
        foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
        try { & $script:Pwsh -NoProfile -NonInteractive -File (Join-Path $script:Repo 'install.ps1') 2>&1 | Out-String }
        finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
    }
    # The installer in Windows PowerShell with an execution policy that is made up: Get-ExecutionPolicy and Set-ExecutionPolicy are
    # functions in the window that runs it - they say what the policy is (Scope=Policy;…) and write down what the installer
    # sets (a Windows 11 that came out of the box is Restricted: the real one cannot be had on a machine that is in use)
    function Invoke-TestInstallPolicy {
        param([string]$Dest, [string]$Policies, [hashtable]$Env = @{})
        $wrapper = Join-Path $script:Tmp 'policy-wrapper.ps1'
        Set-Content -LiteralPath $wrapper -Encoding UTF8 -Value @'
$global:SetCalls = New-Object System.Collections.ArrayList
$pol = @{}
foreach ($p in ($env:TEST_POLICIES -split ';')) { if ($p) { $k, $v = $p -split '='; $pol[$k] = $v } }
function Get-ExecutionPolicy {
    [CmdletBinding()] param([switch]$List, [string]$Scope)
    $scopes = 'MachinePolicy', 'UserPolicy', 'Process', 'CurrentUser', 'LocalMachine'
    if ($List) { foreach ($s in $scopes) { [pscustomobject]@{ Scope = $s; ExecutionPolicy = $(if ($pol[$s]) { $pol[$s] } else { 'Undefined' }) } }; return }
    if ($Scope) { if ($pol[$Scope]) { return $pol[$Scope] } else { return 'Undefined' } }
    foreach ($s in $scopes) { if ($pol[$s] -and $pol[$s] -ne 'Undefined') { return $pol[$s] } }
    'Restricted'
}
function Set-ExecutionPolicy {
    [CmdletBinding()] param($ExecutionPolicy, $Scope, [switch]$Force)
    [void]$global:SetCalls.Add("$Scope=$ExecutionPolicy")
    if ($env:TEST_SETFAIL -eq '1' -and $Scope -eq 'CurrentUser') { throw 'Access to the registry key is denied.' }     # (it really did not work)
    $pol[[string]$Scope] = [string]$ExecutionPolicy
    if ($env:TEST_OVERRIDE -eq '1' -and $Scope -ne 'Process') {
        # what Windows PowerShell does when the window has a policy of its own (Process): the user's is set, and reported as an
        # error without a message of its own ("Security error."), the real one being in the details
        $err = [System.Management.Automation.ErrorRecord]::new([System.Security.SecurityException]::new(), 'ExecutionPolicyOverride', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        $err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Windows PowerShell updated your execution policy successfully, but the setting is overridden by a policy defined at a more specific scope.')
        $PSCmdlet.WriteError($err)
    }
}
function Read-Host { param($Prompt) '' }      # (nobody answers: the question gets a no, with a keyboard or without)
. $env:TEST_INSTALLER
'SET: ' + ($global:SetCalls -join ';')
'@
        $vars = @{ LOTUS_SRC = $script:Repo; LOTUS_DEST = $Dest; LOTUS_PROFILE = (Join-Path $script:Tmp 'profile-policy.ps1'); LOTUS_NO_PATH = '1'; LOTUS_NO_SETUP = '1'; LOTUS_FASTFETCH = 'no'
            TEST_POLICIES = $Policies; TEST_INSTALLER = (Join-Path $script:Repo 'install.ps1') }
        foreach ($k in $Env.Keys) { $vars[$k] = $Env[$k] }
        $saved = @{}
        foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
        try { & $script:Pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper 2>&1 | Out-String }
        finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
    }
}

AfterAll { Restore-LotusTestEnv $script:Ctx }

Describe 'install.ps1' {
    It 'parses' {
        foreach ($f in 'install.ps1', 'bin/lotus.ps1') {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Repo $f), [ref]$null, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0 -Because $f
        }
    }
    It 'installs from a checkout, loads in the profile, and runs' {
        $dest = Join-Path $script:Tmp 'app'
        $out = Invoke-TestInstall $dest
        $out | Should -Match 'Lotus is in'
        $out | Should -Match 'Done'
        foreach ($file in 'win/Lotus.psd1', 'win/Public/lotus.ps1', 'win/Public/pets.ps1', 'win/Public/ai.ps1', 'data/commands.tsv', 'data/pets/lotus.windows.tsv', 'data/ai/system.md',
            'logos/lotus.txt', 'lib/core.zsh', 'lib/lang/en.zsh', 'lib/lang/setup.de.zsh', 'lib/live/liveserver.py', 'lib/html/convert.py',
            'lib/edit/editor.py', 'lib/edit/engine.py', 'lib/edit/web/index.html', 'lib/bg/worker.py', 'lib/mc/bridge/LotusBridge.java', 'bin/lotus.cmd', 'bin/lotus.ps1', '.lotus-install') {
            Test-Path (Join-Path $dest $file) | Should -BeTrue -Because "$file is there"
        }
        Test-Path (Join-Path $dest 'win/tests') | Should -BeFalse
        Test-Path (Join-Path $dest 'lib/cmd') | Should -BeFalse
        Test-Path (Join-Path $dest 'vendor') | Should -BeFalse
        $profileText = Get-Content (Join-Path $script:Tmp 'profile.ps1') -Raw
        $profileText | Should -Match '# >>> lotus >>>'
        $profileText | Should -Match 'Import-Module'
        $got = & $script:Pwsh -NoProfile -Command "Import-Module '$(Join-Path $dest 'win/Lotus.psd1')'; lotus version"
        $got | Should -Be $script:Want
        # the texts are there: German, from the copied language files
        $text = & $script:Pwsh -NoProfile -Command "`$env:LOTUS_NO_TTY = '1'; Import-Module '$(Join-Path $dest 'win/Lotus.psd1')'; lotus settings set LOTUS_LANG de | Out-Null; & (Get-Module Lotus) { Initialize-Lotus; T settings }"
        ($text | Select-Object -Last 1) | Should -Be 'Einstellungen'
        & $script:Pwsh -NoProfile -Command "`$env:LOTUS_NO_TTY = '1'; Import-Module '$(Join-Path $dest 'win/Lotus.psd1')'; lotus settings set LOTUS_LANG en | Out-Null"
    }
    It 'gives lotus to other shells: bin/lotus.ps1 runs a command' {
        $dest = Join-Path $script:Tmp 'app'
        & $script:Pwsh -NoProfile -File (Join-Path $dest 'bin/lotus.ps1') version | Should -Be $script:Want
        & $script:Pwsh -NoProfile -File (Join-Path $dest 'bin/lotus.ps1') nosuchcommand *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'is run a second time without a second block' {
        $dest = Join-Path $script:Tmp 'app'
        Invoke-TestInstall $dest | Out-Null
        ([regex]::Matches((Get-Content (Join-Path $script:Tmp 'profile.ps1') -Raw), '# >>> lotus >>>')).Count | Should -Be 1
    }
}

# Windows PowerShell on a new Windows 11 runs no script files (ExecutionPolicy Restricted): what the installer does about it
Describe 'install.ps1 and the execution policy of Windows PowerShell' -Skip:($PSVersionTable.PSEdition -eq 'Core') {
    It 'Restricted: its own window runs scripts (Process, Bypass), and the user gets RemoteSigned after the command is shown' {
        $out = Invoke-TestInstallPolicy (Join-Path $script:Tmp 'app-policy') 'LocalMachine=Restricted' @{ LOTUS_YES = '1' }
        $out | Should -Match 'SET: Process=Bypass;CurrentUser=RemoteSigned'
        $out | Should -Match 'The command: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned'
        $out | Should -Match 'ExecutionPolicy RemoteSigned for your user'
        $out | Should -Match 'Done'
    }
    It 'the policy of the user is set although PowerShell calls it overridden by the window''s own policy – that is no failure' {
        # (Windows PowerShell reports "Security error." for it: the installer looks at what is set, not at that error)
        $out = Invoke-TestInstallPolicy (Join-Path $script:Tmp 'app-policy') 'LocalMachine=Restricted' @{ LOTUS_YES = '1'; TEST_OVERRIDE = '1' }
        $out | Should -Match 'SET: Process=Bypass;CurrentUser=RemoteSigned'
        $out | Should -Match 'ExecutionPolicy RemoteSigned for your user'
        $out | Should -Not -Match 'It did not work'
    }
    It 'a policy that really cannot be set is reported, with the reason' {
        $out = Invoke-TestInstallPolicy (Join-Path $script:Tmp 'app-policy') 'LocalMachine=Restricted' @{ LOTUS_YES = '1'; TEST_SETFAIL = '1' }
        $out | Should -Match 'It did not work: Access to the registry key is denied'
        $out | Should -Not -Match 'ExecutionPolicy RemoteSigned for your user'
        $out | Should -Match 'Done'
    }
    It 'asks first: without a yes the user policy stays as it is, and the installer says what happens then' {
        $out = Invoke-TestInstallPolicy (Join-Path $script:Tmp 'app-policy') 'LocalMachine=Restricted'
        $out | Should -Match 'SET: Process=Bypass\s*$'
        $out | Should -Match 'Without it a new window prints an error'
    }
    It 'a policy that runs local scripts (RemoteSigned, Unrestricted, a user policy) is left alone' {
        foreach ($p in 'LocalMachine=RemoteSigned', 'LocalMachine=Unrestricted', 'LocalMachine=Restricted;CurrentUser=RemoteSigned', 'LocalMachine=Restricted;CurrentUser=Bypass') {
            $out = Invoke-TestInstallPolicy (Join-Path $script:Tmp 'app-policy') $p @{ LOTUS_YES = '1' }
            $out | Should -Match 'SET:\s*$' -Because $p
            $out | Should -Not -Match 'Set it now' -Because $p
        }
    }
    It 'a policy of the organization is never changed, and the installer says so' {
        $out = Invoke-TestInstallPolicy (Join-Path $script:Tmp 'app-policy') 'MachinePolicy=AllSigned' @{ LOTUS_YES = '1' }
        $out | Should -Match 'A policy of your organization \(AllSigned\)'
        $out | Should -Not -Match 'CurrentUser=RemoteSigned'
    }
    It 'LOTUS_NO_PROFILE=1: the profile is not touched, so the policy is not asked about' {
        $out = Invoke-TestInstallPolicy (Join-Path $script:Tmp 'app-policy') 'LocalMachine=Restricted' @{ LOTUS_YES = '1'; LOTUS_NO_PROFILE = '1' }
        $out | Should -Match 'SET: Process=Bypass\s*$'
        $out | Should -Match 'Your profile was not changed'
    }
}

Describe 'install.ps1 on Windows' -Skip:(-not $IsWindows) {
    It 'cmd.exe runs lotus.cmd' {
        $dest = Join-Path $script:Tmp 'app'
        # (PowerShell hands a .cmd file to cmd.exe)
        $out = & (Join-Path $dest 'bin\lotus.cmd') version
        ($out | Select-Object -Last 1) | Should -Be $script:Want
        $LASTEXITCODE | Should -Be 0
    }
    It 'puts lotus.cmd into the user PATH once, keeps the kind of the value, and lotus uninstall would take it out' {
        $key = Get-Item -LiteralPath 'HKCU:\Environment'
        $had = $key.GetValueNames() -contains 'Path'
        $before = if ($had) { $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames') } else { $null }
        $kind = if ($had) { $key.GetValueKind('Path') } else { $null }
        $dest = Join-Path $script:Tmp 'app'
        $bin = Join-Path $dest 'bin'
        try {
            (Invoke-TestInstall $dest @{ LOTUS_NO_PATH = '' }) | Should -Match 'lotus.cmd is in your PATH'
            (Invoke-TestInstall $dest @{ LOTUS_NO_PATH = '' }) | Should -Not -Match 'lotus.cmd is in your PATH'
            $now = (Get-Item -LiteralPath 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
            @($now -split ';' | Where-Object { $_.TrimEnd('\') -eq $bin.TrimEnd('\') }).Count | Should -Be 1
            if ($had) { (Get-Item -LiteralPath 'HKCU:\Environment').GetValueKind('Path') | Should -Be $kind }
            Import-Module (Join-Path $dest 'win/Lotus.psd1') -Force
            & (Get-Module Lotus) { param($d) Remove-LotusUserPath $d } $bin | Should -BeTrue
            $after = (Get-Item -LiteralPath 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
            $after | Should -Not -Match ([regex]::Escape($bin))
        } finally {
            Remove-Module Lotus -Force -ErrorAction SilentlyContinue
            if ($had) { Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -Value $before -Type $kind }
            else { Remove-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue }
        }
    }
    It "downloads Lotus' own fastfetch, checked against data/vendor.tsv" {
        $dest = Join-Path $script:Tmp 'app-ff'
        $out = Invoke-TestInstall $dest @{ LOTUS_FASTFETCH = 'pinned'; LOTUS_YES = '1' }
        $out | Should -Match 'checked against SHA-256'
        $exe = Join-Path $dest 'vendor/fastfetch/fastfetch.exe'
        Test-Path $exe | Should -BeTrue
        $pin = (Get-Content (Join-Path $script:Repo 'data/vendor.tsv') | Where-Object { $_ -match '^fastfetch\t' } | Select-Object -First 1) -split "`t"
        (& $exe --version) | Should -Match ([regex]::Escape($pin[1]))
        # the start screen finds it there
        $found = & $script:Pwsh -NoProfile -Command "`$env:PATH = 'C:\Windows\System32'; Import-Module '$(Join-Path $dest 'win/Lotus.psd1')'; & (Get-Module Lotus) { Initialize-Lotus; Get-LotusFastfetch }"
        [System.IO.Path]::GetFullPath(($found | Select-Object -Last 1)) | Should -Be ([System.IO.Path]::GetFullPath($exe))
    }
}
