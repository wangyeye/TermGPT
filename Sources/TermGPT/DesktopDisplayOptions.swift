import SwiftUI

struct DesktopDisplayOptions: View {
    @Binding var bookmark: Bookmark
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("显示模式")).font(.headline)
            Picker(L("显示模式"), selection: Binding<DesktopDisplayMode>(get: { bookmark.desktopDisplayMode ?? .fit }, set: { bookmark.desktopDisplayMode = $0 })) {
                ForEach(DesktopDisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden()
            if bookmark.desktopDisplayMode == .fixed {
                Text(L("固定分辨率")).font(.headline)
                Picker(L("固定分辨率"), selection: Binding<DesktopFixedResolution>(get: { bookmark.desktopFixedResolution ?? .fullHD }, set: { bookmark.desktopFixedResolution = $0 })) {
                    ForEach(DesktopFixedResolution.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
            }
            Text(L("Retina 高清按屏幕像素倍率请求分辨率。RDP 同时请求界面缩放；VNC 的界面缩放需在远端设置。远端不支持调整时按原分辨率缩放显示。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
