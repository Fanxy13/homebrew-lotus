# /html – a command of the Live Server plugin (plugin.conf): web pages, style sheets and scripts as documents.
#   /html                          the page open in Live Server's browser – or choose a file, or all of the folder
#   /html all                      every page, style sheet and script of the folder → a folder of their own (Word/ …)
#   /html <file|folder|pattern> …  these files (/html about.html, /html css, /html *.css)
#   … txt | md | docx | odt | rtf | pdf    the format, asked when it is not given ("word", "text" … work too)
#   … --code | --page              HTML as code (colored, numbered lines – the default) or as the page a visitor reads
# The work is done by convert.py and lotusdoc/ – Python's standard library, nothing to install. The originals stay as
# they are; documents of single files go next to them, nothing is written over.
source $LOTUS_ROOT/lib/core.zsh && source $LOTUS_ROOT/lib/ui.zsh && lotus_load || exit 1
setopt extendedglob
zmodload -F zsh/stat b:zstat 2>/dev/null
typeset -g LOTUS_LOG_COMP=html
typeset -g CONV=${LOTUS_PLUGIN_DIR:-${0:A:h}}/convert.py
typeset -g HERE=${${LOTUS_PWD:-$PWD}:A}
typeset -g LAST=${LOTUS_PLUGIN_DATA:-$HOME/.local/share/lotus/plugins/liveserver}/html-last
cd -q -- $HERE 2>/dev/null            # a plugin starts in its own folder: paths are the user's, from the folder they are in

# key | label | what it is good for (the order of the question)
typeset -ga HTML_FORMATS=(
  "docx|Word|.docx – for Word, Pages and Google Docs: what schools and offices ask for"
  "pdf|PDF|pages that look the same everywhere – to send or print"
  "txt|Text|.txt – opens everywhere; code stays exactly as it is"
  "md|Markdown|.md – for GitHub, notes and wikis"
  "odt|OpenDocument|.odt – for LibreOffice"
  "rtf|RTF|.rtf – for TextEdit and older word processors"
)

html_format() {   # a word → REPLY (txt md docx odt rtf pdf); status 1 when it names none
  case ${(L)1#.} in
    txt|text|plain|plaintext)       REPLY=txt ;;
    md|markdown)                    REPLY=md ;;
    docx|doc|word|msword)           REPLY=docx ;;
    odt|opendocument|libreoffice)   REPLY=odt ;;
    rtf|textedit)                   REPLY=rtf ;;
    pdf)                            REPLY=pdf ;;
    *) return 1 ;;
  esac
}

