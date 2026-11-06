# Shared by the test files: each one runs in folders of its own (nothing of yours is read or changed), never waits for a
# keyboard (LOTUS_NO_TTY), and puts the environment back when it is done. Keys for the screens come from a queue.

$script:LotusTestVars = 'LOTUS_ROOT', 'LOTUS_CONF', 'LOTUS_CACHE', 'LOTUS_STATE', 'LOTUS_DATA', 'LOTUS_PROFILE', 'LOTUS_NO_TTY',
'LOTUS_SRC', 'LOTUS_DEST', 'LOTUS_NO_PROFILE', 'LOTUS_SHELL_TEST', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'COLUMNS', 'LINES'

function Initialize-LotusTestEnv {
    param([string]$Name = 'lotus-test')
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("$Name-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $saved = @{}
    foreach ($n in $script:LotusTestVars) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    foreach ($n in $script:LotusTestVars) { [Environment]::SetEnvironmentVariable($n, $null) }
    $env:LOTUS_ROOT = $repo
    $env:LOTUS_CONF = Join-Path $tmp 'conf'
    $env:LOTUS_CACHE = Join-Path $tmp 'cache'
    $env:LOTUS_STATE = Join-Path $tmp 'state'
    $env:LOTUS_DATA = Join-Path $tmp 'data'
    $env:LOTUS_PROFILE = Join-Path $tmp 'profile.ps1'
    $env:LOTUS_NO_TTY = '1'
    $env:COLUMNS = '140'
    [pscustomobject]@{ Repo = $repo; Tmp = $tmp; Saved = $saved }
}

function Restore-LotusTestEnv {
    param($Context)
    if (-not $Context) { return }
    foreach ($n in $Context.Saved.Keys) { [Environment]::SetEnvironmentVariable($n, $Context.Saved[$n]) }
    Remove-Item -LiteralPath $Context.Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# Runs a script block in the module with these keys as the keyboard (names as Read-LotusKeyX gives them: up, enter,
# esc, a, …); what the screens write comes back as text
function Invoke-LotusWithKeys {
    param([string[]]$Keys, [scriptblock]$ScriptBlock)
    InModuleScope Lotus -Parameters @{ Keys = $Keys; Body = $ScriptBlock.ToString() } {
        $script:KeyQueue.Clear()
        foreach ($k in $Keys) { $script:KeyQueue.Enqueue($k) }
        $script:KeyQueueActive = $true
        # made again here, so that it runs inside the module and sees its functions
        try { & ([scriptblock]::Create($Body)) *>&1 | Out-String } finally { $script:KeyQueueActive = $false; $script:KeyQueue.Clear() }
    }
}
