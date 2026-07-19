import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Pure image work: decoding into a flat RGBA buffer, finding the content
/// bounding box, and encoding crops. Everything here is nonisolated so it can
/// run off the main actor.
enum TrimEngine {
    /// Refuse absurdly large bitmaps (120 megapixels ≈ 480 MB RGBA).
    static let maxPixels = 120_000_000

    // MARK: - Decoding

    nonisolated static func load(url: URL) -> LoadedImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        return finish(cg: cg, name: url.deletingPathExtension().lastPathComponent, url: url)
    }

    nonisolated static func load(data: Data, name: String) -> LoadedImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        return finish(cg: cg, name: name, url: nil)
    }

    private nonisolated static func finish(cg: CGImage, name: String, url: URL?) -> LoadedImage? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, w * h <= maxPixels else { return nil }

        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: bpr * h)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                      data: raw.baseAddress, width: w, height: h,
                      bitsPerComponent: 8, bytesPerRow: bpr, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        var opaque = true
        var i = 3
        while i < pixels.count {
            if pixels[i] != 255 { opaque = false; break }
            i += 4
        }

        let buffer = PixelBuffer(width: w, height: h, bytesPerRow: bpr, data: pixels)
        return LoadedImage(name: name, url: url, image: ImageBox(cg), buffer: buffer, isOpaque: opaque)
    }

    // MARK: - Analysis

    /// Finds the tightest bounding box of "content" pixels, in top-left-origin
    /// pixel coordinates (directly usable with CGImage.cropping(to:)).
    ///
    /// Background is: transparent pixels (alpha ≤ cut), plus either a solid
    /// uniform color detected from the four corners, or near-white pixels when
    /// the corners disagree. `tolerance` (0–100) widens all thresholds.
    /// Returns nil when every pixel matches the background.
    nonisolated static func contentRect(in buf: PixelBuffer, tolerance: Double) -> CGRect? {
        let w = buf.width, h = buf.height
        guard w > 0, h > 0 else { return nil }

        let t = min(max(tolerance / 100.0, 0), 1)
        let alphaCut = Int((t * 128).rounded())
        let delta = Int((t * 128).rounded())
        let whiteCut = 255 - delta

        let uniformBG = detectUniformBackground(in: buf)

        return buf.data.withUnsafeBufferPointer { ptr -> CGRect? in
            let bpr = buf.bytesPerRow
            let uniform = uniformBG != nil
            let bgR = uniformBG?.0 ?? 255
            let bgG = uniformBG?.1 ?? 255
            let bgB = uniformBG?.2 ?? 255

            @inline(__always)
            func isContent(_ x: Int, _ y: Int) -> Bool {
                let i = y * bpr + x * 4
                let a = Int(ptr[i + 3])
                if a <= alphaCut { return false }
                var r = Int(ptr[i]), g = Int(ptr[i + 1]), b = Int(ptr[i + 2])
                if a < 255 {  // unpremultiply
                    r = min(255, r * 255 / a)
                    g = min(255, g * 255 / a)
                    b = min(255, b * 255 / a)
                }
                if uniform {
                    return abs(r - bgR) > delta || abs(g - bgG) > delta || abs(b - bgB) > delta
                }
                return r < whiteCut || g < whiteCut || b < whiteCut
            }

            // Top edge.
            var minY = -1
            var y = 0
            topScan: while y < h {
                var x = 0
                while x < w {
                    if isContent(x, y) { minY = y; break topScan }
                    x += 1
                }
                y += 1
            }
            guard minY >= 0 else { return nil }

            // Bottom edge.
            var maxY = minY
            y = h - 1
            bottomScan: while y > minY {
                var x = 0
                while x < w {
                    if isContent(x, y) { maxY = y; break bottomScan }
                    x += 1
                }
                y -= 1
            }

            // Left/right edges: only probe outside the running bounds.
            var minX = w
            var maxX = -1
            for row in minY...maxY {
                var x = 0
                while x < minX {
                    if isContent(x, row) { minX = x; break }
                    x += 1
                }
                var xr = w - 1
                while xr > maxX {
                    if isContent(xr, row) { maxX = xr; break }
                    xr -= 1
                }
            }
            guard maxX >= minX else { return nil }

            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    /// Samples a small patch in each corner. If all four are opaque and agree
    /// on a color, that color is the background — whatever it is.
    private nonisolated static func detectUniformBackground(in buf: PixelBuffer) -> (Int, Int, Int)? {
        let w = buf.width, h = buf.height
        let k = min(3, w, h)
        guard k > 0 else { return nil }

        return buf.data.withUnsafeBufferPointer { ptr -> (Int, Int, Int)? in
            func patch(_ x0: Int, _ y0: Int) -> (r: Int, g: Int, b: Int, a: Int) {
                var r = 0, g = 0, b = 0, a = 0
                for y in y0..<(y0 + k) {
                    for x in x0..<(x0 + k) {
                        let i = y * buf.bytesPerRow + x * 4
                        let pa = Int(ptr[i + 3])
                        a += pa
                        if pa > 0 {
                            r += min(255, Int(ptr[i]) * 255 / pa)
                            g += min(255, Int(ptr[i + 1]) * 255 / pa)
                            b += min(255, Int(ptr[i + 2]) * 255 / pa)
                        }
                    }
                }
                let n = k * k
                return (r / n, g / n, b / n, a / n)
            }

            let corners = [
                patch(0, 0), patch(w - k, 0),
                patch(0, h - k), patch(w - k, h - k),
            ]
            // Transparent corners are already handled by the alpha test.
            guard corners.allSatisfy({ $0.a >= 240 }) else { return nil }

            let agreement = 14
            let first = corners[0]
            for c in corners.dropFirst() {
                if abs(c.r - first.r) > agreement
                    || abs(c.g - first.g) > agreement
                    || abs(c.b - first.b) > agreement {
                    return nil
                }
            }
            let n = corners.count
            return (
                corners.reduce(0) { $0 + $1.r } / n,
                corners.reduce(0) { $0 + $1.g } / n,
                corners.reduce(0) { $0 + $1.b } / n
            )
        }
    }

    // MARK: - Encoding

    nonisolated static func pngData(from cg: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: cg.width, height: cg.height)
        return rep.representation(using: .png, properties: [:])
    }

    nonisolated static func jpegData(from cg: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: cg.width, height: cg.height)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }
}
