import SwiftUI

@main
struct TrimApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Trim", id: "main") {
            ContentView()
                .environmentObject(state)
        }
        .defaultSize(width: 780, height: 620)
        .commands {
            TrimCommands(state: state)
        }
    }
}

struct TrimCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { state.openImages() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Trimmed…") { state.saveSelected() }
                .keyboardShortcut("s")
                .disabled(state.selectedItem == nil)
            Button("Trim All…") { state.trimAll() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state.items.isEmpty)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Copy Trimmed Image") { state.copySelected() }
                .keyboardShortcut("c")
                .disabled(state.selectedItem == nil)
            Button("Paste Image") { state.pasteFromClipboard() }
                .keyboardShortcut("v")
            Divider()
            Button("Remove Image") { state.removeSelected() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(state.selectedItem == nil)
            Button("Clear All") { state.clearAll() }
                .disabled(state.items.isEmpty)
        }
        CommandMenu("Image") {
            Button(state.isPickingColor ? "Stop Sampling" : "Sample Background Color…") {
                state.isPickingColor.toggle()
            }
            .keyboardShortcut("p")
            .disabled(state.selectedItem == nil)
            Menu("Background") {
                ForEach(BackgroundMode.allCases) { mode in
                    Button(mode.label) { state.backgroundMode = mode }
                }
            }
            Menu("Aspect Ratio") {
                ForEach(AspectRatio.allCases) { ratio in
                    Button(ratio.label) { state.aspect = ratio }
                }
            }
            Divider()
            Button("Reveal Original in Finder") { state.revealSelectedSource() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.selectedItem?.sourceURL == nil)
            Button("Reset Settings") { state.resetSettings() }
            Divider()
            Button("Next Image") { state.selectOffset(1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(state.items.count < 2)
            Button("Previous Image") { state.selectOffset(-1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(state.items.count < 2)
        }
    }
}
