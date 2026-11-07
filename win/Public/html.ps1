# /html on Windows – web pages, style sheets and scripts as Word, PDF, Text, Markdown, OpenDocument or RTF: a port of
# lib/cmd/html.zsh. The work is done by lib/html/convert.py and lotusdoc/ – the same converter as on the Mac, Python's
# standard library only (Python 3.9 or newer). The originals stay as they are: documents of single files go next to them,
# all of a folder goes into a folder of its own (Word\ …), nothing is written over.
#   /html                          the page open in Live Server's browser – or choose a file, or all of the folder
#   /html all                      every page, style sheet and script of the folder
#   /html <file|folder|pattern> …  these files (/html about.html, /html css, /html *.css)
#   … txt | md | docx | odt | rtf | pdf    the format, asked when it is not given ("word", "text" … work too)
#   … --code | --page              HTML as code (colored, numbered lines – the default) or as the page a visitor reads

# key | label | what it is good for (the order of the question)
$script:HtmlFormats = @(
    'docx|Word|.docx – for Word and Google Docs: what schools and offices ask for'
    'pdf|PDF|pages that look the same everywhere – to send or print'
    'txt|Text|.txt – opens everywhere; code stays exactly as it is'
    'md|Markdown|.md – for GitHub, notes and wikis'
    'odt|OpenDocument|.odt – for LibreOffice'
    'rtf|RTF|.rtf – for WordPad and older word processors'
)

# A word → txt md docx odt rtf pdf, or $null when it names none
function script:Get-LotusHtmlFormat {
    param([string]$Word)
    switch -Regex (([string]$Word).ToLowerInvariant().TrimStart('.')) {
        '^(txt|text|plain|plaintext)$' { return 'txt' }
        '^(md|markdown)$' { return 'md' }
        '^(docx|doc|word|msword)$' { return 'docx' }
        '^(odt|opendocument|libreoffice)$' { return 'odt' }
        '^(rtf|textedit|wordpad)$' { return 'rtf' }
        '^pdf$' { return 'pdf' }
    }
    $null
}
function script:Get-LotusHtmlLabel { param([string]$Key) foreach ($f in $script:HtmlFormats) { $p = $f -split '\|'; if ($p[0] -ceq $Key) { return $p[1] } }; $Key }

# The converter, with Lotus' colors and the folder where Live Server keeps what /html needs from it
function script:Get-LotusHtmlEnv {
    @{ LOTUS_LIVE_DATA = (Join-Path $script:Paths.State 'live'); LOTUS_NAME = [string]$script:S['LOTUS_NAME']
        LOTUS_COLOR_KEY = $script:C['key']; LOTUS_COLOR_ACCENT = $script:C['accent']; LOTUS_COLOR_DIM = $script:C['dim'] }
}
function script:Get-LotusHtmlScript { Join-Path (Get-LotusRoot) 'lib/html/convert.py' }

function script:Show-LotusHtmlHelp {
    Write-LotusHero 'HTML converter' 'Web pages, style sheets and scripts as Word, PDF, Text, Markdown, OpenDocument or RTF'
    $k = E key; $d = E dim; $r = $script:R
    foreach ($row in @('/html|the page open in Live Server – or choose a file, or all of them', '/html all|every page, style sheet and script → a folder of their own',
            '/html <file or folder>|these files – about.html, css, *.css', '  docx pdf txt md odt rtf|the format – asked when it is not given',
            '  --code|as code: colored like in your editor, numbered lines (default)', '  --page|HTML pages as a visitor reads them – text, lists, tables, pictures')) {
        $p = $row -split '\|', 2
        Write-LotusLine "    $k$(PadR $p[0] 28)$r$($p[1])"
    }
    Write-LotusBlank
    Write-LotusSection 'Examples'; Write-LotusBlank
    Write-LotusLine "    $d/html all docx         the whole project as Word documents, in my-site\Word$r"
    Write-LotusLine "    $d/html about.html pdf   that page as a PDF, next to it$r"
    Write-LotusLine "    $d/html all txt          every file as .txt – for uploads that refuse .html$r"
    Write-LotusBlank
    Write-LotusDim '  The originals stay as they are, nothing is written over. Nothing leaves this PC.'
    Write-LotusBlank
}

