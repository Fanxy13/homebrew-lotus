# lotus – plugins for a Paper server, for the control center (lib/mc/control.zsh).
# Search and download from Modrinth (modrinth.com): only plugins made for Paper, Spigot, Bukkit or
# Purpur and for the server's Minecraft version, only files from Modrinth's own download server, each
# one checked against its SHA-512 before it goes into plugins/. Required dependencies come along.
# Plugins of your own: drag the .jar into the window. What Lotus installed is noted in .lotus/plugins.tsv
# (project id, slug, title, version, file), so updates replace the old file.

typeset -g MCP_API=https://api.modrinth.com/v2 MCP_CDN=https://cdn.modrinth.com/
typeset -ga MCP_LOADERS=(paper spigot bukkit purpur)

# Modrinth wants to know who asks
_mcp_ua() { REPLY="Fanxy13/homebrew-lotus/$LOTUS_VERSION (lotus minecraft control center)" }

# The search address: <query> <minecraft version> <offset>  → REPLY
_mcp_search_url() {
  local q=$1 v=$2 l facets index=relevance
  local -a ors=()
  for l in $MCP_LOADERS; do ors+=("\"categories:$l\""); done
  facets="[[${(j:,:)ors}],[\"versions:$v\"]]"
  [[ -z $q ]] && index=downloads
  lotus_urlencode "$q"; local eq=$REPLY
  lotus_urlencode "$facets"; local ef=$REPLY
  REPLY="$MCP_API/search?query=$eq&limit=30&offset=${3:-0}&index=$index&facets=$ef"
}

