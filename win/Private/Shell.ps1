# The PowerShell adapter – what lib/init.zsh is for zsh and lib/init.bash for bash: the start screen when a window opens,
# the /commands, the Enter extras, the prompt in the theme's color, and the command line that Lotus prepares.
#
# /weather cannot be a PowerShell alias that takes the rest of the line, and a pasted link with & does not even parse.
# So, as in bash, Enter is bound to a small PSReadLine handler that rewrites the line before PowerShell reads it:
# "/weather Paris" becomes "lotus weather Paris" – you see the real command, and the history keeps it.

$script:ShellOn = $false
$script:Slash = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
$script:PetNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

# Only in a window someone types in: not in scripts, not with output going to a file
function Test-LotusShellHost {
    if ($env:LOTUS_SHELL_TEST -eq '1') { return $true }
    $Host.Name -in 'ConsoleHost', 'Visual Studio Code Host' -and [Environment]::UserInteractive -and -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected
}

# lotus shell-init (from the profile block)
function Enable-LotusShell {
    if (-not (Test-LotusShellHost)) { return }
    $script:ShellOn = $true
    Update-LotusShellTables
    Register-LotusEnterKey
    Set-LotusPrompt
    if (-not (Test-LotusOn $script:S['LOTUS_CONFIGURED']) -and (Test-LotusTty)) {
        Import-LotusCommand setup
        Invoke-LotusSetupWizard | Out-Null
        Initialize-Lotus
        Update-LotusShellTables
        Set-LotusPrompt
    }
    Write-LotusLog DEBUG startup "Shell ready (Lotus $(Get-LotusVersion), $(Get-LotusRoot))"
    if ((Test-LotusOn $script:S['LOTUS_STARTUP']) -and -not $env:LOTUS_SHELL_TEST) { Show-LotusStart }
}

# The /commands of data/commands.tsv and your shortcuts, and the names of your pets
function Update-LotusShellTables {
    $script:Slash.Clear()
    foreach ($row in Read-LotusTsv 'commands') {
        if ($row.Count -lt 3 -or -not $row[1].StartsWith('/')) { continue }
        $sub = if ($row[1] -ceq '/lotus') { '' } else { $row[2] }
        $script:Slash[$row[1]] = $sub
    }
    foreach ($kv in $script:Shortcuts.GetEnumerator()) {
        if ($kv.Value -clike '*|on' -and -not $script:Slash.ContainsKey("/$($kv.Key)")) { $script:Slash["/$($kv.Key)"] = "run $($kv.Key)" }
    }
    $script:PetNames.Clear()
    $pets = Join-Path $script:Paths.Conf 'pets.tsv'
    if ((Test-LotusFeature 'pets') -and (Test-Path -LiteralPath $pets)) {
        foreach ($line in ([string](Read-LotusFile $pets)) -split "`n") {
            if (-not $line -or $line[0] -eq '#') { continue }
            [void]$script:PetNames.Add(($line -split "`t")[0].ToLowerInvariant())
        }
    }
}

# A word as PowerShell reads it back unchanged: bare when that is safe, else in single quotes
function ConvertTo-LotusPsArg {
    param([AllowEmptyString()][string]$Word)
    if ($Word -cmatch '^[A-Za-z0-9_/][A-Za-z0-9_./:,+=%~-]*$') { return $Word }
    "'" + $Word.Replace("'", "''") + "'"
}

# The words of the rest of a line: blanks separate, quotes keep a word together (and go)
function Split-LotusShellWords {
    param([AllowEmptyString()][string]$Text)
    $words = [System.Collections.Generic.List[string]]::new()
    $cur = [System.Text.StringBuilder]::new()
    $quote = [char]0; $has = $false
    foreach ($ch in $Text.ToCharArray()) {
        if ($quote) { if ($ch -eq $quote) { $quote = [char]0 } else { [void]$cur.Append($ch) }; continue }
        if ($ch -eq '"' -or $ch -eq "'") { $quote = $ch; $has = $true; continue }
        if ([char]::IsWhiteSpace($ch)) { if ($has) { $words.Add($cur.ToString()); [void]$cur.Clear(); $has = $false }; continue }
        [void]$cur.Append($ch); $has = $true
    }
    if ($has) { $words.Add($cur.ToString()) }
    , $words.ToArray()
}

