//
//  GameWorld.swift
//  CaveOfNationsApp
//
//  High-level responsibilities:
//  - Owns the procedural voxel terrain, block metadata, and SceneKit nodes.
//  - Orchestrates character spawning, movement, digging, and pathfinding.
//  - Manages the orbital camera rig plus building preview visuals.
//

import Foundation
import SceneKit
import GameplayKit
import simd
import AppKit

final class GameWorld {
    struct Dimensions {
        let width: Int
        let height: Int
        let depth: Int
    }

    private(set) var dimensions: Dimensions
    private let tileSize: CGFloat = 1.0
    private let playerHeightMultiplier: CGFloat = 2.4
    private(set) var scene: SCNScene
    private let quicksandNode = SCNNode()
    private let terrainNode = SCNNode()
    private let charactersNode = SCNNode()
    private let rotationAction: SCNAction? = nil
    private lazy var quicksandMaterial: SCNMaterial = Self.makeQuicksandMaterial()

    /// Orbit-style camera rig anchored at `cameraTarget`. The node itself is reused by `SceneView`.
    private let cameraNode = SCNNode()
    /// Focus point that the orbital camera tracks while panning and zooming.
    private var cameraTarget: SCNVector3 = SCNVector3Zero
    /// `(pitch, yaw)` pair (in radians) that drives the orbital camera transform.
    private var cameraAngles = SIMD2<Double>(0.9, Double.pi * 0.75)
    /// Current distance from the target focus point.
    private var cameraDistance: CGFloat = 0
    private let minCameraDistance: CGFloat = 6
    private let maxCameraDistance: CGFloat = 120

    /// Lazily created translucent mesh that previews building placement validity.
    private var placementPreviewNode: SCNNode?

    private var blockNodes: [[[SCNNode?]]]
    private var blockTypes: [[[BlockType]]]
    private var surfaceDepthCache: [[Int]]?
    private var blockTemplateCache: [BlockType: SCNNode] = [:]
    private var fallbackBlockTemplate: SCNNode?
    private var anubisTemplate: SCNNode?
    private var relicCoordinateStore: [SIMD2<Int>] = []
    private var playerNode: SCNNode?
    private var playerGridPosition: SIMD2<Int>?
    private var playerFacing: SIMD2<Int> = SIMD2(0, -1)
    private var playerSelected: Bool = false
    private var playerSelectionNode: SCNNode?
    private lazy var characterIdleAction: SCNAction = {
        let up = SCNAction.moveBy(x: 0, y: 0.25, z: 0, duration: 1.6)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        return SCNAction.repeatForever(SCNAction.sequence([up, down]))
    }()

    var onPlayerPositionChange: ((SIMD2<Int>) -> Void)?

    var focusPoint: SCNVector3 {
        SCNVector3(
            CGFloat(dimensions.width - 1) * tileSize / 2,
            CGFloat(dimensions.height - 1) * tileSize / 2,
            CGFloat(dimensions.depth - 1) * tileSize / 2
        )
    }

    var playerWorldPosition: SCNVector3? {
        playerNode?.presentation.position ?? playerNode?.position
    }

    var playerGridCoordinate: SIMD2<Int>? {
        playerGridPosition
    }

    /// Summary of a placement probe against the voxel grid.
    struct PlacementEvaluation {
        let coordinate: SIMD2<Int>
        let worldPosition: SCNVector3
        let footprint: SIMD2<Int>
        let valid: Bool
    }

    /// Adjust the orbit camera angles with a screen-space drag delta.
    func orbitCamera(by delta: CGPoint) {
        let sensitivity = 0.0032
        cameraAngles.y -= Double(delta.x) * sensitivity
        cameraAngles.x += Double(delta.y) * sensitivity
        let minPitch = 0.2
        let maxPitch = 1.2
        cameraAngles.x = max(minPitch, min(maxPitch, cameraAngles.x))
        updateCameraTransform(animated: true)
    }

    /// Translate the focus point parallel to the ground plane.
    func panCamera(by delta: CGPoint) {
        guard cameraDistance > 0 else { return }
        let scale = Float(cameraDistance) * 0.0008
        let right = cameraNode.simdWorldRight
        let forward = -cameraNode.simdWorldFront
        var translation = (-Float(delta.x) * scale) * right + (Float(delta.y) * scale) * forward
        translation.y = 0
        cameraTarget.x += CGFloat(translation.x)
        cameraTarget.z += CGFloat(translation.z)
        clampCameraTarget()
        updateCameraTransform(animated: false)
    }

    /// Dolly the camera toward or away from the focus point.
    func zoomCamera(by delta: CGFloat) {
        guard cameraDistance > 0 else { return }
        let zoomFactor = 1 - (delta * 0.02)
        cameraDistance = max(minCameraDistance, min(maxCameraDistance, cameraDistance * max(0.25, min(1.75, zoomFactor))))
        updateCameraTransform(animated: false)
    }

