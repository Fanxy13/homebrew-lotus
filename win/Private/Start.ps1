# The start screen: the logo in the theme's color, with fastfetch's system information next to it (as on the other systems).

function ConvertTo-LotusEscape {
    param([string]$Rgb)       # "248;184;208" -> ESC[38;2;248;184;208m
    "$([char]27)[38;2;$Rgb" + 'm'
}

function Get-LotusTheme {
    param([System.Collections.IDictionary]$Settings)
    $name = if ($Settings.Contains('LOTUS_THEME')) { $Settings['LOTUS_THEME'] } else { 'matcha' }
    $themes = @(Get-LotusThemes)
    $theme = $themes | Where-Object Name -eq $name | Select-Object -First 1
    if (-not $theme) { $theme = $themes | Where-Object Name -eq 'matcha' | Select-Object -First 1 }
    $theme
}

function Show-LotusStart {
    $paths = Get-LotusPaths
    $settings = Read-LotusSettings $paths.Settings
    $theme = Get-LotusTheme $settings
    $logoName = if ($settings.Contains('LOTUS_LOGO')) { $settings['LOTUS_LOGO'] } else { 'lotus' }
    $logoFile = Join-Path $paths.Root "logos/$logoName.txt"
    if (-not (Test-Path -LiteralPath $logoFile)) { $logoFile = Join-Path $paths.Root 'logos/lotus.txt' }
    $name = if ($settings.Contains('LOTUS_NAME') -and $settings['LOTUS_NAME']) { $settings['LOTUS_NAME'] } else { $env:USERNAME }
    $reset = "$([char]27)[0m"
    $color = ConvertTo-LotusEscape $theme.Colors['logo']
    $lines = @(Get-Content -LiteralPath $logoFile -Encoding utf8)
    $width = ($lines | Measure-Object -Property Length -Maximum).Maximum
    $fastfetch = Get-Command fastfetch -ErrorAction SilentlyContinue
    if ($fastfetch) {
        # fastfetch draws the logo from a file that already holds the colors (the same way as on the other systems)
        $artDir = Join-Path $paths.Cache 'art'
        New-Item -ItemType Directory -Force -Path $artDir | Out-Null
        $art = Join-Path $artDir "$logoName.txt"
        $painted = $lines | ForEach-Object { $color + $_.PadRight($width) + $reset }
        [System.IO.File]::WriteAllText($art, (($painted -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
        Write-Host ''
        & $fastfetch.Source --logo $art --logo-type file-raw --logo-width $width --logo-height $lines.Count --logo-padding-left 2 --logo-padding-right 4
    } else {
        Write-Host ''
        foreach ($line in $lines) { Write-Host ("  " + $color + $line + $reset) }
    }
    Write-Host ''
    Write-Host ("  Hello, $name") -NoNewline
    Write-Host ("   lotus help") -ForegroundColor DarkGray
}
