# /settings – the settings menu, a port of lib/settings.zsh. Rows of what Windows does not have (Apple Intelligence,
# local MLX models, the AI web chat, Remove BG, the live album cover, the "Last login" line) are left out.
#   lotus settings                the menu (in a window), else the list
#   lotus settings get NAME       one value (for scripts)      lotus settings set NAME VALUE
# Status 10 after an uninstall from the menu, so the shell can unload Lotus.

function script:Invoke-Lotussettings {
    param([string[]]$Rest)
    $sub = if ($Rest.Count) { $Rest[0] } else { '' }
    switch -CaseSensitive ($sub) {
        'get' {
            $name = if ($Rest.Count -gt 1) { $Rest[1] } else { '' }
            if ($script:S.Contains($name)) { [string]$script:S[$name]; return (St 0) }
            if ($script:SExtra.Contains($name)) { [string]$script:SExtra[$name]; return (St 0) }
            return (St 1)
        }
        'set' {
            if ($Rest.Count -lt 3) { Write-LotusLine '  lotus settings set NAME VALUE'; return (St 2) }
            try { Set-LotusSetting -Name $Rest[1] -Value ($Rest[2..($Rest.Count - 1)] -join ' ') }
            catch { Write-LotusError 'Not saved' $_.Exception.Message; return (St 2) }
            Write-LotusLine "  $($Rest[1]) saved in $($script:Paths.Settings)"
            return (St 0)
        }
        'list' { Show-LotusSettingsList; return (St 0) }
    }
    if (-not ((Test-LotusTty) -and (Test-LotusOutTty))) { Show-LotusSettingsList; return (St 0) }
    St (Show-LotusSettingsMenu)
}

function script:Show-LotusSettingsList {
    if (-not (Test-Path -LiteralPath $script:Paths.Settings)) { Write-LotusLine "  No settings yet ($($script:Paths.Settings))." }
    foreach ($k in $script:S.Keys) { Write-LotusLine ('  {0,-28}{1}' -f $k, $script:S[$k]) }
}

