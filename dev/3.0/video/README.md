# Lotus 3.0 – the release video

A package to make the video from: voice-over, scenes, the exact commands, what to record, how to cut it, title, description,
chapters and thumbnail. **Nothing here is a recording and nothing is rendered**: no screen recording exists yet, and none may be
invented. Record it after the release, on the real systems, with the real commands below.

| File | What it is |
|---|---|
| `script.md` | The English voice-over, scene by scene, with the time it should take |
| `storyboard.md` | Every scene as a table: picture, on-screen text, the commands typed, where it is recorded |
| `commands.md` | The exact commands in order, as a checklist to type (nothing here has been run for the video) |
| `recording.md` | Setup of the two machines, the terminal, the fonts, what must not be on screen, how to record |
| `editing.md` | Cuts, transitions, text, music mood, sound, export |
| `youtube.md` | Titles, description, chapters, thumbnail, tags |

## Style (from the website, the only earlier material there is)

There is no earlier Lotus video in the repository. The look comes from the site (`docs/`): near-black ground (`#05070a`), the
Matcha theme (greens, a pink lotus), headings in an italic serif (Instrument Serif), the terminal in JetBrains Mono. Calm, slow,
spacious; no flashing, no fast zooms, no emoji, no stock footage of "hackers".

## Rules

- Show only what exists and what was tested on that system (`dev/3.0/PROGRESS.md`, the table on the website). If the table says
  "Soon" for a system, that scene is not in the video.
- **Windows**: the port is in development. The video says so in one sentence and shows a text card – no Windows recording – until
  a release has it. If a release does, add the scenes in `storyboard.md` marked "when Windows ships".
- Record real runs. If something fails on camera, it stays in or the take is repeated – it is never staged.
- No name, mail address, token or API key on screen (see `recording.md`).
