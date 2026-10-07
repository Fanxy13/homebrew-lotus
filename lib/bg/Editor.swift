// Lotus – "Draw what you want to keep": a tiny window for the Remove BG keep mask.
//
//   lotus-bg-editor --image work.png --alpha alpha.png --keep keep.png [--title photo.jpg]
//
// Shows the photo with the AI result bright and the rest dimmed. Paint over everything that must
// stay; your marks are shown in the theme color. Apply writes keep.png (white = keep) and exits 0,
// Cancel exits 1, unreadable files exit 2. Texts and the accent color come from Lotus through the
// environment (LOTUS_BG_UI, LOTUS_BG_ACCENT). Nothing is sent anywhere.
import AppKit
import ImageIO
import UniformTypeIdentifiers

// ── Texts from Lotus (key=value pairs separated by U+001F) ──────

enum T {
    static let table: [String: String] = {
        var t: [String: String] = [:]
        for pair in (ProcessInfo.processInfo.environment["LOTUS_BG_UI"] ?? "").split(separator: "\u{1f}") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { t[String(kv[0])] = String(kv[1]) }
        }
        return t
    }()
    static func s(_ key: String, _ fallback: String) -> String { table[key] ?? fallback }
}

let accent: NSColor = {
    let parts = (ProcessInfo.processInfo.environment["LOTUS_BG_ACCENT"] ?? "").split(separator: ",").compactMap { Double($0) }
    guard parts.count == 3 else { return NSColor(calibratedRed: 0.71, green: 0.83, blue: 0.44, alpha: 1) }
    return NSColor(calibratedRed: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: 1)
}()

// ── Images ──────────────────────────────────────────────────────

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// The keep mask: an 8-bit gray bitmap the size of the photo (255 = keep).
final class Mask {
    let width: Int, height: Int
    let ctx: CGContext

    init?(width: Int, height: Int, from image: CGImage? = nil) {
        self.width = width
        self.height = height
        guard let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx = c
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let img = image { ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
    }

    var bytes: UnsafeMutablePointer<UInt8> { ctx.data!.assumingMemoryBound(to: UInt8.self) }
    var count: Int { width * height }

    func snapshot() -> Data { Data(bytes: bytes, count: count) }
    func restore(_ d: Data) { d.copyBytes(to: bytes, count: min(count, d.count)) }
    var isEmpty: Bool { !UnsafeBufferPointer(start: bytes, count: count).contains { $0 > 127 } }

    func stroke(_ a: CGPoint, _ b: CGPoint, radius: CGFloat, erase: Bool) {
        ctx.setStrokeColor(gray: erase ? 0 : 1, alpha: 1)
        ctx.setFillColor(gray: erase ? 0 : 1, alpha: 1)
        ctx.setLineWidth(radius * 2)
        if a == b {
            ctx.fillEllipse(in: CGRect(x: a.x - radius, y: a.y - radius, width: radius * 2, height: radius * 2))
        } else {
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        }
    }

    func clear() { memset(bytes, 0, count) }
    func invert() { for i in 0..<count { bytes[i] = 255 &- bytes[i] } }
    func image() -> CGImage? { ctx.makeImage() }

    func write(_ path: String) -> Bool {
        guard let img = image(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest)
    }
}

/// 8-bit gray copy of any image (the AI alpha comes as 16-bit PNG)
func grayCopy(_ img: CGImage, _ w: Int, _ h: Int) -> CGImage? {
    guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return c.makeImage()
}

// ── The canvas ──────────────────────────────────────────────────

final class Canvas: NSView {
    let photo: CGImage
    let aiAlpha: CGImage
    let mask: Mask
    let initial: Data
    var erase = false
    var preview = false { didSet { needsDisplay = true } }
    var brush: CGFloat = 36 { didSet { needsDisplay = true } }   // diameter on screen
    var undo: [Data] = [], redo: [Data] = []
    var onChange: () -> Void = {}
    private var last: CGPoint?
    private var hover: NSPoint?