# Search results JSON → lines: id \t slug \t title \t downloads \t author \t description   (and total_hits first)
_mcp_parse_search() {
  lotus_jq -r '(.total_hits // 0 | tostring),
    (.hits[]? | [.project_id, .slug, .title, (.downloads|tostring), (.author // ""),
      ((.description // "") | gsub("[\t\n\r]+"; " "))] | join("\t"))' 2>/dev/null
}

# Starts a search in the background; the result lands in <file> (written whole at the end)
_mcp_search_start() {   # <query> <version> <offset> <file>
  _mcp_search_url "$1" "$2" "$3"; local url=$REPLY
  _mcp_ua; local ua=$REPLY
  local f=$4
  rm -f -- $f $f.err
  {
    if curl -fsS -m 15 -A "$ua" "$url" 2>$f.err | _mcp_parse_search >| $f.part && [[ -s $f.part ]]; then
      zf_mv -f $f.part $f
    else
      rm -f $f.part; print -r -- "error" >| $f
    fi
  } &!
}

# Big numbers short: 12345678 → 12.3M
_mcp_count() {
  local -i n=$1
  if (( n >= 1000000 )); then printf -v REPLY '%.1fM' $(( n / 1000000.0 ))
  elif (( n >= 1000 )); then printf -v REPLY '%.1fk' $(( n / 1000.0 ))
  else REPLY=$n; fi
  REPLY=${${REPLY/.0M/M}/.0k/k}
}

# The newest file of a project for this server → reply=(version url filename sha512 deps…)
#   <project id> <minecraft version>
_mcp_pick() {
  local id=$1 v=$2 json l
  local -a ls=()
  for l in $MCP_LOADERS; do ls+=("\"$l\""); done
  lotus_urlencode "[${(j:,:)ls}]"; local el=$REPLY
  lotus_urlencode "[\"$v\"]"; local ev=$REPLY
  _mcp_ua
  json=$(curl -fsS -m 20 -A "$REPLY" "$MCP_API/project/$id/version?loaders=$el&game_versions=$ev" 2>/dev/null) || return 1
  reply=("${(@f)$(print -r -- $json | lotus_jq -r '
    (map(select(.version_type == "release")) + .)[0] // empty
    | (.files | (map(select(.primary)) + .)[0]) as $f
    | .version_number, $f.url, $f.filename, $f.hashes.sha512,
      ([.dependencies[]? | select(.dependency_type == "required" and .project_id != null) | .project_id] | join(" "))' 2>/dev/null)}")
  (( ${#reply} >= 4 )) && [[ -n $reply[2] ]]
}

# SHA-512 of a file → REPLY
_mcp_sha512() {
  if (( $+commands[shasum] )); then REPLY=${$(shasum -a 512 -- $1 2>/dev/null)[1]}
  else REPLY=${$(sha512sum -- $1 2>/dev/null)[1]}; fi
}

# What Lotus installed: lines of .lotus/plugins.tsv → MCP_MINE[project id]="slug\ttitle\tversion\tfile"
_mcp_mine() {
  typeset -gA MCP_MINE=()
  local f=$1/.lotus/plugins.tsv line
  [[ -r $f ]] || return 0
  for line in "${(@f)$(<$f)}"; do
    [[ $line == *$'\t'* ]] || continue
    MCP_MINE[${line%%$'\t'*}]=${line#*$'\t'}
  done
}
_mcp_mine_save() {
  local f=$1/.lotus/plugins.tsv id out=
  for id in ${(k)MCP_MINE}; do out+="$id"$'\t'"$MCP_MINE[$id]"$'\n'; done
  print -rn -- $out >| $f
}

# Installs a project from Modrinth, with its required dependencies.
#   _mcp_install <server dir> <project id> <slug> <title> <minecraft version> [depth]
# → status 0 and MCP_DONE (titles installed), or 1 and MCP_ERR
typeset -ga MCP_DONE
typeset -g MCP_ERR=
_mcp_install() {
  local dir=$1 id=$2 slug=$3 title=$4 v=$5
  local -i depth=${6:-0}
  [[ $id == [A-Za-z0-9]## ]] || { MCP_ERR="not a Modrinth project: $id"; return 1 }
  _mcp_pick $id $v || { MCP_ERR="$title has no version for Minecraft $v"; return 1 }
  local ver=$reply[1] url=$reply[2] file=$reply[3] sum=$reply[4] deps=$reply[5]
  # only Modrinth's own download server, only a plain file name
  [[ $url == $MCP_CDN* ]] || { MCP_ERR="$title: unexpected download address"; return 1 }
  [[ $file == [A-Za-z0-9._+-]##.jar && $file != .* ]] || file="${slug//[^A-Za-z0-9._-]/-}.jar"
  local plug=$dir/plugins
  zf_mkdir -p $plug $dir/.lotus
  local part=$plug/.$file.part
  _mcp_ua
  if ! curl -fsSL -m 120 -A "$REPLY" -o $part "$url" 2>/dev/null; then
    rm -f -- $part; MCP_ERR="$title: the download failed"; return 1
  fi
  _mcp_sha512 $part
  if [[ -n $sum && $REPLY != $sum ]]; then
    rm -f -- $part; MCP_ERR="$title: checksum mismatch – nothing was installed"; return 1
  fi
  _mcp_mine $dir
  # an update: the file of the older version goes
  local old=${${(@ps:\t:)MCP_MINE[$id]}[4]}
  [[ -n $old && $old != $file && $old != */* && -f $plug/$old ]] && rm -f -- $plug/$old
  zf_mv -f $part $plug/$file
  MCP_MINE[$id]="$slug"$'\t'"$title"$'\t'"$ver"$'\t'"$file"
  _mcp_mine_save $dir
  MCP_DONE+=("$title $ver")
  lotus_log INFO minecraft "Plugin installed: $title $ver ($file) in ${dir:t}"
  # required dependencies that are not there yet (one level deep is enough in practice)
  local dep
  if (( depth < 2 )); then
    for dep in ${=deps}; do
      [[ -n ${MCP_MINE[$dep]} ]] && continue
      _mcp_install $dir $dep $dep $dep $v $(( depth + 1 )) || MCP_ERR="$title needs $dep: $MCP_ERR"
    done
  fi
  return 0
}

# The plugins in plugins/: one line each → reply ("file\tname\tversion\tfrom")
#   from: lotus (LotusBridge), modrinth (installed here) or own (dragged in, or put there by hand)
_mcp_installed() {
  local dir=$1 jar yml name ver from id
  _mcp_mine $dir
  local -A byfile=()
  for id in ${(k)MCP_MINE}; do
    local -a f=("${(@ps:\t:)MCP_MINE[$id]}")
    byfile[$f[4]]="$f[2]"$'\t'"$f[3]"
  done
  reply=()
  for jar in $dir/plugins/*.jar(N); do
    if [[ ${jar:t} == LotusBridge.jar ]]; then reply+=("${jar:t}"$'\t'"LotusBridge"$'\t'"–"$'\t'"lotus"); continue; fi
    if [[ -n ${byfile[${jar:t}]} ]]; then reply+=("${jar:t}"$'\t'"${byfile[${jar:t}]}"$'\t'"modrinth"); continue; fi
    _mcp_jar_info $jar
    reply+=("${jar:t}"$'\t'"$REPLY"$'\t'"own")
  done
}

# Name and version from a plugin's plugin.yml (or paper-plugin.yml) → REPLY "name\tversion"
_mcp_jar_info() {
  local yml line name= ver=
  yml=$(unzip -p -- $1 plugin.yml 2>/dev/null) || yml=
  [[ -z $yml ]] && yml=$(unzip -p -- $1 paper-plugin.yml 2>/dev/null)
  for line in "${(@f)yml}"; do
    [[ $line == (#b)name:[[:space:]]#[\"\']#([^\"\']##)[\"\']#[[:space:]]# ]] && name=$match[1]
    [[ $line == (#b)version:[[:space:]]#[\"\']#([^\"\']##)[\"\']#[[:space:]]# ]] && ver=$match[1]
  done
  REPLY="${name:-${1:t:r}}"$'\t'"${ver:-?}"
}

# Is this .jar a plugin? → status 0, or 1 with MCP_ERR saying what it is instead
_mcp_check_jar() {
  local list
  list=$(unzip -l -- $1 2>/dev/null) || { MCP_ERR="${1:t} is not a .jar file"; return 1 }
  [[ $list == *[[:space:]](plugin.yml|paper-plugin.yml)$'\n'* || $list == *[[:space:]](plugin.yml|paper-plugin.yml) ]] && return 0
  [[ $list == *fabric.mod.json* ]] && { MCP_ERR="${1:t} is a Fabric mod – Paper runs plugins, not mods"; return 1 }
  [[ $list == *mods.toml* ]] && { MCP_ERR="${1:t} is a Forge mod – Paper runs plugins, not mods"; return 1 }
  MCP_ERR="${1:t} has no plugin.yml – it is not a plugin"
  return 1
}

# Dragged files → into plugins/.  <server dir> <the dropped line>   → MCP_DONE, MCP_ERR
_mcp_drop() {
  local dir=$1 w p
  MCP_DONE=() MCP_ERR=
  local -a words=(${(z)2})
  zf_mkdir -p $dir/plugins
  for w in $words; do
    ui_clean_path "${(Q)w}"; p=$REPLY
    [[ -f $p ]] || { MCP_ERR="not a file: ${p:t}"; continue }
    [[ $p == *.jar ]] || { MCP_ERR="${p:t} is not a .jar"; continue }
    _mcp_check_jar $p || continue
    cp -f -- $p $dir/plugins/${p:t} || { MCP_ERR="could not copy ${p:t}"; continue }
    _mcp_jar_info $dir/plugins/${p:t}
    MCP_DONE+=("${REPLY%%$'\t'*}")
    lotus_log INFO minecraft "Plugin added by hand: ${p:t} in ${dir:t}"
  done
  (( ${#MCP_DONE} ))
}

# Takes a plugin out (its data folder stays, so it keeps its settings if it comes back)
_mcp_remove() {   # <server dir> <file>
  local dir=$1 file=$2 id
  [[ $file == [^/]##.jar && $file != .* ]] || return 1
  rm -f -- $dir/plugins/$file || return 1
  _mcp_mine $dir
  for id in ${(k)MCP_MINE}; do
    [[ ${${(@ps:\t:)MCP_MINE[$id]}[4]} == $file ]] && unset "MCP_MINE[$id]"
  done
  _mcp_mine_save $dir
  lotus_log INFO minecraft "Plugin removed: $file from ${dir:t}"
}
