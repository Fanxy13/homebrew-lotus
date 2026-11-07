# Lotus for Windows – the video

A video of two to three minutes, cut from one real recording on GitHub's Windows machine
(`.github/workflows/windows-video.yml`, run on every change of `record.py`).

- **Where**: `windows-latest` – Windows Server 2025, x64, PowerShell 7. Not a Windows 11 desktop: the start screen's
  fastfetch shows the machine as it is, and the video says where it was recorded.
- **How**: `record.py` types every scene into a real PowerShell 7 in a ConPTY – the pseudo console Windows Terminal
  draws too – at a person's pace, and writes what the console sends to an asciicast v2 file
  (`takes/take-<run>.cast.gz`, also an artifact of the run). Lotus comes from the real install line
  (`irm …/main/install.ps1 | iex`) and its setup; winget, Ollama (qwen2.5:3b, on the processor), ImageMagick, yt-dlp
  and ffmpeg answer as they do for anyone.
- **Off camera**: the tools the scenes use (Ollama and its model, ImageMagick, yt-dlp, ffmpeg) are installed before the
  first scene, five photos and a small website are made to work with, and winget's source terms are accepted once.
- **The cut**: only time is left out – the wait for a download, a model or winget, and parts of a scene. Nothing in a
  scene is changed, sped up or put together from other takes. Where a wait is cut, the video says how long it was.
- **Not in it**: sound, music, now playing and MeshChat – the machine has no audio and no Bluetooth.
- The clip that `/convert` saves is the trailer of Big Buck Bunny, (c) Blender Foundation | www.bigbuckbunny.org,
  CC BY 3.0.

To try the script on Linux or macOS, in a Lotus that is set up already (the scenes that need Windows are skipped):

    python3 record.py out.cast clock zetamac
