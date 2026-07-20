import AppKit
import ApplicationServices
import CoreGraphics
import PuntoCore

/// Связывает все модули и обрабатывает поток клавиатурных событий.
final class AppController {
    private let tap = EventTapController()
    private let buffer = WordBuffer()
    private let switcher = InputSourceSwitcher()
    private let replacer = TextReplacer()
    private let hotkey = HotkeyController()
    private let menu = MenuBarController()
    private let spell = SystemSpellChecker()

    private let exceptions: ExceptionsStore
    private let detector: Detector
    private let undo = UndoManagerLite()

    private var isEnabled = true
    private var accessibilityRetryTimer: Timer?

    /// Последнее слово «на экране» — для ручного форса по хоткею.
    private var lastWord: LastWord?
    private struct LastWord {
        var text: String          // что сейчас на экране
        var separator: String     // хвостовой разделитель на экране ("" если слово ещё печатается)
        var fromAutoSwitch: Bool  // получено авто-заменой (тогда форс = откат с обучением)
    }

    // Пробел — единственный разделитель, ТРИГГЕРЯЩИЙ авто-замену.
    private static let spaceKey: Int64 = 49
    // Enter/Tab завершают слово, но замену НЕ триггерят: тап .listenOnly не может
    // перехватить Enter, а в чатах он уже отправил сообщение не в той раскладке —
    // backspace+перепечатка ушли бы в пустое поле. Просто чистим буфер.
    private static let flushKeys: Set<Int64> = [36, 48, 76] // return, tab, enter
    // Клавиши навигации/выхода — сбрасывают буфер.
    private static let navigationKeys: Set<Int64> = [
        123, 124, 125, 126, // стрелки
        115, 119, 116, 121, // home, end, pageUp, pageDown
        53, 117,            // escape, forward-delete
    ]
    private static let deleteKey: Int64 = 51

    init() {
        let store = ExceptionsStore(fileURL: ExceptionsStore.defaultFileURL())
        self.exceptions = store
        self.detector = Detector(spell: spell, exceptions: store)
    }

    func start() {
        requestAccessibilityIfNeeded()
        setupMenu()

        tap.onKeyDown = { [weak self] event in self?.handleKeyDown(event) }
        tap.onReset = { [weak self] in
            self?.buffer.reset()
            self?.lastWord = nil
        }

        hotkey.onTrigger = { [weak self] in self?.flipLastWord() }
        hotkey.register()

        ensureTapRunning()
    }

    /// Поднимает перехват ТОЛЬКО когда реально выдан Accessibility.
    ///
    /// Важно: `.listenOnly`-перехват создаётся успешно и без доступа, но не получает событий,
    /// поэтому судить о готовности по факту создания tap нельзя — проверяем `AXIsProcessTrusted()`.
    /// Пока доступа нет — ждём и повторяем каждые 2с, так что выдача доступа на лету срабатывает
    /// без перезапуска приложения.
    private func ensureTapRunning() {
        guard AXIsProcessTrusted() else {
            menu.warning = "Ожидание доступа Accessibility — включите в System Settings"
            startRetryTimerIfNeeded()
            return
        }

        if tap.start() {
            accessibilityRetryTimer?.invalidate()
            accessibilityRetryTimer = nil
            menu.warning = spell.hasDictionary(for: "ru")
                ? nil
                : "Нет русского словаря — авто-режим RU не сработает"
        } else {
            menu.warning = "Не удалось создать перехват клавиатуры"
            startRetryTimerIfNeeded()
        }
    }

