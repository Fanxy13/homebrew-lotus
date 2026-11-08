# Lotus for Windows – the video

A video of two to three minutes, cut from one real recording on GitHub's Windows machine
(`.github/workflows/windows-video.yml`: a change of `record.py` rehearses, a take is started by hand).

- **Where**: `windows-latest` – Windows Server 2025, x64, PowerShell 7. Not a Windows 11 desktop: the start screen's
  fastfetch shows the machine as it is, and the video says where it was recorded.
- **How**: `record.py` types every scene into a real PowerShell 7 in a ConPTY – the pseudo console Windows Terminal
  draws too – at a person's pace (the install line and a link are pasted, as a person does), and writes what the
  console sends to an asciicast v2 file (`takes/take-<run>.cast.gz`, also an artifact of the run). Lotus comes from
  the real install line (`irm …/main/install.ps1 | iex`) and its setup; winget, Ollama (qwen2.5:3b, on the
  processor), ImageMagick, yt-dlp and ffmpeg answer as they do for anyone.
- **Off camera**: the tools the scenes use (Ollama and its model, ImageMagick, yt-dlp, ffmpeg) are installed before the
  first scene, five photos and a small website are made to work with, and winget's source terms are accepted once.
- **The cut**: only time is left out – the wait for a download, a model or winget, and parts of a scene. Nothing in a
  scene is changed, sped up or put together from other takes. Where more than three seconds are left out, the video
  says how many.
- **Rehearsals** (`LOTUS_VIDEO_REHEARSAL=1` in the workflow) install the branch's Lotus with install.ps1's `LOTUS_SRC`
  and play every scene even when one goes wrong, to find what goes wrong on Windows before a take. They found eight
  bugs of Lotus for Windows (each fixed with a test) and are never cut into the video. A take installs from `main`
  with the line from the website, and stops at its first failure.
- **Not in it**: sound, music, now playing and MeshChat – the machine has no audio and no Bluetooth.
- The clip that `/convert` saves is the trailer of Big Buck Bunny, (c) Blender Foundation | www.bigbuckbunny.org,
  CC BY 3.0.

To try the script on Linux or macOS, in a Lotus that is set up already (the scenes that need Windows are skipped):

    python3 record.py out.cast clock zetamac

To cut the video from a take: `cut.json` says which moments of each scene are in it – seconds, a marker of the take
(`"scene:img+1.5"`), or the first time a text shows after one (`{"after": "scene:app", "shows": "Did you mean"}`), so
the cut fits any take of these scenes. `render/` replays the take in xterm.js in Chromium, frame by frame, and encodes
it with ffmpeg:

    cd render && npm install
    node render.mjs ../takes/take-<run>.cast.gz ../cut.json --plan        (the parts and their times)
    node render.mjs ../takes/take-<run>.cast.gz ../cut.json lotus-for-windows.mp4
