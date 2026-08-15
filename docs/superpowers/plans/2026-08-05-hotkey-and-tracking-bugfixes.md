# Исправление 4 багов: хоткей-модификаторы, трекинг экрана, ⌘Tab, короткие слова

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Починить 4 бага PuntoSwitcher: (1) хоткей ⌃⌥U не удаляет слово, а дописывает после него; (2) лишние пробелы/backspace после слова ломают подсчёт удаления у хоткея; (3) ⌘Tab не сбрасывает буфер слова; (4) Detector пропускает короткие русские слова с буквами х/ж/э/ъ/б/ю, набранными в EN-раскладке.

**Architecture:** Хрупкая логика «что сейчас лежит на экране» (слово + хвостовые пробелы + backspace'ы) выносится в новый тестируемый тип `ScreenWordTracker` в `PuntoCore`; он заменяет структуру `LastWord` в `AppController`. Системные фиксы точечные: `event.flags = []` на синтетических событиях в `TextReplacer` (синтетический Backspace наследовал зажатые ⌃⌥ и превращался в ⌃⌥⌫, который приложения игнорируют), подписка на `NSWorkspace.didActivateApplicationNotification` для сброса при смене приложения, и перенос проверки минимальной длины в `Detector` с «букв исходника» на «длину слова целиком».

**Tech Stack:** Swift 6 (языковой режим v5), SwiftPM, swift-testing (`@Test` / `#expect`), только системные фреймворки Apple.

## Global Constraints

- `Package.swift` → `dependencies` ДОЛЖЕН оставаться пустым: только системные Apple-фреймворки, никаких сторонних пакетов (инвариант безопасности).
- Event tap остаётся `.listenOnly` — не менять на модифицирующий.
- Никакой записи на диск, кроме существующего `exceptions.txt`.
- macOS 13+, `swift-tools-version:6.0`, `swiftLanguageModes: [.v5]` — не менять.
- Тесты — swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`), как в существующих файлах `Tests/PuntoCoreTests/*.swift`.
- Комментарии в коде — по-русски, в стиле существующих файлов.
- Все команды выполнять из корня проекта (там, где лежит `Package.swift`).

---

### Task 1: `ScreenWordTracker` в PuntoCore

Тип, отслеживающий состояние «на экране» после завершения слова. Чистая логика без системных зависимостей.

**Files:**
- Create: `Sources/PuntoCore/ScreenWordTracker.swift`
- Test: `Tests/PuntoCoreTests/ScreenWordTrackerTests.swift`

**Interfaces:**
- Consumes: ничего (standalone тип).
- Produces (Task 4 полагается на эти сигнатуры):
  - `ScreenWordTracker.state: ScreenWordTracker.State?` (read-only снаружи)
  - `State { var text: String; var separator: String; var fromAutoSwitch: Bool; var edited: Bool }`
  - `func set(text: String, separator: String, fromAutoSwitch: Bool)`
  - `func appendSeparator(_ s: String)`
  - `func backspace()`
  - `func reset()`

- [ ] **Step 1: Написать падающие тесты**

Создать `Tests/PuntoCoreTests/ScreenWordTrackerTests.swift` с содержимым:

```swift
import Testing
@testable import PuntoCore

@Suite struct ScreenWordTrackerTests {

    @Test func setStoresState() {
        let t = ScreenWordTracker()
        t.set(text: "привет", separator: " ", fromAutoSwitch: true)
        #expect(t.state == .init(text: "привет", separator: " ",
                                 fromAutoSwitch: true, edited: false))
    }

    @Test func appendSeparatorGrowsTailAndMarksEdited() {
        let t = ScreenWordTracker()
        t.set(text: "привет", separator: " ", fromAutoSwitch: true)
        t.appendSeparator(" ")
        #expect(t.state?.separator == "  ")
        #expect(t.state?.edited == true)
    }

    @Test func appendSeparatorWithoutStateIsNoop() {
        let t = ScreenWordTracker()
        t.appendSeparator(" ")
        #expect(t.state == nil)
    }

    @Test func backspaceEatsSeparatorFirst() {
        let t = ScreenWordTracker()
        t.set(text: "привет", separator: " ", fromAutoSwitch: false)
        t.backspace()
        #expect(t.state?.text == "привет")
        #expect(t.state?.separator == "")
        #expect(t.state?.edited == true)
    }

    @Test func backspaceEatsWordAfterSeparator() {
        let t = ScreenWordTracker()
        t.set(text: "привет", separator: " ", fromAutoSwitch: false)
        t.backspace()  // съел пробел
        t.backspace()  // съел «т»
        #expect(t.state?.text == "приве")
        #expect(t.state?.separator == "")
    }

    @Test func backspaceToEmptyClearsState() {
        let t = ScreenWordTracker()
        t.set(text: "ab", separator: "", fromAutoSwitch: false)
        t.backspace()
        t.backspace()
        #expect(t.state == nil)
    }

    @Test func backspaceWithoutStateIsNoop() {
        let t = ScreenWordTracker()
        t.backspace()
        #expect(t.state == nil)
    }

    @Test func resetClearsState() {
        let t = ScreenWordTracker()
        t.set(text: "привет", separator: " ", fromAutoSwitch: true)
        t.reset()
        #expect(t.state == nil)
    }

    @Test func setAfterEditsResetsEditedFlag() {
        let t = ScreenWordTracker()
        t.set(text: "раз", separator: " ", fromAutoSwitch: false)
        t.appendSeparator(" ")
        t.set(text: "два", separator: " ", fromAutoSwitch: true)
        #expect(t.state?.edited == false)
    }
}
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `swift test --filter ScreenWordTrackerTests`
Expected: ошибка компиляции «cannot find 'ScreenWordTracker' in scope» — это и есть «падение» на данном шаге.

- [ ] **Step 3: Реализация**

Создать `Sources/PuntoCore/ScreenWordTracker.swift` с содержимым:

```swift
import Foundation

/// Отслеживает, что лежит «на экране» после завершения слова: само слово,
/// хвостовые разделители (пробелы) и правки backspace'ом.
///
/// Нужен хоткею ⌃⌥U: чтобы перевернуть слово, надо удалить РОВНО столько
/// символов, сколько реально есть на экране, — иначе замена портит текст.
/// Живёт только в RAM, как и WordBuffer.
public final class ScreenWordTracker {
    /// Снимок состояния «на экране».
    public struct State: Equatable {
        /// Слово (возможно, уже подрезанное backspace'ами).
        public var text: String
        /// Хвостовые разделители после слова (обычно пробелы).
        public var separator: String
        /// Слово появилось в результате авто-замены.
        public var fromAutoSwitch: Bool
        /// Были ли правки (лишние пробелы/backspace) после фиксации слова.
        /// Пока false — записанный в UndoManagerLite откат совпадает с экраном
        /// и можно идти путём авто-отката; после правок — только force-flip.
        public var edited: Bool
    }

    public private(set) var state: State?

    public init() {}

    /// Зафиксировать новое слово на экране (после коммита или замены).
    public func set(text: String, separator: String, fromAutoSwitch: Bool) {
        state = State(text: text, separator: separator,
                      fromAutoSwitch: fromAutoSwitch, edited: false)
    }

    /// Нажат разделитель (пробел) при пустом буфере — хвост растёт.
    public func appendSeparator(_ s: String) {
        guard state != nil else { return }
        state?.separator += s
        state?.edited = true
    }

    /// Нажат backspace при пустом буфере: сначала укорачивается хвост
    /// разделителей, затем само слово. Слово стёрто целиком → состояние сброшено.
    public func backspace() {
        guard var st = state else { return }
        if !st.separator.isEmpty {
            st.separator.removeLast()
        } else if !st.text.isEmpty {
            st.text.removeLast()
        }
        st.edited = true
        state = st.text.isEmpty ? nil : st
    }

    /// Полный сброс (навигация, клик, смена приложения, Enter/Tab).
    public func reset() { state = nil }
}
```

- [ ] **Step 4: Тесты зелёные**

Run: `swift test --filter ScreenWordTrackerTests`
Expected: 9 tests PASS.

- [ ] **Step 5: Все тесты зелёные**

Run: `swift test`
Expected: все тесты PASS (было 33, стало 42).

- [ ] **Step 6: Commit**

```bash
git add Sources/PuntoCore/ScreenWordTracker.swift Tests/PuntoCoreTests/ScreenWordTrackerTests.swift
git commit -m "feat(core): ScreenWordTracker — трекинг слова и хвоста на экране"
```

---

### Task 2: Detector — не пропускать короткие слова с буквами на пунктуационных клавишах

Баг: `minLength` считается по буквам ИСХОДНИКА. «это» в EN-раскладке — `'nj`: апостроф не буква, буквенных символов 2 < 3 → слово не проверяется вовсе. Та же судьба у «жук» (`;er`), «эти» (`'nb`). Фикс: считать длину по всем символам слова — конвертация посимвольная 1:1, а фильтр `isAllLetters(converted)` ниже уже гарантирует, что каждый символ станет буквой.

**Files:**
- Modify: `Sources/PuntoCore/Detector.swift` (строки 32-36)
- Test: `Tests/PuntoCoreTests/DetectorTests.swift`

**Interfaces:**
- Consumes: `LayoutMapper`, `SpellChecking`, `ExceptionsStore` (без изменений).
- Produces: сигнатура `Detector.decide(_:) -> Decision` НЕ меняется.

- [ ] **Step 1: Написать падающие тесты**

В `Tests/PuntoCoreTests/DetectorTests.swift` добавить внутрь `@Suite struct DetectorTests` (после теста `wordWithBracketLetterKeyIsSwitched`):

```swift
    @Test func shortWordWithApostropheKeyIsSwitched() {
        // «это» в EN-раскладке — "'nj" (апостроф = э). Букв в сыром виде 2,
        // но слово трёхсимвольное и должно проверяться.
        let d = makeDetector(ru: ["это"], en: [])
        #expect(d.decide("'nj") == .switchLayout(replacement: "это", target: .russian))
    }

    @Test func shortWordWithSemicolonKeyIsSwitched() {
        // «жук» — ";er" (точка с запятой = ж).
        let d = makeDetector(ru: ["жук"], en: [])
        #expect(d.decide(";er") == .switchLayout(replacement: "жук", target: .russian))
    }
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `swift test --filter DetectorTests`
Expected: два новых теста FAIL (`decide` возвращает `.leave`), остальные PASS.

- [ ] **Step 3: Фикс**

В `Sources/PuntoCore/Detector.swift` заменить:

```swift
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Считаем буквы в исходнике: слово в неправильной раскладке может содержать
        // пунктуационные клавиши ([ ] ; ' — это буквы х ъ ж э в русской раскладке),
        // поэтому «только буквы» проверяем не здесь, а на СКОНВЕРТИРОВАННОМ результате.
        let letterCount = word.filter { $0.isLetter }.count
        guard letterCount >= minLength else { return .leave }
```

на:

```swift
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Длину меряем по ВСЕМ символам, а не по буквам исходника: слово в неправильной
        // раскладке может содержать пунктуационные клавиши ([ ] ; ' — это буквы х ъ ж э
        // в русской раскладке), из-за подсчёта «только букв» короткие слова вроде
        // «это» ('nj) вообще не проверялись. Конвертация посимвольная 1:1, и фильтр
        // isAllLetters(converted) ниже гарантирует, что каждый символ станет буквой.
        guard word.count >= minLength else { return .leave }
```

- [ ] **Step 4: Тесты зелёные**

Run: `swift test`
Expected: все тесты PASS, включая существующий `tooShortLeftAlone` («yf», 2 символа — по-прежнему `.leave`).

- [ ] **Step 5: Commit**

```bash
git add Sources/PuntoCore/Detector.swift Tests/PuntoCoreTests/DetectorTests.swift
git commit -m "fix(core): Detector не пропускает короткие слова с х/ж/э на пунктуационных клавишах"
```

---

### Task 3: TextReplacer — обнулить модификаторы на синтетических событиях

Корневая причина бага «хоткей дописывает слово вместо замены»: в момент срабатывания ⌃⌥U Control и Option физически зажаты. Источник событий `.combinedSessionState` подмешивает текущие модификаторы сессии в синтетические события — приложение получает ⌃⌥⌫ вместо Backspace и игнорирует удаление, а unicode-вставка проходит (текст берётся из `keyboardSetUnicodeString` напрямую). Итог: слово не удалено, перевёрнутое печатается следом. Авто-замена по пробелу работала, потому что там модификаторы не зажаты.

**Files:**
- Modify: `Sources/PuntoSwitcher/TextReplacer.swift` (методы `postKey`, `postUnicode`)

**Interfaces:**
- Produces: сигнатура `TextReplacer.replace(deleteCount:insert:)` НЕ меняется.

Юнит-тестов нет (системный слой, CGEvent) — проверка ручная в Task 5.

- [ ] **Step 1: Фикс**

В `Sources/PuntoSwitcher/TextReplacer.swift` привести оба метода к виду:

```swift
    private func postKey(_ key: CGKeyCode, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        // В момент срабатывания хоткея ⌃⌥U модификаторы физически зажаты, и событие
        // от .combinedSessionState унаследовало бы их — приложение получило бы ⌃⌥⌫
        // вместо Backspace и проигнорировало бы удаление. Флаги обнуляем явно.
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticMarker.value)
        event.post(tap: .cgSessionEventTap)
    }

    private func postUnicode(_ string: String) {
        var units = Array(string.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            // Те же зажатые ⌃⌥, что и в postKey: без чистки флагов вставка может
            // трактоваться приложением как шорткат.
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticMarker.value)
            event.post(tap: .cgSessionEventTap)
        }
    }
```

(Единственное изменение в каждом методе — добавленная строка `event.flags = []` с комментарием; остальное не трогать.)

- [ ] **Step 2: Сборка проходит**

Run: `swift build`
Expected: Build complete, без warning'ов в изменённом файле.

- [ ] **Step 3: Commit**

```bash
git add Sources/PuntoSwitcher/TextReplacer.swift
git commit -m "fix: синтетические события не наследуют зажатые ⌃⌥ (хоткей не удалял слово)"
```

---

### Task 4: AppController — интеграция ScreenWordTracker + сброс по смене приложения

Заменяет `LastWord` на `ScreenWordTracker` (чинит рассинхрон при двойном пробеле/backspace) и добавляет сброс буфера при переключении приложения через ⌘Tab/Dock (клик мышью уже сбрасывал).

**Files:**
- Modify: `Sources/PuntoSwitcher/AppController.swift`

**Interfaces:**
- Consumes (из Task 1): `ScreenWordTracker` — `state`, `set(text:separator:fromAutoSwitch:)`, `appendSeparator(_:)`, `backspace()`, `reset()`.
- Produces: публичный интерфейс `AppController` (`init`, `start()`) НЕ меняется.

- [ ] **Step 1: Заменить хранение lastWord на tracker**

Удалить свойство `lastWord` и структуру `LastWord` (строки 23-29):

```swift
    /// Последнее слово «на экране» — для ручного форса по хоткею.
    private var lastWord: LastWord?
    private struct LastWord {
        var text: String          // что сейчас на экране
        var separator: String     // хвостовой разделитель на экране ("" если слово ещё печатается)
        var fromAutoSwitch: Bool  // получено авто-заменой (тогда форс = откат с обучением)
    }
```

и на их месте объявить:

```swift
    /// Что сейчас лежит на экране (слово + хвост) — для хоткея ⌃⌥U.
    private let tracker = ScreenWordTracker()
```

- [ ] **Step 2: Обновить start() — сброс через tracker и подписка на смену приложения**

Привести `start()` к виду:

```swift
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
```

- [ ] **Step 3: Обновить handleKeyDown**

В `handleKeyDown` заменить блок обработки клавиш (от `if Self.navigationKeys.contains(keycode)` до конца обработки разделителя) так:

```swift
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
```

Остальная часть метода (накопление в буфер) — без изменений.

- [ ] **Step 4: Обновить process / performSwitch / flipLastWord / forceFlip / performAutoUndo**

Привести пять методов к виду (замены `lastWord = ...` → `tracker.set(...)` и новая логика хоткея):

```swift
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
            forceFlip(text: w, separator: "", deleteCount: w.count)
            return
        }
        // 2) Последнее завершённое слово (с учётом лишних пробелов/backspace).
        guard let st = tracker.state else { return }

        // Нетронутая авто-замена — откат с обучением-исключением. Если после замены
        // были правки (edited), записанный откат уже не совпадает с экраном —
        // переворачиваем то, что реально на экране.
        if st.fromAutoSwitch, !st.edited, undo.canRevert {
            performAutoUndo()
            return
        }
        forceFlip(text: st.text, separator: st.separator,
                  deleteCount: st.text.count + st.separator.count)
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

    /// Откат авто-замены + учёт серии откатов (три подряд по одному слову → в исключения).
    private func performAutoUndo() {
        guard let result = undo.revert() else { return }
        let r = result.replacement
        replacer.replace(deleteCount: r.insertedText.count, insert: r.typedText)
        switcher.select(r.previousLayout)
        buffer.reset()

        let sep = String(r.typedText.dropFirst(r.original.count))
        tracker.set(text: r.original, separator: sep, fromAutoSwitch: false)

        if result.shouldAddException {
            exceptions.add(r.original)
        }
    }
```

После правок в файле не должно остаться ни одного упоминания `lastWord` / `LastWord`. Проверить: `grep -n "lastWord\|LastWord" Sources/PuntoSwitcher/AppController.swift` — пусто.

- [ ] **Step 5: Сборка и тесты**

Run: `swift build && swift test`
Expected: Build complete, все тесты PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/PuntoSwitcher/AppController.swift
git commit -m "fix: ScreenWordTracker вместо lastWord + сброс буфера при смене приложения"
```

---

### Task 5: Сборка, деплой и ручная проверка

Рабочий бинарь живёт в `/Applications/PuntoSwitcher.app` и запускается LaunchAgent'ом — правки нужно задеплоить туда (см. память проекта: autostart-setup).

**Files:**
- Никаких изменений кода. Только сборка/деплой/проверка.

- [ ] **Step 1: Пересобрать и задеплоить**

```bash
./build_app.sh
rm -rf /Applications/PuntoSwitcher.app
cp -R dist/PuntoSwitcher.app /Applications/
launchctl bootout gui/$(id -u)/com.georgi.puntoswitcher
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.georgi.puntoswitcher.plist
```

Подпись стабильным сертификатом (`PuntoSwitcher Local Signing`) сохраняет разрешение Accessibility. Если build_app.sh напишет «Сертификат не найден — ad-hoc подпись», после деплоя надо заново выдать Accessibility в System Settings.

- [ ] **Step 2: Ручная проверка (чек-лист для Георгия)**

Открыть TextEdit или Заметки и проверить:

1. **Главный баг (хоткей):** набрать `ghbdtn`, пробел → авто-замена на `привет `. Сразу нажать ⌃⌥U → на экране должно стать `ghbdtn ` (раньше становилось `привет ghbdtn `). Держать ⌃⌥ зажатыми в момент нажатия — это и есть проверяемый сценарий.
2. **Двойной пробел:** `ghbdtn`, пробел, ещё пробел → ⌃⌥U → `ghbdtn  ` (два пробела сохранены, текст не порчен).
3. **Backspace после слова:** `ghbdtn`, пробел, backspace → ⌃⌥U → `ghbdtn` (без пробела).
4. **⌘Tab:** набрать полслова в TextEdit, ⌘Tab в другое приложение, набрать там слово с пробелом — слово обрабатывается с чистого листа (обрывок из TextEdit не приклеивается).
5. **Короткие слова:** в EN-раскладке набрать `'nj` и пробел → должно замениться на `это ` (слово «это» есть в системном словаре).
6. **Регресс:** обычная авто-замена (`ghbdtn` + пробел → `привет `), форс не-заменённого слова (`hello` + пробел, ⌃⌥U → `руддщ `), обучение исключениям (3 отката подряд одного слова) — работают как раньше.
