# /ai on Windows – answers from Claude, an OpenAI-compatible API or Ollama, right in the window: a port of the parts of
# lib/cmd/ai.zsh that need no AI program. The AI terminal with its tools (files, commands, web pages), the web chat,
# models on this computer and the statistics belong to the AI program (lib/ai, Swift), which has no Windows build yet –
# here /ai is a chat that answers and remembers the conversation for an hour, and cannot read or change files or run
# commands. The instructions are data/ai/system.md ("## windows" and "## answer"), the same file as everywhere.
#   /ai                      a chat (/new forgets, an empty line ends it)
#   /ai <question>           one answer, with the conversation of the last hour
#   /ai new [question]       forget the conversation
#   /ai explain|write <text> · /ai summarize [file] (default: the clipboard) · /ai command <task>
#   lotus ai login | logout | key [claude|openai|remove] | status
# Keys: ANTHROPIC_API_KEY or the saved "lotus-ai-claude"; LOTUS_AI_KEY or "lotus-ai" for the OpenAI-compatible API at
# LOTUS_AI_URL (/settings → AI) – saved for this Windows user with DPAPI (Set-LotusSecret). A key goes only into the
# header of the request to its provider, never into a file of Lotus, a log or a command line.

function script:Invoke-Lotusai {
    param([string]$Cmd, [string[]]$Rest)
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    $more = [string[]]@($Rest | Select-Object -Skip 1)
    $words = $more -join ' '
    switch -CaseSensitive ($sub) {
        'status' { return Show-LotusAiStatus }
        'login' { return $(if (Invoke-LotusAiLogin) { St 0 } else { St 1 }) }
        'connect' { return $(if (Invoke-LotusAiLogin) { St 0 } else { St 1 }) }
        'logout' { return Invoke-LotusAiLogout }
        'key' { return Invoke-LotusAiKey $(if ($more.Count) { $more[0] } else { '' }) }
        'keys' { return Invoke-LotusAiKey $(if ($more.Count) { $more[0] } else { '' }) }
        'new' { return Reset-LotusAiChat $words }
        'clear' { return Reset-LotusAiChat $words }
        'reset' { return Reset-LotusAiChat $words }
        'explain' { return Invoke-LotusAiTask 'Explain clearly and completely, for someone using PowerShell on Windows. Use an example where it helps.' "Explain: $words" }
        'write' { return Invoke-LotusAiTask 'Help the user write text. Return only the finished text.' "Write: $words" }
        'summarize' { return Invoke-LotusAiSummarize $(if ($more.Count) { $more[0] } else { '' }) }
        'summarise' { return Invoke-LotusAiSummarize $(if ($more.Count) { $more[0] } else { '' }) }
        'command' { return Invoke-LotusAiCommand $words }
        'chat' { return Invoke-LotusAiChat }
        '' { return Invoke-LotusAiChat }
    }
    if ($sub -cin 'server', 'web', 'local', 'stats', 'statistics') { return Show-LotusAiNotHere $sub }
    Invoke-LotusAiOnce ($Rest -join ' ')
}

# ── Providers ─────────────────────────────────────────────────

function script:Get-LotusAiClaudeKey { if ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY } else { [string](Get-LotusSecret 'lotus-ai-claude') } }
function script:Get-LotusAiOpenAiKey { if ($env:LOTUS_AI_KEY) { $env:LOTUS_AI_KEY } else { [string](Get-LotusSecret 'lotus-ai') } }
# Where the Claude API is (LOTUS_AI_CLAUDE_URL, as in the AI program) and where Ollama is (its own OLLAMA_HOST)
function script:Get-LotusAiClaudeUrl { if ($env:LOTUS_AI_CLAUDE_URL) { $env:LOTUS_AI_CLAUDE_URL } else { 'https://api.anthropic.com/v1/messages' } }
function script:Get-LotusAiOllamaUrl {
    $h = [string]$env:OLLAMA_HOST
    if (-not $h) { return 'http://localhost:11434' }
    if ($h -notmatch '^https?://') { $h = "http://$h" }
    $h = $h.TrimEnd('/') -replace '^(https?://)0\.0\.0\.0', '$1127.0.0.1'
    if ($h -notmatch ':\d+$') { $h += ':11434' }
    $h
}
function script:Test-LotusAiLoopback { param([string]$Url) $Url -match '^https?://(localhost|127\.\d+\.\d+\.\d+|\[::1\])(:|/|$)' }

# The models Ollama has (it answers within a second when it runs)
function script:Get-LotusAiOllamaModels {
    $url = Get-LotusAiOllamaUrl
    try {
        $r = Invoke-RestMethod -Uri "$url/api/tags" -TimeoutSec 1 -NoProxy:(Test-LotusAiLoopback $url) -ErrorAction Stop
        @($r.models | ForEach-Object { [string]$_.name } | Where-Object { $_ })
    } catch { @() }
}

# claude-opus-5-5 → Claude Opus 5.5
function script:Get-LotusAiClaudeName {
    param([string]$Id)
    $parts = $Id -split '-'
    if ($parts.Count -lt 3 -or $parts[0] -cne 'claude') { return $Id }
    $family = $parts[1].Substring(0, 1).ToUpper() + $parts[1].Substring(1)
    $version = @($parts | Select-Object -Skip 2 | Where-Object { $_.Length -le 2 -and $_ -match '^\d+$' }) -join '.'
    "Claude $family$(if ($version) { " $version" })"
}

# The provider that answers → @{ Name; Model; Url; Key; Label }, or $null. Automatic: Claude, then Ollama, then an
# OpenAI-compatible API (Apple Intelligence and a model on this computer – the Mac's – count as automatic here).
function script:Get-LotusAiProvider {
    $want = [string]$script:S['LOTUS_AI_PROVIDER']
    $order = if ($want -and $want -cnotin 'auto', 'apple', 'local') { @($want) } else { @('claude', 'ollama', 'openai') }
    $model = [string]$script:S['LOTUS_AI_MODEL']
    foreach ($p in $order) {
        if ($p -ceq 'claude') {
            $key = Get-LotusAiClaudeKey
            if (-not $key) { continue }
            $m = if ($model -like 'claude-*') { $model } else { 'claude-opus-5-5' }
            return [pscustomobject]@{ Name = 'claude'; Model = $m; Url = (Get-LotusAiClaudeUrl); Key = $key; Label = (Get-LotusAiClaudeName $m) }
        }
        if ($p -ceq 'ollama') {
            $models = @(Get-LotusAiOllamaModels)
            if (-not $models.Count) { continue }
            $m = if ($models -ccontains $model) { $model } else { $models[0] }
            return [pscustomobject]@{ Name = 'ollama'; Model = $m; Url = (Get-LotusAiOllamaUrl); Key = ''; Label = "$m · Ollama" }
        }
        if ($p -ceq 'openai') {
            $url = ([string]$script:S['LOTUS_AI_URL']).TrimEnd('/')
            $key = Get-LotusAiOpenAiKey
            if (-not $url -or -not $key) { continue }
            $m = if ($model) { $model } else { 'gpt-4o-mini' }
            return [pscustomobject]@{ Name = 'openai'; Model = $m; Url = $url; Key = $key; Label = $m }
        }
    }
    $null
}

