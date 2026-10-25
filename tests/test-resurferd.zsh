# Subway Surfers Resurferd (plugins/resurferd): installed with full access, it gets the game the first time – the Mac
# build of a release (checked against its SHA-256) or one Unity builds from the source – and makes the app run on
# macOS (executable, out of quarantine). update finds a newer release or commit, install takes a zip or an app,
# remove takes the game and its source. A fake release list (file://), a git repository on this Mac and a fake
# Unity that talks like Unity's batch log stand in for GitHub and Unity; the game is never started.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
answer() { (sleep 1.5; print -rn -- $1; sleep 0.5) | script -q /dev/null zsh -fc "$2" 2>&1 | plain }
if (( ! $+commands[jq] )); then print -r -- "  – no jq: skipped"; return 0; fi
D=$LOTUS_DATA/plugins/resurferd A="$LOTUS_DATA/plugins/resurferd/Subway Surfers Resurferd.app"
info() { REPLY=; [[ -r $D/game.info ]] && REPLY=${(j: :)${(f)"$(<$D/game.info)"}:#DATE=*} }

# ── installed: full access, and why ──
out=$(answer y "$LOTUS_ROOT/bin/lotus plugin install $LOTUS_ROOT/plugins/resurferd")
check_has "install names full access" "$out" "full access – your files, the internet, Lotus' settings"
check_has "installed with its two commands and a tool" "$out" "lotus resurferd · lotus surf · 1 AI tool"
check_has "help" "$(lotus surf help 2>&1 | plain)" "lotus surf install <zip|app>"
check_has "an unknown word" "$(lotus surf jump 2>&1 | plain)" "Unknown: lotus surf jump"

# ── not there yet: nothing happens without a yes ──
out=$(lotus plugin-tool resurferd play 2>&1); rc=$?
check_eq "the AI hears that the user has to get it first" $rc 3
check_has "  and how" "$out" "The user gets it with: lotus surf"
check_has "no keyboard: no download" "$(lotus surf 2>&1 | plain)" "no keyboard to ask, so no"
check "  nothing came" test ! -e $A

# ── a release with a Mac build made on Linux: its program not executable ──
R=$HOME/rel
zf_mkdir -p $R/build/StandaloneOSX.app/Contents/MacOS
print -r -- '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Subway Surf</string></dict></plist>' >| $R/build/StandaloneOSX.app/Contents/Info.plist
print -r -- 'echo game' >| "$R/build/StandaloneOSX.app/Contents/MacOS/Subway Surf"
chmod 644 "$R/build/StandaloneOSX.app/Contents/MacOS/Subway Surf"
(cd $R/build && zip -qr ../mac.zip .)
release() {   # <tag> [bad] – the newest release; the one before it has no Mac build
  local sum=$(shasum -a 256 $R/mac.zip) size=$(wc -c < $R/mac.zip)
  sum=${sum%% *}; [[ $2 == bad ]] && sum=${(l:64::0:)}
  print -r -- '[{"tag_name":"'$1'","draft":false,"assets":[
      {"name":"Subway-Surfers-Resurferd-StandaloneWindows64.zip","browser_download_url":"file://'$R'/win.zip","size":1},
      {"name":"Subway-Surfers-Resurferd-StandaloneOSX.zip","browser_download_url":"file://'$R'/mac.zip","size":'${size// }',"digest":"sha256:'$sum'"}]},
    {"tag_name":"build-1","draft":false,"assets":[]}]' >| $R/releases.json
}
release build-55
zf_mkdir -p $D
print -r -- "RELEASES=file://$R/releases.json" >| $D/settings

out=$(answer y "$LOTUS_ROOT/bin/lotus surf update")
check_has "the first time it asks" "$out" "The game is not on this Mac yet"
check_has "  and gets the release's Mac build" "$out" "Ready: Subway Surfers Resurferd, build-55"
check "the app is in its data folder" test -d $A
check "  its program executable now" test -x "$A/Contents/MacOS/Subway Surf"
info; check_eq "  where it came from" "$REPLY" "FROM=release VERSION=build-55"
out=$(lotus surf status 2>&1 | plain)
check_has "status: ready" "$out" "ready – lotus surf starts it"
check_has "  from the release" "$out" "the release build-55"
check_has "update: nothing newer" "$(lotus surf update 2>&1 | plain)" "Up to date – build-55"
release build-56
check_has "a newer release comes" "$(lotus surf update 2>&1 | plain)" "Ready: Subway Surfers Resurferd, build-56"
info; check_eq "  and is noted" "$REPLY" "FROM=release VERSION=build-56"
release build-57 bad
check_has "a file that is not what GitHub promised: refused" "$(lotus surf update 2>&1 | plain)" "its SHA-256 differs"
info; check_eq "  the game before it stays" "$REPLY" "FROM=release VERSION=build-56"
check "  and nothing half is left" eval '[[ ! -e $D/download.zip.part && ! -e $D/.unpack ]]'

# ── your own Mac build: an app out of quarantine ──
cp -R $R/build/StandaloneOSX.app "$HOME/My Build.app"
[[ $OSTYPE == darwin* ]] && xattr -w com.apple.quarantine "0081;00000000;Safari;" "$HOME/My Build.app"
check_has "install an app" "$(cd $HOME && lotus surf install 'My Build.app' 2>&1 | plain)" "from My Build.app"
info; check_eq "  noted as yours" "$REPLY" "FROM=file VERSION=My Build.app"
[[ $OSTYPE == darwin* ]] && check "  out of quarantine" eval '! xattr -p com.apple.quarantine "$A" >/dev/null 2>&1'
check_has "install a zip" "$(lotus surf install $R/mac.zip 2>&1 | plain)" "from mac.zip"
check_has "something that is no Mac build" "$(lotus surf install $R/releases.json 2>&1 | plain)" "A Mac build is a .zip or an .app"

