import Testing
@testable import PuntoCore

@Suite struct FlipStreakTests {

    // MARK: - Серия после автозамены → исключение

    /// Три нажатия подряд по слову, которое испортила автозамена → слово в исключения,
    /// в ИСХОДНОЙ форме. Текст на экране между нажатиями чередуется, серия узнаёт обе формы.
    @Test func threePressesAfterAutoSwitchLearnException() {
        let s = FlipStreak(threshold: 3)
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        #expect(s.press(on: "привет") == .counted(1))   // откат автозамены
        #expect(s.press(on: "ghbdtn") == .counted(2))   // force-flip обратно
        #expect(s.press(on: "привет") == .learnException("ghbdtn"))
    }

    /// После порога серия обнуляется — следующее нажатие начинает новую (уже ручную).
    @Test func seriesResetsAfterLearn() {
        let s = FlipStreak(threshold: 3)
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        _ = s.press(on: "привет")
        _ = s.press(on: "ghbdtn")
        #expect(s.press(on: "привет") == .learnException("ghbdtn"))
        #expect(s.press(on: "ghbdtn") == .counted(1))
    }

    /// Автозамена ДРУГОГО слова начинает серию заново.
    @Test func otherAutoSwitchResetsSeries() {
        let s = FlipStreak(threshold: 3)
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        _ = s.press(on: "привет")                        // 1
        s.autoSwitched(typed: "cjxb", converted: "сочи") // другое слово
        #expect(s.press(on: "сочи") == .counted(1))
    }

    /// Хоткей по ДРУГОМУ слову рвёт серию и начинает новую с этого слова.
    @Test func pressOnOtherWordStartsNewSeries() {
        let s = FlipStreak(threshold: 3)
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        #expect(s.press(on: "привет") == .counted(1))
        #expect(s.press(on: "чужое") == .counted(1))     // серия по «привет» оборвана
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        #expect(s.press(on: "привет") == .counted(1))    // счёт начат заново
    }

    /// Серия переживает перепечатывание того же слова: Enter/клик/смена приложения
    /// её не трогают, а повторная автозамена того же слова продолжает счёт.
    @Test func retypingSameWordKeepsStreak() {
        let s = FlipStreak(threshold: 3)
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        #expect(s.press(on: "привет") == .counted(1))
        s.autoSwitched(typed: "ghbdtn", converted: "привет")   // напечатал заново
        #expect(s.press(on: "привет") == .counted(2))
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        #expect(s.press(on: "привет") == .learnException("ghbdtn"))
    }

    /// Регистр не важен ни для узнавания слова, ни для порога.
    @Test func caseInsensitive() {
        let s = FlipStreak(threshold: 3)
        s.autoSwitched(typed: "Ghbdtn", converted: "Привет")
        #expect(s.press(on: "ПРИВЕТ") == .counted(1))
        #expect(s.press(on: "ghbdtn") == .counted(2))
        #expect(s.press(on: "Привет") == .learnException("Ghbdtn"))
    }

    // MARK: - Ручная серия → автозамена

    /// Слово, которое автозамена не трогала (напр. «рш» короче порога длины):
    /// три нажатия → слово уходит в список «всегда переключать», в набранной форме.
    @Test func threePressesWithoutAutoSwitchLearnAutoSwitch() {
        let s = FlipStreak(threshold: 3)
        #expect(s.press(on: "рш") == .counted(1))   // на экране стало «hi»
        #expect(s.press(on: "hi") == .counted(2))   // вернулось «рш»
        #expect(s.press(on: "рш") == .learnAutoSwitch("рш"))
    }

    /// Ручная серия тоже узнаёт обе формы и не путается с чужим словом.
    @Test func manualSeriesTracksBothForms() {
        let s = FlipStreak(threshold: 3)
        #expect(s.press(on: "рш") == .counted(1))
        #expect(s.press(on: "другое") == .counted(1))  // серия по «рш» оборвана
        #expect(s.press(on: "hi") == .counted(1))      // и это уже новая серия
    }

    /// Если после ручного нажатия сработала автозамена того же слова — серия
    /// становится «отменой автозамены»: дальше учим исключение, а не автозамену.
    @Test func autoSwitchTakesOverManualSeries() {
        let s = FlipStreak(threshold: 3)
        #expect(s.press(on: "ghbdtn") == .counted(1))
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        #expect(s.press(on: "привет") == .counted(2))
        #expect(s.press(on: "ghbdtn") == .learnException("ghbdtn"))
    }

    // MARK: - Общее

    /// Порог настраивается.
    @Test func customThreshold() {
        let s = FlipStreak(threshold: 6)
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        for i in 1...5 {
            #expect(s.press(on: i.isMultiple(of: 2) ? "ghbdtn" : "привет") == .counted(i))
        }
        #expect(s.press(on: "ghbdtn") == .learnException("ghbdtn"))
    }

    /// Явный сброс (напр. авто-режим выключили) убивает серию.
    @Test func resetClearsSeries() {
        let s = FlipStreak(threshold: 3)
        s.autoSwitched(typed: "ghbdtn", converted: "привет")
        _ = s.press(on: "привет")
        s.reset()
        #expect(s.press(on: "привет") == .counted(1))
    }
}
