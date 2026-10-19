import AppKit
import SwiftUI

@main
struct SorcererApp: App {
    @State private var store = Store()

    init() {
        // Needed when launched with `swift run` instead of from the .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Onboarding is a fixed, compact window like the design; the workspace resizes freely.
                if store.settings.onboarded {
                    Workspace().frame(minWidth: 1100, minHeight: 700)
                } else {
                    Onboarding().frame(width: 1160, height: 720)
                }
            }
            .environment(store)
            .preferredColorScheme(.dark)
            .tint(.ember)
            .background(Color.ink)
            .onAppear { NSApp.activate() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands { SorcererCommands(store: store) }

        SwiftUI.Settings {
            SettingsWindow().environment(store).preferredColorScheme(.dark).tint(.ember)
        }
        .windowResizability(.contentSize)
    }
}

/// Menu bar: every screen and action, with its shortcut, so nothing is only a hidden button.
struct SorcererCommands: Commands {
    var store: Store
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Task { await store.updater.check() } }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Experiment") { store.go(.new) }.keyboardShortcut("n")
            Button("Go to…") { store.paletteOpen = true }.keyboardShortcut("k")
        }
        CommandMenu("Go") {
            let inside = store.experiment != nil && store.settings.onboarded
            Button("Feed") { store.go(.feed) }.keyboardShortcut("1").disabled(!inside)
            Button("Characters") { store.showCharacters() }.keyboardShortcut("2").disabled(!inside)
            Button("Report") { store.go(.report) }.keyboardShortcut("3").disabled(!inside)
            Button("Context") { store.go(.context) }.keyboardShortcut("4").disabled(!inside)
            Divider()
            Button("Back") { store.goBack() }.keyboardShortcut("[").disabled(store.back.isEmpty)
            Button("Forward") { store.goForward() }.keyboardShortcut("]").disabled(store.forward.isEmpty)
        }
        CommandGroup(after: .appSettings) {
            Button("Providers & Models…") { store.settingsPane = .providers; openSettings() }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            Button("Limits & Pacing…") { store.settingsPane = .limits; openSettings() }
        }
        CommandMenu("Experiment") {
            let ready = store.branch != nil && store.settings.onboarded
            Button(store.running ? "Pause" : "Run") { store.running ? store.pause() : store.run() }
                .keyboardShortcut("r").disabled(!ready)
            Button("Step One Round") { Task { await store.step() } }
                .keyboardShortcut(.rightArrow).disabled(!ready || store.busy != nil)
            Button("Inject an Event…") { store.go(.feed); store.focusInject += 1 }
                .keyboardShortcut("e").disabled(!ready)
            Button("Ask Everyone…") { store.go(.feed); store.focusPoll += 1 }
                .keyboardShortcut("p").disabled(!ready || store.busy != nil)
            Button("Fork This Moment") { store.fork() }
                .keyboardShortcut("f", modifiers: [.command, .shift]).disabled(!ready)
            Divider()
            Button("Generate Report") { store.go(.report); Task { await store.report() } }
                .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!ready || store.busy != nil)
            Button("Export Experiment…") { store.exporting = .experiment }.disabled(!ready)
            Button("Share Bundle…") { store.exporting = .bundle }.disabled(!ready)
        }
    }
}