# Enter: the line rewritten (lotus_accept_line in lib/init.zsh), or $null to run it as typed – only for features that are on.
#   /weather Paris → lotus weather Paris (also your shortcuts) · /unknown → lotus suggest /unknown · a pasted link →
#   lotus open <link> · open Spotify → lotus app Spotify · a pet's name → lotus pet <name> '…' · who is the goat? → lotus goat
function Convert-LotusShellLine {
    param([AllowEmptyString()][string]$Line)
    if ($Line.Contains("`n")) { return $null }
    $t = $Line.Trim()
    if (-not $t) { return $null }
    if ($t -match '^(?i)who is the goat\??$') { return 'lotus goat' }
    $first = ($t -split '\s+', 2)[0]
    $rest = if ($t.Length -gt $first.Length) { $t.Substring($first.Length).TrimStart() } else { '' }
    $args_ = { param($r) $w = Split-LotusShellWords $r; if ($w.Count) { ' ' + (($w | ForEach-Object { ConvertTo-LotusPsArg $_ }) -join ' ') } else { '' } }
    if (-not $rest -and $t -match '^(?i)https?://\S+$' -and (Test-LotusFeature 'web')) {
        return "lotus open $(ConvertTo-LotusPsArg $t)"
    }
    if ($first -ceq 'open' -and $rest -and -not $rest.StartsWith('-') -and (Test-LotusFeature 'apps')) {
        $target = (Split-LotusShellWords $rest) -join ' '
        $path = if ($target.StartsWith('~')) { (Get-LotusHome) + $target.Substring(1) } else { $target }
        if (-not (Test-Path -LiteralPath $path) -and -not $target.Contains(':') -and -not $target.Contains('.')) {
            return "lotus app $(ConvertTo-LotusPsArg $target)"
        }
        return $null
    }
    if ($first.StartsWith('/') -and -not (Test-Path -LiteralPath $first)) {
        $sub = $null
        if ($script:Slash.TryGetValue($first, [ref]$sub)) { return "lotus$(if ($sub) { " $sub" })$(& $args_ $rest)" }
        if ($first -cmatch '^/[A-Za-z][A-Za-z0-9_-]*$') { return "lotus suggest $(ConvertTo-LotusPsArg $first)$(& $args_ $rest)" }
        return $null
    }
    if ($script:PetNames.Count) {
        $name = ($first -replace '[,:!?.]+$', '').ToLowerInvariant()
        if ($name -and $script:PetNames.Contains($name) -and -not (Get-Command -Name ($first -replace '[,:!?.]+$', '') -ErrorAction SilentlyContinue)) {
            $said = $t.Substring($first.Length) -replace '^[\s,:!?.]+', ''
            return "lotus pet $name$(if ($said) { ' ' + (ConvertTo-LotusPsArg $said) })"
        }
    }
    $null
}