# No AI yet: what can be done (in a terminal: connect Claude right away) → $true when one was connected
function script:Show-LotusAiNone {
    if ((Test-LotusTty) -and (Test-LotusOutTty)) {
        Write-LotusHeader 'AI' 'no AI connected yet'
        Write-LotusText 'Lotus did not find an AI it can use on this PC.'
        Write-LotusBlank
        $pick = Read-LotusChoice 'What do you want to do?' @('Connect Claude – paste an API key (about a minute)', 'Show the other options', 'Cancel')
        if ($pick -eq 1 -and (Invoke-LotusAiLogin)) { return $true }
        if ($pick -ne 2) { return $false }
    }
    Write-LotusError 'No AI is available yet' 'Lotus did not find an AI it can use on this PC.' @(
        'Claude: lotus ai login  (opens the key page, then paste the key)'
        'Ollama: winget install Ollama.Ollama, open it and download a model, e.g. ollama pull qwen3'
        'Other: set the AI URL in /settings and add a key with: lotus ai key openai')
    $false
}

# The provider, or after Show-LotusAiNone the one connected just now, or $null
function script:Use-LotusAiProvider {
    $p = Get-LotusAiProvider
    if ($p) { return $p }
    if (Show-LotusAiNone) { return (Get-LotusAiProvider) }
    $null
}

# ── Instructions and memory ───────────────────────────────────

# A section of data/ai/system.md
function script:Get-LotusAiSection {
    param([string]$Name)
    $text = Read-LotusFile (Join-Path (Get-LotusRoot) 'data/ai/system.md')
    if (-not $text) { return '' }
    $m = [regex]::Match($text, "(?ms)^## $([regex]::Escape($Name))[ \t]*\n(.*?)(?=^## |\z)")
    if ($m.Success) { $m.Groups[1].Value.Trim() } else { '' }
}

# What every answer gets: who it is, where, and how to answer
function script:Get-LotusAiSystem {
    $dir = Format-LotusHomePath (Get-Location).ProviderPath
    $name = if ($script:S['LOTUS_NAME']) { " The user's name is $($script:S['LOTUS_NAME'])." } else { '' }
    $parts = @((Get-LotusAiSection 'windows'), (Get-LotusAiSection 'answer')) | Where-Object { $_ }
    if (-not $parts) { return "You are Lotus AI, a helpful assistant in the user's PowerShell window on Windows. Working folder: $dir. Answer in the user's language." }
    $text = ($parts -join "`n`n").Replace('{{os}}', [string][Environment]::OSVersion.Version).Replace('{{ps}}', [string]$PSVersionTable.PSVersion)
    $text.Replace('{{folder}}', $dir).Replace('{{date}}', (Get-Date).ToString('D')).Replace('{{name}}', $name)
}

# The conversation of /ai: kept for an hour after the last message (like the AI program's), the newest 20 messages
function script:Get-LotusAiConversationFile { Join-Path $script:Paths.Cache 'ai/conversation.json' }
function script:Get-LotusAiConversation {
    $file = Get-LotusAiConversationFile
    $text = Read-LotusFile $file
    if (-not $text) { return }
    try { $c = $text | ConvertFrom-Json -ErrorAction Stop } catch { return }
    if ((Get-LotusEpoch) - [double]$c.updated -ge 3600) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue; return }
    # (one turn after the other into the pipeline: @(Get-LotusAiConversation) is the list)
    $c.turns | Where-Object { $_.role -cin 'user', 'assistant' -and $_.text } | ForEach-Object { @{ role = [string]$_.role; text = [string]$_.text } }
}
function script:Save-LotusAiConversation {
    param([object[]]$Turns)
    $keep = @($Turns | Select-Object -Last 20)
    while ($keep.Count -gt 2 -and (($keep | ForEach-Object { $_.text.Length }) | Measure-Object -Sum).Sum -gt 60000) { $keep = @($keep | Select-Object -Skip 2) }
    if ($keep.Count -and $keep[0].role -cne 'user') { $keep = @($keep | Select-Object -Skip 1) }
    $json = @{ turns = @($keep | ForEach-Object { @{ role = $_.role; text = $_.text } }); summary = ''; updated = [double](Get-LotusEpoch) } | ConvertTo-Json -Depth 5 -Compress
    try { Write-LotusFile (Get-LotusAiConversationFile) $json } catch { Write-LotusLog WARN ai "The conversation could not be saved: $_" }
}
function script:Clear-LotusAiConversation { Remove-Item -LiteralPath (Get-LotusAiConversationFile) -Force -ErrorAction SilentlyContinue }

# ── A request: sent, read as it streams in, never waited for ──
# Start-LotusAiRequest → an object; Update-LotusAiRequest reads what has come (→ $true when it is done: .Text, .Error);
# Stop-LotusAiRequest cancels it. A pet animates while it polls; /ai prints the text as it grows.

# Lotus' thinking levels as Claude's (from the AI program: xhigh came with Opus 4.7, the 4.6 models get max for maximum)
function script:Get-LotusAiClaudeEffort {
    param([string]$Model, [string]$Effort)
    $xhigh = if ($Model -like '*-4-6*') { 'max' } else { 'xhigh' }
    $map = @{ low = 'low'; medium = 'medium'; high = 'high'; max = $xhigh; ultra = 'max' }
    if ($map.ContainsKey($Effort)) { $map[$Effort] } else { 'high' }
}