# type|variable|label|values (value=label;…), rebuilt when the language or a feature changes
function script:Get-LotusSettingsItems {
    $on = { param($id) Test-LotusFeature $id }
    $themes = ($script:ThemeNames | ForEach-Object { "$_=$($script:ThemeLabels[$_])" }) -join ';'
    $logos = ($script:LogoNames | ForEach-Object { "$_=$($script:LogoLabels[$_])" }) -join ';'
    $items = [System.Collections.Generic.List[string]]::new()
    $add = { param([string[]]$rows) foreach ($x in $rows) { $items.Add($x) } }
    & $add @(
        "head||$(T head_general 'General')|"
        "text|LOTUS_NAME|$(T name 'Name')|"
        "choice|LOTUS_LANG|$(T lang 'Language')|en=English;de=Deutsch;fr=Français;es=Español"
        "bool|LOTUS_STARTUP|$(T startup 'Auto-start on terminal launch')|"
        "choice|LOTUS_LOGO|$(T logo 'Logo')|$logos"
        "bool|LOTUS_LOGO_THEME|$(T logo_theme 'Logo in theme colors')|")
    if (Test-LotusOn $script:S['LOTUS_LOGO_THEME']) { & $add @("bool|LOTUS_LOGO_FADE|$(T logo_fade 'Logo gradient')|") }
    & $add @(
        "action|logos|$(T logos_action 'Preview logos, paste your own')|"
        "choice|LOTUS_THEME|$(T theme 'Theme')|$themes"
        "bool|LOTUS_PROMPT|$(T prompt 'Colored prompt')|"
        "head||$(T head_features 'Features')|")
    foreach ($id in $script:FeatureIds) { if ($id -cne 'core') { & $add @("feature|$id|$(Get-LotusFeatureLabel $id)|") } }
    & $add @(
        "head||$(T head_greeting 'Greeting')|"
        "choice|LOTUS_GREETING|$(T greet_top 'Top')|rotate=$(T rotate '15 languages in order');random=$(T random '15 languages, random');off=$(T off 'Off')"
        "choice|LOTUS_SALUTE|$(T greet_bottom 'Bottom, by time of day')|off=$(T off 'Off');fr=$(T sal_fr 'French');de=$(T sal_de 'German');en=$(T sal_en 'English');es=$(T sal_es 'Spanish')"
        "head||$(T head_sections 'Sections')|"
        "bool|LOTUS_SHOW_HARDWARE|$(T sec_hw 'Hardware')|"
        "bool|LOTUS_SHOW_SESSION|$(T sec_session 'Session')|"
        "bool|LOTUS_SHOW_TIME|$(T sec_time 'Uptime & date')|")
    if (& $on 'music') {
        & $add @(
            "bool|LOTUS_SHOW_MUSIC|$(T sec_music 'Now playing')|"
            "choice|LOTUS_INTERVAL|$(T interval 'Update every')|1=$(T sec1 '1 second');2=2 $(T secs 'seconds');3=3 $(T secs 'seconds');5=5 $(T secs 'seconds')")
    }
    & $add @(
        "choice|LOTUS_COLORS|$(T colors 'Color mode')|auto=$(T col_auto 'Automatic');truecolor=$(T col_tc '16M colors');256=$(T col_256 '256 colors')"
        "head||$(T head_clock 'Clock')|"
        "choice|LOTUS_CLOCK_DESIGN|$(T clk_design 'Design')|minimal=$(T clk_minimal 'Minimal');big=$(T clk_big 'Big');retro=$(T clk_retro 'Retro');matrix=$(T clk_matrix 'Matrix');analog=$(T clk_analog 'Analog');world=$(T clk_world 'World')"
        "choice|LOTUS_CLOCK_SECONDS|$(T clk_secs 'Seconds')|1=$(T on 'on');0=$(T off 'Off')"
        "text|LOTUS_CLOCK_ZONES|$(T clk_zones 'World clock: time zones')|")
    if (& $on 'visualizer') { & $add @("choice|LOTUS_VISUAL_MODE|$(T visual_mode 'Visualizer mode')|bars=Bars;wave=Wave;spectrum=Spectrum;particles=Particles;minimal=Minimal;circular=Circular;retro=Retro terminal;matrix=Matrix") }
    if ((& $on 'weather') -or (& $on 'web')) {
        & $add @("head||$(T head_weather 'Weather & web')|")
        if (& $on 'weather') { & $add @("text|LOTUS_WEATHER_LOCATION|$(T weather_city 'Weather city')|", "choice|LOTUS_WEATHER_UNITS|$(T units 'Units')|metric=°C, km/h;imperial=°F, mph") }
        if (& $on 'web') { & $add @("choice|LOTUS_SEARCH_ENGINE|$(T search_engine 'Search engine')|google=Google;duckduckgo=DuckDuckGo;bing=Bing;ecosia=Ecosia;brave=Brave Search") }
    }
    if (& $on 'ai') {
        & $add @(
            "head||$(T head_ai 'AI')|"
            "choice|LOTUS_AI_PROVIDER|$(T ai_provider 'Provider')|auto=$(T col_auto 'Automatic');claude=Claude;ollama=Ollama;openai=OpenAI-compatible"
            "choice|LOTUS_AI_EFFORT|$(T ai_effort 'Thinking')|low=$(T effort_low 'quick');medium=$(T effort_medium 'balanced');high=$(T effort_high 'thorough');max=$(T effort_max 'maximum');ultra=$(T effort_ultra 'ultra')"
            "text|LOTUS_AI_MODEL|$(T ai_model 'Model (optional)')|"
            "text|LOTUS_AI_URL|$(T ai_url 'API URL (optional)')|"
            "action|aikey|$(T ai_key 'API keys (Claude, OpenAI-compatible)')|")
    }
    if (& $on 'pets') {
        & $add @(
            "head||$(T head_pets 'Pets')|"
            "action|pets|$(T pet_manage 'Your pets')|"
            "bool|LOTUS_PET_START|$(T pet_start 'Pet on the start screen')|"
            "bool|LOTUS_PET_HELP|$(T pet_help '/help with a pet')|"
            "bool|LOTUS_PET_REACT|$(T pet_react 'Pets react')|"
            "choice|LOTUS_PET_BRAIN|$(T pet_brain 'Pets think with')|ai=$(T pet_brain_ai 'the AI of /ai');off=$(T pet_brain_off 'nothing, short phrases')")
    }
    & $add @(
        "head||$(T head_diag 'Diagnostics')|"
        "choice|LOTUS_LOG_LEVEL|$(T log_level 'Log level')|off=$(T log_off 'off');warn=$(T log_warn 'errors and warnings');info=$(T log_info 'normal');debug=$(T log_debug 'detailed');trace=$(T log_trace 'everything')"
        "choice|LOTUS_LOG_RETENTION|$(T log_keep 'Keep logs for')|1=1 $(T day 'day');7=7 $(T days 'days');30=30 $(T days 'days');90=90 $(T days 'days')"
        "bool|LOTUS_LOG_STARTUP|$(T log_startup 'Show startup details')|"
        "action|log|$(T log_open 'Open the log')|"
        "head||$(T head_lotus 'lotus')|"
        "action|shortcuts|$(T shortcuts_action 'Manage shortcuts')|"
        "action|setup|$(T setup_again 'Run setup again')|"
        "action|uninstall|$(T uninstall 'Uninstall Lotus')|")
    , $items.ToArray()
}

