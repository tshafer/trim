import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var items: [TrimItem] = []
    @Published var selectedID: TrimItem.ID?
    @Published var statusMessage: String?
    @Published var isLoading = false
    /// While true, a click on the preview eyedrops the background color.
    @Published var isPickingColor = false

    // MARK: - Settings (persisted)

    @Published var tolerance: Double = 10 {
        didSet {
            guard tolerance != oldValue else { return }
            store(.tolerance, tolerance)
            scheduleRecompute()
        }
    }
    @Published var padding: Int = 0 {
        didSet { store(.padding, padding) }
    }
    @Published var backgroundMode: BackgroundMode = .auto {
        didSet {
            guard backgroundMode != oldValue else { return }
            store(.backgroundMode, backgroundMode.rawValue)
            scheduleRecompute(debounce: false)
        }
    }
    @Published var customColor: RGB = RGB(r: 255, g: 255, b: 255) {
        didSet {
            guard customColor != oldValue else { return }
            store(.customColor, customColor.packed)
            if backgroundMode == .custom { scheduleRecompute() }
        }
    }
    @Published var trimEdges: EdgeSet = .all {
        didSet { store(.trimEdges, trimEdges.rawValue) }
    }
    @Published var aspect: AspectRatio = .free {
        didSet { store(.aspect, aspect.rawValue) }
    }
    @Published var exportFormat: ExportFormat = .matchSource {
        didSet { store(.exportFormat, exportFormat.rawValue) }
    }
    /// 0.05–1.0, used only for JPEG.
    @Published var jpegQuality: Double = 0.92 {
        didSet { store(.jpegQuality, jpegQuality) }
    }
    /// Output scale multiplier applied after cropping.
    @Published var exportScale: Double = 1.0 {
        didSet { store(.exportScale, exportScale) }
    }

    private var recomputeTask: Task<Void, Never>?

    var selectedItem: TrimItem? { items.first { $0.id == selectedID } }

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: Key.tolerance.rawValue) != nil {
            tolerance = d.double(forKey: Key.tolerance.rawValue)
        }
        padding = d.integer(forKey: Key.padding.rawValue)
        if let raw = d.string(forKey: Key.backgroundMode.rawValue),
           let mode = BackgroundMode(rawValue: raw) {
            backgroundMode = mode
        }
        if d.object(forKey: Key.customColor.rawValue) != nil {
            customColor = RGB(packed: d.integer(forKey: Key.customColor.rawValue))
        }
        if d.object(forKey: Key.trimEdges.rawValue) != nil {
            trimEdges = EdgeSet(rawValue: d.integer(forKey: Key.trimEdges.rawValue))
        }
        if let raw = d.string(forKey: Key.aspect.rawValue), let a = AspectRatio(rawValue: raw) {
            aspect = a
        }
        if let raw = d.string(forKey: Key.exportFormat.rawValue),
           let f = ExportFormat(rawValue: raw) {
            exportFormat = f
        }
        if d.object(forKey: Key.jpegQuality.rawValue) != nil {
            jpegQuality = d.double(forKey: Key.jpegQuality.rawValue)
        }
        if d.object(forKey: Key.exportScale.rawValue) != nil {
            exportScale = d.double(forKey: Key.exportScale.rawValue)
        }
    }

    private enum Key: String {
        case tolerance, padding, backgroundMode, customColor, trimEdges
        case aspect, exportFormat, jpegQuality, exportScale
    }

    private func store(_ key: Key, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    func resetSettings() {
        tolerance = 10
        padding = 0
        backgroundMode = .auto
        customColor = RGB(r: 255, g: 255, b: 255)
        trimEdges = .all
        aspect = .free
        exportFormat = .matchSource
        jpegQuality = 0.92
        exportScale = 1.0
        statusMessage = "Settings reset."
    }

    // MARK: - Loading

    func openImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose images to trim."
        guard panel.runModal() == .OK else { return }
        loadURLs(panel.urls)
    }

    func loadURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isLoading = true
        Task {
            var loaded: [LoadedImage] = []
            var failures = 0
            for url in urls {
                let result = await Task.detached(priority: .userInitiated) {
                    TrimEngine.load(url: url)
                }.value
                if let result { loaded.append(result) } else { failures += 1 }
            }
            isLoading = false
            append(loaded, failures: failures)
        }
    }

    func loadImageData(_ data: Data, name: String) {
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                TrimEngine.load(data: data, name: name)
            }.value
            isLoading = false
            append(result.map { [$0] } ?? [], failures: result == nil ? 1 : 0)
        }
    }

    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let objects = pb.readObjects(forClasses: [NSURL.self], options: options),
           !objects.isEmpty {
            loadURLs(objects.compactMap { $0 as? URL })
            return
        }
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            loadImageData(data, name: pastedName())
            return
        }
        statusMessage = "No image on the clipboard."
    }

    private var pasteCounter = 0
    private func pastedName() -> String {
        pasteCounter += 1
        return pasteCounter == 1 ? "Pasted image" : "Pasted image \(pasteCounter)"
    }

    private func append(_ loaded: [LoadedImage], failures: Int) {
        var newItems: [TrimItem] = []
        for li in loaded {
            let ns = NSImage(cgImage: li.image.cg,
                             size: NSSize(width: li.buffer.width, height: li.buffer.height))
            newItems.append(TrimItem(
                name: li.name, sourceURL: li.url, image: li.image,
                buffer: li.buffer, isOpaque: li.isOpaque, nsImage: ns))
        }
        items.append(contentsOf: newItems)
        if let first = newItems.first { selectedID = first.id }
        if failures > 0 {
            statusMessage = failures == 1
                ? "One item couldn’t be read as an image."
                : "\(failures) items couldn’t be read as images."
        } else if !newItems.isEmpty {
            statusMessage = nil
        }
        if !newItems.isEmpty { scheduleRecompute(debounce: false) }
    }

    func removeSelected() {
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: idx)
        selectedID = items.indices.contains(idx) ? items[idx].id : items.last?.id
    }

    func remove(_ item: TrimItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: idx)
        if selectedID == item.id {
            selectedID = items.indices.contains(idx) ? items[idx].id : items.last?.id
        }
    }

    func clearAll() {
        recomputeTask?.cancel()
        items.removeAll()
        selectedID = nil
        statusMessage = nil
    }

    /// Moves the selection through the batch (⌘↓ / ⌘↑).
    func selectOffset(_ offset: Int) {
        guard items.count > 1 else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        let next = (current + offset + items.count) % items.count
        selectedID = items[next].id
    }

    func revealSelectedSource() {
        guard let url = selectedItem?.sourceURL else {
            statusMessage = "That image didn’t come from a file."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Analysis

    var backgroundSpec: BackgroundSpec {
        switch backgroundMode {
        case .auto: return .auto
        case .white: return .color(RGB(r: 255, g: 255, b: 255))
        case .black: return .color(RGB(r: 0, g: 0, b: 0))
        case .transparency: return .transparencyOnly
        case .custom: return .color(customColor)
        }
    }

    func scheduleRecompute(debounce: Bool = true) {
        recomputeTask?.cancel()
        let tol = tolerance
        let spec = backgroundSpec
        recomputeTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled, let self else { return }
            await self.recomputeAll(tolerance: tol, spec: spec)
        }
    }

    private func recomputeAll(tolerance: Double, spec: BackgroundSpec) async {
        // Selected item first so the visible preview updates immediately.
        var ids = items.map(\.id)
        if let sel = selectedID, let idx = ids.firstIndex(of: sel) {
            ids.remove(at: idx)
            ids.insert(sel, at: 0)
        }
        for id in ids {
            guard !Task.isCancelled else { return }
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let buffer = item.buffer
            let result = await Task.detached(priority: .userInitiated) {
                TrimEngine.contentRect(in: buffer, tolerance: tolerance, spec: spec)
            }.value
            guard !Task.isCancelled, self.tolerance == tolerance, self.backgroundSpec == spec
            else { return }
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].analysis = .done(result)
            }
        }
    }

    // MARK: - Eyedropper

    /// Samples the image at a pixel coordinate and adopts it as the background.
    func pickColor(in item: TrimItem, atX x: Int, y: Int) {
        guard let rgb = item.buffer.color(atX: x, y: y) else { return }
        customColor = rgb
        if backgroundMode != .custom {
            backgroundMode = .custom  // triggers its own rescan
        } else {
            scheduleRecompute(debounce: false)
        }
        isPickingColor = false
        statusMessage = "Background set to \(rgb.hex)."
    }

    // MARK: - Crop geometry

    /// content rect → edge locks → padding → aspect ratio, clamped to the image.
    private func shape(_ rect: CGRect, in item: TrimItem) -> CGRect {
        let full = item.fullRect
        var r = rect

        if !trimEdges.contains(.top) {
            r.size.height += r.minY
            r.origin.y = 0
        }
        if !trimEdges.contains(.left) {
            r.size.width += r.minX
            r.origin.x = 0
        }
        if !trimEdges.contains(.bottom) { r.size.height = full.height - r.minY }
        if !trimEdges.contains(.right) { r.size.width = full.width - r.minX }

        if padding > 0 {
            r = r.insetBy(dx: -CGFloat(padding), dy: -CGFloat(padding)).intersection(full)
        }
        if let ratio = aspect.value(originalWidth: item.pixelWidth, originalHeight: item.pixelHeight) {
            r = expand(r, toRatio: ratio, in: full)
        }
        return r.intersection(full).integral
    }

    /// Grows the short side to hit `ratio`, staying inside `full`; shrinks the
    /// long side instead when there isn't room to grow.
    private func expand(_ rect: CGRect, toRatio ratio: CGFloat, in full: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0, ratio > 0 else { return rect }
        var w = rect.width
        var h = rect.height
        if w / h < ratio { w = h * ratio } else { h = w / ratio }
        if w > full.width {
            w = full.width
            h = w / ratio
        }
        if h > full.height {
            h = full.height
            w = h * ratio
        }
        let x = min(max(0, (rect.midX - w / 2).rounded()), full.width - w.rounded())
        let y = min(max(0, (rect.midY - h / 2).rounded()), full.height - h.rounded())
        return CGRect(x: x, y: y, width: w.rounded(), height: h.rounded())
    }

    /// Crop rect for display; nil while pending or when there is no content.
    func paddedCropRect(for item: TrimItem) -> CGRect? {
        guard let rect = item.analysis.result?.rect else { return nil }
        return shape(rect, in: item)
    }

    /// Crop rect for export; computes synchronously if analysis hasn't landed.
    func resolvedCropRect(for item: TrimItem) -> CGRect? {
        switch item.analysis {
        case .done(let result):
            guard let rect = result.rect else { return nil }
            return shape(rect, in: item)
        case .pending:
            let result = TrimEngine.contentRect(
                in: item.buffer, tolerance: tolerance, spec: backgroundSpec)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].analysis = .done(result)
            }
            guard let rect = result.rect else { return nil }
            return shape(rect, in: item)
        }
    }

    /// How many pixels come off each side, for the readout.
    func trimInsets(for item: TrimItem) -> (top: Int, left: Int, bottom: Int, right: Int)? {
        guard let crop = paddedCropRect(for: item) else { return nil }
        let full = item.fullRect
        return (
            top: Int(crop.minY),
            left: Int(crop.minX),
            bottom: Int(full.maxY - crop.maxY),
            right: Int(full.maxX - crop.maxX)
        )
    }

    /// Final pixel size after cropping and scaling.
    func outputSize(for item: TrimItem) -> (width: Int, height: Int)? {
        guard let crop = paddedCropRect(for: item) else { return nil }
        return (max(1, Int((crop.width * exportScale).rounded())),
                max(1, Int((crop.height * exportScale).rounded())))
    }

    func croppedImage(for item: TrimItem) -> CGImage? {
        guard let rect = resolvedCropRect(for: item),
              let cropped = item.image.cg.cropping(to: rect) else { return nil }
        return TrimEngine.scaled(cropped, by: exportScale)
    }

    // MARK: - Export

    private func exportData(for item: TrimItem, _ cg: CGImage, format: ExportFormat) -> Data? {
        TrimEngine.data(from: cg, format: format,
                        prefersJPEG: item.prefersJPEG, jpegQuality: jpegQuality)
    }

    private func suggestedExtension(for item: TrimItem) -> String {
        TrimEngine.fileExtension(for: exportFormat, prefersJPEG: item.prefersJPEG)
    }

    func saveSelected() {
        guard let item = selectedItem else { return }
        guard let cg = croppedImage(for: item) else {
            statusMessage = "Nothing to save — the whole image matches the background."
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let preferred = suggestedExtension(for: item)
        panel.allowedContentTypes = [UTType(filenameExtension: preferred) ?? .png, .png, .jpeg, .tiff]
        panel.nameFieldStringValue = item.name + "-trimmed." + preferred
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format: ExportFormat
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": format = .jpeg
        case "tif", "tiff": format = .tiff
        case "png": format = .png
        default: format = exportFormat
        }
        do {
            guard let data = exportData(for: item, cg, format: format) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url)
            statusMessage = "Saved \(url.lastPathComponent) — \(cg.width) × \(cg.height) px."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func copySelected() {
        guard let item = selectedItem, let cg = croppedImage(for: item) else {
            statusMessage = "Nothing to copy at this tolerance."
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        var wrote = false
        if let png = TrimEngine.pngData(from: cg) {
            wrote = pb.setData(png, forType: .png) || wrote
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let tiff = rep.tiffRepresentation {
            wrote = pb.setData(tiff, forType: .tiff) || wrote
        }
        statusMessage = wrote ? "Copied \(cg.width) × \(cg.height) px." : "Copy failed."
    }

    func trimAll() {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the trimmed copies."
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        var written = 0
        var skipped = 0
        for item in items {
            guard let cg = croppedImage(for: item) else { skipped += 1; continue }
            let ext = suggestedExtension(for: item)
            var url = dir.appendingPathComponent("\(item.name)-trimmed.\(ext)")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = dir.appendingPathComponent("\(item.name)-trimmed-\(n).\(ext)")
                n += 1
            }
            let data = exportData(for: item, cg, format: exportFormat)
            if let data, (try? data.write(to: url)) != nil {
                written += 1
            } else {
                skipped += 1
            }
        }
        statusMessage = skipped == 0
            ? "Exported \(written) trimmed image\(written == 1 ? "" : "s")."
            : "Exported \(written), skipped \(skipped) (all-background or unwritable)."
    }

    /// Provides the trimmed image as a file for drag-out of the preview.
    func dragProvider(for item: TrimItem) -> NSItemProvider? {
        guard let cg = croppedImage(for: item) else { return nil }
        let ext = suggestedExtension(for: item)
        guard let data = exportData(for: item, cg, format: exportFormat) else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrimDrags", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(item.name)-trimmed.\(ext)")
        try? FileManager.default.removeItem(at: url)
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        return NSItemProvider(contentsOf: url)
    }
}
