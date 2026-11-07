# /ai on Windows (Public/ai.ps1) against a small fake AI on 127.0.0.1 (TestKit.ps1: Start-LotusFakeAi) – Claude's,
# OpenAI's and Ollama's streams, the conversation of the last hour, the commands, the keys, and a pet that thinks with it.
# No real key is used: the test kit empties ANTHROPIC_API_KEY, LOTUS_AI_KEY, LOTUS_AI_CLAUDE_URL and OLLAMA_HOST.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestKit.ps1')
    $script:Ctx = Initialize-LotusTestEnv 'lotus-ai'
    $script:Fake = Start-LotusFakeAi
    Import-Module (Join-Path $PSScriptRoot '../Lotus.psd1') -Force
    lotus settings set LOTUS_CONFIGURED 1 | Out-Null
    lotus settings set LOTUS_NAME Ada | Out-Null
    InModuleScope Lotus { Initialize-Lotus; Import-LotusCommand ai }
    function Get-Plain { param([string]$Text) $Text -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '' }
    function Use-Claude { param([string]$Key = 'sk-ant-test') $env:ANTHROPIC_API_KEY = $Key; $env:LOTUS_AI_CLAUDE_URL = "$($script:Fake.Url)/v1/messages" }
    function Get-LastRequest { @(Get-LotusFakeAiRequests $script:Fake | Where-Object { $_.method -eq 'POST' })[-1] }
}

AfterAll {
    Remove-Module Lotus -Force -ErrorAction SilentlyContinue
    Stop-LotusFakeAi $script:Fake
    Restore-LotusTestEnv $script:Ctx
}

Describe 'which AI answers' {
    AfterEach {
        Remove-Item env:ANTHROPIC_API_KEY, env:LOTUS_AI_CLAUDE_URL, env:OLLAMA_HOST, env:LOTUS_AI_KEY -ErrorAction SilentlyContinue
        lotus settings set LOTUS_AI_PROVIDER auto | Out-Null
        lotus settings set LOTUS_AI_MODEL '' | Out-Null
    }
    It 'none: it says what can be done' {
        $out = lotus ai 'hello' 6>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'No AI is available yet'
        $out | Should -Match 'lotus ai login'
        $out | Should -Match 'winget install Ollama.Ollama'
    }
    It 'Claude first, with its model and a label' {
        Use-Claude
        $env:OLLAMA_HOST = $script:Fake.Url
        $p = InModuleScope Lotus { Initialize-Lotus; Get-LotusAiProvider }
        $p.Name | Should -Be 'claude'
        $p.Model | Should -Be 'claude-opus-5-5'
        $p.Label | Should -Be 'Claude Opus 5.5'
        lotus settings set LOTUS_AI_MODEL claude-sonnet-5-5 | Out-Null
        (InModuleScope Lotus { Initialize-Lotus; Get-LotusAiProvider }).Label | Should -Be 'Claude Sonnet 5.5'
    }
    It 'Ollama when it runs, with the model of the settings when Ollama has it' {
        $env:OLLAMA_HOST = $script:Fake.Url.Substring(7)
        $p = InModuleScope Lotus { Initialize-Lotus; Get-LotusAiProvider }
        $p.Name | Should -Be 'ollama'
        $p.Model | Should -Be 'llama3:8b'
        lotus settings set LOTUS_AI_MODEL 'qwen3:4b' | Out-Null
        (InModuleScope Lotus { Initialize-Lotus; Get-LotusAiProvider }).Model | Should -Be 'qwen3:4b'
    }
    It 'the provider of the settings only' {
        Use-Claude
        lotus settings set LOTUS_AI_PROVIDER openai | Out-Null
        InModuleScope Lotus { Initialize-Lotus; Get-LotusAiProvider } | Should -BeNullOrEmpty
        lotus settings set LOTUS_AI_URL $script:Fake.Url | Out-Null
        $env:LOTUS_AI_KEY = 'sk-test-openai'
        (InModuleScope Lotus { Initialize-Lotus; Get-LotusAiProvider }).Name | Should -Be 'openai'
        lotus settings set LOTUS_AI_URL '' | Out-Null
    }
}

