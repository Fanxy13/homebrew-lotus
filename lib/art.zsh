# lotus – the art left of the start screen: the logo, or the album cover while a song plays.
#
#   Logo   logos/*.txt hold shapes only. Lotus paints them into the cache: in the theme's logo
#          color, or in their own colors (/settings → Logo in theme colors off) – the lotus pink
#          from tip to base, the Apple in the six stripes of 1977, the flag of Earth as white rings
#          on blue. Your own logo always takes the theme's color.
#   Cover  the cover of the song that plays, always in its own colors, never the theme's: two
#          pixels per character (▄), 24-bit color or the nearest of 256. It takes the logo's place
#          and as much room as the logo has (the whole height of the info). macOS gives the cover
#          to fastfetch's MediaRemote helper, run by Apple's perl as fastfetch does it itself (since
#          macOS 15.4 other programs may not ask MediaRemote); sips and lib/cover.pl turn it into
#          characters. Cached per song and size in ~/.cache/lotus/covers.
#   Live   while the start screen is on screen, the live loop in init.zsh swaps cover and logo in
#          place when a song starts, changes or stops (lotus_art_live).

# Own colors of the built-in logos:  fade <colors…> (top to bottom) · stripes <first row> <colors…>
# (rows above the first row take the first color) · box <front> <back> (the whole rectangle)
typeset -gA LOTUS_LOGO_OWN=(
  lotus    'fade 255;222;234 247;150;188 226;96;150'
  minimal  'fade 255;222;234 247;150;188 226;96;150'
  large    'fade 255;222;234 247;150;188 226;96;150'
  terminal 'fade 255;222;234 247;150;188 226;96;150'
  apple    'stripes 6 97;187;70 253;184;39 245;130;31 224;58;62 150;61;151 0;157;220'
  earth    'box 255;255;255 1;58;167'
)

# Block characters by their lit quarters: top left 1, top right 2, bottom left 4, bottom right 8
typeset -ga LOTUS_QUADS=(' ' ▘ ▝ ▀ ▖ ▌ ▞ ▛ ▗ ▚ ▐ ▜ ▄ ▙ ▟ █)

# The art's room on screen, for live swaps (set by lotus_art_pick); they are drawn to LOTUS_ART_TTY
typeset -gi LOTUS_ART_W=0 LOTUS_ART_H=0 LOTUS_ART_INFO=22 LOTUS_ART_LW=0 LOTUS_ART_LH=0 _lotus_art_tries=0
typeset -g LOTUS_ART_LOGO= LOTUS_ART_SHOWN= LOTUS_ART_KEY= LOTUS_ART_TTY=/dev/tty

# ── Logo ──────────────────────────────────────────────────────

