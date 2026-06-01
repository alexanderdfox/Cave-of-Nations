//
//  GameViewModel.swift
//  CaveOfNationsApp
//
//  This observable object bridges SwiftUI/SceneKit input with GameWorld state.
//  - Maintains unit selection, economy snapshots, and placement mode.
//  - Exposes commands for clicks, keyboard events, and camera gestures.
//  - Ticks the simulation and queues unit actions.
//

import Foundation
import SceneKit
import Combine
import CoreGraphics
import simd

@MainActor
final class GameViewModel: ObservableObject {
    /// Blends Age of Empires command modes with Minecraft voxel editing.
    enum InteractionMode: String, CaseIterable, Identifiable {
        case rts
        case mine
        case place

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rts: return "RTS"
            case .mine: return "Mine"
            case .place: return "Place"
            }
        }
    }

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
    /// Live state for ghost building placement, if any.
    @Published private(set) var placementState: PlacementState?
    @Published private(set) var isGuardianSelected: Bool = false
    @Published private(set) var worldSeed: UInt32 = 0
    @Published var interactionMode: InteractionMode = .rts
    @Published var placeBlockType: BlockType = .soil

    private var cancellables: Set<AnyCancellable> = []
    private let settings: GameSettings
    private let tickInterval: TimeInterval = 0.5
    private var timer: AnyCancellable?
    /// Hard-coded sample templates until a tech tree or content pipeline exists.
    private let buildingTemplates: [Building.Template] = [
        Building.Template(
            kind: .burrow,
            name: "Burrow",
            cost: [.soil: 12, .stone: 4],
            populationBonus: 4,
            footprint: SIMD2<Int>(2, 2)
        ),
        Building.Template(
            kind: .workshop,
            name: "Workshop",
            cost: [.stone: 10, .pipestone: 6],
            populationBonus: 2,
            footprint: SIMD2<Int>(2, 3)
        )
    ]

    init(settings: GameSettings) {
        self.settings = settings
        let dimensions = GameWorld.Dimensions(
            width: settings.dimensions.width,
            height: settings.dimensions.height,
            depth: settings.dimensions.depth
        )
        let seed = Int32(bitPattern: settings.worldGenerationSeed)
        self.world = GameWorld(dimensions: dimensions, seed: seed)
        self.worldSeed = settings.worldGenerationSeed
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
        GameAudio.shared.configure(
            musicVolume: settings.musicVolume,
            effectsVolume: settings.effectsVolume
        )
    }

    var scene: SCNScene { world.scene }
    /// Buildings exposed in the command bar for quick placement.
    var availableBuildings: [Building.Template] { buildingTemplates }
    var isPlacingBuilding: Bool { placementState != nil }

    func rebuild(using settings: GameSettings) {
        let dimensions = GameWorld.Dimensions(
            width: settings.dimensions.width,
            height: settings.dimensions.height,
            depth: settings.dimensions.depth
        )
        let seed = Int32(bitPattern: settings.worldGenerationSeed)
        world.rebuild(with: dimensions, seed: seed)
        world.setPaused(isPaused)
        playerCoordinate = world.playerGridCoordinate
        worldSeed = world.worldGenerationSeed
        isGuardianSelected = false
        world.setPlayerSelected(false)
        isLoading = true
        recalculateCounts()
        economy.resetForNewWorld()
        bootstrapClan()
    }

    /// Replace the selection with a single unit.
    func select(unit: Unit) {
        select(unit: unit, additive: false)
    }

    /// Replace the selection with a set of known unit identifiers.
    func selectUnits(in ids: Set<UUID>) {
        selectUnits(in: ids, additive: false)
    }

    /// Select a unit and optionally merge with the existing selection.
    func select(unit: Unit, additive: Bool) {
        if additive {
            selectedUnitIDs.insert(unit.id)
        } else {
            selectedUnitIDs = [unit.id]
            setGuardianSelected(false)
        }
        GameAudio.shared.play(.select)
    }

    /// Bulk select units by ID and optionally merge with the current selection.
    func selectUnits(in ids: Set<UUID>, additive: Bool) {
        if additive {
            selectedUnitIDs.formUnion(ids)
        } else {
            selectedUnitIDs = ids
            if !ids.isEmpty {
                setGuardianSelected(false)
            }
        }
        if !ids.isEmpty {
            GameAudio.shared.play(.select)
        }
    }

    func isPlayerNode(_ node: SCNNode) -> Bool {
        world.isPlayerSelected(node)
    }

    /// Reset the unit selection to an empty set.
    func clearSelection() {
        selectedUnitIDs = []
        setGuardianSelected(false)
    }

    func selectGuardian(additive: Bool) {
        if additive {
            setGuardianSelected(true)
        } else {
            selectedUnitIDs = []
            setGuardianSelected(true)
        }
        GameAudio.shared.play(.select)
    }

    private func setGuardianSelected(_ selected: Bool) {
        isGuardianSelected = selected
        world.setPlayerSelected(selected)
    }

    func updateMoveHover(with worldPoint: SCNVector3?) {
        guard !isPaused, placementState == nil, interactionMode == .rts else {
            world.updateMoveHover(at: nil)
            return
        }
        world.updateMoveHover(at: worldPoint)
    }

    func syncAudio(with settings: GameSettings) {
        GameAudio.shared.configure(
            musicVolume: settings.musicVolume,
            effectsVolume: settings.effectsVolume
        )
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

    func movePlayer(to worldPoint: SCNVector3) {
        guard !isPaused else { return }
        world.movePlayer(to: worldPoint)
        GameAudio.shared.play(.move)
    }

    func playerDig() {
        guard !isPaused else { return }
        applyHarvest(world.digPlayerForward())
    }

    func playInvalidPlacementFeedback() {
        GameAudio.shared.play(.invalid)
    }

    /// Minecraft: break the surface block at a world column.
    func mineBlock(at worldPoint: SCNVector3) {
        guard !isPaused, interactionMode == .mine,
              let coordinate = world.gridCoordinate(for: worldPoint) else { return }
        applyHarvest(world.mineBlock(at: coordinate))
    }

    /// Minecraft: spend inventory to place a block above terrain.
    func placeBlock(at worldPoint: SCNVector3) {
        guard !isPaused, interactionMode == .place,
              let coordinate = world.gridCoordinate(for: worldPoint) else { return }
        let available = inventory[placeBlockType, default: 0]
        guard available > 0 else {
            playInvalidPlacementFeedback()
            return
        }
        guard world.placeBlock(placeBlockType, at: coordinate) else {
            playInvalidPlacementFeedback()
            return
        }
        inventory[placeBlockType, default: 0] -= 1
        recalculateCounts()
        GameAudio.shared.play(.dig)
    }

    /// Age of Empires: train a villager when food and housing allow.
    func trainVillager() {
        let foodCost = 50
        let soilCost = 10
        guard economy.population < economy.populationCap else {
            playInvalidPlacementFeedback()
            return
        }
        guard economy.consume(foodCost, of: .food), economy.consume(soilCost, of: .soil) else {
            playInvalidPlacementFeedback()
            return
        }
        let spawn = world.playerWorldPosition ?? world.focusPoint
        units.append(Unit(role: .miner, position: spawn))
        economy.adjustPopulation(by: 1)
        GameAudio.shared.play(.select)
    }

    /// Craft tunnel blocks from soil and stone (Minecraft-style recipe).
    func craftTunnelBlocks() {
        let soilCost = 2
        let stoneCost = 1
        guard inventory[.soil, default: 0] >= soilCost,
              inventory[.rock, default: 0] >= stoneCost else {
            playInvalidPlacementFeedback()
            return
        }
        inventory[.soil, default: 0] -= soilCost
        inventory[.rock, default: 0] -= stoneCost
        inventory[.tunnel, default: 0] += 4
    }

    var populationLabel: String {
        "\(economy.population)/\(economy.populationCap)"
    }

    private func applyHarvest(_ harvested: BlockType?) {
        guard let harvested else { return }
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
        GameAudio.shared.play(.dig)
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

    /// Enter build mode with the provided template.
    func beginPlacement(for template: Building.Template) {
        placementState = PlacementState(template: template, evaluation: nil)
        world.updatePlacementPreview(for: nil)
    }

    /// Toggle build mode—tapping the same template twice cancels it.
    func togglePlacement(for template: Building.Template) {
        if let existing = placementState, existing.template.id == template.id {
            cancelPlacement()
        } else {
            beginPlacement(for: template)
        }
    }

    /// Exit build mode and hide the ghost mesh.
    func cancelPlacement() {
        placementState = nil
        world.updatePlacementPreview(for: nil)
    }

    /// Update the ghost mesh based on the cursor hit-test point.
    func updatePlacementHover(with worldPoint: SCNVector3?) {
        guard var state = placementState else { return }
        guard let worldPoint, let coordinate = world.gridCoordinate(for: worldPoint) else {
            state.evaluation = nil
            placementState = state
            world.updatePlacementPreview(for: nil)
            return
        }
        let evaluation = world.evaluatePlacement(at: coordinate, footprint: state.template.footprint)
        state.evaluation = evaluation
        placementState = state
        world.updatePlacementPreview(for: evaluation)
    }

    /// Convert the ghost blueprint into a queued build command for selected units.
    func commitPlacement() {
        guard let state = placementState,
              let evaluation = state.evaluation,
              evaluation.valid else { return }
        let blueprint = state.template.makeBlueprint(at: evaluation.worldPosition)
        issue(command: .build(blueprint))
        placementState = nil
        world.updatePlacementPreview(for: nil)
    }

    /// Forward raw orbit deltas to the world controller.
    func orbitCamera(by delta: CGPoint) {
        world.orbitCamera(by: delta)
    }

    /// Forward planar panning to the world controller.
    func panCamera(by delta: CGPoint) {
        world.panCamera(by: delta)
    }

    /// Forward dolly/zoom deltas to the world controller.
    func zoomCamera(by delta: CGFloat) {
        world.zoomCamera(by: delta)
    }

    /// Tracks the active template and last evaluation result while in build mode.
    struct PlacementState {
        let template: Building.Template
        var evaluation: GameWorld.PlacementEvaluation?

        var isValid: Bool {
            evaluation?.valid ?? false
        }
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
