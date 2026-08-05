import Foundation

/// Отслеживает, что лежит «на экране» после завершения слова: само слово,
/// хвостовые разделители (пробелы) и правки backspace'ом.
///
/// Нужен хоткею ⌃⌥U: чтобы перевернуть слово, надо удалить РОВНО столько
/// символов, сколько реально есть на экране, — иначе замена портит текст.
/// Живёт только в RAM, как и WordBuffer.
public final class ScreenWordTracker {
    /// Снимок состояния «на экране».
    public struct State: Equatable {
        /// Слово (возможно, уже подрезанное backspace'ами).
        public var text: String
        /// Хвостовые разделители после слова (обычно пробелы).
        public var separator: String
        /// Слово появилось в результате авто-замены.
        public var fromAutoSwitch: Bool
        /// Были ли правки (лишние пробелы/backspace) после фиксации слова.
        /// Пока false — записанный в UndoManagerLite откат совпадает с экраном
        /// и можно идти путём авто-отката; после правок — только force-flip.
        public var edited: Bool
    }

    public private(set) var state: State?

    public init() {}

    /// Зафиксировать новое слово на экране (после коммита или замены).
    public func set(text: String, separator: String, fromAutoSwitch: Bool) {
        state = State(text: text, separator: separator,
                      fromAutoSwitch: fromAutoSwitch, edited: false)
    }

    /// Нажат разделитель (пробел) при пустом буфере — хвост растёт.
    public func appendSeparator(_ s: String) {
        guard state != nil else { return }
        state?.separator += s
        state?.edited = true
    }

    /// Нажат backspace при пустом буфере: сначала укорачивается хвост
    /// разделителей, затем само слово. Слово стёрто целиком → состояние сброшено.
    public func backspace() {
        guard var st = state else { return }
        if !st.separator.isEmpty {
            st.separator.removeLast()
        } else if !st.text.isEmpty {
            st.text.removeLast()
        }
        st.edited = true
        state = st.text.isEmpty ? nil : st
    }

    /// Полный сброс (навигация, клик, смена приложения, Enter/Tab).
    public func reset() { state = nil }
}
