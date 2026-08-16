import Foundation

/// Серия нажатий хоткея по одному и тому же слову — механика «обучения» из оригинального
/// Punto Switcher. Три нажатия подряд по слову значат «ты про это слово ошибаешься», и в
/// зависимости от того, КАК ошибается, слово уходит в один из двух списков:
///
///  * автозамена сработала и испортила слово → слово в **исключения** («не трогай»);
///  * автозамена промолчала, а слово надо было перевернуть → в **автозамену** («всегда переключай»).
///
/// Считаются ЛЮБЫЕ нажатия по слову: после первого текст на экране чередуется между двумя
/// формами, обе принадлежат одной серии. Серия рвётся только работой с ДРУГИМ словом —
/// Enter, клик, смена приложения её не трогают (слово в мессенджере живёт
/// «напечатал → отправил → напечатал снова»). Живёт только в RAM.
public final class FlipStreak {

    /// Что делать с нажатием хоткея.
    public enum Outcome: Equatable {
        /// Нажатие учтено, порог не достигнут. Значение — текущий счёт.
        case counted(Int)
        /// Порог по слову, которое испортила автозамена: слово (исходная форма) — в исключения.
        case learnException(String)
        /// Порог по слову, которое автозамена не трогала: слово (исходная форма) — в автозамену.
        case learnAutoSwitch(String)
    }

    /// Откуда взялась серия — от этого зависит, чему учимся.
    private enum Kind {
        /// Началась с реальной автозамены: пользователь её отменяет.
        case autoSwitched
        /// Началась с ручного хоткея по нетронутому слову: пользователь доделывает за автозаменой.
        case manual
    }

    /// Слово, за которым следим: обе его формы.
    private struct Series {
        /// Как набрал пользователь — эта форма и уходит в список, её проверяет `Detector`.
        var typed: String
        /// Противоположная раскладка.
        var converted: String
        var kind: Kind
        var count: Int

        func matches(_ text: String) -> Bool {
            let t = FlipStreak.normalize(text)
            return t == FlipStreak.normalize(typed) || t == FlipStreak.normalize(converted)
        }
    }

    private var series: Series?
    private let threshold: Int

    /// - Parameter threshold: сколько нажатий хоткея по одному слову → слово в список.
    public init(threshold: Int = 3) {
        self.threshold = threshold
    }

    /// Сработала автозамена: `typed` заменено на `converted`.
    /// То же слово (в любой из двух форм) — счёт продолжается, другое — серия начинается заново.
    public func autoSwitched(typed: String, converted: String) {
        let carried = (series?.matches(typed) == true) ? series!.count : 0
        series = Series(typed: typed, converted: converted, kind: .autoSwitched, count: carried)
    }

    /// Нажат хоткей по слову `text` — тому, что реально на экране.
    public func press(on text: String) -> Outcome {
        guard var s = series, s.matches(text) else {
            // Первое нажатие по нетронутому слову: на экране ещё исходная форма,
            // значит именно `text` — то, что набрал пользователь.
            series = Series(typed: text, converted: LayoutMapper.flipped(text),
                            kind: .manual, count: 1)
            return threshold <= 1 ? finish(series!) : .counted(1)
        }
        s.count += 1
        if s.count >= threshold { return finish(s) }
        series = s
        return .counted(s.count)
    }

    /// Явный сброс серии.
    public func reset() { series = nil }

    private func finish(_ s: Series) -> Outcome {
        series = nil      // порог отработан, счёт начинаем с нуля
        switch s.kind {
        case .autoSwitched: return .learnException(s.typed)
        case .manual:       return .learnAutoSwitch(s.typed)
        }
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
