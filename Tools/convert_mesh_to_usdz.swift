import Foundation
import ModelIO

func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3 else {
        fputs("Usage: convert_mesh_to_usdz <input mesh> <output usdz>\n", stderr)
        exit(1)
    }

    let inputURL = URL(fileURLWithPath: arguments[1])
    let outputURL = URL(fileURLWithPath: arguments[2])

    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        fputs("Input file not found: \(inputURL.path)\n", stderr)
        exit(1)
    }

    let asset = MDLAsset(url: inputURL)
    guard asset.count > 0 else {
        fputs("Failed to load mesh asset or asset is empty.\n", stderr)
        exit(1)
    }

    if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
    }

    do {
        try asset.export(to: outputURL)
    } catch {
        fputs("ModelIO export failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    print("Converted \(inputURL.lastPathComponent) -> \(outputURL.lastPathComponent)")
}

try main()
