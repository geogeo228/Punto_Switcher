import Foundation

/// Преобразование текста между раскладками US QWERTY (EN) и стандартной русской ЙЦУКЕН (RU).
///
/// Используется статическая таблица соответствия по физическим клавишам. Она детерминирована,
/// читается глазами целиком и не зависит от установленных в системе раскладок — это осознанный
/// выбор в пользу аудируемости (см. план: «безопасность — приоритет №1»).
public enum LayoutMapper {

    /// EN-символ (то, что на клавише в US QWERTY) → RU-символ (то же место на ЙЦУКЕН).
    /// Включены буквы и те пунктуационные клавиши, на которых в русской раскладке стоят буквы
    /// (х ъ ж э б ю ё и т.п.), иначе слова вроде «хорошо» не сконвертировать.
    public static let enToRu: [Character: Character] = [
        // строчные
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш",
        "o": "щ", "p": "з", "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь", ",": "б",
        ".": "ю", "/": ".",
        "`": "ё",
        // заглавные / с Shift
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш",
        "O": "Щ", "P": "З", "{": "Х", "}": "Ъ",
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
        "L": "Д", ":": "Ж", "\"": "Э",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь", "<": "Б",
        ">": "Ю", "?": ",",
        "~": "Ё",
    ]

    /// Обратная таблица RU → EN, выведена из `enToRu`. Значения `enToRu` уникальны,
    /// поэтому обращение однозначно.
    public static let ruToEn: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, ru) in enToRu { map[ru] = en }
        return map
    }()

    /// Раскладки, между которыми переключаемся.
    public enum Layout {
        case english
        case russian
    }

    /// Определить преобладающий скрипт слова.
    public static func script(of text: String) -> Layout {
        var cyr = 0, lat = 0
        for ch in text.unicodeScalars {
            if (0x0410...0x044F).contains(ch.value) || ch.value == 0x0401 || ch.value == 0x0451 {
                cyr += 1
            } else if (0x41...0x5A).contains(ch.value) || (0x61...0x7A).contains(ch.value) {
                lat += 1
            }
        }
        return cyr > lat ? .russian : .english
    }

    /// Сконвертировать текст, набранный в EN-раскладке, в русский (как будто печатали в RU).
    public static func toRussian(_ text: String) -> String {
        String(text.map { enToRu[$0] ?? $0 })
    }

    /// Сконвертировать текст, набранный в RU-раскладке, в английский.
    public static func toEnglish(_ text: String) -> String {
        String(text.map { ruToEn[$0] ?? $0 })
    }

    /// Перевернуть слово в противоположную раскладку по его скрипту.
    public static func flipped(_ text: String) -> String {
        switch script(of: text) {
        case .russian: return toEnglish(text)
        case .english: return toRussian(text)
        }
    }
}
