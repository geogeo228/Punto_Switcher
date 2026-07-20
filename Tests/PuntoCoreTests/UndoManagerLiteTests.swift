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
        let result = u.revert()
        #expect(result?.replacement.original == "ghbdtn")
        #expect(!u.canRevert)
    }

    @Test func revertNothingReturnsNil() {
        let u = UndoManagerLite()
        #expect(u.revert() == nil)
    }

    @Test func learningAfterThreshold() {
        let u = UndoManagerLite(undoThreshold: 3)
        for i in 1...3 {
            u.record(rep("wtf"))
            let r = u.revert()
            if i < 3 {
                #expect(r?.shouldAddException == false)
            } else {
                #expect(r?.shouldAddException == true)
            }
        }
    }

    @Test func differentWordResetsStreak() {
        let u = UndoManagerLite(undoThreshold: 3)
        u.record(rep("wtf")); _ = u.revert()
        u.record(rep("wtf")); _ = u.revert()
        u.record(rep("lol")); let r = u.revert()
        #expect(r?.shouldAddException == false)
    }

    /// Между откатами «wtf» проскочило принятое авто-переключение другого слова —
    /// серия должна обнулиться, слово НЕ добавляется, даже если всего откатов ≥3.
    @Test func interruptingSwitchResetsStreak() {
        let u = UndoManagerLite(undoThreshold: 3)
        u.record(rep("wtf")); _ = u.revert()   // streak 1
        u.record(rep("wtf")); _ = u.revert()   // streak 2
        u.record(rep("abc"))                    // другое слово переключилось (принято, без отката)
        u.record(rep("wtf")); let r = u.revert() // серия начата заново → streak 1
        #expect(r?.shouldAddException == false)
    }

    /// Три отката одного слова ПОДРЯД (без прерываний) — добавляется.
    @Test func threeConsecutiveAdds() {
        let u = UndoManagerLite(undoThreshold: 3)
        u.record(rep("wtf")); _ = u.revert()
        u.record(rep("wtf")); _ = u.revert()
        u.record(rep("wtf")); let r = u.revert()
        #expect(r?.shouldAddException == true)
    }
}