# "2 minutes ago"
function script:Format-LotusAgo {
    param([long]$Epoch)
    $s = (Get-LotusEpoch) - $Epoch
    if ($s -lt 60) { 'just now' } elseif ($s -lt 3600) { "$([Math]::Truncate($s / 60)) min ago" } elseif ($s -lt 86400) { "$([Math]::Truncate($s / 3600)) h ago" }
    elseif ($s -lt 172800) { 'yesterday' } else { "$([Math]::Truncate($s / 86400)) days ago" }
}

# The files of a folder that can be converted, the newest first → @(Kind; Time; Path), the newest first
function script:Get-LotusHtmlFiles {
    param($Python, [string]$Folder)
    $text = Invoke-LotusPythonText $Python (Get-LotusHtmlScript) @('scan', $Folder) (Get-LotusHtmlEnv)
    foreach ($line in ([string]$text) -split "`n") {
        $f = $line.TrimEnd("`r") -split "`t"
        if ($f.Count -eq 3 -and $f[0] -cne 'left') { [pscustomobject]@{ Kind = $f[0]; Time = (Get-LotusInt $f[1] 0); Path = $f[2] } }
    }
}

# "7 pages · 2 style sheets · 1 script"
function script:Format-LotusHtmlCount {
    param([object[]]$Files)
    $one = [ordered]@{ page = 'page'; style = 'style sheet'; script = 'script'; data = 'data file'; text = 'text' }
    @(foreach ($k in $one.Keys) {
            $n = @($Files | Where-Object Kind -ceq $k).Count
            if ($n) { "$n $($one[$k])$(if ($n -ne 1) { 's' })" }
        }) -join ' · '
}

function script:Get-LotusHtmlRel { param([string]$Path, [string]$Here) if ($Path.StartsWith($Here + [IO.Path]::DirectorySeparatorChar)) { $Path.Substring($Here.Length + 1) } else { $Path } }