function script:Show-LotusSettingsMenu {
    $esc = [char]27
    $items = Get-LotusSettingsItems
    $field = { param($i) $items[$i - 1] -split '\|', 4 }
    $sel = 2; $top = 1; $msg = ''; $rc = 0
    $move = {
        param($d)
        $n = $items.Count; $j = $script:SetSel
        for ($x = 0; $x -lt $n; $x++) {
            $j = (($j - 1 + $d + $n) % $n) + 1
            if (($items[$j - 1] -split '\|')[0] -cne 'head') { $script:SetSel = $j; return }
        }
    }
    $script:SetSel = $sel
    Enter-LotusKeys
    Write-LotusRaw "$esc[?1049h$esc[?25l$esc[2J"
    try {
        while ($rc -eq 0) {
            $sel = $script:SetSel
            # all rows of the menu; only the part around the selection fits on the screen
            $acc = $script:C['accent']; $dim = $script:C['dim']
            $rows = [System.Collections.Generic.List[string]]::new()
            $selrow = 1
            for ($i = 1; $i -le $items.Count; $i++) {
                $f = & $field $i
                $t = $f[0]; $k = $f[1]; $label = $f[2]
                if ($t -ceq 'head') {
                    if ($i -gt 1) { $rows.Add('') }
                    $rows.Add("  $esc[$($dim)m$($label.ToUpper())$esc[0m")
                    continue
                }
                $v = if ($k -and $t -cnotin 'feature', 'action') { [string]$script:S[$k] } else { '' }
                $shown = switch ($t) {
                    'feature' { if (Test-LotusFeature $k) { "$esc[$($script:C['key'])m● $(T on 'on')$esc[0m" } else { "$esc[$($dim)m○ $((T off 'Off').ToLower())$esc[0m" } }
                    'bool' { if (Test-LotusOn $v) { "$esc[$($script:C['key'])m● $(T on 'on')$esc[0m" } else { "$esc[$($dim)m○ $((T off 'Off').ToLower())$esc[0m" } }
                    'choice' {
                        $vals = $f[3] -split ';'
                        $hit = $vals | Where-Object { ($_ -split '=', 2)[0] -ceq $v } | Select-Object -First 1
                        $lab = if ($hit) { ($hit -split '=', 2)[1] } else { $v }
                        if ($i -eq $sel) { "‹ $lab ›" } else { $lab }
                    }
                    'text' { $(if ($v) { $v } else { "$esc[$($dim)m–$esc[0m" }) + $(if ($i -eq $sel) { "$esc[$($dim)m  $(T edit '⏎ edit')$esc[0m" }) }
                    'action' { if ($i -eq $sel) { "$esc[$($dim)m$(T run '⏎ run')$esc[0m" } else { '' } }
                    default { '' }
                }
                $lab32 = PadR $label 32
                if ($k -ceq 'uninstall') { $lab32 = "$esc[38;5;203m$lab32$esc[0m" }
                if ($i -eq $sel) { $selrow = $rows.Count + 1; $rows.Add("  $esc[$($acc)m›$esc[0;1m $lab32$esc[0m$shown") }
                else { $rows.Add("    $lab32$shown") }
            }
            $screenH = (Get-LotusSize)[1]
            $h = [Math]::Max(6, $screenH - 7)
            if ($selrow -lt $top + 1) { $top = [Math]::Max(1, $selrow - 2) }
            if ($selrow -gt $top + $h - 2) { $top = $selrow - $h + 2 }
            if ($top -gt $rows.Count - $h + 1) { $top = $rows.Count - $h + 1 }
            if ($top -lt 1) { $top = 1 }
            $out = [System.Text.StringBuilder]::new("$esc[H$esc[K`n")
            [void]$out.Append("  $esc[1;$($acc)mlotus$esc[0;$($dim)m / $(T settings 'Settings') · v$(Get-LotusVersion)$esc[0m$esc[K`n$esc[K`n")
            for ($i = $top; $i -lt $top + $h -and $i -le $rows.Count; $i++) { [void]$out.Append("$($rows[$i - 1])$esc[K`n") }
            [void]$out.Append("$esc[K`n  $esc[$($dim)m$(T footer '↑↓ select   ←→ ⏎ change   v preview   r reset   q done')$esc[0m$esc[K`n")
            [void]$out.Append("  $msg$esc[K$esc[J")
            Write-LotusRaw $out.ToString()
            $msg = ''
            $key = Read-LotusKeyX
            switch -CaseSensitive -Regex ($key) {
                '^(up|k)$' { & $move -1; break }
                '^(down|j)$' { & $move 1; break }
                '^(right|l|space|enter)$' { $r = Set-LotusSettingsItem $items $script:SetSel 1; if ($r.Items) { $items = $r.Items }; $msg = $r.Msg; $rc = $r.Rc; break }
                '^(left|h)$' {
                    $t = (& $field $script:SetSel)[0]
                    if ($t -cnotin 'text', 'action') { $r = Set-LotusSettingsItem $items $script:SetSel -1; if ($r.Items) { $items = $r.Items }; $msg = $r.Msg }
                    break
                }
                '^[vp]$' {
                    Write-LotusRaw "$esc[H$esc[2J"
                    Show-LotusStart
                    Write-LotusRaw "`n  $esc[$($script:C['dim'])m$(T back '(press any key to go back)')$esc[0m"
                    [void](Read-LotusKeyX)
                    Write-LotusRaw "$esc[2J"
                    break
                }
                '^r$' {
                    if (Read-LotusSettingsAsk (T confirm_reset 'Reset all settings to their defaults? [y/N] ')) {
                        $keep = @{}
                        foreach ($n in 'LOTUS_NAME', 'LOTUS_LANG', 'LOTUS_FEATURES_OFF', 'LOTUS_BG_READY') { $keep[$n] = $script:S[$n] }
                        $sc = $script:Shortcuts
                        Reset-LotusSettings
                        foreach ($n in $keep.Keys) { $script:S[$n] = $keep[$n] }
                        $script:S['LOTUS_CONFIGURED'] = '1'; $script:S['LOTUS_CONFIG_VERSION'] = '3'
                        $script:Shortcuts = $sc
                        Save-LotusSettings
                        Import-LotusLang; Initialize-LotusColors
                        $items = Get-LotusSettingsItems
                        $msg = "$esc[$($script:C['key'])m$(T reset_done '✓ defaults restored')$esc[0m"
                    }
                    break
                }
                '^(q|Q|esc|interrupt)$' { $rc = -1; break }
            }
        }
    } finally {
        Write-LotusRaw "$esc[?1049l$esc[?25h"
        Exit-LotusKeys
    }
    if ($rc -eq 10) {
        Import-LotusCommand system
        Invoke-LotusUninstall @('--yes') | Out-Null
        return 10
    }
    0
}

