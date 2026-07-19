import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var items: [TrimItem] = []
    @Published var selectedID: TrimItem.ID?
    @Published var tolerance: Double = 10 {
        didSet { if tolerance != oldValue { scheduleRecompute() } }
    }
    @Published var padding: Int = 0
    @Published var statusMessage: String?
    @Published var isLoading = false

    private var recomputeTask: Task<Void, Never>?

    var selectedItem: TrimItem? { items.first { $0.id == selectedID } }

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

    func clearAll() {
        recomputeTask?.cancel()
        items.removeAll()
        selectedID = nil
        statusMessage = nil
    }

    // MARK: - Analysis

    func scheduleRecompute(debounce: Bool = true) {
        recomputeTask?.cancel()
        let tol = tolerance
        recomputeTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled, let self else { return }
            await self.recomputeAll(tolerance: tol)
        }
    }

    private func recomputeAll(tolerance: Double) async {
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
            let rect = await Task.detached(priority: .userInitiated) {
                TrimEngine.contentRect(in: buffer, tolerance: tolerance)
            }.value
            guard !Task.isCancelled, self.tolerance == tolerance else { return }
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].analysis = .done(rect)
            }
        }
    }

    // MARK: - Crop geometry

    private func padded(_ rect: CGRect, in item: TrimItem) -> CGRect {
        guard padding > 0 else { return rect }
        return rect
            .insetBy(dx: -CGFloat(padding), dy: -CGFloat(padding))
            .intersection(item.fullRect)
    }

    /// Crop rect for display; nil while pending or when there is no content.
    func paddedCropRect(for item: TrimItem) -> CGRect? {
        guard case .done(let rect?) = item.analysis else { return nil }
        return padded(rect, in: item)
    }

    /// Crop rect for export; computes synchronously if analysis hasn't landed.
    func resolvedCropRect(for item: TrimItem) -> CGRect? {
        switch item.analysis {
        case .done(let rect):
            guard let rect else { return nil }
            return padded(rect, in: item)
        case .pending:
            let rect = TrimEngine.contentRect(in: item.buffer, tolerance: tolerance)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].analysis = .done(rect)
            }
            guard let rect else { return nil }
            return padded(rect, in: item)
        }
    }

    func croppedImage(for item: TrimItem) -> CGImage? {
        guard let rect = resolvedCropRect(for: item) else { return nil }
        return item.image.cg.cropping(to: rect)
    }

    // MARK: - Export

    func saveSelected() {
        guard let item = selectedItem else { return }
        guard let cg = croppedImage(for: item) else {
            statusMessage = "Nothing to save — the whole image matches the background."
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        if item.isOpaque {
            panel.allowedContentTypes = item.prefersJPEG ? [.jpeg, .png] : [.png, .jpeg]
        } else {
            panel.allowedContentTypes = [.png]
        }
        panel.nameFieldStringValue = item.name + "-trimmed." + (item.prefersJPEG ? "jpg" : "png")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let wantsJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let data = wantsJPEG ? TrimEngine.jpegData(from: cg) : TrimEngine.pngData(from: cg)
        do {
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url)
            statusMessage = "Saved \(url.lastPathComponent)."
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
            let ext = item.prefersJPEG ? "jpg" : "png"
            var url = dir.appendingPathComponent("\(item.name)-trimmed.\(ext)")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = dir.appendingPathComponent("\(item.name)-trimmed-\(n).\(ext)")
                n += 1
            }
            let data = item.prefersJPEG ? TrimEngine.jpegData(from: cg) : TrimEngine.pngData(from: cg)
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

    /// Provides the trimmed PNG as a file for drag-out of the preview.
    func dragProvider(for item: TrimItem) -> NSItemProvider? {
        guard let cg = croppedImage(for: item),
              let data = TrimEngine.pngData(from: cg) else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrimDrags", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(item.name)-trimmed.png")
        try? FileManager.default.removeItem(at: url)
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        return NSItemProvider(contentsOf: url)
    }
}
