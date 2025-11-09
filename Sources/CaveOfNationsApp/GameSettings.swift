import Foundation
import CoreGraphics
import Combine

final class GameSettings: ObservableObject {
    struct Dimensions {
        var width: Int
        var height: Int
        var depth: Int
    }

    enum Resolution: String, CaseIterable, Identifiable {
        case hd720 = "1280x720"
        case hd1080 = "1920x1080"
        case qhd = "2560x1440"
        case uhd = "3840x2160"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .hd720: return "1280 × 720 (HD)"
            case .hd1080: return "1920 × 1080 (Full HD)"
            case .qhd: return "2560 × 1440 (QHD)"
            case .uhd: return "3840 × 2160 (4K UHD)"
            }
        }

        var size: CGSize {
            switch self {
            case .hd720: return CGSize(width: 1280, height: 720)
            case .hd1080: return CGSize(width: 1920, height: 1080)
            case .qhd: return CGSize(width: 2560, height: 1440)
            case .uhd: return CGSize(width: 3840, height: 2160)
            }
        }
    }

    @Published var dimensions: Dimensions
    @Published var musicVolume: Double
    @Published var effectsVolume: Double
    @Published var resolution: Resolution
    @Published var isFullscreen: Bool
    @Published var showLoadingScreen: Bool
    @Published var loadingDuration: TimeInterval

    let resetPublisher = PassthroughSubject<Void, Never>()

    init(dimensions: Dimensions = .init(width: 16, height: 12, depth: 16),
         musicVolume: Double = 0.7,
         effectsVolume: Double = 0.8,
         resolution: Resolution = .hd1080,
         isFullscreen: Bool = false,
         showLoadingScreen: Bool = true,
         loadingDuration: TimeInterval = 2.5) {
        self.dimensions = Dimensions(
            width: max(8, dimensions.width),
            height: max(6, dimensions.height),
            depth: max(8, dimensions.depth)
        )
        self.musicVolume = min(max(musicVolume, 0), 1)
        self.effectsVolume = min(max(effectsVolume, 0), 1)
        self.resolution = resolution
        self.isFullscreen = isFullscreen
        self.showLoadingScreen = showLoadingScreen
        self.loadingDuration = loadingDuration
    }

    func requestReset() {
        resetPublisher.send()
    }
}