# ── built from the source: a git repository and a Unity that says what $HOME/unity.mode says ──
G=$HOME/src
zf_mkdir -p $G/ProjectSettings $G/Assets/Scripts $G/Assets/Mesh
print -r -- $'m_EditorVersion: 2019.4.41f2\nm_EditorVersionWithRevision: 2019.4.41f2 (6b23d448b533)' >| $G/ProjectSettings/ProjectVersion.txt
print -r -- 'class A {}' >| $G/Assets/Scripts/A.cs; print -r -- meta >| $G/Assets/Scripts/A.cs.meta
head -c 40000 /dev/zero >| $G/Assets/Mesh/train.asset; print -r -- meta >| $G/Assets/Mesh/train.asset.meta
commit() { (cd $G && git add -A && git -c user.email=t@example.com -c user.name=Test commit -qm "$1") }
(cd $G && git init -q) && commit one
U=$HOME/Unity.app/Contents/MacOS
zf_mkdir -p $U
cat >| $U/Unity <<'EOF'
#!/bin/zsh -f
mode=$(<$HOME/unity.mode)
print -r -- "$*" >| $HOME/unity.args
while (( $# )); do case $1 in -buildOSXUniversalPlayer) out=$2; shift ;; esac; shift; done
print -r -- "LICENSE SYSTEM [2026] Next license update check is after 2026-10-26"
[[ $mode == license ]] && { print -r -- "No valid Unity Editor license found. Please activate your license."; exit 1 }
for f in Assets/Scripts/A.cs Assets/Mesh/train.asset; do print -r -- "Start importing $f using Guid(0123) Importer(-1,0)"; done
print -r -- "- Starting compile Library/ScriptAssemblies/Assembly-CSharp.dll"
[[ $mode == compile ]] && { print -r -- "Assets/Scripts/A.cs(1,7): error CS0246: The type or namespace name 'Foo' could not be found"; exit 1 }
print -r -- "DisplayProgressbar: Building Player"
print -r -- 'Compiling shader "Mobile/Diffuse" pass "" (vp)'
mkdir -p "$out/Contents/MacOS"
cp $HOME/rel/build/StandaloneOSX.app/Contents/Info.plist "$out/Contents/Info.plist"
print -r -- 'echo game' > "$out/Contents/MacOS/Subway Surf"
print -r -- "Exiting batchmode successfully now!"
EOF
chmod +x $U/Unity
print -r -- $'GET=build\nGIT=file://'$G$'\nUNITY='$HOME/Unity.app >| $D/settings

print -r -- license >| $HOME/unity.mode
out=$(lotus surf build 2>&1 | plain)
check_has "the source comes with git" "$out" "Getting the source"
check_has "no license: said in words" "$out" "Unity has no license on this Mac"
check_has "  and how to get the free one" "$out" "Get a free personal license"
print -r -- compile >| $HOME/unity.mode
out=$(lotus surf build 2>&1 | plain)
check_has "scripts that do not compile: Unity's words" "$out" "Assets/Scripts/A.cs(1,7): error CS0246"
info; check_eq "  the game before it stays" "$REPLY" "FROM=file VERSION=mac.zip"
print -r -- good >| $HOME/unity.mode
out=$(lotus surf build 2>&1 | plain)
check_has "built" "$out" "Ready: Subway Surfers Resurferd, built from"
check_has "  through its steps" "$out" "Compiling the scripts"
args=$(<$HOME/unity.args)
check_has "Unity builds the Mac player" "$args" "-batchmode -quit -projectPath $D/source -buildTarget OSXUniversal -buildOSXUniversalPlayer"
check "  executable, in place" test -x "$A/Contents/MacOS/Subway Surf"
info; check_eq "  noted with its commit" "$REPLY" "FROM=source VERSION=$(git -C $G rev-parse --short HEAD)"
check_has "the log" "$(lotus surf log 2>&1 | plain)" "Exiting batchmode successfully now!"
check_has "update: the same commit" "$(lotus surf update 2>&1 | plain)" "Up to date"
print -r -- 'class B {}' >| $G/Assets/Scripts/B.cs; commit two
check_has "a new commit: built again" "$(lotus surf update 2>&1 | plain)" "Ready: Subway Surfers Resurferd, built from"
info; check_eq "  from it" "$REPLY" "FROM=source VERSION=$(git -C $G rev-parse --short HEAD)"
out=$(lotus surf status 2>&1 | plain)
check_has "status: the source" "$out" "with Unity's Library"
check_has "  and Unity" "$out" "2019.4.41f2 · ~/Unity.app"

# ── remove: the game and its source, your settings stay ──
check_has "no keyboard: nothing removed" "$(lotus surf remove 2>&1 | plain)" "Remove them?"
check "  still there" test -d $A
out=$(answer y "$LOTUS_ROOT/bin/lotus surf remove")
check_has "removed" "$out" "Removed – lotus surf gets the game again"
check "  the game and the source are gone" eval '[[ ! -e $A && ! -e $D/source && ! -e $D/game.info ]]'
check "  the settings stay" test -r $D/settings
