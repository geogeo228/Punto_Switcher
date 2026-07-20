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

/// Результат отката.
public struct RevertResult: Equatable {
    public let replacement: Replacement
    /// true → пользователь откатил это слово достаточно раз, слово надо добавить в исключения.
    public let shouldAddException: Bool
}

/// Лёгкий менеджер отмены в RAM: помнит последнюю замену и считает повторные откаты
/// одного и того же слова. После `undoThreshold` откатов подряд предлагает добавить слово
/// в исключения — механика «обучения», как в оригинальном Punto Switcher.
public final class UndoManagerLite {
    private var last: Replacement?
    private var lastRevertedWord: String?
    private var revertStreak = 0
    private let undoThreshold: Int

    /// - Parameter undoThreshold: сколько раз подряд надо откатить слово, чтобы оно ушло в исключения.
    public init(undoThreshold: Int = 3) {
        self.undoThreshold = undoThreshold
    }

    /// Записать выполненную автозамену.
    /// Если авто-переключилось ДРУГОЕ слово — серия откатов «подряд» прерывается и обнуляется,
    /// поэтому в исключения слово уходит только после трёх откатов ОДНОГО и того же слова подряд.
    public func record(_ replacement: Replacement) {
        if replacement.original != lastRevertedWord {
            revertStreak = 0
            lastRevertedWord = nil
        }
        last = replacement
    }

    /// Есть ли что откатывать.
    public var canRevert: Bool { last != nil }

    /// Откатить последнюю замену. Возвращает данные для отката или nil, если откатывать нечего.
    public func revert() -> RevertResult? {
        guard let replacement = last else { return nil }

        // Считаем серию откатов одного и того же исходного слова.
        if lastRevertedWord == replacement.original {
            revertStreak += 1
        } else {
            lastRevertedWord = replacement.original
            revertStreak = 1
        }

        // Слово (в правильной раскладке — то, что мы навязали) добавляем в исключения,
        // чтобы «replacement» (напр. wtf→туа) больше не срабатывал: исключаем ИСХОДНОЕ слово.
        let shouldAdd = revertStreak >= undoThreshold

        last = nil  // одно и то же нельзя откатить дважды
        return RevertResult(replacement: replacement, shouldAddException: shouldAdd)
    }

    /// Сбросить серию (напр. пользователь начал печатать другое).
    public func resetStreak() {
        lastRevertedWord = nil
        revertStreak = 0
    }
}