function script:Start-LotusAiRequest {
    param([string]$System, [string]$Prompt, [object[]]$Messages, [int]$MaxTokens = 64000, [string]$Effort, $Provider)
    if (-not $Provider) { $Provider = Get-LotusAiProvider }
    $req = [pscustomobject]@{ Provider = $Provider; Text = ''; Thinking = ''; Error = ''; Detail = ''; Status = 0; Stop = ''; Done = $false; Stopped = $false
        Client = $null; Cts = $null; Send = $null; Response = $null; Reader = $null; Line = $null }
    if (-not $Provider) { $req.Error = 'No AI is available yet'; $req.Done = $true; return $req }
    # instructions of a command (a pet, /ai explain …) get the line the AI program adds to them
    $sys = if ($System) { "$System`nAnswer in the user's language." } else { Get-LotusAiSystem }
    $turns = if ($Messages) { @($Messages) } else { @(@{ role = 'user'; text = $Prompt }) }
    if (-not $Effort) { $Effort = if ($script:S['LOTUS_AI_EFFORT']) { [string]$script:S['LOTUS_AI_EFFORT'] } else { 'high' } }
    $headers = @{}
    switch ($Provider.Name) {
        'claude' {
            $url = $Provider.Url
            $model = $Provider.Model
            $body = [ordered]@{
                model = $model; max_tokens = $MaxTokens; stream = $true
                system = @(@{ type = 'text'; text = $sys })
                messages = @(foreach ($t in $turns) { @{ role = $t.role; content = @(@{ type = 'text'; text = $t.text }) } })
                cache_control = @{ type = 'ephemeral' }
            }
            # Claude 4.6 and newer think adaptively and take an effort level
            if ($model -notmatch '-4-5|-4-1|-4-0$|claude-3') {
                $body['thinking'] = @{ type = 'adaptive'; display = 'summarized' }
                $body['output_config'] = @{ effort = (Get-LotusAiClaudeEffort $model $Effort) }
                if ($Effort -ceq 'ultra' -and $MaxTokens -eq 64000) { $body['max_tokens'] = 128000 }   # room for the longest thinking
            } elseif ($Effort -cne 'low') {
                $budget = @{ ultra = 48000; max = 32000; high = 16000 }[$Effort]
                if (-not $budget) { $budget = 6000 }
                $body['thinking'] = @{ type = 'enabled'; budget_tokens = $budget }
                $body['max_tokens'] = [Math]::Max($MaxTokens, $budget + 4000)
            }
            $headers['x-api-key'] = $Provider.Key
            $headers['anthropic-version'] = '2023-06-01'
            if ($model -cin 'claude-opus-5-5', 'claude-opus-5', 'claude-sonnet-5-5', 'claude-fable-5-1', 'claude-fable-5') {
                $body['fallbacks'] = 'default'
                $headers['anthropic-beta'] = 'server-side-fallback-2026-07-01'
            }
        }
        'ollama' {
            $url = "$($Provider.Url)/api/chat"
            $body = [ordered]@{ model = $Provider.Model; stream = $true
                messages = @(@{ role = 'system'; content = $sys }) + @(foreach ($t in $turns) { @{ role = $t.role; content = $t.text } }) }
        }
        default {
            $url = "$($Provider.Url)/chat/completions"
            $body = [ordered]@{ model = $Provider.Model; stream = $true
                messages = @(@{ role = 'system'; content = $sys }) + @(foreach ($t in $turns) { @{ role = $t.role; content = $t.text } }) }
            $headers['Authorization'] = "Bearer $($Provider.Key)"
        }
    }
    try {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        if (Test-LotusAiLoopback $url) { $handler.UseProxy = $false }
        $req.Client = [System.Net.Http.HttpClient]::new($handler)
        $req.Client.Timeout = [TimeSpan]::FromMinutes(10)
        $msg = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $url)
        foreach ($h in $headers.Keys) { [void]$msg.Headers.TryAddWithoutValidation($h, $headers[$h]) }
        $msg.Content = [System.Net.Http.StringContent]::new(($body | ConvertTo-Json -Depth 12 -Compress), [System.Text.Encoding]::UTF8, 'application/json')
        $req.Cts = [System.Threading.CancellationTokenSource]::new()
        $req.Send = $req.Client.SendAsync($msg, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $req.Cts.Token)
    } catch {
        $req.Error = "$(Get-LotusAiService $Provider) could not be reached"
        $req.Detail = $_.Exception.Message
        Complete-LotusAiRequest $req
    }
    $req
}

function script:Get-LotusAiService {
    param($Provider)
    switch ($Provider.Name) { 'claude' { 'The Claude API' } 'ollama' { 'Ollama' } default { "The AI at $($Provider.Url)" } }
}

# What an error answer says (the JSON of the providers: error.message, or error)
function script:Get-LotusAiErrorMessage {
    param([string]$Body)
    try {
        $j = $Body | ConvertFrom-Json -ErrorAction Stop
        if ($j.error.message) { return [string]$j.error.message }
        if ($j.error -is [string]) { return $j.error }
        if ($j.message) { return [string]$j.message }
    } catch { }
    Cut ($Body -replace '\s+', ' ').Trim() 200
}

# An answer with an error → .Error and .Detail, in the words of the AI program
function script:Set-LotusAiHttpError {
    param($Req, [int]$Status, [string]$Body)
    $p = $Req.Provider
    $message = Get-LotusAiErrorMessage $Body
    $Req.Status = $Status
    if ($p.Name -ceq 'claude') {
        switch ($Status) {
            401 { $Req.Error = 'The Claude API key was not accepted'; $Req.Detail = 'Connect a new key with: lotus ai login'; return }
            403 { $Req.Error = "This Claude API key may not use $($p.Label)"; $Req.Detail = $message; return }
            404 { $Req.Error = "$($p.Model) was not found"; $Req.Detail = "Choose another model in /settings → AI.  ($message)"; return }
            413 { $Req.Error = 'The conversation is too long'; $Req.Detail = 'Start a new one with /ai new.'; return }
            429 { $Req.Error = 'Too many requests to the Claude API'; $Req.Detail = $message; return }
            529 { $Req.Error = 'Claude is overloaded right now'; $Req.Detail = 'Try again in a minute.'; return }
        }
        $Req.Error = "The Claude API answered with an error ($Status)"; $Req.Detail = $message
        return
    }
    if ($Status -eq 401 -or $Status -eq 403) { $Req.Error = "$(Get-LotusAiService $p) did not accept the key"; $Req.Detail = 'Save a new one with: lotus ai key openai'; return }
    if ($Status -eq 404 -and $p.Name -ceq 'ollama') { $Req.Error = "Ollama has no model $($p.Model)"; $Req.Detail = "Download it with: ollama pull $($p.Model)"; return }
    $Req.Error = "$(Get-LotusAiService $p) answered with an error ($Status)"; $Req.Detail = $message
}

