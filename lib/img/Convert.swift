// lotus-img – the image converter of Lotus (/img convert), built once by lotus_swift_build (lib/core.zsh).
//
//   lotus-img --formats      what this Mac can write: one "<type identifier>" per line
//   lotus-img --jobs <n>     the jobs on stdin, one per line, tab-separated, n at a time:
//                            <input> <output> <type identifier> <quality 1–100, 0 = the format's own> <max pixels, 0 = keep>
//                            and one line per image on stdout:
//                              start <i>
//                              done <i> <input bytes> <output bytes> <w>x<h> <new w>x<new h>
//                              fail <i> <reason>
//
// With Apple's ImageIO – it reads what Preview reads (HEIC, WebP, RAW, PSD, SVG, JPEG XL …). Photos come out the way
// they are meant to be seen (their orientation is applied), smaller but never larger, and keep their camera data.
// Formats without transparency (JPEG, BMP) get a white background; an icon (ICO) becomes a square of at most 256.
// WebP, which ImageIO cannot write, goes through PNG and cwebp. Every file is written next to its name first and
// renamed when it is complete, so a stopped run leaves no half image behind.

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

struct Job { let index: Int; let input: String; let output: String; let type: String; let quality: Int; let max: Int }
struct Failure: Error { let reason: String }

let out = FileHandle.standardOutput
let lock = NSLock()
func say(_ line: String) { lock.lock(); out.write((line + "\n").data(using: .utf8)!); lock.unlock() }

func size(_ path: String) -> Int { ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue ?? 0 }

let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

// The picture drawn on a new canvas: a background color (or clear), centered in <w> × <h>
func redraw(_ img: CGImage, width w: Int, height h: Int, white: Bool) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    if white { ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: (w - img.width) / 2, y: (h - img.height) / 2, width: img.width, height: img.height))
    return ctx.makeImage()
}

func hasAlpha(_ img: CGImage) -> Bool {
    switch img.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: return false; default: return true }
}

func convert(_ job: Job) throws -> String {
    let url = URL(fileURLWithPath: job.input)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(src) > 0 else { throw Failure(reason: "not an image this Mac can read") }
    let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
    let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0, h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
    let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
    let (dw, dh) = orientation >= 5 ? (h, w) : (w, h)               // as it is seen
    let icon = job.type == "com.microsoft.ico"
    var side = max(dw, dh)
    if job.max > 0 && job.max < side { side = job.max }             // smaller, never larger
    if icon { side = min(side, 256) }
    var opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                 kCGImageSourceCreateThumbnailWithTransform: true,
                                 kCGImageSourceShouldCacheImmediately: true]
    if side > 0 { opts[kCGImageSourceThumbnailMaxPixelSize] = side }
    guard var img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
        throw Failure(reason: "it could not be decoded")
    }
    let noAlpha = ["public.jpeg", "com.microsoft.bmp"].contains(job.type)
    if noAlpha && hasAlpha(img), let flat = redraw(img, width: img.width, height: img.height, white: true) { img = flat }
    if icon && img.width != img.height {
        let s = max(img.width, img.height)
        guard let square = redraw(img, width: s, height: s, white: false) else { throw Failure(reason: "the icon could not be made") }
        img = square
    }

    // the camera data stays, the orientation is in the pixels now
    var meta = props
    for k in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyOrientation, kCGImagePropertyDepth,
              kCGImagePropertyHasAlpha, kCGImagePropertyColorModel, kCGImagePropertyProfileName] { meta.removeValue(forKey: k) }
    if var tiff = meta[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
        tiff[kCGImagePropertyTIFFOrientation] = 1
        meta[kCGImagePropertyTIFFDictionary] = tiff
    }
    meta[kCGImagePropertyOrientation] = 1
    if job.quality > 0 { meta[kCGImageDestinationLossyCompressionQuality] = Double(job.quality) / 100 }

    let tmp = job.output + ".lotus-tmp"
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    let webp = job.type == "org.webmproject.webp" && !writable.contains(job.type)
    let type = webp ? "public.png" : job.type
    guard writable.contains(type) else { throw Failure(reason: "this Mac cannot write \(job.type)") }
    guard let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: tmp) as CFURL, type as CFString, 1, nil) else {
        throw Failure(reason: "cannot write to \(URL(fileURLWithPath: job.output).deletingLastPathComponent().path)")
    }
    CGImageDestinationAddImage(dst, img, meta as CFDictionary)
    guard CGImageDestinationFinalize(dst) else { throw Failure(reason: "the new file could not be written") }

    if webp {
        // ImageIO cannot write WebP: cwebp makes it from the PNG
        let cwebp = ProcessInfo.processInfo.environment["LOTUS_CWEBP"] ?? "cwebp"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [cwebp, "-quiet", "-q", String(job.quality > 0 ? job.quality : 85), "-metadata", "exif,icc", tmp, "-o", tmp + ".webp"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw Failure(reason: "cwebp is needed for WebP: brew install webp") }
        p.waitUntilExit()
        defer { try? FileManager.default.removeItem(atPath: tmp + ".webp") }
        guard p.terminationStatus == 0 else { throw Failure(reason: "cwebp could not make the WebP") }
        try? FileManager.default.removeItem(atPath: tmp)
        try FileManager.default.moveItem(atPath: tmp + ".webp", toPath: tmp)
    }
    if FileManager.default.fileExists(atPath: job.output) { try FileManager.default.removeItem(atPath: job.output) }
    try FileManager.default.moveItem(atPath: tmp, toPath: job.output)
    return "\(size(job.input)) \(size(job.output)) \(dw)x\(dh) \(img.width)x\(img.height)"
}

@main
struct Main {
    static func main() {
        let args = CommandLine.arguments
        if args.count > 1 && args[1] == "--formats" {
            for t in writable.sorted() { print(t) }
            return
        }
        var n = 4
        if args.count > 2 && args[1] == "--jobs" { n = max(1, Int(args[2]) ?? 4) }
        var jobs: [Job] = []
        while let line = readLine() {
            let f = line.components(separatedBy: "\t")
            guard f.count >= 5 else { continue }
            jobs.append(Job(index: jobs.count + 1, input: f[0], output: f[1], type: f[2], quality: Int(f[3]) ?? 0, max: Int(f[4]) ?? 0))
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = n
        for job in jobs {
            queue.addOperation {
                say("start \(job.index)")
                do { say("done \(job.index) " + (try autoreleasepool { try convert(job) })) }
                catch let f as Failure { say("fail \(job.index) \(f.reason)") }
                catch { say("fail \(job.index) \(error.localizedDescription)") }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
    }
}
