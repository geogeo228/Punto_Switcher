import Foundation

/// Копит символы текущего «слова» в оперативной памяти.
///
/// Никогда не пишет на диск. Сбрасывается на разделителе, навигации, смене фокуса
/// или потере активности — то есть в буфере всегда живёт максимум одно текущее слово.
public final class WordBuffer {
    private(set) var chars: [Character] = []

    public init() {}

    /// Текущее накопленное слово.
    public var current: String { String(chars) }

    public var isEmpty: Bool { chars.isEmpty }

    /// Добавить напечатанный символ.
    public func append(_ ch: Character) {
        chars.append(ch)
    }

    /// Backspace — убрать последний символ.
    public func backspace() {
        if !chars.isEmpty { chars.removeLast() }
    }

    /// Полный сброс (смена фокуса, навигация, клик мышью и т.п.).
    public func reset() {
        chars.removeAll(keepingCapacity: true)
    }

    /// Завершить слово (нажат разделитель). Возвращает накопленное слово и очищает буфер.
    /// Возвращает nil, если буфер был пуст.
    @discardableResult
    public func commit() -> String? {
        guard !chars.isEmpty else { return nil }
        let word = String(chars)
        chars.removeAll(keepingCapacity: true)
        return word
    }
}
