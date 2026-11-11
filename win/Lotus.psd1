@{
    RootModule        = 'Lotus.psm1'
    ModuleVersion     = '3.0.0'
    GUID              = '5f0a3a52-6d0f-4a58-9a39-7b7a8d9c1e11'
    Author            = 'Fanxy13'
    Description       = 'Lotus for Windows: a start screen and command center for Windows PowerShell 5.1 and PowerShell 7 (see win/README.md)'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @('lotus')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('terminal', 'startscreen', 'prompt'); ProjectUri = 'https://github.com/Fanxy13/homebrew-lotus'; LicenseUri = 'https://github.com/Fanxy13/homebrew-lotus/blob/main/LICENSE' } }
}
