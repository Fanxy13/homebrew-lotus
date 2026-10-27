#!/bin/bash
# Temporary experiment (to be removed): what macOS does with a Bluetooth program started from Terminal.app,
# and whether a program that disclaims responsibility, or an app opened by LaunchServices, gets its own permission.
set -u
W=$GITHUB_WORKSPACE
D=$RUNNER_TEMP/mc            # stands in for the plugin's data folder
O=$D/out
mkdir -p "$O"
sw_vers

echo "── Terminal.app"
T=/System/Applications/Utilities/Terminal.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $T/Contents/Info.plist
plutil -p $T/Contents/Info.plist | grep -i -E 'usage' || echo "(no usage descriptions in Info.plist)"
if /usr/libexec/PlistBuddy -c 'Print :NSBluetoothAlwaysUsageDescription' $T/Contents/Info.plist >/dev/null 2>&1; then
  echo "RESULT Terminal.app declares NSBluetoothAlwaysUsageDescription"
else
  echo "RESULT Terminal.app does NOT declare NSBluetoothAlwaysUsageDescription"
fi
ls $T/Contents/Resources | grep -i -E 'infoplist|loctable'
for f in $T/Contents/Resources/InfoPlist.loctable $T/Contents/Resources/en.lproj/InfoPlist.strings; do
  [ -e "$f" ] && { echo "$f:"; plutil -p "$f" | grep -i -E 'bluetooth' | head -4; }
done

echo "── other terminal apps"
for c in iterm2 ghostty wezterm kitty alacritty warp visual-studio-code; do
  brew install --cask --quiet $c >/dev/null 2>&1 || echo "($c could not be installed)"