    /// Snap the focus point to an arbitrary world-space location.
    func focusCamera(on point: SCNVector3, animated: Bool = true) {
        cameraTarget = point
        clampCameraTarget()
        updateCameraTransform(animated: animated)
    }

    init(dimensions: Dimensions) {
        self.dimensions = dimensions
        self.scene = SCNScene()
        self.blockNodes = Array(repeating: Array(repeating: Array(repeating: nil, count: dimensions.depth), count: dimensions.height), count: dimensions.width)
        self.blockTypes = Array(repeating: Array(repeating: Array(repeating: .air, count: dimensions.depth), count: dimensions.height), count: dimensions.width)
        configureScene()
        rebuild()
    }

    func rebuild(with dimensions: Dimensions? = nil) {
        if let newDimensions = dimensions, newDimensions.width != self.dimensions.width || newDimensions.height != self.dimensions.height || newDimensions.depth != self.dimensions.depth {
            self.dimensions = newDimensions
            blockNodes = Array(repeating: Array(repeating: Array(repeating: nil, count: newDimensions.depth), count: newDimensions.height), count: newDimensions.width)
            blockTypes = Array(repeating: Array(repeating: Array(repeating: .air, count: newDimensions.depth), count: newDimensions.height), count: newDimensions.width)
        }
        terrainNode.childNodes.forEach { $0.removeFromParentNode() }
        charactersNode.childNodes.forEach { $0.removeFromParentNode() }
        invalidateSurfaceDepthCache()
        layoutQuicksandPlane()
        generateBlocks()
        layoutBlocks()
        spawnPlayerCharacter()
        updatePlacementPreview(for: nil)
        resetCamera(animated: true)
    }

    func blockCounts() -> [BlockType: Int] {
        var counts: [BlockType: Int] = [:]
        for x in 0..<dimensions.width {
            for y in 0..<dimensions.height {
                for z in 0..<dimensions.depth {
                    let type = blockTypes[x][y][z]
                    counts[type, default: 0] += 1
                }
            }
        }
        return counts
    }

    func surfaceDepthMap() -> [[Int]] {
        if let cache = surfaceDepthCache {
            return cache
        }
        var map: [[Int]] = Array(repeating: Array(repeating: -1, count: dimensions.width), count: dimensions.depth)
        for z in 0..<dimensions.depth {
            for x in 0..<dimensions.width {
                map[z][x] = surfaceLevel(atX: x, z: z) ?? -1
            }
        }
        surfaceDepthCache = map
        return map
    }

    private func invalidateSurfaceDepthCache() {
        surfaceDepthCache = nil
    }

    private func updateSurfaceDepthCache(at coordinate: SIMD2<Int>) {
        guard coordinate.y >= 0, coordinate.y < dimensions.depth,
              coordinate.x >= 0, coordinate.x < dimensions.width else { return }
        if surfaceDepthCache == nil {
            surfaceDepthCache = surfaceDepthMap()
            return
        }
        guard var cache = surfaceDepthCache else { return }
        cache[coordinate.y][coordinate.x] = surfaceLevel(atX: coordinate.x, z: coordinate.y) ?? -1
        surfaceDepthCache = cache
    }

    private func configureScene() {
        scene.rootNode.addChildNode(quicksandNode)
        scene.rootNode.addChildNode(terrainNode)
        scene.rootNode.addChildNode(charactersNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 200
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let directional = SCNLight()
        directional.type = .directional
        directional.intensity = 900
        directional.castsShadow = true
        directional.shadowMode = .deferred
        directional.shadowColor = NSColor.black.withAlphaComponent(0.55)
        let directionalNode = SCNNode()
        directionalNode.eulerAngles = SCNVector3(-CGFloat.pi / 3.5, CGFloat.pi / 4, 0)
        directionalNode.light = directional
        scene.rootNode.addChildNode(directionalNode)

        let camera = SCNCamera()
        camera.zFar = 400
        camera.zNear = 0.1
        camera.fieldOfView = 68
        cameraNode.camera = camera
        cameraNode.name = "primary.camera"
        scene.rootNode.addChildNode(cameraNode)
        resetCamera(animated: false)

        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -0.5, 0)
        floorNode.geometry?.firstMaterial?.diffuse.contents = NSColor.darkGray
        scene.rootNode.addChildNode(floorNode)

        layoutQuicksandPlane()
    }

    /// Initialize the camera rig each time the world is rebuilt.
    private func resetCamera(animated: Bool) {
        cameraTarget = focusPoint
        let baseline = max(CGFloat(dimensions.width), CGFloat(dimensions.depth)) * tileSize * 1.75
        cameraDistance = baseline.clamped(to: minCameraDistance...maxCameraDistance)
        cameraAngles = SIMD2<Double>(0.82, Double.pi * 0.72)
        updateCameraTransform(animated: animated, duration: animated ? 0.35 : 0)
    }

