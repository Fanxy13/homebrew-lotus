# lotus – /weather with ASCII art. Provider: Open-Meteo (free, no API key).
# The provider lives in lotus_weather_fetch – swap it there to use another service.

typeset -gi LOTUS_WEATHER_TTL=600   # seconds a forecast is reused

lotus_cmd_weather() {
  shift   # "weather"
  local place="$*"
  [[ -z ${place// } ]] && place=$LOTUS_WEATHER_LOCATION
  if [[ -z ${place// } ]]; then
    ui_header Weather
    ui_dim "No default city yet."
    ui_input "City" || return 1
    place=$REPLY
    [[ -z ${place// } ]] && return 1
    if ui_confirm "Use $place as your default city?" y; then
      LOTUS_WEATHER_LOCATION=$place; lotus_save
    fi
  fi
  if [[ $place == *[[:cntrl:]\;\`\$\\]* || ${#place} -gt 60 ]]; then
    ui_error "That does not look like a city name" "$place"; return 1
  fi
  lotus_weather_fetch "$place" || return 1
  lotus_weather_show
}

# ── Provider: Open-Meteo ──────────────────────────────────────
# Fills LOTUS_W[...] and LOTUS_WD (daily rows). Uses and refreshes the cache.
lotus_weather_fetch() {
  local place=$1 key=${${(L)1}//[^[:alnum:]]/_}
  local dir=$LOTUS_CACHE/weather geo=$LOTUS_CACHE/weather/$key.geo data=$LOTUS_CACHE/weather/$key-$LOTUS_WEATHER_UNITS.json
  zf_mkdir -p $dir
  local -a st
  local fresh=0 offline=0
  [[ -r $data ]] && zstat -A st +mtime $data && (( EPOCHSECONDS - st[1] < LOTUS_WEATHER_TTL )) && fresh=1

  # 1. city → coordinates (cached for good)
  if [[ ! -s $geo ]]; then
    lotus_urlencode $place %20
    local g=$(curl -fsS -m 8 "https://geocoding-api.open-meteo.com/v1/search?name=$REPLY&count=1&language=en&format=json" 2>/dev/null)
    if [[ -z $g ]]; then
      ui_error "No internet connection" "Lotus could not reach the weather service." "Try again when you are online."
      return 1
    fi
    print -r -- $g | lotus_jq -r '.results[0] // empty | [.name, (.admin1 // ""), .country, .latitude, .longitude] | @tsv' >| $geo
    if [[ ! -s $geo ]]; then
      rm -f $geo
      ui_error "City not found" "$place" "Check the spelling, e.g. /weather Zurich"
      return 1
    fi
  fi
  local -a loc=("${(@ps:\t:)$(<$geo)}")

  # 2. forecast (cached for a few minutes)
  if (( ! fresh )); then
    local units="&temperature_unit=celsius&wind_speed_unit=kmh"
    [[ $LOTUS_WEATHER_UNITS == imperial ]] && units="&temperature_unit=fahrenheit&wind_speed_unit=mph"
    local url="https://api.open-meteo.com/v1/forecast?latitude=$loc[4]&longitude=$loc[5]&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=4$units"
    if curl -fsS -m 8 $url -o $data.tmp 2>/dev/null && [[ -s $data.tmp ]]; then
      zf_mv -f $data.tmp $data
    else
      rm -f $data.tmp
      [[ -r $data ]] || { ui_error "No internet connection" "Lotus could not reach the weather service."; return 1 }
      offline=1
    fi
  fi

  typeset -gA LOTUS_W=()
  local -a c=("${(@f)$(lotus_jq -r '.current | .temperature_2m, .apparent_temperature, .relative_humidity_2m, .weather_code, .wind_speed_10m, .is_day, .time' $data)}")
  LOTUS_W=(name "$loc[1]" region "$loc[2]" country "$loc[3]" temp "$c[1]" feels "$c[2]" hum "$c[3]" code "$c[4]"
           wind "$c[5]" day "$c[6]" time "$c[7]" offline $offline)
  typeset -ga LOTUS_WD=("${(@f)$(lotus_jq -r '.daily | [.time, .weather_code, .temperature_2m_max, .temperature_2m_min, .precipitation_probability_max] | transpose[] | @tsv' $data)}")
}

# ── Presentation ──────────────────────────────────────────────

# WMO weather code → kind and words
lotus_weather_kind() {   # <code> <is_day> → reply=(kind text)
  local -i c=$1
  case $c in
    0)        reply=(sunny "Clear sky") ;;
    1|2)      reply=(partly "Partly cloudy") ;;
    3)        reply=(cloudy "Overcast") ;;
    45|48)    reply=(fog "Fog") ;;
    51|53|55|56|57) reply=(rain "Drizzle") ;;
    61|63|65|66|67|80|81|82) reply=(rain "Rain") ;;
    71|73|75|77|85|86) reply=(snow "Snow") ;;
    95|96|99) reply=(storm "Thunderstorm") ;;
    *)        reply=(cloudy "Cloudy") ;;
  esac
  [[ $2 == 0 && $reply[1] == (sunny|partly) ]] && reply[1]=night
}

# ASCII art, 5 lines × 15 columns, colored with the theme → reply
lotus_weather_art() {
  local wt=$'\e[97m' s=$'\e['"$LOTUS_C[key2]m" w=$'\e['"$LOTUS_C[border]m" r=$'\e['"$LOTUS_C[accent]m" n=$'\e['"$LOTUS_C[salute]m" x=$'\e[0m' f=$'\e['"$LOTUS_C[dim]m" b=$'\e[1;'"$LOTUS_C[key2]m"
  case $1 in
    sunny)  reply=("${s}    \\   /      $x" "${s}     .-.       $x" "${s}  - (   ) -    $x" "${s}     \`-'       $x" "${s}    /   \\      $x") ;;
    partly) reply=("${s}   \\  /        $x" "${s} _ /\"\"${w}.-.      $x" "${s}   \\_${w}(   ).    $x" "${s}   /${w}(___(__)   $x" "               ") ;;
    cloudy) reply=("               " "${w}     .--.      $x" "${w}  .-(    ).    $x" "${w} (___.__)__)   $x" "               ") ;;
    rain)   reply=("${w}     .-.       $x" "${w}    (   ).     $x" "${w}   (___(__)    $x" "${r}    ' ' ' '    $x" "${r}   ' ' ' '     $x") ;;
    storm)  reply=("${w}     .-.       $x" "${w}    (   ).     $x" "${w}   (___(__)    $x" "${b}    /_ ${r}' '${b} /_   $x" "${r}   ' '${b}/ ${r}' '    $x") ;;
    snow)   reply=("${w}     .-.       $x" "${w}    (   ).     $x" "${w}   (___(__)    $x" "${wt}    *  *  *    $x" "${wt}   *  *  *     $x") ;;
    fog)    reply=("               " "${f} _ - _ - _ -   $x" "${f}  _ - _ - _    $x" "${f} _ - _ - _ -   $x" "               ") ;;
    night)  reply=("${n}      *    .   $x" "${n}   .--.   *    $x" "${n}  (  (     .   $x" "${n}   \`--'   *    $x" "${n}  *    .       $x") ;;
  esac
}

lotus_weather_show() {
  local u=°C sp=km/h
  [[ $LOTUS_WEATHER_UNITS == imperial ]] && { u=°F; sp=mph }
  lotus_weather_kind $LOTUS_W[code] $LOTUS_W[day]
  local kind=$reply[1] text=$reply[2]
  lotus_weather_art $kind
  local -a art=("${reply[@]}")
  local k=$'\e[1;'"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" x=$'\e[0m' t=$'\e[1m'
  local -a info=(
    "${t}${LOTUS_W[name]}${x}${d}${LOTUS_W[region]:+, $LOTUS_W[region]}, $LOTUS_W[country]${x}"
    "${t}${${LOTUS_W[temp]}%.*}${u}${x}  ${text}"
    "${k}Feels like${x}  ${${LOTUS_W[feels]}%.*}${u}"
    "${k}Humidity  ${x}  $LOTUS_W[hum]%"
    "${k}Wind      ${x}  ${${LOTUS_W[wind]}%.*} $sp"
  )
  ui_header Weather "${${(M)LOTUS_W[offline]:#1}:+offline – last update ${LOTUS_W[time]#*T}}"
  local -i i
  for (( i = 1; i <= 5; i++ )); do print -r -- "  ${art[i]}   ${info[i]}"; done
  ui_blank
  # forecast: today + 3 days
  local row day dname kd LC_ALL=C
  local -a f out=()
  for row in $LOTUS_WD; do
    f=("${(@ps:\t:)row}")
    strftime -r -s day '%Y-%m-%d' $f[1] 2>/dev/null
    strftime -s dname '%a' $day 2>/dev/null
    lotus_weather_kind $f[2] 1
    out+=("${k}${(r:4:)dname}${x} ${(r:14:)reply[2]} ${t}${${f[3]}%.*}${u}${x}${d} / ${${f[4]}%.*}${u}  ${f[5]:-0}% rain${x}")
  done
  ui_category "Forecast"
  for row in $out; do print -r -- "    $row"; done
  ui_blank
}
