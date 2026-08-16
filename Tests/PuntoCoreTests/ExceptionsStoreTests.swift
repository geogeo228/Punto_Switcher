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

    /// Слово можно убрать — напр. когда оно переехало в противоположный список.
    @Test func removeDeletesWord() {
        let s = ExceptionsStore(fileURL: nil)
        s.add("рш")
        s.remove("РШ")            // регистр не важен
        #expect(!s.contains("рш"))
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

    /// Правки файла руками подхватываются без перезапуска: reload заменяет память файлом.
    @Test func reloadPicksUpExternalEdits() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("punto-test-\(UUID().uuidString)")
            .appendingPathComponent("exceptions.txt")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

        let s = ExceptionsStore(fileURL: tmp)
        s.add("wtf")
        s.add("lol")
        #expect(s.contains("wtf"))

        // пользователь открыл файл и вычистил лишнее, оставив одно слово
        try "lol\n".write(to: tmp, atomically: true, encoding: .utf8)
        s.reload()

        #expect(!s.contains("wtf"))
        #expect(s.contains("lol"))
    }

    @Test func ensureFileExistsCreatesIt() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("punto-test-\(UUID().uuidString)")
            .appendingPathComponent("exceptions.txt")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

        let s = ExceptionsStore(fileURL: tmp)
        #expect(!FileManager.default.fileExists(atPath: tmp.path))
        s.ensureFileExists()
        #expect(FileManager.default.fileExists(atPath: tmp.path))
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
