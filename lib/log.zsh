# lotus – one log for everything: the zsh commands, the background remover and the AI terminal.
#   lotus_log <LEVEL> <component> <message…>      levels: ERROR WARN INFO DEBUG TRACE
# One line per entry, tab separated:  2026-10-07 09:31:04.123  INFO  bg  Model loaded
# Keys and tokens are masked and the home folder becomes ~ before anything is written.
# Writing never fails loudly: without a writable log folder (e.g. inside Homebrew's sandbox) it is skipped.

typeset -g LOTUS_STATE=${XDG_STATE_HOME:-$HOME/.local/state}/lotus
typeset -g LOTUS_LOG=$LOTUS_STATE/lotus.log
typeset -gA LOTUS_LOG_RANK=(off 0 error 1 warn 2 info 3 debug 4 trace 5)
typeset -ga LOTUS_LOG_LEVELS=(off warn info debug trace)   # the choices in /settings
typeset -gi _lotus_log_max=-1 _lotus_log_ready=0
typeset -gi LOTUS_LOG_SIZE=1048576   # rotate at 1 MB, keep 3 older files

# Highest level that gets written (LOTUS_VERBOSE=1 raises it to debug and mirrors lines to stderr)
lotus_log_setup() {
  _lotus_log_max=${LOTUS_LOG_RANK[${LOTUS_LOG_LEVEL:-info}]:-3}
  (( LOTUS_VERBOSE && _lotus_log_max < 4 )) && _lotus_log_max=4
}

# Would a line at this level be written?  lotus_log_on DEBUG
lotus_log_on() {
  (( _lotus_log_max >= 0 )) || lotus_log_setup
  (( ${LOTUS_LOG_RANK[${(L)1}]:-3} <= _lotus_log_max ))
}

# Masks secrets and shortens paths → REPLY
lotus_log_clean() {
  setopt localoptions extendedglob
  local m=$1
  m=${m//$'\n'/\\n}; m=${m//$'\t'/ }; m=${m//$'\r'/}
  [[ -n $HOME && $HOME != / ]] && m=${m//$HOME/\~}
  m=${m//(#b)(sk-(ant-|proj-|))[[:alnum:]_-](#c12,)/${match[1]}•••}
  m=${m//(#b)((#i)bearer )[^[:space:]]##/${match[1]}•••}
  m=${m//(#b)((#i)(api[_-]#key|token|secret|password|passwd|authorization)[\"\']#[[:space:]]#[=:][[:space:]]#)[^[:space:],;]##/${match[1]}•••}
  REPLY=$m
}

lotus_log() {
  local level=${(U)1} comp=$2
  shift 2
  lotus_log_on $level || return 0
  (( _lotus_log_ready )) || lotus_log_open || return 0
  lotus_log_clean "$*"
  local -F now=$EPOCHREALTIME
  local ts frac=${now#*.}000
  strftime -s ts '%Y-%m-%d %H:%M:%S' ${now%.*}
  local line="$ts.${frac[1,3]}"$'\t'"$level"$'\t'"$comp"$'\t'"$REPLY"
  { print -r -- $line >> $LOTUS_LOG } 2>/dev/null
  (( LOTUS_VERBOSE )) && print -r -- $'\e[2m'"${ts#* } ${(r:5:)level} ${comp}: $REPLY"$'\e[0m' >&2
  return 0
}

# Creates the folder and does the upkeep (size rotation, retention) – once per process
lotus_log_open() {
  { zf_mkdir -p $LOTUS_STATE && chmod 700 $LOTUS_STATE } 2>/dev/null || return 1
  _lotus_log_ready=1
  local -a st
  zstat -A st +size $LOTUS_LOG 2>/dev/null && (( st[1] > LOTUS_LOG_SIZE )) && lotus_log_rotate
  # Old rotated files go after the retention time (checked once a day)
  local stamp=$LOTUS_STATE/.upkeep today
  strftime -s today %Y-%m-%d $EPOCHSECONDS
  [[ -r $stamp && $(<$stamp) == $today ]] && return 0
  print -r -- $today >| $stamp 2>/dev/null
  local -i days=${LOTUS_LOG_RETENTION:-7} f_age
  local f
  for f in $LOTUS_LOG.<1-9>(N); do
    zstat -A st +mtime $f 2>/dev/null || continue
    (( f_age = (EPOCHSECONDS - st[1]) / 86400 ))
    (( f_age >= days )) && rm -f $f
  done
  lotus_log_trim $days
  return 0
}

lotus_log_rotate() {
  local -i i
  rm -f $LOTUS_LOG.3
  for (( i = 2; i >= 1; i-- )); do
    [[ -e $LOTUS_LOG.$i ]] && zf_mv -f $LOTUS_LOG.$i $LOTUS_LOG.$(( i + 1 ))
  done
  zf_mv -f $LOTUS_LOG $LOTUS_LOG.1 2>/dev/null
}

# Drops entries older than <days> from the current file
lotus_log_trim() {
  [[ -s $LOTUS_LOG ]] || return 0
  local first cutoff
  IFS= read -r first < $LOTUS_LOG
  strftime -s cutoff %Y-%m-%d $(( EPOCHSECONDS - $1 * 86400 ))
  [[ ${first[1,10]} < $cutoff ]] || return 0
  local -a keep=()
  local l
  for l in "${(@f)$(<$LOTUS_LOG)}"; do [[ ${l[1,10]} < $cutoff ]] || keep+=("$l"); done
  { if (( ${#keep} )); then print -rl -- $keep; fi } >| $LOTUS_LOG.tmp 2>/dev/null && zf_mv -f $LOTUS_LOG.tmp $LOTUS_LOG
}
