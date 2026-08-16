import Testing
@testable import PuntoCore

/// Фейковый спелл-чекер: реальными словами считаются только переданные в множествах.
private struct FakeSpell: SpellChecking {
    var ru: Set<String> = []
    var en: Set<String> = []
    func isRealWord(_ word: String, language: String) -> Bool {
        let w = word.lowercased()
        return language == "ru" ? ru.contains(w) : en.contains(w)
    }
}

@Suite struct DetectorTests {

    private func makeDetector(ru: Set<String>, en: Set<String>,
                              exceptions: [String] = []) -> Detector {
        let store = ExceptionsStore(fileURL: nil)
        exceptions.forEach { store.add($0) }
        return Detector(spell: FakeSpell(ru: ru, en: en), exceptions: store)
    }

    private func makeDetector(ru: Set<String>, en: Set<String>,
                              exceptions: [String], alwaysSwitch: [String]) -> Detector {
        let exc = ExceptionsStore(fileURL: nil)
        exceptions.forEach { exc.add($0) }
        let always = ExceptionsStore(fileURL: nil)
        alwaysSwitch.forEach { always.add($0) }
        return Detector(spell: FakeSpell(ru: ru, en: en), exceptions: exc, alwaysSwitch: always)
    }

    // MARK: - Список «всегда переключать»

    /// Выученное слово переключается, даже если оно короче порога длины и словарь его не знает.
    @Test func alwaysSwitchBeatsMinLength() {
        let d = makeDetector(ru: [], en: [], exceptions: [], alwaysSwitch: ["рш"])
        #expect(d.decide("рш") == .switchLayout(replacement: "hi", target: .english))
    }

    /// Исключение сильнее автозамены: если слово попало в оба списка, «не трогай» побеждает.
    @Test func exceptionBeatsAlwaysSwitch() {
        let d = makeDetector(ru: [], en: [], exceptions: ["рш"], alwaysSwitch: ["рш"])
        #expect(d.decide("рш") == .leave)
    }

    /// Слово, провалившееся только по длине, годится для обучения автозамене.
    @Test func wouldSwitchIgnoringLengthSeesShortWord() {
        let d = makeDetector(ru: [], en: ["hi"])
        #expect(d.decide("рш") == .leave)                 // порог длины
        #expect(d.wouldSwitchIgnoringLength("рш"))
    }

    /// Настоящее слово обучению не подлежит: иначе тремя нажатиями можно сломать «hi».
    @Test func wouldSwitchIgnoringLengthRejectsRealWord() {
        let d = makeDetector(ru: [], en: ["hi"])
        #expect(!d.wouldSwitchIgnoringLength("hi"))
    }

    // MARK: - Основное правило

    @Test func wrongLayoutIsSwitched() {
        let d = makeDetector(ru: ["привет"], en: [])
        #expect(d.decide("ghbdtn") == .switchLayout(replacement: "привет", target: .russian))
    }

    @Test func correctEnglishWordLeftAlone() {
        let d = makeDetector(ru: [], en: ["hello"])
        #expect(d.decide("hello") == .leave)
    }

    @Test func bothValidLeftAlone() {
        let d = makeDetector(ru: ["еуые"], en: ["test"])
        #expect(d.decide("test") == .leave)
    }

    @Test func convertedNotRealWordLeftAlone() {
        let d = makeDetector(ru: [], en: [])
        #expect(d.decide("ghbdtn") == .leave)
    }

    @Test func cyrillicToEnglish() {
        let d = makeDetector(ru: [], en: ["hello"])
        #expect(d.decide("руддщ") == .switchLayout(replacement: "hello", target: .english))
    }

    @Test func wordWithBracketLetterKeyIsSwitched() {
        // «хорошо» в EN-раскладке набирается как "[jhjij" (скобка = х). Должно исправиться.
        let d = makeDetector(ru: ["хорошо"], en: [])
        #expect(d.decide("[jhjij") == .switchLayout(replacement: "хорошо", target: .russian))
    }

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

    @Test func exceptionWordLeftAlone() {
        let d = makeDetector(ru: ["привет"], en: [], exceptions: ["ghbdtn"])
        #expect(d.decide("ghbdtn") == .leave)
    }

    @Test func tooShortLeftAlone() {
        let d = makeDetector(ru: ["на"], en: [])
        #expect(d.decide("yf") == .leave)
    }

    @Test func allCapsLeftAlone() {
        let d = makeDetector(ru: ["привет"], en: [])
        #expect(d.decide("GHBDTN") == .leave)
    }

    @Test func camelCaseLeftAlone() {
        let d = makeDetector(ru: ["привет"], en: [])
        #expect(d.decide("gHbdtn") == .leave)
    }

    @Test func wordWithDigitsLeftAlone() {
        let d = makeDetector(ru: ["привет"], en: [])
        #expect(d.decide("ghbdtn1") == .leave)
    }
}
