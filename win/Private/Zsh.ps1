# Reading the files that the zsh engine writes and sources – settings.zsh, lib/lang/*.zsh, the LOTUS_KEYS list and the
# defaults in lib/core.zsh – and writing values the way zsh's ${(qq)…} does. Nothing is ever expanded or run: only
# the quoting is undone ('single', "double" with its backslashes, $'ANSI-C', bare words with \ escapes).

# One token per match, each starting where the last one ended (\G): the parts of a word, ( ), the ends of commands
$script:ZshToken = [regex]::new(
    '\G(?:''(?<sq>[^'']*)''|\$''(?<ansi>(?:\\[\s\S]|[^''\\])*)''|"(?<dq>(?:\\[\s\S]|[^"\\])*)"|\\(?<esc>[\s\S])|(?<bare>[^ \t\r\n''"\\()#;$]+)|(?<hash>#)|(?<dollar>\$)|(?<paren>[()])|(?<end>[;\n])|(?<ws>[ \t\r]+))',
    [System.Text.RegularExpressions.RegexOptions]::Compiled)

function ConvertFrom-LotusAnsiC {
    # the inside of $'…'
    param([string]$Text)
    [regex]::Replace($Text, '\\(x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|[0-7]{1,3}|[\s\S])', {
            param($m)
            $e = $m.Groups[1].Value
            switch -CaseSensitive -Regex ($e) {
                '^x' { return [string][char][Convert]::ToInt32($e.Substring(1), 16) }
                '^u' { return [char]::ConvertFromUtf32([Convert]::ToInt32($e.Substring(1), 16)) }
                '^[0-7]' { return [string][char][Convert]::ToInt32($e, 8) }
                '^n$' { return "`n" } '^t$' { return "`t" } '^r$' { return "`r" } '^e$' { return [string][char]27 } '^E$' { return [string][char]27 }
                '^a$' { return [string][char]7 } '^b$' { return [string][char]8 } '^f$' { return [string][char]12 } '^v$' { return [string][char]11 }
                default { return $e }
            }
        })
}

# The tokens of a zsh text → a list of @(kind, text): kind 'w' (a word, quoting undone), '(' , ')' or 'end' (a new line or ;)
function Split-LotusZsh {
    param([AllowEmptyString()][string]$Text)
    $tokens = [System.Collections.Generic.List[string[]]]::new()
    $sb = [System.Text.StringBuilder]::new()
    $inWord = $false
    $pos = 0
    $n = $Text.Length
    while ($pos -lt $n) {
        $m = $script:ZshToken.Match($Text, $pos)
        if (-not $m.Success) { throw "Lotus cannot read this zsh text (at character $pos)." }
        $g = $m.Groups
        $pos += $m.Length
        if ($g['sq'].Success) { [void]$sb.Append($g['sq'].Value); $inWord = $true }
        elseif ($g['bare'].Success) { [void]$sb.Append($g['bare'].Value); $inWord = $true }
        elseif ($g['ws'].Success -or $g['end'].Success -or $g['paren'].Success) {
            if ($inWord) { $tokens.Add(@('w', $sb.ToString())); [void]$sb.Clear(); $inWord = $false }
            if ($g['end'].Success) { $tokens.Add(@('end', $g['end'].Value)) }
            elseif ($g['paren'].Success) { $tokens.Add(@($g['paren'].Value, $g['paren'].Value)) }
        }
        elseif ($g['dq'].Success) {
            [void]$sb.Append([regex]::Replace($g['dq'].Value, '\\([$`"\\\n])', { param($x) if ($x.Groups[1].Value -eq "`n") { '' } else { $x.Groups[1].Value } }))
            $inWord = $true
        }
        elseif ($g['ansi'].Success) { [void]$sb.Append((ConvertFrom-LotusAnsiC $g['ansi'].Value)); $inWord = $true }
        elseif ($g['esc'].Success) {
            if ($g['esc'].Value -ne "`n") { [void]$sb.Append($g['esc'].Value); $inWord = $true }
        }
        elseif ($g['hash'].Success) {
            if ($inWord) { [void]$sb.Append('#') }
            else {
                # a comment, to the end of the line (the new line itself ends the command)
                $nl = $Text.IndexOf("`n", $pos)
                $pos = if ($nl -lt 0) { $n } else { $nl }
            }
        }
        elseif ($g['dollar'].Success) { [void]$sb.Append('$'); $inWord = $true }
    }
    if ($inWord) { $tokens.Add(@('w', $sb.ToString())) }
    , $tokens
}

# 'value' with every ' written as '\'' – what zsh's ${(qq)value} gives, and what bash reads the same way
function ConvertTo-LotusQuoted {
    param([AllowEmptyString()][AllowNull()][string]$Value)
    "'" + ([string]$Value).Replace("'", "'\''") + "'"
}

# The undone quoting of one zsh word ('it'\''s' → it's); $null when the text is not exactly one word
function ConvertFrom-LotusQuoted {
    param([AllowEmptyString()][string]$Text)
    try { $t = Split-LotusZsh $Text } catch { return $null }
    if ($t.Count -ne 1 -or $t[0][0] -ne 'w') { return $null }
    $t[0][1]
}

# The words inside NAME=( … ) or NAME+=( … ) of a zsh text → strings ($null when there is no such array).
# With -All every such array is joined (a language file can add twice).
function Get-LotusZshArray {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Name, [switch]$All, $Tokens)
    if ($null -eq $Tokens) { $Tokens = Split-LotusZsh $Text }
    $out = [System.Collections.Generic.List[string]]::new()
    $found = $false
    for ($i = 0; $i -lt $Tokens.Count - 1; $i++) {
        $t = $Tokens[$i]
        if ($t[0] -ne 'w' -or ($t[1] -cne "$Name=" -and $t[1] -cne "$Name+=")) { continue }
        if ($Tokens[$i + 1][0] -ne '(') { continue }
        $found = $true
        for ($j = $i + 2; $j -lt $Tokens.Count; $j++) {
            $w = $Tokens[$j]
            if ($w[0] -eq ')') { break }
            if ($w[0] -eq 'w') { $out.Add($w[1]) }
        }
        $i = $j
        if (-not $All) { break }
    }
    if (-not $found) { return $null }
    , $out.ToArray()
}

# The simple commands of a zsh text, each as the list of its words (arrays in ( ) are left out)
function Get-LotusZshCommands {
    param([AllowEmptyString()][string]$Text, $Tokens)
    if ($null -eq $Tokens) { $Tokens = Split-LotusZsh $Text }
    $cur = [System.Collections.Generic.List[string]]::new()
    $depth = 0
    foreach ($t in $Tokens) {
        switch ($t[0]) {
            'end' { if ($depth -eq 0 -and $cur.Count) { , $cur.ToArray(); $cur.Clear() } }
            '(' { $depth++ }
            ')' { if ($depth) { $depth-- } }
            default { if ($depth -eq 0) { $cur.Add($t[1]) } }
        }
    }
    if ($cur.Count) { , $cur.ToArray() }
}
