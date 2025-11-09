import Foundation
import SceneKit
import Combine
import simd

@MainActor
final class GameViewModel: ObservableObject {
    enum MoveDirection {
        case forward
        case backward
        case left
        case right

        var delta: SIMD2<Int> {
            switch self {
            case .forward: return SIMD2(0, -1)
            case .backward: return SIMD2(0, 1)
            case .left: return SIMD2(-1, 0)
            case .right: return SIMD2(1, 0)
            }
        }
    }

    @Published private(set) var world: GameWorld
    @Published private(set) var blockCounts: [BlockType: Int] = [:]
    @Published private(set) var economy: EconomyState
    @Published private(set) var units: [Unit] = []
    @Published private(set) var selectedUnitIDs: Set<UUID> = []
    @Published private(set) var inventory: [BlockType: Int] = [:]
    @Published private(set) var isPaused: Bool
    @Published private(set) var playerCoordinate: SIMD2<Int>?
    @Published private(set) var isLoading: Bool

    private var cancellables: Set<AnyCancellable> = []
    private let tickInterval: TimeInterval = 0.5
    private var timer: AnyCancellable?

    init(settings: GameSettings) {
        let dimensions = GameWorld.Dimensions(
            width: settings.dimensions.width,
            height: settings.dimensions.height,
            depth: settings.dimensions.depth
        )
        self.world = GameWorld(dimensions: dimensions)
        self.economy = EconomyState()
        self.isPaused = true
        self.isLoading = true
        self.playerCoordinate = world.playerGridCoordinate
        world.setPaused(true)
        world.onPlayerPositionChange = { [weak self] coordinate in
            Task { @MainActor in
                self?.playerCoordinate = coordinate
            }
        }
        bootstrapClan()
        recalculateCounts()
        setupTimer()
    }

    var scene: SCNScene { world.scene }

    func rebuild(using settings: GameSettings) {
        let dimensions = GameWorld.Dimensions(
            width: settings.dimensions.width,
            height: settings.dimensions.height,
            depth: settings.dimensions.depth
        )
        world.rebuild(with: dimensions)
        world.setPaused(isPaused)
        playerCoordinate = world.playerGridCoordinate
        isLoading = true
        recalculateCounts()
        economy.resetForNewWorld()
        bootstrapClan()
    }

    func select(unit: Unit) {
        selectedUnitIDs = [unit.id]
    }

    func selectUnits(in ids: Set<UUID>) {
        selectedUnitIDs = ids
    }

    func issue(command: Unit.Command) {
        for index in units.indices where selectedUnitIDs.contains(units[index].id) {
            units[index].enqueue(command: command)
        }
    }

    func focusPointForCamera() -> SCNVector3 {
        world.playerWorldPosition ?? world.focusPoint
    }

    func movePlayer(_ direction: MoveDirection) {
        guard !isPaused else { return }
        world.movePlayer(by: direction.delta)
    }

    func movePlayer(by delta: SIMD2<Int>) {
        guard !isPaused else { return }
        world.movePlayer(by: delta)
    }

    func playerDig() {
        guard !isPaused else { return }
        if let harvested = world.digPlayerForward() {
            switch harvested {
            case .soil:
                economy.add(3, of: .soil)
                addToInventory(block: .soil)
            case .rock:
                economy.add(2, of: .stone)
                addToInventory(block: .rock)
            case .pipestone:
                economy.add(2, of: .pipestone)
                economy.add(1, of: .energy)
                addToInventory(block: .pipestone)
            case .relic:
                economy.add(1, of: .relic)
                addToInventory(block: .relic)
            case .den:
                economy.add(2, of: .food)
                addToInventory(block: .den)
            case .tunnel, .air:
                break
            }
            recalculateCounts()
        }
    }

    private func bootstrapClan() {
        let spawn = SCNVector3(2, 1, 2)
        units = [
            Unit(role: .miner, position: spawn),
            Unit(role: .builder, position: spawn + SCNVector3(1, 0, 0)),
            Unit(role: .scout, position: spawn + SCNVector3(-1, 0, 0))
        ]
    }

    private func setupTimer() {
        timer = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard !isPaused else { return }
        objectWillChange.send()
        updateUnits()
        economy.progressTick()
    }

    private func updateUnits() {
        for index in units.indices {
            units[index].update(in: world, economy: &economy)
        }
    }

    private func recalculateCounts() {
        blockCounts = world.blockCounts()
    }

    private func addToInventory(block: BlockType) {
        guard block != .air else { return }
        inventory[block, default: 0] += 1
    }

    func pauseGame() {
        guard !isPaused else { return }
        isPaused = true
        world.setPaused(true)
    }

    func resumeGame() {
        guard isPaused else { return }
        isPaused = false
        world.setPaused(false)
    }

    func togglePause() {
        isPaused ? resumeGame() : pauseGame()
    }

    func loadingFinished() {
        isLoading = false
    }

    func prepareForPlay() {
        isLoading = true
        world.preloadResources()
        pauseGame()
    }

    var minimapSnapshot: MinimapSnapshot {
        MinimapSnapshot(map: world.surfaceDepthMap(), player: playerCoordinate, relics: world.relicCoordinates())
    }
}

struct MinimapSnapshot {
    let map: [[Int]]
    let player: SIMD2<Int>?
    let relics: [SIMD2<Int>]

    var rows: Int { map.count }
    var columns: Int { map.first?.count ?? 0 }
    var maxDepth: Int { map.flatMap { $0 }.max() ?? 0 }
}
