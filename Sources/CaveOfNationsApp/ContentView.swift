import SwiftUI
import SceneKit
import AppKit

private enum GameplayTheme {
    static let background = LinearGradient(
        colors: [Color(red: 0.07, green: 0.09, blue: 0.11),
                 Color(red: 0.22, green: 0.16, blue: 0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accentGold = Color(red: 0.86, green: 0.68, blue: 0.29)
    static let accentTeal = Color(red: 0.18, green: 0.39, blue: 0.41)
    static let panelHighlight = Color.white.opacity(0.18)
    static let panelFill = Color.black.opacity(0.35)
}

struct ContentView: View {
    @ObservedObject private var settings: GameSettings
    @StateObject private var viewModel: GameViewModel
    @State private var viewState: ViewState = .mainMenu
    @State private var isOptionsVisible = false
    @State private var optionsDraft = SettingsDraft()
    @State private var resourcesCollapsed = true
    @State private var showLoadingOverlay = false
    @State private var loadingProgress: Double = 0.0
    @State private var loadingDuration: TimeInterval = 0
    @State private var loadingStart: Date?
    @State private var loadingTimer: Timer?
    /// Screen-space rectangle rendered while drag-selecting units.
    @State private var selectionRect: CGRect?

    init(settings: GameSettings) {
        self._settings = ObservedObject(initialValue: settings)
        _viewModel = StateObject(wrappedValue: GameViewModel(settings: settings))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GameplayTheme.background
                    .ignoresSafeArea()

                switch viewState {
                case .mainMenu:
                    MainMenuView(startAction: startGame, optionsAction: presentOptions)
                        .transition(.opacity)
                case .playing:
                    gameplayScene(size: proxy.size)
                        .transition(.opacity.combined(with: .scale))
                }

                if isOptionsVisible {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                    GameOptionsPanel(
                        draft: $optionsDraft,
                        onDone: commitOptions,
                        onCancel: { isOptionsVisible = false }
                    )
                    .transition(.scale)
                    .zIndex(2)
                }

                if showLoadingOverlay && settings.showLoadingScreen {
                    LoadingOverlay(progress: loadingProgress)
                        .zIndex(3)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            applyDisplaySettings()
        }
        .onChange(of: settings.isFullscreen) { _ in
            applyDisplaySettings()
        }
        .onChange(of: settings.resolution) { _ in
            applyDisplaySettings()
        }
        .onDisappear {
            loadingTimer?.invalidate()
            loadingTimer = nil
        }
    }

    private func gameplayScene(size: CGSize) -> some View {
        ZStack {
            SceneViewWrapper(selectionRect: $selectionRect, viewModel: viewModel, onKeyDown: handleKeyDown)
                .frame(width: size.width, height: size.height)
                .ignoresSafeArea()
                .overlay(selectionOverlay)
                .onReceive(settings.resetPublisher) { _ in
                    viewModel.rebuild(using: settings)
                    viewModel.prepareForPlay()
                    startLoadingCountdown()
                }

            VStack {
                topOverlay
                    .padding(.horizontal, 36)
                    .padding(.top, 24)
                Spacer()
                bottomOverlay
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }

            if viewModel.isPaused {
                PausedOverlay(resumeAction: viewModel.togglePause)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }

    /// Renders the translucent marquee shown during drag selection.
    private var selectionOverlay: some View {
        GeometryReader { proxy in
            if let rect = selectionRect {
                let adjusted = CGRect(
                    x: rect.origin.x,
                    y: proxy.size.height - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(GameplayTheme.accentGold.opacity(0.9), lineWidth: 1.2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .frame(width: adjusted.width, height: adjusted.height)
                    .position(x: adjusted.midX, y: adjusted.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private var topOverlay: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cave of Nations")
                    .font(.system(size: 40, weight: .heavy, design: .default))
                    .foregroundStyle(GameplayTheme.accentGold)
                    .shadow(color: GameplayTheme.accentGold.opacity(0.45), radius: 14, x: 0, y: 10)
                Text("Guide the fox clans through the shifting sands—mine, build, and unite the underground nations.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .minimumScaleFactor(0.8)
                HStack(spacing: 18) {
                    statBadge(icon: "compass.drawing", title: "Depth", value: depthLabel)
                    statBadge(icon: "sparkles", title: "Relics", value: "\(viewModel.inventory[.relic] ?? 0)")
                }
            }

            Spacer(minLength: 24)

            VStack(alignment: .trailing, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Resources")
                        .font(.headline)
                        .foregroundStyle(GameplayTheme.accentGold)
                    Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { resourcesCollapsed.toggle() } }) {
                        Image(systemName: resourcesCollapsed ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(GameplayTheme.accentGold)
                            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }

                if resourcesCollapsed {
                    collapsedSummary
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    resourcesGrid
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Divider()
                        .overlay(GameplayTheme.panelHighlight)
                    Text("Inventory")
                        .font(.headline)
                        .foregroundStyle(GameplayTheme.accentGold)
                    inventoryList
                        .transition(.opacity)
                }

                MinimapView(snapshot: viewModel.minimapSnapshot)
            }
        }
        .padding(24)
        .glassPanel(radius: 28)
    }

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Commands")
                .font(.headline)
                .foregroundStyle(GameplayTheme.accentGold)
            HStack(spacing: 16) {
                commandButton(label: "Harvest Soil", action: { viewModel.issue(command: .harvest(.soil)) })
                commandButton(label: "Harvest Stone", action: { viewModel.issue(command: .harvest(.rock)) })
                commandButton(label: "Collect Pipestone", action: { viewModel.issue(command: .harvest(.pipestone)) })
                commandButton(label: "Dig Forward", action: viewModel.playerDig)
                commandButton(label: "Rally", action: {
                    let focus = viewModel.focusPointForCamera()
                    viewModel.issue(command: .move(to: focus))
                })
                // Build command menu toggles placement mode and exposes cancel action.
                Menu {
                    ForEach(viewModel.availableBuildings) { template in
                        Button {
                            viewModel.togglePlacement(for: template)
                        } label: {
                            Label(template.name, systemImage: "hammer.fill")
                        }
                    }
                    if viewModel.isPlacingBuilding {
                        Divider()
                        Button("Cancel Placement", action: viewModel.cancelPlacement)
                    }
                } label: {
                    Label(viewModel.isPlacingBuilding ? "Placing..." : "Place Building", systemImage: "hammer")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if viewModel.isPlacingBuilding {
                    Button("Cancel", action: viewModel.cancelPlacement)
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button(viewModel.isPaused ? "Resume" : "Pause") {
                    viewModel.togglePause()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if let placement = viewModel.placementState {
                HStack {
                    Label("Placing \(placement.template.name)", systemImage: placement.isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundStyle(placement.isValid ? Color.green : Color.red)
                    Text(placement.isValid ? "Left-click to confirm." : "Move cursor to a valid tile.")
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .font(.footnote.weight(.semibold))
            }

            Text("Controls: Click to path Anubis, drag-select to choose units, WASD/Arrows move, Space digs, Right-drag orbit, Option-drag or middle-drag pan, scroll or pinch to zoom.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.75))

            Divider()
                .overlay(GameplayTheme.panelHighlight)

            HStack(spacing: 12) {
                Button("Main Menu") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        viewState = .mainMenu
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Game Options") {
                    presentOptions()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(24)
        .glassPanel()
    }

    private var resourcesGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                resourceChip(icon: "leaf.fill", title: "Soil", value: viewModel.economy.amount(of: .soil))
                resourceChip(icon: "cube.fill", title: "Stone", value: viewModel.economy.amount(of: .stone))
            }
            GridRow {
                resourceChip(icon: "square.fill", title: "Pipestone", value: viewModel.economy.amount(of: .pipestone))
                resourceChip(icon: "sparkles", title: "Relics", value: viewModel.economy.amount(of: .relic))
            }
            GridRow {
                resourceChip(icon: "leaf.circle.fill", title: "Food", value: viewModel.economy.amount(of: .food))
                resourceChip(icon: "bolt.fill", title: "Energy", value: viewModel.economy.amount(of: .energy))
            }
        }
    }

    private var inventoryList: some View {
        VStack(alignment: .trailing, spacing: 10) {
            inventoryRow(title: "Soil Blocks", value: viewModel.inventory[.soil] ?? 0)
            inventoryRow(title: "Rock Blocks", value: viewModel.inventory[.rock] ?? 0)
            inventoryRow(title: "Pipestone Blocks", value: viewModel.inventory[.pipestone] ?? 0)
            inventoryRow(title: "Relic Finds", value: viewModel.inventory[.relic] ?? 0)
            inventoryRow(title: "Den Remnants", value: viewModel.inventory[.den] ?? 0)
        }
        .font(.callout)
        .foregroundStyle(Color.white.opacity(0.85))
    }

    private func commandButton(label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(GoldButtonStyle())
    }

    private func statBadge(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(GameplayTheme.accentGold)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func resourceChip(icon: String, title: String, value: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GameplayTheme.accentTeal)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("\(value)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func inventoryRow(title: String, value: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Text("\(value)")
                .foregroundStyle(GameplayTheme.accentGold)
                .font(.headline)
        }
    }

    private var collapsedSummary: some View {
        Text("Soil \(viewModel.economy.amount(of: .soil))  ·  Stone \(viewModel.economy.amount(of: .stone))  ·  Pipestone \(viewModel.economy.amount(of: .pipestone))  ·  Relics \(viewModel.economy.amount(of: .relic))")
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.85))
    }

    private var depthLabel: String {
        let snapshot = viewModel.minimapSnapshot
        if let player = snapshot.player,
           player.y >= 0, player.y < snapshot.rows,
           player.x >= 0, player.x < snapshot.columns {
            let depth = snapshot.map[player.y][player.x]
            if depth >= 0 {
                return "Row \(depth)"
            }
        }
        return "Unknown"
    }

    private func startLoadingCountdown() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        loadingProgress = 0
        loadingStart = Date()
        loadingDuration = settings.loadingDuration

        guard settings.showLoadingScreen else {
            showLoadingOverlay = false
            viewModel.loadingFinished()
            viewModel.resumeGame()
            return
        }

        showLoadingOverlay = true
        viewModel.pauseGame()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateLoadingProgress()
        }
    }

    private func updateLoadingProgress() {
        guard let start = loadingStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= loadingDuration {
            loadingTimer?.invalidate()
            loadingTimer = nil
            withAnimation(.easeOut(duration: 0.35)) {
                showLoadingOverlay = false
                viewModel.loadingFinished()
                viewModel.resumeGame()
            }
        } else {
            loadingProgress = min(1.0, elapsed / max(loadingDuration, 0.1))
        }
    }
}

extension ContentView {
    enum ViewState {
        case mainMenu
        case playing
    }

    private func startGame() {
        viewModel.prepareForPlay()
        withAnimation {
            viewState = .playing
        }
        DispatchQueue.main.async {
            startLoadingCountdown()
        }
    }

    private func presentOptions() {
        optionsDraft = SettingsDraft(settings: settings)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isOptionsVisible = true
        }
    }

    private func commitOptions() {
        optionsDraft.apply(to: settings)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isOptionsVisible = false
        }
        applyDisplaySettings()
    }

    private func applyDisplaySettings() {
        guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first else {
            return
        }

        if !window.styleMask.contains(.fullScreen) {
            let targetSize = settings.resolution.size
            window.setContentSize(targetSize)
            window.center()
        }

        let wantsFullscreen = settings.isFullscreen
        let isFullscreen = window.styleMask.contains(.fullScreen)

        if wantsFullscreen != isFullscreen {
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.toggleFullScreen(nil)
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard viewState == .playing else { return }
        if let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "w":
                viewModel.movePlayer(.forward)
            case "s":
                viewModel.movePlayer(.backward)
            case "a":
                viewModel.movePlayer(.left)
            case "d":
                viewModel.movePlayer(.right)
            case " ":
                viewModel.playerDig()
            default:
                break
            }
        }

        switch event.keyCode {
        case 126:
            viewModel.movePlayer(.forward)
        case 125:
            viewModel.movePlayer(.backward)
        case 123:
            viewModel.movePlayer(.left)
        case 124:
            viewModel.movePlayer(.right)
        case 49:
            viewModel.playerDig()
        default:
            break
        }
    }
}

private struct MainMenuView: View {
    let startAction: () -> Void
    let optionsAction: () -> Void

    var body: some View {
        ZStack {
            GameplayTheme.background
                .ignoresSafeArea()

            VStack(spacing: 36) {
                VStack(spacing: 12) {
                    Text("Cave of Nations")
                        .font(.system(size: 54, weight: .black))
                        .foregroundStyle(GameplayTheme.accentGold)
                    Text("Awaken the clans beneath the dunes.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .multilineTextAlignment(.center)

                HStack(spacing: 24) {
                    Button("Start Adventure", action: startAction)
                        .buttonStyle(GoldButtonStyle())
                        .padding(.horizontal, 12)
                    Button("Options", action: optionsAction)
                        .buttonStyle(SecondaryButtonStyle())
                }

                VStack(spacing: 6) {
                    Text("WASD / Arrow keys to move, Space to dig")
                        .font(.footnote)
                    Text("Click to interact with the sands and uncover relics")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(40)
            .glassPanel()
            .padding(.horizontal, 80)
        }
    }
}

private struct GameOptionsPanel: View {
    @Binding var draft: SettingsDraft
    var onDone: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Game Options")
                .font(.title.weight(.bold))
                .foregroundStyle(GameplayTheme.accentGold)

            VStack(alignment: .leading, spacing: 18) {
                Text("World Size")
                    .font(.headline)
                Stepper(value: $draft.width, in: 8...32, step: 2) {
                    Text("Width: \(draft.width)")
                }
                Stepper(value: $draft.depth, in: 8...32, step: 2) {
                    Text("Depth: \(draft.depth)")
                }
                Stepper(value: $draft.height, in: 6...24) {
                    Text("Height: \(draft.height)")
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                Text("Audio")
                    .font(.headline)
                sliderRow(title: "Music Volume", value: $draft.musicVolume)
                sliderRow(title: "Effects Volume", value: $draft.effectsVolume)
            }

            VStack(alignment: .leading, spacing: 18) {
                Text("Display")
                    .font(.headline)
                Picker("Resolution", selection: $draft.resolution) {
                    ForEach(GameSettings.Resolution.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Fullscreen", isOn: $draft.isFullscreen)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Done", action: onDone)
                    .buttonStyle(GoldButtonStyle())
            }
        }
        .padding(32)
        .frame(maxWidth: 520)
        .glassPanel()
    }

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .foregroundStyle(GameplayTheme.accentGold)
            }
            Slider(value: value, in: 0...1)
        }
    }
}

private struct SettingsDraft {
    var width: Int = 16
    var height: Int = 12
    var depth: Int = 16
    var musicVolume: Double = 0.7
    var effectsVolume: Double = 0.8
    var resolution: GameSettings.Resolution = .hd1080
    var isFullscreen: Bool = false
    var showLoadingScreen: Bool = true
    var loadingDuration: TimeInterval = 2.5

    init() {}

    init(settings: GameSettings) {
        self.width = settings.dimensions.width
        self.height = settings.dimensions.height
        self.depth = settings.dimensions.depth
        self.musicVolume = settings.musicVolume
        self.effectsVolume = settings.effectsVolume
        self.resolution = settings.resolution
        self.isFullscreen = settings.isFullscreen
        self.showLoadingScreen = settings.showLoadingScreen
        self.loadingDuration = settings.loadingDuration
    }

    func apply(to settings: GameSettings) {
        settings.dimensions = GameSettings.Dimensions(
            width: max(8, min(32, width)),
            height: max(6, min(24, height)),
            depth: max(8, min(32, depth))
        )
        settings.musicVolume = min(max(musicVolume, 0), 1)
        settings.effectsVolume = min(max(effectsVolume, 0), 1)
        settings.resolution = resolution
        settings.isFullscreen = isFullscreen
        settings.showLoadingScreen = showLoadingScreen
        settings.loadingDuration = loadingDuration
    }
}

private struct SceneViewWrapper: NSViewRepresentable {
    final class GameSceneView: SCNView {
        weak var coordinator: Coordinator?
        var keyDownHandler: ((NSEvent) -> Void)?
        private var trackingArea: NSTrackingArea?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
            window?.acceptsMouseMovedEvents = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .inVisibleRect, .mouseEnteredAndExited]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func keyDown(with event: NSEvent) {
            if let handler = keyDownHandler {
                handler(event)
            } else {
                super.keyDown(with: event)
            }
        }

        override func mouseDown(with event: NSEvent) {
            coordinator?.handleMouseDown(event, in: self)
        }

        override func mouseDragged(with event: NSEvent) {
            coordinator?.handleMouseDragged(event, in: self)
        }

        override func mouseUp(with event: NSEvent) {
            coordinator?.handleMouseUp(event, in: self)
        }

        override func rightMouseDown(with event: NSEvent) {
            coordinator?.handleRightMouseDown(event, in: self)
        }

        override func rightMouseDragged(with event: NSEvent) {
            coordinator?.handleRightMouseDragged(event, in: self)
        }

        override func rightMouseUp(with event: NSEvent) {
            coordinator?.handleRightMouseUp(event, in: self)
        }

        override func otherMouseDown(with event: NSEvent) {
            coordinator?.handleOtherMouseDown(event, in: self)
        }

        override func otherMouseDragged(with event: NSEvent) {
            coordinator?.handleOtherMouseDragged(event, in: self)
        }

        override func otherMouseUp(with event: NSEvent) {
            coordinator?.handleOtherMouseUp(event, in: self)
        }

        override func scrollWheel(with event: NSEvent) {
            coordinator?.handleScrollWheel(event, in: self)
        }

        override func magnify(with event: NSEvent) {
            coordinator?.handleMagnify(event, in: self)
        }

        override func mouseMoved(with event: NSEvent) {
            coordinator?.handleMouseMoved(event, in: self)
        }

        override func mouseExited(with event: NSEvent) {
            coordinator?.handleMouseExited(event, in: self)
        }
    }

    @Binding var selectionRect: CGRect?
    var viewModel: GameViewModel
    var onKeyDown: ((NSEvent) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, selectionRect: _selectionRect)
    }

    func makeNSView(context: Context) -> GameSceneView {
        let view = GameSceneView()
        view.scene = viewModel.scene
        view.backgroundColor = .black
        view.allowsCameraControl = false
        view.isPlaying = true
        view.rendersContinuously = true
        view.loops = true
        view.antialiasingMode = .multisampling4X
        view.isJitteringEnabled = true
        view.coordinator = context.coordinator
        view.keyDownHandler = onKeyDown
        view.pointOfView = cameraNode(from: viewModel.scene)
        context.coordinator.sceneView = view
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: GameSceneView, context: Context) {
        if nsView.scene !== viewModel.scene {
            nsView.scene = viewModel.scene
        }
        nsView.keyDownHandler = onKeyDown
        nsView.coordinator = context.coordinator
        if nsView.pointOfView == nil || nsView.pointOfView?.name != "primary.camera" {
            nsView.pointOfView = cameraNode(from: viewModel.scene)
        }
        context.coordinator.sceneView = nsView
    }

    private func cameraNode(from scene: SCNScene) -> SCNNode? {
        scene.rootNode.childNode(withName: "primary.camera", recursively: true)
    }

    @MainActor
    /// Routes macOS input events to gameplay actions and overlays.
    final class Coordinator: NSObject {
        let viewModel: GameViewModel
        var selectionRect: Binding<CGRect?>
        weak var sceneView: GameSceneView?

        private var dragStartPoint: CGPoint = .zero
        private var lastDragPoint: CGPoint = .zero
        private var orbitAnchor: CGPoint = .zero
        private var panAnchor: CGPoint = .zero
        private var isDraggingSelection = false
        private var isOrbitingCamera = false
        private var isPanningCamera = false

        init(viewModel: GameViewModel, selectionRect: Binding<CGRect?>) {
            self.viewModel = viewModel
            self.selectionRect = selectionRect
        }

        func handleMouseDown(_ event: NSEvent, in view: GameSceneView) {
            sceneView = view
            let location = view.convert(event.locationInWindow, from: nil)
            dragStartPoint = location
            lastDragPoint = location
            isDraggingSelection = false
            isPanningCamera = false
            selectionRect.wrappedValue = nil
            if viewModel.isPlacingBuilding {
                updatePlacementHover(at: location, in: view)
            }
        }

        func handleMouseDragged(_ event: NSEvent, in view: GameSceneView) {
            let location = view.convert(event.locationInWindow, from: nil)
            let delta = CGPoint(x: location.x - lastDragPoint.x, y: location.y - lastDragPoint.y)
            lastDragPoint = location

            if viewModel.isPlacingBuilding {
                updatePlacementHover(at: location, in: view)
                return
            }

            if event.modifierFlags.contains(.option) {
                if !isPanningCamera {
                    isPanningCamera = true
                    panAnchor = location
                }
                viewModel.panCamera(by: delta)
                selectionRect.wrappedValue = nil
                return
            }

            let distance = hypot(location.x - dragStartPoint.x, location.y - dragStartPoint.y)
            if !isDraggingSelection && distance > 6 {
                isDraggingSelection = true
            }
            if isDraggingSelection {
                updateSelectionRect(to: location)
            }
        }

        func handleMouseUp(_ event: NSEvent, in view: GameSceneView) {
            let location = view.convert(event.locationInWindow, from: nil)

            if viewModel.isPlacingBuilding {
                updatePlacementHover(at: location, in: view)
                if viewModel.placementState?.isValid == true {
                    viewModel.commitPlacement()
                } else {
                    NSSound.beep()
                }
                selectionRect.wrappedValue = nil
                return
            }

            if isDraggingSelection, let rect = selectionRect.wrappedValue {
                finalizeSelection(with: rect, event: event, in: view)
            } else {
                handleClick(event: event, at: location, in: view)
            }

            selectionRect.wrappedValue = nil
            isDraggingSelection = false
            isPanningCamera = false
        }

        func handleRightMouseDown(_ event: NSEvent, in view: GameSceneView) {
            sceneView = view
            orbitAnchor = view.convert(event.locationInWindow, from: nil)
            isOrbitingCamera = true
        }

        func handleRightMouseDragged(_ event: NSEvent, in view: GameSceneView) {
            guard isOrbitingCamera else { return }
            let location = view.convert(event.locationInWindow, from: nil)
            let delta = CGPoint(x: location.x - orbitAnchor.x, y: location.y - orbitAnchor.y)
            orbitAnchor = location
            viewModel.orbitCamera(by: delta)
        }

        func handleRightMouseUp(_ event: NSEvent, in view: GameSceneView) {
            isOrbitingCamera = false
        }

        func handleOtherMouseDown(_ event: NSEvent, in view: GameSceneView) {
            guard event.buttonNumber == 2 else { return }
            sceneView = view
            panAnchor = view.convert(event.locationInWindow, from: nil)
            isPanningCamera = true
        }

        func handleOtherMouseDragged(_ event: NSEvent, in view: GameSceneView) {
            guard isPanningCamera, event.buttonNumber == 2 else { return }
            let location = view.convert(event.locationInWindow, from: nil)
            let delta = CGPoint(x: location.x - panAnchor.x, y: location.y - panAnchor.y)
            panAnchor = location
            viewModel.panCamera(by: delta)
        }

        func handleOtherMouseUp(_ event: NSEvent, in view: GameSceneView) {
            if event.buttonNumber == 2 {
                isPanningCamera = false
            }
        }

        func handleScrollWheel(_ event: NSEvent, in view: GameSceneView) {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 0.08 : 0.3
            let delta = CGFloat(event.scrollingDeltaY) * scale
            viewModel.zoomCamera(by: delta)
        }

        func handleMagnify(_ event: NSEvent, in view: GameSceneView) {
            let delta = CGFloat(event.magnification) * 3.5
            viewModel.zoomCamera(by: delta)
        }

        func handleMouseMoved(_ event: NSEvent, in view: GameSceneView) {
            guard viewModel.isPlacingBuilding else { return }
            let location = view.convert(event.locationInWindow, from: nil)
            updatePlacementHover(at: location, in: view)
        }

        func handleMouseExited(_ event: NSEvent, in view: GameSceneView) {
            guard viewModel.isPlacingBuilding else { return }
            viewModel.updatePlacementHover(with: nil)
        }

        private func updateSelectionRect(to point: CGPoint) {
            let rect = CGRect(
                x: min(dragStartPoint.x, point.x),
                y: min(dragStartPoint.y, point.y),
                width: abs(point.x - dragStartPoint.x),
                height: abs(point.y - dragStartPoint.y)
            )
            selectionRect.wrappedValue = rect
        }

        private func finalizeSelection(with rect: CGRect, event: NSEvent, in view: GameSceneView) {
            let ids = units(in: rect, view: view)
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            viewModel.selectUnits(in: ids, additive: additive)
        }

        private func handleClick(event: NSEvent, at location: CGPoint, in view: GameSceneView) {
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            if let unit = nearestUnit(to: location, in: view) {
                viewModel.select(unit: unit, additive: additive)
                return
            }

            guard !additive, let worldPoint = worldPoint(at: location, in: view) else { return }
            viewModel.movePlayer(to: worldPoint)
        }

        private func units(in rect: CGRect, view: GameSceneView) -> Set<UUID> {
            guard !viewModel.units.isEmpty else { return [] }
            var identifiers: Set<UUID> = []
            for unit in viewModel.units {
                let projected = view.projectPoint(unit.position)
                guard projected.z >= 0 else { continue }
                let point = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                if rect.contains(point) {
                    identifiers.insert(unit.id)
                }
            }
            return identifiers
        }

        private func nearestUnit(to location: CGPoint, in view: GameSceneView) -> Unit? {
            var best: (Unit, CGFloat)?
            for unit in viewModel.units {
                let projected = view.projectPoint(unit.position)
                guard projected.z >= 0 else { continue }
                let point = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                let distance = hypot(point.x - location.x, point.y - location.y)
                if distance <= 24 {
                    if let bestCurrent = best {
                        if distance < bestCurrent.1 {
                            best = (unit, distance)
                        }
                    } else {
                        best = (unit, distance)
                    }
                }
            }
            return best?.0
        }

        private func updatePlacementHover(at location: CGPoint, in view: GameSceneView) {
            guard let point = worldPoint(at: location, in: view) else {
                viewModel.updatePlacementHover(with: nil)
                return
            }
            viewModel.updatePlacementHover(with: point)
        }

        /// Map a 2D screen coordinate to a world point by first hit-testing and then falling back to an unprojected ray.
        private func worldPoint(at location: CGPoint, in view: GameSceneView) -> SCNVector3? {
            let options: [SCNHitTestOption: Any] = [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: false,
                .backFaceCulling: false
            ]
            if let hit = view.hitTest(location, options: options).first {
                return hit.worldCoordinates
            }

            let focus = viewModel.focusPointForCamera()
            let near = view.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 0))
            let far = view.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 1))
            let direction = far - near
            guard direction.y != 0 else { return nil }
            let t = (focus.y - near.y) / direction.y
            guard t >= 0 else { return nil }
            return near + direction * CGFloat(t)
        }
    }
}

private struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: configuration.isPressed ?
                            [GameplayTheme.accentGold.opacity(0.7), GameplayTheme.accentTeal.opacity(0.7)] :
                            [GameplayTheme.accentGold, GameplayTheme.accentTeal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.25 : 0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.2 : 0.4), radius: configuration.isPressed ? 6 : 14, x: 0, y: configuration.isPressed ? 4 : 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(GameplayTheme.accentGold)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GameplayTheme.accentGold.opacity(configuration.isPressed ? 0.6 : 0.9), lineWidth: 1.4)
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06))
            )
            .shadow(color: Color.black.opacity(0.25), radius: configuration.isPressed ? 4 : 8, x: 0, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct GlassPanel: ViewModifier {
    var radius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(GameplayTheme.panelFill)
                    .background(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(GameplayTheme.panelHighlight, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 12)
    }
}

private extension View {
    func glassPanel(radius: CGFloat = 28) -> some View {
        modifier(GlassPanel(radius: radius))
    }
}

private struct MinimapView: View {
    let snapshot: MinimapSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Minimap")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameplayTheme.accentGold)
            Canvas { context, size in
                guard snapshot.rows > 0, snapshot.columns > 0 else { return }
                let cellWidth = size.width / CGFloat(snapshot.columns)
                let cellHeight = size.height / CGFloat(snapshot.rows)
                let maxDepth = max(snapshot.maxDepth, 1)
                for (rowIndex, row) in snapshot.map.enumerated() {
                    for (colIndex, depth) in row.enumerated() where depth >= 0 {
                        let normalized = CGFloat(depth) / CGFloat(maxDepth)
                        let color = Color(red: 0.32 + 0.28 * normalized,
                                          green: 0.24 + 0.18 * normalized,
                                          blue: 0.16 + 0.16 * (1 - normalized))
                        let rect = CGRect(x: CGFloat(colIndex) * cellWidth,
                                          y: size.height - CGFloat(rowIndex + 1) * cellHeight,
                                          width: cellWidth,
                                          height: cellHeight)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
                for relic in snapshot.relics {
                    let rect = CGRect(x: CGFloat(relic.x) * cellWidth,
                                      y: size.height - CGFloat(relic.y + 1) * cellHeight,
                                      width: cellWidth,
                                      height: cellHeight)
                    let path = Path(ellipseIn: rect.insetBy(dx: cellWidth * 0.25, dy: cellHeight * 0.25))
                    context.fill(path, with: .color(.yellow))
                }
                if let player = snapshot.player {
                    let rect = CGRect(x: CGFloat(player.x) * cellWidth,
                                      y: size.height - CGFloat(player.y + 1) * cellHeight,
                                      width: cellWidth,
                                      height: cellHeight)
                    let path = Path(ellipseIn: rect.insetBy(dx: cellWidth * 0.2, dy: cellHeight * 0.2))
                    context.fill(path, with: .color(.white))
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
    }
}

private struct LoadingOverlay: View {
    var progress: Double

    var body: some View {
        ZStack {
            GameplayTheme.background
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.65))
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Cave of Nations")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(GameplayTheme.accentGold)
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: GameplayTheme.accentGold))
                    .frame(width: 280)
                    .padding(.horizontal, 32)
                Text("Preparing the sands...")
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(48)
            .glassPanel(radius: 32)
        }
    }
}

private struct PausedOverlay: View {
    var resumeAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Game Paused")
                .font(.title.weight(.bold))
                .foregroundStyle(GameplayTheme.accentGold)
            Button("Resume", action: resumeAction)
                .buttonStyle(GoldButtonStyle())
        }
        .padding(36)
        .glassPanel(radius: 24)
    }
}
