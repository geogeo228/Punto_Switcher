import CoreGraphics
import Foundation

/// Заменяет только что набранное слово: синтетические backspace + прямая вставка Unicode.
/// Буфер обмена НЕ используется. Все события помечаются `SyntheticMarker`.
final class TextReplacer {
    private let source = CGEventSource(stateID: .combinedSessionState)
    private let deleteKey: CGKeyCode = 0x33   // клавиша Delete (backspace), keycode 51

    /// Удалить `deleteCount` символов и вставить `insert`.
    func replace(deleteCount: Int, insert: String) {
        guard deleteCount >= 0 else { return }
        for _ in 0..<deleteCount {
            postKey(deleteKey, down: true)
            postKey(deleteKey, down: false)
        }
        if !insert.isEmpty {
            postUnicode(insert)
        }
    }

    private func postKey(_ key: CGKeyCode, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        // В момент срабатывания хоткея ⌃⌥U модификаторы физически зажаты, и событие
        // от .combinedSessionState унаследовало бы их — приложение получило бы ⌃⌥⌫
        // вместо Backspace и проигнорировало бы удаление. Флаги обнуляем явно.
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticMarker.value)
        event.post(tap: .cgSessionEventTap)
    }

    private func postUnicode(_ string: String) {
        var units = Array(string.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            // Те же зажатые ⌃⌥, что и в postKey: без чистки флагов вставка может
            // трактоваться приложением как шорткат.
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticMarker.value)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