# One line of the stream: Claude's and OpenAI's server-sent events, Ollama's lines of JSON
function script:Read-LotusAiStreamLine {
    param($Req, [string]$Line)
    $p = $Req.Provider.Name
    if ($p -ceq 'ollama') {
        if (-not $Line.Trim()) { return }
        try { $j = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return }
        if ($j.error) { $Req.Error = 'Ollama stopped with an error'; $Req.Detail = [string]$j.error; $Req.Done = $true; return }
        if ($j.message.thinking) { $Req.Thinking += [string]$j.message.thinking }
        if ($j.message.content) { $Req.Text += [string]$j.message.content }
        if ($j.done) { $Req.Stop = [string]$j.done_reason; $Req.Done = $true }
        return
    }
    if (-not $Line.StartsWith('data:')) { return }
    $data = $Line.Substring(5).Trim()
    if (-not $data) { return }
    if ($data -ceq '[DONE]') { $Req.Done = $true; return }
    try { $j = $data | ConvertFrom-Json -ErrorAction Stop } catch { return }      # (a line that is not JSON is left out)
    if ($p -ceq 'claude') {
        switch ([string]$j.type) {
            'content_block_delta' {
                if ($j.delta.type -ceq 'text_delta') { $Req.Text += [string]$j.delta.text }
                elseif ($j.delta.type -ceq 'thinking_delta') { $Req.Thinking += [string]$j.delta.thinking }
            }
            'message_delta' { if ($j.delta.stop_reason) { $Req.Stop = [string]$j.delta.stop_reason } }
            'message_stop' { $Req.Done = $true }
            'error' { $Req.Error = 'The Claude API stopped with an error'; $Req.Detail = [string]$j.error.message; $Req.Done = $true }
        }
        return
    }
    if ($j.error) { $Req.Error = "$(Get-LotusAiService $Req.Provider) stopped with an error"; $Req.Detail = Get-LotusAiErrorMessage $data; $Req.Done = $true; return }
    $d = @($j.choices)[0].delta
    if ($d.reasoning_content) { $Req.Thinking += [string]$d.reasoning_content }
    if ($d.content) { $Req.Text += [string]$d.content }
    if (@($j.choices)[0].finish_reason) { $Req.Stop = [string]@($j.choices)[0].finish_reason }
}

# Reads what has arrived, without waiting → $true when the answer is complete (or failed: .Error)
function script:Update-LotusAiRequest {
    param($Req)
    if ($Req.Done) { return $true }
    try {
        if ($Req.Send) {
            if (-not $Req.Send.IsCompleted) { return $false }
            $resp = $Req.Send.GetAwaiter().GetResult()
            $Req.Send = $null
            $Req.Response = $resp
            if (-not $resp.IsSuccessStatusCode) {
                Set-LotusAiHttpError $Req ([int]$resp.StatusCode) ($resp.Content.ReadAsStringAsync().GetAwaiter().GetResult())
                Complete-LotusAiRequest $Req
                return $true
            }
            $Req.Status = [int]$resp.StatusCode
            $Req.Reader = [System.IO.StreamReader]::new($resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult(), [System.Text.Encoding]::UTF8)
        }
        while ($true) {
            if (-not $Req.Line) { $Req.Line = $Req.Reader.ReadLineAsync() }
            if (-not $Req.Line.IsCompleted) { return $false }
            $line = $Req.Line.GetAwaiter().GetResult()
            $Req.Line = $null
            if ($null -eq $line) { break }
            Read-LotusAiStreamLine $Req $line
            if ($Req.Done) { break }
        }
    } catch {
        if (-not $Req.Error -and -not $Req.Stopped) {
            $Req.Error = "$(Get-LotusAiService $Req.Provider) could not be reached"
            $e = $_.Exception
            while ($e.InnerException) { $e = $e.InnerException }
            $Req.Detail = $e.Message
        }
    }
    Complete-LotusAiRequest $Req
    $true
}

function script:Complete-LotusAiRequest {
    param($Req)
    $Req.Done = $true
    foreach ($x in @($Req.Reader, $Req.Response, $Req.Client, $Req.Cts)) { if ($x) { try { $x.Dispose() } catch { } } }
    $Req.Reader = $null; $Req.Response = $null; $Req.Client = $null; $Req.Cts = $null; $Req.Send = $null; $Req.Line = $null
}

function script:Stop-LotusAiRequest {
    param($Req)
    if (-not $Req -or $Req.Done) { return }
    $Req.Stopped = $true
    try { if ($Req.Cts) { $Req.Cts.Cancel() } } catch { }
    Complete-LotusAiRequest $Req
}

# The answer without a model's thoughts in <think> … </think> (some models of Ollama write them into the text)
function script:Get-LotusAiVisibleText {
    param([AllowEmptyString()][string]$Text)
    $t = [regex]::Replace($Text, '(?s)<think>.*?</think>\s*', '')
    $i = $t.IndexOf('<think>')
    if ($i -ge 0) { $t = $t.Substring(0, $i) }
    $t
}

# ── On screen: the answer as it streams in ────────────────────
# Words wrap at the window's width, two spaces in; **bold**, `code`, # headings and fenced code blocks are shown as
# such, everything else as the AI wrote it.

function script:New-LotusAiRender {
    @{ Col = 0; Word = ''; Line = ''; Space = $false; Start = $true; Bold = $false; Code = $false; Head = $false; HeadOpen = $false; Fence = 0
        Width = [Math]::Max(20, (Get-LotusColumns) - 4); Out = [System.Text.StringBuilder]::new() }
}

function script:Add-LotusAiRender {
    param($Render, [AllowEmptyString()][string]$Text)
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq "`r") { continue }
        if ($Render.Fence) {
            if ($ch -eq "`n") { Write-LotusAiCodeLine $Render } else { $Render.Line += $ch }
            continue
        }
        if ($ch -eq "`n") {
            Write-LotusAiWord $Render
            # the line that opens a code block ended here: the code comes next (the fence line is left out)
            if ($Render.Fence) { $Render.Fence = 2; $Render.Line = ''; continue }
            Write-LotusAiNewline $Render
        }
        elseif ($ch -eq ' ' -or $ch -eq "`t") { Write-LotusAiWord $Render; if ($Render.Col) { $Render.Space = $true } }
        else { $Render.Word += $ch }
    }
    Write-LotusRaw $Render.Out.ToString()
    [void]$Render.Out.Clear()
}

