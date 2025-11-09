import Foundation
import SceneKit

struct Unit: Identifiable {
    enum Role {
        case miner
        case builder
        case scout
        case soldier
    }

    enum Command {
        case move(to: SCNVector3)
        case harvest(BlockType)
        case build(Building.Blueprint)
        case patrol(points: [SCNVector3])
        case idle
    }

    let id: UUID
    let role: Role
    private(set) var position: SCNVector3
    private var queue: [Command] = []
    private var cooldown: TimeInterval = 0

    init(role: Role, position: SCNVector3) {
        self.id = UUID()
        self.role = role
        self.position = position
        self.queue = [.idle]
    }

    mutating func enqueue(command: Command) {
        queue.append(command)
    }

    mutating func update(in world: GameWorld, economy: inout EconomyState) {
        guard !queue.isEmpty else {
            queue = [.idle]
            return
        }

        cooldown = max(0, cooldown - 0.5)
        guard cooldown == 0 else { return }

        var current = queue.removeFirst()
        switch current {
        case .move(let destination):
            position = destination
        case .harvest(let blockType):
            handleHarvest(blockType, economy: &economy)
        case .build(let blueprint):
            handleBuild(blueprint, economy: &economy)
        case .patrol(let points):
            if let next = points.first {
                position = next
                if points.count > 1 {
                    current = .patrol(points: Array(points.dropFirst()) + [next])
                    queue.insert(current, at: 0)
                } else {
                    queue.append(.idle)
                }
            }
        case .idle:
            queue.append(.idle)
        }
        cooldown = 1.0
    }

    private mutating func handleHarvest(_ type: BlockType, economy: inout EconomyState) {
        switch type {
        case .soil:
            economy.add(5, of: .soil)
        case .rock:
            economy.add(4, of: .stone)
        case .relic:
            economy.add(1, of: .relic)
        case .pipestone:
            economy.add(2, of: .pipestone)
            economy.add(3, of: .energy)
        case .den:
            economy.add(2, of: .food)
        case .tunnel, .air:
            break
        }
    }

    private mutating func handleBuild(_ blueprint: Building.Blueprint, economy: inout EconomyState) {
        if blueprint.cost.allSatisfy({ economy.consume($0.value, of: $0.key) }) {
            position = blueprint.location
            economy.adjustPopulationCap(by: blueprint.populationBonus)
        }
    }
}
