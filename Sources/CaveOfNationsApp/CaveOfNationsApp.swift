import SwiftUI

@main
struct CaveOfNationsApp: App {
    @StateObject private var gameSettings = GameSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: gameSettings)
        }
        .commands {
            CommandMenu("Game") {
                Button("New Game") {
                    gameSettings.requestReset()
                }
                .keyboardShortcut("r")
            }
        }
    }
}
