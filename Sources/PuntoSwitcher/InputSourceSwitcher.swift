import Carbon
import PuntoCore

/// Переключение системной раскладки клавиатуры через Carbon Text Input Sources (TIS).
final class InputSourceSwitcher {
    private var cache: [String: TISInputSource] = [:]

    /// Переключиться на раскладку нужного языка.
    func select(_ layout: LayoutMapper.Layout) {
        let lang = (layout == .russian) ? "ru" : "en"
        guard let source = inputSource(for: lang) else { return }
        TISSelectInputSource(source)
    }

    private func inputSource(for lang: String) -> TISInputSource? {
        if let cached = cache[lang] { return cached }
        guard let cfList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
              let list = cfList as? [TISInputSource] else { return nil }

        for source in list {
            guard category(of: source) == (kTISCategoryKeyboardInputSource as String) else { continue }
            guard isSelectable(source) else { continue }
            let langs = languages(of: source)
            if langs.first == lang {
                cache[lang] = source
                return source
            }
        }
        return nil
    }

    // MARK: - Чтение свойств TIS

    private func category(of source: TISInputSource) -> String? {
        stringProperty(source, kTISPropertyInputSourceCategory)
    }

    private func isSelectable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private func languages(of source: TISInputSource) -> [String] {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }
        let array = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue()
        return (array as? [String]) ?? []
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return (Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String)
    }
}