    init(photo: CGImage, aiAlpha: CGImage, mask: Mask) {
        self.photo = photo
        self.aiAlpha = aiAlpha
        self.mask = mask
        self.initial = mask.snapshot()
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    /// Where the photo sits: as large as possible, keeping its proportions
    var photoRect: CGRect {
        let pad: CGFloat = 16
        let box = bounds.insetBy(dx: pad, dy: pad)
        let s = min(box.width / CGFloat(mask.width), box.height / CGFloat(mask.height))
        let w = CGFloat(mask.width) * s, h = CGFloat(mask.height) * s
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    func toImage(_ p: NSPoint) -> CGPoint {
        let r = photoRect
        return CGPoint(x: (p.x - r.minX) / r.width * CGFloat(mask.width), y: (p.y - r.minY) / r.height * CGFloat(mask.height))
    }

    var radiusInImage: CGFloat { brush / 2 / (photoRect.width / CGFloat(mask.width)) }

    func checkpoint() {
        undo.append(mask.snapshot())
        if undo.count > 40 { undo.removeFirst() }
        redo.removeAll()
        onChange()
    }

    override func mouseDown(with e: NSEvent) {
        checkpoint()
        let p = toImage(convert(e.locationInWindow, from: nil))
        mask.stroke(p, p, radius: radiusInImage, erase: erase)
        last = p
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        let loc = convert(e.locationInWindow, from: nil)
        hover = loc
        let p = toImage(loc)
        mask.stroke(last ?? p, p, radius: radiusInImage, erase: erase)
        last = p
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) { last = nil; onChange() }
    override func mouseMoved(with e: NSEvent) { hover = convert(e.locationInWindow, from: nil); needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hover = nil; needsDisplay = true }

    override func scrollWheel(with e: NSEvent) {
        brush = max(4, min(240, brush + e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.5 : 4)))
        onChange()
    }

    func perform(_ change: () -> Void) {
        checkpoint()
        change()
        needsDisplay = true
        onChange()
    }

    func doUndo() {
        guard let d = undo.popLast() else { return }
        redo.append(mask.snapshot()); mask.restore(d); needsDisplay = true; onChange()
    }

    func doRedo() {
        guard let d = redo.popLast() else { return }
        undo.append(mask.snapshot()); mask.restore(d); needsDisplay = true; onChange()
    }

    func reset() { perform { mask.restore(initial) } }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        bounds.fill()
        let r = photoRect
        guard let keep = mask.image() else { return }
        if preview {
            // The result: kept parts over a checkerboard
            let tile: CGFloat = 12
            g.saveGState(); g.clip(to: r)
            var y = r.minY, row = 0
            while y < r.maxY {
                var x = r.minX, col = row % 2
                while x < r.maxX {
                    g.setFillColor(gray: col % 2 == 0 ? 0.80 : 0.62, alpha: 1)
                    g.fill(CGRect(x: x, y: y, width: tile, height: tile))
                    x += tile; col += 1
                }
                y += tile; row += 1
            }
            g.restoreGState()
            for m in [aiAlpha, keep] {
                g.saveGState(); g.clip(to: r, mask: m); g.draw(photo, in: r); g.restoreGState()
            }
        } else {
            // The photo dimmed, the AI result bright, your marks bright and tinted
            g.draw(photo, in: r)
            g.setFillColor(gray: 0, alpha: 0.62)
            g.fill(r)
            g.saveGState(); g.clip(to: r, mask: aiAlpha); g.draw(photo, in: r); g.restoreGState()
            g.saveGState(); g.clip(to: r, mask: keep); g.draw(photo, in: r)
            g.setFillColor(accent.withAlphaComponent(0.42).cgColor); g.fill(r); g.restoreGState()
        }
        // Brush outline
        if let h = hover, r.contains(h), !preview {
            let d = brush
            g.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            g.setLineWidth(1.5)
            g.strokeEllipse(in: CGRect(x: h.x - d / 2, y: h.y - d / 2, width: d, height: d))
            g.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            g.setLineWidth(1)
            g.strokeEllipse(in: CGRect(x: h.x - d / 2 - 1.5, y: h.y - d / 2 - 1.5, width: d + 3, height: d + 3))
        }
    }

    override func keyDown(with e: NSEvent) {
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "b": erase = false; onChange()
        case "e": erase = true; onChange()
        case "[": brush = max(4, brush / 1.25); onChange()
        case "]": brush = min(240, brush * 1.25); onChange()
        case "i": perform { mask.invert() }
        case "p", " ": preview.toggle(); onChange()
        default: super.keyDown(with: e)
        }
    }
}