    private func startRetryTimerIfNeeded() {
        guard accessibilityRetryTimer == nil else { return }
        accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.ensureTapRunning()
        }
    }

    // MARK: - Меню

    private func setupMenu() {
        menu.isEnabled = isEnabled
        menu.onToggle = { [weak self] enabled in self?.isEnabled = enabled }
        menu.onQuit = { NSApp.terminate(nil) }
        menu.install()

        if !spell.hasDictionary(for: "ru") {
            menu.warning = "Нет русского словаря — авто-режим RU не сработает"
        }
    }

    // MARK: - Обработка клавиш

    private func handleKeyDown(_ event: CGEvent) {
        guard isEnabled else { return }

        // Шорткаты (⌘/⌃) — это команды, а не ввод текста. Пропускаем БЕЗ изменения
        // буфера: иначе ⌘A/⌘C/⌘Z дописывают букву в слово, а ⌘Space/⌘Tab (keycode
        // пробела/таба) ложно коммитят и запускают авто-замену. Буфер не трогаем,
        // чтобы не сломать хоткей ⌃⌥U (он приходит сюда же как нажатие U с Control).
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        if Self.navigationKeys.contains(keycode) {
            buffer.reset()
            lastWord = nil   // курсор ушёл — форсить старое слово небезопасно
            return
        }
        if keycode == Self.deleteKey {
            buffer.backspace()
            return
        }
        // Enter/Tab — завершают слово без авто-замены (см. flushKeys).
        if Self.flushKeys.contains(keycode) {
            buffer.reset()
            lastWord = nil
            return
        }

        let produced = producedString(from: event)
        let isSeparator = keycode == Self.spaceKey || produced == " "

        if isSeparator {
            if let word = buffer.commit() {
                process(word: word, separator: " ")
            }
            return
        }

        // Обычный печатный символ — копим в буфер.
        if produced.count == 1, let ch = produced.first, !ch.isNewline, !ch.isWhitespace {
            buffer.append(ch)
        } else if produced.isEmpty {
            // модификатор без символа — игнор
        } else {
            buffer.reset()
        }
    }

    private func producedString(from event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: - Замена и откат

    private func process(word: String, separator: String) {
        guard case let .switchLayout(replacement, target) = detector.decide(word) else {
            // Авто ничего не тронуло — запоминаем как есть, чтобы можно было форснуть вручную.
            lastWord = LastWord(text: word, separator: separator, fromAutoSwitch: false)
            return
        }
        performSwitch(word: word, replacement: replacement, target: target, separator: separator)
    }

    private func performSwitch(word: String, replacement: String,
                               target: LayoutMapper.Layout, separator: String) {
        let insertedText = replacement + separator
        let typedText = word + separator

        // Разделитель уже вставлен приложением — удаляем слово + разделитель, печатаем заново.
        replacer.replace(deleteCount: typedText.count, insert: insertedText)
        switcher.select(target)

        let previousLayout: LayoutMapper.Layout = (target == .russian) ? .english : .russian
        undo.record(Replacement(
            original: word,
            replacement: replacement,
            previousLayout: previousLayout,
            insertedText: insertedText,
            typedText: typedText
        ))
        lastWord = LastWord(text: replacement, separator: separator, fromAutoSwitch: true)
    }

    /// Хоткей ⌃⌥U: перекинуть последнее слово в другую раскладку.
    /// Работает и когда авто НЕ сработало (ручной форс), и когда сработало не так (откат).
    private func flipLastWord() {
        // 1) Слово ещё печатается (разделителя не было) — перекидываем текущее.
        if !buffer.isEmpty {
            let w = buffer.current
            buffer.reset()
            forceFlip(text: w, separator: "", deleteCount: w.count)
            return
        }
        // 2) Последнее завершённое слово.
        guard let lw = lastWord else { return }

        // Если это была авто-замена — идём через откат (с обучением-исключением).
        if lw.fromAutoSwitch, undo.canRevert {
            performAutoUndo()
            return
        }
        // Иначе — обычный форс того, что на экране.
        forceFlip(text: lw.text, separator: lw.separator,
                  deleteCount: lw.text.count + lw.separator.count)
    }

    /// Безусловно перекинуть слово в другую раскладку (без словаря).
    private func forceFlip(text: String, separator: String, deleteCount: Int) {
        let flipped = LayoutMapper.flipped(text)
        replacer.replace(deleteCount: deleteCount, insert: flipped + separator)
        let target: LayoutMapper.Layout =
            LayoutMapper.script(of: flipped) == .russian ? .russian : .english
        switcher.select(target)
        lastWord = LastWord(text: flipped, separator: separator, fromAutoSwitch: false)
    }

    /// Откат авто-замены + учёт серии откатов (три подряд по одному слову → в исключения).
    private func performAutoUndo() {
        guard let result = undo.revert() else { return }
        let r = result.replacement
        replacer.replace(deleteCount: r.insertedText.count, insert: r.typedText)
        switcher.select(r.previousLayout)
        buffer.reset()

        let sep = String(r.typedText.dropFirst(r.original.count))
        lastWord = LastWord(text: r.original, separator: sep, fromAutoSwitch: false)

        if result.shouldAddException {
            exceptions.add(r.original)
        }
    }

    // MARK: - Accessibility

    private func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
