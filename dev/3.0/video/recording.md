# Recording

## The machines
- **Mac**: a new user account (so the start screen has nothing of yours), macOS up to date, Terminal or iTerm2.
- **Linux**: Ubuntu 24.04 (real hardware or a VM at the full screen resolution), GNOME Terminal. Install `playerctl`, `imagemagick` and `bubblewrap`
  for the scenes that use them; leave bubblewrap out for the one take that shows the refusal.
- Both: Lotus installed by the real install line in the scene, not before (scenes 4 and 5). The other scenes follow on that install.

## The terminal
120 x 30 characters, JetBrains Mono 16 pt, the Matcha theme (`lotus setup` or `lotus themes`), no transparency, no tabs, a 1 px
border-less window. Hide the dock and the menu bar clock if they show a time that does not match the voice-over.

## What must not be on screen
Your name (set a name in the setup: "Lotus"), email addresses, API keys (paste into the hidden prompt, or use Ollama), the file names of
private folders (use a folder of license-free photos for `/img convert`), notifications, the clipboard.

## How
- QuickTime (Mac) or OBS (both): 1920 x 1080 minimum, 60 fps, the window only, no cursor highlights.
- Record the voice-over separately in a quiet room, after the script is final. Speak slowly; leave a second of silence at each [pause].
- Record every scene twice. Keep the take where the command output is what the release really prints.
- Keep the real timings: do not speed up a command that is slow (a download); cut to the result with a cross dissolve and the text "(2 minutes later)" if needed.