Describe 'answers' {
    BeforeEach { Use-Claude; InModuleScope Lotus { Clear-LotusAiConversation } }
    AfterEach {
        Remove-Item env:ANTHROPIC_API_KEY, env:LOTUS_AI_CLAUDE_URL, env:OLLAMA_HOST, env:LOTUS_AI_KEY -ErrorAction SilentlyContinue
        lotus settings set LOTUS_AI_PROVIDER auto | Out-Null
    }
    It 'come from Claude, streamed, with the instructions of Lotus for Windows' {
        lotus ai 'hello there' | Should -Be 'Answer to: hello there'
        $LASTEXITCODE | Should -Be 0
        $r = Get-LastRequest
        $r.path | Should -Be '/v1/messages'
        $r.key | Should -Be 'sk-ant-test'
        $r.body.stream | Should -BeTrue
        $r.body.model | Should -Be 'claude-opus-5-5'
        $r.body.thinking.type | Should -Be 'adaptive'
        $r.body.output_config.effort | Should -Be 'high'
        $r.body.system[0].text | Should -Match "inside the user's PowerShell window on Windows"
        $r.body.system[0].text | Should -Match "The user's name is Ada"
        $r.body.system[0].text | Should -Match 'How to answer:'
        $r.body.system[0].text | Should -Not -Match '\{\{'
    }
    It 'remember the conversation of the last hour – /ai new forgets it' {
        lotus ai 'first question' | Out-Null
        lotus ai 'second question' | Should -Be 'Answer to: second question'
        $m = @((Get-LastRequest).body.messages)
        $m.Count | Should -Be 3
        $m[1].role | Should -Be 'assistant'
        $m[1].content[0].text | Should -Be 'Answer to: first question'
        lotus ai new 6>&1 | Out-String | Should -Match 'forgot'
        lotus ai 'third' | Out-Null
        @((Get-LastRequest).body.messages).Count | Should -Be 1
        # an hour later it is gone
        $f = Join-Path $env:LOTUS_CACHE 'ai/conversation.json'
        $c = Get-Content $f -Raw | ConvertFrom-Json
        $c.updated = [double]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 3700)
        $c | ConvertTo-Json -Depth 5 | Set-Content $f
        lotus ai 'fourth' | Out-Null
        @((Get-LastRequest).body.messages).Count | Should -Be 1
    }
    It 'from an OpenAI-compatible API, with the key as a bearer token' {
        Remove-Item env:ANTHROPIC_API_KEY
        lotus settings set LOTUS_AI_PROVIDER openai | Out-Null
        lotus settings set LOTUS_AI_URL "$($script:Fake.Url)/v1" | Out-Null
        $env:LOTUS_AI_KEY = 'sk-test-openai'
        try {
            lotus ai 'hi openai' | Should -Be 'Answer to: hi openai'
            $r = Get-LastRequest
            $r.path | Should -Be '/v1/chat/completions'
            $r.auth | Should -Be 'Bearer sk-test-openai'
            $r.body.messages[0].role | Should -Be 'system'
            $r.body.model | Should -Be 'gpt-4o-mini'
        } finally { lotus settings set LOTUS_AI_URL '' | Out-Null }
    }
    It 'from Ollama' {
        Remove-Item env:ANTHROPIC_API_KEY
        $env:OLLAMA_HOST = $script:Fake.Url
        lotus ai 'hi ollama' | Should -Be 'Answer to: hi ollama'
        (Get-LastRequest).path | Should -Be '/api/chat'
        (Get-LastRequest).body.model | Should -Be 'llama3:8b'
    }
    It 'errors in the words of the AI program' {
        Use-Claude 'sk-ant-bad'
        lotus ai 'x' 6>&1 | Out-String | Should -Match 'The Claude API key was not accepted'
        $LASTEXITCODE | Should -Be 1
        Use-Claude
        lotus settings set LOTUS_AI_MODEL claude-missing | Out-Null
        try { lotus ai 'x' 6>&1 | Out-String | Should -Match 'claude-missing was not found' } finally { lotus settings set LOTUS_AI_MODEL '' | Out-Null }
        $env:LOTUS_AI_CLAUDE_URL = 'http://127.0.0.1:1/v1/messages'
        lotus ai 'x' 6>&1 | Out-String | Should -Match 'The Claude API could not be reached'
    }
    It 'explain, write and summarize get their own instructions and no memory' {
        lotus ai explain 'Get-ChildItem -Recurse' | Should -Be 'Answer to: Explain: Get-ChildItem -Recurse'
        (Get-LastRequest).body.system[0].text | Should -Match "^Explain clearly.*PowerShell on Windows.*`nAnswer in the user's language\.$"
        lotus ai write 'a short thank-you note' | Should -Match '^Answer to: Write: a short'
        $f = Join-Path $env:LOTUS_CACHE 'notes.md'
        Set-Content -LiteralPath $f -Value "# Notes`nLotus runs on Windows now."
        lotus ai summarize $f | Should -Match '^Answer to: # Notes'
        (Get-LastRequest).body.system[0].text | Should -Match '^Summarize the text'
        [IO.File]::WriteAllBytes((Join-Path $env:LOTUS_CACHE 'x.bin'), [byte[]](0, 1, 2, 3))
        lotus ai summarize (Join-Path $env:LOTUS_CACHE 'x.bin') 6>&1 | Out-String | Should -Match 'Not a text file'
        lotus ai explain 6>&1 | Out-String | Should -Match 'What should the AI do'
        Test-Path (Join-Path $env:LOTUS_CACHE 'ai/conversation.json') | Should -BeFalse
    }
    It 'a command is suggested, never run' {
        $out = lotus ai command 'find files larger than 1 GB' 6>&1 | Out-String
        $out | Should -Match 'COMMAND\s+Get-ChildItem -Recurse \| Where-Object Length -gt 1GB'
        $out | Should -Match 'Lotus never runs it'
        (Get-LastRequest).body.system[0].text | Should -Match 'single command line for PowerShell 7 on Windows'
        $put = Invoke-LotusWithKeys @('enter') { Invoke-LotusAiCommand 'find files larger than 1 GB' }
        Get-Plain $put | Should -Match 'Ready on your command line'
        Get-Content (Join-Path $env:LOTUS_CACHE 'ai-prompt') | Should -Be 'Get-ChildItem -Recurse | Where-Object Length -gt 1GB'
        Remove-Item (Join-Path $env:LOTUS_CACHE 'ai-prompt')
    }
    It 'the chat: questions until an empty line, /new forgets' {
        $out = Invoke-LotusWithKeys @() {
            $script:ChatLines = [System.Collections.Generic.Queue[string]]::new()
            foreach ($l in 'one', 'two', '/new', 'three', '') { $script:ChatLines.Enqueue($l) }
            $script:LineHook = { param($Label, $Text) $script:ChatLines.Dequeue() }
            try { Invoke-LotusAiChat } finally { $script:LineHook = $null }
        }
        # (captured, every write of the screen is a line of its own: the words are compared, not the lines)
        $plain = (Get-Plain $out) -replace '\s+', ' '
        $plain | Should -Match 'Answer to: one'
        $plain | Should -Match 'Answer to: two'
        $plain | Should -Match 'New conversation'
        $plain | Should -Match 'cannot read or change files or run commands'
        @((Get-LastRequest).body.messages).Count | Should -Be 1
    }
    It 'the Mac-only parts say so' {
        foreach ($w in 'server', 'local', 'stats') {
            lotus ai $w 6>&1 | Out-String | Should -Match 'not on Windows yet'
            $LASTEXITCODE | Should -Be 2
        }
    }
    It 'older Claude models think with a budget' {
        lotus settings set LOTUS_AI_MODEL claude-sonnet-4-5 | Out-Null
        try {
            lotus ai 'x' | Out-Null
            $b = (Get-LastRequest).body
            $b.thinking.type | Should -Be 'enabled'
            $b.thinking.budget_tokens | Should -Be 16000
            $b.max_tokens | Should -BeGreaterThan 16000
            $b.PSObject.Properties.Name | Should -Not -Contain 'output_config'
        } finally { lotus settings set LOTUS_AI_MODEL '' | Out-Null }
    }
}

