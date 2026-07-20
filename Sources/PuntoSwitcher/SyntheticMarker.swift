import Foundation

/// Маркер, которым помечаем СВОИ синтетические события (backspace/вставка текста),
/// чтобы перехватчик их игнорировал и не зациклился на собственном вводе.
/// Значение "PSW" (Punto SWitcher) в ASCII.
enum SyntheticMarker {
    static let value: Int64 = 0x50_53_57
}
