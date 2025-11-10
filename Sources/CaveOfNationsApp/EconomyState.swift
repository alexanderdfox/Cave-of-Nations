//
//  EconomyState.swift
//  CaveOfNationsApp
//
//  Tracks resource stockpiles, population limits, and basic upkeep logic used by the game loop.
//

import Foundation
import SceneKit

struct EconomyState {
    enum Resource: CaseIterable {
        case soil
        case stone
        case relic
        case pipestone
        case food
        case energy
    }

    private(set) var stockpile: [Resource: Int] = [:]
    private(set) var population: Int = 3
    private(set) var populationCap: Int = 5

    init() {
        for resource in Resource.allCases {
            stockpile[resource] = 0
        }
        stockpile[.food] = 50
        stockpile[.energy] = 20
    }

    mutating func add(_ amount: Int, of resource: Resource) {
        stockpile[resource, default: 0] += amount
    }

    mutating func consume(_ amount: Int, of resource: Resource) -> Bool {
        let current = stockpile[resource, default: 0]
        guard current >= amount else { return false }
        stockpile[resource] = current - amount
        return true
    }

    mutating func adjustPopulation(by delta: Int) {
        population = max(0, population + delta)
    }

    mutating func adjustPopulationCap(by delta: Int) {
        populationCap = max(1, populationCap + delta)
    }

    mutating func progressTick() {
        // upkeep
        if !consume(1, of: .food) {
            population = max(1, population - 1)
        }
        if !consume(1, of: .energy) {
            // degrade productivity when energy starved
        }
    }

    mutating func resetForNewWorld() {
        self = EconomyState()
    }

    func amount(of resource: Resource) -> Int {
        stockpile[resource, default: 0]
    }
}
