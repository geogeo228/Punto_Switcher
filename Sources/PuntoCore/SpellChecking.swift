import Foundation

/// Абстракция проверки «это реальное слово в данном языке?».
///
/// Вынесена в протокол, чтобы `Detector` тестировался детерминированно (через фейк),
/// а в проде работал через системный `NSSpellChecker` без бандла собственных словарей.
public protocol SpellChecking {
    /// Язык в формате ISO (`"ru"`, `"en"`).
    func isRealWord(_ word: String, language: String) -> Bool
}
