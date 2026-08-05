import Foundation

/// Решение детектора: что делать с завершённым словом.
public enum Decision: Equatable {
    /// Ничего не делаем.
    case leave
    /// Слово набрано не в той раскладке — заменить на `replacement` и переключиться на `target`.
    case switchLayout(replacement: String, target: LayoutMapper.Layout)
}

/// Определяет, набрано ли слово в неправильной раскладке.
///
/// Правило (как у RuSwitcher, самый чистый по приватности подход):
///  1. слово в списке исключений → оставить;
///  2. пре-фильтры (длина, только буквы, не CAPS/camelCase) → оставить;
///  3. если сконвертированный вариант — реальное слово в целевом языке,
///     а исходный НЕ реальное слово в своём языке → переключить;
///  4. если оба валидны (напр. англ. «no» и то, что из него выходит) → оставить.
public struct Detector {
    private let spell: SpellChecking
    private let exceptions: ExceptionsStore
    private let minLength: Int

    public init(spell: SpellChecking, exceptions: ExceptionsStore, minLength: Int = 3) {
        self.spell = spell
        self.exceptions = exceptions
        self.minLength = minLength
    }

    public func decide(_ raw: String) -> Decision {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Длину меряем по ВСЕМ символам, а не по буквам исходника: слово в неправильной
        // раскладке может содержать пунктуационные клавиши ([ ] ; ' — это буквы х ъ ж э
        // в русской раскладке), из-за подсчёта «только букв» короткие слова вроде
        // «это» ('nj) вообще не проверялись. Конвертация посимвольная 1:1, и фильтр
        // isAllLetters(converted) ниже гарантирует, что каждый символ станет буквой.
        guard word.count >= minLength else { return .leave }
        guard !word.contains(where: { $0.isNumber }) else { return .leave }
        guard !isAllCaps(word) else { return .leave }
        guard !isCamelCase(word) else { return .leave }
        guard !exceptions.contains(word) else { return .leave }

        let currentScript = LayoutMapper.script(of: word)
        let sourceLang: String
        let targetLang: String
        let converted: String
        let target: LayoutMapper.Layout

        switch currentScript {
        case .english:
            // набрано латиницей → предполагаем, что хотели русский
            sourceLang = "en"; targetLang = "ru"
            converted = LayoutMapper.toRussian(word); target = .russian
        case .russian:
            // набрано кириллицей → предполагаем, что хотели английский
            sourceLang = "ru"; targetLang = "en"
            converted = LayoutMapper.toEnglish(word); target = .english
        }

        // Конвертация должна дать нормальные буквы целевого скрипта, иначе смысла нет.
        guard isAllLetters(converted) else { return .leave }
        // Переключаем, только если converted — настоящее слово, а исходник — нет.
        guard spell.isRealWord(converted, language: targetLang) else { return .leave }
        guard !spell.isRealWord(word, language: sourceLang) else { return .leave }

        return .switchLayout(replacement: converted, target: target)
    }

    // MARK: - Пре-фильтры

    private func isAllLetters(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }

    private func isAllCaps(_ s: String) -> Bool {
        let letters = s.filter { $0.isLetter }
        return !letters.isEmpty && letters == letters.uppercased() && letters != letters.lowercased()
    }

    /// camelCase / наличие заглавной не в начале — вероятно, намеренный ввод (идентификатор).
    private func isCamelCase(_ s: String) -> Bool {
        var idx = 0
        for ch in s {
            if idx > 0 && ch.isUppercase { return true }
            idx += 1
        }
        return false
    }
}
