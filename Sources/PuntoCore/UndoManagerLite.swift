import Foundation

/// Данные о последней автозамене — чтобы можно было откатить.
public struct Replacement: Equatable {
    public let original: String        // исходное слово (гиббериш), без разделителя
    public let replacement: String     // на что заменили, без разделителя
    public let previousLayout: LayoutMapper.Layout  // раскладка до переключения
    /// Полный текст, который реально был вставлен (converted + разделитель) — для отката.
    public let insertedText: String
    /// Полный исходный текст (original + разделитель) — что вернуть при откате.
    public let typedText: String

    public init(original: String,
                replacement: String,
                previousLayout: LayoutMapper.Layout,
                insertedText: String? = nil,
                typedText: String? = nil) {
        self.original = original
        self.replacement = replacement
        self.previousLayout = previousLayout
        self.insertedText = insertedText ?? replacement
        self.typedText = typedText ?? original
    }
}

/// Лёгкий менеджер отмены в RAM: помнит последнюю автозамену, чтобы её можно было откатить
/// ровно один раз. Учётом повторных нажатий и обучением исключений занимается `FlipStreak` —
/// здесь только «что вернуть на экран».
public final class UndoManagerLite {
    private var last: Replacement?

    public init() {}

    /// Записать выполненную автозамену.
    public func record(_ replacement: Replacement) {
        last = replacement
    }

    /// Есть ли что откатывать.
    public var canRevert: Bool { last != nil }

    /// Откатить последнюю замену. Возвращает данные для отката или nil, если откатывать нечего.
    /// Одну и ту же замену откатить дважды нельзя.
    public func revert() -> Replacement? {
        defer { last = nil }
        return last
    }

    /// Забыть последнюю замену (слово ушло в исключения, фокус сменился и т.п.).
    public func reset() { last = nil }
}