Describe 'on screen' {
    It 'wraps words, shows **bold**, `code` and code blocks' {
        # exactly what is written, escapes and all (a captured Write-Host loses them)
        $out = InModuleScope Lotus {
            $env:COLUMNS = '40'
            $real = (Get-Item function:Write-LotusRaw).ScriptBlock
            $script:Written = [System.Text.StringBuilder]::new()
            Set-Item function:script:Write-LotusRaw { param($Text) [void]$script:Written.Append($Text) }
            try {
                $r = New-LotusAiRender
                foreach ($piece in '# Title', "`nSome **bold** words and ``code`` here, and a long line that has to wrap somewhere.", "`n``````powershell`nGet-Date`n``````", "`nDone.") {
                    Add-LotusAiRender $r $piece
                }
                Close-LotusAiRender $r
            } finally { $env:COLUMNS = '140'; Set-Item function:script:Write-LotusRaw $real }
            $script:Written.ToString()
        }
        $out | Should -Match "$([char]27)\[1mTitle"
        $out | Should -Match "$([char]27)\[1mbold$([char]27)\[22m"
        $plain = Get-Plain $out
        $plain | Should -Not -Match '\*\*|`'
        $plain | Should -Match '(?m)^    Get-Date$'
        $plain | Should -Not -Match 'powershell'
        foreach ($line in $plain -split "`n") { $line.Length | Should -BeLessOrEqual 38 }
        $plain | Should -Match '(?m)^  Done\.$'
    }
    It 'leaves out what a model thinks in <think>' {
        InModuleScope Lotus {
            Get-LotusAiVisibleText "<think>hmm`nlet me see</think>`nThe answer." | Should -Be 'The answer.'
            Get-LotusAiVisibleText '<think>still thinking' | Should -Be ''
        }
    }
}

