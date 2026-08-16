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
    private let toast = ToastWindow()

    private let exceptions: ExceptionsStore
    /// Второй список: слова, которые надо переключать всегда (короткие вроде «рш» → «hi»).
    private let alwaysSwitch: ExceptionsStore
    private let detector: Detector
    private let undo = UndoManagerLite()
    /// Серия нажатий хоткея по одному слову: 3 подряд → слово в исключения.
    private let streak = FlipStreak(threshold: 3)

    private var isEnabled = true
    private var accessibilityRetryTimer: Timer?

    /// Что сейчас лежит на экране (слово + хвост) — для хоткея ⌃⌥U.
    private let tracker = ScreenWordTracker()

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
        let always = ExceptionsStore(fileURL: ExceptionsStore.defaultFileURL(named: "autoswitch.txt"))
        self.exceptions = store
        self.alwaysSwitch = always
        self.detector = Detector(spell: spell, exceptions: store, alwaysSwitch: always)
    }

    func start() {
        requestAccessibilityIfNeeded()
        setupMenu()

        tap.onKeyDown = { [weak self] event in self?.handleKeyDown(event) }
        tap.onReset = { [weak self] in
            self?.buffer.reset()
            self?.tracker.reset()
        }

        // ⌘Tab/Dock: смена активного приложения не проходит через тап (⌘-события
        // отфильтрованы), поэтому слушаем NSWorkspace — иначе недопечатанное слово
        // «переезжает» в другое приложение и хоткей бьёт по чужому полю.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.buffer.reset()
            self?.tracker.reset()
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
        menu.onToggle = { [weak self] enabled in
            self?.isEnabled = enabled
            self?.streak.reset()   // пауза обрывает серию: контекст всё равно потерян
        }
        menu.onQuit = { NSApp.terminate(nil) }
        // Оба файла можно править руками — перечитываем при каждом открытии меню,
        // чтобы удалённое слово переставало действовать без перезапуска приложения.
        menu.onMenuWillOpen = { [weak self] in
            self?.exceptions.reload()
            self?.alwaysSwitch.reload()
        }
        menu.onOpenExceptions = { [weak self] in
            guard let url = self?.exceptions.ensureFileExists() else { return }
            NSWorkspace.shared.open(url)
        }
        menu.onOpenAutoSwitch = { [weak self] in
            guard let url = self?.alwaysSwitch.ensureFileExists() else { return }
            NSWorkspace.shared.open(url)
        }
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
            tracker.reset()   // курсор ушёл — форсить старое слово небезопасно
            return
        }
        if keycode == Self.deleteKey {
            if buffer.isEmpty {
                tracker.backspace()   // стирают уже завершённое слово/его хвост
            } else {
                buffer.backspace()
            }
            return
        }
        // Enter/Tab — завершают слово без авто-замены (см. flushKeys).
        if Self.flushKeys.contains(keycode) {
            buffer.reset()
            tracker.reset()
            return
        }

        let produced = producedString(from: event)
        let isSeparator = keycode == Self.spaceKey || produced == " "

        if isSeparator {
            if let word = buffer.commit() {
                process(word: word, separator: " ")
            } else {
                tracker.appendSeparator(" ")   // лишний пробел после слова — хвост растёт
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
            tracker.set(text: word, separator: separator, fromAutoSwitch: false)
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
        // Серия «нажал хоткей по этому слову» начинается только с реальной автозамены.
        streak.autoSwitched(typed: word, converted: replacement)
        undo.record(Replacement(
            original: word,
            replacement: replacement,
            previousLayout: previousLayout,
            insertedText: insertedText,
            typedText: typedText
        ))
        tracker.set(text: replacement, separator: separator, fromAutoSwitch: true)
    }

    /// Хоткей ⌃⌥U: перекинуть последнее слово в другую раскладку.
    /// Работает и когда авто НЕ сработало (ручной форс), и когда сработало не так (откат).
    private func flipLastWord() {
        // 1) Слово ещё печатается (разделителя не было) — перекидываем текущее.
        if !buffer.isEmpty {
            let w = buffer.current
            buffer.reset()
            handleFlip(text: w, separator: "", canAutoUndo: false)
            return
        }
        // 2) Последнее завершённое слово (с учётом лишних пробелов/backspace).
        guard let st = tracker.state else { return }

        // Нетронутая авто-замена откатывается «как было». Если после замены были правки
        // (edited), записанный откат уже не совпадает с экраном — переворачиваем то,
        // что реально на экране.
        handleFlip(text: st.text, separator: st.separator,
                   canAutoUndo: st.fromAutoSwitch && !st.edited && undo.canRevert)
    }

    /// Одно нажатие хоткея: сначала учёт серии, потом собственно переворот.
    ///
    /// Серия считает ЛЮБЫЕ нажатия по одному слову, поэтому третье нажатие подряд
    /// (откат → форс → форс) добавляет слово в исключения. К этому моменту на экране
    /// уже должна стоять исходная набранная форма — если вдруг нет (например, в серию
    /// затесалось нажатие по правленому слову), доворачиваем принудительно.
    private func handleFlip(text: String, separator: String, canAutoUndo: Bool) {
        let deleteCount = text.count + separator.count

        switch streak.press(on: text) {
        case .counted:
            break

        case let .learnException(typedForm):
            // Автозамена портила это слово — запрещаем её для него.
            alwaysSwitch.remove(typedForm)
            exceptions.add(typedForm)
            announce(menuLine: "Исключение: \(typedForm)",
                     toastLine: "✓ «\(typedForm)» — больше не трогаю")
            undo.reset()
            // На экране должна остаться исходная набранная форма.
            settle(to: typedForm, text: text, separator: separator, deleteCount: deleteCount)
            return

        case let .learnAutoSwitch(typedForm):
            // Автозамена молчала (слишком короткое слово и т.п.), а переключать надо.
            // Учим только если слово провалилось именно по длине — иначе тремя случайными
            // нажатиями можно научить приложение ломать настоящее слово.
            let flipped = LayoutMapper.flipped(typedForm)
            if detector.wouldSwitchIgnoringLength(typedForm) {
                exceptions.remove(typedForm)
                alwaysSwitch.add(typedForm)
                announce(menuLine: "Автозамена: \(typedForm) → \(flipped)",
                         toastLine: "✓ «\(typedForm)» → «\(flipped)» — теперь переключаю сам")
            }
            undo.reset()
            // Здесь нужная форма — перевёрнутая: пользователь именно её и добивался.
            settle(to: flipped, text: text, separator: separator, deleteCount: deleteCount)
            return
        }

        if canAutoUndo {
            performAutoUndo()
            return
        }
        forceFlip(text: text, separator: separator, deleteCount: deleteCount)
    }

    /// Довести экран до нужной формы слова: если она уже там — не трогаем текст вовсе.
    private func settle(to wanted: String, text: String, separator: String, deleteCount: Int) {
        guard text.lowercased() != wanted.lowercased() else { return }
        forceFlip(text: text, separator: separator, deleteCount: deleteCount)
    }

    private func announce(menuLine: String, toastLine: String) {
        menu.noteLearned(menuLine)
        // Иконка в углу экрана незаметна ровно тогда, когда нужна: пользователь
        // смотрит в поле ввода. Плашка всплывает у курсора, там же, где взгляд.
        toast.show(toastLine)
    }

    /// Безусловно перекинуть слово в другую раскладку (без словаря).
    private func forceFlip(text: String, separator: String, deleteCount: Int) {
        let flipped = LayoutMapper.flipped(text)
        replacer.replace(deleteCount: deleteCount, insert: flipped + separator)
        let target: LayoutMapper.Layout =
            LayoutMapper.script(of: flipped) == .russian ? .russian : .english
        switcher.select(target)
        tracker.set(text: flipped, separator: separator, fromAutoSwitch: false)
    }

    /// Откат авто-замены: возвращаем ровно то, что было напечатано, и прежнюю раскладку.
    private func performAutoUndo() {
        guard let r = undo.revert() else { return }
        replacer.replace(deleteCount: r.insertedText.count, insert: r.typedText)
        switcher.select(r.previousLayout)
        buffer.reset()

        let sep = String(r.typedText.dropFirst(r.original.count))
        tracker.set(text: r.original, separator: sep, fromAutoSwitch: false)
    }

    // MARK: - Accessibility

    private func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