    /// Prevent panning from straying too far outside the playable area.
    private func clampCameraTarget() {
        let minX: CGFloat = -tileSize * 4
        let maxX: CGFloat = CGFloat(dimensions.width - 1) * tileSize + tileSize * 4
        let minZ: CGFloat = -tileSize * 4
        let maxZ: CGFloat = CGFloat(dimensions.depth - 1) * tileSize + tileSize * 4
        cameraTarget.x = cameraTarget.x.clamped(to: minX...maxX)
        cameraTarget.z = cameraTarget.z.clamped(to: minZ...maxZ)
        let minY: CGFloat = tileSize * 0.5
        let maxY: CGFloat = CGFloat(dimensions.height) * tileSize
        cameraTarget.y = cameraTarget.y.clamped(to: minY...maxY)
    }

    /// Convert the polar camera state into an SCNNode transform.
    private func updateCameraTransform(animated: Bool, duration: TimeInterval = 0.18) {
        guard cameraDistance > 0 else { return }
        let pitch = cameraAngles.x
        let yaw = cameraAngles.y
        let cosPitch = cos(pitch)
        let sinPitch = sin(pitch)
        let sinYaw = sin(yaw)
        let cosYaw = cos(yaw)
        let offsetX = cameraDistance * CGFloat(sinYaw * cosPitch)
        let offsetY = cameraDistance * CGFloat(sinPitch)
        let offsetZ = cameraDistance * CGFloat(cosYaw * cosPitch)
        let target = cameraTarget
        let position = SCNVector3(
            target.x + offsetX,
            target.y + offsetY,
            target.z + offsetZ
        )

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        cameraNode.position = position
        cameraNode.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        SCNTransaction.commit()
    }

    private func layoutQuicksandPlane() {
        let width = CGFloat(dimensions.width) * tileSize + tileSize * 6
        let height = CGFloat(dimensions.depth) * tileSize + tileSize * 6
        let plane = SCNPlane(width: width, height: height)
        plane.cornerRadius = tileSize * 2.5
        plane.materials = [quicksandMaterial]
        quicksandNode.geometry = plane
        quicksandNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        quicksandNode.position = SCNVector3(focusPoint.x, -tileSize * 0.65, focusPoint.z)
    }

    private func generateBlocks() {
        invalidateSurfaceDepthCache()
        relicCoordinateStore = []
        let source = GKPerlinNoiseSource(frequency: 0.3, octaveCount: 4, persistence: 0.55, lacunarity: 2.2, seed: Int32.random(in: Int32.min...Int32.max))
        let noise = GKNoise(source)
        let map = GKNoiseMap(noise, size: vector_double2(1.0, 1.0), origin: vector_double2(0, 0), sampleCount: vector_int2(Int32(dimensions.width), Int32(dimensions.depth)), seamless: true)

        for x in 0..<dimensions.width {
            for z in 0..<dimensions.depth {
                let heightNoise = noiseValue(map: map, x: x, z: z)
                let columnHeight = max(2, Int(Double(dimensions.height) * (0.45 + 0.35 * heightNoise)))
                for y in 0..<dimensions.height {
                    let blockType: BlockType
                    if y >= columnHeight {
                        blockType = .air
                    } else if y == 0 {
                        blockType = .den
                    } else if y < columnHeight - 3 {
                        blockType = Bool.random(probability: 0.12) ? .rock : .soil
                    } else if Bool.random(probability: 0.06) {
                        blockType = .relic
                    } else if Bool.random(probability: 0.04) {
                        blockType = .pipestone
                    } else {
                        blockType = .soil
                    }

                    blockTypes[x][y][z] = blockType
                    if blockType == .relic {
                        relicCoordinateStore.append(SIMD2(x, z))
                    }
                }
            }
        }
    }

    private func layoutBlocks() {
        for x in 0..<dimensions.width {
            for y in 0..<dimensions.height {
                for z in 0..<dimensions.depth {
                    let type = blockTypes[x][y][z]
                    guard type != .air else { continue }
                    let node = makeBlockNode(for: type)
                    node.position = SCNVector3(
                        CGFloat(x) * tileSize,
                        CGFloat(y) * tileSize,
                        CGFloat(z) * tileSize
                    )
                    terrainNode.addChildNode(node)
                    if let rotationAction {
                        node.runAction(rotationAction)
                    }
                    blockNodes[x][y][z] = node
                }
            }
        }
    }

    private func makeBlockNode(for type: BlockType) -> SCNNode {
        if type == .air {
            return SCNNode()
        }
        return blockTemplate(for: type).clone()
    }

