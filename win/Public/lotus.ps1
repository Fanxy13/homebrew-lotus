# The lotus command – what bin/lotus is for zsh: each subcommand goes to its module (Public/<module>.ps1, loaded when
# first used). A feature that is turned off explains itself; an unknown command gets a suggestion; what Windows does
# not have says so instead of failing quietly.
# (A simple function with $args, not an advanced one: "lotus -v" must reach it as the text "-v", not as a parameter.)

$script:WebsiteStatus = 'https://fanxy13.github.io/homebrew-lotus/#platforms'

$script:Modules = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
foreach ($pair in @(
        'setup system', 'update system', 'upgrade system', 'doctor system', 'uninstall system', 'unhook system',
        'help help', '-h help', '--help help', 'cheatsheet help', 'themes help', 'suggest help',
        'web web', 'github web', 'goat web', 'who web', 'browse web', 'google web', 'search web', 'open web',
        'app app', 'brew brew', 'install install', 'audio audio', 'weather weather', 'ai ai',
        'ios ios', 'minecraft minecraft', 'mc minecraft', 'convert convert', 'visual visual',
        'shortcuts shortcuts', 'shortcut shortcuts', 'run shortcuts', 'logo logo',
        'bg bg', 'log log', 'features setup', 'pets pets', 'pet pets', 'feed pets', 'zetamac pets', 'clock clock',
        'caffeine caffeine', 'awake caffeine', 'ai-tool aitools',
        'plugin plugin', 'plugins plugin', 'plugin-tool plugin', 'plugin-startup plugin', 'bash-init shell',
        'img img', 'liveserver live', 'html html', 'meshchat meshchat')) {
    $kv = $pair -split ' '
    $script:Modules[$kv[0]] = $kv[1]
}

# What Windows cannot do (yet), in words: module → the reason, and whether the table of what works where helps
$script:NotOnWindows = @{
    ios       = @("iPhone and iPad tools need Apple’s tools: they are for macOS only.", $false)
    plugin    = @('Plugins are not on Windows yet: Windows has no sandbox that PowerShell can use, so every plugin will need the approval a full-access one needs.', $true)
    aitools   = @('The AI program is not on Windows yet.', $true)
    shell     = @('bash-init is for bash on macOS and Linux. PowerShell has its own: lotus setup --hook', $false)
}

function lotus {
    $script:T0 = [datetime]::UtcNow
    $argv = @($args | ForEach-Object { [string]$_ })
    $verboseWas = $env:LOTUS_VERBOSE
    if ($argv.Count -and $argv[0] -cin '-V', '--verbose') { $env:LOTUS_VERBOSE = '1'; $argv = @($argv | Select-Object -Skip 1) }
    $cmd = if ($argv.Count) { $argv[0] } else { 'show' }
    $rest = [string[]]@($argv | Select-Object -Skip 1)
    $rc = 0
    try {
        Initialize-Lotus
        foreach ($o in (Invoke-LotusDispatch $cmd $rest)) {
            if (Test-LotusStatus $o) { $rc = $o.Code } else { $o }
        }
    } finally {
        if ($null -eq $verboseWas) { Remove-Item Env:LOTUS_VERBOSE -ErrorAction SilentlyContinue } else { $env:LOTUS_VERBOSE = $verboseWas }
        try { Exit-LotusKeys } catch { }
        $global:LASTEXITCODE = [int]$rc
    }
    if ($script:ShellOn) { Update-LotusShellAfter $cmd }
}

# Runs one command: its output, and its status as the last St
function Invoke-LotusDispatch {
    param([string]$Cmd, [string[]]$Rest)
    switch -CaseSensitive ($Cmd) {
        { $_ -cin 'show', '' } {
            if (-not (Test-LotusOn $script:S['LOTUS_CONFIGURED']) -and (Test-LotusTty) -and (Test-LotusOutTty)) {
                Import-LotusCommand setup
                Invoke-LotusSetupWizard | Where-Object { -not (Test-LotusStatus $_) }
                Initialize-Lotus
            }
            Show-LotusStart
            return (St 0)
        }
        { $_ -cin 'settings', 'config' } {
            Write-LotusLog DEBUG cli 'Settings opened'
            Import-LotusCommand settings
            Invoke-LotusSettings $Rest
            return
        }
        { $_ -cin 'version', '-v', '--version' } { Get-LotusVersion; return (St 0) }
        'shell-init' { Enable-LotusShell; return (St 0) }
    }
    $module = $null
    if (-not $script:Modules.TryGetValue($Cmd, [ref]$module)) {
        Write-LotusLog INFO cli "Unknown command: $Cmd"
        Import-LotusCommand help
        Invoke-LotusSuggest $Cmd $Rest     # its status: 1, or the one of the command you chose to run instead
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $script:LotusModuleRoot "Public/$module.ps1"))) {
        $why = if ($script:NotOnWindows.ContainsKey($module)) { $script:NotOnWindows[$module] } else { @("lotus $Cmd is not available on Windows yet.", $true) }
        Write-LotusLine ''
        Write-LotusLine "  $(E '1')$(E key2)!$($script:R) $($why[0])"
        if ($why[1]) { Write-LotusLine "  $(E dim)What works where: $($script:WebsiteStatus)$($script:R)" }
        Write-LotusLine ''
        Write-LotusLog INFO cli "$Cmd is not available on Windows"
        return (St 2)
    }
    # a feature that is turned off explains itself instead of running
    $feature = Get-LotusFeatureOf $Cmd
    if (-not (Test-LotusFeature $feature)) {
        Write-LotusLog DEBUG cli "${Cmd}: the feature `"$feature`" is turned off"
        if (Show-LotusFeatureOff $feature) { Initialize-Lotus } else { return (St 3) }
    }
    Write-LotusLog DEBUG cli "Command: $Cmd$(if ($env:LOTUS_VERBOSE -eq '1' -and $Rest.Count) { ' ' + ($Rest -join ' ') })"
    Import-LotusCommand $module
    $script:LogComp = $module
    $rc = 0
    try {
        foreach ($o in (& "Invoke-Lotus$module" $Cmd $Rest)) {
            if (Test-LotusStatus $o) { $rc = $o.Code } else { $o }
        }
    } finally { $script:LogComp = $null }
    if ($rc -and $rc -ne 130) { Write-LotusLog DEBUG cli "$Cmd ended with status $rc" }
    St $rc
}
