// swift-tools-version:6.0
import PackageDescription

// PuntoSwitcher — авто-переключатель раскладки RU↔EN для macOS.
// ИНВАРИАНТ БЕЗОПАСНОСТИ: dependencies ДОЛЖЕН оставаться пустым.
// Только системные Apple-фреймворки. Никаких сторонних пакетов.
let package = Package(
    name: "PuntoSwitcher",
    platforms: [.macOS(.v13)],
    targets: [
        // Чистая логика — без доступа к системе, полностью тестируемая.
        .target(
            name: "PuntoCore",
            dependencies: []
        ),
        // Исполняемый файл — тонкий системный слой (CGEventTap, TIS, меню-бар).
        .executableTarget(
            name: "PuntoSwitcher",
            dependencies: ["PuntoCore"]
        ),
        .testTarget(
            name: "PuntoCoreTests",
            dependencies: ["PuntoCore"]
        ),
    ],
    // v5-режим: смягчает строгие concurrency-проверки Swift 6 для системного слоя,
    // который весь работает на главном потоке (CGEventTap/Carbon на main runloop).
    swiftLanguageModes: [.v5]
)
