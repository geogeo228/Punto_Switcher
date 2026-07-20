import CoreGraphics
import Foundation

/// Пассивный перехватчик клавиатуры на базе `CGEventTap` (`.listenOnly`).
///
/// Только НАБЛЮДАЕТ поток событий (не модифицирует его) — минимальная привилегия.
/// Замена текста делается отдельно, через постинг новых событий из `TextReplacer`.
/// Свои синтетические события отсеиваются по `SyntheticMarker`.
final class EventTapController {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Нажата клавиша (не наша синтетическая).
    var onKeyDown: ((CGEvent) -> Void)?
    /// Событие, сбрасывающее буфер слова (клик мышью).
    var onReset: (() -> Void)?

    /// Уже поднят ли перехват.
    var isRunning: Bool { tap != nil }

    /// Запустить перехват. Возвращает false, если не выданы права Accessibility.
    /// Идемпотентно: повторный вызов при уже поднятом перехвате просто вернёт true.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let controller = Unmanaged<EventTapController>.fromOpaque(refcon!).takeUnretainedValue()
            controller.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // Перехват может отключиться системой — включаем обратно.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        // Игнорируем собственные синтетические события.
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticMarker.value { return }

        switch type {
        case .keyDown:
            onKeyDown?(event)
        case .leftMouseDown, .rightMouseDown:
            onReset?()
        default:
            break
        }
    }
}
