import Testing
@testable import PuntoCore

@Suite struct UndoManagerLiteTests {

    private func rep(_ original: String) -> Replacement {
        Replacement(original: original, replacement: "привет", previousLayout: .english)
    }

    @Test func recordAndRevert() {
        let u = UndoManagerLite()
        #expect(!u.canRevert)
        u.record(rep("ghbdtn"))
        #expect(u.canRevert)
        #expect(u.revert()?.original == "ghbdtn")
        #expect(!u.canRevert)
    }

    @Test func revertNothingReturnsNil() {
        let u = UndoManagerLite()
        #expect(u.revert() == nil)
    }

    /// Одну и ту же замену дважды не откатить — иначе второй хоткей испортит текст.
    @Test func revertIsSingleUse() {
        let u = UndoManagerLite()
        u.record(rep("ghbdtn"))
        _ = u.revert()
        #expect(u.revert() == nil)
    }

    /// Новая замена перекрывает старую.
    @Test func recordOverwrites() {
        let u = UndoManagerLite()
        u.record(rep("ghbdtn"))
        u.record(rep("cjxb"))
        #expect(u.revert()?.original == "cjxb")
    }

    @Test func resetForgetsLast() {
        let u = UndoManagerLite()
        u.record(rep("ghbdtn"))
        u.reset()
        #expect(!u.canRevert)
        #expect(u.revert() == nil)
    }
}
