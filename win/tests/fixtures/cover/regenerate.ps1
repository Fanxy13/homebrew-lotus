# Writes expected.tsv: the SHA-256 of what lib/cover.pl (the Mac's and Linux' drawing of a cover) makes of each picture.
#   pwsh win/tests/fixtures/cover/regenerate.ps1        (needs perl)
. (Join-Path $PSScriptRoot 'pictures.ps1')
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) "lotus-cover-$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $pics = Get-CoverPictures
    foreach ($name in $pics.Keys) { [IO.File]::WriteAllBytes((Join-Path $tmp "$name.bmp"), $pics[$name]) }
    $rows = foreach ($case in Get-CoverCases) {
        $name, $cols, $rows_, $mode = $case
        $psi = [System.Diagnostics.ProcessStartInfo]::new('perl')
        $psi.Arguments = (@((Join-Path $repo 'lib/cover.pl'), (Join-Path $tmp "$name.bmp"), "$cols", "$rows_", $mode) | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $ms = [IO.MemoryStream]::new(); $p.StandardOutput.BaseStream.CopyTo($ms); $p.WaitForExit()
        $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($ms.ToArray())).Replace('-', '').ToLowerInvariant()
        "$name`t$cols`t$rows_`t$mode`t$hash"
    }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'expected.tsv'), ($rows -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    "wrote $(@($rows).Count) lines"
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
