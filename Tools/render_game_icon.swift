#!/usr/bin/env swift
import Foundation
import SceneKit
import AppKit

struct IconGenerator {
    let projectRoot: URL
    let charactersURL: URL
    let iconsetURL: URL

    init() {
        let cwd = FileManager.default.currentDirectoryPath
        projectRoot = URL(fileURLWithPath: cwd)
        charactersURL = projectRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("CaveOfNationsApp")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Characters")
            .appendingPathComponent("AnubisGuardian.usdz")
        iconsetURL = projectRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("CaveOfNationsApp")
            .appendingPathComponent("Resources")
            .appendingPathComponent("AppIcon.iconset")
    }

    func run() throws {
        guard FileManager.default.fileExists(atPath: charactersURL.path) else {
            throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "AnubisGuardian.usdz not found at \(charactersURL.path)"])
        }

        if FileManager.default.fileExists(atPath: iconsetURL.path) {
            try FileManager.default.removeItem(at: iconsetURL)
        }
        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        let baseImage = try renderBaseImage()
        try writeIconImages(from: baseImage)
    }

    private func renderBaseImage() throws -> NSImage {
        let scene = SCNScene()

        let block = SCNBox(width: 1.2, height: 0.6, length: 1.2, chamferRadius: 0.12)
        let blockMaterial = SCNMaterial()
        blockMaterial.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.18, blue: 0.2, alpha: 1.0)
        blockMaterial.lightingModel = .physicallyBased
        block.materials = [blockMaterial]
        let blockNode = SCNNode(geometry: block)
        blockNode.position = SCNVector3(0, -0.4, 0)
        scene.rootNode.addChildNode(blockNode)

        let anubisScene = try SCNScene(url: charactersURL, options: nil)
        let anubisNode = SCNNode()
        anubisScene.rootNode.childNodes.forEach { child in
            let copy = child.clone()
            anubisNode.addChildNode(copy)
        }

        let (minVec, maxVec) = anubisNode.boundingBox
        let extentFloat = max(maxVec.x - minVec.x, max(maxVec.y - minVec.y, maxVec.z - minVec.z))
        let extent = CGFloat(extentFloat)
        let targetHeight: CGFloat = 1.4
        let scale = extent > 0 ? targetHeight / extent : 1.0
        let floatScale = Float(scale)
        anubisNode.scale = SCNVector3(floatScale, floatScale, floatScale)
        anubisNode.position = SCNVector3(0, 0.2, 0)
        scene.rootNode.addChildNode(anubisNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 120
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let directional = SCNLight()
        directional.type = .directional
        directional.intensity = 900
        directional.castsShadow = true
        directional.shadowMode = .deferred
        directional.shadowRadius = 12
        directional.shadowColor = NSColor.black.withAlphaComponent(0.35)
        let directionalNode = SCNNode()
        directionalNode.light = directional
        directionalNode.eulerAngles = SCNVector3(-.pi / 3.2, .pi / 4.5, 0)
        scene.rootNode.addChildNode(directionalNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 400
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-.pi / 2.5, -.pi / 3.0, 0)
        scene.rootNode.addChildNode(fillNode)

        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = true
        camera.bloomIntensity = 0.4
        camera.bloomBlurRadius = 6
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.9, 2.1)
        cameraNode.look(at: SCNVector3(0, 0.1, 0))
        scene.rootNode.addChildNode(cameraNode)

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        renderer.autoenablesDefaultLighting = false

        let size = CGSize(width: 1024, height: 1024)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)

        return image
    }

    private func writeIconImages(from baseImage: NSImage) throws {
        let representations: [(CGFloat, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png")
        ]

        for (dimension, filename) in representations {
            let size = NSSize(width: dimension, height: dimension)
            guard let pngData = baseImage.resized(to: size)?.pngData() else {
                throw NSError(domain: "IconGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create \(filename)"])
            }
            let fileURL = iconsetURL.appendingPathComponent(filename)
            try pngData.write(to: fileURL)
        }
    }
}

private extension NSImage {
    func resized(to newSize: NSSize) -> NSImage? {
        let image = NSImage(size: newSize)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: newSize)
        draw(in: rect, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0, respectFlipped: false, hints: nil)
        image.unlockFocus()
        return image
    }

    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

let generator = IconGenerator()
do {
    try generator.run()
    guard FileManager.default.fileExists(atPath: generator.iconsetURL.path) else {
        throw NSError(domain: "IconGenerator", code: 5, userInfo: [NSLocalizedDescriptionKey: "Iconset generation failed"])
    }
    let iconsetPath = generator.iconsetURL.path
    let icnsOutput = generator.projectRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("CaveOfNationsApp")
        .appendingPathComponent("Resources")
        .appendingPathComponent("AppIcon.icns")
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["iconutil", "-c", "icns", iconsetPath, "-o", icnsOutput.path]
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        print("Rendered icon to \(icnsOutput.path)")
    } else {
        print("iconutil failed with status \(task.terminationStatus)")
    }
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
