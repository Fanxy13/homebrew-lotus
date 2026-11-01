# The lotus command. Everything it can do on Windows is listed in `lotus help`; the rest says so instead of failing quietly.
# (A simple function with $args, not an advanced one: "lotus -v" must reach us as the text "-v", not as a parameter.)

$script:WebsiteStatus = 'https://fanxy13.github.io/homebrew-lotus/#platforms'

function lotus {
    $command = if ($args.Count -gt 0) { [string]$args[0] } else { 'show' }
    $rest = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)]) } else { @() }
    switch -Regex ($command) {
        '^(show|)$'                  { Show-LotusStart; return }
        '^(version|-v|--version)$'   { Get-LotusVersion; return }
        '^doctor$'                   { Invoke-LotusDoctor; return }
        '^themes$'                   { Show-LotusThemes; return }
        '^(settings|config)$'        { Invoke-LotusSettings $rest; return }
        '^setup$'                    { Invoke-LotusSetup $rest; return }
        '^unhook$'                   { if (Remove-LotusHook) { Write-Host '  Removed the Lotus lines from your PowerShell profile.' } else { Write-Host '  There were no Lotus lines in your profile.' }; return }
        '^uninstall$'                { Invoke-LotusUninstall $rest; return }
        '^(help|-h|--help)$'         { Show-LotusHelp; return }
        default {
            Write-Host "  lotus $command is not available on Windows yet." -ForegroundColor Yellow
            Write-Host "  What works where: $script:WebsiteStatus"
            $global:LASTEXITCODE = 2
        }
    }
}

function Show-LotusHelp {
    Write-Host ''
    Write-Host '  Lotus for Windows (preview)' -ForegroundColor Green
    Write-Host ''
    @(
        @('lotus', 'the start screen'),
        @('lotus version', 'the installed version'),
        @('lotus doctor', 'what is there and what is missing'),
        @('lotus themes', 'the themes'),
        @('lotus settings [get|set NAME VALUE]', 'the settings file, the same format as on macOS and Linux'),
        @('lotus setup --hook', 'load Lotus in every PowerShell window (a block in your profile)'),
        @('lotus unhook', 'take that block out again'),
        @('lotus uninstall', 'remove your settings and the block (asks first)')
    ) | ForEach-Object { Write-Host ('  {0,-38}{1}' -f $_[0], $_[1]) }
    Write-Host ''
    Write-Host "  Everything else is being built. What works where: $script:WebsiteStatus"
    Write-Host ''
}

function Show-LotusThemes {
    $esc = [char]27
    foreach ($theme in Get-LotusThemes) {
        $swatch = ($theme.Colors.Values | Select-Object -First 4 | ForEach-Object { "$esc[48;2;$($_)m  $esc[0m" }) -join ''
        Write-Host ('  {0,-10}{1}' -f $theme.Name, $swatch)
    }
}

function Invoke-LotusSettings {
    param($Rest)
    $Rest = @($Rest | Where-Object { $null -ne $_ })      # an empty array arrives as $null
    $paths = Get-LotusPaths
    switch ("$($Rest[0])") {
        'get' {
            $settings = Read-LotusSettings $paths.Settings
            if ($settings.Contains("$($Rest[1])")) { $settings["$($Rest[1])"] } else { $global:LASTEXITCODE = 1 }
        }
        'set' {
            if ($Rest.Count -lt 3) { Write-Host '  lotus settings set NAME VALUE'; $global:LASTEXITCODE = 2; return }
            Set-LotusSetting -Path $paths.Settings -Name $Rest[1] -Value ($Rest[2..($Rest.Count - 1)] -join ' ')
            Write-Host "  $($Rest[1]) saved in $($paths.Settings)"
        }
        default {
            $settings = Read-LotusSettings $paths.Settings
            if ($settings.Count -eq 0) { Write-Host "  No settings yet ($($paths.Settings))." }
            foreach ($key in $settings.Keys) { Write-Host ('  {0,-28}{1}' -f $key, $settings[$key]) }
        }
    }
}

function Invoke-LotusSetup {
    param($Rest)
    $Rest = @($Rest | Where-Object { $null -ne $_ })      # an empty array arrives as $null
    $path = Add-LotusHook
    Write-Host "  Lotus is loaded from $path"
    Write-Host '  Open a new PowerShell window. The setup wizard is not on Windows yet; set your name with: lotus settings set LOTUS_NAME Ada'
}

function Invoke-LotusUninstall {
    param($Rest)
    $Rest = @($Rest | Where-Object { $null -ne $_ })      # an empty array arrives as $null
    $paths = Get-LotusPaths
    Write-Host '  This removes your Lotus settings and cache and the Lotus lines in your PowerShell profile:'
    Write-Host "    $($paths.Conf)"
    Write-Host "    $($paths.Cache)"
    if ($Rest -notcontains '--yes') {
        $answer = Read-Host '  Remove them? [y/N]'
        if ($answer -notmatch '^(y|yes|j|ja)$') { Write-Host '  Nothing was removed.'; return }
    }
    Remove-LotusHook | Out-Null
    foreach ($dir in @($paths.Conf, $paths.Cache)) {
        if ((Test-Path -LiteralPath $dir) -and $dir.Length -gt 12) { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
    Write-Host '  Removed. The program itself goes with the tool you installed it with: winget uninstall or scoop uninstall.'
}

function Invoke-LotusDoctor {
    $paths = Get-LotusPaths
    $rows = @(
        @('PowerShell 7.2 or newer', (($PSVersionTable.PSVersion.Major -gt 7) -or ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -ge 2)), "$($PSVersionTable.PSVersion)"),
        @('Windows Terminal', [bool]$env:WT_SESSION, $(if ($env:WT_SESSION) { 'yes' } else { 'not detected: colors may be fewer' })),
        @('fastfetch (system information)', [bool](Get-Command fastfetch -ErrorAction SilentlyContinue), $(if (Get-Command fastfetch -ErrorAction SilentlyContinue) { (Get-Command fastfetch).Source } else { 'winget install Fastfetch-cli.Fastfetch' })),
        @('Lotus data and logos', (Test-Path -LiteralPath (Join-Path $paths.Root 'logos')), $paths.Root),
        @('Settings file', (Test-Path -LiteralPath $paths.Settings), $paths.Settings),
        @('Loaded by your profile', (Test-LotusHook), 'lotus setup --hook')
    )
    Write-Host ''
    foreach ($row in $rows) {
        $mark = if ($row[1]) { 'ok     ' } else { 'missing' }
        Write-Host ("  {0}  {1,-34}{2}" -f $mark, $row[0], $row[2])
    }
    Write-Host ''
}
