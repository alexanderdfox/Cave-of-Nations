//
//  Building.swift
//  CaveOfNationsApp
//
//  Contains lightweight types that describe player structures:
//  - `Template` holds authoring data for the command menu.
//  - `Blueprint` captures placement coordinates and costs for queued builds.
//

import Foundation
import SceneKit
import simd

struct Building: Identifiable {
    /// Immutable snapshot of a build command that units can execute.
    struct Blueprint {
        let name: String
        let cost: [EconomyState.Resource: Int]
        let populationBonus: Int
        let location: SCNVector3
        let footprint: SIMD2<Int>
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

    /// Authoring-time description of a building that can be placed in the world.
    struct Template: Identifiable {
        let id = UUID()
        let kind: Kind
        let name: String
        let cost: [EconomyState.Resource: Int]
        let populationBonus: Int
        let footprint: SIMD2<Int>

        func makeBlueprint(at position: SCNVector3) -> Blueprint {
            Blueprint(
                name: name,
                cost: cost,
                populationBonus: populationBonus,
                location: position,
                footprint: footprint
            )
        }
    }
}
