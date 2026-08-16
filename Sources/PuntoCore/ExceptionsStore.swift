import Foundation

/// Список слов-исключений: слова, которые пользователь явно пометил «не трогать».
///
/// Хранится в RAM как множество + персист в ЧЕЛОВЕКОЧИТАЕМЫЙ plain-text файл
/// (по слову на строку). Это единственное осознанное отступление от инварианта
/// «ноль записи на диск»: сюда попадают ТОЛЬКО явно добавленные слова, а не сырой ввод.
/// Файл можно открыть и проверить глазами.
public final class ExceptionsStore {
    private var words: Set<String> = []
    private let fileURL: URL?

    /// - Parameter fileURL: путь к файлу исключений. `nil` → режим только в памяти (для тестов).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    /// Путь по умолчанию: ~/Library/Application Support/PuntoSwitcher/exceptions.txt
    public static func defaultFileURL() -> URL {
        defaultFileURL(named: "exceptions.txt")
    }

    /// Тот же формат, другой файл — например `autoswitch.txt` для списка «всегда переключать».
    public static func defaultFileURL(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PuntoSwitcher/\(name)")
    }

    public func contains(_ word: String) -> Bool {
        words.contains(normalize(word))
    }

    /// Добавить слово в исключения и сохранить.
    public func add(_ word: String) {
        let w = normalize(word)
        guard !w.isEmpty else { return }
        let (inserted, _) = words.insert(w)
        if inserted { save() }
    }

    /// Убрать слово из списка (напр. оно переехало в противоположный список).
    public func remove(_ word: String) {
        if words.remove(normalize(word)) != nil { save() }
    }

    public var all: [String] { words.sorted() }

    /// Путь к файлу списка (nil в режиме «только в памяти»).
    public var url: URL? { fileURL }

    /// Перечитать файл с диска: пользователь мог поправить список руками.
    /// Память полностью заменяется содержимым файла — удалённые строки реально уходят.
    public func reload() {
        words.removeAll()
        load()
    }

    /// Создать файл (и папку), если его ещё нет, — чтобы его можно было открыть в редакторе.
    @discardableResult
    public func ensureFileExists() -> URL? {
        guard let url = fileURL else { return nil }
        if !FileManager.default.fileExists(atPath: url.path) { save() }
        return url
    }

    // MARK: - Персист

    private func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func load() {
        guard let url = fileURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            let w = normalize(String(line))
            if !w.isEmpty { words.insert(w) }
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = words.sorted().joined(separator: "\n") + "\n"
        // Атомарная запись, чтобы не оставить полуфайл при сбое.
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
