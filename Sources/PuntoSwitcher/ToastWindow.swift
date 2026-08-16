import AppKit

/// Короткая плашка у курсора: «слово → в исключения».
///
/// Своё borderless-окно, а не системное уведомление: не нужны разрешения, не нужен
/// бандл-идентификатор в Notification Center и, главное, не крадётся фокус —
/// приложение остаётся `.accessory`, а панель `.nonactivatingPanel`, поэтому набор
/// текста не прерывается. Всплывает рядом с курсором, где и смотрит пользователь,
/// в отличие от иконки в строке меню.
final class ToastWindow {
    private var panel: NSPanel?
    private var hideTimer: Timer?

    private let visibleSeconds: TimeInterval = 1.8

    func show(_ text: String) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        guard let label = panel.contentView?.subviews.compactMap({ $0 as? NSTextField }).first else { return }
        label.stringValue = text
        label.sizeToFit()

        let size = NSSize(width: label.frame.width + 34, height: label.frame.height + 20)
        label.setFrameOrigin(NSPoint(x: 17, y: 10))
        panel.setContentSize(size)
        panel.setFrameOrigin(originNearCursor(for: size))

        hideTimer?.invalidate()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: visibleSeconds, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    // MARK: - Сборка окна

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true            // сквозь плашку можно кликать
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 10
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        blur.addSubview(label)

        panel.contentView = blur
        return panel
    }

    /// Плашка ложится под курсором и не вылезает за край экрана.
    private func originNearCursor(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var x = mouse.x + 14
        var y = mouse.y - size.height - 14

        if let frame = screen?.visibleFrame {
            x = min(max(frame.minX + 8, x), frame.maxX - size.width - 8)
            y = min(max(frame.minY + 8, y), frame.maxY - size.height - 8)
        }
        return NSPoint(x: x, y: y)
    }
}
