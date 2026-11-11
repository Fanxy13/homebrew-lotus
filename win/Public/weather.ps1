# /weather with ASCII art – a port of lib/cmd/weather.zsh. Provider: Open-Meteo (free, no API key), the same requests
# and the same cache files; PowerShell reads the JSON itself (no jq).

$script:WeatherTtl = 600   # seconds a forecast is used again

function script:Invoke-Lotusweather {
    param([string]$Cmd, [string[]]$Rest)
    $place = ($Rest -join ' ').Trim()
    if (-not $place) { $place = [string]$script:S['LOTUS_WEATHER_LOCATION'] }
    if (-not $place.Trim()) {
        Write-LotusHeader 'Weather'
        Write-LotusDim 'No default city yet.'
        $place = Read-LotusInput 'City'
        if (-not $place -or -not $place.Trim()) { return (St 1) }
        if (Read-LotusConfirm "Use $place as your default city?" 'y') { $script:S['LOTUS_WEATHER_LOCATION'] = $place; Save-LotusSettings }
    }
    if ($place -match '[\p{Cc};`$\\]' -or $place.Length -gt 60) {
        Write-LotusError 'That does not look like a city name' $place
        return (St 1)
    }
    $w = Get-LotusWeather $place
    if (-not $w) { return (St 1) }
    Show-LotusWeather $w
    St 0
}

# City → coordinates (kept for good), the forecast (kept a few minutes) → the weather, or $null after an error screen
function script:Get-LotusWeather {
    param([string]$Place)
    $key = ($Place.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]', '_')
    $dir = New-LotusDir (Join-Path $script:Paths.Cache 'weather')
    $units = [string]$script:S['LOTUS_WEATHER_UNITS']
    $geo = Join-Path $dir "$key.geo"
    $data = Join-Path $dir "$key-$units.json"
    $m = Get-LotusMtime $data
    $fresh = $null -ne $m -and (Get-LotusEpoch) - $m -lt $script:WeatherTtl
    $offline = $false
    # 1. the city's coordinates
    if (-not (Test-Path -LiteralPath $geo) -or (Get-Item -LiteralPath $geo).Length -eq 0) {
        try {
            $g = Invoke-RestMethod -Uri "https://geocoding-api.open-meteo.com/v1/search?name=$([uri]::EscapeDataString($Place))&count=1&language=en&format=json" -TimeoutSec 8 -ErrorAction Stop
        } catch {
            Write-LotusError 'No internet connection' 'Lotus could not reach the weather service.' @('Try again when you are online.')
            return $null
        }
        $r = @($g.results)[0]
        if (-not $r) {
            Write-LotusError 'City not found' $Place @('Check the spelling, e.g. /weather Zurich')
            return $null
        }
        Write-LotusFile $geo ((@($r.name, [string]$r.admin1, $r.country, $r.latitude.ToString([cultureinfo]::InvariantCulture), $r.longitude.ToString([cultureinfo]::InvariantCulture)) -join "`t") + "`n")
    }
    $loc = ([string](Read-LotusFile $geo)).TrimEnd("`n") -split "`t"
    # 2. the forecast
    if (-not $fresh) {
        $u = if ($units -eq 'imperial') { '&temperature_unit=fahrenheit&wind_speed_unit=mph' } else { '&temperature_unit=celsius&wind_speed_unit=kmh' }
        $url = "https://api.open-meteo.com/v1/forecast?latitude=$($loc[3])&longitude=$($loc[4])&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=4$u"
        try {
            $resp = Invoke-WebRequest -Uri $url -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
            Write-LotusFile $data ([string]$resp.Content)
        } catch {
            if (-not (Test-Path -LiteralPath $data)) { Write-LotusError 'No internet connection' 'Lotus could not reach the weather service.'; return $null }
            $offline = $true
        }
    }
    $j = (Read-LotusFile $data) | ConvertFrom-Json
    $c = $j.current
    $days = for ($i = 0; $i -lt @($j.daily.time).Count; $i++) {
        [pscustomobject]@{ Date = $j.daily.time[$i]; Code = $j.daily.weather_code[$i]; Max = $j.daily.temperature_2m_max[$i]; Min = $j.daily.temperature_2m_min[$i]; Rain = $j.daily.precipitation_probability_max[$i] }
    }
    [pscustomobject]@{
        Name = $loc[0]; Region = $loc[1]; Country = $loc[2]; Temp = $c.temperature_2m; Feels = $c.apparent_temperature; Hum = $c.relative_humidity_2m
        Code = $c.weather_code; Wind = $c.wind_speed_10m; Day = $c.is_day; Time = [string]$c.time; Offline = $offline; Days = @($days)
    }
}

