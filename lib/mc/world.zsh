# lotus – the little Minecraft world on the control center's stats page (lib/mc/control.zsh).
# A side view that drifts by: hills of grass, dirt and stone with ores above the bedrock, oak trees
# and flowers, water with lily pads and lotus flowers, blocky clouds, and the square sun and moon of
# a day that lasts two minutes, with stars at night. A little figure walks for every player online,
# a creeper waits when nobody is. While the server is stopped, the world stands still.
# Two pixels per character (half blocks), every color made from the theme's eight.
#   _mcw_frame <columns> <rows> <players> <moving 0|1>  → reply = the lines

zmodload zsh/mathfunc zsh/datetime

typeset -ga MCW_COL MCW_SURF MCW_CLOUD MCW_STARS
typeset -gA MCW_FG MCW_BG MCW_CP
typeset -gi MCW_BASE=0 MCW_CBASE=0 MCW_H=0 MCW_SEA=0 MCW_CLEFT=0 MCW_CGAP=4 MCW_CLEN=0 MCW_CY=2 MCW_CPOS=0
typeset -gF MCW_T=0 MCW_LAST=0
typeset -g MCW_THEME= MCW_STARKEY=

# A theme color made darker or lighter: <r;g;b> <percent> → REPLY
_mcw_scale() {
  local -a c=(${(s:;:)1})
  local -i r=$(( c[1] * $2 / 100 )) g=$(( c[2] * $2 / 100 )) b=$(( c[3] * $2 / 100 ))
  REPLY="$(( r > 255 ? 255 : r ));$(( g > 255 ? 255 : g ));$(( b > 255 ? 255 : b ))"
}
# Two colors mixed: <r;g;b> <r;g;b> <percent of the second> → REPLY
_mcw_mix() {
  local -a a=(${(s:;:)1}) b=(${(s:;:)2})
  local -i p=$3
  REPLY="$(( (a[1] * (100 - p) + b[1] * p) / 100 ));$(( (a[2] * (100 - p) + b[2] * p) / 100 ));$(( (a[3] * (100 - p) + b[3] * p) / 100 ))"
}

