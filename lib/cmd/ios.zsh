# lotus – iOS device tools: a launcher for AirCard, Nugget, Sideloadly and Dopamine.
# Lotus never bundles these tools. It links to the official sources, launches
# installed apps and checks compatibility with the connected device first.

lotus_cmd_ios() {
  shift   # "ios"
  lotus_ios_tools
  case $1 in
    devices|device) lotus_ios_devices_screen ;;
    '')             lotus_ios_menu ;;
    *)              lotus_ios_tool_by_name "$*" ;;
  esac
}

# data/ios-tools.tsv → LOTUS_IOS[id]=line, LOTUS_IOS_IDS
lotus_ios_tools() {
  typeset -gA LOTUS_IOS=()
  typeset -ga LOTUS_IOS_IDS=()
  local line
  for line in "${(@f)$(<$LOTUS_ROOT/data/ios-tools.tsv)}"; do
    [[ $line == \#* ]] && continue
    LOTUS_IOS[${line%%$'\t'*}]=$line
    LOTUS_IOS_IDS+=(${line%%$'\t'*})
  done
}

# ── Device detection ──────────────────────────────────────────
# Fills LOTUS_DEVICES (one tab separated line per device):
#   name  model  ios version  product type  connection  paired
lotus_ios_detect() {
  typeset -ga LOTUS_DEVICES=()
  local udid conn
  if (( $+commands[idevice_id] && $+commands[ideviceinfo] )); then
    for conn in usb network; do
      for udid in ${(f)"$(idevice_id ${${conn:#usb}:+-n} -l 2>/dev/null)"}; do
        [[ -z $udid ]] && continue
        local name=$(ideviceinfo -u $udid ${${conn:#usb}:+-n} -k DeviceName 2>/dev/null)
        local type=$(ideviceinfo -u $udid ${${conn:#usb}:+-n} -k ProductType 2>/dev/null)
        local ver=$(ideviceinfo -u $udid ${${conn:#usb}:+-n} -k ProductVersion 2>/dev/null)
        local paired=no
        idevicepair -u $udid validate >/dev/null 2>&1 && paired=yes
        LOTUS_DEVICES+=("${name:-iOS device}"$'\t'"$(lotus_ios_model $type)"$'\t'"${ver:-unknown}"$'\t'"$type"$'\t'"${(C)conn/usb/USB}"$'\t'"$paired")
      done
    done
    return
  fi
  # Without libimobiledevice: USB devices from the system profiler (no iOS version)
  local line
  for line in ${(f)"$(system_profiler SPUSBDataType 2>/dev/null | grep -E '^ +(iPhone|iPad|iPod)[^:]*:$')"}; do
    line=${${line##[[:space:]]#}%:}
    LOTUS_DEVICES+=("$line"$'\t'"$line"$'\t'"unknown"$'\t'"-"$'\t'"USB"$'\t'"unknown")
  done
}

# ProductType → readable model (common iPhones; others are shown as they are)
lotus_ios_model() {
  local -A names=(
    iPhone11,2 'iPhone XS' iPhone11,6 'iPhone XS Max' iPhone11,8 'iPhone XR' iPhone12,1 'iPhone 11'
    iPhone12,3 'iPhone 11 Pro' iPhone12,5 'iPhone 11 Pro Max' iPhone12,8 'iPhone SE (2nd gen)'
    iPhone13,2 'iPhone 12' iPhone13,3 'iPhone 12 Pro' iPhone14,5 'iPhone 13' iPhone14,2 'iPhone 13 Pro'
    iPhone14,7 'iPhone 14' iPhone15,2 'iPhone 14 Pro' iPhone15,4 'iPhone 15' iPhone16,1 'iPhone 15 Pro'
    iPhone17,3 'iPhone 16' iPhone17,1 'iPhone 16 Pro')
  print -r -- ${names[$1]:-${1:-unknown}}
}

# Apple chip from the ProductType (iPhones; iPads and others → unknown)
lotus_ios_chip() {
  local t=$1
  [[ $t == iPhone<->,<-> ]] || { REPLY=; return 1 }
  local -i major=${${t#iPhone}%%,*}
  case $major in
    7) REPLY=A8 ;; 8) REPLY=A9 ;; 9) REPLY=A10 ;; 10) REPLY=A11 ;; 11) REPLY=A12 ;; 12) REPLY=A13 ;;
    13) REPLY=A14 ;; 14) REPLY=A15 ;; 15) REPLY=A16 ;; 16) REPLY=A17 ;; 17) REPLY=A18 ;; *) REPLY=A19 ;;
  esac
}

# "1.2.3" <= "1.10" ?   lotus_ver_le a b
lotus_ver_le() {
  local -a a=(${(s:.:)1}) b=(${(s:.:)2})
  local -i i
  for (( i = 1; i <= 3; i++ )); do
    (( ${a[i]:-0} < ${b[i]:-0} )) && return 0
    (( ${a[i]:-0} > ${b[i]:-0} )) && return 1
  done
  return 0
}

# Compatibility of a tool with a device → REPLY = ok | no | unknown, LOTUS_COMPAT_WHY
lotus_ios_compat() {   # <tool id> <ios version> <product type>
  local -a f=("${(@ps:\t:)LOTUS_IOS[$1]}")
  local ver=$2 type=$3 min=$f[9] max=$f[10]
  typeset -g LOTUS_COMPAT_WHY=
  if [[ $ver != [0-9]* ]]; then REPLY=unknown; LOTUS_COMPAT_WHY="iOS version unknown"; return; fi
  if ! lotus_ver_le $min $ver; then REPLY=no; LOTUS_COMPAT_WHY="needs iOS $min or newer"; return; fi
  if [[ $max != - ]] && ! lotus_ver_le $ver $max; then REPLY=no; LOTUS_COMPAT_WHY="supports up to iOS ${max/26.99/26.x}"; return; fi
  if [[ $1 == dopamine ]]; then
    lotus_ios_chip $type || { REPLY=unknown; LOTUS_COMPAT_WHY="check the chip on the Dopamine page"; return }
    local chip=$REPLY limit
    case $chip in
      A8|A9|A10|A11) limit=18.7.1 ;;
      A12|A13)       limit=26.0.1; lotus_ver_le $ver 18.7.1 || [[ $ver == 26.0* ]] || { REPLY=no; LOTUS_COMPAT_WHY="$chip: iOS 15.0-18.7.1 or 26.0-26.0.1"; return } ;;
      *)             limit=17.3.1 ;;
    esac
    lotus_ver_le $ver $limit || { REPLY=no; LOTUS_COMPAT_WHY="$chip supports up to iOS $limit"; return }
  fi
  REPLY=ok
}