// ── Window and controls ─────────────────────────────────────────

final class Editor: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let canvas: Canvas
    let keepPath: String
    let title: String
    var window: NSWindow!
    let tool = NSSegmentedControl()
    let size = NSSlider()
    let previewButton = NSButton()
    let undoButton = NSButton(), redoButton = NSButton()
    var finished = false

    init(canvas: Canvas, keepPath: String, title: String) {
        self.canvas = canvas
        self.keepPath = keepPath
        self.title = title
    }

    func button(_ label: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = []) -> NSButton {
        let b = NSButton(title: label, target: self, action: action)
        b.bezelStyle = .rounded
        b.keyEquivalent = key
        b.keyEquivalentModifierMask = mods
        return b
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let ratio = CGFloat(canvas.mask.width) / CGFloat(canvas.mask.height)
        var h = min(screen.height * 0.82, 900), w = (h - 120) * ratio + 32
        if w > screen.width * 0.86 { w = screen.width * 0.86; h = (w - 32) / ratio + 120 }
        w = max(w, 860)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Lotus – " + T.s("title", "Draw what you want to keep")
        window.subtitle = title
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = CGSize(width: 760, height: 480)
        window.delegate = self
        window.isReleasedWhenClosed = false

        let hint = NSTextField(labelWithString: T.s("hint", "Paint over everything that must stay. Bright: kept by the AI. Colored: your marks."))
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        tool.segmentStyle = .rounded
        tool.segmentCount = 2
        tool.setLabel(T.s("brush", "Brush"), forSegment: 0)
        tool.setLabel(T.s("eraser", "Eraser"), forSegment: 1)
        tool.selectedSegment = 0
        tool.target = self
        tool.action = #selector(pickTool)

        size.minValue = 4; size.maxValue = 240; size.doubleValue = Double(canvas.brush)
        size.target = self; size.action = #selector(pickSize)
        size.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let sizeLabel = NSTextField(labelWithString: T.s("size", "Size"))
        sizeLabel.textColor = .secondaryLabelColor

        undoButton.title = T.s("undo", "Undo"); undoButton.bezelStyle = .rounded; undoButton.target = self; undoButton.action = #selector(doUndo)
        redoButton.title = T.s("redo", "Redo"); redoButton.bezelStyle = .rounded; redoButton.target = self; redoButton.action = #selector(doRedo)
        previewButton.setButtonType(.pushOnPushOff)
        previewButton.bezelStyle = .rounded
        previewButton.title = T.s("preview", "Preview")
        previewButton.target = self; previewButton.action = #selector(togglePreview)

        let apply = button(T.s("apply", "Apply"), #selector(applyMask), key: "\r")
        apply.bezelColor = accent
        let cancel = button(T.s("cancel", "Cancel"), #selector(cancel), key: "\u{1b}")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let bar = NSStackView(views: [tool, sizeLabel, size, undoButton, redoButton,
                                      button(T.s("clear", "Clear"), #selector(clearMask)),
                                      button(T.s("reset", "Reset"), #selector(resetMask)),
                                      button(T.s("invert", "Invert"), #selector(invertMask)),
                                      previewButton, spacer, cancel, apply])
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 12, right: 14)
        let top = NSStackView(views: [hint])
        top.edgeInsets = NSEdgeInsets(top: 8, left: 18, bottom: 0, right: 18)
        let stack = NSStackView(views: [top, canvas, bar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        canvas.translatesAutoresizingMaskIntoConstraints = false
        for v in [top, canvas, bar] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        canvas.setContentHuggingPriority(.init(1), for: .vertical)
        window.contentView = stack
        canvas.onChange = { [weak self] in self?.sync() }
        sync()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        if let snap = ProcessInfo.processInfo.environment["LOTUS_BG_EDITOR_TEST"] { selfTest(snap) }
    }

    func sync() {
        tool.selectedSegment = canvas.erase ? 1 : 0
        size.doubleValue = Double(canvas.brush)
        previewButton.state = canvas.preview ? .on : .off
        undoButton.isEnabled = !canvas.undo.isEmpty
        redoButton.isEnabled = !canvas.redo.isEmpty
    }

    @objc func pickTool() { canvas.erase = tool.selectedSegment == 1 }
    @objc func pickSize() { canvas.brush = CGFloat(size.doubleValue) }
    @objc func doUndo() { canvas.doUndo() }
    @objc func doRedo() { canvas.doRedo() }
    @objc func clearMask() { canvas.perform { canvas.mask.clear() } }
    @objc func resetMask() { canvas.reset() }
    @objc func invertMask() { canvas.perform { canvas.mask.invert() } }
    @objc func togglePreview() { canvas.preview.toggle(); sync() }

    @objc func applyMask() {
        finished = true
        exit(canvas.mask.write(keepPath) ? 0 : 2)
    }

    @objc func cancel() { finished = true; exit(1) }
    func windowWillClose(_ n: Notification) { if !finished { exit(1) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    /// LOTUS_BG_EDITOR_TEST=<file.png>: paints, uses undo/redo/invert, saves pictures of the
    /// window (normal and preview) and applies – for Lotus' own tests.
    func selfTest(_ snapPath: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            let w = CGFloat(canvas.mask.width), h = CGFloat(canvas.mask.height)
            canvas.checkpoint()
            canvas.mask.stroke(CGPoint(x: w * 0.1, y: h * 0.8), CGPoint(x: w * 0.3, y: h * 0.8), radius: w * 0.03, erase: false)
            canvas.perform { canvas.mask.invert() }
            canvas.doUndo()
            canvas.doUndo()
            canvas.doRedo()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                snapshot(snapPath)
                canvas.preview = true
                sync()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                    snapshot(snapPath.replacingOccurrences(of: ".png", with: "-preview.png"))
                    applyMask()
                }
            }
        }
    }

    /// A real picture of the window (needs Screen Recording access for the terminal; otherwise the
    /// canvas alone is drawn into the file)
    func snapshot(_ path: String) {
        window.displayIfNeeded()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l\(window.windowNumber)", path]
        try? p.run()
        p.waitUntilExit()
        if FileManager.default.fileExists(atPath: path) { return }
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

// ── Main ────────────────────────────────────────────────────────

@main
struct LotusBgEditor {
    static func main() {
        var opts: [String: String] = [:]
        var args = Array(CommandLine.arguments.dropFirst())
        while args.count >= 2, args[0].hasPrefix("--") { opts[String(args[0].dropFirst(2))] = args[1]; args.removeFirst(2) }
        guard let imagePath = opts["image"], let alphaPath = opts["alpha"], let keepPath = opts["keep"],
              let photo = loadImage(imagePath), let alphaRaw = loadImage(alphaPath) else {
            FileHandle.standardError.write(Data("usage: lotus-bg-editor --image work.png --alpha alpha.png --keep keep.png\n".utf8))
            exit(2)
        }
        let w = photo.width, h = photo.height
        let previous = FileManager.default.fileExists(atPath: keepPath) ? loadImage(keepPath) : nil
        guard let alpha = grayCopy(alphaRaw, w, h), let mask = Mask(width: w, height: h, from: previous) else { exit(2) }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let editor = Editor(canvas: Canvas(photo: photo, aiAlpha: alpha, mask: mask), keepPath: keepPath, title: opts["title"] ?? "")
        app.delegate = editor
        // Menu with the usual shortcuts (⌘Z, ⇧⌘Z, ⌘Q cancels)
        let menu = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem()
        menu.addItem(appItem); menu.addItem(editItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: T.s("cancel", "Cancel"), action: #selector(Editor.cancel), keyEquivalent: "q").target = editor
        appItem.submenu = appMenu
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: T.s("undo", "Undo"), action: #selector(Editor.doUndo), keyEquivalent: "z").target = editor
        let r = edit.addItem(withTitle: T.s("redo", "Redo"), action: #selector(Editor.doRedo), keyEquivalent: "z")
        r.keyEquivalentModifierMask = [.command, .shift]
        r.target = editor
        edit.addItem(withTitle: T.s("invert", "Invert"), action: #selector(Editor.invertMask), keyEquivalent: "i").target = editor
        editItem.submenu = edit
        app.mainMenu = menu
        app.run()
    }
}
