import Foundation

enum DesktopDisplayMode: String, Codable, CaseIterable {
    case fit, retina, fixed
    var title: String { switch self { case .fit: return L("适应窗口"); case .retina: return L("Retina 高清"); case .fixed: return L("固定分辨率") } }
}
enum DesktopFixedResolution: String, Codable, CaseIterable {
    case hd = "1280 × 720", fullHD = "1920 × 1080", qhd = "2560 × 1440", uhd = "3840 × 2160"
    var size: NSSize { switch self { case .hd: return NSSize(width: 1280, height: 720); case .fullHD: return NSSize(width: 1920, height: 1080); case .qhd: return NSSize(width: 2560, height: 1440); case .uhd: return NSSize(width: 3840, height: 2160) } }
}
/// Remote pixels and RDP desktop scaling, bounded by the bridge framebuffer limits.
struct DesktopResolution: Equatable {
    let width: Int
    let height: Int
    let desktopScale: Int
    init?(size: NSSize, mode: DesktopDisplayMode = .fit, backingScale: CGFloat = 1, fixed: DesktopFixedResolution = .fullHD) {
        let size = mode == .fixed ? fixed.size : size
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { return nil }
        let density = mode == .retina && backingScale.isFinite ? max(1, min(5, backingScale)) : 1
        let scale = min(density, 4096 / size.width, 2160 / size.height)
        width = max(200, Int(size.width * scale) / 2 * 2)
        height = max(200, Int(size.height * scale))
        desktopScale = max(100, min(500, Int(scale * 100)))
    }
}
