// Lotus – Remove BG: what is in the clipboard? (JavaScript for Automation, comes with macOS)
//
//   osascript -l JavaScript clipboard.js peek          → "files <n>" · "image <w>x<h>" · "none"
//   osascript -l JavaScript clipboard.js save <file>   → one path per line: the copied files, or <file>
//                                                        with the clipboard image written as PNG
//
// Files copied in the Finder win over image data, so the originals are used. Image data (a
// screenshot, "Copy Image" in a browser, Preview) is written without changes when it is PNG and
// converted when it is TIFF or another image type. Nothing leaves the Mac.
// LOTUS_BG_PASTEBOARD names another pasteboard than the general one (Lotus' own tests use it).
ObjC.import('AppKit');

function board() {
  const name = $.NSProcessInfo.processInfo.environment.objectForKey('LOTUS_BG_PASTEBOARD');
  return name.isNil() ? $.NSPasteboard.generalPasteboard : $.NSPasteboard.pasteboardWithName(name);
}

function files(pb) {
  const urls = pb.readObjectsForClassesOptions($([$.NSURL]), $({ NSPasteboardURLReadingFileURLsOnlyKey: true }));
  const out = [];
  if (!urls.isNil()) for (let i = 0; i < urls.count; i++) out.push(urls.objectAtIndex(i).path.js);
  return out;
}

// PNG data of the clipboard image (or null), with its size in pixels
function image(pb) {
  let data = pb.dataForType('public.png');
  let rep = data.isNil() ? null : $.NSBitmapImageRep.imageRepWithData(data);
  if (!rep || rep.isNil()) {
    const tiff = pb.dataForType('public.tiff');
    if (!tiff.isNil()) rep = $.NSBitmapImageRep.imageRepWithData(tiff);
  }
  if (!rep || rep.isNil()) {
    const img = $.NSImage.alloc.initWithPasteboard(pb);
    if (img.isNil()) return null;
    rep = $.NSBitmapImageRep.imageRepWithData(img.TIFFRepresentation);
    if (rep.isNil()) return null;
  }
  if (data.isNil()) data = rep.representationUsingTypeProperties(4 /* PNG */, $({}));
  return { data, w: rep.pixelsWide, h: rep.pixelsHigh };
}

function run(argv) {
  const pb = board();
  const paths = files(pb);
  if (argv[0] === 'peek') {
    if (paths.length) return `files ${paths.length}`;
    const img = image(pb);
    return img ? `image ${img.w}x${img.h}` : 'none';
  }
  if (paths.length) return paths.join('\n');
  const img = image(pb);
  if (!img || !argv[1]) return '';
  return img.data.writeToFileAtomically(argv[1], true) ? argv[1] : '';
}