    /// Uniformly scales USDZ assets so their largest axis matches a single tile.
    private func normalize(node: SCNNode, targetHeight: CGFloat? = nil) {
        let (minVec, maxVec) = node.boundingBox
        let sizeX = CGFloat(maxVec.x - minVec.x)
        let sizeY = CGFloat(maxVec.y - minVec.y)
        let sizeZ = CGFloat(maxVec.z - minVec.z)
        let extent = max(sizeX, max(sizeY, sizeZ))
        guard extent > 0 else { return }
        let desired = targetHeight ?? tileSize
        let scale = desired / extent
        let floatScale = Float(scale)
        node.scale = SCNVector3(floatScale, floatScale, floatScale)
        let center = SCNVector3(
            (maxVec.x + minVec.x) / 2,
            (maxVec.y + minVec.y) / 2,
            (maxVec.z + minVec.z) / 2
        )
        node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
    }

    private func spawnPlayerCharacter() {
        charactersNode.childNodes.forEach { $0.removeFromParentNode() }
        playerNode = nil
        playerGridPosition = nil
        playerFacing = SIMD2(0, -1)

        if anubisTemplate == nil {
            guard let url = Bundle.module.url(forResource: "AnubisGuardian", withExtension: "usdz", subdirectory: "Characters"),
                  let characterScene = try? SCNScene(url: url, options: nil) else {
                return
            }
            let template = SCNNode()
            for child in characterScene.rootNode.childNodes {
                let copy = child.clone()
                normalize(node: copy, targetHeight: tileSize * playerHeightMultiplier)
                template.addChildNode(copy)
            }
            anubisTemplate = template
        }

        guard let template = anubisTemplate else { return }
        let container = template.clone()

        var spawnCoordinate = defaultPlayerSpawnCoordinate()
        var surface = navigableSurface(atX: spawnCoordinate.x, z: spawnCoordinate.y)

        if surface == nil, let fallback = firstNavigableCoordinate() {
            spawnCoordinate = fallback.coordinate
            surface = fallback.surface
        }

        let resolvedSurface = surface ?? -1
        let position = playerWorldPosition(x: spawnCoordinate.x, surface: resolvedSurface, z: spawnCoordinate.y)

        container.position = position
        container.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
        container.runAction(characterIdleAction, forKey: "guardian.idle")

        let ringGeometry = SCNTorus(ringRadius: tileSize * 0.55, pipeRadius: tileSize * 0.05)
        let ringMaterial = SCNMaterial()
        ringMaterial.diffuse.contents = NSColor.systemYellow.withAlphaComponent(0.75)
        ringMaterial.emission.contents = NSColor.systemYellow
        ringMaterial.lightingModel = .physicallyBased
        ringGeometry.materials = [ringMaterial]
        let ringNode = SCNNode(geometry: ringGeometry)
        ringNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        ringNode.position = SCNVector3(0, -CGFloat(playerHeightMultiplier) * tileSize / 2 + 0.05, 0)
        ringNode.isHidden = true
        container.addChildNode(ringNode)
        playerSelectionNode = ringNode
        playerSelected = false

        charactersNode.addChildNode(container)
        playerNode = container
        playerGridPosition = spawnCoordinate
        onPlayerPositionChange?(spawnCoordinate)
    }

    func movePlayer(by delta: SIMD2<Int>) {
        guard let current = playerGridPosition,
              let node = playerNode else { return }

        let candidate = SIMD2(current.x + delta.x, current.y + delta.y)
        guard candidate.x >= 0,
              candidate.x < dimensions.width,
              candidate.y >= 0,
              candidate.y < dimensions.depth else { return }

        guard let surface = navigableSurface(atX: candidate.x, z: candidate.y) else { return }

        let target = playerWorldPosition(x: candidate.x, surface: surface, z: candidate.y)
        let moveAction = SCNAction.move(to: target, duration: 0.25)
        moveAction.timingMode = .easeInEaseOut
        node.runAction(moveAction, forKey: "guardian.move")

        let facing = facingAngle(for: delta)
        let rotateAction = SCNAction.rotateTo(x: 0, y: facing, z: 0, duration: 0.2, usesShortestUnitArc: true)
        node.runAction(rotateAction, forKey: "guardian.face")

        if node.action(forKey: "guardian.idle") == nil {
            node.runAction(characterIdleAction, forKey: "guardian.idle")
        }

        playerGridPosition = candidate
        onPlayerPositionChange?(candidate)
        if delta.x != 0 || delta.y != 0 {
            playerFacing = delta
        }
    }

