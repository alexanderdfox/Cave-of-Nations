import SceneKit
import AppKit

enum BlockType: CaseIterable {
    case soil
    case rock
    case relic
    case tunnel
    case den
    case pipestone
    case air

    var resourceName: String? {
        switch self {
        case .soil: return "SoilBlock"
        case .rock: return "RockBlock"
        case .relic: return "RelicBlock"
        case .tunnel: return "TunnelBlock"
        case .den: return "DenBlock"
        case .pipestone: return "PipestoneBlock"
        case .air: return nil
        }
    }

    var fallbackColor: NSColor {
        switch self {
        case .soil: return NSColor(calibratedRed: 0.52, green: 0.33, blue: 0.18, alpha: 1)
        case .rock: return NSColor(calibratedWhite: 0.35, alpha: 1)
        case .relic: return NSColor(calibratedRed: 0.93, green: 0.78, blue: 0.25, alpha: 1)
        case .tunnel: return NSColor(calibratedWhite: 0.12, alpha: 1)
        case .den: return NSColor(calibratedRed: 0.88, green: 0.7, blue: 0.5, alpha: 1)
        case .pipestone: return NSColor(calibratedRed: 0.72, green: 0.18, blue: 0.2, alpha: 1)
        case .air: return .clear
        }
    }

    var isSolid: Bool {
        switch self {
        case .air, .tunnel:
            return false
        default:
            return true
        }
    }
}
