# Shared by the test files: each one runs in folders of its own (nothing of yours is read or changed), never waits for a
# keyboard (LOTUS_NO_TTY), and puts the environment back when it is done. Keys for the screens come from a queue.

$script:LotusTestVars = 'LOTUS_ROOT', 'LOTUS_CONF', 'LOTUS_CACHE', 'LOTUS_STATE', 'LOTUS_DATA', 'LOTUS_PROFILE', 'LOTUS_NO_TTY',
'LOTUS_SRC', 'LOTUS_DEST', 'LOTUS_NO_PROFILE', 'LOTUS_SHELL_TEST', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'COLUMNS', 'LINES',
'ANTHROPIC_API_KEY', 'LOTUS_AI_KEY', 'LOTUS_AI_CLAUDE_URL', 'OLLAMA_HOST', 'LOTUS_DOWNLOADS', 'PATH'

function Initialize-LotusTestEnv {
    param([string]$Name = 'lotus-test')
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("$Name-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $saved = @{}
    foreach ($n in $script:LotusTestVars) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    # (PATH is kept as it is – a test that puts a program in front of it gets it back afterwards)
    foreach ($n in $script:LotusTestVars) { if ($n -cne 'PATH') { [Environment]::SetEnvironmentVariable($n, $null) } }
    $env:LOTUS_ROOT = $repo
    $env:LOTUS_CONF = Join-Path $tmp 'conf'
    $env:LOTUS_CACHE = Join-Path $tmp 'cache'
    $env:LOTUS_STATE = Join-Path $tmp 'state'
    $env:LOTUS_DATA = Join-Path $tmp 'data'
    $env:LOTUS_PROFILE = Join-Path $tmp 'profile.ps1'
    $env:LOTUS_NO_TTY = '1'
    $env:COLUMNS = '140'
    # Windows PowerShell 5.1 reads and writes text as ANSI unless it is told otherwise (PowerShell 7: UTF-8); Lotus' files are UTF-8
    if ($PSVersionTable.PSEdition -ne 'Core') {
        foreach ($c in 'Get-Content', 'Set-Content', 'Add-Content', 'Out-File') { $global:PSDefaultParameterValues["${c}:Encoding"] = 'UTF8' }
        # The tests collect what Lotus shows with  6>&1 | Out-String  and read it as the plain text a person sees. PowerShell 7 does
        # that by itself: it leaves the color codes out and does not wrap a line at the width of the window. Windows PowerShell
        # 5.1 does neither – so its Out-String is stood in for here (the real one does the work).
        function global:Out-String {
            [CmdletBinding()]
            param([switch]$Stream, [int]$Width = 4096, [Parameter(ValueFromPipeline = $true)][AllowNull()][psobject]$InputObject)
            begin { $items = [System.Collections.Generic.List[object]]::new() }
            process { $items.Add($InputObject) }
            end {
                $codes = '\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)'
                $text = @($items.ToArray() | Microsoft.PowerShell.Utility\Out-String -Width $Width -Stream:$Stream)
                if ($Stream) { foreach ($t in $text) { [regex]::Replace($t, $codes, '') } } else { [regex]::Replace(($text -join ''), $codes, '') }
            }
        }
    }
    [pscustomobject]@{ Repo = $repo; Tmp = $tmp; Saved = $saved }
}

function Restore-LotusTestEnv {
    param($Context)
    if (-not $Context) { return }
    foreach ($n in $Context.Saved.Keys) { [Environment]::SetEnvironmentVariable($n, $Context.Saved[$n]) }
    foreach ($c in 'Get-Content', 'Set-Content', 'Add-Content', 'Out-File') { $global:PSDefaultParameterValues.Remove("${c}:Encoding") }
    Remove-Item -LiteralPath function:global:Out-String -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Context.Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# Runs a script block in the module with these keys as the keyboard (names as Read-LotusKeyX gives them: up, enter,
# esc, a, …); what the screens write comes back as text
function Invoke-LotusWithKeys {
    param([string[]]$Keys, [scriptblock]$ScriptBlock)
    InModuleScope Lotus -Parameters @{ Keys = $Keys; Body = $ScriptBlock.ToString() } {
        $script:KeyQueue.Clear()
        foreach ($k in $Keys) { $script:KeyQueue.Enqueue($k) }
        $script:KeyQueueActive = $true
        # made again here, so that it runs inside the module and sees its functions
        try { & ([scriptblock]::Create($Body)) *>&1 | Out-String } finally { $script:KeyQueueActive = $false; $script:KeyQueue.Clear() }
    }
}

# ── A small AI for the tests ──────────────────────────────────
# On 127.0.0.1, a port of its own: Claude's /v1/messages and /v1/models, OpenAI's /chat/completions, Ollama's /api/tags
# and /api/chat – streamed the way the real ones stream. It answers "Answer to: <the last message>"; a message with
# "pick two" gets "2, 1" and a sentence (the numbers /help asks for), instructions that ask for a single command line
# get one in a code block. The key "sk-ant-bad" is refused (401), the model "claude-missing" is not there (404).
# Every request goes into .Log, one JSON per line: method, path, the key headers and the body.
$script:FakeAiServer = {
    param($Listener, $Log)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    function Send-Reply($Stream, [int]$Code, [string]$Type, [string]$Body, [bool]$Length) {
        $reason = @{ 200 = 'OK'; 401 = 'Unauthorized'; 404 = 'Not Found' }[$Code]
        $bytes = $utf8.GetBytes($Body)
        $head = "HTTP/1.1 $Code $reason`r`nContent-Type: $Type`r`nConnection: close`r`n$(if ($Length) { "Content-Length: $($bytes.Length)`r`n" })`r`n"
        $h = [System.Text.Encoding]::ASCII.GetBytes($head)
        $Stream.Write($h, 0, $h.Length); $Stream.Write($bytes, 0, $bytes.Length); $Stream.Flush()
    }
    while ($true) {
        try { $client = $Listener.AcceptTcpClient() } catch { break }
        try {
            $stream = $client.GetStream()
            $buf = [System.Collections.Generic.List[byte]]::new()
            $one = [byte[]]::new(1)
            while ($stream.Read($one, 0, 1) -eq 1) {
                $buf.Add($one[0]); $c = $buf.Count
                if ($c -ge 4 -and $buf[$c - 4] -eq 13 -and $buf[$c - 3] -eq 10 -and $buf[$c - 2] -eq 13 -and $buf[$c - 1] -eq 10) { break }
            }
            $lines = [System.Text.Encoding]::ASCII.GetString($buf.ToArray()) -split "`r`n"
            $method, $path = ($lines[0] -split ' ')[0, 1]
            $headers = @{}
            foreach ($l in $lines | Select-Object -Skip 1) { $i = $l.IndexOf(':'); if ($i -gt 0) { $headers[$l.Substring(0, $i).Trim().ToLower()] = $l.Substring($i + 1).Trim() } }
            $len = [int]$headers['content-length']
            $raw = [byte[]]::new($len); $got = 0
            while ($got -lt $len) { $n = $stream.Read($raw, $got, $len - $got); if ($n -le 0) { break }; $got += $n }
            $text = $utf8.GetString($raw, 0, $got)
            [System.IO.File]::AppendAllText($Log, (@{ method = $method; path = $path; key = $headers['x-api-key']; auth = $headers['authorization']; body = $text } | ConvertTo-Json -Compress -Depth 3) + "`n")
            if ($method -eq 'GET' -and $path -like '*/api/tags') { Send-Reply $stream 200 'application/json' '{"models":[{"name":"llama3:8b"},{"name":"qwen3:4b"}]}' $true; continue }
            if ($method -eq 'GET' -and $path -like '*/v1/models') {
                if ($headers['x-api-key'] -eq 'sk-ant-good-key') { Send-Reply $stream 200 'application/json' '{"data":[]}' $true }
                else { Send-Reply $stream 401 'application/json' '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}' $true }
                continue
            }
            $req = $text | ConvertFrom-Json
            if ($headers['x-api-key'] -eq 'sk-ant-bad') { Send-Reply $stream 401 'application/json' '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}' $true; continue }
            if ($req.model -eq 'claude-missing') { Send-Reply $stream 404 'application/json' '{"type":"error","error":{"type":"not_found_error","message":"model: claude-missing"}}' $true; continue }
            $last = @($req.messages)[-1]
            $said = if ($last.content -is [string]) { $last.content } else { (@($last.content) | ForEach-Object { $_.text }) -join ' ' }
            $sys = if ($req.system) { (@($req.system) | ForEach-Object { $_.text }) -join ' ' } else { [string](@($req.messages)[0].content) }
            $answer = if ($said -match 'pick two') { "2, 1`nThese two help." }
            elseif ($sys -match 'single command line') { "``````powershell`nGet-ChildItem -Recurse | Where-Object Length -gt 1GB`n``````" }
            else { "Answer to: $($said.Substring(0, [Math]::Min(80, $said.Length)))" }
            $parts = [regex]::Matches($answer, '\S+\s*|\s+') | ForEach-Object Value
            $sb = [System.Text.StringBuilder]::new()
            if ($path -like '*/v1/messages') {
                $ev = { param($type, $data) [void]$sb.Append("event: $type`ndata: $($data | ConvertTo-Json -Compress -Depth 6)`n`n") }
                & $ev 'message_start' @{ type = 'message_start'; message = @{ id = 'msg_test'; role = 'assistant'; content = @(); usage = @{ input_tokens = 10; output_tokens = 1 } } }
                & $ev 'content_block_start' @{ type = 'content_block_start'; index = 0; content_block = @{ type = 'thinking'; thinking = '' } }
                & $ev 'content_block_delta' @{ type = 'content_block_delta'; index = 0; delta = @{ type = 'thinking_delta'; thinking = 'Thinking it over.' } }
                & $ev 'content_block_stop' @{ type = 'content_block_stop'; index = 0 }
                & $ev 'content_block_start' @{ type = 'content_block_start'; index = 1; content_block = @{ type = 'text'; text = '' } }
                foreach ($t in $parts) { & $ev 'content_block_delta' @{ type = 'content_block_delta'; index = 1; delta = @{ type = 'text_delta'; text = $t } } }
                & $ev 'content_block_stop' @{ type = 'content_block_stop'; index = 1 }
                & $ev 'message_delta' @{ type = 'message_delta'; delta = @{ stop_reason = 'end_turn' }; usage = @{ output_tokens = 5 } }
                & $ev 'message_stop' @{ type = 'message_stop' }
                Send-Reply $stream 200 'text/event-stream' $sb.ToString() $false
            } elseif ($path -like '*/chat/completions') {
                foreach ($t in $parts) { [void]$sb.Append("data: $(@{ choices = @(@{ index = 0; delta = @{ content = $t } }) } | ConvertTo-Json -Compress -Depth 6)`n`n") }
                [void]$sb.Append("data: $(@{ choices = @(@{ index = 0; delta = @{}; finish_reason = 'stop' }) } | ConvertTo-Json -Compress -Depth 6)`n`ndata: [DONE]`n`n")
                Send-Reply $stream 200 'text/event-stream' $sb.ToString() $false
            } elseif ($path -like '*/api/chat') {
                foreach ($t in $parts) { [void]$sb.Append("$(@{ model = $req.model; message = @{ role = 'assistant'; content = $t }; done = $false } | ConvertTo-Json -Compress -Depth 6)`n") }
                [void]$sb.Append("$(@{ model = $req.model; message = @{ role = 'assistant'; content = '' }; done = $true; done_reason = 'stop' } | ConvertTo-Json -Compress -Depth 6)`n")
                Send-Reply $stream 200 'application/x-ndjson' $sb.ToString() $false
            } else { Send-Reply $stream 404 'text/plain' 'not here' $true }
        } catch {
            [System.IO.File]::AppendAllText($Log, (@{ error = "$_" } | ConvertTo-Json -Compress) + "`n")
        } finally { $client.Dispose() }
    }
}

function Start-LotusFakeAi {
    param([int]$OnPort = 0)                           # (a port of its own, or one such as Ollama's 11434)
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $OnPort)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $log = Join-Path ([System.IO.Path]::GetTempPath()) "lotus-fake-ai-$port.log"
    [System.IO.File]::WriteAllText($log, '')
    $ps = [powershell]::Create()
    [void]$ps.AddScript($script:FakeAiServer.ToString()).AddArgument($listener).AddArgument($log)
    [pscustomobject]@{ Url = "http://127.0.0.1:$port"; Log = $log; Listener = $listener; PS = $ps; Handle = $ps.BeginInvoke() }
}

# The requests the fake AI got (objects: method, path, key, auth, body as an object)
function Get-LotusFakeAiRequests {
    param($Fake)
    foreach ($l in [System.IO.File]::ReadAllLines($Fake.Log)) {
        if (-not $l) { continue }
        $r = $l | ConvertFrom-Json
        if ($r.body) { $r.body = $r.body | ConvertFrom-Json }
        $r
    }
}

function Stop-LotusFakeAi {
    param($Fake)
    if (-not $Fake) { return }
    try { $Fake.Listener.Stop() } catch { }
    try { $Fake.PS.Stop(); $Fake.PS.Dispose() } catch { }
    Remove-Item -LiteralPath $Fake.Log -Force -ErrorAction SilentlyContinue
}