    @discardableResult
    func digPlayerForward() -> BlockType? {
        guard let current = playerGridPosition else { return nil }
        let targetColumn = SIMD2(current.x + playerFacing.x, current.y + playerFacing.y)
        guard targetColumn.x >= 0, targetColumn.x < dimensions.width,
              targetColumn.y >= 0, targetColumn.y < dimensions.depth else { return nil }

        guard let surface = surfaceLevel(atX: targetColumn.x, z: targetColumn.y) else {
            return nil
        }

        let blockType = blockTypes[targetColumn.x][surface][targetColumn.y]
        guard blockType != .air else { return nil }

        if let node = blockNodes[targetColumn.x][surface][targetColumn.y] {
            node.removeFromParentNode()
            blockNodes[targetColumn.x][surface][targetColumn.y] = nil
        }

        blockTypes[targetColumn.x][surface][targetColumn.y] = .air
        updateSurfaceDepthCache(at: targetColumn)
        if blockType == .relic {
            relicCoordinateStore.removeAll { $0 == targetColumn }
        }

        let digPosition = playerWorldPosition(x: targetColumn.x, surface: surface, z: targetColumn.y)
        spawnDigParticles(at: digPosition, color: blockColor(for: blockType))
        animatePlayerDig()

        return blockType
    }

    private func defaultPlayerSpawnCoordinate() -> SIMD2<Int> {
        let x = max(0, min(dimensions.width - 1, dimensions.width / 2))
        let z = max(0, min(dimensions.depth - 1, dimensions.depth / 2))
        return SIMD2(x, z)
    }

    private func surfaceLevel(atX x: Int, z: Int) -> Int? {
        guard x >= 0, x < dimensions.width,
              z >= 0, z < dimensions.depth else { return nil }
        for y in stride(from: dimensions.height - 1, through: 0, by: -1) {
            if blockTypes[x][y][z] != .air {
                return y
            }
        }
        return nil
    }

    private func navigableSurface(atX x: Int, z: Int) -> Int? {
        guard x >= 0, x < dimensions.width,
              z >= 0, z < dimensions.depth else { return nil }
        let surface = surfaceLevel(atX: x, z: z) ?? -1
        let headIndex = surface + 1
        if headIndex >= dimensions.height {
            return nil
        }
        if headIndex >= 0 {
            let headBlock = blockTypes[x][headIndex][z]
            if headBlock != .air {
                return nil
            }
        }
        return surface
    }

    private func firstNavigableCoordinate() -> (coordinate: SIMD2<Int>, surface: Int)? {
        let centerX = dimensions.width / 2
        let centerZ = dimensions.depth / 2

        var candidates: [(coord: SIMD2<Int>, distance: Double)] = []
        for x in 0..<dimensions.width {
            for z in 0..<dimensions.depth {
                let dx = Double(x - centerX)
                let dz = Double(z - centerZ)
                let distance = dx * dx + dz * dz
                candidates.append((SIMD2(x, z), distance))
            }
        }

        candidates.sort { $0.distance < $1.distance }

        for candidate in candidates {
            let coordinate = candidate.coord
            if let surface = navigableSurface(atX: coordinate.x, z: coordinate.y) {
                return (coordinate, surface)
            }
        }

        return nil
    }

    private func playerWorldPosition(x: Int, surface: Int, z: Int) -> SCNVector3 {
        let playerHeight = tileSize * playerHeightMultiplier
        let effectiveSurface = max(surface, -1)
        let groundTop = CGFloat(effectiveSurface) * tileSize + tileSize / 2
        let centerY = groundTop + playerHeight / 2
        return SCNVector3(
            CGFloat(x) * tileSize,
            centerY,
            CGFloat(z) * tileSize
        )
    }

    private func facingAngle(for delta: SIMD2<Int>) -> CGFloat {
        if delta.x == 0 && delta.y == 0 {
            return playerNode?.presentation.eulerAngles.y ?? 0
        }
        return CGFloat(atan2(Double(delta.x), Double(-delta.y)))
    }

    func gridCoordinate(for worldPoint: SCNVector3) -> SIMD2<Int>? {
        guard tileSize != 0 else { return nil }
        let x = Int(round(Double(CGFloat(worldPoint.x) / tileSize)))
        let z = Int(round(Double(CGFloat(worldPoint.z) / tileSize)))
        guard x >= 0, x < dimensions.width, z >= 0, z < dimensions.depth else { return nil }
        return SIMD2(x, z)
    }

    private func findPath(from start: SIMD2<Int>, to goal: SIMD2<Int>) -> [SIMD2<Int>]? {
        guard start != goal else { return [start, goal] }
        var openSet: Set<SIMD2<Int>> = [start]
        var cameFrom: [SIMD2<Int>: SIMD2<Int>] = [:]
        var gScore: [SIMD2<Int>: Int] = [start: 0]
        var fScore: [SIMD2<Int>: Int] = [start: heuristic(start, goal)]

        while !openSet.isEmpty {
            guard let current = openSet.min(by: { (fScore[$0] ?? Int.max) < (fScore[$1] ?? Int.max) }) else { break }
            if current == goal {
                return reconstructPath(cameFrom: cameFrom, current: current)
            }

            openSet.remove(current)
            for neighbor in neighbors(of: current) {
                guard navigableSurface(atX: neighbor.x, z: neighbor.y) != nil else { continue }
                let tentativeG = (gScore[current] ?? Int.max) + 1
                if tentativeG < (gScore[neighbor] ?? Int.max) {
                    cameFrom[neighbor] = current
                    gScore[neighbor] = tentativeG
                    fScore[neighbor] = tentativeG + heuristic(neighbor, goal)
                    openSet.insert(neighbor)
                }
            }
        }
        return nil
    }

