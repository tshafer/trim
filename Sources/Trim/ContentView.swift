import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if state.items.isEmpty {
                EmptyDropView(isTargeted: isDropTargeted, isLoading: state.isLoading)
            } else {
                HStack(spacing: 0) {
                    if state.items.count > 1 {
                        BatchSidebar()
                        Divider()
                    }
                    DetailView()
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.openImages()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open images (⌘O)")
                Button {
                    state.clearAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Remove all images")
                .disabled(state.items.isEmpty)
            }
        }
        .navigationTitle(state.selectedItem.map { "Trim — \($0.name)" } ?? "Trim")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                let appState = state
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let direct = item as? URL {
                        url = direct
                    }
                    if let url {
                        Task { @MainActor in appState.loadURLs([url]) }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                accepted = true
                let appState = state
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let data = (object as? NSImage)?.tiffRepresentation else { return }
                    Task { @MainActor in appState.loadImageData(data, name: "Dropped image") }
                }
            }
        }
        return accepted
    }
}

// MARK: - Empty state

struct EmptyDropView: View {
    let isTargeted: Bool
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "crop")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            if isLoading {
                ProgressView()
            } else {
                Text("Drop an image to trim its margins")
                    .font(.title3)
                Text("Transparent and solid-color borders are cut away automatically.")
                    .foregroundStyle(.secondary)
                Text("⌘O to open  ·  ⌘V to paste")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(20)
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

// MARK: - Batch sidebar

struct BatchSidebar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: $state.selectedID) {
            ForEach(state.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)
                    Text(subtitle(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
                .tag(item.id)
                .contextMenu {
                    Button("Remove") { state.remove(item) }
                    if item.sourceURL != nil {
                        Button("Reveal in Finder") {
                            state.selectedID = item.id
                            state.revealSelectedSource()
                        }
                    }
                }
            }
        }
        .frame(width: 220)
    }

    private func subtitle(for item: TrimItem) -> String {
        let w = item.pixelWidth, h = item.pixelHeight
        switch item.analysis {
        case .pending:
            return "\(w) × \(h) — scanning…"
        case .done(let result):
            guard result.rect != nil else { return "\(w) × \(h) — all background" }
            if let out = state.outputSize(for: item) {
                return "\(w) × \(h) → \(out.width) × \(out.height)"
            }
            return "\(w) × \(h)"
        }
    }
}

// MARK: - Detail

struct DetailView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let item = state.selectedItem {
                PreviewView(item: item, cropRect: state.paddedCropRect(for: item))
                    .padding(16)
                Divider()
                ControlsBar(item: item)
            } else {
                Text("Select an image from the list")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Preview with crop overlay

struct PreviewView: View {
    @EnvironmentObject private var state: AppState
    let item: TrimItem
    let cropRect: CGRect?

    var body: some View {
        GeometryReader { geo in
            let iw = CGFloat(item.pixelWidth)
            let ih = CGFloat(item.pixelHeight)
            let scale = min(geo.size.width / iw, geo.size.height / ih)
            let dw = iw * scale
            let dh = ih * scale
            let ox = (geo.size.width - dw) / 2
            let oy = (geo.size.height - dh) / 2
            let imageFrame = CGRect(x: ox, y: oy, width: dw, height: dh)

            ZStack(alignment: .topLeading) {
                Checkerboard()
                    .frame(width: dw, height: dh)
                    .offset(x: ox, y: oy)
                Image(nsImage: item.nsImage)
                    .resizable()
                    .interpolation(scale < 1 ? .high : .none)
                    .frame(width: dw, height: dh)
                    .offset(x: ox, y: oy)
                if let crop = cropRect {
                    let displayCrop = CGRect(
                        x: ox + crop.minX * scale,
                        y: oy + crop.minY * scale,
                        width: crop.width * scale,
                        height: crop.height * scale)
                    DimmedMargins(outer: imageFrame, inner: displayCrop)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .modifier(PreviewInteraction(
                item: item, imageFrame: imageFrame, scale: scale))
        }
        .overlay(alignment: .top) {
            if state.isPickingColor {
                Text("Click a background pixel to sample it  ·  esc to cancel")
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 6)
            }
        }
        .help(state.isPickingColor
              ? "Click to sample the background color"
              : "Drag out to export the trimmed image")
    }
}

/// Click-to-eyedrop while picking; drag-out-to-export otherwise.
private struct PreviewInteraction: ViewModifier {
    @EnvironmentObject private var state: AppState
    let item: TrimItem
    let imageFrame: CGRect
    let scale: CGFloat

    func body(content: Content) -> some View {
        if state.isPickingColor {
            content
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    sample(at: value.location)
                })
                .onExitCommand { state.isPickingColor = false }
        } else {
            content.onDrag { state.dragProvider(for: item) ?? NSItemProvider() }
        }
    }

    private func sample(at point: CGPoint) {
        guard imageFrame.contains(point), scale > 0 else { return }
        let x = Int((point.x - imageFrame.minX) / scale)
        let y = Int((point.y - imageFrame.minY) / scale)
        state.pickColor(in: item, atX: x, y: y)
    }
}

struct DimmedMargins: View {
    let outer: CGRect
    let inner: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(outer)
                p.addRect(inner.intersection(outer))
            }
            .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true, antialiased: true))
            Path { p in
                p.addRect(inner)
            }
            .stroke(Color.accentColor, lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(nsColor: .textBackgroundColor)))
            let s: CGFloat = 8
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : s
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(.gray.opacity(0.18)))
                    x += s * 2
                }
                y += s
                row += 1
            }
        }
        .clipped()
    }
}

// MARK: - Controls

