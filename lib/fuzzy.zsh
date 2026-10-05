# lotus – fuzzy matching, shared by commands, apps, Homebrew, the installer and shortcuts.

# Edit distance between two strings → REPLY
lotus_lev() {
  local a=$1 b=$2
  local -i la=${#a} lb=${#b} i j cost d ins sub
  (( la )) || { REPLY=$lb; return }
  (( lb )) || { REPLY=$la; return }
  local -a prev cur
  for (( j = 0; j <= lb; j++ )); do prev[j+1]=$j; done
  for (( i = 1; i <= la; i++ )); do
    cur=($i)
    for (( j = 1; j <= lb; j++ )); do
      [[ ${a[i]} == ${b[j]} ]] && cost=0 || cost=1
      (( d = prev[j+1] + 1, ins = cur[j] + 1, sub = prev[j] + cost ))
      (( ins < d )) && d=ins
      (( sub < d )) && d=sub
      cur[j+1]=$d
    done
    prev=("${cur[@]}")
  done
  REPLY=${prev[lb+1]}
}

# Similarity of a typed query and a candidate, 0–100 → REPLY
#   100 exact · 90+ start of the name · 75+ inside the name · below: typo distance
#   Multi-word names also match by initials ("vscode") and by single words ("firefx" → Mozilla Firefox)
lotus_score() {
  local q=${${(L)1}//[^[:alnum:]]/}
  _lotus_score1 $q $2
  local -i best=$REPLY
  (( best >= 90 )) && return
  local -a words=(${=${(L)2}//[^[:alnum:] ]/})
  if (( ${#words} > 1 )); then
    local ini=${(j::)${(M)words#?}} w
    [[ $q == $ini* ]] && (( ${#ini} >= 2 && best < 80 )) && best=80
    for w in $words; do
      (( ${#w} < 3 )) && continue
      _lotus_score1 $q $w
      (( REPLY - 6 > best )) && (( best = REPLY - 6 ))
    done
  fi
  REPLY=$best
}

_lotus_score1() {   # <normalized query> <candidate>
  local q=$1 c=${${(L)2}//[^[:alnum:]]/}
  if [[ -z $q || -z $c ]]; then REPLY=0; return; fi
  if [[ $q == $c ]]; then REPLY=100; return; fi
  if [[ $c == $q* ]]; then REPLY=$(( 90 + 9 * ${#q} / ${#c} )); return; fi
  if [[ $c == *$q* ]]; then REPLY=$(( 75 + 10 * ${#q} / ${#c} )); return; fi
  local -i m best
  lotus_lev $q $c
  (( m = ${#q} > ${#c} ? ${#q} : ${#c} ))
  (( best = (m - REPLY) * 80 / m ))
  # a typo in the first letters of a longer name ("visul" → "visual studio code")
  if (( ${#c} > ${#q} + 2 && ${#q} >= 3 )); then
    lotus_lev $q ${c[1,${#q}]}
    (( REPLY = (${#q} - REPLY) * 72 / ${#q} ))
    (( REPLY > best )) && best=REPLY
  fi
  REPLY=$best
}

# Rank candidates → reply=(best first), LOTUS_SCORES=(their scores)
#   lotus_rank <query> <minimum score> <candidate>…
lotus_rank() {
  setopt localoptions extendedglob
  local q=$1 c
  local -i min=$2
  shift 2
  local -a scored
  for c in "$@"; do
    lotus_score $q $c
    (( REPLY >= min )) && scored+=("${(l:3::0:)REPLY}"$'\t'"$c")
  done
  scored=(${(On)scored})
  typeset -ga LOTUS_SCORES=(${${scored%%$'\t'*}##0#})
  reply=(${scored#*$'\t'})
}

# Decide what the user meant. Exact or clearly unique → no question.
# Typos → "Did you mean …?". Several close names → short list.
#   lotus_pick <query> <what, e.g. "app"> <candidate>…   → REPLY = choice, status 1 = none/cancelled
lotus_pick() {
  local q=$1 what=$2
  shift 2
  lotus_rank $q 55 "$@"
  local -a found=("${reply[@]}") scores=("${LOTUS_SCORES[@]}")
  (( ${#found} )) || return 1
  local -i top=${scores[1]} second=${scores[2]:-0}
  if (( top == 100 || (top >= 90 && top - second >= 8) )); then
    REPLY=${found[1]}; return 0
  fi
  if (( top >= 60 && top - second >= 12 )) || (( ${#found} == 1 )); then
    ui_confirm "Did you mean \"${found[1]}\"?" y || return 1
    REPLY=${found[1]}; return 0
  fi
  ui_choose "Which $what did you mean?" "${(@)found[1,6]}" || return 1
  REPLY=${found[REPLY]}
}