# A question at the bottom of the screen → $true for yes
function script:Read-LotusSettingsAsk {
    param([string]$Question)
    $H = (Get-LotusSize)[1]
    Write-LotusRaw "$([char]27)[$H;1H$([char]27)[K$([char]27)[?25h  $Question"
    $k = Read-LotusKeyX
    Write-LotusRaw "$([char]27)[?25l"
    $k -cmatch '^[yYjJ]$'
}

# A line of text at the bottom of the screen → the text ($null: nothing typed, Esc)
function script:Read-LotusSettingsLine {
    param([string]$Label)
    $H = (Get-LotusSize)[1]
    Write-LotusRaw "$([char]27)[$H;1H$([char]27)[K$([char]27)[?25h  ${Label}: "
    $text = ''
    try {
        while ($true) {
            $k = Read-LotusKeyX
            switch -Regex ($k) {
                '^enter$' { return $text }
                '^(esc|interrupt)$' { return $null }
                '^back$' { if ($text.Length) { $text = $text.Substring(0, $text.Length - 1); Write-LotusRaw "`b `b" }; continue }
                '^space$' { $text += ' '; Write-LotusRaw ' '; continue }
                default { if ($k.Length -eq 1 -and -not [char]::IsControl($k[0]) -and $text.Length -lt 200) { $text += $k; Write-LotusRaw $k } }
            }
        }
    } finally { Write-LotusRaw "$([char]27)[?25l" }
}

