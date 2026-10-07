# lotus – Remove BG: first use, choices (model, output folder), installing, the model cache, doctor.
# Used by /bg and by the setup wizard. Nothing is downloaded without a yes.

# "auto" or a model id → REPLY ("Auto · BiRefNet" for auto)
lotus_bg_model_label() {
  if [[ $1 == auto ]]; then
    bg_auto_model; bg_model_field $REPLY 3
    REPLY="$LOTUS_L[col_auto] · $REPLY"
  else
    bg_model_field $1 3
  fi
}

# Model choice (radio list) → LOTUS_BG_MODEL. Status 1 = back.
lotus_bg_pick_model() {
  bg_registry
  local -a ids=(auto $BG_MODEL_IDS) opts=()
  local id state mb
  bg_auto_model; bg_model_field $REPLY 3
  opts+=("$LOTUS_L[col_auto]|${LOTUS_L[bg_m_auto]//\%s/$REPLY}")
  for id in $BG_MODEL_IDS; do
    bg_model_field $id 4; mb=$REPLY
    bg_model_state $id; state=$REPLY
    bg_model_field $id 3
    opts+=("$REPLY|${LOTUS_L[bg_m_$id]} · ${${(M)state:#ok}:+$LOTUS_L[bg_installed]}${${state:#ok}:+$mb MB}")
  done
  ui_select ${ids[(i)$LOTUS_BG_MODEL]} "${opts[@]}" || return 1
  LOTUS_BG_MODEL=$ids[REPLY]
}

# Finder's folder dialog → REPLY (status 1 when cancelled)
_bg_choose_folder() {
  local p
  p=$(osascript -e 'activate' -e "POSIX path of (choose folder with prompt \"${LOTUS_L[bg_o_prompt]//\"/}\" default location (path to pictures folder))" 2>/dev/null) || return 1
  REPLY=${p%/}
  [[ -n $REPLY ]]
}

