import Testing
@testable import PuntoCore

@Suite struct LayoutMapperTests {

    @Test func enToRuKnownWords() {
        #expect(LayoutMapper.toRussian("ghbdtn") == "привет")
        #expect(LayoutMapper.toRussian("gjrf") == "пока")
        #expect(LayoutMapper.toRussian("[jhjij") == "хорошо")
    }

    @Test func ruToEnKnownWords() {
        #expect(LayoutMapper.toEnglish("руддщ") == "hello")
        #expect(LayoutMapper.toEnglish("цщкв") == "word")
    }

    @Test func roundTripSymmetry() {
        for s in ["ghbdtn", "gjrf", "test", "hello"] {
            #expect(LayoutMapper.toEnglish(LayoutMapper.toRussian(s)) == s)
        }
    }

    @Test func scriptDetection() {
        #expect(LayoutMapper.script(of: "привет") == .russian)
        #expect(LayoutMapper.script(of: "ghbdtn") == .english)
        #expect(LayoutMapper.script(of: "hello") == .english)
    }

    @Test func flippedUsesScript() {
        #expect(LayoutMapper.flipped("ghbdtn") == "привет")
        #expect(LayoutMapper.flipped("руддщ") == "hello")
    }

    @Test func uppercasePreserved() {
        #expect(LayoutMapper.toRussian("Ghbdtn") == "Привет")
    }

    @Test func unknownCharsPassThrough() {
        #expect(LayoutMapper.toRussian("test123") == "еуые123")
    }
}