# One row changed (_ls_change) → @{ Items (when the list changed); Msg; Rc (10 = uninstall) }
function script:Set-LotusSettingsItem {
    param([string[]]$Items, [int]$Sel, [int]$Dir)
    $f = $Items[$Sel - 1] -split '\|', 4
    $t = $f[0]; $k = $f[1]
    $saved = "$([char]27)[$($script:C['key'])m$(T saved '✓ saved')$([char]27)[0m"
    $res = @{ Items = $null; Msg = ''; Rc = 0 }
    switch ($t) {
        'bool' { $script:S[$k] = if (Test-LotusOn $script:S[$k]) { '0' } else { '1' } }
        'feature' {
            Set-LotusFeature $k (-not (Test-LotusFeature $k))
            Save-LotusSettings
            Initialize-Lotus
            $res.Items = Get-LotusSettingsItems
            for ($j = 1; $j -le $res.Items.Count; $j++) { if ($res.Items[$j - 1] -clike "feature|$k|*") { $script:SetSel = $j } }
            $res.Msg = $saved
            return $res
        }
        'choice' {
            $keys = @($f[3] -split ';' | ForEach-Object { ($_ -split '=', 2)[0] })
            $j = [Array]::IndexOf($keys, [string]$script:S[$k])
            if ($j -lt 0) { $j = 0 } else { $j = (($j + $Dir) % $keys.Count + $keys.Count) % $keys.Count }
            $script:S[$k] = $keys[$j]
        }
        'text' {
            $new = Read-LotusSettingsLine $f[2]
            if ($null -eq $new) { return $res }
            if ($k -ceq 'LOTUS_NAME' -and -not $new.Trim()) { return $res }
            $script:S[$k] = $new.TrimStart()
        }
        'action' {
            if ($k -ceq 'uninstall') {
                if (Read-LotusSettingsAsk (T confirm_un 'Uninstall lotus completely? [y/N] ')) { $res.Rc = 10 }
                return $res
            }
            $map = @{ logos = @('logo', 'logo'); shortcuts = @('shortcuts', 'shortcuts'); setup = @('setup', 'setup'); aikey = @('ai', 'ai', 'key'); log = @('log', 'log'); pets = @('pets', 'pets') }
            $run = $map[$k]
            if ($run) {
                Write-LotusRaw "$([char]27)[H$([char]27)[2J$([char]27)[?25h"
                Exit-LotusKeys
                try {
                    Initialize-Lotus
                    [void](@(Invoke-LotusDispatch $run[1] ([string[]]@($run | Select-Object -Skip 2))))
                } catch { Write-LotusError 'That did not work' $_.Exception.Message }
                Enter-LotusKeys
                Initialize-Lotus
                $res.Items = Get-LotusSettingsItems
                Write-LotusRaw "$([char]27)[?25l"
                if ($k -cnotin 'log', 'pets') { Write-LotusDim (T back '(press any key to go back)'); [void](Read-LotusKeyX) }
                Write-LotusRaw "$([char]27)[2J"
            }
            return $res
        }
    }
    Save-LotusSettings
    Reset-LotusLog
    Import-LotusLang
    Initialize-LotusColors
    if ($k -cin 'LOTUS_LANG', 'LOTUS_LOGO_THEME') { $res.Items = Get-LotusSettingsItems }
    $res.Msg = $saved
    $res
}
