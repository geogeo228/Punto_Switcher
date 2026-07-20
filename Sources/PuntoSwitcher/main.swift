import AppKit

// Меню-бар приложение без иконки в доке.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = AppController()
controller.start()

app.run()
