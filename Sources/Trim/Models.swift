import AppKit
import CoreGraphics
import Foundation
import SwiftUI

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

    /// Straight (unpremultiplied) color at a pixel, or nil when out of bounds.
    func color(atX x: Int, y: Int) -> RGB? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = y * bytesPerRow + x * 4
        let a = Int(data[i + 3])
        guard a > 0 else { return RGB(r: 255, g: 255, b: 255) }
        return RGB(r: min(255, Int(data[i]) * 255 / a),
                   g: min(255, Int(data[i + 1]) * 255 / a),
                   b: min(255, Int(data[i + 2]) * 255 / a))
    }
}

struct RGB: Sendable, Equatable, Hashable {
    var r: Int
    var g: Int
    var b: Int

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(r: Int, g: Int, b: Int) {
        self.r = min(max(r, 0), 255)
        self.g = min(max(g, 0), 255)
        self.b = min(max(b, 0), 255)
    }

    init?(nsColor: NSColor) {
        guard let c = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(r: Int((c.redComponent * 255).rounded()),
                  g: Int((c.greenComponent * 255).rounded()),
                  b: Int((c.blueComponent * 255).rounded()))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    /// Packed as 0xRRGGBB so it round-trips through UserDefaults as an Int.
    var packed: Int { r << 16 | g << 8 | b }
    init(packed: Int) {
        self.init(r: (packed >> 16) & 0xFF, g: (packed >> 8) & 0xFF, b: packed & 0xFF)
    }
}

/// Result of decoding an image off the main actor.
struct LoadedImage: Sendable {
    let name: String
    let url: URL?
    let image: ImageBox
    let buffer: PixelBuffer
    let isOpaque: Bool
}

/// What counts as background when scanning for content.
enum BackgroundMode: String, CaseIterable, Identifiable, Sendable {
    /// Sample the four corners; fall back to near-white when they disagree.
    case auto
    case white
    case black
    /// Only fully/mostly transparent pixels are background.
    case transparency
    /// A specific color, usually eyedropped from the image.
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .white: return "White"
        case .black: return "Black"
        case .transparency: return "Transparent only"
        case .custom: return "Custom color"
        }
    }
}

/// Resolved background rule handed to the (nonisolated) engine.
enum BackgroundSpec: Sendable, Equatable {
    case auto
    case color(RGB)
    case transparencyOnly
}

/// Which sides Trim is allowed to cut.
struct EdgeSet: OptionSet, Sendable, Equatable {
    let rawValue: Int
    static let top = EdgeSet(rawValue: 1 << 0)
    static let left = EdgeSet(rawValue: 1 << 1)
    static let bottom = EdgeSet(rawValue: 1 << 2)
    static let right = EdgeSet(rawValue: 1 << 3)
    static let all: EdgeSet = [.top, .left, .bottom, .right]
}

enum AspectRatio: String, CaseIterable, Identifiable, Sendable {
    case free, square, fourThree, threeTwo, sixteenNine, original

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .threeTwo: return "3:2"
        case .sixteenNine: return "16:9"
        case .original: return "Original"
        }
    }

    /// width / height, or nil when the crop is unconstrained.
    func value(originalWidth: Int, originalHeight: Int) -> CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeTwo: return 3.0 / 2.0
        case .sixteenNine: return 16.0 / 9.0
        case .original:
            guard originalHeight > 0 else { return nil }
            return CGFloat(originalWidth) / CGFloat(originalHeight)
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    /// Match the source: PNG unless the original was an opaque JPEG.
    case matchSource, png, jpeg, tiff

    var id: String { rawValue }

    var label: String {
        switch self {
        case .matchSource: return "Match source"
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }
}

/// Result of one content scan.
struct TrimResult: Sendable, Equatable {
    /// nil means every pixel matched the background.
    var rect: CGRect?
    /// The color treated as background, or nil when only alpha was used.
    var background: RGB?
}

enum Analysis: Equatable {
    case pending
    case done(TrimResult)

    var result: TrimResult? {
        if case .done(let r) = self { return r }
        return nil
    }
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
