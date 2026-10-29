import SwiftUI
import AppKit

extension Notification.Name {
    static let studioNavigate = Notification.Name("studio.navigate")
}

@main struct YTDLPStudioApp: App {
    @StateObject private var manager = DownloadManager()

    var body: some Scene {
        Window("YTDLP Studio", id: "main") {
            ContentView(manager: manager)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Novo Download") { navigate(0) }.keyboardShortcut("n")
            }
            CommandMenu("Downloads") {
                Button("Baixar") { navigate(0) }.keyboardShortcut("1")
                Button("Atividade") { navigate(1) }.keyboardShortcut("2")
                Button("Concluídos") { navigate(2) }.keyboardShortcut("3")
            }
        }
    }

    private func navigate(_ tab: Int) {
        NotificationCenter.default.post(name: .studioNavigate, object: tab)
        NSApp.activate(ignoringOtherApps: true)
    }
}