function Register-LotusEnterKey {
    if (-not (Get-Module PSReadLine)) { return }
    if ($null -eq $script:EnterWas) {
        $script:EnterWas = (Get-PSReadLineKeyHandler -Chord Enter -ErrorAction SilentlyContinue | Select-Object -First 1).Function
        if (-not $script:EnterWas -or $script:EnterWas -eq 'LotusAcceptLine') { $script:EnterWas = 'AcceptLine' }
    }
    # (no closure: this script block belongs to the Lotus module, so it sees its functions and $script: state; when the
    # module is gone it simply accepts the line)
    Set-PSReadLineKeyHandler -Chord Enter -BriefDescription 'LotusAcceptLine' -Description 'Lotus: /commands, links, open <app> and pets, then the line runs' -ScriptBlock {
        param($key, $arg)
        $line = $null; $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        $new = $null
        try { $new = Convert-LotusShellLine $line } catch { }
        if ($new) { [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $new) }
        if ($script:EnterWas -eq 'ValidateAndAcceptLine') { [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine($key, $arg) }
        else { [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($key, $arg) }
    }
}

# The prompt in the theme's color (/settings → Colored prompt) – yours comes back when it is turned off
function Set-LotusPrompt {
    if ($null -eq $script:PromptWas) {
        $f = Get-Item -LiteralPath function:global:prompt -ErrorAction SilentlyContinue
        $script:PromptWas = if ($f) { $f.ScriptBlock } else { { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " } }
    }
    if (Test-LotusOn $script:S['LOTUS_PROMPT']) {
        $color = "$([char]27)[$($script:C['accent'])m"
        $reset = "$([char]27)[0m"
        Set-Item -LiteralPath function:global:prompt -Value ({
                $dir = Split-Path -Leaf $executionContext.SessionState.Path.CurrentLocation.ProviderPath
                if (-not $dir) { $dir = $executionContext.SessionState.Path.CurrentLocation.ProviderPath }
                "$color$([Environment]::UserName)@$([Environment]::MachineName.ToLowerInvariant()) $dir>$reset "
            }.GetNewClosure())
    } elseif ($script:PromptWas) {
        Set-Item -LiteralPath function:global:prompt -Value $script:PromptWas
    }
}

# After a lotus command in this window (the lotus function of lib/init.zsh): new settings, shortcuts and pets take
# effect, a command Lotus prepared goes onto the command line (it is never run), an uninstall unloads Lotus.
function Update-LotusShellAfter {
    param([string]$Command)
    if ($Command -cin 'uninstall' -and -not (Test-Path -LiteralPath $script:Paths.Settings)) { Disable-LotusShell; return }
    if ($Command -cin 'settings', 'config', 'setup', 'features', 'pets', 'pet', 'feed', 'zetamac', 'shortcut', 'shortcuts', 'logo', 'themes') {
        Initialize-Lotus
        Update-LotusShellTables
        Set-LotusPrompt
    }
    $f = Join-Path $script:Paths.Cache 'ai-prompt'
    if (Test-Path -LiteralPath $f) {
        $text = ([string](Read-LotusFile $f)).TrimEnd("`n")
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        if ($text -and (Get-Module PSReadLine)) {
            # PSReadLine raises OnIdle while it waits for keys: that is when the line can be filled. The event it raises
            # carries no MessageData ($Event.MessageData was empty, and an empty Insert put a NUL key, ^@, on the line),
            # and an event's action runs in a scope of its own (no closure, no module) – so the text is in the action.
            Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action (Get-LotusLineAction $text) | Out-Null
        }
    }
}

# The action that puts text onto the line PSReadLine is reading – the command a Lotus command prepared (it is never run):
# the text as a single-quoted string, every quote PowerShell takes for one (' ‘ ’ ‚ ‛) doubled
function Get-LotusLineAction {
    param([string]$Text)
    $literal = "'" + ($Text -replace "['\u2018\u2019\u201A\u201B]", '$0$0') + "'"
    [scriptblock]::Create("[Microsoft.PowerShell.PSConsoleReadLine]::Insert($literal)")
}

# Lotus leaves this window (after lotus uninstall): Enter, the prompt and the module as they were
function Disable-LotusShell {
    if (Get-Module PSReadLine) {
        $was = if ($script:EnterWas) { $script:EnterWas } else { 'AcceptLine' }
        Set-PSReadLineKeyHandler -Chord Enter -Function $was
    }
    if ($script:PromptWas) { Set-Item -LiteralPath function:global:prompt -Value $script:PromptWas }
    $script:ShellOn = $false
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
}
