import AppKit

/// Иконка и меню в строке состояния.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleItem = NSMenuItem(title: "Авто-режим", action: #selector(toggle), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// Строка «Исключение: …» — видна только после того, как слово реально добавили.
    private let exceptionLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    /// Пока идёт флеш «Пу✓», обычный заголовок не перерисовываем.
    private var flashTimer: Timer?

    var isEnabled = true { didSet { updateUI() } }
    var onToggle: ((Bool) -> Void)?
    var onQuit: (() -> Void)?
    /// Пункт «Открыть список исключений».
    var onOpenExceptions: (() -> Void)?
    /// Пункт «Открыть список автозамен».
    var onOpenAutoSwitch: (() -> Void)?
    /// Меню вот-вот откроется — повод перечитать список с диска.
    var onMenuWillOpen: (() -> Void)?

    /// Предупреждение (напр. отсутствует русский словарь). nil → всё ок.
    var warning: String? { didSet { updateUI() } }

    func install() {
        let menu = NSMenu()
        menu.delegate = self

        toggleItem.target = self
        menu.addItem(toggleItem)

        statusLine.isEnabled = false
        menu.addItem(statusLine)

        exceptionLine.isEnabled = false
        exceptionLine.isHidden = true
        menu.addItem(exceptionLine)

        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Отмена замены: ⌃⌥U", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        let hintLearn = NSMenuItem(title: "3 нажатия подряд → слово запоминается",
                                   action: nil, keyEquivalent: "")
        hintLearn.isEnabled = false
        menu.addItem(hintLearn)

        let openExceptions = NSMenuItem(title: "Список исключений (не трогать)…",
                                        action: #selector(openExceptions), keyEquivalent: "")
        openExceptions.target = self
        menu.addItem(openExceptions)

        let openAutoSwitch = NSMenuItem(title: "Список автозамен (всегда переключать)…",
                                        action: #selector(openAutoSwitch), keyEquivalent: "")
        openAutoSwitch.target = self
        menu.addItem(openAutoSwitch)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateUI()
    }

    /// Слово выучено (в исключения или в автозамену): «Пу» → «Пу✓» на пару секунд +
    /// строка в меню, которая висит до следующего добавления. Без системных уведомлений.
    func noteLearned(_ line: String) {
        exceptionLine.title = line
        exceptionLine.isHidden = false

        statusItem.button?.title = "Пу✓"
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.flashTimer = nil
            self?.updateUI()
        }
    }

    private func updateUI() {
        toggleItem.state = isEnabled ? .on : .off
        if flashTimer == nil {
            statusItem.button?.title = isEnabled ? "Пу" : "Пу⊘"
        }
        statusLine.title = warning.map { "⚠️ \($0)" } ?? (isEnabled ? "Работает" : "Пауза")
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    @objc private func toggle() {
        isEnabled.toggle()
        onToggle?(isEnabled)
    }

    @objc private func openExceptions() {
        onOpenExceptions?()
    }

    @objc private func openAutoSwitch() {
        onOpenAutoSwitch?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
