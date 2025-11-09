import Foundation
import SceneKit

struct Building: Identifiable {
    struct Blueprint {
        let name: String
        let cost: [EconomyState.Resource: Int]
        let populationBonus: Int
        let location: SCNVector3
    }

    enum Kind {
        case burrow
        case workshop
        case nexus
    }

    let id = UUID()
    let kind: Kind
    let position: SCNVector3
    let blueprint: Blueprint
}
