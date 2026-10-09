import Foundation

/// Logical view points keep remote text readable on Retina displays.
struct DesktopResolution: Equatable {
    let width: Int
    let height: Int
    init?(size: NSSize) {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { return nil }
        let scale = min(1, 4096 / size.width, 2160 / size.height)
        width = max(200, Int(size.width * scale) / 2 * 2)
        height = max(200, Int(size.height * scale))
    }
}
