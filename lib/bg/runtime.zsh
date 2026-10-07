# lotus – Remove BG: the Python runtime and the models.
# Both are installed only after a yes, into Lotus' own folder (~/.local/share/lotus), never system-wide:
#   runtime/bg/       a Python environment with PyTorch & co. (lib/bg/requirements-<arch>.txt)
#   models/<id>/      the model files from data/bg-models.tsv, checked against their SHA-256

typeset -g BG_RUNTIME=$LOTUS_DATA/runtime/bg BG_MODELS=$LOTUS_DATA/models
typeset -g BG_TB=transparent-background==1.3.4      # InSPyReNet's model code (installed without extras)
typeset -gA BG_MODEL_ROW=()
typeset -ga BG_MODEL_IDS=()

# data/bg-models.tsv → BG_MODEL_IDS, BG_MODEL_ROW[id]
bg_registry() {
  (( ${#BG_MODEL_IDS} )) && return
  local line
  for line in "${(@f)$(<$LOTUS_ROOT/data/bg-models.tsv)}"; do
    [[ $line == \#* || -z $line ]] && continue
    BG_MODEL_IDS+=(${line%%$'\t'*})
    BG_MODEL_ROW[${line%%$'\t'*}]=$line
  done
}

bg_model_field() {   # <id> <n> → REPLY  (1 id, 2 engine, 3 label, 4 MB, 5 input, 6 license, 7 project, 8 files)
  bg_registry
  local -a f=("${(@ps:\t:)BG_MODEL_ROW[$1]}")
  REPLY=$f[$2]
}

# Apple silicon or Intel – also right when the terminal itself runs under Rosetta
bg_arch() { [[ $(sysctl -n hw.optional.arm64 2>/dev/null) == 1 ]] && REPLY=arm64 || REPLY=x86_64 }
bg_memory_gb() { REPLY=$(( $(sysctl -n hw.memsize 2>/dev/null || print 0) / 1073741824 )) }

# How to start the runtime's Python (natively, even from a Rosetta terminal) → reply
bg_python() {
  reply=($BG_RUNTIME/bin/python3 -s -E)
  bg_arch
  [[ $REPLY == arm64 && $(sysctl -n sysctl.proc_translated 2>/dev/null) == 1 ]] && reply=(arch -arm64 $reply)
}

bg_requirements() { bg_arch; REPLY=$LOTUS_ROOT/lib/bg/requirements-$REPLY.txt }

# The runtime is there and matches this Lotus version's requirements
bg_runtime_ok() {
  [[ -x $BG_RUNTIME/bin/python3 && -r $BG_RUNTIME/lotus-runtime ]] || return 1
  bg_requirements
  local want=$(cat $REPLY | cksum) have
  IFS= read -r have < $BG_RUNTIME/lotus-runtime
  [[ ${have%% *} == ${want%% *} ]]
}

# Installed state of a model: ok, missing or partial (quick: names and sizes)
bg_model_state() {
  bg_model_field $1 8
  local spec name bytes
  local -i have=0 n=0
  local -a st
  for spec in ${(s:;:)REPLY}; do
    name=${spec%%|*} bytes=${spec##*|}
    (( n++ ))
    zstat -A st +size $BG_MODELS/$1/$name 2>/dev/null && (( st[1] == bytes )) && (( have++ ))
  done
  if (( have == n )); then REPLY=ok; elif (( have )) || [[ -d $BG_MODELS/$1 ]]; then REPLY=partial; else REPLY=missing; fi
}

# What "Auto" means on this Mac right now → REPLY (model id).
# A model that is already downloaded wins, so Auto never downloads a second model on its own.
bg_auto_model() {
  local best=birefnet id
  bg_arch; local arch=$REPLY
  bg_memory_gb
  [[ $arch != arm64 ]] || (( REPLY < 8 )) && best=birefnet-lite
  bg_model_state $best
  [[ $REPLY == ok ]] && { REPLY=$best; return }
  for id in birefnet birefnet-lite inspyrenet; do
    bg_model_state $id
    [[ $REPLY == ok ]] && { REPLY=$id; return }
  done
  REPLY=$best
}

bg_resolve_model() {   # setting or flag → REPLY (model id)
  local want=${1:-$LOTUS_BG_MODEL}
  bg_registry
  if [[ $want == auto || -z ${BG_MODEL_ROW[$want]} ]]; then bg_auto_model; else REPLY=$want; fi
}

# A Python that fits → reply=(path version). Apple silicon: 3.10–3.14 (native arm64), Intel: 3.10–3.12.
bg_find_python() {
  bg_arch; local arch=$REPLY
  local -a order cands=()
  [[ $arch == arm64 ]] && order=(3.13 3.12 3.11 3.14 3.10) || order=(3.12 3.11 3.10)
  local v d p ver
  for v in $order; do
    for d in /opt/homebrew/bin /usr/local/bin /Library/Frameworks/Python.framework/Versions/$v/bin ${${commands[python$v]}:h}; do
      [[ -x $d/python$v ]] && cands+=($d/python$v)
    done
  done
  [[ -n $commands[python3] ]] && cands+=($commands[python3])
  # Apple's python3 only with the Command Line Tools – otherwise it would open an install dialog
  xcode-select -p >/dev/null 2>&1 && cands+=(/usr/bin/python3)
  for p in ${(u)cands}; do
    if [[ $arch == arm64 ]]; then
      ver=$(arch -arm64 $p -c 'import sys, venv, ensurepip, platform; print("%d.%d %s" % (sys.version_info[:2] + (platform.machine(),)))' 2>/dev/null) || continue
      [[ $ver == 3.1[0-4]\ arm64 ]] || continue
    else
      ver=$($p -c 'import sys, venv, ensurepip; print("%d.%d x86_64" % sys.version_info[:2])' 2>/dev/null) || continue
      [[ $ver == 3.1[0-2]\ * ]] || continue
    fi
    reply=($p ${ver%% *})
    return 0
  done
  return 1
}

bg_free_gb() {   # free space where Lotus keeps its data → REPLY (GB)
  local dir=$LOTUS_DATA
  while [[ ! -d $dir ]]; do dir=${dir:h}; done
  local -a df=(${=${(f)"$(df -k $dir 2>/dev/null)"}[2]})
  REPLY=$(( ${df[4]:-0} / 1048576 ))
}

# Runs a command and feeds its lines to the progress screen.  bg_ui_follow <log tag> <cmd…>
# Like the worker: a plain background process writing into a named pipe.
bg_ui_follow() {
  local tag=$1; shift
  local line fifo=$BG_SESSION/follow
  local -i fd rc
  rm -f $fifo; mkfifo -m 600 $fifo || return 1
  "$@" > $fifo 2>&1 &
  BG_WORKER_PID=$!
  exec {fd}< $fifo
  local -i open=1
  _BG_BUF=
  while (( open )); do
    bg_read_lines $fd 0.08 || open=0
    for line in $reply; do
      lotus_log TRACE bg "$tag: $line"
      case $line in
        (Collecting\ *)  bg_ui_note "${line#Collecting }" ;;
        (*Downloading\ *) bg_ui_note "${${line##*Downloading }%%\?*}" ;;
        (Installing\ collected*) bg_ui_note $LOTUS_L[bg_n_unpack] ;;
        (Successfully\ installed*) bg_ui_note "" ;;
        (ERROR:*|error:*) lotus_log ERROR bg "$tag: $line" ;;
      esac
    done
    bg_ui_frame
  done
  exec {fd}<&-
  rm -f $fifo
  bg_ui_check
  wait $BG_WORKER_PID 2>/dev/null; rc=$?
  BG_WORKER_PID=0
  return rc
}

# Creates the Python environment and installs the packages (about 1 GB, once)
bg_install_runtime() {
  bg_ui_stage python
  bg_requirements; local req=$REPLY
  local py
  if ! bg_find_python; then
    BG_ERR=(BG-001 "No suitable Python 3 was found." "") ; return 1
  fi
  py=$reply[1]
  lotus_log INFO bg "Runtime: Python $reply[2] from $py"
  bg_ui_info python "Python $reply[2]"
  rm -rf $BG_RUNTIME
  zf_mkdir -p ${BG_RUNTIME:h}
  local -a run=($py)
  bg_arch; [[ $REPLY == arm64 ]] && run=(arch -arm64 $py)
  if ! bg_ui_follow venv $run -m venv $BG_RUNTIME; then
    rm -rf $BG_RUNTIME; BG_ERR=(BG-002 "Python could not create an environment." "$py -m venv"); return 1
  fi
  bg_ui_stage packages
  bg_python
  local -a pip=($reply -m pip --disable-pip-version-check --no-input install --progress-bar off)
  if ! bg_ui_follow pip $pip --upgrade pip || ! bg_ui_follow pip $pip -r $req || ! bg_ui_follow pip $pip --no-deps $BG_TB; then
    rm -rf $BG_RUNTIME
    BG_ERR=(BG-002 "The Python packages could not be installed." "pip failed – details in /lotus log")
    return 1
  fi
  print -r -- "$(cat $req | cksum) $(date +%F)" >| $BG_RUNTIME/lotus-runtime
  lotus_log INFO bg "Runtime installed ($(du -sh $BG_RUNTIME 2>/dev/null | cut -f1))"
  return 0
}

# Downloads the files of a model with a real progress bar, then checks every SHA-256 and moves
# the files in place. Unfinished downloads continue where they stopped.
bg_fetch_model() {
  local id=$1 spec name url sha bytes part
  local -i total=0 have=0 pid
  local -a specs st todo=()
  bg_model_field $id 8; specs=(${(s:;:)REPLY})
  bg_model_field $id 3; local label=$REPLY
  for spec in $specs; do
    total+=${spec##*|}
    name=${spec%%|*}
    if zstat -A st +size $BG_MODELS/$id/$name 2>/dev/null && (( st[1] == ${spec##*|} )); then have+=${spec##*|}
    else todo+=($spec); fi
  done
  bg_ui_stage download
  bg_ui_info model $label
  zf_mkdir -p $BG_MODELS/$id
  lotus_log INFO bg "Downloading $label ($(( total / 1048576 )) MB, ${#todo} file(s))"
  for spec in $todo; do
    name=${spec%%|*} url=${${spec#*|}%%|*} bytes=${spec##*|}
    part=$BG_MODELS/$id/$name.part
    bg_ui_note $name
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -C - -o $part -- $url 2>>$BG_SESSION_LOG &
    pid=$! BG_WORKER_PID=$!
    while kill -0 $pid 2>/dev/null; do
      zstat -A st +size $part 2>/dev/null || st=(0)
      bg_ui_progress $(( have + st[1] )) $total
      bg_ui_frame
      bg_ui_tick 10
    done
    if ! wait $pid; then
      # a part that cannot be continued (e.g. already complete) – load that file again once
      rm -f $part
      curl -fsSL --retry 3 --connect-timeout 15 -o $part -- $url 2>>$BG_SESSION_LOG &
      pid=$! BG_WORKER_PID=$!
      while kill -0 $pid 2>/dev/null; do
        zstat -A st +size $part 2>/dev/null || st=(0)
        bg_ui_progress $(( have + st[1] )) $total
        bg_ui_frame; bg_ui_tick 10
      done
      wait $pid || { BG_ERR=(BG-003 "The download of $label failed." "$url"); return 1 }
    fi
    have+=bytes
  done
  bg_ui_progress 0 0
  bg_ui_stage verify
  for spec in $todo; do
    name=${spec%%|*} sha=${${spec%|*}##*|}
    part=$BG_MODELS/$id/$name.part
    bg_ui_note $name
    bg_ui_frame
    local got=$(shasum -a 256 $part 2>/dev/null)
    if [[ ${got%% *} != $sha ]]; then
      rm -f $part
      lotus_log ERROR bg "Checksum mismatch for $id/$name: ${got%% *}"
      BG_ERR=(BG-009 "$label did not arrive intact (checksum mismatch)." "$name"); return 1
    fi
    zf_mv -f $part $BG_MODELS/$id/$name
  done
  bg_ui_note ""
  lotus_log INFO bg "$label downloaded and verified"
  return 0
}

bg_model_size_mb() {   # actual size on disk → REPLY
  [[ -d $1 ]] || { REPLY=0; return }
  REPLY=$(( $(du -sk $1 2>/dev/null | cut -f1) / 1024 ))
}