# One letter per kind of pixel; the colors come from the theme, once per theme and color mode
_mcw_palette() {
  [[ $MCW_THEME == "$LOTUS_THEME $LOTUS_MODE" ]] && return
  MCW_THEME="$LOTUS_THEME $LOTUS_MODE"
  local -a th=(${=LOTUS_THEMES[$LOTUS_THEME]:-$LOTUS_THEMES[matcha]})
  local logo=$th[1] key=$th[2] accent=$th[3] key2=$th[4] salute=$th[5] border=$th[6] dim=$th[7] music=$th[8]
  local white='255;255;255' k
  local -A rgb
  _mcw_mix $dim $white 30;      rgb[.]=$REPLY          # stars
  _mcw_mix $salute $white 40;   rgb[:]=$REPLY
  _mcw_mix $dim $white 72;      rgb[c]=$REPLY          # clouds, their shade below
  _mcw_mix $dim $white 48;      rgb[C]=$REPLY
  rgb[U]=$salute;                                      # the sun, its bright middle
  _mcw_mix $salute $white 55;   rgb[u]=$REPLY
  _mcw_mix $dim $white 78;      rgb[M]=$REPLY          # the moon and its craters
  _mcw_mix $dim $white 45;      rgb[m]=$REPLY
  rgb[g]=$key;                                         # grass, a darker blade here and there
  _mcw_scale $key 80;           rgb[q]=$REPLY
  _mcw_scale $key2 50;          rgb[d]=$REPLY          # dirt
  _mcw_scale $key2 40;          rgb[e]=$REPLY
  _mcw_mix $key2 $white 25;     rgb[a]=$REPLY          # sand
  _mcw_scale $dim 72;           rgb[x]=$REPLY          # stone
  _mcw_scale $dim 58;           rgb[y]=$REPLY
  rgb[o]=$accent; rgb[r]=$logo; rgb[n]=$salute         # ores
  _mcw_scale $dim 30;           rgb[b]=$REPLY          # bedrock
  # water: the theme's accent with enough blue in it that it still reads as water
  _mcw_mix $accent '50;110;225' 55; local water=$REPLY
  _mcw_scale $water 70;         rgb[w]=$REPLY          # water, its surface
  _mcw_scale $water 95;         rgb[W]=$REPLY
  _mcw_scale $key2 52;          rgb[T]=$REPLY          # oak trunk and leaves
  _mcw_scale $key 62;           rgb[L]=$REPLY
  _mcw_scale $key 84;           rgb[l]=$REPLY
  rgb[f]=$logo; rgb[F]=$salute                         # flowers
  rgb[p]=$logo                                         # the lotus, its middle, the lily pad
  _mcw_mix $logo $white 50;     rgb[P]=$REPLY
  _mcw_scale $key 55;           rgb[k]=$REPLY
  _mcw_mix $salute $white 35;   rgb[H]=$REPLY          # players: head, shirt (four kinds), trousers
  rgb[1]=$accent; rgb[2]=$logo; rgb[3]=$key2; rgb[4]=$music
  _mcw_scale $border 70;        rgb[K]=$REPLY
  _mcw_scale $key 92;           rgb[E]=$REPLY          # the creeper and its face
  _mcw_scale $key 28;           rgb[N]=$REPLY
  MCW_FG=() MCW_BG=()
  for k in ${(k)rgb}; do
    lotus_sgr $rgb[$k]
    MCW_FG[$k]=$REPLY MCW_BG[$k]=48${REPLY#38}
  done
}

# Height of the ground at a column: smooth hills through a random point every 12 columns,
# with a step of one pixel now and then → REPLY (the pixel row of the surface, 1 = top)
_mcw_height() {
  local -i x=$1 k=$(( $1 / 12 )) H=$MCW_H
  local -i lo=$(( H * 40 / 100 )) hi=$(( H * 82 / 100 )) j
  for j in $k $(( k + 1 )); do
    [[ -n ${MCW_CP[$j]} ]] && continue
    # now and then a valley under the sea level, so there is water
    if (( RANDOM % 4 == 0 )); then MCW_CP[$j]=$(( MCW_SEA + 2 + RANDOM % 4 ))
    else MCW_CP[$j]=$(( lo + RANDOM % (MCW_SEA - lo) )); fi
    (( MCW_CP[$j] > hi )) && MCW_CP[$j]=$hi
  done
  local -F t=$(( (x % 12) / 12.0 )) s
  (( s = t * t * (3 - 2 * t) ))
  REPLY=$(( int(MCW_CP[$k] + (MCW_CP[$(( k + 1 ))] - MCW_CP[$k]) * s + 0.5) ))
}

# 16 more columns of ground, then trees, flowers and lotus flowers on them
_mcw_more() {
  local -i n=${#MCW_COL} i y x surf H=$MCW_H sea=$MCW_SEA
  local col ch
  for (( i = 1; i <= 16; i++ )); do
    (( x = MCW_BASE + n + i ))
    _mcw_height $x; surf=$REPLY
    col=
    for (( y = 1; y <= H; y++ )); do
      if (( y == H )); then ch=b
      elif (( y < surf )); then
        if (( y > sea )); then ch=w; elif (( y == sea && surf > sea )); then ch=W; else ch=' '; fi
      elif (( y == surf )); then
        (( surf > sea )) && ch=a || { (( RANDOM % 5 )) && ch=g || ch=q }
      elif (( y <= surf + 2 )); then
        (( surf > sea )) && ch=a || { (( RANDOM % 4 )) && ch=d || ch=e }
      elif (( y == H - 1 && RANDOM % 2 )); then ch=b
      else
        case $(( RANDOM % 100 )) in
          0) ch=o ;; 1) ch=r ;; 2) ch=n ;; <3-16>) ch=y ;; *) ch=x ;;
        esac
      fi
      col+=$ch
    done
    MCW_COL+=("$col")
    MCW_SURF+=($surf)
  done
  # features, only where all their columns are in this chunk
  local -i ci th top
  for (( i = n + 3; i <= n + 14; i++ )); do
    surf=$MCW_SURF[i]
    if (( surf < sea && surf == MCW_SURF[i-1] && surf == MCW_SURF[i+1] && RANDOM % 7 == 0 )) && [[ ${MCW_COL[i-1]}${MCW_COL[i-2]} != *T* ]]; then
      # an oak: trunk, then a wide crown and a narrow one on top
      (( th = 3 + RANDOM % 2, top = surf - th ))
      (( top > 4 )) || continue
      for (( y = surf - 1; y >= top; y-- )); do _mcw_setc $(( i )) $(( y )) T; done
      for (( ci = i - 2; ci <= i + 2; ci++ )); do
        for y in $(( top )) $(( top + 1 )); do
          [[ ${MCW_COL[ci][y]} == ' ' ]] && { (( (ci + y) % 3 )) && _mcw_setc $(( ci )) $(( y )) L || _mcw_setc $(( ci )) $(( y )) l }
        done
      done
      for (( ci = i - 1; ci <= i + 1; ci++ )); do
        for y in $(( top - 1 )) $(( top - 2 )); do
          [[ ${MCW_COL[ci][y]} == ' ' ]] && { (( (ci + y) % 2 )) && _mcw_setc $(( ci )) $(( y )) l || _mcw_setc $(( ci )) $(( y )) L }
        done
      done
      (( i += 3 ))
    elif (( surf < sea && RANDOM % 9 == 0 )) && [[ ${MCW_COL[i][surf-1]} == ' ' ]]; then
      (( RANDOM % 2 )) && _mcw_setc $(( i )) $(( surf-1 )) f || _mcw_setc $(( i )) $(( surf-1 )) F
    elif (( surf > sea + 1 && MCW_SURF[i-1] > sea && MCW_SURF[i+1] > sea && RANDOM % 6 == 0 )); then
      # a lotus on its lily pad
      _mcw_setc $(( i-1 )) $(( sea )) k; _mcw_setc $(( i )) $(( sea )) k; _mcw_setc $(( i+1 )) $(( sea )) k
      _mcw_setc $(( i-1 )) $(( sea-1 )) p; _mcw_setc $(( i )) $(( sea-1 )) P; _mcw_setc $(( i+1 )) $(( sea-1 )) p
      _mcw_setc $(( i )) $(( sea-2 )) p
      (( i += 2 ))
    fi
  done
}