lotus_ios_devices_screen() {
  ui_header "iOS devices"
  lotus_ios_detect
  if (( ! ${#LOTUS_DEVICES} )); then
    ui_text "No iOS device detected."
    ui_dim "Connect an iPhone or iPad with a cable and unlock it."
    (( $+commands[ideviceinfo] )) || ui_dim "For the iOS version and pairing status: brew install libimobiledevice"
    ui_blank; return 0
  fi
  local d
  local -a f
  for d in $LOTUS_DEVICES; do
    f=("${(@ps:\t:)d}")
    ui_card $f[1] "MODEL|$f[2]" "iOS|$f[3]" "CONNECTION|$f[5]" "PAIRED|$f[6]"
    local tool tools=()
    for tool in $LOTUS_IOS_IDS; do
      lotus_ios_compat $tool $f[3] $f[4]
      case $REPLY in ok) REPLY=✓ ;; no) REPLY=✗ ;; *) REPLY=? ;; esac
      tools+=("$REPLY ${${(@ps:\t:)LOTUS_IOS[$tool]}[2]}")
    done
    ui_dim "  ${(j:   :)tools}"
    ui_blank
  done
  (( $+commands[ideviceinfo] )) || { ui_dim "Install libimobiledevice for the iOS version: brew install libimobiledevice"; ui_blank }
}

lotus_ios_menu() {
  ui_header "iOS tools" "AirCard · Nugget · Sideloadly · Dopamine"
  lotus_ios_detect
  local dev_ver=unknown dev_type=- id state
  if (( ${#LOTUS_DEVICES} )); then
    local -a d=("${(@ps:\t:)LOTUS_DEVICES[1]}")
    dev_ver=$d[3] dev_type=$d[4]
    ui_info "Device: $d[1] · iOS $d[3] · $d[5]"
  else
    ui_dim "No iOS device detected – compatibility is checked once one is connected."
  fi
  ui_blank
  local -a labels f
  for id in $LOTUS_IOS_IDS; do
    f=("${(@ps:\t:)LOTUS_IOS[$id]}")
    state="not installed"
    [[ $f[7] != - && -d /Applications/$f[7] ]] && state=installed
    [[ $f[3] == ipa ]] && state="iOS app"
    lotus_ios_compat $id $dev_ver $dev_type
    case $REPLY in ok) REPLY=compatible ;; no) REPLY="not compatible" ;; *) REPLY= ;; esac
    labels+=("${(r:11:)f[2]} ${(r:15:)state} $REPLY")
  done
  ui_choose "Pick a tool" $labels || return 0
  lotus_ios_tool_card $LOTUS_IOS_IDS[REPLY] $dev_ver $dev_type
}

