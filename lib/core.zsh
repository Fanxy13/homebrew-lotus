# lotus – core functions. Loaded by init.zsh (shell) and bin/lotus (command).

typeset -g LOTUS_VERSION=2.4.0
typeset -g LOTUS_ROOT=${${(%):-%x}:A:h:h}
typeset -g LOTUS_CONF=${XDG_CONFIG_HOME:-$HOME/.config}/lotus
typeset -g LOTUS_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/lotus
typeset -g LOTUS_DATA=${XDG_DATA_HOME:-$HOME/.local/share}/lotus     # downloaded runtimes and models
typeset -g LOTUS_FF=${commands[fastfetch]:-$LOTUS_ROOT/vendor/fastfetch}

zmodload zsh/datetime
zmodload -F zsh/stat b:zstat
zmodload -F zsh/files b:zf_mv b:zf_mkdir
source $LOTUS_ROOT/lib/log.zsh

# ── Settings ──────────────────────────────────────────────────

typeset -ga LOTUS_KEYS=(
  LOTUS_NAME LOTUS_LANG LOTUS_STARTUP LOTUS_LOGO LOTUS_THEME LOTUS_PROMPT LOTUS_COLORS
  LOTUS_GREETING LOTUS_SALUTE
  LOTUS_SHOW_HARDWARE LOTUS_SHOW_SESSION LOTUS_SHOW_TIME LOTUS_SHOW_MUSIC
  LOTUS_LIVE LOTUS_INTERVAL
  LOTUS_WEATHER_LOCATION LOTUS_WEATHER_UNITS LOTUS_SEARCH_ENGINE LOTUS_VISUAL_MODE
  LOTUS_AI_PROVIDER LOTUS_AI_MODEL LOTUS_AI_URL LOTUS_AI_EFFORT LOTUS_AI_LOCAL
  LOTUS_FEATURES_OFF
  LOTUS_BG_READY LOTUS_BG_MODEL LOTUS_BG_BACKEND LOTUS_BG_OUTPUT LOTUS_BG_REFINE LOTUS_BG_PREVIEW
  LOTUS_LOG_LEVEL LOTUS_LOG_RETENTION LOTUS_LOG_STARTUP
  LOTUS_PET_START LOTUS_PET_HELP LOTUS_PET_REACT LOTUS_PET_BRAIN
  LOTUS_CONFIGURED LOTUS_CONFIG_VERSION
)

lotus_defaults() {
  typeset -g LOTUS_NAME= LOTUS_LANG=en LOTUS_STARTUP=1 LOTUS_LOGO=lotus LOTUS_THEME=matcha
  typeset -g LOTUS_PROMPT=0 LOTUS_COLORS=auto LOTUS_GREETING=rotate LOTUS_SALUTE=off
  typeset -g LOTUS_SHOW_HARDWARE=1 LOTUS_SHOW_SESSION=1 LOTUS_SHOW_TIME=1 LOTUS_SHOW_MUSIC=1
  typeset -g LOTUS_LIVE=1 LOTUS_INTERVAL=2
  typeset -g LOTUS_WEATHER_LOCATION= LOTUS_WEATHER_UNITS=metric LOTUS_SEARCH_ENGINE=google
  typeset -g LOTUS_VISUAL_MODE=bars LOTUS_AI_PROVIDER=auto LOTUS_AI_MODEL= LOTUS_AI_URL= LOTUS_AI_EFFORT=high LOTUS_AI_LOCAL=
  typeset -g LOTUS_FEATURES_OFF=
  typeset -g LOTUS_BG_READY=0 LOTUS_BG_MODEL=auto LOTUS_BG_BACKEND=auto LOTUS_BG_REFINE=ask LOTUS_BG_PREVIEW=0
  typeset -g LOTUS_BG_OUTPUT='~/Pictures/Lotus/Background Removed'
  typeset -g LOTUS_LOG_LEVEL=info LOTUS_LOG_RETENTION=7 LOTUS_LOG_STARTUP=0
  typeset -g LOTUS_PET_START=1 LOTUS_PET_HELP=1 LOTUS_PET_REACT=1 LOTUS_PET_BRAIN=apple
  typeset -g LOTUS_CONFIGURED=0 LOTUS_CONFIG_VERSION=0
  typeset -gA LOTUS_SHORTCUTS=()
}

