# settings.zsh: one line KEY='value' for every setting, the file zsh sources. The same format on every system, so a
# file can move between them. A value with an apostrophe is written as zsh writes it: 'it'\''s'.

function ConvertFrom-LotusQuoted {
    param([string]$Text)
    if ($Text -notmatch "^'.*'$" -or $Text.Length -lt 2) { return $null }
    $Text.Substring(1, $Text.Length - 2).Replace("'\''", "'")
}

function ConvertTo-LotusQuoted {
    param([string]$Value)
    "'" + $Value.Replace("'", "'\''") + "'"
}

function Read-LotusSettings {
    param([Parameter(Mandatory)][string]$Path)
    $settings = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $settings }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
        if ($line -match '^(LOTUS_[A-Z0-9_]+)=(.*)$') {
            $value = ConvertFrom-LotusQuoted $Matches[2]
            if ($null -ne $value) { $settings[$Matches[1]] = $value }
        }
    }
    $settings
}

function Set-LotusSetting {
    # Changes or adds one setting and leaves every other line as it is (comments, the shortcuts line, keys of newer versions).
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Name -notmatch '^LOTUS_[A-Z0-9_]+$') { throw "Not a Lotus setting name: $Name" }
    if ($Value -match "[`r`n]") { throw 'A setting is one line.' }
    $new = "$Name=$(ConvertTo-LotusQuoted $Value)"
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = @(Get-Content -LiteralPath $Path -Encoding utf8) }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -like "$Name=*") { $lines[$i] = $new; $found = $true }
    }
    if (-not $found) { $lines += $new }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    # LF line ends, no byte order mark: zsh reads the file too
    [System.IO.File]::WriteAllText($Path, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}
