import SwiftUI
import AppKit

/// 半透明系统材质背景。用 NSVisualEffectView（behindWindow 模糊），
/// 在 macOS 26 上会自动呈现系统的液态玻璃外观。
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var makeWindowTransparent: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        guard makeWindowTransparent else { return }
        // 让窗口透明，才能透出桌面形成"玻璃"效果
        DispatchQueue.main.async {
            if let w = v.window {
                w.isOpaque = false
                w.backgroundColor = .clear
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.titlebarSeparatorStyle = .none
                w.isMovableByWindowBackground = true   // 标题栏隐藏后，可从空白处拖动窗口
            }
        }
    }
}

/// 根据系统版本切换背景：
/// - macOS 26+：半透明液态玻璃材质
/// - 更早版本：保持原来的纯色窗口背景
struct AppBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            VisualEffectView(material: .underWindowBackground,
                             blending: .behindWindow,
                             makeWindowTransparent: true)
                .ignoresSafeArea()
        } else {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
    }
}
