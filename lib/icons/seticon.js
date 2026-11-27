// Lotus – folder icons on macOS (JavaScript for Automation, comes with macOS – nothing to install)
//
//   osascript -l JavaScript seticon.js set <folder> <picture>   → ok · unreadable · failed
//   osascript -l JavaScript seticon.js reset <folder>           → ok · failed
//
// NSWorkspace's setIcon is what Finder does for "Get Info → paste a picture onto the icon": macOS keeps the picture in a hidden
// file called "Icon" inside the folder, so the icon moves with the folder. Nothing else in the folder is touched, and
// "reset" takes the picture away again, which gives the folder its normal icon back.
ObjC.import('AppKit');

function run(argv) {
  const action = argv[0];
  const folder = argv[1];
  if (!folder) return 'usage';
  const workspace = $.NSWorkspace.sharedWorkspace;

  if (action === 'set') {
    if (!argv[2]) return 'usage';
    const image = $.NSImage.alloc.initWithContentsOfFile(argv[2]);
    if (image.isNil()) return 'unreadable';
    // 0: every size of the picture is kept (no options)
    return workspace.setIconForFileOptions(image, folder, 0) ? 'ok' : 'failed';
  }

  if (action === 'reset') {
    // "no picture" is how the API is told to remove the custom icon; the two ways to write "nothing" in JXA are both tried
    for (const nothing of [$(), null]) {
      try {
        if (workspace.setIconForFileOptions(nothing, folder, 0)) return 'ok';
      } catch (e) { /* the other kind of nothing */ }
    }
    return 'failed';
  }

  return 'usage';
}