function script:Invoke-Lotushtml {
    param([string]$Cmd, [string[]]$Rest)
    $here = (Get-Location).ProviderPath
    $lastFile = Join-Path $script:Paths.State 'html-last'
    New-LotusDir (Join-Path $script:Paths.State 'live') | Out-Null
    $fmt = $null; $mode = ''; $scope = ''
    $picks = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Rest.Count; $i++) {
        $arg = $Rest[$i]
        $low = $arg.ToLowerInvariant()
        if ($low -cin 'all', 'alles', 'alle', '--all', '-a', 'everything', 'tout', 'todo') { $scope = 'all' }
        elseif ($low -cin '--to', '-t') { if ($i + 1 -lt $Rest.Count) { $i++; $f = Get-LotusHtmlFormat $Rest[$i]; if ($f) { $fmt = $f } } }
        elseif ($low.StartsWith('--to=')) { $f = Get-LotusHtmlFormat $low.Substring(5); if ($f) { $fmt = $f } }
        elseif ($low -cin '--page', '--pages', 'page', 'pages', 'seite') { $mode = 'page' }
        elseif ($low -cin '--code', 'code', 'source') { $mode = 'code' }
        elseif ($low -cin '-', '->', '→', '=>', 'to', 'into', 'in', 'as', 'als', 'nach', 'zu') { }
        elseif ($low -cin 'help', '-h', '--help') { Show-LotusHtmlHelp; return (St 0) }
        else { $f = Get-LotusHtmlFormat $arg; if ($f) { $fmt = $f } else { $picks.Add($arg) } }
    }
    Write-LotusHero 'HTML converter' 'Web pages, style sheets and scripts as Word, PDF, Text, Markdown, OpenDocument or RTF'
    $py = Find-LotusPython
    if (-not $py) { Write-LotusError '/html needs Python 3.9 or newer' 'Python is free; Lotus uses only its standard library.' @('winget install --id Python.Python.3.13 -e   then open a new window'); return (St 1) }
    $ask = (Test-LotusTty) -and (Test-LotusOutTty)
    $ok = "  $(E '1')$(E key)✓$($script:R)"; $d = E dim; $r = $script:R

    # ── what: files, a folder, all of the folder – or the page open in Live Server
    $root = $here
    $files = [System.Collections.Generic.List[string]]::new()
    $found = @()
    foreach ($p in $picks) {
        if ($p -match '[*?\[]') {
            $pattern = if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $here $p }
            $hits = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | ForEach-Object FullName)
            if (-not $hits.Count) { Write-LotusWarn "Nothing matches $p" }
            foreach ($h in $hits) { $files.Add($h) }
            continue
        }
        $q = ConvertTo-LotusCleanPath $p
        if (Test-Path -LiteralPath $q -PathType Container) { $root = $q; $scope = 'all' }
        elseif (Test-Path -LiteralPath $q -PathType Leaf) { $files.Add($q) }
        else { Write-LotusWarn "Not found: $p" }
    }
    $home_ = Get-LotusHome
    $isTop = { param($dir) $dir.TrimEnd('\', '/') -eq $home_.TrimEnd('\', '/') -or $dir -eq [IO.Path]::GetPathRoot($dir) -or $dir.TrimEnd('\', '/') -eq (Split-Path -Parent $home_).TrimEnd('\', '/') }
    if ($scope -ceq 'all') {
        if (& $isTop $root) {
            Write-LotusError "That is your whole $(if ($root.TrimEnd('\', '/') -eq $home_.TrimEnd('\', '/')) { 'home folder' } else { 'disk' }) – go to the folder of a project first" '' @('cd ~\path\to\site   then   /html all')
            return (St 1)
        }
        $found = @(Get-LotusHtmlFiles $py $root)
        if (-not $found.Count) { Write-LotusError "No web files in $(Format-LotusHomePath $root)" '' @('Pages (.html), style sheets (.css) and scripts (.js) – /html <file> for one of its own'); return (St 1) }
        Write-LotusLine "$ok All of $(Split-Path -Leaf $root)  $d$(Format-LotusHtmlCount $found)$r"
        Write-LotusBlank
    } elseif ($files.Count) {
        $unique = @($files | Select-Object -Unique)
        $files = [System.Collections.Generic.List[string]]::new(); foreach ($f in $unique) { $files.Add($f) }
        Write-LotusLine "$ok $(Get-LotusHtmlRel $files[0] $here)$(if ($files.Count -gt 1) { " and $($files.Count - 1) more" })"
        Write-LotusBlank
    } else {
        $open = [string](Invoke-LotusPythonText $py (Get-LotusHtmlScript) @('open', $here) (Get-LotusHtmlEnv))
        if ($open.Trim()) {
            $files.Add($open.Trim())
            Write-LotusLine "$ok $(Get-LotusHtmlRel $open.Trim() $here)  ${d}open in the browser right now$r"
            Write-LotusBlank
        } else {
            if (& $isTop $here) { Write-LotusError 'Which file?' 'Here in your home folder there is no page open in Live Server.' @('cd ~\path\to\site   then   /html   ·   /html <file>'); return (St 1) }
            $found = @(Get-LotusHtmlFiles $py $here)
            if (-not $found.Count) { Write-LotusError 'No web files here' "$(Format-LotusHomePath $here) has no pages, style sheets or scripts." @('cd into your project – or /html <file>'); return (St 1) }
            if (-not $ask) { Write-LotusError 'Which file?' 'No page is open in Live Server.' @('/html <file> <format>   ·   /html all <format>'); return (St 1) }
            $opts = [System.Collections.Generic.List[string]]::new()
            $opts.Add("$(Get-LotusHtmlRel $found[0].Path $here)|the newest – changed $(Format-LotusAgo $found[0].Time)")
            if ($found.Count -gt 1) { $opts.Add("$(Get-LotusHtmlRel $found[1].Path $here)|changed $(Format-LotusAgo $found[1].Time)") }
            $opts.Add("All of $(Split-Path -Leaf $here)|$(Format-LotusHtmlCount $found) → a folder of their own")
            if ($found.Count -gt 2) { $opts.Add("Another file …|one of the $($found.Count) in this folder") }
            Write-LotusLine "  $($script:B)What should become a document?$r"
            $pick = Read-LotusSelect 1 $opts.ToArray()
            if ($null -eq $pick) { return (St 0) }
            $chosen = $opts[$pick - 1]
            if ($chosen.StartsWith('All of ')) { $scope = 'all' }
            elseif ($chosen.StartsWith('Another file')) {
                $which = Read-LotusChoice 'Which file?' @($found | ForEach-Object { Get-LotusHtmlRel $_.Path $here })
                if ($null -eq $which) { return (St 0) }
                $files.Add($found[$which - 1].Path)
            } else { $files.Add($found[$pick - 1].Path) }
            Write-LotusBlank
        }
    }

    # ── the format – and the choice of last time
    $last = ([string](Read-LotusFile $lastFile)).Trim()
    if (-not $fmt) {
        if (-not $ask) { Write-LotusError 'Into which format?' '' @('/html … docx   ·   pdf   ·   txt   ·   md   ·   odt   ·   rtf'); return (St 1) }
        $keys = @($script:HtmlFormats | ForEach-Object { ($_ -split '\|')[0] })
        $opts = @($script:HtmlFormats | ForEach-Object { $p = $_ -split '\|'; "$($p[1])|$($p[2])" })
        Write-LotusLine "  $($script:B)Into which format?$r"
        $sel = [Array]::IndexOf($keys, ($last -split '\|')[0]) + 1
        $pick = Read-LotusSelect $(if ($sel -gt 0) { $sel } else { 1 }) $opts
        if ($null -eq $pick) { return (St 0) }
        $fmt = $keys[$pick - 1]
    }

    # ── code or page – only a question when there are HTML pages
    $pages = if ($scope -ceq 'all') { [bool]@($found | Where-Object Kind -ceq 'page').Count } else { [bool]@($files | Where-Object { $_ -match '\.(html|htm|xhtml)$' }).Count }
    if (-not $mode -and -not $ask) { $mode = 'code' }
    elseif (-not $mode) {
        $mode = ($last -split '\|', 2 | Select-Object -Skip 1 -First 1)
        if ($mode -cnotin 'code', 'page') { $mode = 'code' }
        if ($pages) {
            Write-LotusLine "  $($script:B)What should it show?$r"
            $pick = Read-LotusSelect $(if ($mode -ceq 'page') { 2 } else { 1 }) @(
                'The code|as you wrote it – colored like in your editor, every line with its number'
                'The page|what a visitor reads – headings, text, lists, tables, links and pictures')
            if ($null -eq $pick) { return (St 0) }
            $mode = if ($pick -eq 2) { 'page' } else { 'code' }
        }
    }
    if ($ask) { try { Write-LotusFile $lastFile "$fmt|$mode`n" } catch { } }

    # ── the work: convert.py says what it did, and writes where the documents went into a file
    $result = Join-Path ([IO.Path]::GetTempPath()) "lotus-html-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8)).txt"
    $argv = @('convert', '--to', $fmt, "--$mode", '--root', $root, '--result', $result)
    $argv += if ($scope -ceq 'all') { @('--all') } else { @($files) }
    Write-LotusLog INFO html "$(if ($scope) { $scope } else { "$($files.Count) file(s)" }) → $(Get-LotusHtmlLabel $fmt) ($mode)"
    $rc = Invoke-LotusPython $py (Get-LotusHtmlScript) $argv (Get-LotusHtmlEnv)
    $first = ''; $folder = ''
    foreach ($line in ([string](Read-LotusFile $result)) -split "`n") {
        if ($line.StartsWith("first`t")) { $first = $line.Substring(6) }
        if ($line.StartsWith("folder`t")) { $folder = $line.Substring(7) }
    }
    Remove-Item -LiteralPath $result -Force -ErrorAction SilentlyContinue
    if ($rc -ne 0) { return (St $rc) }
    Show-LotusPetReact done
    if ($ask) {
        Write-LotusBlank
        if ($folder) { if (Read-LotusConfirm 'Show the folder in File Explorer?' 'y') { [void](Open-LotusTarget $folder) } }
        elseif ($first) { if (Read-LotusConfirm 'Open it?' 'y') { [void](Open-LotusTarget $first) } }
    }
    St 0
}
