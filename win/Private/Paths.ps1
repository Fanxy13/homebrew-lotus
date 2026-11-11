# Where Lotus' program files and the user's files are.

function Get-LotusRoot {
    # LOTUS_ROOT for tests and developers; else the folder above the module (a checkout, or an install that ships
    # win/, data/ and logos/ side by side), else the module folder itself
    if ($script:LotusRootCache) { return $script:LotusRootCache }
    if ($env:LOTUS_ROOT -and (Test-Path -LiteralPath (Join-Path $env:LOTUS_ROOT 'data/commands.tsv'))) { return $env:LOTUS_ROOT }
    foreach ($candidate in @((Split-Path -Parent $script:LotusModuleRoot), $script:LotusModuleRoot)) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'data/commands.tsv')) { $script:LotusRootCache = $candidate; return $candidate }
    }
    throw 'Lotus cannot find its data folder (data/commands.tsv). Set LOTUS_ROOT to the folder that has data/ and logos/.'
}

function Get-LotusHome {
    if ($IsWindows) { $env:USERPROFILE } else { $HOME }
}

function Get-LotusPaths {
    # Windows: %APPDATA%\lotus for settings, %LOCALAPPDATA%\lotus\{cache,data,state} for the rest. Elsewhere (the tests
    # run on Linux and macOS too): the XDG folders, as the zsh engine has them. XDG variables are honored on Windows
    # when they are set; LOTUS_CONF, LOTUS_CACHE, LOTUS_DATA and LOTUS_STATE override everything.
    $home_ = Get-LotusHome
    if ($IsWindows) {
        $conf = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'lotus' } else { Join-Path $env:APPDATA 'lotus' }
        $cache = if ($env:XDG_CACHE_HOME) { Join-Path $env:XDG_CACHE_HOME 'lotus' } else { Join-Path $env:LOCALAPPDATA 'lotus\cache' }
        $data = if ($env:XDG_DATA_HOME) { Join-Path $env:XDG_DATA_HOME 'lotus' } else { Join-Path $env:LOCALAPPDATA 'lotus\data' }
        $state = if ($env:XDG_STATE_HOME) { Join-Path $env:XDG_STATE_HOME 'lotus' } else { Join-Path $env:LOCALAPPDATA 'lotus\state' }
    } else {
        $conf = Join-Path $(if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $home_ '.config' }) 'lotus'
        $cache = Join-Path $(if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $home_ '.cache' }) 'lotus'
        $data = Join-Path $(if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $home_ '.local/share' }) 'lotus'
        $state = Join-Path $(if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path $home_ '.local/state' }) 'lotus'
    }
    if ($env:LOTUS_CONF) { $conf = $env:LOTUS_CONF }
    if ($env:LOTUS_CACHE) { $cache = $env:LOTUS_CACHE }
    if ($env:LOTUS_DATA) { $data = $env:LOTUS_DATA }
    if ($env:LOTUS_STATE) { $state = $env:LOTUS_STATE }
    [pscustomobject]@{
        Root     = Get-LotusRoot
        Home     = $home_
        Conf     = $conf
        Cache    = $cache
        Data     = $data
        State    = $state
        Log      = Join-Path $state 'lotus.log'
        Settings = Join-Path $conf 'settings.zsh'
    }
}

# A folder that exists (made when it does not)
function New-LotusDir {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($Path) }
    $Path
}

# Writes text as the zsh engine does: UTF-8 without a byte order mark, new lines as they are – through a temporary
# file and a rename, so a reader never sees half a file
function Write-LotusFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir) { New-LotusDir $dir | Out-Null }
    $tmp = "$Path.$PID.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# The text of a file, or $null when it is not there (UTF-8; a byte order mark is ignored; CRLF line ends – a file
# edited in Notepad, a checkout that converted them – are read as LF, the way the zsh engine wrote them)
function Read-LotusFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false)).Replace("`r`n", "`n")
}

# A path for display: ~ for the home folder
function Format-LotusHomePath {
    param([AllowEmptyString()][string]$Path)
    $h = Get-LotusHome
    if ($h -and $Path -and ($Path -eq $h -or $Path.StartsWith($h + [IO.Path]::DirectorySeparatorChar) -or $Path.StartsWith($h + '/'))) {
        return '~' + $Path.Substring($h.Length)
    }
    $Path
}

# Seconds since 1970 (what zsh's EPOCHSECONDS and zstat +mtime give)
function Get-LotusEpoch {
    param([datetime]$Time = [datetime]::UtcNow)
    [long][DateTimeOffset]::new($Time.ToUniversalTime()).ToUnixTimeSeconds()
}
function Get-LotusMtime {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    [long][DateTimeOffset]::new($item.LastWriteTimeUtc).ToUnixTimeSeconds()
}