Describe 'keys' {
    AfterEach { InModuleScope Lotus { $script:SecretHook = $null; Remove-LotusSecret 'lotus-ai-claude' | Out-Null; Remove-LotusSecret 'lotus-ai' | Out-Null } }
    It 'lotus ai login checks the key with Claude and keeps it' {
        $env:LOTUS_AI_CLAUDE_URL = "$($script:Fake.Url)/v1/messages"
        try {
            $out = Invoke-LotusWithKeys @('n') {
                $script:SecretTries = [System.Collections.Generic.Queue[string]]::new()
                foreach ($k in 'not-a-key', 'sk-ant-wrong', 'sk-ant-good-key') { $script:SecretTries.Enqueue($k) }
                $script:SecretHook = { param($Label) $script:SecretTries.Dequeue() }
                "connected=$(Invoke-LotusAiLogin)"
            }
            $plain = Get-Plain $out
            $plain | Should -Match 'they start with sk-ant-'
            $plain | Should -Match 'did not accept this key'
            $plain | Should -Match '••••••••••••-key'
            $plain | Should -Match 'Claude is connected'
            $plain | Should -Match 'connected=True'
            $plain | Should -Not -Match 'sk-ant-good-key'
            InModuleScope Lotus { Get-LotusSecret 'lotus-ai-claude' } | Should -Be 'sk-ant-good-key'
            $check = @(Get-LotusFakeAiRequests $script:Fake | Where-Object { $_.path -eq '/v1/models' })[-1]
            $check.key | Should -Be 'sk-ant-good-key'
        } finally { Remove-Item env:LOTUS_AI_CLAUDE_URL -ErrorAction SilentlyContinue }
    }
    It 'an empty paste cancels, and three wrong ones end it' {
        $out = Invoke-LotusWithKeys @('n') { $script:SecretHook = { param($Label) '' }; "connected=$(Invoke-LotusAiLogin)" }
        Get-Plain $out | Should -Match 'Cancelled'
        Get-Plain $out | Should -Match 'connected=False'
    }
    It 'lotus ai key openai keeps a key for the OpenAI-compatible API' {
        Get-Plain (Invoke-LotusWithKeys @() { $script:SecretHook = { param($Label) ' sk-openai-123 ' }; Invoke-LotusAiKey 'openai' }) | Should -Match 'Saved in'
        InModuleScope Lotus { Get-LotusSecret 'lotus-ai' } | Should -Be 'sk-openai-123'
    }
    It 'lotus ai status shows what is there' {
        InModuleScope Lotus { Set-LotusSecret 'lotus-ai-claude' 'sk-ant-x' | Out-Null }
        $out = Get-Plain (lotus ai status 6>&1 | Out-String)
        $out | Should -Match '✓ Claude\s+key saved'
        $out | Should -Match 'Ollama'
        $out | Should -Match 'Apple Intelligence\s+on a Mac only'
    }
}

Describe 'a pet thinks with it' {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $env:LOTUS_CONF | Out-Null
        [IO.File]::WriteAllText((Join-Path $env:LOTUS_CONF 'pets.tsv'), "Mochi`tcat`t`t$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 3600)`n")
        InModuleScope Lotus { $script:PetHour = 14 }
    }
    AfterAll { InModuleScope Lotus { $script:PetHour = $null }; Remove-Item env:ANTHROPIC_API_KEY, env:LOTUS_AI_CLAUDE_URL -ErrorAction SilentlyContinue }
    BeforeEach { Use-Claude }

    It 'answers in its bubble and remembers it' {
        $out = (Get-Plain (lotus pet mochi 'how are you' 6>&1 | Out-String)) -replace '[─-▟]', ' ' -replace '\s+', ' '
        $out | Should -Match 'Answer to: Ada: how are you'
        $r = Get-LastRequest
        $r.body.system[0].text | Should -Match '^You are Mochi, a little cat'
        $r.body.output_config.effort | Should -Be 'low'
        Get-Content (Join-Path $env:LOTUS_STATE 'pets/mochi.mem') | Should -Contain 'Mochi: Answer to: Ada: how are you'
        lotus pet mochi 'and now' | Out-Null
        (Get-LastRequest).body.messages[0].content[0].text | Should -Match "^Earlier:`nAda: how are you"
    }
    It '/help: the AI picks the commands by their numbers' {
        # (a key ends the first speech; the pick that follows the commands finds none and ends /help)
        $out = Invoke-LotusWithKeys @('space') {
            $script:LineHook = { param($Label, $Text) 'pick two please' }
            try { Initialize-LotusPets; $cmds = Get-LotusPetCommands; "first=$($cmds[0].Usage)"; Invoke-LotusPetHelp } finally { $script:LineHook = $null }
        }
        $plain = Get-Plain $out
        $first = [regex]::Match($plain, 'first=(.+)').Groups[1].Value.Trim()
        $plain | Should -Match 'These two help'
        $plain | Should -Match "2  $([regex]::Escape($first))"
        (Get-LastRequest).body.system[0].text | Should -Match 'These are the Lotus commands, numbered'
    }
}
