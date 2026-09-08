import AppKit
import SwiftUI
import AngerCore

@main struct AngerRateApp: App {
    private var menuController: MenuBarController?
    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-demo"), CommandLine.arguments.count > index + 1 {
            NSApplication.shared.setActivationPolicy(.accessory)
            do {
                try DemoRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), korean: CommandLine.arguments.contains("--korean"))
                exit(0)
            } catch {
                fputs("Demo export failed: \(error)\n", stderr)
                exit(1)
            }
        }
        if CommandLine.arguments.contains("--scan-check") {
            let scanner = SessionScanner()
            let start = Date()
            let initial = scanner.scanNew()
            let history = scanner.historicalMessages(limit: 100)
            let elapsed = Date().timeIntervalSince(start)
            print("files=\(scanner.scannedFileCount) initialEmitted=\(initial.count) historySample=\(history.count) elapsedSeconds=\(elapsed) error=\(scanner.lastError == nil ? "none" : "read-error")")
            exit(initial.isEmpty ? 0 : 1)
        }
        if CommandLine.arguments.contains("--smoke-test") {
            let now = Date()
            let message = SessionMessage(id: "smoke", timestamp: now, source: "codex", text: "씨발")
            let event = ScoreEngine.evaluate(message: message, profile: .starter, deviceID: "smoke")!
            let score = ScoreEngine.score(events: [event], at: now)
            print("{\"app\":\"AngerRate\",\"smoke\":\(score == 30 ? "true" : "false"),\"score\":\(score)}")
            exit(score == 30 ? 0 : 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let model = AppModel(preview: true)
            let view = NSHostingView(rootView: CommandLine.arguments.contains("--settings-preview") ? AnyView(PreferencesView(model: model)) : AnyView(MainPanel(model: model)))
            view.frame = CommandLine.arguments.contains("--settings-preview") ? NSRect(x: 0, y: 0, width: 680, height: 760) : NSRect(x: 0, y: 0, width: 400, height: 540)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                }
            }
            exit(0)
        }
        menuController = MenuBarController(model: AppModel())
    }
    var body: some Scene {
        Settings { EmptyView() }
    }
}
