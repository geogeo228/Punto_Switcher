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