function script:Write-LotusAiNewline {
    param($Render)
    if ($Render.Head -or $Render.Bold) { [void]$Render.Out.Append("$([char]27)[22m") }
    if ($Render.Code) { [void]$Render.Out.Append("$([char]27)[39m") }
    $Render.Head = $false; $Render.Bold = $false; $Render.Code = $false
    [void]$Render.Out.Append("`n")
    $Render.Col = 0; $Render.Space = $false; $Render.Start = $true
}

function script:Write-LotusAiWord {
    param($Render)
    $w = $Render.Word
    if (-not $w) { return }
    $Render.Word = ''
    $esc = [char]27
    if ($Render.Start) {
        $Render.Start = $false
        if ($w.StartsWith('```')) { $Render.Fence = 1; $Render.Line = $w.Substring(3); return }     # the rest of the line names the language
        if ($w -match '^#{1,6}$') { $Render.Head = $true; $Render.HeadOpen = $true; $Render.Start = $true; return }
        if ($w -ceq '*') { $w = '-' }
    }
    # **bold** and `code` inside the words
    $sb = [System.Text.StringBuilder]::new()
    $shown = 0
    for ($i = 0; $i -lt $w.Length; $i++) {
        if ($w[$i] -eq '*' -and $i + 1 -lt $w.Length -and $w[$i + 1] -eq '*') {
            $Render.Bold = -not $Render.Bold
            [void]$sb.Append($(if ($Render.Bold -or $Render.Head) { "$esc[1m" } else { "$esc[22m" }))
            $i++
            continue
        }
        if ($w[$i] -eq '`') {
            $Render.Code = -not $Render.Code
            [void]$sb.Append($(if ($Render.Code) { E accent } else { "$esc[39m" }))
            continue
        }
        [void]$sb.Append($w[$i]); $shown++
    }
    if ($Render.Col -and $Render.Col + 1 + $shown -gt $Render.Width) { [void]$Render.Out.Append("`n"); $Render.Col = 0; $Render.Space = $false }
    if (-not $Render.Col) { [void]$Render.Out.Append('  ') }
    elseif ($Render.Space) { [void]$Render.Out.Append(' '); $Render.Col++ }
    $Render.Space = $false
    if ($Render.HeadOpen) { [void]$Render.Out.Append("$esc[1m"); $Render.HeadOpen = $false }
    [void]$Render.Out.Append($sb.ToString())
    $Render.Col += $shown
}

# A line of a code block: as it is, in the accent color – the fence lines themselves are left out
function script:Write-LotusAiCodeLine {
    param($Render)
    $line = $Render.Line
    $Render.Line = ''
    if ($Render.Fence -eq 1) { $Render.Fence = 2; return }
    if ($line.TrimStart().StartsWith('```')) { $Render.Fence = 0; $Render.Start = $true; return }
    [void]$Render.Out.Append("    $(E accent)$line$([char]27)[39m`n")
}

function script:Close-LotusAiRender {
    param($Render)
    if ($Render.Fence -and $Render.Line) { Write-LotusAiCodeLine $Render }
    Write-LotusAiWord $Render
    if ($Render.Col) { [void]$Render.Out.Append("`n") }
    [void]$Render.Out.Append("$([char]27)[0m")
    Write-LotusRaw $Render.Out.ToString()
    [void]$Render.Out.Clear()
}

# One key while the AI answers. (The keys of the tests: only an Esc is taken from the queue here – the other keys
# are for the questions that come after the answer.)
function script:Read-LotusAiKey {
    if ($script:KeyQueueActive) {
        if ($script:KeyQueue.Count -and $script:KeyQueue.Peek() -cin 'esc', 'interrupt') { return $script:KeyQueue.Dequeue() }
        Start-Sleep -Milliseconds 20
        return 'timeout'
    }
    Read-LotusKeyX 0.05
}

# Asks and shows the answer as it arrives (Esc or Ctrl-C stops it) → the answer, or $null (stopped, failed).
# Without a terminal nothing is drawn: the caller gets the text (for a pipe or a file).
function script:Invoke-LotusAiAnswer {
    param([string]$System, [object[]]$Messages, $Provider, [switch]$Spinner)
    $live = Test-LotusOutTty
    $keys = $live -and (Test-LotusTty)
    Write-LotusLog INFO ai "AI answer with $($Provider.Name) (thinking: $(if ($script:S['LOTUS_AI_EFFORT']) { $script:S['LOTUS_AI_EFFORT'] } else { 'high' }))"
    $req = Start-LotusAiRequest -System $System -Messages $Messages -Provider $Provider
    $render = New-LotusAiRender
    $esc = [char]27
    $dots = @('·  ', '·· ', '···', ' ··', '  ·', '   ')
    $shown = 0; $tick = 0; $spin = $false
    if ($keys) { Enter-LotusKeys }
    try {
        while ($true) {
            $done = Update-LotusAiRequest $req
            if ($live -and -not $Spinner) {
                $vis = Get-LotusAiVisibleText $req.Text
                if ($vis.Length -gt $shown) {
                    if ($spin) { Write-LotusRaw "`r$esc[K"; $spin = $false }
                    $new = $vis.Substring($shown)
                    if (-not $shown) { $new = $new.TrimStart() }
                    Add-LotusAiRender $render $new
                    $shown = $vis.Length
                }
            }
            if ($done) { break }
            if ($live -and ($Spinner -or -not $shown)) {
                Write-LotusRaw "`r$esc[K  $(E dim)$($dots[$tick % $dots.Count]) $(if ($req.Thinking) { 'thinking' } else { $Provider.Label })   esc stops$($script:R)"
                $spin = $true
                $tick++
            }
            if ($keys) {
                $k = Read-LotusAiKey
                if ($k -cin 'esc', 'interrupt') { Stop-LotusAiRequest $req; break }
            } else { Start-Sleep -Milliseconds 30 }
        }
    } finally {
        if ($spin) { Write-LotusRaw "`r$esc[K" }
        if ($live -and -not $Spinner) { Close-LotusAiRender $render }
        if ($keys) { Exit-LotusKeys }
    }
    if ($req.Stopped) { Write-LotusDim 'Stopped.'; return $null }
    if ($req.Error) {
        Write-LotusLog WARN ai "$($req.Error)$(if ($req.Detail) { " – $($req.Detail)" })"
        Write-LotusError $req.Error $req.Detail
        return $null
    }
    $text = (Get-LotusAiVisibleText $req.Text).Trim()
    if (-not $text) {
        Write-LotusError 'The AI gave no answer' $(if ($req.Stop -ceq 'refusal') { 'It declined to answer this one.' } elseif ($req.Stop -ceq 'max_tokens') { 'It ran out of room while thinking.' } else { 'Try again, or ask in other words.' })
        return $null
    }
    $text
}