# Output choice → LOTUS_BG_OUTPUT (a folder, or @source = next to the original). Status 1 = back.
lotus_bg_pick_output() {
  local def='~/Pictures/Lotus/Background Removed' cur=$LOTUS_BG_OUTPUT
  local -i sel=1
  [[ $cur == @source ]] && sel=2
  [[ $cur != @source && $cur != $def ]] && sel=3
  local custom=$LOTUS_L[bg_o_other_d]
  (( sel == 3 )) && { ui_path "${cur/#\~/$HOME}" 40; custom=$REPLY }
  ui_select $sel "$LOTUS_L[bg_o_default]|$def" "$LOTUS_L[bg_o_source]|$LOTUS_L[bg_o_source_d]" "$LOTUS_L[bg_o_other]|$custom" || return 1
  case $REPLY in
    1) LOTUS_BG_OUTPUT=$def
       if ! zf_mkdir -p "${def/#\~/$HOME}" 2>/dev/null; then ui_warn "$LOTUS_L[bg_o_nocreate] $def"; return 1; fi
       ui_success "$LOTUS_L[bg_o_ready] $def" ;;
    2) LOTUS_BG_OUTPUT=@source ;;
    3) if ! _bg_choose_folder; then
         ui_line $LOTUS_L[bg_o_type] "${${cur:#@source}:-$def}" || return 1
       fi
       local dir=${REPLY/#\~/$HOME}
       dir=${dir:a}
       if [[ ! -d $dir ]] && ! zf_mkdir -p $dir 2>/dev/null; then ui_warn "$LOTUS_L[bg_o_nocreate] $dir"; return 1; fi
       if [[ ! -w $dir ]]; then ui_warn "$LOTUS_L[bg_o_nowrite] $dir"; return 1; fi
       [[ $dir == $HOME/* ]] && dir="~${dir#$HOME}"
       LOTUS_BG_OUTPUT=$dir ;;
  esac
  lotus_log INFO bg "Output folder: $LOTUS_BG_OUTPUT"
  return 0
}

# Install now or on first use → REPLY 1/0. Status 1 = back.
lotus_bg_pick_when() {
  ui_select $(( $1 ? 2 : 1 )) "$LOTUS_L[bg_w_later]|$LOTUS_L[bg_w_later_d]" "$LOTUS_L[bg_w_now]|$LOTUS_L[bg_w_now_d]" || return 1
  (( REPLY == 2 )) && REPLY=1 || REPLY=0
  return 0
}

# What is still missing for a model → reply=(runtime? model?) and the download summary on screen
_bg_missing() {
  local id=$1
  local -i rt=0 md=0
  bg_runtime_ok || rt=1
  bg_model_state $id; [[ $REPLY == ok ]] || md=1
  reply=($rt $md)
}

_bg_summary() {   # <model id> <runtime missing> <model missing>
  local id=$1
  local -i rt=$2 md=$3
  bg_model_field $id 3; local label=$REPLY
  bg_model_field $id 4; local mb=$REPLY
  ui_section $LOTUS_L[bg_dl_what]; ui_blank
  (( rt )) && print -r -- "    ${(r:22:)LOTUS_L[bg_dl_runtime]}${(r:12:)LOTUS_L[bg_dl_runtime_mb]}"$'\e['"$LOTUS_C[dim]m$LOTUS_L[bg_dl_runtime_d]"$_UI_R
  (( md )) && print -r -- "    ${(r:22:)label}${(r:12:)${:-$mb MB}}"$'\e['"$LOTUS_C[dim]m$LOTUS_L[bg_dl_model_d]"$_UI_R
  ui_blank
  ui_path $LOTUS_DATA; ui_kv $LOTUS_L[bg_dl_where] $REPLY
  bg_model_field $id 8
  local host=${${${REPLY#*|}#https://}%%/*}
  (( rt )) && host="pypi.org · $host"
  ui_kv $LOTUS_L[bg_dl_from] $host
  ui_blank
  ui_dim "  $LOTUS_L[bg_dl_after]"
  ui_blank
}

# Installs what is missing for a model, with the progress screen and a short test at the end.
#   lotus_bg_install [model id] [--yes]
lotus_bg_install() {
  lotus_lang_group bg
  local id=$1 yes=$2
  [[ -z $id ]] && { bg_resolve_model; id=$REPLY }
  _bg_missing $id
  local -i rt=$reply[1] md=$reply[2]
  if (( ! rt && ! md )); then
    LOTUS_BG_READY=1; lotus_save; return 0
  fi
  if ! ui_has_tty; then
    bg_error_screen BG-014 "$LOTUS_L[bg_e_notty]" ""; return 1
  fi
  bg_model_field $id 4
  local -i need=$(( (rt ? 1300 : 0) + (md ? REPLY : 0) + 500 ))
  bg_free_gb
  if (( REPLY * 1024 < need )); then
    bg_error_screen BG-012 "${LOTUS_L[bg_e_space]//\%s/$(( need / 1024 + 1 ))}" "$REPLY GB free"; return 1
  fi
  if [[ $yes != --yes ]]; then
    _bg_summary $id $rt $md
    ui_confirm "$LOTUS_L[bg_dl_q]" y || { ui_info $LOTUS_L[cancelled]; return 1 }
  fi
  bg_model_field $id 3
  local -a stages=()
  (( rt )) && stages+=("python|$LOTUS_L[bg_s_python]" "packages|$LOTUS_L[bg_s_packages]")
  (( md )) && stages+=("download|${LOTUS_L[bg_s_download]//\%s/$REPLY}" "verify|$LOTUS_L[bg_s_verify]")
  stages+=("load_model|$LOTUS_L[bg_s_test_load]" "segment|$LOTUS_L[bg_s_test]")
  typeset -ga BG_ERR=()
  bg_session_new
  trap _bg_interrupt INT TERM HUP
  lotus_log INFO bg "Installing: ${${(M)rt:#1}:+runtime }${${(M)md:#1}:+$id}"
  bg_ui_begin "$LOTUS_L[bg_title] · $LOTUS_L[bg_setup]" $stages
  local -i ok=1
  if (( rt )) && ! bg_install_runtime; then ok=0; fi
  if (( ok && md )) && ! bg_fetch_model $id; then ok=0; fi
  if (( ok )); then
    bg_ui_stage load_model
    bg_worker selftest --model $id --models-dir $BG_MODELS --backend ${LOTUS_BG_BACKEND:-auto} || ok=0
  fi
  (( ok )) && bg_ui_complete
  bg_ui_end
  bg_session_end
  trap 'exit 130' INT; trap - TERM HUP
  if (( ! ok )); then
    bg_error_screen "${BG_ERR[@]}"
    return 1
  fi
  LOTUS_BG_READY=1
  lotus_save
  ui_hero "$LOTUS_L[bg_title] · $LOTUS_L[bg_setup]"
  ui_success "${LOTUS_L[bg_ready]//\%s/${BG_INFO[model]:-$id}} (${BG_INFO[backend]:-CPU}, ${BG_INFO[seconds]:-?}s)"
  ui_blank
  return 0
}

# First /bg remove: explain, choose, install
lotus_bg_first_use() {
  lotus_log INFO bg "First use of Remove BG"
  ui_hero $LOTUS_L[bg_title] $LOTUS_L[bg_tagline]
  ui_text $LOTUS_L[bg_intro]
  ui_blank
  ui_section $LOTUS_L[bg_q_model]; ui_blank
  lotus_bg_pick_model || return 1
  ui_blank
  ui_section $LOTUS_L[bg_q_output]; ui_blank
  lotus_bg_pick_output || return 1
  lotus_save
  ui_blank
  bg_resolve_model
  lotus_bg_install $REPLY
}

# /bg models – what is on this Mac, download, remove, check
bg_models_screen() {
  bg_registry
  while :; do
    ui_hero "$LOTUS_L[bg_title] · $LOTUS_L[bg_cache]"
    local id state mb d=$'\e['"$LOTUS_C[dim]m" k=$'\e[1;'"$LOTUS_C[key]m"
    local -i total=0
    for id in $BG_MODEL_IDS; do
      bg_model_state $id; state=$REPLY
      bg_model_field $id 3; local label=$REPLY
      bg_model_field $id 4; mb=$REPLY
      bg_model_field $id 6; local lic=$REPLY
      if [[ $state == ok ]]; then
        bg_model_size_mb $BG_MODELS/$id; total+=REPLY
        print -r -- "    ${k}✓${_UI_R} ${(r:16:)label}${(l:7:)REPLY} MB   ${d}${LOTUS_L[bg_m_$id]} · $lic${_UI_R}"
      else
        print -r -- "    ${d}·${_UI_R} ${(r:16:)label}${d}${(l:7:)mb} MB   ${LOTUS_L[bg_m_$id]} · ${${(M)state:#partial}:+$LOTUS_L[bg_partial] · }$lic${_UI_R}"
      fi
    done
    ui_blank
    if bg_runtime_ok; then
      bg_model_size_mb $BG_RUNTIME
      ui_kv $LOTUS_L[bg_runtime] "$LOTUS_L[bg_installed] · $REPLY MB"
    else
      ui_kv $LOTUS_L[bg_runtime] $LOTUS_L[bg_not_installed]
    fi
    ui_path $LOTUS_DATA; ui_kv $LOTUS_L[bg_dl_where] $REPLY
    ui_blank
    ui_select 1 "$LOTUS_L[bg_a_done]|" "$LOTUS_L[bg_a_download]|" "$LOTUS_L[bg_a_remove]|" "$LOTUS_L[bg_a_check]|" "$LOTUS_L[bg_a_remove_all]|$LOTUS_L[bg_a_remove_all_d]" || return 0
    case $REPLY in
      1) return 0 ;;
      2) _bg_pick_id "$LOTUS_L[bg_a_download]" && lotus_bg_install $REPLY ;;
      3) _bg_pick_id "$LOTUS_L[bg_a_remove]" installed || continue
         local rid=$REPLY
         bg_model_field $rid 3
         ui_confirm "${LOTUS_L[bg_rm_q]//\%s/$REPLY}" n && rm -rf $BG_MODELS/$rid && lotus_log INFO bg "Removed model $rid" && ui_success $LOTUS_L[bg_removed] ;;
      4) _bg_check_all ;;
      5) ui_confirm "$LOTUS_L[bg_rm_all_q]" n || continue
         rm -rf $BG_MODELS $BG_RUNTIME
         LOTUS_BG_READY=0; lotus_save
         lotus_log INFO bg "Removed the Remove BG runtime and all models"
         ui_success $LOTUS_L[bg_removed] ;;
    esac
    ui_blank; ui_dim "  $LOTUS_L[back]"; ui_key
    print -n $'\e[H\e[2J'
  done
}

_bg_pick_id() {   # <title> [installed] → REPLY id
  local -a ids=() labels=()
  local id
  for id in $BG_MODEL_IDS; do
    bg_model_state $id
    if [[ $2 == installed ]]; then [[ $REPLY == missing ]] && continue
    else [[ $REPLY == ok ]] && continue; fi
    ids+=($id); bg_model_field $id 3; labels+=("$REPLY|")
  done
  (( ${#ids} )) || { ui_info $LOTUS_L[bg_nothing]; return 1 }
  ui_blank; ui_section $1; ui_blank
  ui_select 1 "${labels[@]}" || return 1
  REPLY=$ids[REPLY]
}

# Full check: every SHA-256 (takes a few seconds per model)
_bg_check_all() {
  bg_runtime_ok || { ui_warn $LOTUS_L[bg_not_installed]; return }
  ui_step $LOTUS_L[bg_checking]
  bg_python
  local line
  local -a f
  for line in "${(@f)$(LOTUS_LOG=$LOTUS_LOG LOTUS_LOG_LEVEL=$LOTUS_LOG_LEVEL $reply $LOTUS_ROOT/lib/bg/worker.py check --models-dir $BG_MODELS --full 2>/dev/null)}"; do
    f=("${(@ps:\t:)line}")
    [[ $f[1] == model ]] || continue
    bg_model_field $f[2] 3
    case $f[3] in
      ok)      ui_success "$REPLY" ;;
      damaged) ui_warn "$REPLY – ${LOTUS_L[bg_damaged]} ${f[4]}" ;;
    esac
  done
}

# Rows for lotus doctor (only when the feature is on, or with: lotus doctor --bg)
bg_doctor_rows() {
  local ok=$'\e[1;'"$LOTUS_C[key]m✓"$'\e[0m' bad=$'\e[1;38;5;203m✗\e[0m' opt=$'\e['"$LOTUS_C[dim]m·"$'\e[0m'
  _r() { print -r -- "  $1 ${(r:17:)2} $3" }
  lotus_feature_on bg && _r $ok Feature "$LOTUS_L[on] (/bg remove)" || _r $opt Feature "${(L)LOTUS_L[off]} – lotus features bg on"
  bg_arch; local arch=$REPLY
  bg_memory_gb
  _r $ok Mac "${${arch/arm64/Apple silicon}/x86_64/Intel} · $REPLY GB"
  if bg_runtime_ok; then
    bg_python
    local -A p=()
    local line
    local -a f
    for line in "${(@f)$($reply $LOTUS_ROOT/lib/bg/worker.py probe 2>/dev/null)}"; do
      f=("${(@ps:\t:)line}")
      [[ $f[1] == info && $f[2] != module ]] && p[$f[2]]=$f[3]
      [[ $f[1] == info && $f[2] == module && $f[4] != ok ]] && p[missing]+=" $f[3]"
    done
    ui_path $BG_RUNTIME 60
    _r $ok Python "${p[python]:-?} ($REPLY)"
    if [[ -n $p[torch] ]]; then _r $ok PyTorch $p[torch]; else _r $bad PyTorch "$LOTUS_L[bg_d_torch]"; fi
    [[ -n $p[missing] ]] && _r $bad Packages "missing:$p[missing] – /bg models → $LOTUS_L[bg_a_remove_all]"
    if [[ $p[mps] == 1 ]]; then _r $ok MPS "$LOTUS_L[bg_d_mps]"; else _r $opt MPS "$LOTUS_L[bg_d_cpu]"; fi
  else
    bg_find_python && _r $opt Python "$LOTUS_L[bg_d_rt_later] (Python $reply[2] found)" || _r $opt Python "$LOTUS_L[bg_d_nopython]"
  fi
  bg_model_size_mb $BG_MODELS
  local mb=$REPLY
  ui_path $BG_MODELS 60
  _r $ok "Model cache" "$REPLY ($mb MB)"
  local id
  bg_registry
  for id in $BG_MODEL_IDS; do
    bg_model_field $id 3
    local label=$REPLY
    bg_model_state $id
    case $REPLY in
      ok)      _r $ok $label $LOTUS_L[bg_installed] ;;
      partial) _r $bad $label "$LOTUS_L[bg_partial] – /bg models" ;;
      *)       _r $opt $label $LOTUS_L[bg_not_installed] ;;
    esac
  done
  local out=$LOTUS_BG_OUTPUT
  if [[ $out == @source ]]; then _r $ok Output "$LOTUS_L[bg_o_source]"
  else
    local dir=${out/#\~/$HOME}
    if [[ -d $dir && -w $dir ]]; then _r $ok Output "$out"
    elif [[ ! -e $dir ]]; then _r $opt Output "$out ($LOTUS_L[bg_d_created])"
    else _r $bad Output "$out – $LOTUS_L[bg_o_nowrite]"; fi
  fi
  lotus_can_swift && _r $ok Editor "$LOTUS_L[bg_d_editor]" || _r $opt Editor "$LOTUS_L[bg_d_noeditor]"
  unfunction _r
}
