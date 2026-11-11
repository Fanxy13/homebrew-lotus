# One log for everything, in the zsh engine's format (lib/log.zsh):
#   2026-10-07 09:31:04.123<TAB>INFO<TAB>bg<TAB>Model loaded
# Keys and tokens are masked and the home folder becomes ~ before anything is written. Writing never fails loudly.

$script:LogRank = @{ off = 0; error = 1; warn = 2; info = 3; debug = 4; trace = 5 }
$script:LogMax = -1
$script:LogReady = $false
$script:LogSize = 1048576     # rotate at 1 MB, keep 3 older files

function Reset-LotusLog { $script:LogMax = -1 }

function Test-LotusLogOn {
    param([string]$Level)
    if ($script:LogMax -lt 0) {
        $lvl = if ($script:S) { $script:S['LOTUS_LOG_LEVEL'] } else { 'info' }
        $script:LogMax = if ($script:LogRank.ContainsKey([string]$lvl)) { $script:LogRank[[string]$lvl] } else { 3 }
        if ($env:LOTUS_VERBOSE -eq '1' -and $script:LogMax -lt 4) { $script:LogMax = 4 }
    }
    $r = $script:LogRank[$Level.ToLowerInvariant()]
    if ($null -eq $r) { $r = 3 }
    $r -le $script:LogMax
}

# Secrets masked, paths shortened (lotus_log_clean)
function Get-LotusLogClean {
    param([AllowEmptyString()][string]$Text)
    $m = $Text.Replace("`n", '\n').Replace("`t", ' ').Replace("`r", '')
    $h = Get-LotusHome
    if ($h -and $h -ne '/' -and $h -ne '\') { $m = $m.Replace($h, '~') }
    $m = [regex]::Replace($m, '(sk-(?:ant-|proj-|))[A-Za-z0-9_-]{12,}', '$1•••')
    $m = [regex]::Replace($m, '((?i)bearer )\S+', '$1•••')
    $m = [regex]::Replace($m, '((?i)(?:api[_-]*key|token|secret|password|passwd|authorization)["'']*\s*[=:]\s*)[^\s,;]+', '$1•••')
    $m
}

function Write-LotusLog {
    param([Parameter(Mandatory)][string]$Level, [Parameter(Mandatory)][string]$Component, [AllowEmptyString()][string]$Message = '')
    try {
        $Level = $Level.ToUpperInvariant()
        if (-not (Test-LotusLogOn $Level)) { return }
        if (-not $script:LogReady -and -not (Open-LotusLog)) { return }
        $clean = Get-LotusLogClean $Message
        $now = [datetime]::Now
        $line = $now.ToString('yyyy-MM-dd HH:mm:ss.fff', [cultureinfo]::InvariantCulture) + "`t$Level`t$Component`t$clean"
        [System.IO.File]::AppendAllText($script:Paths.Log, "$line`n", [System.Text.UTF8Encoding]::new($false))
        if ($env:LOTUS_VERBOSE -eq '1') {
            [Console]::Error.WriteLine("$([char]27)[2m$($now.ToString('HH:mm:ss.fff')) $($Level.PadRight(5)) ${Component}: $clean$([char]27)[0m")
        }
    } catch { }
}

# The folder, and the upkeep (size rotation, retention) – once per session
function Open-LotusLog {
    try {
        if (-not $script:Paths) { return $false }
        New-LotusDir $script:Paths.State | Out-Null
        $script:LogReady = $true
        $log = $script:Paths.Log
        $item = Get-Item -LiteralPath $log -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt $script:LogSize) {
            Remove-Item -LiteralPath "$log.3" -ErrorAction SilentlyContinue
            foreach ($i in 2, 1) { if (Test-Path -LiteralPath "$log.$i") { Move-Item -LiteralPath "$log.$i" -Destination "$log.$($i + 1)" -Force } }
            Move-Item -LiteralPath $log -Destination "$log.1" -Force -ErrorAction SilentlyContinue
        }
        # old rotated files go after the retention time (checked once a day)
        $stamp = Join-Path $script:Paths.State '.upkeep'
        $today = [datetime]::Now.ToString('yyyy-MM-dd')
        if ((Read-LotusFile $stamp) -match "^$today") { return $true }
        [System.IO.File]::WriteAllText($stamp, "$today`n")
        $days = 7
        if ($script:S -and $script:S['LOTUS_LOG_RETENTION'] -match '^\d+$') { $days = [int]$script:S['LOTUS_LOG_RETENTION'] }
        foreach ($f in Get-ChildItem -LiteralPath $script:Paths.State -Filter 'lotus.log.*' -File -ErrorAction SilentlyContinue) {
            if ($f.Name -match '^lotus\.log\.[1-9]$' -and ([datetime]::UtcNow - $f.LastWriteTimeUtc).TotalDays -ge $days) { Remove-Item -LiteralPath $f.FullName -Force }
        }
        Invoke-LotusLogTrim $days
        $true
    } catch { $false }
}

# Drops entries older than <days> from the current file
function Invoke-LotusLogTrim {
    param([int]$Days)
    $log = $script:Paths.Log
    if (-not (Test-Path -LiteralPath $log)) { return }
    $cutoff = [datetime]::Now.AddDays(-$Days).ToString('yyyy-MM-dd')
    $lines = [System.IO.File]::ReadAllLines($log)
    if (-not $lines.Count -or [string]::CompareOrdinal($lines[0].Substring(0, [Math]::Min(10, $lines[0].Length)), $cutoff) -ge 0) { return }
    $keep = $lines | Where-Object { [string]::CompareOrdinal($_.Substring(0, [Math]::Min(10, $_.Length)), $cutoff) -ge 0 }
    Write-LotusFile $log ($(if ($keep) { ($keep -join "`n") + "`n" } else { '' }))
}
