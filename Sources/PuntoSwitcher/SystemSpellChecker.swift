import AppKit
import PuntoCore

/// Реализация `SpellChecking` через системный `NSSpellChecker`.
/// Не бандлит собственных словарей и не ходит в сеть — использует словари ОС.
final class SystemSpellChecker: SpellChecking {
    private let checker = NSSpellChecker.shared

    func isRealWord(_ word: String, language: String) -> Bool {
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        // location == NSNotFound → орфографических ошибок нет → это реальное слово.
        return range.location == NSNotFound
    }

    /// Есть ли в системе словари для нужных языков (для предупреждения в меню).
    func hasDictionary(for language: String) -> Bool {
        checker.availableLanguages.contains { $0.hasPrefix(language) }
    }
}