struct ControlsBar: View {
    @EnvironmentObject private var state: AppState
    let item: TrimItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Tolerance")
                Slider(value: $state.tolerance, in: 0...100)
                    .frame(minWidth: 120, maxWidth: 220)
                Text("\(Int(state.tolerance))")
                    .monospacedDigit()
                    .frame(width: 26, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Divider().frame(height: 18)
                Stepper("Padding: \(state.padding) px", value: $state.padding, in: 0...256)
                    .fixedSize()
                Divider().frame(height: 18)
                Picker("Aspect", selection: $state.aspect) {
                    ForEach(AspectRatio.allCases) { Text($0.label).tag($0) }
                }
                .fixedSize()
                .help("Grow the crop to a fixed aspect ratio")
                Spacer()
            }

            HStack(spacing: 12) {
                BackgroundControls()
                Divider().frame(height: 18)
                EdgeToggles()
                Spacer()
                ExportOptionsButton()
                Button("Copy") { state.copySelected() }
                    .help("Copy the trimmed image (⌘C)")
                Button("Save…") { state.saveSelected() }
                    .buttonStyle(.borderedProminent)
                    .help("Save the trimmed image (⌘S)")
                if state.items.count > 1 {
                    Button("Trim All…") { state.trimAll() }
                        .help("Export every image, trimmed, to a folder (⇧⌘S)")
                }
            }

            HStack {
                summaryText
                    .monospacedDigit()
                Spacer()
                if let message = state.statusMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.callout)
        }
        .padding(12)
    }

    @ViewBuilder
    private var summaryText: some View {
        let w = item.pixelWidth, h = item.pixelHeight
        switch item.analysis {
        case .pending:
            Text("\(w) × \(h) px — scanning…")
                .foregroundStyle(.secondary)
        case .done(let result):
            if result.rect == nil {
                Text("\(w) × \(h) px — nothing but background at this tolerance")
                    .foregroundStyle(.orange)
            } else if let crop = state.paddedCropRect(for: item),
                      let out = state.outputSize(for: item) {
                if crop == item.fullRect && state.exportScale == 1 {
                    Text("\(w) × \(h) px — already tight, no margins to trim")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Text("\(w) × \(h) px  →  \(out.width) × \(out.height) px")
                        if let insets = state.trimInsets(for: item) {
                            Text("cut \(insets.top) ↑ \(insets.right) → \(insets.bottom) ↓ \(insets.left) ←")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// Background source: auto-detect, a fixed color, alpha only, or eyedropped.
struct BackgroundControls: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Picker("Background", selection: $state.backgroundMode) {
                ForEach(BackgroundMode.allCases) { Text($0.label).tag($0) }
            }
            .fixedSize()

            if state.backgroundMode == .custom {
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .help(state.customColor.hex)
            } else if let detected = state.selectedItem?.analysis.result?.background {
                Swatch(color: detected.color)
                    .help("Detected background \(detected.hex)")
            }

            Button {
                state.isPickingColor.toggle()
            } label: {
                Image(systemName: "eyedropper")
            }
            .help("Sample the background color from the image (⌘P)")
            .background(state.isPickingColor
                        ? Color.accentColor.opacity(0.25) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { state.customColor.color },
            set: { newValue in
                if let rgb = RGB(nsColor: NSColor(newValue)) { state.customColor = rgb }
            })
    }
}

struct Swatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5)))
    }
}

/// Which sides Trim is allowed to cut.
struct EdgeToggles: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            Text("Edges").fixedSize()
            toggle(.top, symbol: "arrow.up.to.line", help: "Trim the top edge")
            toggle(.right, symbol: "arrow.right.to.line", help: "Trim the right edge")
            toggle(.bottom, symbol: "arrow.down.to.line", help: "Trim the bottom edge")
            toggle(.left, symbol: "arrow.left.to.line", help: "Trim the left edge")
        }
    }

    private func toggle(_ edge: EdgeSet, symbol: String, help: String) -> some View {
        Toggle(isOn: binding(edge)) {
            Image(systemName: symbol)
        }
        .toggleStyle(.button)
        .help(help)
    }

    private func binding(_ edge: EdgeSet) -> Binding<Bool> {
        Binding(
            get: { state.trimEdges.contains(edge) },
            set: { on in
                if on { state.trimEdges.insert(edge) } else { state.trimEdges.remove(edge) }
            })
    }
}

/// Format, quality, and output scale, tucked into a popover.
struct ExportOptionsButton: View {
    @EnvironmentObject private var state: AppState
    @State private var showing = false

    private static let scales: [Double] = [0.25, 0.5, 1.0, 2.0]

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Label("Options", systemImage: "slider.horizontal.3")
        }
        .help("Export format, quality, and scale")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            Form {
                Picker("Format", selection: $state.exportFormat) {
                    ForEach(ExportFormat.allCases) { Text($0.label).tag($0) }
                }
                if isJPEG {
                    HStack {
                        Slider(value: $state.jpegQuality, in: 0.3...1.0)
                        Text("\(Int(state.jpegQuality * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    .help("JPEG quality")
                }
                Picker("Scale", selection: $state.exportScale) {
                    ForEach(Self.scales, id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
                if let out = state.selectedItem.flatMap({ state.outputSize(for: $0) }) {
                    LabeledContent("Output", value: "\(out.width) × \(out.height) px")
                }
                Divider()
                Button("Reset to defaults") { state.resetSettings() }
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    private var isJPEG: Bool {
        let prefersJPEG = state.selectedItem?.prefersJPEG ?? false
        return TrimEngine.resolve(state.exportFormat, prefersJPEG: prefersJPEG) == .jpeg
    }
}
