# Where Lotus' program files and the user's files are.

function Get-LotusRoot {
    # LOTUS_ROOT for tests and developers; else the folder above the module (a checkout, or an install that ships
    # win/, data/ and logos/ side by side), else the module folder itself
    if ($env:LOTUS_ROOT -and (Test-Path -LiteralPath (Join-Path $env:LOTUS_ROOT 'data/commands.tsv'))) { return $env:LOTUS_ROOT }
    foreach ($candidate in @((Split-Path -Parent $script:LotusModuleRoot), $script:LotusModuleRoot)) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'data/commands.tsv')) { return $candidate }
    }
    throw 'Lotus cannot find its data folder (data/commands.tsv). Set LOTUS_ROOT to the folder that has data/ and logos/.'
}

function Get-LotusPaths {
    # Windows: %APPDATA%\lotus for settings, %LOCALAPPDATA%\lotus for cache and data. Elsewhere (the tests run on Linux too):
    # the XDG folders. LOTUS_CONF, LOTUS_CACHE and LOTUS_DATA override.
    $home_ = if ($IsWindows) { $env:USERPROFILE } else { $HOME }
    if ($IsWindows) {
        $conf = if ($env:LOTUS_CONF) { $env:LOTUS_CONF } else { Join-Path $env:APPDATA 'lotus' }
        $cache = if ($env:LOTUS_CACHE) { $env:LOTUS_CACHE } else { Join-Path $env:LOCALAPPDATA 'lotus/cache' }
        $data = if ($env:LOTUS_DATA) { $env:LOTUS_DATA } else { Join-Path $env:LOCALAPPDATA 'lotus/data' }
    } else {
        $xdgConfig = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $home_ '.config' }
        $xdgCache = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $home_ '.cache' }
        $xdgData = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $home_ '.local/share' }
        $conf = if ($env:LOTUS_CONF) { $env:LOTUS_CONF } else { Join-Path $xdgConfig 'lotus' }
        $cache = if ($env:LOTUS_CACHE) { $env:LOTUS_CACHE } else { Join-Path $xdgCache 'lotus' }
        $data = if ($env:LOTUS_DATA) { $env:LOTUS_DATA } else { Join-Path $xdgData 'lotus' }
    }
    [pscustomobject]@{
        Root     = Get-LotusRoot
        Conf     = $conf
        Cache    = $cache
        Data     = $data
        Settings = Join-Path $conf 'settings.zsh'
    }
}
