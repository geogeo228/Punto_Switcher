import Testing
@testable import PuntoCore

@Suite struct WordBufferTests {

    @Test func appendAndCommit() {
        let b = WordBuffer()
        "ghbdtn".forEach { b.append($0) }
        #expect(b.current == "ghbdtn")
        #expect(b.commit() == "ghbdtn")
        #expect(b.isEmpty)
    }

    @Test func commitEmptyReturnsNil() {
        let b = WordBuffer()
        #expect(b.commit() == nil)
    }

    @Test func backspace() {
        let b = WordBuffer()
        "abc".forEach { b.append($0) }
        b.backspace()
        #expect(b.current == "ab")
    }

    @Test func backspaceOnEmptyIsSafe() {
        let b = WordBuffer()
        b.backspace()
        #expect(b.isEmpty)
    }

    @Test func resetClears() {
        let b = WordBuffer()
        "abc".forEach { b.append($0) }
        b.reset()
        #expect(b.isEmpty)
    }
}
