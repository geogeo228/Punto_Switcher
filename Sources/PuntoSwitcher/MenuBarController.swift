import AppKit

/// Иконка и меню в строке состояния.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleItem = NSMenuItem(title: "Авто-режим", action: #selector(toggle), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    var isEnabled = true { didSet { updateUI() } }
    var onToggle: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    /// Предупреждение (напр. отсутствует русский словарь). nil → всё ок.
    var warning: String? { didSet { updateUI() } }

    func install() {
        statusItem.button?.title = "Пу"
        let menu = NSMenu()

        toggleItem.target = self
        menu.addItem(toggleItem)

        statusLine.isEnabled = false
        menu.addItem(statusLine)

        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Отмена замены: ⌃⌥U", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateUI()
    }

    private func updateUI() {
        toggleItem.state = isEnabled ? .on : .off
        statusItem.button?.title = isEnabled ? "Пу" : "Пу⊘"
        if let warning {
            statusLine.title = "⚠️ \(warning)"
            statusLine.isHidden = false
        } else {
            statusLine.title = "Работает"
            statusLine.isHidden = false
        }
    }

    @objc private func toggle() {
        isEnabled.toggle()
        onToggle?(isEnabled)
    }

    @objc private func quit() {
        onQuit?()
    }
}
