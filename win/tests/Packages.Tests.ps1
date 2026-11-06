# /install and /brew on Windows: winget's output read by the position of its columns (it is in the language of Windows),
# the card, the install in the open after a yes, and the catalog of data/apps.tsv. winget itself is mocked here; the CI
# asks the real winget for every id of the catalog (.github/workflows/windows.yml).

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    InModuleScope Lotus { Initialize-Lotus; Import-LotusCommand brew; Import-LotusCommand install }
    $script:SearchEn = @(
        'Name                              Id                                Version       Match          Source'
        '-----------------------------------------------------------------------------------------------------------'
        'Mozilla Firefox                   Mozilla.Firefox                   133.0.3       Tag: firefox   winget'
        'Firefox Developer Edition         Mozilla.Firefox.DeveloperEdition  134.0b5                      winget'
        'Mozilla Firefox Nightly Build Ve… Mozilla.Firefox.Nightly.Long.Id…  135.0a1                      winget'
        'Firefox                           9NZVDKPMR9RD                      Unknown                      msstore')
    $script:SearchDe = @(
        'Name             ID               Version  Übereinstimmung Quelle'
        '------------------------------------------------------------------'
        'Mozilla Firefox  Mozilla.Firefox  133.0.3  Tag: firefox    winget')
    $script:Show = @(
        'Found Mozilla Firefox [Mozilla.Firefox]'
        'Version: 133.0.3'
        'Publisher: Mozilla'
        'Description: Mozilla Firefox is free and open source software.'
        'Homepage: https://www.mozilla.org/firefox/')
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Restore-LotusTestEnv $script:Ctx
}

Describe 'what winget prints' {
    It 'reads the columns of a search by their position, whatever the language' {
        InModuleScope Lotus -Parameters @{ En = $script:SearchEn; De = $script:SearchDe } {
            $rows = @(ConvertFrom-LotusWingetTable $En)
            $rows.Count | Should -Be 4
            $rows[0].Name | Should -Be 'Mozilla Firefox'
            $rows[0].Id | Should -Be 'Mozilla.Firefox'
            $rows[0].Version | Should -Be '133.0.3'
            $rows[0].Source | Should -Be 'winget'
            $rows[1].Id | Should -Be 'Mozilla.Firefox.DeveloperEdition'
            $rows[3].Source | Should -Be 'msstore'
            $de = @(ConvertFrom-LotusWingetTable $De)
            $de[0].Id | Should -Be 'Mozilla.Firefox'
            $de[0].Source | Should -Be 'winget'
        }
    }
    It 'leaves out ids winget cut, and the Microsoft Store' {
        Mock -ModuleName Lotus Get-Command { $null } -ParameterFilter { $Name -eq 'Find-WinGetPackage' }
        Mock -ModuleName Lotus Invoke-LotusWingetText { $script:SearchEn }
        InModuleScope Lotus { @(Find-LotusPkg 'firefox').Id -join ' ' } | Should -Be 'Mozilla.Firefox Mozilla.Firefox.DeveloperEdition'
    }
    It 'reads the details of winget show' {
        Mock -ModuleName Lotus Invoke-LotusWingetText { $script:Show } -ParameterFilter { $Arguments[0] -eq 'show' }
        $d = InModuleScope Lotus { Get-LotusPkgDetails 'Mozilla.Firefox' }
        $d.Name | Should -Be 'Mozilla Firefox'
        $d.Version | Should -Be '133.0.3'
        $d.Publisher | Should -Be 'Mozilla'
        $d.Homepage | Should -Be 'https://www.mozilla.org/firefox/'
    }
    It 'refuses what is no package id, before winget sees it' {
        InModuleScope Lotus {
            Test-LotusPkgName 'Mozilla.Firefox' | Should -BeTrue
            Test-LotusPkgName 'x; Remove-Item C:\' | Should -BeFalse
            Test-LotusPkgName '../evil' | Should -BeFalse
            Test-LotusPkgName 'rust & go' -Search | Should -BeFalse
        }
    }
}

Describe 'installing' {
    BeforeEach {
        Mock -ModuleName Lotus Test-LotusWinget { $true }
        Mock -ModuleName Lotus Invoke-LotusWingetText { $script:Show } -ParameterFilter { $Arguments[0] -eq 'show' }
        Mock -ModuleName Lotus Invoke-LotusWingetText { @() } -ParameterFilter { $Arguments[0] -eq 'list' }
        Mock -ModuleName Lotus Invoke-LotusInTheOpen { $global:LotusRan = "$Program $($Arguments -join ' ')"; 0 }
        $global:LotusRan = $null
    }
    It 'shows the card and the exact command, and installs only after a yes' {
        $out = Invoke-LotusWithKeys @('n') { lotus brew info Mozilla.Firefox }
        $out | Should -Match 'Mozilla Firefox'
        $out | Should -Match 'winget install --id Mozilla.Firefox --exact'
        $global:LotusRan | Should -BeNullOrEmpty
        $out = Invoke-LotusWithKeys @('y') { lotus brew install Mozilla.Firefox }
        $global:LotusRan | Should -Be 'winget install --id Mozilla.Firefox --exact --source winget'
        $out | Should -Match 'is installed'
    }
    It 'finds an app of the catalog by name, typos and all, and installs its winget id' {
        $out = Invoke-LotusWithKeys @('y', 'y') { lotus install firefx }
        $global:LotusRan | Should -Be 'winget install --id Mozilla.Firefox --exact --source winget'
    }
    It 'says when it is installed already, and installs nothing' {
        Mock -ModuleName Lotus Invoke-LotusWingetText { @('Name Id Version', '------------------------', 'Mozilla Firefox Mozilla.Firefox 133.0') } -ParameterFilter { $Arguments[0] -eq 'list' }
        Mock -ModuleName Lotus ConvertFrom-LotusWingetTable { [pscustomobject]@{ Name = 'Mozilla Firefox'; Id = 'Mozilla.Firefox'; Version = '133.0'; Source = '' } }
        $out = Invoke-LotusWithKeys @('y') { lotus brew info Mozilla.Firefox }
        $out | Should -Match 'already installed'
        $global:LotusRan | Should -BeNullOrEmpty
    }
}

Describe 'the catalog' {
    It 'has a winget id for every app that Windows has, and none for the apps of the Mac' {
        InModuleScope Lotus {
            $all = @(Read-LotusTsv 'apps')
            foreach ($f in $all) { $f.Count | Should -Be 6 -Because "$($f[0]) has the winget column" }
            $cat = @(Get-LotusCatalog)
            $cat.Count | Should -BeGreaterThan 50
            ($cat | Where-Object Name -eq 'Mozilla Firefox').Winget | Should -Be 'Mozilla.Firefox'
            ($cat | Where-Object Name -eq 'iTerm2') | Should -BeNullOrEmpty
            foreach ($a in $cat) { Test-LotusPkgName $a.Winget | Should -BeTrue -Because $a.Name }
        }
    }
}
