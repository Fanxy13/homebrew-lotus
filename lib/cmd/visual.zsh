# lotus – animated audio visualizer (/lotus visual)
# macOS does not hand audio levels to terminal programs, so the motion is
# simulated and follows the playback state: lively when music plays, calm otherwise.

zmodload zsh/mathfunc
source $LOTUS_ROOT/lib/cmd/audio.zsh

typeset -ga VIS_MODES=(bars wave spectrum particles minimal circular retro matrix)
typeset -gA VIS_LABELS=(bars Bars wave Wave spectrum Spectrum particles Particles minimal Minimal circular Circular retro 'Retro terminal' matrix Matrix)

lotus_cmd_visual() {
  setopt localoptions nonotify nomonitor
  if ! ui_has_tty; then ui_error "The visualizer needs a terminal window"; return 1; fi
  local -i mi=${VIS_MODES[(i)${LOTUS_VISUAL_MODE:-bars}]} W H N
  (( mi > ${#VIS_MODES} )) && mi=1
  local -F gain=1.0 energy=0.3 target=0.3 t t0=$EPOCHREALTIME last_np=-10
  local key out mode stty_saved np_line=
  local -a L P PX PY PV MY MS
  local c_logo=$'\e['"$LOTUS_C[logo]m" c_key=$'\e['"$LOTUS_C[key]m" c_acc=$'\e['"$LOTUS_C[accent]m" c_k2=$'\e['"$LOTUS_C[key2]m" c_dim=$'\e['"$LOTUS_C[dim]m" R=$'\e[0m'
  local -i dirty=1
  local E=$'\e'

  stty_saved=$(stty -g < /dev/tty)
  stty -echo -icanon < /dev/tty
  print -n $'\e[?1049h\e[?25l\e[2J'
  trap 'print -n "\e[?25h\e[?1049l"; stty $stty_saved < /dev/tty' EXIT
  trap 'return 0' INT
  TRAPWINCH() { dirty=1 }

  while :; do
    if (( dirty )); then
      W=$(( ${COLUMNS:-80} )) H=$(( ${LINES:-24} - 3 ))
      [[ -t 1 ]] && { local -a sz=(${=$(stty size < /dev/tty)}); H=$(( sz[1] - 3 )); W=$sz[2] }
      (( H < 8 )) && H=8
      N=$(( W / 3 )); L=(); P=(); PX=(); PY=(); PV=(); MY=(); MS=()
      print -n $'\e[2J'
      dirty=0
    fi
    (( t = EPOCHREALTIME - t0 ))
    mode=$VIS_MODES[mi]

    # playback state every 2 seconds (one short fastfetch call)
    if (( t - last_np > 2 )); then
      last_np=t
      if lotus_np_state && [[ -n $LOTUS_NP[title] ]]; then
        np_line="$LOTUS_NP[title]${LOTUS_NP[artist]:+ — $LOTUS_NP[artist]}"
        [[ $LOTUS_NP[status] == Playing ]] && target=1.0 || target=0.25
      else
        np_line="nothing playing"; target=0.15
      fi
    fi
    (( energy += (target - energy) * 0.08 ))

    _vis_levels
    out=$'\e[H'
    _vis_$mode
    _vis_footer
    print -rn -- $out

    read -rsk1 -t 0.066 key < /dev/tty || continue
    case $key in
      ' '|$'\t'|n) (( mi = mi % ${#VIS_MODES} + 1 )); print -n $'\e[2J'; L=(); P=(); PX=(); MY=() ;;
      +|=)         (( gain = gain < 2.0 ? gain + 0.2 : 2.0 )) ;;
      -|_)         (( gain = gain > 0.4 ? gain - 0.2 : 0.2 )) ;;
      q|Q|$'\e')   break ;;
    esac
  done
  LOTUS_VISUAL_MODE=$VIS_MODES[mi]
  lotus_save
}

# One level (0…1) per band: layered waves + a beat + a little noise, smoothed
_vis_levels() {
  local -i i n=$N
  local -F v beat
  (( beat = sin(t * 7.3) > 0.75 ? 0.35 : 0 ))
  for (( i = 1; i <= n; i++ )); do
    (( v = 0.45 + 0.3 * sin(t * (1.7 + i * 0.13) + i * 0.7) + 0.2 * sin(t * 4.1 - i * 0.31) + (RANDOM % 100) / 600.0 + beat * exp(-((i - n * 0.25) ** 2) / (n * 3.0)) ))
    (( v = v * energy * gain * (1.05 - 0.45 * i / n) ))
    (( v < 0 )) && v=0; (( v > 1 )) && v=1
    (( L[i] = ${L[i]:-0} > v ? ${L[i]:-0} * 0.82 + v * 0.18 : ${L[i]:-0} * 0.4 + v * 0.6 ))
  done
}

_vis_footer() {
  local label="${VIS_LABELS[$mode]}  ·  intensity ${(l:3:)$(( int(gain * 100) ))}%  ·  ♫ ${np_line[1,40]}"
  out+="${E}[$((H + 2));1H${E}[K  ${c_acc}${label}${R}"
  out+="${E}[$((H + 3));1H${E}[K  ${c_dim}space mode   + / - intensity   q quit   ·   motion simulated from playback${R}"
}

_vis_bars() {
  local -i r i h
  local line col
  for (( r = 1; r <= H; r++ )); do
    (( r < H / 3 )) && col=$c_logo || { (( r < 2 * H / 3 )) && col=$c_acc || col=$c_key }
    line="$col "
    for (( i = 1; i <= N; i++ )); do
      (( h = int(L[i] * H + 0.5) ))
      (( H - r < h )) && line+="██ " || line+="   "
    done
    out+="$line$R"$'\e[K\n'
  done
}

_vis_spectrum() {
  local -a blocks=(' ' ▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  local -i r i full part n=$(( W / 2 ))
  local -F lv
  local line
  for (( i = 1; i <= n; i++ )); do
    (( lv = L[(i - 1) * N / n + 1] ))
    (( P[i] = ${P[i]:-0} - 0.015 > lv ? ${P[i]:-0} - 0.015 : lv ))
  done
  for (( r = 1; r <= H; r++ )); do
    line=$c_acc
    for (( i = 1; i <= n; i++ )); do
      (( lv = L[(i - 1) * N / n + 1] * H * 8, full = int(lv / 8), part = int(lv) % 8 ))
      if (( H - r < full )); then line+="█ "
      elif (( H - r == full && part > 0 )); then line+="${blocks[part+1]} "
      elif (( H - r == int(P[i] * H) )); then line+="${c_logo}▔${c_acc} "
      else line+="  "; fi
    done
    out+="$line$R"$'\e[K\n'
  done
}

# Sparse drawing: erase the points of the last frame, draw the new ones
_vis_wave() {
  local -i x y mid=$(( H / 2 ))
  local -F a
  for (( x = 1; x <= W; x++ )); do
    [[ -n ${PY[x]} ]] && out+=$'\e['"${PY[x]};${x}H "
    (( a = sin(x * 0.09 + t * 3.1) * 0.6 + sin(x * 0.023 - t * 1.7) * 0.4 ))
    (( y = mid + int(a * (H / 2 - 1) * (0.15 + energy * gain * 0.85)) ))
    (( y < 1 )) && y=1; (( y > H )) && y=H
    PY[x]=$y
    out+=$'\e['"${y};${x}H${c_acc}•${R}"
  done
  out+=$'\e['"$((H + 1));1H"
}

_vis_particles() {
  local -i i n=70 x y
  for (( i = 1; i <= n; i++ )); do
    if [[ -z ${PX[i]} ]]; then (( PX[i] = RANDOM % W + 1, PY[i] = H + RANDOM % H, PV[i] = 0.3 + (RANDOM % 100) / 100.0 )); fi
    (( x = PX[i], y = int(PY[i]) ))
    (( y >= 1 && y <= H )) && out+=$'\e['"${y};${x}H "
    (( PY[i] -= PV[i] * (0.3 + energy * gain * 1.6) ))
    if (( PY[i] < 1 )); then (( PX[i] = RANDOM % W + 1, PY[i] = H, PV[i] = 0.3 + (RANDOM % 100) / 100.0 )); fi
    (( y = int(PY[i]) ))
    if (( y >= 1 && y <= H )); then
      (( PV[i] > 0.9 )) && out+="${E}[${y};${PX[i]}H${c_logo}•${R}" || out+="${E}[${y};${PX[i]}H${c_acc}·${R}"
    fi
  done
  out+=$'\e['"$((H + 1));1H"
}

_vis_minimal() {
  local -a blocks=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  local -i i n=$(( W / 2 > 64 ? 64 : W / 2 )) y=$(( H / 2 )) pad
  local line=
  for (( i = 1; i <= n; i++ )); do line+="${blocks[int(L[(i - 1) * N / n + 1] * 7) + 1]} "; done
  (( pad = (W - n * 2) / 2 ))
  out+="${E}[${y};1H${E}[K${(l:pad:)}${c_acc}${line}${R}"
  out+="${E}[$((y + 2));1H${E}[K${(l:pad:)}${c_dim}${np_line[1,$((n * 2))]}${R}"
}

_vis_circular() {
  local -i k n=64 x y cx=$(( W / 2 )) cy=$(( H / 2 ))
  local -F th r R0=$(( H / 2.0 - 2 ))
  for (( k = 1; k <= n; k++ )); do
    [[ -n ${PX[k]} ]] && out+=$'\e['"${PY[k]};${PX[k]}H "
    (( th = k * 6.2832 / n + t * 0.2, r = R0 * (0.45 + 0.55 * L[(k - 1) * N / n + 1]) ))
    (( x = cx + int(cos(th) * r * 2.1), y = cy + int(sin(th) * r) ))
    (( x < 1 )) && x=1; (( y < 1 )) && y=1; (( y > H )) && y=H
    PX[k]=$x PY[k]=$y
    out+=$'\e['"${y};${x}H${c_logo}●${R}"
  done
  out+="${E}[${cy};$((cx - 2))H${c_dim}lotus${R}${E}[$((H + 1));1H"
}

_vis_retro() {
  local -i ch seg segs=$(( W - 16 > 60 ? 60 : W - 16 )) lit
  local line col edge
  local -F lv
  lotus_line $(( segs + 6 )); edge=$REPLY
  out+="${E}[$((H / 2 - 3));1H${E}[K"
  out+="  ${c_k2}┌${edge}┐${R}"$'\n'
  for ch in 1 2; do
    (( lv = (L[ch] + L[N / 2] + L[N - ch]) / 3.0, lit = int(lv * segs) ))
    line="  ${c_k2}│ ${${ch/1/L}/2/R} "
    for (( seg = 1; seg <= segs; seg++ )); do
      (( seg > segs * 0.85 )) && col=$'\e[38;5;203m' || { (( seg > segs * 0.65 )) && col=$c_k2 || col=$c_key }
      (( seg <= lit )) && line+="${col}▮" || line+="${c_dim}·"
    done
    out+="$line ${c_k2}│${R}"$'\e[K\n'
  done
  out+="  ${c_k2}└${edge}┘${R}"$'\e[K\n'
  out+="    ${c_dim}-40     -20     -10     -5      0  dB${R}"$'\e[K'
}

_vis_matrix() {
  local -i c n=$(( W / 2 )) y
  local glyphs='01ｱｲｳｴｵｶｷｸｹｺ#*+=-:.'
  for (( c = 1; c <= n; c++ )); do
    [[ -z ${MY[c]} ]] && { (( MY[c] = -(RANDOM % H), MS[c] = 0.4 + (RANDOM % 100) / 100.0 )) }
    (( MY[c] += MS[c] * (0.3 + energy * gain * 1.4) ))
    (( y = int(MY[c]) ))
    (( y - 8 >= 1 && y - 8 <= H )) && out+="${E}[$((y - 8));$((c * 2))H "
    (( y - 1 >= 1 && y - 1 <= H )) && out+="${E}[$((y - 1));$((c * 2))H${c_key}${glyphs[RANDOM % ${#glyphs} + 1]}"
    (( y >= 1 && y <= H )) && out+="${E}[${y};$((c * 2))H${E}[1;97m${glyphs[RANDOM % ${#glyphs} + 1]}${R}"
    if (( y - 8 > H )); then (( MY[c] = -(RANDOM % 10), MS[c] = 0.4 + (RANDOM % 100) / 100.0 )); fi
  done
  out+=$'\e['"$((H + 1));1H"
}
