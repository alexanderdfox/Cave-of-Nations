//
//  CaveOfNationsApp.swift
//  CaveOfNationsApp
//
//  SwiftUI entry point that wires GameSettings into the root ContentView and
//  exposes a simple command menu for resetting the world.
//

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