html_label() {    # txt → Text …
  local f
  for f in $HTML_FORMATS; do [[ ${f%%|*} == $1 ]] && { REPLY=${${f#*|}%%|*}; return }; done
  REPLY=$1
}

html_help() {
  ui_hero "HTML converter" "Web pages, style sheets and scripts as Word, PDF, Text, Markdown, OpenDocument or RTF"
  local k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" r
  local -a rows=(
    "/html|the page open in Live Server – or choose a file, or all of them"
    "/html all|every page, style sheet and script → a folder of their own"
    "/html <file or folder>|these files – about.html, css, *.css"
    "  docx pdf txt md odt rtf|the format – asked when it is not given"
    "  --code|as code: colored like in your editor, numbered lines (default)"
    "  --page|HTML pages as a visitor reads them – text, lists, tables, pictures")
  for r in $rows; do print -r -- "    ${k}${(r:28:)${r%%|*}}${_UI_R}${r#*|}"; done
  ui_blank
  ui_section Examples; ui_blank
  print -r -- "    ${d}/html all docx         the whole project as Word documents, in my-site/Word${_UI_R}"
  print -r -- "    ${d}/html about.html pdf   that page as a PDF, next to it${_UI_R}"
  print -r -- "    ${d}/html all txt          every file as .txt – for uploads that refuse .html${_UI_R}"
  ui_blank
  ui_dim "  The originals stay as they are, nothing is written over. Nothing leaves this Mac."
  ui_blank
}

html_ago() {      # <epoch> → REPLY "2 minutes ago"
  local -i s=$(( EPOCHSECONDS - $1 ))
  if (( s < 60 )); then REPLY="just now"
  elif (( s < 3600 )); then REPLY="$(( s / 60 )) min ago"
  elif (( s < 86400 )); then REPLY="$(( s / 3600 )) h ago"
  elif (( s < 172800 )); then REPLY="yesterday"
  else REPLY="$(( s / 86400 )) days ago"; fi
}

# The files of a folder that can be converted, the newest first → HTML_FILES, HTML_KINDS, HTML_TIMES, HTML_LEFT
html_scan() {
  typeset -ga HTML_FILES=() HTML_KINDS=() HTML_TIMES=()
  typeset -gA HTML_LEFT=()
  local line
  local -a f
  for line in "${(@f)$(python3 -B $CONV scan $1 2>/dev/null)}"; do
    f=("${(@ps:\t:)line}")
    if [[ $f[1] == left ]]; then HTML_LEFT[$f[2]]=$f[3]
    elif (( ${#f} == 3 )); then HTML_FILES+=($f[3]) HTML_KINDS+=($f[1]) HTML_TIMES+=($f[2]); fi
  done
}

html_count() {    # what HTML_KINDS holds → REPLY "7 pages · 2 style sheets · 1 script"
  local -A n=()
  local k
  local -a out=()
  for k in $HTML_KINDS; do (( n[$k]++ )); done
  local -A one=(page page style "style sheet" script script data "data file" text text)
  for k in page style script data text; do
    (( n[$k] )) || continue
    out+=("$n[$k] ${one[$k]}${${n[$k]:#1}:+s}")
  done
  REPLY=${(j: · :)out}
}

html_main() {
  local fmt= mode= scope= arg
  local -a picks=()
  local -i dash=0
  while (( $# )); do
    arg=$1; shift
    case ${(L)arg} in
      all|alles|alle|--all|-a|everything) scope=all ;;
      --to|-t)   html_format "${1:-}" && fmt=$REPLY; (( $# )) && shift ;;
      --to=*)    html_format "${arg#*=}" && fmt=$REPLY ;;
      --page|--pages|page|pages|seite) mode=page ;;
      --code|code|source)              mode=code ;;
      -)                               dash=1 ;;
      '->'|'→'|'=>'|to|into|in|as|als|nach|zu) ;;
      help|-h|--help) html_help; return 0 ;;
      *) if html_format "$arg"; then fmt=$REPLY; else picks+=("$arg"); fi ;;
    esac
  done

  # "/html -> txt": zsh took the > for a redirect – what Lotus prints would go into a new file "txt". It goes away
  # again, and txt is the format.
  if (( dash )) && [[ ! -t 1 ]]; then
    local -A me there
    local w
    if zstat -H me -f 1 2>/dev/null; then
      for w in txt text md markdown docx doc word odt rtf pdf; do
        [[ -f $HERE/$w ]] || continue
        zstat -H there -- $HERE/$w 2>/dev/null || continue
        [[ $there[inode] == $me[inode] && $there[device] == $me[device] ]] && (( there[size] < 4096 )) || continue
        rm -f -- $HERE/$w
        html_format $w && fmt=$REPLY
        { exec >/dev/tty } 2>/dev/null
        break
      done
    fi
  fi

  ui_hero "HTML converter" "Web pages, style sheets and scripts as Word, PDF, Text, Markdown, OpenDocument or RTF"
  if (( ! $+commands[python3] )); then
    ui_error "/html needs Python 3" "" "xcode-select --install   (Apple's Command Line Tools bring it)"
    return 1
  fi
  local -i ask=0
  ui_has_tty && [[ -t 1 ]] && ask=1

  # ── what: files, a folder, all of the folder – or the page open in Live Server
  local root=$HERE p q found
  local -a files=()
  for p in $picks; do
    ui_clean_path "$p"
    q=$REPLY
    if [[ $p == *[*?\[]* ]]; then
      [[ $p == /* ]] && found=(${~p}(N.)) || found=($HERE/${~p}(N.))
      (( ${#found} )) || ui_warn "Nothing matches $p"
      files+=($found)
    elif [[ -d $q ]]; then
      root=$q scope=all
    elif [[ -f $q ]]; then
      files+=($q)
    else
      ui_warn "Not found: $p"
    fi
  done
  if [[ $scope == all ]]; then
    if [[ $root == ($HOME|/|${HOME:h}) ]]; then
      ui_error "That is your whole ${${${root:#$HOME}:+disk}:-home folder} – go to the folder of a project first" "" \
        "cd ~/path/to/site   then   /html all"
      return 1
    fi
    html_scan $root
    if (( ! ${#HTML_FILES} )); then
      ui_error "No web files in ${root/#$HOME/~}" "" "Pages (.html), style sheets (.css) and scripts (.js) – /html <file> for one of its own"
      return 1
    fi
    html_count
    print -r -- "  "$'\e[1;'"$LOTUS_C[key]m✓"$_UI_R" All of ${root:t}  "$'\e['"$LOTUS_C[dim]m$REPLY"$_UI_R
    ui_blank
  elif (( ${#files} )); then
    files=(${(u)files})
    local more=
    (( ${#files} > 1 )) && more=" and $(( ${#files} - 1 )) more"
    print -r -- "  "$'\e[1;'"$LOTUS_C[key]m✓"$_UI_R" ${files[1]#$HERE/}$more"
    ui_blank
  else
    local open=
    open=$(python3 -B $CONV open $HERE 2>/dev/null)
    if [[ -n $open ]]; then
      files=($open)
      print -r -- "  "$'\e[1;'"$LOTUS_C[key]m✓"$_UI_R" ${open#$HERE/}  "$'\e['"$LOTUS_C[dim]m"open in the browser right now$_UI_R
      ui_blank
    else
      if [[ $HERE == ($HOME|/) ]]; then
        ui_error "Which file?" "Here in your home folder there is no page open in Live Server." "cd ~/path/to/site   then   /html   ·   /html <file>"
        return 1
      fi
      html_scan $HERE
      if (( ! ${#HTML_FILES} )); then
        ui_error "No web files here" "${HERE/#$HOME/~} has no pages, style sheets or scripts." "cd into your project – or /html <file>"
        return 1
      fi
      if (( ! ask )); then
        ui_error "Which file?" "No page is open in Live Server." "/html <file> <format>   ·   /html all <format>"
        return 1
      fi
      html_ago $HTML_TIMES[1]
      local -a opts=("${HTML_FILES[1]#$HERE/}|the newest – changed $REPLY")
      (( ${#HTML_FILES} > 1 )) && { html_ago $HTML_TIMES[2]; opts+=("${HTML_FILES[2]#$HERE/}|changed $REPLY") }
      html_count
      opts+=("All of ${HERE:t}|$REPLY → a folder of their own")
      (( ${#HTML_FILES} > 2 )) && opts+=("Another file …|one of the ${#HTML_FILES} in this folder")
      print -r -- "  ${_UI_B}What should become a document?${_UI_R}"
      ui_select 1 "${opts[@]}" || return 0
      local -i pick=$REPLY
      if [[ ${opts[pick]} == "All of "* ]]; then
        scope=all
      elif [[ ${opts[pick]} == "Another file …"* ]]; then
        ui_choose "Which file?" ${HTML_FILES#$HERE/} || return 0
        files=($HTML_FILES[REPLY])
      else
        files=($HTML_FILES[pick])
      fi
      ui_blank
    fi
  fi

  # ── the format
  local last=
  [[ -r $LAST ]] && last=$(<$LAST)
  if [[ -z $fmt ]]; then
    if (( ! ask )); then
      ui_error "Into which format?" "" "/html … docx   ·   pdf   ·   txt   ·   md   ·   odt   ·   rtf"
      return 1
    fi
    local -a opts=() keys=()
    local f
    for f in $HTML_FORMATS; do
      local -a part=("${(@s:|:)f}")
      opts+=("$part[2]|$part[3]") keys+=($part[1])
    done
    print -r -- "  ${_UI_B}Into which format?${_UI_R}"
    local -i sel=${keys[(Ie)${last%%|*}]}
    ui_select ${sel:-1} "${opts[@]}" || return 0
    fmt=$keys[REPLY]
  fi

  # ── code or page – only a question when there are HTML pages
  local -i pages=0
  if [[ $scope == all ]]; then
    (( ${HTML_KINDS[(Ie)page]} )) && pages=1
  else
    for f in $files; do [[ ${(L)f} == *.(html|htm|xhtml) ]] && pages=1; done
  fi
  if [[ -z $mode ]] && (( ! ask )); then
    mode=code                           # without questions: code, unless --page says otherwise
  elif [[ -z $mode ]]; then
    mode=${${last#*|}:-code}
    [[ $mode == (code|page) ]] || mode=code
    if (( pages )); then
      print -r -- "  ${_UI_B}What should it show?${_UI_R}"
      local -i msel=1
      [[ $mode == page ]] && msel=2
      ui_select $msel \
        "The code|as you wrote it – colored like in your editor, every line with its number" \
        "The page|what a visitor reads – headings, text, lists, tables, links and pictures" || return 0
      (( REPLY == 2 )) && mode=page || mode=code
    fi
  fi
  (( ask )) && { zf_mkdir -p ${LAST:h} && print -r -- "$fmt|$mode" >| $LAST } 2>/dev/null     # the choice, for next time

  # ── the work: convert.py prints what it did
  local result=${TMPDIR:-/tmp}/lotus-html-$$.txt
  local -a run=(python3 -B $CONV convert --to $fmt --$mode --root $root --result $result)
  [[ $scope == all ]] && run+=(--all) || run+=($files)
  html_label $fmt
  lotus_log INFO html "${scope:-${#files} file(s)} → $REPLY ($mode)"
  $run
  local -i rc=$?
  local first= folder= line
  if [[ -r $result ]]; then
    for line in "${(@f)$(<$result)}"; do
      [[ $line == first$'\t'* ]] && first=${line#*$'\t'}
      [[ $line == folder$'\t'* ]] && folder=${line#*$'\t'}
    done
  fi
  rm -f -- $result
  (( rc == 0 )) || return $rc
  lotus_pet_react done 2>/dev/null
  if (( ask )) && (( $+commands[open] )); then
    ui_blank
    if [[ -n $folder ]]; then
      ui_confirm "Show the folder in Finder?" y && open -- $folder
    elif [[ -n $first ]]; then
      ui_confirm "Open it?" y && open -- $first
    fi
  fi
  return 0
}

html_main "$@"