done
for a in /Applications/*.app; do
  case "$(basename "$a")" in iTerm.app|Ghostty.app|WezTerm.app|kitty.app|Alacritty.app|Warp.app|"Visual Studio Code.app") ;; *) continue ;; esac
  if v=$(/usr/libexec/PlistBuddy -c 'Print :NSBluetoothAlwaysUsageDescription' "$a/Contents/Info.plist" 2>/dev/null); then
    echo "RESULT $(basename "$a") declares it: $v"
  else
    echo "RESULT $(basename "$a") does NOT declare it"
  fi
done

echo "── build"
xcrun swiftc -Onone -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos11.0" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$W/plugins/meshchat/Info.plist" \
  -o "$D/meshchat" "$W"/plugins/meshchat/Sources/*.swift || exit 1
cat > "$D/spawn.c" <<'EOF'
// spawn plain|disclaim <program> [args…] – starts it, waits, says how it ended
#include <dlfcn.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
extern char **environ;
int main(int argc, char **argv) {
    if (argc < 3) return 2;
    posix_spawnattr_t a;
    posix_spawnattr_init(&a);
    int r = 0;
    if (strcmp(argv[1], "disclaim") == 0) {
        int (*f)(posix_spawnattr_t *, int) =
            (int (*)(posix_spawnattr_t *, int))dlsym(RTLD_DEFAULT, "responsibility_spawnattrs_setdisclaim");
        r = f ? f(&a, 1) : -100;
    }
    pid_t pid;
    int e = posix_spawn(&pid, argv[2], NULL, &a, argv + 2, environ);
    if (e) { printf("spawn failed: %s\n", strerror(e)); return 1; }
    int st = 0;
    waitpid(pid, &st, 0);
    if (WIFSIGNALED(st)) printf("ENDED BY SIGNAL %d (%s), disclaim call %d\n", WTERMSIG(st), strsignal(WTERMSIG(st)), r);
    else printf("exited %d, disclaim call %d\n", WEXITSTATUS(st), r);
    return 0;
}
EOF
xcrun clang -o "$D/spawn" "$D/spawn.c" || exit 1
A=$D/MeshChat.app
mkdir -p "$A/Contents/MacOS"
cp "$D/meshchat" "$A/Contents/MacOS/meshchat"
cat > "$A/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>meshchat</string>
  <key>CFBundleIdentifier</key><string>io.github.fanxy13.lotus.meshchat</string>
  <key>CFBundleName</key><string>MeshChat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>MeshChat talks to the Macs around you over Bluetooth.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$A" && codesign -dv "$A" 2>&1 | grep -E 'Identifier|Signature'

H=$(cd ~ && pwd -P)
TMP=$(cd "${TMPDIR:-/tmp}" && pwd -P)
cat > "$D/profile.sb" <<EOF
(version 1)
(allow default)
(allow file-write* (subpath "$TMP") (subpath "/private/tmp") (subpath "/private/var/folders"))
(deny file-read* (subpath "$H") (subpath "/Volumes"))
(deny file-write* (subpath "$H") (subpath "/Volumes"))
(allow file-read* (subpath "$W/plugins/meshchat") (subpath "$D"))
(allow file-write* (subpath "$D"))
(deny process-exec (literal "/usr/bin/security") (literal "/usr/bin/osascript") (literal "/usr/bin/sudo") (literal "/usr/bin/su"))
(deny appleevent-send)
(deny mach-lookup (global-name "com.apple.SecurityServer") (global-name "com.apple.securityd.xpc"))
(deny network*)
EOF

# the same cases, from the CI shell (no app above it) and from Terminal.app
cat > "$D/cases.sh" <<EOF
#!/bin/bash
w=\$1
run() { local n=\$1; shift; "\$@" > "$O/\$w-\$n.txt" 2>&1; echo "[done]" >> "$O/\$w-\$n.txt"; }
run plain "$D/spawn" plain "$D/meshchat" probe-bluetooth
run disclaim "$D/spawn" disclaim "$D/meshchat" probe-bluetooth
run sandbox-plain /usr/bin/sandbox-exec -f "$D/profile.sb" "$D/spawn" plain "$D/meshchat" probe-bluetooth
run sandbox-disclaim /usr/bin/sandbox-exec -f "$D/profile.sb" "$D/spawn" disclaim "$D/meshchat" probe-bluetooth
/usr/bin/open -W -n -g -a "$A" --stdout "$O/\$w-app.txt" --stderr "$O/\$w-app.txt" --args probe-bluetooth
echo "open: \$?" > "$O/\$w-app-open.txt"
/usr/bin/sandbox-exec -f "$D/profile.sb" /usr/bin/open -W -n -g -a "$A" --stdout "$O/\$w-sandbox-app.txt" --stderr "$O/\$w-sandbox-app.txt" --args probe-bluetooth
echo "open: \$?" > "$O/\$w-sandbox-app-open.txt"
p=\$\$; while [ "\$p" -gt 1 ]; do ps -o pid=,ppid=,comm= -p \$p; p=\$(ps -o ppid= -p \$p | tr -d ' '); done > "$O/\$w-parents.txt"
touch "$O/\$w-done"
EOF
chmod +x "$D/cases.sh"
printf '#!/bin/bash\n"%s" terminal\n' "$D/cases.sh" > "$D/cases.command"
chmod +x "$D/cases.command"

echo "── from the CI shell"
"$D/cases.sh" ci
echo "── from Terminal.app"
open -a Terminal "$D/cases.command"
for i in $(seq 120); do [ -e "$O/terminal-done" ] && break; sleep 1; done
[ -e "$O/terminal-done" ] || echo "(Terminal did not finish within 2 minutes)"

for f in "$O"/*.txt; do echo "━━ $(basename "$f")"; cat "$f"; done

echo "── crash reports"
ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -10
for f in $(ls -t ~/Library/Logs/DiagnosticReports/*meshchat* ~/Library/Logs/DiagnosticReports/*MeshChat* 2>/dev/null | head -4); do
  echo "━━ $f"
  grep -o -E '"(namespace|indicator|reasons|code|signal|procPath|responsibleProc|parentProc)" *: *[^,]*' "$f" | head -20
  grep -o -E 'usage description[^"]*' "$f" | head -2
done
echo "── tccd"
log show --last 10m --style compact --predicate 'process == "tccd" OR subsystem == "com.apple.TCC"' 2>/dev/null \
  | grep -i -E 'bluetooth|meshchat|usage|responsib|attribution' | tail -60
true
