# Hello – a plugin for Lotus with full access (plugin.conf). It loads Lotus' own functions:
#   lib/core.zsh  settings (lotus_load), colors ($LOTUS_C), features, the log
#   lib/ui.zsh    ui_header, ui_success, ui_kv, ui_dim, ui_error, ui_confirm, ui_input
source $LOTUS_ROOT/lib/core.zsh && source $LOTUS_ROOT/lib/ui.zsh && lotus_load || exit 1
lotus_features

local id
local -a on=()
for id in ${LOTUS_FEATURE_IDS:#core}; do
  lotus_feature_on $id && { lotus_feature_label $id; on+=($REPLY) }
done

ui_header Hello "a plugin with full access"
print
ui_success "Hello${LOTUS_NAME:+, $LOTUS_NAME}!"
ui_kv Lotus "$LOTUS_VERSION"
ui_kv Theme "${LOTUS_THEME_LABELS[$LOTUS_THEME]:-$LOTUS_THEME}"
ui_kv Features "${(j:, :)on}"
print
ui_dim "  This plugin read Lotus' settings – only plugins with full access can."
lotus_log INFO plugin "hello greeted ${LOTUS_NAME:-someone}"
