# lotus – the art left of the start screen: the logo, or the album cover while a song plays.
#
#   Logo   logos/*.txt hold shapes only. Lotus paints them into the cache: in the theme's colors –
#          a gradient from its second key color over the logo color to its key color, or the logo
#          color alone (/settings → Logo gradient) – or in their own colors (Logo in theme colors
#          off): the lotus pink from tip to base, the Apple in the six stripes of 1977, the flag of
#          Earth as white rings on blue. Your own logo always takes the theme's colors.
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
  local -a th=(${=LOTUS_THEMES[$LOTUS_THEME]:-$LOTUS_THEMES[matcha]})   # logo key accent key2 …
  (( LOTUS_LOGO_FADE )) && rule="fade $th[4] $th[1] $th[2]"
  (( LOTUS_LOGO_THEME )) || rule=${LOTUS_LOGO_OWN[$1]:-$rule}
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
  # One color per half line (the top and the bottom pixel of a character): a gradient gets
  # twice as many steps where the shape is solid
  local -a r=(${=rule})
  local back= stop
  local -i k
  case $r[1] in
    fade)
      # mixed in OKLab: the colors in between stay clear (pink → green is no muddy brown)
      local -F t u
      local -i s
      local -a ok=() a b
      for stop in ${r[2,-1]}; do _lotus_oklab $stop; ok+=("$reply"); done
      (( n = ${#ok} - 1 ))     # number of steps between the colors
      for (( k = 1; k <= 2 * h; k++ )); do
        if (( n < 1 )); then lotus_sgr $r[2]; codes+=($REPLY); continue; fi
        (( t = (k - 1.0) / (2 * h - 1) * n, s = t, u = t - s ))
        (( s >= n )) && (( s = n - 1, u = 1 ))
        a=(${=ok[s + 1]}) b=(${=ok[s + 2]})
        _lotus_oklab_rgb $(( a[1] + (b[1] - a[1]) * u )) $(( a[2] + (b[2] - a[2]) * u )) $(( a[3] + (b[3] - a[3]) * u ))
        lotus_sgr $REPLY
        codes+=($REPLY)
      done ;;
    stripes)
      local -i first=$r[2]
      c=(${r[3,-1]})
      for (( i = 1; i <= h; i++ )); do
        (( k = i < first ? 1 : (i - first) * ${#c} / (h - first + 1) + 1 ))
        lotus_sgr $c[k]; codes+=($REPLY $REPLY)
      done ;;
    box)
      lotus_sgr $r[3]; back=$REPLY
      lotus_sgr $r[2]
      for (( i = 1; i <= h; i++ )); do codes+=($REPLY $REPLY); done ;;
    *)
      for (( i = 1; i <= h; i++ )); do codes+=($LOTUS_C[logo] $LOTUS_C[logo]); done ;;
  esac

  # Every line as wide as the logo: fastfetch puts the info right after it.
  # Block characters whose top half is lit are drawn the other way round – the color as the
  # background, the dark part as the character: terminals that draw them with the font (Terminal.app)
  # leave a gap above each character, which would cut the picture into stripes. A full block is
  # ▄ in the bottom color on the top color.
  local norm inv full ch want state top bot
  local -i j q
  for (( i = 1; i <= h; i++ )); do
    line=$lines[i] top=${codes[2 * i - 1]} bot=${codes[2 * i]}
    if [[ -n $back ]]; then
      line=${(r:w:: :)line} norm="1;$top;48${back#38}" inv="1;$back;48${top#38}" full=$inv
    else
      norm="1;$bot" inv="1;7;$top" full="1;$bot;48${top#38}"
    fi
    state=
    for (( j = 1; j <= ${#line}; j++ )); do
      ch=$line[j] want=$norm
      if (( q = ${LOTUS_QUADS[(Ie)$ch]} - 1, q == 15 )) && [[ -z $back ]]; then
        want=$full ch=▄
      elif (( q > 0 && q & 3 )); then
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

# OKLab (Björn Ottosson), a color space where mixing two colors looks even to the eye
#   _lotus_oklab "r;g;b" → reply = (L a b)      _lotus_oklab_rgb L a b → REPLY = "r;g;b"
_lotus_oklab() {
  local -a c=(${(s:;:)1}) v=()
  local -F x l m s
  for x in $c; do (( x /= 255.0, x = x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4 )); v+=($x); done
  (( l = (0.4122214708 * v[1] + 0.5363325363 * v[2] + 0.0514459929 * v[3]) ** (1.0 / 3),
     m = (0.2119034982 * v[1] + 0.6806995451 * v[2] + 0.1073969566 * v[3]) ** (1.0 / 3),
     s = (0.0883024619 * v[1] + 0.2817188376 * v[2] + 0.6299787005 * v[3]) ** (1.0 / 3) ))
  reply=($(( 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s ))
         $(( 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s ))
         $(( 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s )))
}
_lotus_oklab_rgb() {
  local -F l m s x
  local -i i
  local -a out=()
  (( l = ($1 + 0.3963377774 * $2 + 0.2158037573 * $3) ** 3,
     m = ($1 - 0.1055613458 * $2 - 0.0638541728 * $3) ** 3,
     s = ($1 - 0.0894841775 * $2 - 1.2914855480 * $3) ** 3 ))
  for x in $(( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s )) \
           $(( -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s )) \
           $(( -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s )); do
    (( x = x <= 0.0031308 ? 12.92 * x : 1.055 * x ** (1 / 2.4) - 0.055, i = x * 255 + 0.5, i = i < 0 ? 0 : (i > 255 ? 255 : i) ))
    out+=($i)
  done
  REPLY=${(j:;:)out}
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
