#!/usr/bin/env zsh
# The contract between the two engines: what the zsh engine makes of the cases in tests/contract/cases.
#   zsh tests/contract/zsh.zsh <out folder>
# tests/contract/expected holds its answers. tests/test-contract.zsh checks that they are still what zsh makes;
# win/tests/Contract.Tests.ps1 checks that Lotus for Windows (PowerShell) makes the same – on Windows, Linux and macOS.
# Generate them again after a change of the zsh engine:  zsh tests/contract/zsh.zsh tests/contract/expected
emulate -L zsh
setopt extendedglob
local root=${0:A:h:h:h} out=${1:?the folder for the answers}
mkdir -p $out/fastfetch
local home=$(mktemp -d "${TMPDIR:-/tmp}/lotus-contract.XXXXXX")
export HOME=$home XDG_CONFIG_HOME= XDG_CACHE_HOME= XDG_STATE_HOME= XDG_DATA_HOME= LOTUS_ROOT=$root LC_ALL=C.UTF-8 USER=ada
unset COLORTERM TERM_PROGRAM WT_SESSION KONSOLE_VERSION KITTY_WINDOW_ID ALACRITTY_LOG VTE_VERSION
export TERM=xterm-256color
source $root/lib/core.zsh
source $root/lib/fuzzy.zsh
local cases=$root/tests/contract/cases line
local -a f

# 1. colors: 24-bit and the nearest of the 256
for line in "${(@f)$(<$cases/sgr.txt)}"; do
  [[ $line == \#* || -z $line ]] && continue
  LOTUS_TC=1; lotus_sgr $line; local tc=$REPLY
  LOTUS_TC=0; lotus_sgr $line
  print -r -- "$line"$'\t'"$tc"$'\t'"$REPLY"
done >| $out/sgr.tsv

# 2. fuzzy scores and rankings
for line in "${(@f)$(<$cases/fuzzy.txt)}"; do
  [[ $line == \#* ]] && continue
  f=("${(@ps:\t:)line}")
  lotus_score "$f[1]" "$f[2]"
  print -r -- "$f[1]"$'\t'"$f[2]"$'\t'"$REPLY"
done >| $out/fuzzy.tsv
for line in "${(@f)$(<$cases/rank.txt)}"; do
  [[ $line == \#* || -z $line ]] && continue
  f=("${(@ps:\t:)line}")
  local -a cands=("${(@s:|:)f[3]}") pairs=()
  lotus_rank "$f[1]" $f[2] $cands
  local -i i
  for (( i = 1; i <= ${#reply}; i++ )); do lotus_score "$f[1]" "$reply[i]"; pairs+=("$reply[i]:$REPLY"); done
  print -r -- "$f[1]"$'\t'"$f[2]"$'\t'"${(j:|:)pairs}"
done >| $out/rank.tsv

# 3. settings: read, migrated (the file as the migration leaves it), then saved with the corrected values
mkdir -p $home/.config/lotus
cp $cases/settings.zsh $home/.config/lotus/settings.zsh
lotus_load
cp $home/.config/lotus/settings.zsh $out/settings-migrated.zsh
lotus_save quiet
cp $home/.config/lotus/settings.zsh $out/settings-saved.zsh

# 4. the language files, as data: number of texts and a digest of key=value, sorted by key
local lf k dump
for lf in $root/lib/lang/*.zsh(N); do
  typeset -A LOTUS_L=()
  source $lf
  dump=
  for k in ${(ko)LOTUS_L}; do dump+="$k"$'\x1f'"${LOTUS_L[$k]}"$'\x1e'; done
  print -rn -- "$dump" | lotus_os_sha256_stdin
  print -r -- "${lf:t}"$'\t'"${#LOTUS_L}"$'\t'"$REPLY"
done >| $out/lang.tsv

# 5. the logos as painted: each logo in two themes, both color modes, gradient or one color, theme or own colors
local colors theme fade own logo
for colors in truecolor 256; do for theme in matcha ocean; do for fade in 1 0; do for own in 1 0; do
  for logo in lotus minimal large terminal apple earth; do
    LOTUS_COLORS=$colors LOTUS_THEME=$theme LOTUS_LOGO_FADE=$fade LOTUS_LOGO_THEME=$own
    lotus_colors
    lotus_logo_paint $logo || continue
    lotus_os_sha256 $REPLY
    print -r -- "$colors-$theme-$fade-$own-$logo"$'\t'"$reply"$'\t'"$REPLY"
  done
done; done; done; done >| $out/art.tsv

# 6. the fastfetch configs of the start screen, for a few kinds of settings
_ff_case() {   # <name> <assignments…>
  local name=$1; shift
  lotus_defaults; LOTUS_NAME=Ada
  local a; for a in "$@"; do typeset -g "$a"; done
  lotus_colors
  (( LOTUS_SHOW_MUSIC )) && lotus_feature_on music && LOTUS_NP_ON=1 || LOTUS_NP_ON=0
  lotus_build force
  cp $LOTUS_CACHE/fastfetch-$LOTUS_MODE.jsonc $out/fastfetch/$name.jsonc
  cp $LOTUS_CACHE/fastfetch-$LOTUS_MODE.jsonc.lines $out/fastfetch/$name.lines
  cp $LOTUS_CACHE/np-$LOTUS_MODE.jsonc $out/fastfetch/$name.np.jsonc
}
_ff_case default LOTUS_COLORS=truecolor
_ff_case mono-256 LOTUS_COLORS=256 LOTUS_THEME=mono
_ff_case quiet LOTUS_COLORS=truecolor LOTUS_THEME=neon LOTUS_GREETING=off LOTUS_SALUTE=de LOTUS_SHOW_SESSION=0
_ff_case bare LOTUS_COLORS=256 LOTUS_SHOW_HARDWARE=0 LOTUS_SHOW_TIME=0 LOTUS_FEATURES_OFF=music

# 7. the greeting and the line at the bottom (a fixed hour; the rotation starts again from a new cache)
lotus_defaults; LOTUS_NAME=Ada LOTUS_COLORS=truecolor; lotus_colors
rm -f $LOTUS_CACHE/greeting
{
  local -i n
  for (( n = 1; n <= 16; n++ )); do lotus_hello; print -r -- "hello	$REPLY"; done
  for LOTUS_SALUTE in fr de en es off; do
    local h
    for h in 3 9 11 15 19 21; do
      strftime() { if [[ $1 == -s ]]; then typeset -g "$2=$h"; fi }
      lotus_salute; print -r -- "salute-$LOTUS_SALUTE-$h	$REPLY"
      unfunction strftime
    done
  done
} >| $out/texts.tsv
rm -rf -- "${home:?}"