# ── /ai: the chat and single answers ──────────────────────────

# A line typed in the chat (the editing of the console; the tests type with Read-LotusLine)
function script:Read-LotusAiLine {
    param([string]$Label)
    if ($script:LineHook -or $script:KeyQueueActive) { return Read-LotusLine $Label '' }
    if (-not (Test-LotusTty)) { return $null }
    Write-LotusRaw "  $(E '1')$(E accent)$Label ›$($script:R) "
    try { [Console]::ReadLine() } catch { $null }
}

function script:Invoke-LotusAiChat {
    $p = Use-LotusAiProvider
    if (-not $p) { return (St 1) }
    if (-not ((Test-LotusTty) -and (Test-LotusOutTty))) { Write-LotusError 'The chat needs a terminal' '' @('Ask single questions: /ai <question>'); return (St 1) }
    $turns = [System.Collections.Generic.List[object]]::new()
    foreach ($t in @(Get-LotusAiConversation)) { $turns.Add($t) }
    Write-LotusHeader 'AI' "$($p.Label) · /new forgets · an empty line ends the chat"
    Write-LotusDim 'On Windows the AI answers and remembers this conversation for an hour – it cannot read or change files or run commands.'
    if ($turns.Count) { Write-LotusDim "It still knows the last $([Math]::Truncate($turns.Count / 2)) question(s) of this conversation." }
    Write-LotusLog INFO ai "AI chat with $($p.Name)"
    while ($true) {
        Write-LotusBlank
        $said = Read-LotusAiLine (T pt_you 'You')
        if ($null -eq $said -or -not $said.Trim()) { break }
        $said = $said.Trim()
        if ($said -cin '/exit', '/quit', 'exit', 'quit') { break }
        if ($said -cin '/new', '/clear') { $turns.Clear(); Clear-LotusAiConversation; Write-LotusSuccess 'New conversation – the AI forgot the last one'; continue }
        $turns.Add(@{ role = 'user'; text = $said })
        Write-LotusBlank
        $answer = Invoke-LotusAiAnswer -Messages $turns.ToArray() -Provider $p
        if ($null -eq $answer) { $turns.RemoveAt($turns.Count - 1); continue }
        $turns.Add(@{ role = 'assistant'; text = $answer })
        Save-LotusAiConversation $turns.ToArray()
    }
    Write-LotusBlank
    St 0
}

# /ai <question>: one answer, with the conversation of the last hour
function script:Invoke-LotusAiOnce {
    param([string]$Question)
    if (-not $Question.Trim()) { return Invoke-LotusAiChat }
    $p = Use-LotusAiProvider
    if (-not $p) { return (St 1) }
    $turns = @(Get-LotusAiConversation) + @(@{ role = 'user'; text = $Question.Trim() })
    if (Test-LotusOutTty) { Write-LotusBlank }
    $answer = Invoke-LotusAiAnswer -Messages $turns -Provider $p
    if ($null -eq $answer) { return (St 1) }
    Save-LotusAiConversation (@($turns) + @(@{ role = 'assistant'; text = $answer }))
    if (Test-LotusOutTty) { Write-LotusBlank } else { $answer }
    St 0
}

function script:Reset-LotusAiChat {
    param([string]$Question)
    Clear-LotusAiConversation
    Write-LotusSuccess 'New conversation – the AI forgot the last one'
    if ($Question.Trim()) { return Invoke-LotusAiOnce $Question }
    St 0
}

# One answer without memory: <instructions> <prompt> (/ai explain, /ai write)
function script:Invoke-LotusAiTask {
    param([string]$Instructions, [string]$Prompt)
    if (-not $Prompt.Trim() -or $Prompt -match '^(Explain|Write):\s*$') { Write-LotusError 'What should the AI do?' '' @('Example: /ai explain Get-ChildItem -Recurse'); return (St 1) }
    $p = Use-LotusAiProvider
    if (-not $p) { return (St 1) }
    if (Test-LotusOutTty) { Write-LotusBlank }
    $answer = Invoke-LotusAiAnswer -System $Instructions -Messages @(@{ role = 'user'; text = $Prompt }) -Provider $p
    if ($null -eq $answer) { return (St 1) }
    if (Test-LotusOutTty) { Write-LotusBlank } else { $answer }
    St 0
}

# /ai summarize [file]: a text file, or what is on the clipboard
function script:Invoke-LotusAiSummarize {
    param([string]$File)
    if ($File) {
        $path = ConvertTo-LotusCleanPath $File
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-LotusError 'File not found' $File; return (St 1) }
        $head = [byte[]]::new(8192)
        $fs = [System.IO.File]::OpenRead($path)
        try { $n = $fs.Read($head, 0, $head.Length) } finally { $fs.Dispose() }
        if ([Array]::IndexOf($head, [byte]0, 0, $n) -ge 0) { Write-LotusError 'Not a text file' $File @('Summaries work with text files, e.g. .txt or .md'); return (St 1) }
        $text = [string](Read-LotusFile $path)
        $src = Split-Path -Leaf $path
    } else {
        $clip = Get-LotusClipboardText
        $text = if ($clip.Code -eq 0) { [string]$clip.Value } else { '' }
        $src = 'clipboard'
    }
    if (-not $text.Trim()) { Write-LotusError 'Nothing to summarize' "The $src is empty." @('Usage: /ai summarize <file>   or copy text first'); return (St 1) }
    $p = Use-LotusAiProvider
    if (-not $p) { return (St 1) }
    if ($text.Length -gt 60000) { $text = $text.Substring(0, 60000); Write-LotusDim 'Long text: the first 60,000 characters are used.' }
    if (Test-LotusOutTty) { Write-LotusHeader 'AI' "summary of $src" }
    $answer = Invoke-LotusAiAnswer -System "Summarize the text: first one sentence with the gist, then the key points as short '-' bullets. Plain text." -Messages @(@{ role = 'user'; text = $text }) -Provider $p
    if ($null -eq $answer) { return (St 1) }
    if (Test-LotusOutTty) { Write-LotusBlank } else { $answer }
    St 0
}