# WMO weather code → kind and words
function script:Get-LotusWeatherKind {
    param([int]$Code, $IsDay = 1)
    $k = switch ($Code) {
        0 { 'sunny', 'Clear sky' } { $_ -in 1, 2 } { 'partly', 'Partly cloudy' } 3 { 'cloudy', 'Overcast' } { $_ -in 45, 48 } { 'fog', 'Fog' }
        { $_ -in 51, 53, 55, 56, 57 } { 'rain', 'Drizzle' } { $_ -in 61, 63, 65, 66, 67, 80, 81, 82 } { 'rain', 'Rain' }
        { $_ -in 71, 73, 75, 77, 85, 86 } { 'snow', 'Snow' } { $_ -in 95, 96, 99 } { 'storm', 'Thunderstorm' }
        default { 'cloudy', 'Cloudy' }
    }
    $k = @($k)
    if ("$IsDay" -eq '0' -and $k[0] -in 'sunny', 'partly') { $k[0] = 'night' }
    $k
}

# ASCII art, 5 lines × 15 columns, in the theme's colors
function script:Get-LotusWeatherArt {
    param([string]$Kind)
    $esc = [char]27
    $wt = "$esc[97m"; $s = E key2; $w = E border; $r = E accent; $n = E salute; $x = "$esc[0m"; $f = E dim; $b = "$esc[1;$($script:C['key2'])m"
    switch ($Kind) {
        'sunny' { @("$s    \   /      $x", "$s     .-.       $x", "$s  - (   ) -    $x", "$s     ``-'       $x", "$s    /   \      $x") }
        'partly' { @("$s   \  /        $x", "$s _ /`"`"$w.-.      $x", "$s   \_$w(   ).    $x", "$s   /$w(___(__)   $x", '               ') }
        'cloudy' { @('               ', "$w     .--.      $x", "$w  .-(    ).    $x", "$w (___.__)__)   $x", '               ') }
        'rain' { @("$w     .-.       $x", "$w    (   ).     $x", "$w   (___(__)    $x", "$r    ' ' ' '    $x", "$r   ' ' ' '     $x") }
        'storm' { @("$w     .-.       $x", "$w    (   ).     $x", "$w   (___(__)    $x", "$b    /_ $r' '$b /_   $x", "$r   ' '$b/ $r' '    $x") }
        'snow' { @("$w     .-.       $x", "$w    (   ).     $x", "$w   (___(__)    $x", "$wt    *  *  *    $x", "$wt   *  *  *     $x") }
        'fog' { @('               ', "$f _ - _ - _ -   $x", "$f  _ - _ - _    $x", "$f _ - _ - _ -   $x", '               ') }
        'night' { @("$n      *    .   $x", "$n   .--.   *    $x", "$n  (  (     .   $x", "$n   ``--'   *    $x", "$n  *    .       $x") }
    }
}

# a number as zsh shows it: the part before the point
function script:Format-LotusWhole { param($Value) ([string]([double]$Value).ToString([cultureinfo]::InvariantCulture) -split '\.')[0] }

function script:Show-LotusWeather {
    param($W)
    $u = '°C'; $sp = 'km/h'
    if ($script:S['LOTUS_WEATHER_UNITS'] -eq 'imperial') { $u = '°F'; $sp = 'mph' }
    $kind = Get-LotusWeatherKind $W.Code $W.Day
    $art = @(Get-LotusWeatherArt $kind[0])
    $k = "$(E '1')$(E key)"; $d = E dim; $x = "$([char]27)[0m"; $t = "$([char]27)[1m"
    $info = @(
        "$t$($W.Name)$x$d$(if ($W.Region) { ", $($W.Region)" }), $($W.Country)$x"
        "$t$(Format-LotusWhole $W.Temp)$u$x  $($kind[1])"
        "${k}Feels like$x  $(Format-LotusWhole $W.Feels)$u"
        "${k}Humidity  $x  $($W.Hum)%"
        "${k}Wind      $x  $(Format-LotusWhole $W.Wind) $sp"
    )
    Write-LotusHeader 'Weather' $(if ($W.Offline) { "offline – last update $(($W.Time -split 'T')[-1])" } else { '' })
    for ($i = 0; $i -lt 5; $i++) { Write-LotusLine "  $($art[$i])   $($info[$i])" }
    Write-LotusBlank
    Write-LotusCategory 'Forecast'
    foreach ($day in $W.Days) {
        $name = try { ([datetime]::ParseExact($day.Date, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)).ToString('ddd', [cultureinfo]::InvariantCulture) } catch { '?' }
        $dk = Get-LotusWeatherKind $day.Code 1
        $rain = if ($null -ne $day.Rain) { $day.Rain } else { 0 }
        Write-LotusLine "    $k$(PadR $name 4)$x $(PadR $dk[1] 14) $t$(Format-LotusWhole $day.Max)$u$x$d / $(Format-LotusWhole $day.Min)$u  $rain% rain$x"
    }
    Write-LotusBlank
}
