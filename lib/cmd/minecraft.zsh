# lotus – Minecraft server setup assistant (/minecraft, /mc)
# Server files come only from the official sources: Mojang (Vanilla) and PaperMC (Paper).

typeset -g MC_HOME=${LOTUS_MC_HOME:-~/Minecraft}

lotus_cmd_minecraft() {
  shift
  ui_header Minecraft "server assistant"
  ui_choose "What do you want to do?" "Set up a new server" "Start a server I set up" "Port forwarding and firewall guide" "Cancel" || return 0
  case $REPLY in
    1) lotus_mc_new ;;
    2) lotus_mc_start ;;
    3) lotus_mc_guide ;;
  esac
}

_mc_step() { ui_blank; print -r -- "  "$'\e['"$LOTUS_C[dim]m$1/8"$'\e[0m'"  "$'\e[1m'"$2"$'\e[0m' }

lotus_mc_new() {
  # 1. type
  _mc_step 1 "Server type"
  ui_choose "" "Vanilla – the official Minecraft server" "Paper – faster, supports plugins" || return 0
  local type=${${REPLY/1/vanilla}/2/paper}

  # 2. version
  _mc_step 2 "Minecraft version"
  ui_step "Asking Mojang for the versions …"
  local manifest=$(curl -fsSL -m 10 https://piston-meta.mojang.com/mc/game/version_manifest_v2.json 2>/dev/null)
  [[ -z $manifest ]] && { ui_error "No internet connection" "Lotus could not reach Mojang."; return 1 }
  local latest=$(print -r -- $manifest | lotus_jq -r '.latest.release')
  ui_input "Version" $latest || return 1
  local version=$REPLY
  local vurl=$(print -r -- $manifest | lotus_jq -r --arg v $version '.versions[] | select(.id == $v and .type == "release") | .url')
  [[ -z $vurl ]] && { ui_error "Unknown version" "$version" "Latest release: $latest"; return 1 }
  local vjson=$(curl -fsSL -m 10 $vurl 2>/dev/null)
  local -i java_need=$(print -r -- $vjson | lotus_jq -r '.javaVersion.majorVersion // 21')

  # 3. Java
  _mc_step 3 "Java $java_need"
  local java_home
  java_home=$(/usr/libexec/java_home -v $java_need+ 2>/dev/null) || java_home=$(/usr/libexec/java_home -v $java_need 2>/dev/null)
  if [[ -z $java_home ]]; then
    ui_warn "Minecraft $version needs Java $java_need or newer – it is not installed."
    ui_dim "Lotus can install Eclipse Temurin (free, open source) with Homebrew."
    ui_confirm "Install Java now?" y || { ui_info "Install Java $java_need later and run /minecraft again."; return 1 }
    source $LOTUS_ROOT/lib/cmd/brew.zsh
    lotus_need_brew || return 1
    lotus_brew_run cask temurin || return 1
    java_home=$(/usr/libexec/java_home -v $java_need+ 2>/dev/null) || { ui_error "Java is still missing" "" "Restart the terminal and try again."; return 1 }
  fi
  ui_success "Java: ${java_home:h:h:t}"

  # 4. folder
  _mc_step 4 "Folder"
  ui_input "Server name" "${type}-${version}" || return 1
  local name=${REPLY//[^[:alnum:]._-]/-}
  local dir=$MC_HOME/$name
  if [[ -e $dir ]]; then
    ui_warn "$dir already exists."
    ui_confirm "Use it anyway (files with the same name are replaced)?" n || return 0
  fi
  zf_mkdir -p $dir

  # 5. memory
  _mc_step 5 "Memory (RAM)"
  local -i total=$(( $(sysctl -n hw.memsize) / 1073741824 )) g
  local -a opts=()
  for g in 2 4 6 8 12; do (( g <= total / 2 )) && opts+=("$g GB"); done
  (( ${#opts} )) || opts=("2 GB")
  ui_dim "Your Mac has $total GB. Keep at least half for macOS. 4 GB is plenty for a few friends."
  ui_choose "" $opts || return 0
  local ram=${opts[REPLY]% GB}G

  # 6. download
  _mc_step 6 "Download"
  local url sum algo=sha1
  if [[ $type == vanilla ]]; then
    url=$(print -r -- $vjson | lotus_jq -r '.downloads.server.url // empty')
    sum=$(print -r -- $vjson | lotus_jq -r '.downloads.server.sha1 // empty')
  else
    local build=$(curl -fsSL -m 10 "https://fill.papermc.io/v3/projects/paper/versions/$version/builds/latest" 2>/dev/null)
    url=$(print -r -- $build | lotus_jq -r '.downloads["server:default"].url // empty' 2>/dev/null)
    sum=$(print -r -- $build | lotus_jq -r '.downloads["server:default"].checksums.sha256 // empty' 2>/dev/null)
    algo=sha256
  fi
  [[ -z $url ]] && { ui_error "No $type server for $version yet" "" "Try another version or Vanilla."; return 1 }
  ui_dim "From: ${${url#https://}%%/*}"
  curl -fL --progress-bar -o $dir/server.jar.part $url || { rm -f $dir/server.jar.part; ui_error "Download failed"; return 1 }
  if [[ -n $sum ]]; then
    local got=${$(shasum -a ${algo#sha} $dir/server.jar.part)[1]}
    [[ $got == $sum ]] || { rm -f $dir/server.jar.part; ui_error "Checksum mismatch" "The download was damaged or changed." "Nothing was installed. Try again."; return 1 }
    ui_success "Checksum verified"
  fi
  zf_mv -f $dir/server.jar.part $dir/server.jar

  # 7. EULA + basic settings
  _mc_step 7 "Minecraft EULA and settings"
  ui_text "Running a server requires accepting the Minecraft End User License Agreement:"
  ui_dim "https://aka.ms/MinecraftEULA"
  if ui_confirm "Do you accept the EULA?" n; then
    print "eula=true" >| $dir/eula.txt
  else
    print "eula=false" >| $dir/eula.txt
    ui_warn "The server will not start until you set eula=true in $dir/eula.txt"
  fi
  ui_input "Server name in the list (MOTD)" "A Lotus Minecraft server" || return 1
  local motd=${REPLY//[^[:print:]]/}
  ui_input "Max players" 10 || return 1
  local -i players=${REPLY//[^0-9]/}; (( players < 1 )) && players=10
  local -a diffs=(peaceful easy normal hard)
  ui_choose "Difficulty" $diffs || return 0
  local diff=$diffs[REPLY]
  print -r -- "# Created by Lotus – the server adds all other settings on first start
motd=$motd
max-players=$players
difficulty=$diff
server-port=25565
online-mode=true
white-list=false" >| $dir/server.properties

  # 8. start script
  _mc_step 8 "Start script"
  print -r -- "#!/bin/zsh
# Double-click to start the server. Stop it by typing: stop
cd \"\${0:A:h}\"
exec \"$java_home/bin/java\" -Xms$ram -Xmx$ram -jar server.jar nogui" >| $dir/start.command
  chmod +x $dir/start.command
  ui_success "Server ready in $dir"
  ui_blank
  local lan=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
  ui_card "How to join" "THIS MAC|localhost" "SAME WI-FI|${lan:-your Mac's IP}:25565" "INTERNET|needs port forwarding (guide: /minecraft → 3)"
  ui_blank
  ui_confirm "Start the server now?" y && "$dir/start.command"
}

lotus_mc_start() {
  local -a servers=($MC_HOME/*/start.command(N))
  (( ${#servers} )) || { ui_error "No server found" "Lotus looks in $MC_HOME" "Set one up first: /minecraft → 1"; return 1 }
  ui_choose "Which server?" ${servers:h:t} || return 0
  ui_dim "Type 'stop' to shut it down."
  "${servers[REPLY]}"
}

lotus_mc_guide() {
  local lan=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
  ui_header Minecraft "port forwarding guide"
  ui_category "1  Play on the same Wi-Fi"
  ui_text "Friends on your network join with:  ${lan:-<your Mac's IP>}:25565"
  ui_dim  "Find the IP any time in System Settings → Wi-Fi → Details."
  ui_blank
  ui_category "2  Allow the firewall"
  ui_text "When the server starts, macOS may ask whether java may accept incoming connections."
  ui_text "Choose Allow. To check: System Settings → Network → Firewall → Options."
  ui_blank
  ui_category "3  Play over the internet (port forwarding)"
  ui_text "a) Give your Mac a fixed IP in the router (DHCP reservation)."
  ui_text "b) In the router, forward TCP port 25565 to ${lan:-your Mac's IP}."
  ui_text "c) Friends join with your public IP – your router's status page shows it."
  ui_dim  "   Share it only with people you trust. Lotus does not look it up or store it."
  ui_blank
  ui_category "4  Safer alternatives"
  ui_text "Turn on white-list=true in server.properties and add friends with: whitelist add <name>"
  ui_text "Tools like Tailscale let friends join without opening router ports."
  ui_blank
  ui_dim "Full tutorial: $LOTUS_P[website]minecraft.html"
  ui_blank
}