# The cloud layer: blocky clouds of two rows with gaps between them, one column → REPLY
# (a string for the rows 1 to 6, spaces where there is no cloud)
_mcw_cloud_col() {
  if (( MCW_CLEFT <= 0 )); then
    if (( MCW_CGAP > 0 )); then (( MCW_CGAP-- )); REPLY='      '; return; fi
    (( MCW_CLEN = MCW_CLEFT = 7 + RANDOM % 11, MCW_CY = 2 + RANDOM % 3, MCW_CGAP = 6 + RANDOM % 22, MCW_CPOS = 0 ))
  fi
  (( MCW_CLEFT--, MCW_CPOS++ ))
  local col='      '
  col[MCW_CY+1]=C
  (( MCW_CPOS > 2 && MCW_CPOS <= MCW_CLEN - 2 )) && col[MCW_CY]=c
  REPLY=$col
}

# A new world for a new height
_mcw_reset() {
  MCW_H=$1 MCW_COL=() MCW_SURF=() MCW_CLOUD=() MCW_CP=() MCW_BASE=0 MCW_CBASE=0 MCW_CLEFT=0 MCW_CGAP=3
  (( MCW_SEA = MCW_H * 64 / 100 ))
  MCW_STARKEY=
}

_mcw_frame() {
  local -i W=$1 R=$2 P=$3 moving=$4
  local -i H=$(( R * 2 ))
  (( W > 0 && R > 0 )) || { reply=(); return }
  (( H != MCW_H )) && _mcw_reset $H
  _mcw_palette
  # the world's own time: it runs while the server does
  local -F now=$EPOCHREALTIME
  (( MCW_LAST > 0 && moving )) && (( MCW_T += now - MCW_LAST > 1 ? 0.2 : now - MCW_LAST ))
  MCW_LAST=$now
  local -i scroll=$(( int(MCW_T * 2.6) )) cscroll=$(( int(MCW_T * 1.3) ))
  while (( ${#MCW_COL} < scroll - MCW_BASE + W + 2 )); do _mcw_more; done
  # forget what has drifted out on the left
  local -i drop=$(( scroll - MCW_BASE - 4 ))
  if (( drop > 32 )); then
    MCW_COL[1,drop]=() MCW_SURF[1,drop]=()
    (( MCW_BASE += drop ))
  fi
  while (( ${#MCW_CLOUD} < cscroll - MCW_CBASE + W + 2 )); do _mcw_cloud_col; MCW_CLOUD+=("$REPLY"); done
  (( drop = cscroll - MCW_CBASE - 4 ))
  if (( drop > 32 )); then
    MCW_CLOUD[1,drop]=()
    (( MCW_CBASE += drop ))
  fi

  # stars sit still in the sky, a new set for every window size
  local -i i y x
  if [[ $MCW_STARKEY != $W,$H ]]; then
    MCW_STARKEY=$W,$H MCW_STARS=()
    for (( i = 0; i < W / 4; i++ )); do MCW_STARS+=("$(( RANDOM % W + 1 )) $(( RANDOM % (MCW_SEA - 3) + 1 ))"); done
  fi

  # the day: 120 seconds, the sun for the first 70, the moon for the rest
  local -F ph=$(( (MCW_T + 20) % 120 / 120.0 )) arc
  local -i night=0 bx by
  local body=U core=u
  if (( ph < 0.58 )); then (( arc = ph / 0.58 ))
  else (( arc = (ph - 0.58) / 0.42, night = 1 )); body=M core=m; fi
  (( bx = int(arc * (W + 4)) - 3, by = int(2 + (MCW_SEA * 0.45) * (1 - sin(arc * 3.14159))) ))

  local -a cols
  local col cl
  local -i off=$(( scroll - MCW_BASE ))
  for (( i = 1; i <= W; i++ )); do
    col=${MCW_COL[off+i]}
    cl=${MCW_CLOUD[cscroll-MCW_CBASE+i]}
    for (( y = 1; y <= 6; y++ )); do
      [[ ${cl[y]} != ' ' && ${col[y]} == ' ' ]] && col[y]=${cl[y]}
    done
    # sun or moon, behind the clouds
    if (( i >= bx && i < bx + 4 )); then
      for (( y = by; y < by + 4 && y <= H; y++ )); do
        [[ ${col[y]} == ' ' ]] || continue
        if (( (i == bx + 1 || i == bx + 2) && (y == by + 1 || y == by + 2) )); then
          (( night )) && { (( i == bx + 1 && y == by + 1 )) && col[y]=m || col[y]=M } || col[y]=$core
        else col[y]=$body; fi
      done
    fi
    cols[i]=$col
  done
  if (( night )); then
    local s
    local -i k=0
    for s in $MCW_STARS; do
      (( x = ${s%% *}, y = ${s##* }, k++ ))
      [[ ${cols[x][y]} == ' ' ]] || continue
      # twinkling: a few are bright, a few gone, changing every second
      case $(( (k * 7 + int(MCW_T)) % 9 )) in 0) _mcw_setf $x $y : ;; 1) ;; *) _mcw_setf $x $y . ;; esac
    done
  fi

  # players, or a creeper when nobody is online
  local -i fx fy step=$(( int(MCW_T * 4) % 2 )) n=$(( P > 4 ? 4 : P ))
  local -a spots=(42 58 27 72)
  if (( n == 0 )); then
    (( fx = W * 66 / 100 ))
    _mcw_ground $off $fx; fy=$REPLY
    _mcw_put $fx $(( fy - 4 )) EE; _mcw_put $fx $(( fy - 3 )) NN
    _mcw_put $fx $(( fy - 2 )) EE; _mcw_put $fx $(( fy - 1 )) EE
  else
    for (( k = 1; k <= n; k++ )); do
      (( fx = W * spots[k] / 100 ))
      _mcw_ground $off $fx; fy=$REPLY
      _mcw_put $fx $(( fy - 4 )) HH
      _mcw_put $fx $(( fy - 3 )) $k$k
      _mcw_put $fx $(( fy - 2 )) KK
      (( (step + k) % 2 )) && _mcw_put $fx $(( fy - 1 )) 'K ' || _mcw_put $fx $(( fy - 1 )) ' K'
    done
  fi

  _mcw_paint $R
}

# Where a figure stands at screen column <x>: on the ground, or swimming on the water → REPLY
_mcw_ground() {
  local -i s1=${MCW_SURF[$1+$2]:-$MCW_SEA} s2=${MCW_SURF[$1+$2+1]:-$MCW_SEA}
  local -i s=$(( s1 < s2 ? s1 : s2 ))
  (( s > MCW_SEA )) && s=$(( MCW_SEA + 1 ))
  REPLY=$s
}

# The pixel columns in the array cols (one string per column, top to bottom) as lines → reply.
# Half blocks: the top pixel as background, the bottom one as ▄ (Terminal.app draws ▄ with a thin
# gap above it that then shows the right color); ▀ where only the top one is there.
_mcw_paint() {
  local -i R=$1 W=${#cols} y i
  local t b fg bg want_fg want_bg line ch
  local e=$'\e['
  reply=()
  for (( y = 1; y <= R; y++ )); do
    line= fg= bg=
    for (( i = 1; i <= W; i++ )); do
      t=${cols[i][2*y-1]} b=${cols[i][2*y]}
      [[ -z $t ]] && t=' '
      [[ -z $b ]] && b=' '
      if [[ $t == ' ' ]]; then
        if [[ $b == ' ' ]]; then
          [[ -n $bg ]] && { line+="${e}49m"; bg= }
          line+=' '; continue
        fi
        want_fg=${MCW_FG[$b]} want_bg= ch=▄
      elif [[ $b == ' ' ]]; then
        want_fg=${MCW_FG[$t]} want_bg= ch=▀
      else
        want_fg=${MCW_FG[$b]} want_bg=${MCW_BG[$t]} ch=▄
      fi
      if [[ $want_bg != $bg ]]; then line+="${e}${want_bg:-49}m"; bg=$want_bg; fi
      if [[ $want_fg != $fg ]]; then line+="${e}${want_fg}m"; fg=$want_fg; fi
      line+=$ch
    done
    reply+=("$line${e}0m")
  done
}

# The server icon when there is none yet: a grass block, 12 × 12 pixels → reply (6 lines)
_mcw_icon() {
  _mcw_palette
  local -a rows=(
    'gggqgggggqgg' 'ggggggqggggg' 'gqgggggggqgg' 'dgdgqgdggdgd' 'dddgdddgddde' 'ddeddddddedd'
    'ddddddeddddd' 'deddddddddde' 'dddddeddeddd' 'ddedddddddde' 'dddddddeddd ' 'eddeddddddd ')
  rows[11]='dddddddedddd' rows[12]='eddedddddddd'
  local -a cols=()
  local -i x y
  for (( x = 1; x <= 12; x++ )); do
    cols[x]=
    for (( y = 1; y <= 12; y++ )); do cols[x]+=${rows[y][x]}; done
  done
  _mcw_paint 6
}

# One pixel of the world, or of the frame being drawn: <column> <row> <letter>
_mcw_setc() { local c=${MCW_COL[$1]}; c[$2]=$3; MCW_COL[$1]=$c }
_mcw_setf() { local c=${cols[$1]}; c[$2]=$3; cols[$1]=$c }

# Two pixels side by side into the frame (a space keeps what is there): <x> <y> <two letters>
_mcw_put() {
  local -i x=$1 y=$2
  (( y >= 1 )) || return 0
  [[ ${3[1]} != ' ' ]] && (( x >= 1 && x <= ${#cols} )) && _mcw_setf $x $y ${3[1]}
  [[ ${3[2]} != ' ' ]] && (( x + 1 <= ${#cols} )) && _mcw_setf $(( x + 1 )) $y ${3[2]}
  return 0
}