    private func heuristic(_ a: SIMD2<Int>, _ b: SIMD2<Int>) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func neighbors(of coordinate: SIMD2<Int>) -> [SIMD2<Int>] {
        [SIMD2(coordinate.x + 1, coordinate.y),
         SIMD2(coordinate.x - 1, coordinate.y),
         SIMD2(coordinate.x, coordinate.y + 1),
         SIMD2(coordinate.x, coordinate.y - 1)]
            .filter { $0.x >= 0 && $0.x < dimensions.width && $0.y >= 0 && $0.y < dimensions.depth }
    }

    private func reconstructPath(cameFrom: [SIMD2<Int>: SIMD2<Int>], current: SIMD2<Int>) -> [SIMD2<Int>] {
        var path: [SIMD2<Int>] = [current]
        var currentNode = current
        while let parent = cameFrom[currentNode] {
            path.append(parent)
            currentNode = parent
        }
        return path.reversed()
    }

    private func followPath(_ path: [SIMD2<Int>]) {
        guard let playerNode else { return }
        guard path.count > 1 else { return }

        var actions: [SCNAction] = []
        var previous = path[0]

        for coordinate in path.dropFirst() {
            guard let surface = navigableSurface(atX: coordinate.x, z: coordinate.y) else { continue }
            let target = playerWorldPosition(x: coordinate.x, surface: surface, z: coordinate.y)
            let delta = SIMD2(coordinate.x - previous.x, coordinate.y - previous.y)
            let facing = facingAngle(for: delta)
            let rotate = SCNAction.rotateTo(x: 0, y: facing, z: 0, duration: 0.15, usesShortestUnitArc: true)
            let move = SCNAction.move(to: target, duration: 0.28)
            move.timingMode = .easeInEaseOut
            let group = SCNAction.group([rotate, move])
            let updateState = SCNAction.run { [weak self] _ in
                self?.playerGridPosition = coordinate
                self?.onPlayerPositionChange?(coordinate)
                if delta.x != 0 || delta.y != 0 {
                    self?.playerFacing = delta
                }
            }
            actions.append(group)
            actions.append(updateState)
            previous = coordinate
        }

        let ensureIdle = SCNAction.run { [weak self] node in
            guard let self else { return }
            if node.action(forKey: "guardian.idle") == nil {
                node.runAction(self.characterIdleAction, forKey: "guardian.idle")
            }
        }
        actions.append(ensureIdle)

        playerNode.runAction(SCNAction.sequence(actions), forKey: "guardian.path")
    }

    /// Request an A* path toward a hit-test coordinate and animate the guardian along it.
    func movePlayer(to worldPoint: SCNVector3) {
        guard let playerNode, let current = playerGridPosition else { return }
        guard let targetCoordinate = gridCoordinate(for: worldPoint) else { return }
        guard targetCoordinate != current else { return }
        guard let path = findPath(from: current, to: targetCoordinate) else { return }
        playerNode.removeAction(forKey: "guardian.path")
        followPath(path)
    }

    /// Validate a rectangular building footprint and return the associated world transform.
    func evaluatePlacement(at coordinate: SIMD2<Int>, footprint: SIMD2<Int>) -> PlacementEvaluation {
        let footprintX = max(1, footprint.x)
        let footprintZ = max(1, footprint.y)
        var surfaces: [Int] = []
        var valid = true

        for dx in 0..<footprintX {
            for dz in 0..<footprintZ {
                let x = coordinate.x + dx
                let z = coordinate.y + dz
                guard x >= 0, x < dimensions.width, z >= 0, z < dimensions.depth else {
                    valid = false
                    continue
                }
                guard let surface = surfaceLevel(atX: x, z: z) else {
                    valid = false
                    continue
                }
                let headIndex = surface + 1
                if headIndex >= dimensions.height {
                    valid = false
                } else if headIndex >= 0 && blockTypes[x][headIndex][z] != .air {
                    valid = false
                }
                surfaces.append(surface)
            }
        }

        if valid, let reference = surfaces.first {
            valid = surfaces.allSatisfy { abs($0 - reference) <= 1 }
        } else if surfaces.isEmpty {
            valid = false
        }

        let maxSurface = surfaces.max() ?? 0
        let halfTile = tileSize / 2
        let groundTop = CGFloat(maxSurface) * tileSize + halfTile
        let buildingHeight = tileSize * 0.9
        let centerX = CGFloat(coordinate.x) + CGFloat(footprintX - 1) / 2
        let centerZ = CGFloat(coordinate.y) + CGFloat(footprintZ - 1) / 2
        let position = SCNVector3(
            centerX * tileSize,
            groundTop + buildingHeight / 2,
            centerZ * tileSize
        )

        return PlacementEvaluation(
            coordinate: coordinate,
            worldPosition: position,
            footprint: SIMD2<Int>(footprintX, footprintZ),
            valid: valid
        )
    }

