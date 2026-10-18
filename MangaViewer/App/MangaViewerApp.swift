import SwiftUI

@main
struct MangaViewerApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(ProgressStore.shared)
                // ショートカット（ChatGPT）からの答えを受け取る
                .onOpenURL { url in ChatGPTBridge.shared.handle(url) }
        }
    }
}