lotus_ios_tool_by_name() {
  local -A by_name
  local id
  for id in $LOTUS_IOS_IDS; do by_name[${${(@ps:\t:)LOTUS_IOS[$id]}[2]}]=$id; done
  lotus_pick "$1" tool ${(k)by_name} || { ui_error "Unknown tool" "$1" "Tools: ${(j:, :)${(k)by_name}}"; return 1 }
  lotus_ios_detect
  local -a d=("${(@ps:\t:)LOTUS_DEVICES[1]}")
  lotus_ios_tool_card $by_name[$REPLY] ${d[3]:-unknown} ${d[4]:--}
}

lotus_ios_tool_card() {   # <id> <ios version> <product type>
  local id=$1
  local -a f=("${(@ps:\t:)LOTUS_IOS[$id]}")
  local installed=no supported compat
  [[ $f[7] != - && -d /Applications/$f[7] ]] && installed=yes
  supported="iOS $f[9]${${f[10]:#-}:+ – ${f[10]/26.99/26.x}}${${(M)f[10]:#-}:+ and newer}"
  lotus_ios_compat $id $2 $3
  case $REPLY in
    ok) compat="compatible with your device" ;;
    no) compat="NOT compatible: $LOTUS_COMPAT_WHY" ;;
    *)  compat="unknown – ${${(M)2:#unknown}:+connect the device}${2:#unknown}${${2:#unknown}:+ – $LOTUS_COMPAT_WHY}" ;;
  esac
  ui_blank
  ui_card $f[2] "ABOUT|$f[4]" "TYPE|${${f[3]/mac/Mac app}/ipa/iOS app (IPA)}" "SUPPORTS|$supported" \
    "SOURCE|$f[5]" "INSTALLED|${${f[3]:#ipa}:+$installed}${${(M)f[3]:#ipa}:+on the device}" "DEVICE|$compat"
  [[ $f[11] != - ]] && { ui_blank; ui_warn $f[11] }
  [[ $REPLY == no ]] && ui_warn "Lotus will not start $f[2] for this device."
  ui_blank

  local -a actions=()
  [[ $installed == yes && $REPLY != no ]] && actions+=("Open $f[2]")
  [[ $f[6] != - ]] && actions+=("Download the official release")
  actions+=("Open the official page" "Cancel")
  ui_choose "" $actions || return 0
  case $actions[REPLY] in
    Open\ *page)  open $f[5] ;;
    Open\ *)      open -a "/Applications/$f[7]" && ui_info "Opening $f[2]" ;;
    Download*)    lotus_ios_download $id ;;
  esac
}

# Latest official release asset from GitHub → ~/Downloads/Lotus, then open it
lotus_ios_download() {
  local -a f=("${(@ps:\t:)LOTUS_IOS[$1]}")
  local asset=${f[8]//\{arch\}/${${$(uname -m)/arm64/arm}/x86_64/intel}} json url tag dest
  ui_step "Asking GitHub for the latest $f[2] release …"
  json=$(curl -fsSL -m 10 "https://api.github.com/repos/$f[6]/releases/latest" 2>/dev/null)
  [[ -z $json ]] && { ui_error "Could not reach GitHub" "Check your internet connection."; return 1 }
  tag=$(print -r -- $json | lotus_jq -r '.tag_name')
  url=$(print -r -- $json | lotus_jq -r --arg a $asset '.assets[] | select(.name == $a) | .browser_download_url')
  [[ -z $url ]] && { ui_error "No $asset in the latest release" "" "Opening the releases page instead."; open "$f[5]/releases"; return 1 }
  dest=~/Downloads/Lotus/${asset}
  zf_mkdir -p ${dest:h}
  ui_card "$f[2] $tag" "FILE|$asset" "FROM|github.com/$f[6] (official releases)" "TO|$dest"
  ui_blank
  ui_confirm "Download it?" y || return 0
  if [[ -e $dest ]] && ! ui_confirm "$asset already exists. Replace it?" n; then return 0; fi
  curl -fL --progress-bar -o $dest.part $url && zf_mv -f $dest.part $dest || { rm -f $dest.part; ui_error "Download failed"; return 1 }
  ui_success "Saved to $dest"
  if [[ $f[3] == ipa ]]; then
    ui_info "Install it on your device with Sideloadly (or TrollStore)."
    [[ -d /Applications/Sideloadly.app ]] && ui_confirm "Open Sideloadly now?" y && open -a /Applications/Sideloadly.app
  else
    ui_confirm "Open the installer?" y && open $dest
  fi
}