# lotus_logo_paint <name> → REPLY = painted file (ANSI), reply = (width height); 1 = no logo
lotus_logo_paint() {
  setopt localoptions extendedglob
  lotus_logo_file $1
  local src=$REPLY
  REPLY= reply=(0 0)
  [[ -n $src ]] || return 1
  local -a st
  zstat -A st +mtime $src 2>/dev/null || return 1
  local rule=theme
  (( LOTUS_LOGO_THEME )) || rule=${LOTUS_LOGO_OWN[$1]:-theme}
  local dir=$LOTUS_CACHE/art out=$LOTUS_CACHE/art/$1.txt
  local key="$LOTUS_VERSION $src $st[1] $LOTUS_MODE $rule $LOTUS_C[logo]"
  if [[ -r $out && -r $out.key ]]; then
    local -a k=("${(@f)$(<$out.key)}")
    if [[ $k[1] == "$key" ]]; then REPLY=$out; reply=(${=k[2]}); return 0; fi
  fi

  local line text=
  local -a lines=() codes=() c
  local -i w=0 h i n
  for line in "${(@f)$(<$src)}"; do
    line=${line//\$\$/\$}
    lines+=("$line"); (( ${#line} > w )) && w=${#line}
  done
  h=${#lines}
  (( h )) || return 1
  local -a r=(${=rule})
  local back=
  case $r[1] in
    fade)
      local -F t u
      local -i s cr cg cb
      local -a a b
      (( n = ${#r} - 2 ))      # number of steps between the colors
      for (( i = 1; i <= h; i++ )); do
        if (( n < 1 )); then lotus_sgr $r[2]; codes+=("1;$REPLY"); continue; fi
        (( t = h > 1 ? (i - 1.0) / (h - 1) * n : 0, s = t, u = t - s ))
        (( s >= n )) && (( s = n - 1, u = 1 ))
        a=(${(s:;:)r[s + 2]}) b=(${(s:;:)r[s + 3]})
        (( cr = a[1] + (b[1] - a[1]) * u, cg = a[2] + (b[2] - a[2]) * u, cb = a[3] + (b[3] - a[3]) * u ))
        lotus_sgr "$cr;$cg;$cb"
        codes+=("1;$REPLY")
      done ;;
    stripes)
      local -i first=$r[2] k
      c=(${r[3,-1]})
      for (( i = 1; i <= h; i++ )); do
        (( k = i < first ? 1 : (i - first) * ${#c} / (h - first + 1) + 1 ))
        lotus_sgr $c[k]; codes+=("1;$REPLY")
      done ;;
    box)
      lotus_sgr $r[3]; back=$REPLY
      lotus_sgr $r[2]
      for (( i = 1; i <= h; i++ )); do codes+=("1;$REPLY"); done ;;
    *)
      for (( i = 1; i <= h; i++ )); do codes+=("1;$LOTUS_C[logo]"); done ;;
  esac

  # Every line as wide as the logo: fastfetch puts the info right after it.
  # Block characters whose top half is lit are drawn the other way round – the color as the
  # background, the dark part as the character: terminals that draw them with the font (Terminal.app)
  # leave a gap above each character, which would cut the picture into stripes.
  local norm inv ch want state fg
  local -i j q
  for (( i = 1; i <= h; i++ )); do
    line=$lines[i]
    fg=${codes[i]#1;}
    if [[ -n $back ]]; then
      line=${(r:w:: :)line} norm="1;$fg;48${back#38}" inv="1;$back;48${fg#38}"
    else
      norm="1;$fg" inv="1;7;$fg"
    fi
    state=
    for (( j = 1; j <= ${#line}; j++ )); do
      ch=$line[j] want=$norm
      if (( q = ${LOTUS_QUADS[(Ie)$ch]} - 1, q > 0 && q & 3 )); then
        want=$inv ch=${LOTUS_QUADS[16 - q]}     # the dark quarters
      fi
      [[ $want == $state ]] || { text+=$'\e[0;'"${want}m"; state=$want }
      text+=$ch
    done
    text+=$'\e[0m'"${(l:w-${#line}:: :)}"$'\n'
  done
  zf_mkdir -p $dir
  print -rn -- $text >| $out.$$ && zf_mv -f $out.$$ $out
  print -rl -- $key "$w $h" >| $out.key.$$ && zf_mv -f $out.key.$$ $out.key
  REPLY=$out reply=($w $h)
}

# ── Album cover ───────────────────────────────────────────────

# What plays, from macOS → reply = (status title artist album cover-file); 1 = nothing.
# The cover file is new and ours: the caller removes it (lotus_cover).
lotus_cover_query() {
  reply=()
  local ff=${LOTUS_FF:A} out
  [[ -x /usr/bin/perl && -x $ff ]] || return 1
  out=$(FF_MEDIA_REMOTE_SAVE_COVER=1 /usr/bin/perl -e 'require DynaLoader;
    my $so = DynaLoader::dl_load_file($ARGV[0], 0) or exit 1;
    my $sym = DynaLoader::dl_find_symbol($so, "ffPrintMediaByMediaRemote") or exit 1;
    DynaLoader::dl_install_xsub("fn", $sym, __FILE__); exit(fn())' $ff 2>/dev/null) || return 1
  local -a v=("${(@f)out}")
  (( ${#v} >= 7 )) || return 1
  reply=("$v[1]" "$v[2]" "$v[3]" "$v[4]" "$v[7]")
}

# lotus_cover <columns> <rows> → REPLY = art of the playing song's cover (as big as fits),
# reply = (width height); 1 = nothing plays, or the song has no cover
lotus_cover() {
  setopt localoptions extendedglob
  local -i cols=$1 rows=$2
  REPLY=
  lotus_cover_query || return 1
  local state=$reply[1] cover=$reply[5] id="$reply[2]|$reply[3]|$reply[4]"
  reply=()
  # only fastfetch's own temporary file is ours to remove
  [[ $cover == /*/ff_[[:alnum:]-]##.[[:alnum:]]## && -f $cover ]] || cover=
  if [[ $state != Playing || -z $cover ]]; then
    [[ -n $cover ]] && rm -f -- $cover
    return 1
  fi
  local -a sum=(${=$(print -rn -- $id | cksum)})
  local dir=$LOTUS_CACHE/covers
  local out=$dir/$sum[1]-${cols}x$rows-$LOTUS_MODE.txt
  if [[ ! -s $out ]]; then
    zf_mkdir -p $dir
    local bmp=$dir/.$$.bmp
    local -i px=$(( 4 * (cols > 2 * rows ? cols : 2 * rows) ))
    if sips -s format bmp -Z $px $cover --out $bmp >/dev/null 2>&1 &&
       /usr/bin/perl $LOTUS_ROOT/lib/cover.pl $bmp $cols $rows $LOTUS_MODE >| $out.$$ 2>/dev/null &&
       [[ -s $out.$$ ]]; then
      zf_mv -f $out.$$ $out
      lotus_log DEBUG cover "Cover of \"$id\" drawn (${cols}×$rows)"
    else
      rm -f -- $out.$$
      lotus_log DEBUG cover "Cover of \"$id\" could not be read"
    fi
    rm -f -- $bmp
    local -a old=($dir/*.txt(Nom[81,-1]))    # keep the newest 80
    (( ${#old} )) && rm -f -- $old
  fi
  rm -f -- $cover
  [[ -s $out ]] || return 1
  local -a lines=("${(@f)$(<$out)}")
  local first=${lines[1]//$'\e'\[[0-9;]#m/}
  REPLY=$out reply=(${#first} ${#lines})
}

# ── The start screen ──────────────────────────────────────────

# lotus_art_pick <info lines> → reply = fastfetch arguments for the art.
# The logo (the minimal lotus or none when the window is too narrow), or while a song plays its
# cover in the logo's place, as big as the logo's room. With a cover the room stays wide enough
# for the logo, so they can swap later without moving the info.
lotus_art_pick() {
  local -i n=$1 cols=${COLUMNS:-200} lw=0 lh=0 ltop=0 block cw ch top
  local logo=
  if lotus_logo_paint $LOTUS_LOGO; then
    logo=$REPLY lw=$reply[1] lh=$reply[2]
    if (( cols < lw + 60 )); then
      logo= lw=0 lh=0
      if [[ $LOTUS_LOGO != minimal ]] && lotus_logo_paint minimal && (( cols >= reply[1] + 60 )); then
        logo=$REPLY lw=$reply[1] lh=$reply[2]
      fi
    fi
  fi
  (( lh )) && (( ltop = lh >= n - 2 ? 2 : (n - lh) / 2 ))
  (( block = lh + ltop > n ? lh + ltop : n ))
  LOTUS_ART_LOGO=$logo LOTUS_ART_LW=$lw LOTUS_ART_LH=$lh LOTUS_ART_INFO=$n LOTUS_ART_H=$block

  _lotus_art_tries=0
  if (( LOTUS_NP_ON && LOTUS_COVER )); then
    # the info needs about 56 columns – the cover never cuts it off
    (( cw = cols - 64, ch = block, cw > 2 * ch && (cw = 2 * ch) ))
    if (( cw >= 24 )) && lotus_cover $cw $ch; then
      local -i w=$reply[1] h=$reply[2]
      (( top = (block - h) / 2 ))
      LOTUS_ART_W=$(( w > lw ? w : lw )) LOTUS_ART_SHOWN=$REPLY
      reply=(--logo $REPLY --logo-type file-raw --logo-width $w --logo-height $h
        --logo-padding-top $top --logo-padding-left 2 --logo-padding-right $(( 6 + LOTUS_ART_W - w )))
      return
    fi
    (( cw >= 24 )) && _lotus_art_tries=1    # a song may play whose cover macOS has not yet
  fi
  LOTUS_ART_W=$lw LOTUS_ART_SHOWN=$logo
  if (( lw )); then
    reply=(--logo $logo --logo-type file-raw --logo-width $lw --logo-height $lh
      --logo-padding-top $ltop --logo-padding-left 2 --logo-padding-right 6)
  else
    reply=(--logo none)
  fi
}

# Live swap (from the live loop): lotus_art_live <now playing line 1> <line 2>
# A song starts, changes or stops → its cover or the logo again, drawn into the art's room.
# Right after a song changes macOS may not have its cover yet: asked again up to 3 times.
lotus_art_live() {
  local key=
  [[ $2 == *▶* ]] && key=$1
  if [[ $key != $LOTUS_ART_KEY ]]; then
    LOTUS_ART_KEY=$key _lotus_art_tries=0
  elif [[ -z $key || $LOTUS_ART_SHOWN == $LOTUS_CACHE/covers/* ]] || (( _lotus_art_tries == 0 || _lotus_art_tries >= 3 )); then
    return 0     # the same song – its cover is shown, or it was asked for often enough
  fi
  (( LOTUS_ART_W > 0 && LOTUS_NP_ROW > 0 )) || return 0
  local art=$LOTUS_ART_LOGO
  local -i w=$LOTUS_ART_LW h=$LOTUS_ART_LH top r row
  (( top = h >= LOTUS_ART_INFO - 2 ? 2 : (LOTUS_ART_INFO - h) / 2 ))
  local -i cw=$(( LOTUS_ART_W < 2 * LOTUS_ART_H ? LOTUS_ART_W : 2 * LOTUS_ART_H ))
  if [[ -n $key ]] && (( LOTUS_COVER && cw >= 24 )); then
    (( _lotus_art_tries++ ))
    if lotus_cover $cw $LOTUS_ART_H; then
      art=$REPLY w=$reply[1] h=$reply[2]
      (( top = (LOTUS_ART_H - h) / 2 ))
    fi
  fi
  [[ $art == "$LOTUS_ART_SHOWN" ]] && return 0
  LOTUS_ART_SHOWN=$art
  local -a lines=()
  [[ -n $art ]] && lines=("${(@f)$(<$art)}")
  local out=$'\e7\e[?7l' fill=${(l:LOTUS_ART_W - w:: :)} blank=${(l:LOTUS_ART_W:: :)}
  local -i first=$(( LOTUS_NP_ROW - LOTUS_NP_IDX + 1 ))
  for (( r = 0; r < LOTUS_ART_H; r++ )); do
    (( row = first + r ))
    (( row >= 1 )) || continue
    if (( r >= top && r - top < ${#lines} )); then
      out+=$'\e['"$row;3H${lines[r - top + 1]}"$'\e[0m'"$fill"
    else
      out+=$'\e['"$row;3H$blank"
    fi
  done
  print -rn -- "$out"$'\e[0m\e[?7h\e8' > $LOTUS_ART_TTY 2>/dev/null
}
