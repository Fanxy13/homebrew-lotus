# What every lotus call starts with (lotus_load in lib/core.zsh): paths, the system, settings, features, texts, colors.

function Initialize-Lotus {
    $script:Paths = Get-LotusPaths
    Initialize-LotusPlatform
    Import-LotusProject
    Import-LotusSettings
    Import-LotusFeatures
    Import-LotusLang
    Initialize-LotusColors
    # now playing needs the Music feature as well as its start screen section
    $script:NpOn = (Test-LotusOn $script:S['LOTUS_SHOW_MUSIC']) -and (Test-LotusFeature 'music')
}

# The exit status of a command. Commands write what is for the screen to the host and what is data (a version, a
# path) to the pipeline; their status travels as one of these, and lotus turns the last one into $LASTEXITCODE.
#   return (St 1)
function St { param([int]$Code = 0) [pscustomobject]@{ PSTypeName = 'Lotus.Status'; Code = $Code } }
function Test-LotusStatus { param($Object) $null -ne $Object -and $Object.PSObject.TypeNames[0] -eq 'Lotus.Status' }

# A command file of Public/, loaded the first time it is needed – its functions are defined as script:, so they belong
# to the module and stay private
$script:CommandFiles = @{}
function Import-LotusCommand {
    param([Parameter(Mandatory)][string]$Name)
    if ($script:CommandFiles.ContainsKey($Name)) { return }
    $file = Join-Path $script:LotusModuleRoot "Public/$Name.ps1"
    if (-not (Test-Path -LiteralPath $file)) { throw "Lotus has no command file $Name.ps1" }
    . $file
    $script:CommandFiles[$Name] = $true
}
