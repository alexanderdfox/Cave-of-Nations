import Foundation
import RealityKit
import AppKit

struct BlockSpec {
    let name: String
    let color: SIMD3<Float>
}

let specs: [BlockSpec] = [
    BlockSpec(name: "Soil", color: SIMD3<Float>(0.62, 0.41, 0.27)),
    BlockSpec(name: "Rock", color: SIMD3<Float>(0.35, 0.35, 0.4)),
    BlockSpec(name: "Relic", color: SIMD3<Float>(0.93, 0.78, 0.25)),
    BlockSpec(name: "Tunnel", color: SIMD3<Float>(0.1, 0.1, 0.12)),
    BlockSpec(name: "Den", color: SIMD3<Float>(0.88, 0.7, 0.5))
]

let resourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources")
    .appendingPathComponent("Blocks")

try? FileManager.default.createDirectory(at: resourcesRoot, withIntermediateDirectories: true)

func export(spec: BlockSpec) throws {
    let mesh = MeshResource.generateBox(size: 1.0)
    let color = NSColor(calibratedRed: CGFloat(spec.color.x),
                        green: CGFloat(spec.color.y),
                        blue: CGFloat(spec.color.z),
                        alpha: 1.0)
    let material = SimpleMaterial(color: color, roughness: 0.35, isMetallic: false)
    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.name = "\(spec.name)Block"
    let destination = resourcesRoot.appendingPathComponent("\(spec.name)Block.usdz")
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }

    let exporter = USDZExporter()
    try exporter.export(entities: [entity], to: destination)
    print("Exported \(destination.path)")
}

for spec in specs {
    do {
        try export(spec: spec)
    } catch {
        fputs("Failed to export \(spec.name): \(error)\n", stderr)
        exit(1)
    }
}
