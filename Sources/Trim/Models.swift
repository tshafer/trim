import AppKit
import CoreGraphics
import Foundation

/// Immutable CGImage wrapper so decoded images can cross actor boundaries.
/// CGImage is immutable after creation, so this is safe in practice.
final class ImageBox: @unchecked Sendable {
    let cg: CGImage
    init(_ cg: CGImage) { self.cg = cg }
}

/// One flat RGBA8 (premultiplied-last, sRGB) copy of the bitmap.
/// Row 0 is the top scanline, matching CGImage.cropping(to:) coordinates.
struct PixelBuffer: Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]
}

/// Result of decoding an image off the main actor.
struct LoadedImage: Sendable {
    let name: String
    let url: URL?
    let image: ImageBox
    let buffer: PixelBuffer
    let isOpaque: Bool
}

enum Analysis: Equatable {
    case pending
    /// nil rect means the whole image matched the background.
    case done(CGRect?)
}

struct TrimItem: Identifiable {
    let id = UUID()
    let name: String
    let sourceURL: URL?
    let image: ImageBox
    let buffer: PixelBuffer
    let isOpaque: Bool
    let nsImage: NSImage
    var analysis: Analysis = .pending

    var pixelWidth: Int { buffer.width }
    var pixelHeight: Int { buffer.height }
    var fullRect: CGRect {
        CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
    }
    /// True when the source can be reasonably re-encoded as JPEG.
    var prefersJPEG: Bool {
        isOpaque && ["jpg", "jpeg"].contains(sourceURL?.pathExtension.lowercased() ?? "")
    }
}
