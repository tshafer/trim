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
    }
}