# /ai command <task>: one PowerShell command, suggested – Lotus never runs it, you decide
function script:Invoke-LotusAiCommand {
    param([string]$Task)
    if (-not $Task.Trim()) { Write-LotusError 'What should the command do?' '' @('Example: /ai command find files larger than 1 GB'); return (St 1) }
    $p = Use-LotusAiProvider
    if (-not $p) { return (St 1) }
    Write-LotusHeader 'AI' "command for: $Task"
    $answer = Invoke-LotusAiAnswer -System 'You are a Windows PowerShell expert. Answer with a single command line for PowerShell 7 on Windows, nothing else.' -Messages @(@{ role = 'user'; text = $Task }) -Provider $p -Spinner
    if ($null -eq $answer) { return (St 1) }
    $lines = @(($answer -replace '`', '') -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^(powershell|pwsh|ps1?|shell|cmd)$' })
    $cmd = if ($lines.Count) { $lines[0] } else { '' }
    if (-not $cmd) { Write-LotusError 'The AI did not suggest a command' '' @('Try describing the task with other words.'); return (St 1) }
    Write-LotusCard 'Suggestion' @("COMMAND|$cmd")
    Write-LotusBlank
    Write-LotusWarn 'Lotus never runs it. Check it before you press Enter.'
    if (-not (Test-LotusTty)) { if (-not (Test-LotusOutTty)) { $cmd }; return (St 0) }
    $pick = Read-LotusChoice '' @('Put it on the command line', 'Copy to clipboard', 'Cancel')
    if ($pick -eq 1) {
        Write-LotusFile (Join-Path $script:Paths.Cache 'ai-prompt') "$cmd`n"
        Write-LotusSuccess 'Ready on your command line'
    } elseif ($pick -eq 2) {
        if ((Set-LotusClipboardText $cmd).Code -eq 0) { Write-LotusSuccess 'Copied' }
        else { Write-LotusWarn 'There is no clipboard here – the command stays on the screen'; Write-LotusText $cmd }
    }
    St 0
}

function script:Show-LotusAiNotHere {
    param([string]$What)
    $name = switch -Regex ($What) { '^(server|web)$' { 'The web chat (lotus ai server)' } '^local$' { 'A model on this computer (lotus ai local)' } default { 'The statistics of the AI (lotus ai stats)' } }
    Write-LotusError "$name is not on Windows yet" 'It belongs to the AI program, which Lotus builds with Swift – there is no Windows build of it yet.' @(
        'Here /ai answers and chats: /ai <question>', "What works where: $($script:WebsiteStatus)")
    St 2
}

# ── Status and keys ───────────────────────────────────────────

function script:Show-LotusAiStatus {
    $ok = "$(E '1')$(E key)✓$($script:R)"; $no = "$(E dim)·$($script:R)"
    $effort = @{ low = 'quick'; medium = 'balanced'; high = 'thorough'; max = 'maximum'; ultra = 'ultra' }[[string]$(if ($script:S['LOTUS_AI_EFFORT']) { $script:S['LOTUS_AI_EFFORT'] } else { 'high' })]
    Write-LotusHeader 'AI' "provider: $(if ($script:S['LOTUS_AI_PROVIDER']) { $script:S['LOTUS_AI_PROVIDER'] } else { 'auto' }) · thinks $(if ($effort) { $effort } else { 'thorough' })"
    $cm = if ([string]$script:S['LOTUS_AI_MODEL'] -like 'claude-*') { " · $($script:S['LOTUS_AI_MODEL'])" } else { '' }
    if (Get-LotusAiClaudeKey) { Write-LotusLine "  $ok Claude              key saved$cm" } else { Write-LotusLine "  $no Claude              connect: lotus ai login" }
    $models = @(Get-LotusAiOllamaModels)
    if ($models.Count) { Write-LotusLine "  $ok Ollama              $($models.Count) model(s), e.g. $($models[0])" }
    elseif (Find-LotusProgram @('ollama')) { Write-LotusLine "  $no Ollama              installed, but not running – open the Ollama app" }
    else { Write-LotusLine "  $no Ollama              not installed: winget install Ollama.Ollama" }
    if ($script:S['LOTUS_AI_URL'] -and (Get-LotusAiOpenAiKey)) { Write-LotusLine "  $ok OpenAI-compatible   $($script:S['LOTUS_AI_URL'])" }
    else { Write-LotusLine "  $no OpenAI-compatible   set a URL in /settings and a key with: lotus ai key openai" }
    Write-LotusLine "  $no Apple Intelligence  on a Mac only"
    Write-LotusBlank
    if (@(Get-LotusAiConversation).Count) { Write-LotusDim 'Memory: the current conversation is kept for an hour after the last message (/ai new forgets it).' }
    else { Write-LotusDim 'Memory: no conversation right now.' }
    Write-LotusDim 'On Windows /ai answers and chats; the AI terminal with its tools, the web chat and models on this PC are not here yet.'
    Write-LotusBlank
    St 0
}

# A key typed without showing it (the tests give it with $script:SecretHook)
function script:Read-LotusAiSecret {
    param([string]$Label)
    if ($script:SecretHook) { return [string](& $script:SecretHook $Label) }
    Write-LotusRaw "  $Label $(E dim)(hidden, Enter when done)$($script:R): "
    try {
        $secure = $Host.UI.ReadLineAsSecureString()
        if ($null -eq $secure) { return $null }
        [System.Net.NetworkCredential]::new('', $secure).Password
    } catch { $null }
}

# Opens the key page, takes the pasted key (hidden), checks it with Claude and keeps it with DPAPI → $true when connected.
# The key never appears on screen, in a file of Lotus or on a command line.
function script:Invoke-LotusAiLogin {
    Write-LotusHeader 'AI' 'connect Claude'
    if (-not (Test-LotusTty)) { Write-LotusError 'This needs a terminal window' '' @('Run: lotus ai login'); return $false }
    $store = Get-LotusSecretStoreName
    Write-LotusText '1  Sign in at console.anthropic.com and click "Create Key" (any name, e.g. Lotus).'
    Write-LotusText "2  Copy the key and paste it here. Lotus checks it and keeps it in $store."
    Write-LotusDim '   Claude is paid per use by Anthropic – a typical question costs well under one cent.'
    Write-LotusBlank
    $page = 'https://console.anthropic.com/settings/keys'
    if (Read-LotusConfirm 'Open the key page in your browser now?' 'y') { if ((Open-LotusTarget $page).Code -ne 0) { Write-LotusDim "  $page" } }
    Write-LotusBlank
    $key = ''
    $ok = $false
    for ($try = 0; $try -lt 3; $try++) {
        $typed = Read-LotusAiSecret 'Paste your key'
        $key = ([string]$typed) -replace '\s', ''
        Write-LotusLine ''
        if (-not $key) { Write-LotusInfo 'Cancelled'; return $false }
        Write-LotusLine "  $(E dim)••••••••••••$($key.Substring([Math]::Max(0, $key.Length - 4)))$($script:R)"
        if ($key -cnotmatch '^sk-ant-[A-Za-z0-9_-]+$') { Write-LotusWarn 'That is not a Claude API key – they start with sk-ant-. Try again or press Enter to stop.'; continue }
        Write-LotusStep 'Checking the key with Claude …'
        $code = Test-LotusAiClaudeKey $key
        if ($code -eq 200) { $ok = $true; break }
        if ($code -eq 401 -or $code -eq 403) { Write-LotusWarn 'Claude did not accept this key. Copy it again (all of it) or create a new one.'; continue }
        if ($code -eq 0) { Write-LotusWarn 'Claude could not be reached right now – the key is saved anyway.' }
        else { Write-LotusWarn "Claude answered with $code – the key is saved anyway." }
        $ok = $true
        break
    }
    if (-not $ok) { return $false }
    if ((Set-LotusSecret 'lotus-ai-claude' $key) -ne 0 -or (Get-LotusSecret 'lotus-ai-claude') -cne $key) {
        Write-LotusError "The key could not be saved in $store" '' @("Try again, or set ANTHROPIC_API_KEY in your PowerShell profile.")
        return $false
    }
    $want = [string]$script:S['LOTUS_AI_PROVIDER']
    if ($want -and $want -cnotin 'auto', 'claude') {
        $script:S['LOTUS_AI_PROVIDER'] = 'claude'
        if ([string]$script:S['LOTUS_AI_MODEL'] -notlike 'claude-*') { $script:S['LOTUS_AI_MODEL'] = '' }
        Save-LotusSettings
    }
    Write-LotusLog INFO ai "Claude connected (key in $store)"
    Write-LotusSuccess 'Claude is connected'
    Write-LotusDim 'Type /ai to chat, or /ai <question> for one answer.'
    Write-LotusBlank
    $true
}

# The status of a key at the Claude API (GET …/v1/models) → 200, 401, … or 0 when Claude could not be reached
function script:Test-LotusAiClaudeKey {
    param([string]$Key)
    $url = (Get-LotusAiClaudeUrl) -replace '/messages/?$', '/models'
    try {
        $r = Invoke-WebRequest -Uri $url -Headers @{ 'x-api-key' = $Key; 'anthropic-version' = '2023-06-01' } -TimeoutSec 20 -SkipHttpErrorCheck -NoProxy:(Test-LotusAiLoopback $url) -ErrorAction Stop
        [int]$r.StatusCode
    } catch { 0 }
}

function script:Invoke-LotusAiLogout {
    if (-not (Get-LotusSecret 'lotus-ai-claude')) { Write-LotusInfo 'No Claude key is saved.'; return (St 0) }
    if (-not (Read-LotusConfirm "Remove the Claude key from $(Get-LotusSecretStoreName)?" 'n')) { return (St 0) }
    if ((Remove-LotusSecret 'lotus-ai-claude') -eq 0) { Write-LotusSuccess 'Claude is disconnected' }
    if ([string]$script:S['LOTUS_AI_PROVIDER'] -ceq 'claude') { $script:S['LOTUS_AI_PROVIDER'] = 'auto'; Save-LotusSettings }
    St 0
}

# lotus ai key [claude|openai|remove]
function script:Invoke-LotusAiKey {
    param([string]$Which)
    if (-not $Which) {
        Write-LotusHeader 'AI' 'API keys'
        $pick = Read-LotusChoice 'Which key?' @('Claude (Anthropic)', 'OpenAI-compatible API', 'Remove a saved key')
        if ($null -eq $pick) { return (St 0) }
        $Which = @('claude', 'openai', 'remove')[$pick - 1]
    }
    switch -CaseSensitive ($Which) {
        { $_ -cin 'claude', 'anthropic' } { return $(if (Invoke-LotusAiLogin) { St 0 } else { St 1 }) }
        'openai' {
            Write-LotusHeader 'AI' 'API key'
            if (-not (Test-LotusTty)) { Write-LotusError 'This needs a terminal window' '' @('Run: lotus ai key openai'); return (St 1) }
            Write-LotusText "Paste the key – Lotus keeps it in $(Get-LotusSecretStoreName) (item: lotus-ai)."
            $key = ([string](Read-LotusAiSecret 'Paste the key')) -replace '\s', ''
            Write-LotusLine ''
            if (-not $key) { Write-LotusInfo (T cancelled 'Cancelled.'); return (St 0) }
            if ((Set-LotusSecret 'lotus-ai' $key) -eq 0) { Write-LotusSuccess "Saved in $(Get-LotusSecretStoreName)"; return (St 0) }
            Write-LotusError 'The key could not be saved' '' @('Set LOTUS_AI_KEY in your PowerShell profile instead.')
            return (St 1)
        }
        'remove' {
            $pick = Read-LotusChoice 'Remove which key?' @('Claude', 'OpenAI-compatible API')
            if ($null -eq $pick) { return (St 0) }
            $item = if ($pick -eq 2) { 'lotus-ai' } else { 'lotus-ai-claude' }
            if (-not (Read-LotusConfirm "Remove the key `"$item`" from $(Get-LotusSecretStoreName)?" 'n')) { return (St 0) }
            if ((Remove-LotusSecret $item) -eq 0) { Write-LotusSuccess 'Removed' } else { Write-LotusWarn 'There was no saved key.' }
            return (St 0)
        }
    }
    Write-LotusError 'Unknown key type' $Which @('Use: lotus ai login   or   lotus ai key openai')
    St 1
}
