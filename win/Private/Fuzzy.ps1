# Fuzzy matching, shared by commands, apps, packages and shortcuts – the same scores as lib/fuzzy.zsh, so the same typo
# gets the same answer on every system (the contract tests compare both engines).

# Edit distance between two strings
function Get-LotusLevenshtein {
    param([AllowEmptyString()][string]$A, [AllowEmptyString()][string]$B)
    $la = $A.Length; $lb = $B.Length
    if (-not $la) { return $lb }
    if (-not $lb) { return $la }
    $prev = [int[]]::new($lb + 1)
    $cur = [int[]]::new($lb + 1)
    for ($j = 0; $j -le $lb; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $la; $i++) {
        $cur[0] = $i
        $ca = $A[$i - 1]
        for ($j = 1; $j -le $lb; $j++) {
            $cost = if ($ca -ceq $B[$j - 1]) { 0 } else { 1 }
            $d = $prev[$j] + 1
            $ins = $cur[$j - 1] + 1
            $sub = $prev[$j - 1] + $cost
            if ($ins -lt $d) { $d = $ins }
            if ($sub -lt $d) { $d = $sub }
            $cur[$j] = $d
        }
        $tmp = $prev; $prev = $cur; $cur = $tmp
    }
    $prev[$lb]
}

# zsh's (L) and [^[:alnum:]] → only letters and digits, lower case
$script:NotAlnum = [regex]::new('[^\p{L}\p{Nd}]', 'Compiled')
$script:NotAlnumSpace = [regex]::new('[^\p{L}\p{Nd} ]', 'Compiled')
function ConvertTo-LotusAlnum {
    param([AllowEmptyString()][string]$Text, [switch]$KeepSpaces)
    if ($KeepSpaces) { $script:NotAlnumSpace.Replace($Text.ToLowerInvariant(), '') } else { $script:NotAlnum.Replace($Text.ToLowerInvariant(), '') }
}

function Get-LotusScore1 {
    # <normalized query> <candidate>
    param([AllowEmptyString()][string]$Q, [AllowEmptyString()][string]$Candidate)
    $c = ConvertTo-LotusAlnum $Candidate
    if (-not $Q -or -not $c) { return 0 }
    if ($Q -ceq $c) { return 100 }
    if ($c.StartsWith($Q, [StringComparison]::Ordinal)) { return 90 + [Math]::Truncate(9 * $Q.Length / $c.Length) }
    if ($c.Contains($Q)) { return 75 + [Math]::Truncate(10 * $Q.Length / $c.Length) }
    $dist = Get-LotusLevenshtein $Q $c
    $m = [Math]::Max($Q.Length, $c.Length)
    $best = [Math]::Truncate(($m - $dist) * 80 / $m)
    # a typo in the first letters of a longer name ("visul" → "visual studio code")
    if ($c.Length -gt $Q.Length + 2 -and $Q.Length -ge 3) {
        $d2 = Get-LotusLevenshtein $Q $c.Substring(0, $Q.Length)
        $s2 = [Math]::Truncate(($Q.Length - $d2) * 72 / $Q.Length)
        if ($s2 -gt $best) { $best = $s2 }
    }
    [int]$best
}

# Similarity of a typed query and a candidate, 0–100:
#   100 exact · 90+ start of the name · 75+ inside the name · below: typo distance.
#   Multi-word names also match by initials ("vscode") and by single words ("firefx" → Mozilla Firefox)
function Get-LotusScore {
    param([AllowEmptyString()][string]$Query, [AllowEmptyString()][string]$Candidate)
    $q = ConvertTo-LotusAlnum $Query
    $best = Get-LotusScore1 $q $Candidate
    if ($best -ge 90) { return $best }
    $words = @((ConvertTo-LotusAlnum $Candidate -KeepSpaces) -split ' ' | Where-Object { $_ })
    if ($words.Count -gt 1) {
        $ini = -join ($words | ForEach-Object { $_[0] })
        if ($q.StartsWith($ini, [StringComparison]::Ordinal) -and $ini.Length -ge 2 -and $best -lt 80) { $best = 80 }
        foreach ($w in $words) {
            if ($w.Length -lt 3) { continue }
            $r = Get-LotusScore1 $q $w
            if ($r - 6 -gt $best) { $best = $r - 6 }
        }
    }
    [int]$best
}

# zsh's (On): descending, digit runs compared as numbers, the rest by character code (zsh in a UTF-8 C locale and on a Mac)
function Compare-LotusZshNumeric {
    param([string]$A, [string]$B)
    $i = 0
    $n = [Math]::Min($A.Length, $B.Length)
    while ($i -lt $n -and $A[$i] -ceq $B[$i]) { $i++ }
    if (($i -lt $A.Length -and [char]::IsDigit($A[$i])) -or ($i -lt $B.Length -and [char]::IsDigit($B[$i]))) {
        $s = $i
        while ($s -gt 0 -and [char]::IsDigit($A[$s - 1])) { $s-- }
        $ea = $s; while ($ea -lt $A.Length -and [char]::IsDigit($A[$ea])) { $ea++ }
        $eb = $s; while ($eb -lt $B.Length -and [char]::IsDigit($B[$eb])) { $eb++ }
        if ($ea -gt $s -and $eb -gt $s) {
            $da = $A.Substring($s, $ea - $s).TrimStart('0'); $db = $B.Substring($s, $eb - $s).TrimStart('0')
            if ($da.Length -ne $db.Length) { return $da.Length - $db.Length }
            $c = [string]::CompareOrdinal($da, $db)
            if ($c -ne 0) { return $c }
        }
    }
    [string]::CompareOrdinal($A, $B)
}

# Rank candidates: the best first → @{ Names; Scores }   (lotus_rank <query> <minimum score> <candidate>…)
function Get-LotusRank {
    param([AllowEmptyString()][string]$Query, [int]$Min, [string[]]$Candidates)
    $scored = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $Candidates) {
        if ([string]::IsNullOrEmpty($c)) { continue }
        $s = Get-LotusScore $Query $c
        if ($s -ge $Min) { $scored.Add(('{0:000}' -f $s) + "`t" + $c) }
    }
    $arr = $scored.ToArray()
    [Array]::Sort($arr, [System.Comparison[string]] { param($x, $y) - (Compare-LotusZshNumeric $x $y) })
    [pscustomobject]@{
        Names  = @($arr | ForEach-Object { $_.Substring(4) })
        Scores = @($arr | ForEach-Object { [int]$_.Substring(0, 3) })
    }
}

# Decide what the user meant: exact or clearly unique → no question; typos → "Did you mean …?"; several → a short list.
#   → the choice, or $null (none, or cancelled)     (lotus_pick)
function Select-LotusPick {
    param([AllowEmptyString()][string]$Query, [string]$What, [string[]]$Candidates)
    $r = Get-LotusRank $Query 55 $Candidates
    if (-not $r.Names.Count) { return $null }
    $top = $r.Scores[0]
    $second = if ($r.Scores.Count -gt 1) { $r.Scores[1] } else { 0 }
    if ($top -eq 100 -or ($top -ge 90 -and $top - $second -ge 8)) { return $r.Names[0] }
    if (($top -ge 60 -and $top - $second -ge 12) -or $r.Names.Count -eq 1) {
        if (-not (Read-LotusConfirm "Did you mean `"$($r.Names[0])`"?" 'y')) { return $null }
        return $r.Names[0]
    }
    $pick = Read-LotusChoice "Which $What did you mean?" @($r.Names | Select-Object -First 6)
    if ($null -eq $pick) { return $null }
    $r.Names[$pick - 1]
}