    /// Create or update the translucent placement preview mesh.
    func updatePlacementPreview(for evaluation: PlacementEvaluation?) {
        guard let evaluation else {
            placementPreviewNode?.removeFromParentNode()
            placementPreviewNode = nil
            return
        }

        let width = CGFloat(evaluation.footprint.x) * tileSize
        let length = CGFloat(evaluation.footprint.y) * tileSize
        let height = tileSize * 0.9

        let node: SCNNode
        if let existing = placementPreviewNode, let box = existing.geometry as? SCNBox {
            if abs(box.width - width) > 0.01 || abs(box.length - length) > 0.01 {
                box.width = width
                box.length = length
            }
            node = existing
        } else {
            let box = SCNBox(width: width, height: height, length: length, chamferRadius: tileSize * 0.08)
            let material = SCNMaterial()
            material.diffuse.contents = NSColor.systemGreen.withAlphaComponent(0.35)
            material.emission.contents = NSColor.systemGreen
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.blendMode = .alpha
            box.materials = [material]
            let newNode = SCNNode(geometry: box)
            newNode.opacity = 0.85
            newNode.name = "placement.preview"
            newNode.castsShadow = false
            terrainNode.addChildNode(newNode)
            placementPreviewNode = newNode
            node = newNode
        }

        if let material = node.geometry?.firstMaterial {
            if evaluation.valid {
                material.diffuse.contents = NSColor.systemGreen.withAlphaComponent(0.35)
                material.emission.contents = NSColor.systemGreen.withAlphaComponent(0.65)
            } else {
                material.diffuse.contents = NSColor.systemRed.withAlphaComponent(0.35)
                material.emission.contents = NSColor.systemRed.withAlphaComponent(0.65)
            }
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.15
        node.position = evaluation.worldPosition
        SCNTransaction.commit()
    }

    func isPlayerSelected(_ node: SCNNode) -> Bool {
        guard let playerNode else { return false }
        return node === playerNode || nodeHasAncestor(node, ancestor: playerNode)
    }

    private func nodeHasAncestor(_ node: SCNNode, ancestor: SCNNode) -> Bool {
        var current: SCNNode? = node.parent
        while let currentNode = current {
            if currentNode === ancestor { return true }
            current = currentNode.parent
        }
        return false
    }

    func relicCoordinates() -> [SIMD2<Int>] {
        relicCoordinateStore
    }

    func preloadResources() {
        for type in BlockType.allCases where type != .air {
            _ = blockTemplate(for: type)
        }
        if anubisTemplate == nil {
            anubisTemplate = buildAnubisTemplate()
        }
    }

    func setPlayerSelected(_ selected: Bool) {
        playerSelected = selected
        playerSelectionNode?.isHidden = !selected
    }

    func setPaused(_ paused: Bool) {
        scene.isPaused = paused
    }

    private func noiseValue(map: GKNoiseMap, x: Int, z: Int) -> Double {
        let value = map.value(at: vector_int2(Int32(x), Int32(z)))
        return max(0.0, min(1.0, Double(value)))
    }

    private static func makeQuicksandMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = makeQuicksandTexture()
        material.roughness.contents = 0.65
        material.metalness.contents = 0.0
        material.isDoubleSided = true
        material.lightingModel = .physicallyBased
        return material
    }