lotus_load() {
  lotus_defaults
  if [[ -r $LOTUS_CONF/settings.zsh ]]; then
    source $LOTUS_CONF/settings.zsh
    lotus_migrate
  fi
  if [[ -z $LOTUS_NAME ]]; then
    local -a full=(${=$(id -F 2>/dev/null)})
    (( ${#full[1]} > 1 )) && LOTUS_NAME=$full[1] || LOTUS_NAME=${(C)${USER:-${LOGNAME:-$(id -un)}}}
  fi
  [[ $LOTUS_INTERVAL == <1-60> ]] || LOTUS_INTERVAL=2
  [[ -n ${LOTUS_LOG_RANK[$LOTUS_LOG_LEVEL]} ]] || LOTUS_LOG_LEVEL=info
  _lotus_log_max=-1
  # Now playing needs the Music feature as well as its start screen section
  (( LOTUS_SHOW_MUSIC )) && lotus_feature_on music && LOTUS_NP_ON=1 || LOTUS_NP_ON=0
  lotus_project
  lotus_lang
  lotus_colors
  lotus_snapshot
}

# Settings written by older versions keep working. Every key that is missing gets its default,
# nothing the user chose is changed.
#   1.x → 2.0  the bottom greeting is off, the wizard is not shown again
#   2.x → 2.2  features, Remove BG and logging start with their defaults (all features on)
lotus_migrate() {
  [[ $LOTUS_LOGO == heart ]] && LOTUS_LOGO=lotus   # older versions called the lotus "heart"
  (( LOTUS_CONFIG_VERSION >= 3 )) && return
  local from=$LOTUS_CONFIG_VERSION
  if (( LOTUS_CONFIG_VERSION < 2 )); then
    LOTUS_SALUTE=off
    LOTUS_CONFIGURED=1          # an existing user does not need the first-time wizard
  fi
  LOTUS_CONFIG_VERSION=3
  [[ -w $LOTUS_CONF/settings.zsh ]] || return
  lotus_save quiet
  lotus_log INFO settings "Settings migrated from version $from to 3 (Lotus $LOTUS_VERSION)"
}

# Project constants (website, GitHub, …) from data/project.tsv → LOTUS_P[key]
lotus_project() {
  (( ${+LOTUS_P} )) && return
  typeset -gA LOTUS_P=()
  local line
  for line in "${(@f)$(<$LOTUS_ROOT/data/project.tsv)}"; do
    [[ $line == \#* || $line != *$'\t'* ]] && continue
    LOTUS_P[${line%%$'\t'*}]=${line#*$'\t'}
  done
}

# Loads the UI texts: English first, then the chosen language on top
lotus_lang() {
  typeset -gA LOTUS_L=()
  typeset -ga _lotus_lang_groups=()
  source $LOTUS_ROOT/lib/lang/en.zsh
  [[ $LOTUS_LANG != en && -r $LOTUS_ROOT/lib/lang/$LOTUS_LANG.zsh ]] && source $LOTUS_ROOT/lib/lang/$LOTUS_LANG.zsh
  return 0
}

# Texts of a bigger screen (setup, bg, log), loaded only when it opens: lotus_lang_group bg
lotus_lang_group() {
  (( ${_lotus_lang_groups[(Ie)$1]} )) && return
  _lotus_lang_groups+=($1)
  source $LOTUS_ROOT/lib/lang/$1.en.zsh
  [[ $LOTUS_LANG != en && -r $LOTUS_ROOT/lib/lang/$1.$LOTUS_LANG.zsh ]] && source $LOTUS_ROOT/lib/lang/$1.$LOTUS_LANG.zsh
  return 0     # English has no second file – that is not a failure (the setup took it for "back")
}

# Writes the settings file. Changed keys are logged (personal values only as "changed").
lotus_save() {
  zf_mkdir -p $LOTUS_CONF
  local k out="# lotus – settings (easier: lotus settings)"$'\n'
  local -a changed=()
  for k in $LOTUS_KEYS; do
    out+="$k=${(qq)${(P)k}}"$'\n'
    [[ ${+_lotus_saved} == 1 && ${_lotus_saved[$k]-} != ${(P)k} ]] && changed+=($k)
  done
  if (( ${#LOTUS_SHORTCUTS} )); then
    out+="typeset -gA LOTUS_SHORTCUTS=(${(@qqkv)LOTUS_SHORTCUTS})"$'\n'
  else
    out+="typeset -gA LOTUS_SHORTCUTS=()"$'\n'
  fi
  print -rn -- $out >| $LOTUS_CONF/settings.zsh
  if [[ $1 != quiet ]] && (( ${#changed} )); then
    lotus_log INFO settings "Changed: ${changed#LOTUS_}"
    for k in $changed; do
      [[ $k == (LOTUS_NAME|LOTUS_WEATHER_LOCATION|LOTUS_BG_OUTPUT|LOTUS_AI_URL) ]] && continue
      lotus_log DEBUG settings "${k#LOTUS_} = ${(P)k}"
    done
  fi
  lotus_snapshot
}

# Remembers the saved values, so the next save can tell what changed
lotus_snapshot() {
  typeset -gA _lotus_saved=()
  local k
  for k in $LOTUS_KEYS; do _lotus_saved[$k]=${(P)k}; done
}

# ── Features ──────────────────────────────────────────────────

# Is a feature turned on?  lotus_feature_on bg   (data/features.tsv lists them)
lotus_feature_on() { [[ " $LOTUS_FEATURES_OFF " != *" $1 "* ]] }

# data/features.tsv → LOTUS_FEATURE_IDS (in order), LOTUS_FEATURE_ROW[id]=line, LOTUS_FEATURE_OF[command]=id
lotus_features() {
  (( ${+LOTUS_FEATURE_IDS} )) && return
  typeset -ga LOTUS_FEATURE_IDS=()
  typeset -gA LOTUS_FEATURE_ROW=() LOTUS_FEATURE_OF=()
  local line c
  local -a f
  for line in "${(@f)$(<$LOTUS_ROOT/data/features.tsv)}"; do
    [[ $line == \#* || -z $line ]] && continue
    f=("${(@ps:\t:)line}")
    LOTUS_FEATURE_IDS+=($f[1])
    LOTUS_FEATURE_ROW[$f[1]]=$line
    for c in ${=f[3]}; do LOTUS_FEATURE_OF[$c]=$f[1]; done
  done
}

# Feature name in the interface language → REPLY
lotus_feature_label() {
  lotus_features
  local -a f=("${(@ps:\t:)LOTUS_FEATURE_ROW[$1]}")
  REPLY=${LOTUS_L[feat_$1]:-$f[2]}
}

lotus_feature_set() {   # <id> <0|1>
  local -a off=(${=LOTUS_FEATURES_OFF})
  off=(${off:#$1})
  (( $2 )) || off+=($1)
  LOTUS_FEATURES_OFF=${(j: :)${(ou)off}}
  lotus_log INFO features "$1 turned ${${(M)2:#1}:+on}${${2:#1}:+off}"
}

# ── Swift helpers ─────────────────────────────────────────────

lotus_can_swift() { xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1 }

# Builds a small Swift program once and keeps it in the cache; the name changes with the source.
#   lotus_swift_build <name> <source files…>   → REPLY = program path (status 1 when it cannot be built)
lotus_swift_build() {
  local name=$1; shift
  local sum=$(cat "$@" | cksum)
  REPLY=$LOTUS_CACHE/bin/$name-${sum%% *}
  [[ -x $REPLY ]] && return 0
  lotus_can_swift || { lotus_log WARN swift "$name: no Command Line Tools"; return 1 }
  local bin=$REPLY
  zf_mkdir -p ${bin:h}
  lotus_log INFO swift "Building $name"
  if ! xcrun swiftc -Onone -parse-as-library -swift-version 5 -o $bin.tmp "$@" >/dev/null 2>$LOTUS_CACHE/$name-build.log; then
    rm -f $bin.tmp
    lotus_log ERROR swift "$name: the Swift compiler failed, see ${LOTUS_CACHE}/$name-build.log"
    return 1
  fi
  zf_mv -f $bin.tmp $bin
  rm -f ${bin:h}/$name-^${${bin:t}#$name-}(N)    # older builds of the same program
  REPLY=$bin
}

# ── Colors ────────────────────────────────────────────────────

# Detect whether the terminal supports 24-bit color
lotus_detect_tc() {
  case $LOTUS_COLORS in
    truecolor) LOTUS_TC=1; return ;;
    256)       LOTUS_TC=0; return ;;
  esac
  if [[ $COLORTERM == (truecolor|24bit) ||
        $TERM_PROGRAM == (iTerm.app|WezTerm|ghostty|vscode|WarpTerminal|Hyper|Tabby|kitty|zed) ]]; then
    LOTUS_TC=1
  elif [[ $TERM_PROGRAM == Apple_Terminal ]]; then
    # Terminal.app supports 24-bit color from macOS 26 on
    local f=$LOTUS_CACHE/macos v
    if [[ -r $f ]]; then v=$(<$f)
    else v=$(sw_vers -productVersion 2>/dev/null); zf_mkdir -p $LOTUS_CACHE; print -r -- $v >| $f; fi
    (( ${${v%%.*}:-0} >= 26 )) && LOTUS_TC=1 || LOTUS_TC=0
  else
    LOTUS_TC=0
  fi
}

# "r;g;b" → SGR code in REPLY (truecolor or the nearest of the 256 colors)
lotus_sgr() {
  if (( LOTUS_TC )); then REPLY="38;2;$1"; return; fi
  local -a c=(${(s:;:)1})
  local -i r=$c[1] g=$c[2] b=$c[3] hi lo
  hi=$(( r > g ? (r > b ? r : b) : (g > b ? g : b) ))
  lo=$(( r < g ? (r < b ? r : b) : (g < b ? g : b) ))
  if (( hi - lo < 12 )); then
    REPLY="38;5;$(( r < 8 ? 16 : (r > 238 ? 231 : 232 + (r - 8) / 10) ))"
  else
    REPLY="38;5;$(( 16 + 36 * ((r * 5 + 127) / 255) + 6 * ((g * 5 + 127) / 255) + (b * 5 + 127) / 255 ))"
  fi
}

# Themes come from data/themes.tsv (shared with the website)
#   LOTUS_THEMES[name]="logo key accent key2 salute border dim music", LOTUS_THEME_NAMES, LOTUS_THEME_LABELS
lotus_themes() {
  (( ${+LOTUS_THEMES} )) && return
  typeset -gA LOTUS_THEMES=() LOTUS_THEME_LABELS=()
  typeset -ga LOTUS_THEME_NAMES=()
  local line
  local -a f
  for line in "${(@f)$(<$LOTUS_ROOT/data/themes.tsv)}"; do
    [[ $line == \#* ]] && continue
    f=("${(@ps:\t:)line}")
    LOTUS_THEME_NAMES+=($f[1])
    LOTUS_THEME_LABELS[$f[1]]=$f[2]
    LOTUS_THEMES[$f[1]]="${f[3,10]}"
  done
}

# Sets LOTUS_C[logo|key|accent|key2|salute|border|dim|music] as SGR codes
lotus_colors() {
  lotus_detect_tc
  lotus_themes
  typeset -gA LOTUS_C
  local -a rgb=(${=LOTUS_THEMES[$LOTUS_THEME]:-$LOTUS_THEMES[matcha]})
  local -a names=(logo key accent key2 salute border dim music)
  local i
  for i in {1..8}; do lotus_sgr $rgb[i]; LOTUS_C[$names[i]]=$REPLY; done
  (( LOTUS_TC )) && LOTUS_MODE=tc || LOTUS_MODE=256
}

# ── Text helpers ──────────────────────────────────────────────

# Percent-encoding for links → REPLY. $2 = what a space becomes (default +)
lotus_urlencode() {
  local LC_ALL=C s=$1 sp=${2:-+} out= c hex
  local -i i
  for (( i = 1; i <= ${#s}; i++ )); do
    c=${s[i]}
    case $c in
      [a-zA-Z0-9.~_-]) out+=$c ;;
      ' ')             out+=$sp ;;
      *)               printf -v hex '%%%02X' "'$c"; out+=$hex ;;
    esac
  done
  REPLY=$out
}

# ── JSON ──────────────────────────────────────────────────────

# jq ships with macOS 15 and newer; older systems get it from Homebrew
lotus_jq() {
  if (( $+commands[jq] )); then jq "$@"; return; fi
  print -u2 -- "lotus: this command needs jq on your macOS version – install it with: brew install jq"
  return 1
}

# ── Logos ─────────────────────────────────────────────────────

# Built-in logos live in logos/<name>.txt; "custom" is the user's own file
typeset -ga LOTUS_LOGOS=(lotus minimal large terminal custom none)
typeset -gA LOTUS_LOGO_LABELS=(lotus 'Lotus Classic' minimal 'Lotus Minimal' large 'Lotus Large'
  terminal 'Lotus Terminal' custom 'Custom' none 'None')

lotus_logo_file() {   # $1 logo name → REPLY = path ("" for none or missing)
  case $1 in
    none)   REPLY= ;;
    custom) REPLY=$LOTUS_CONF/logo.txt ;;
    *)      REPLY=$LOTUS_ROOT/logos/$1.txt ;;
  esac
  [[ -n $REPLY && ! -r $REPLY ]] && REPLY=
}

lotus_logo_size() {   # $1 path → reply=(width height)
  local l
  local -i w=0 h=0
  for l in "${(@f)$(<$1)}"; do (( ${#l} > w )) && w=${#l}; (( h++ )); done
  reply=($w $h)
}

# ── Generate the fastfetch config (only when something changed) ──

lotus_line() { REPLY=${${(l:$1::x:)}//x/─} }   # $1 × ─ (independent of the locale)

# Border pieces left/right of a centered title → reply=(left right)
lotus_box_parts() {
  local t=" $1 " left
  local -i nl=$(( (42 - ${#t}) / 2 ))
  lotus_line $nl; left=$REPLY
  lotus_line $(( 42 - ${#t} - nl ))
  reply=("┌$left" "$REPLY┐")
}

lotus_box() {  # $1 title, $2 title color → REPLY = top border line (fastfetch markup)
  lotus_box_parts $1
  REPLY="{#$LOTUS_C[border]}${reply[1]}{#$2} $1 {#$LOTUS_C[border]}${reply[2]}"
}

lotus_build() {
  local cfg=$LOTUS_CACHE/fastfetch-$LOTUS_MODE.jsonc np=$LOTUS_CACHE/np-$LOTUS_MODE.jsonc
  local set=$LOTUS_CONF/settings.zsh core=$LOTUS_ROOT/lib/core.zsh
  # The cache belongs to one lotus version and folder (Homebrew moves it on updates)
  local stamp=$LOTUS_CACHE/build-$LOTUS_MODE want="$LOTUS_VERSION $LOTUS_ROOT"
  [[ -z $1 && -e $cfg && -e $np && -r $stamp && $(<$stamp) == $want &&
     $cfg -nt $core && ( ! -e $set || $cfg -nt $set ) ]] && return
  zf_mkdir -p $LOTUS_CACHE

  local -A C=("${(@kv)LOTUS_C}")
  lotus_line 42
  local bottom="{ \"type\": \"custom\", \"format\": \"{#$C[border]}└${REPLY}┘\" }"
  local -a m=()
  local -i n=0   # number of info lines (to center the logo)

  if [[ $LOTUS_GREETING != off ]]; then
    m+=('{ "type": "custom", "format": "@@LOTUS_HELLO@@" }' '"break"'); n+=2
  fi
  if (( LOTUS_SHOW_HARDWARE )); then
    lotus_box Hardware $C[accent]
    m+=("{ \"type\": \"custom\", \"format\": \"$REPLY\" }"
      '{ "type": "cpu", "key": "├─ CPU", "format": "{name} ({cores-physical}C / {cores-logical}T) @ {freq-max}" }'
      '{ "type": "gpu", "key": "├─ GPU", "format": "{name} [{type}] // {core-count} Cores" }'
      '{ "type": "memory", "key": "├─ RAM", "format": "{used} / {total} {percentage-bar} {percentage}" }'
      '{ "type": "swap", "key": "├─ SWAP", "format": "{used} / {total} {percentage-bar} {percentage}" }'
      '{ "type": "disk", "key": "├─ DRIVE", "format": "{mountpoint} {size-used} / {size-total} {size-percentage-bar} {size-percentage}" }'
      $bottom '"break"'); n+=9
  fi
  if (( LOTUS_SHOW_SESSION )); then
    lotus_box Session $C[accent]
    m+=("{ \"type\": \"custom\", \"format\": \"$REPLY\" }"
      '{ "type": "users", "key": "├─ LOGIN", "myselfOnly": true, "format": "{name} // {login-time}" }'
      $bottom '"break"'); n+=4
  fi
  if (( LOTUS_SHOW_TIME )); then
    lotus_box 'Uptime / Date' $C[key2]
    m+=("{ \"type\": \"custom\", \"format\": \"$REPLY\" }"
      "{ \"type\": \"uptime\", \"key\": \"├─ UPTIME\", \"keyColor\": \"1;$C[key2]\" }"
      "{ \"type\": \"datetime\", \"key\": \"├─ DATE\", \"keyColor\": \"1;$C[key2]\", \"format\": \"{year}-{month-pretty}-{day-pretty} {hour-pretty}:{minute-pretty}:{second-pretty}\" }"
      $bottom '"break"'); n+=5
  fi
  if [[ $LOTUS_SALUTE != off ]]; then
    m+=('{ "type": "custom", "format": "@@LOTUS_SALUTE@@" }' '"break"'); n+=2
  fi
  if (( LOTUS_NP_ON )); then
    m+=('{ "type": "custom", "format": "@@LOTUS_NP1@@" }' '{ "type": "custom", "format": "@@LOTUS_NP2@@" }'); n+=2
  fi
  [[ ${m[-1]} == '"break"' ]] && { m[-1]=(); n=n-1 }

  local logo='{ "type": "none" }' file
  lotus_logo_file $LOTUS_LOGO; file=$REPLY
  if [[ -n $file && -r $file ]]; then
    local -a ll=("${(@f)$(<$file)}")
    local -i top=$(( ${#ll} >= n - 2 ? 2 : (n - ${#ll}) / 2 ))
    logo="{ \"type\": \"file\", \"source\": \"${file//\"/\\\"}\", \"color\": { \"1\": \"$C[logo]\" }, \"padding\": { \"top\": $top, \"left\": 2, \"right\": 6 } }"
  elif [[ $LOTUS_LOGO != none ]]; then
    want=incomplete   # logo file missing right now → build again next time
  fi

  local bar="\"bar\": { \"char\": { \"elapsed\": \"■\", \"total\": \"·\" }, \"border\": { \"left\": \"[\", \"right\": \"]\" }, \"color\": { \"elapsed\": \"$C[key]\", \"total\": \"$C[dim]\", \"border\": \"97\" }, \"width\": 10 }"

  print -r -- "// Generated by lotus – do not edit, use: lotus settings
{
  \"logo\": $logo,
  \"display\": {
    \"separator\": \"\",
    \"key\": { \"width\": 14 },
    \"color\": { \"keys\": \"$C[key]\", \"output\": \"97\" },
    \"percent\": { \"type\": [\"num\", \"bar\"], \"color\": { \"green\": \"97\", \"yellow\": \"97\", \"red\": \"97\" } },
    $bar,
    \"size\": { \"binaryPrefix\": \"iec\", \"ndigits\": 2 }
  },
  \"modules\": [
    ${(pj:,\n    :)m}
  ]
}" >| $cfg

  print -r -- "// Generated by lotus – the now playing lines only
{
  \"logo\": { \"type\": \"none\" },
  \"display\": { \"separator\": \"\", \"key\": { \"width\": 0 }, \"color\": { \"output\": \"97\" }, \"percent\": { \"type\": [\"num\", \"bar\"] }, $bar },
  \"modules\": [
    { \"type\": \"media\", \"key\": \"♫ \", \"keyColor\": \"1;$C[music]\", \"format\": \"{title}{?artist} {#$C[border]}—{#0}{#97} {artist}{?}\" },
    { \"type\": \"media\", \"key\": \"  \", \"format\": \"{progress-bar} {#$C[dim]}{progress}  {status}\" }
  ]
}" >| $np
  print -r -- $want >| $stamp
}

# ── Texts ─────────────────────────────────────────────────────

typeset -ga LOTUS_HELLOS=(
  Bonjour こんにちは Hello Grüezi 你好 Hola Ciao 안녕하세요
  Olá Hej नमस्ते Aloha 'Γειά σου' 'Xin chào' Allillanchu
)

lotus_hello() {
  local f=$LOTUS_CACHE/greeting
  local -i i
  case $LOTUS_GREETING in
    rotate) [[ -r $f ]] && i=$(<$f) || i=-1
            i=$(( (i + 1) % ${#LOTUS_HELLOS} )); print -r -- $i >| $f ;;
    random) i=$(( RANDOM % ${#LOTUS_HELLOS} )) ;;
    *)      REPLY=; return ;;
  esac
  REPLY=$'\e[1;97m'"${LOTUS_HELLOS[i+1]}${LOTUS_NAME:+, }"$'\e[0;'"$LOTUS_C[accent]m$LOTUS_NAME"$'\e[0m'
}

lotus_salute() {
  local s hh
  strftime -s hh %H $EPOCHSECONDS
  local -i h=$(( 10#$hh ))
  case $LOTUS_SALUTE in
    fr) if (( h < 5 )); then s='Bonne nuit!'; elif (( h < 18 )); then s='Bonjour!'; else s='Bonsoir!'; fi ;;
    de) if (( h < 5 )); then s='Gute Nacht!'; elif (( h < 11 )); then s='Guten Morgen!'
        elif (( h < 18 )); then s='Guten Tag!'; else s='Guten Abend!'; fi ;;
    en) if (( h < 5 )); then s='Good night!'; elif (( h < 12 )); then s='Good morning!'
        elif (( h < 18 )); then s='Good afternoon!'; else s='Good evening!'; fi ;;
    es) if (( h < 5 || h >= 20 )); then s='¡Buenas noches!'; elif (( h < 12 )); then s='¡Buenos días!'
        else s='¡Buenas tardes!'; fi ;;
    *)  REPLY=; return ;;
  esac
  REPLY=$'\e[1;'"$LOTUS_C[salute]m$s${LOTUS_NAME:+ $LOTUS_NAME.}"$'\e[0m'
}

# ── Now playing ───────────────────────────────────────────────

# Asks the player and writes both lines to the (shared) cache
lotus_np_query() {
  local f=$LOTUS_CACHE/np-$LOTUS_MODE-$LOTUS_LANG
  local out=$($LOTUS_FF -c $LOTUS_CACHE/np-$LOTUS_MODE.jsonc --pipe false 2>/dev/null)
  if [[ -z $out ]]; then
    out=$'\e[1;'"$LOTUS_C[music]m♫ "$'\e[0;'"$LOTUS_C[dim]m$LOTUS_L[nothing]"$'\e[0m\n  \e['"$LOTUS_C[dim]m[··········]"$'\e[0m'
  else
    out=${${${out//Playing/$LOTUS_L[playing]}//Paused/$LOTUS_L[paused]}//Stopped/$LOTUS_L[stopped]}
  fi
  print -r -- $out >| $f.$$ && zf_mv -f $f.$$ $f
}

# reply = both lines; fresh values from the cache are reused
lotus_np_get() {
  local f=$LOTUS_CACHE/np-$LOTUS_MODE-$LOTUS_LANG
  local -a st
  if ! { [[ -r $f ]] && zstat -A st +mtime $f && (( EPOCHSECONDS - st[1] < LOTUS_INTERVAL )) }; then
    lotus_np_query
  fi
  reply=("${(@f)$(<$f)}")
}

# ── Start screen ──────────────────────────────────────────────

# Optional dim line under the start screen (/settings → Diagnostics → Show startup details)
lotus_startup_details() {
  (( LOTUS_LOG_STARTUP )) || return 0
  lotus_features
  local -i on=0 ms=$(( (EPOCHREALTIME - ${_lotus_t0:-$EPOCHREALTIME}) * 1000 ))
  local id
  for id in $LOTUS_FEATURE_IDS; do lotus_feature_on $id && (( on++ )); done
  print -r -- "  "$'\e['"$LOTUS_C[dim]mlotus $LOTUS_VERSION · ${ms} ms · $on/${#LOTUS_FEATURE_IDS} ${LOTUS_L[features_word]:-features} · log: $LOTUS_LOG_LEVEL · /lotus log"$'\e[0m'
  lotus_log DEBUG startup "Start screen in ${ms} ms, $on of ${#LOTUS_FEATURE_IDS} features on"
}

# Pets (lib/cmd/pets.zsh is only loaded when there is a pet to show)
lotus_pet_start() {   # below the start screen
  (( LOTUS_PET_START )) && [[ -t 1 ]] && lotus_feature_on pets || return 0
  (( ${+functions[lotus_pet_greet]} )) || source $LOTUS_ROOT/lib/cmd/pets.zsh
  lotus_pet_greet
}
lotus_pet_react() {   # <typo|done> – a pet comments on what just happened
  (( LOTUS_PET_REACT )) && [[ -t 1 && -s $LOTUS_CONF/pets.tsv ]] && lotus_feature_on pets || return 0
  (( ${+functions[lotus_pet_react_now]} )) || source $LOTUS_ROOT/lib/cmd/pets.zsh
  lotus_pet_react_now "$@"
}

# Current cursor row in REPLY (keys typed ahead are kept)
lotus_cursor_row() {
  local state resp
  state=$(stty -g < /dev/tty 2>/dev/null) || return 1
  stty raw -echo min 0 time 10 < /dev/tty
  print -n $'\e[6n' > /dev/tty
  IFS= read -r -d R resp < /dev/tty
  stty $state < /dev/tty
  [[ $resp == *$'\e['<->';'<-> ]] || return 1
  [[ -n ${resp%%$'\e['*} ]] && print -z -- "${resp%%$'\e['*}"
  resp=${resp##*$'\e['}
  REPLY=${resp%%;*}
}

# Prints the start screen. With "live" the position of the now playing lines
# is remembered (LOTUS_NP_ROW/COL) so init.zsh can keep them updated.
lotus_render() {
  setopt localoptions extendedglob nomonitor
  LOTUS_NP_ROW=0 LOTUS_NP_IDX=0
  [[ -x $LOTUS_FF ]] || { print -u2 -- $LOTUS_L[ff_missing]; return 1 }
  lotus_build
  zf_mkdir -p $LOTUS_CACHE

  local -a args=(-c $LOTUS_CACHE/fastfetch-$LOTUS_MODE.jsonc --pipe false)
  # Window too narrow for the logo → the minimal lotus, or no logo at all
  lotus_logo_file $LOTUS_LOGO
  if [[ -n $REPLY ]]; then
    lotus_logo_size $REPLY
    if (( ${COLUMNS:-200} < reply[1] + 60 )); then
      lotus_logo_file minimal
      local small=$REPLY
      lotus_logo_size $small
      if [[ $LOTUS_LOGO != minimal ]] && (( ${COLUMNS:-200} >= reply[1] + 60 )); then
        args+=(--logo $small --logo-padding-top 4)
      else
        args+=(--logo none)
      fi
    fi
  fi

  # Fetch the song in parallel to the main run
  local -i np_pid=0
  if (( LOTUS_NP_ON )); then
    local -a st
    local f=$LOTUS_CACHE/np-$LOTUS_MODE-$LOTUS_LANG
    if ! { [[ -r $f ]] && zstat -A st +mtime $f && (( EPOCHSECONDS - st[1] < LOTUS_INTERVAL )) }; then
      lotus_np_query &
      np_pid=$!
    fi
  fi

  local out=$($LOTUS_FF $args 2>/dev/null)
  local -a lines=("${(@f)out}")
  local -i i
  (( np_pid )) && wait $np_pid

  lotus_hello;  out=${out//@@LOTUS_HELLO@@/$REPLY}
  lotus_salute; out=${out//@@LOTUS_SALUTE@@/$REPLY}
  if (( LOTUS_NP_ON )); then
    lotus_np_get
    LOTUS_NP_LAST=${(F)reply}
    for (( i = 1; i <= ${#lines}; i++ )); do
      [[ ${lines[i]} == *@@LOTUS_NP1@@* ]] || continue
      local plain=${lines[i]//$'\e['[0-9;?]#[a-zA-Z]/}
      LOTUS_NP_COL=${plain[(i)@@LOTUS_NP1@@]}
      LOTUS_NP_IDX=$i
      break
    done
    out=${out//@@LOTUS_NP1@@/$reply[1]}
    out=${out//@@LOTUS_NP2@@/$reply[2]}
  fi

  # Print without line wrapping: every line stays exactly one screen row
  print -n $'\e[?7l'
  print -r -- $out
  print -n $'\e[?7h'

  if [[ $1 == live ]] && (( LOTUS_NP_ON && LOTUS_LIVE && LOTUS_NP_IDX )) && lotus_cursor_row; then
    LOTUS_NP_ROW=$(( REPLY - ${#lines} + LOTUS_NP_IDX - 1 ))
    LOTUS_NP_CURSOR=$REPLY
    (( LOTUS_NP_ROW >= 1 )) || LOTUS_NP_ROW=0
  fi
}
