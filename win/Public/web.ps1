# /google, /search, /web, links, /lotus web, /lotus github – a port of lib/cmd/web.zsh

$script:Engines = @{
    google     = 'https://www.google.com/search?q='
    duckduckgo = 'https://duckduckgo.com/?q='
    bing       = 'https://www.bing.com/search?q='
    ecosia     = 'https://www.ecosia.org/search?q='
    brave      = 'https://search.brave.com/search?q='
}
# Sites /web knows by name: "/web github lotus" searches GitHub for lotus
$script:Sites = @{
    github        = 'https://github.com|https://github.com/search?q='
    youtube       = 'https://www.youtube.com|https://www.youtube.com/results?search_query='
    reddit        = 'https://www.reddit.com|https://www.reddit.com/search/?q='
    wikipedia     = 'https://en.wikipedia.org|https://en.wikipedia.org/w/index.php?search='
    maps          = 'https://www.google.com/maps|https://www.google.com/maps/search/'
    amazon        = 'https://www.amazon.com|https://www.amazon.com/s?k='
    stackoverflow = 'https://stackoverflow.com|https://stackoverflow.com/search?q='
    npm           = 'https://www.npmjs.com|https://www.npmjs.com/search?q='
    winget        = 'https://winget.run|https://winget.run/search?query='
    brew          = 'https://brew.sh|https://formulae.brew.sh/?search='
    x             = 'https://x.com|https://x.com/search?q='
    spotify       = 'https://open.spotify.com|https://open.spotify.com/search/'
    translate     = 'https://translate.google.com|https://translate.google.com/?text='
}

function script:Invoke-Lotusweb {
    param([string]$Cmd, [string[]]$Rest)
    switch -CaseSensitive ($Cmd) {
        'web' { return Open-LotusUrl $script:P['website'] 'Lotus website' }
        'github' { return Open-LotusUrl $script:P['github'] 'GitHub' }
        { $_ -cin 'goat', 'who' } { $r = Open-LotusUrl $script:P['github'] 'quiet'; if ($r.Code -eq 0) { Write-LotusDim 'Obviously.' }; return $r }
        'google' { return Invoke-LotusSearch 'google' $Rest }
        'search' { return Invoke-LotusSearch ([string]$script:S['LOTUS_SEARCH_ENGINE']) $Rest }
        'browse' { return Invoke-LotusBrowse $Rest }
        'open' { return Open-LotusLink $Rest }
    }
}

# Percent-encoding for links (lotus_urlencode): letters, digits and .~_- stay, a space becomes + (or what $Space says)
function script:ConvertTo-LotusUrlEncoded {
    param([string]$Text, [string]$Space = '+')
    $sb = [System.Text.StringBuilder]::new()
    foreach ($b in [System.Text.Encoding]::UTF8.GetBytes($Text)) {
        $c = [char]$b
        if (($b -ge 0x30 -and $b -le 0x39) -or ($b -ge 0x41 -and $b -le 0x5a) -or ($b -ge 0x61 -and $b -le 0x7a) -or $c -in '.', '~', '_', '-') { [void]$sb.Append($c) }
        elseif ($b -eq 0x20) { [void]$sb.Append($Space) }
        else { [void]$sb.Append('%').Append($b.ToString('X2')) }
    }
    $sb.ToString()
}

# A link Lotus is willing to open: http(s), a host with a dot, no spaces or control characters
function script:Test-LotusValidUrl {
    param([string]$Url)
    $Url -match '^(?i)https?://[^\s/]+\.[^\s]+$' -and $Url -notmatch '\p{Cc}'
}

# "example.com/page" or "https://…" → the link, or $null (lotus_as_url)
function script:ConvertTo-LotusUrl {
    param([string]$Text)
    if ($Text -match '\s') { return $null }
    $u = if ($Text -match '^(?i)https?://') { $Text } elseif ($Text -match '^[\p{L}\p{Nd}-]+(\.[\p{L}\p{Nd}-]+)*\.\p{L}{2,}(/.*)?$') { "https://$Text" } else { return $null }
    if (Test-LotusValidUrl $u) { $u } else { $null }
}

function script:Open-LotusUrl {
    param([string]$Url, [string]$Label)
    if (-not (Test-LotusValidUrl $Url)) {
        Write-LotusError 'That is not a valid link' $Url @('Links need to start with http:// or https://')
        return (St 1)
    }
    $rc = Open-LotusTarget $Url
    if ($rc -ne 0) {
        if ($rc -eq 2) { Write-LotusInfo 'Nothing here can open links – open this address in a browser:'; Write-LotusText $Url }
        else { Write-LotusError 'Could not open the link' $Url }
        return (St 1)
    }
    if ($Label -ne 'quiet') { Write-LotusInfo "Opening $(if ($Label) { $Label } else { $Url })" }
    St 0
}

function script:Invoke-LotusSearch {
    param([string]$Engine, [string[]]$Words)
    $q = ($Words -join ' ').Trim()
    if (-not $q) {
        Write-LotusError 'Nothing to search for' '' @('Example: /search best minecraft server plugins')
        return (St 1)
    }
    $base = if ($script:Engines.ContainsKey($Engine)) { $script:Engines[$Engine] } else { $script:Engines['google'] }
    $name = if ($Engine) { $Engine.Substring(0, 1).ToUpper() + $Engine.Substring(1) } else { 'Google' }
    Open-LotusUrl "$base$(ConvertTo-LotusUrlEncoded $q)" "${name}: $q"
}

function script:Invoke-LotusBrowse {
    param([string[]]$Words)
    if (-not $Words.Count) { return Open-LotusUrl $script:P['website'] 'Lotus website' }
    $site = $Words[0].ToLowerInvariant()
    if ($Words.Count -eq 1 -and ($u = ConvertTo-LotusUrl $Words[0])) { return Open-LotusUrl $u }
    if ($script:Sites.ContainsKey($site)) {
        $parts = $script:Sites[$site] -split '\|'
        $label = $site.Substring(0, 1).ToUpper() + $site.Substring(1)
        if ($Words.Count -eq 1) { return Open-LotusUrl $parts[0] $label }
        $q = ($Words | Select-Object -Skip 1) -join ' '
        return Open-LotusUrl "$($parts[1])$(ConvertTo-LotusUrlEncoded $q)" "${label}: $q"
    }
    Invoke-LotusSearch ([string]$script:S['LOTUS_SEARCH_ENGINE']) $Words
}

function script:Open-LotusLink {
    param([string[]]$Words)
    $u = if ($Words.Count -eq 1) { ConvertTo-LotusUrl $Words[0] } else { $null }
    if (-not $u) {
        Write-LotusError 'That is not a valid link' ($Words -join ' ') @('Example: https://github.com/Fanxy13')
        return (St 1)
    }
    Open-LotusUrl $u
}
