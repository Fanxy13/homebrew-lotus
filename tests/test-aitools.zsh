# Lotus tools for the AI: only enabled features, checked arguments, honest results
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
source $LOTUS_ROOT/lib/fuzzy.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }

source $LOTUS_ROOT/lib/cmd/aitools.zsh
lotus_ai_toolkit
kit=$REPLY
if (( $+commands[jq] )); then
  check "the list is valid JSON" jq -e . $kit
  names=$(jq -r '.tools[].name' $kit)
  check_has "it offers the weather" "$names" "weather"
  check "every tool has a feature, a level and a description" eval '[[ $(jq "[.tools[] | select(.feature == \"\" or .level == \"\" or .description == \"\")] | length" $kit) == 0 ]]'
  check "levels are read, act or install" eval '[[ -z $(jq -r ".tools[].level" $kit | grep -vE "^(read|act|install)$") ]]'
fi

# a feature that is off: its tools are not offered, and it is named for the AI
lotus features weather off >/dev/null
lotus_load
lotus_ai_toolkit
if (( $+commands[jq] )); then
  check "weather off: no weather tool" eval '! jq -r ".tools[].name" $kit | grep -qx weather'
  check_has "weather off: named as off" "$(jq -r '.off[]' $kit)" "lotus features weather on"
fi
out=$(lotus ai-tool weather Zurich); rc=$?
check_eq "weather off: the tool refuses" $rc 1
check_has "weather off: and says how to turn it on" "$out" "lotus features weather on"
lotus features weather on >/dev/null

out=$(lotus ai-tool no_such_tool); rc=$?
check_eq "an unknown tool is refused" $rc 2

out=$(lotus ai-tool set_theme no-such-theme); rc=$?
check_eq "a theme that does not exist: refused" $rc 2
out=$(lotus ai-tool set_theme ocean); rc=$?
check_eq "a real theme: done" $rc 0
lotus_load
check_eq "and saved" "$LOTUS_THEME" ocean

out=$(lotus ai-tool keep_awake abc); rc=$?
check_eq "keep awake: minutes must be a number" $rc 2
out=$(lotus ai-tool minecraft_start '../../etc'); rc=$?
check_eq "minecraft: no paths as server names" $rc 2
out=$(lotus ai-tool install_app 'x;rm -rf'); rc=$?
check "install: no shell characters" test $rc -ne 0
out=$(lotus ai-tool open_app 'qqqzzzxxx-no-app'); rc=$?
check_eq "open: an app that is not there – failed, not done" $rc 1

out=$(lotus ai-tool weather); rc=$?
check_eq "weather without a city and no default: the user has to say" $rc 3

out=$(lotus ai-tool set_feature pets off); rc=$?
check_eq "a feature off" $rc 0
check_has "lotus_status shows it" "$(lotus ai-tool lotus_status)" "Features off: Pets"
out=$(lotus ai-tool set_feature core off); rc=$?
check_eq "the core cannot be turned off" $rc 2
