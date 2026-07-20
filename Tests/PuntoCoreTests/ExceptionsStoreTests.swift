import Testing
import Foundation
@testable import PuntoCore

@Suite struct ExceptionsStoreTests {

    @Test func inMemoryAddContains() {
        let s = ExceptionsStore(fileURL: nil)
        #expect(!s.contains("ghbdtn"))
        s.add("ghbdtn")
        #expect(s.contains("ghbdtn"))
    }

    @Test func caseInsensitive() {
        let s = ExceptionsStore(fileURL: nil)
        s.add("GhBdTn")
        #expect(s.contains("ghbdtn"))
    }

    @Test func persistAndReload() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("punto-test-\(UUID().uuidString)")
            .appendingPathComponent("exceptions.txt")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

        let s1 = ExceptionsStore(fileURL: tmp)
        s1.add("wtf")
        s1.add("lol")

        let s2 = ExceptionsStore(fileURL: tmp)
        #expect(s2.contains("wtf"))
        #expect(s2.contains("lol"))
    }

    @Test func fileIsHumanReadable() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("punto-test-\(UUID().uuidString)")
            .appendingPathComponent("exceptions.txt")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

        let s = ExceptionsStore(fileURL: tmp)
        s.add("wtf")
        let text = try String(contentsOf: tmp, encoding: .utf8)
        #expect(text.contains("wtf"))
    }
}
