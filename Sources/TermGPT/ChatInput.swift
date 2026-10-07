import AppKit
import SwiftUI
final class ChatTextView: NSTextView {
    var onSubmit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText() {
            if event.modifierFlags.contains(.option) { insertNewline(nil) }
            else { onSubmit?() }
            return
        }
        super.keyDown(with: event)
    }
}
struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        init(_ parent: ChatInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let view = ChatTextView()
        view.isRichText = false
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textContainerInset = NSSize(width: 6, height: 6)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.setAccessibilityLabel("聊天输入，Enter 发送，Option Enter 换行")
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? ChatTextView else { return }
        scroll.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.backgroundColor = .textBackgroundColor
        view.textColor = .textColor
        view.insertionPointColor = .textColor
        view.onSubmit = onSubmit
        if view.string != text && !view.hasMarkedText() { view.string = text }
    }
}