    private static func makeQuicksandTexture() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor(calibratedRed: 0.58, green: 0.44, blue: 0.26, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let centers = [
            NSPoint(x: size.width * 0.35, y: size.height * 0.6),
            NSPoint(x: size.width * 0.65, y: size.height * 0.4)
        ]
        for center in centers {
            for ring in 0..<6 {
                let radius = CGFloat(60 + ring * 28)
                let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                let alpha = CGFloat(0.12) - CGFloat(ring) * 0.015
                NSColor(calibratedRed: 0.72, green: 0.55, blue: 0.33, alpha: alpha).setStroke()
                let path = NSBezierPath(ovalIn: rect)
                path.lineWidth = CGFloat(18 - ring * 2)
                path.stroke()
            }
        }

        let speckPath = NSBezierPath()
        for _ in 0..<350 {
            let point = NSPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height))
            let rect = NSRect(x: point.x, y: point.y, width: 2.2, height: 2.2)
            NSColor(calibratedRed: 0.48, green: 0.34, blue: 0.22, alpha: Double.random(in: 0.2...0.45)).setFill()
            speckPath.appendOval(in: rect)
        }
        speckPath.fill()

        image.unlockFocus()
        return image
    }

    private func blockColor(for type: BlockType) -> NSColor {
        switch type {
        case .soil:
            return NSColor(calibratedRed: 0.58, green: 0.42, blue: 0.26, alpha: 1.0)
        case .rock:
            return NSColor(calibratedWhite: 0.45, alpha: 1.0)
        case .pipestone:
            return NSColor(calibratedRed: 0.74, green: 0.24, blue: 0.26, alpha: 1.0)
        case .relic:
            return NSColor(calibratedRed: 0.93, green: 0.79, blue: 0.32, alpha: 1.0)
        case .den:
            return NSColor(calibratedRed: 0.86, green: 0.70, blue: 0.52, alpha: 1.0)
        case .tunnel, .air:
            return NSColor(calibratedWhite: 0.25, alpha: 1.0)
        }
    }

    private func spawnDigParticles(at position: SCNVector3, color: NSColor) {
        let particleSystem = SCNParticleSystem()
        particleSystem.loops = false
        particleSystem.birthRate = 1200
        particleSystem.emissionDuration = 0.12
        particleSystem.particleLifeSpan = 0.6
        particleSystem.particleLifeSpanVariation = 0.25
        particleSystem.particleVelocity = 2.4
        particleSystem.particleVelocityVariation = 1.6
        particleSystem.particleAngleVariation = 360
        particleSystem.particleSize = 0.06
        particleSystem.particleSizeVariation = 0.03
        particleSystem.particleColor = color
        particleSystem.particleColorVariation = SCNVector4(0.05, 0.05, 0.05, 0.0)
        particleSystem.particleImage = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.white.setFill()
            rect.insetBy(dx: 2, dy: 2).fill()
            return true
        }
        particleSystem.blendMode = .additive
        particleSystem.acceleration = SCNVector3(0, -3.0, 0)

        let emitterNode = SCNNode()
        let newY = CGFloat(position.y) + tileSize * 0.2
        emitterNode.position = SCNVector3(Float(position.x), Float(newY), Float(position.z))
        emitterNode.addParticleSystem(particleSystem)
        terrainNode.addChildNode(emitterNode)

        let cleanup = SCNAction.sequence([
            .wait(duration: 1.0),
            .removeFromParentNode()
        ])
        emitterNode.runAction(cleanup)
    }

    private func animatePlayerDig() {
        guard let playerNode else { return }
        playerNode.removeAction(forKey: "guardian.dig")
        let squash = SCNAction.scale(to: 0.92, duration: 0.1)
        squash.timingMode = .easeInEaseOut
        let stretch = SCNAction.scale(to: 1.0, duration: 0.16)
        stretch.timingMode = .easeOut
        let sequence = SCNAction.sequence([squash, stretch])
        playerNode.runAction(sequence, forKey: "guardian.dig")
    }

    private func blockTemplate(for type: BlockType) -> SCNNode {
        if let cached = blockTemplateCache[type] {
            return cached
        }

        let template: SCNNode
        if let resourceName = type.resourceName,
           let url = Bundle.module.url(forResource: resourceName, withExtension: "usdz", subdirectory: "Blocks"),
           let scene = try? SCNScene(url: url, options: nil) {
            let container = SCNNode()
            for child in scene.rootNode.childNodes {
                let copy = child.clone()
                normalize(node: copy)
                container.addChildNode(copy)
            }
            template = container
        } else {
            if fallbackBlockTemplate == nil {
                let geometry = SCNBox(width: tileSize, height: tileSize, length: tileSize, chamferRadius: tileSize * 0.04)
                let material = SCNMaterial()
                material.diffuse.contents = type.fallbackColor
                material.locksAmbientWithDiffuse = true
                geometry.materials = [material]
                fallbackBlockTemplate = SCNNode(geometry: geometry)
            }
            template = fallbackBlockTemplate ?? SCNNode()
        }

        blockTemplateCache[type] = template
        return template
    }

    private func buildAnubisTemplate() -> SCNNode? {
        guard let url = Bundle.module.url(forResource: "AnubisGuardian", withExtension: "usdz", subdirectory: "Characters"),
              let characterScene = try? SCNScene(url: url, options: nil) else {
            return nil
        }
        let template = SCNNode()
        for child in characterScene.rootNode.childNodes {
            let copy = child.clone()
            normalize(node: copy, targetHeight: tileSize * playerHeightMultiplier)
            template.addChildNode(copy)
        }
        return template
    }
}

private extension Bool {
    static func random(probability: Double) -> Bool {
        Double.random(in: 0...1) < probability
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
