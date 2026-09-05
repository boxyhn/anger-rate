import AppKit
import AngerCore

/// Offline promotional composition. Uses synthetic messages and production scoring/geometry.
/// Runs before AppModel exists: no personal sessions, preferences, or notifications are accessed.
@MainActor enum DemoRenderer {
    static func render(to directory: URL, korean: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fps = 24, frames = 360
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let messages = korean
            ? ["이 버튼 좀 고쳐줘.", "아 씨발, 또 안 되잖아.", "씨발, 똑같이 망가졌잖아.", "씨발 진짜, 씨발."]
            : ["Can you fix this button?", "Fuck, it broke again.", "Fuck, the same thing again.", "Fuck this. Fuck."]
        let times = [1.0, 3.0, 5.0, 7.0]
        let events = zip(messages.indices, times).compactMap { index, time in
            ScoreEngine.evaluate(message: SessionMessage(id: "demo-\(index)", timestamp: base.addingTimeInterval(time), source: "codex", text: messages[index]), profile: .starter, deviceID: "demo")
        }
        var gate = AlertGate(), known = Set<String>(), alerts = 0
        var phase = 0.0, evidence: [[String: Any]] = []
        for frame in 0..<frames {
            try autoreleasepool {
                let t = Double(frame) / Double(fps)
                // The edit explicitly jumps forward ten minutes; decay is never sped up silently.
                let elapsed = t < 11 ? t : t + 600
                let now = base.addingTimeInterval(elapsed)
                let available = events.filter { $0.timestamp <= now }
                let ids = Set(available.map(\.id))
                let score = ScoreEngine.score(events: available, at: now)
                let alert = gate.update(events: available, newEventIDs: ids.subtracting(known), at: now, halfLife: 300, allowAlert: true, notificationDeviceID: "demo")
                if alert { alerts += 1 }
                if ids != known || frame == 264 {
                    evidence.append(["videoSecond": t, "simulatedElapsedSeconds": elapsed, "score": score, "alert": alert])
                }
                known = ids
                phase += FlameMotion.frequency(score) * 2 * .pi / Double(fps)
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                let cg = context.cgContext
                cg.translateBy(x: 0, y: 800); cg.scaleBy(x: 1, y: -1)
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                draw(t: t, score: score, phase: phase, messages: messages, times: times, korean: korean, alertVisible: alerts > 0 && t >= 7 && t < 11)
                NSGraphicsContext.restoreGraphicsState()
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: directory.appendingPathComponent(String(format: "%04d.png", frame)))
            }
        }
        guard alerts == 1, events.count == 3 else { throw CocoaError(.validationMissingMandatoryProperty) }
        let report: [String: Any] = ["syntheticMessages": true, "screenRecording": false, "fps": fps, "frames": frames, "alertCount": alerts, "engine": "ScoreEngine + AlertGate", "timeline": evidence]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("verification.json"))
        print("Exported \(frames) frames; \(events.count) scored messages; \(alerts) threshold alert.")
    }

    private static let ink = NSColor(calibratedWhite: 0.12, alpha: 1)
    private static let muted = NSColor(calibratedWhite: 0.47, alpha: 1)
    private static func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor? = nil) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color ?? ink])
    }
    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 0) {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
    }
    private static func flame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, score: Double, phase: Double) {
        let cg = NSGraphicsContext.current!.cgContext
        cg.saveGState()
        cg.translateBy(x: x, y: y); cg.scaleBy(x: w / 64, y: h / 80)
        let level = FlameMotion.level(score), k = [1.0, 0.73, 0.95][FlameMotion.level(score)]
        cg.translateBy(x: 32 * (1-k), y: 73 * (1-k)); cg.scaleBy(x: k, y: k)
        let paths = FlameGeometry.paths(level: level, phase: phase, score: score)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        cg.setFillColor(ink.cgColor); cg.addPath(paths.0.cgPath); cg.fillPath()
        cg.clip(to: CGRect(x: 0, y: 0, width: 64, height: 80))
        cg.setBlendMode(.clear); cg.addPath(paths.1.cgPath); cg.fillPath()
        cg.endTransparencyLayer()
        cg.restoreGState()
    }
    private static func draw(t: Double, score: Double, phase: Double, messages: [String], times: [Double], korean: Bool, alertVisible: Bool) {
        rect(0, 0, 1280, 800, NSColor(calibratedRed: 0.965, green: 0.96, blue: 0.95, alpha: 1))
        text("AngerRate", 64, 42, 24, weight: .semibold)
        text(korean ? "예시 대화 · 실제 점수 엔진 · 연출된 데모" : "SAMPLE MESSAGES · REAL SCORING · STAGED DEMO", 674, 49, 13, color: muted)
        let title = t < 7
            ? (korean ? "AI한테 자꾸 욕하게 돼서 만들었습니다." : "I kept swearing at my coding agent.")
            : (korean ? "작은 불꽃이, 잠깐 멈출 때를 알려줍니다." : "So I made a tiny flame that tells me to pause.")
        text(title, 64, 105, korean ? 37 : 39, weight: .semibold)
        text(korean ? "Codex · Claude Code를 위한 macOS 메뉴 막대 앱" : "A macOS menu bar companion for Codex & Claude Code", 66, 165, 20, color: muted)
        rect(64, 232, 650, 388, .white, radius: 20)
        text(korean ? "코딩하다 보면…" : "A familiar coding session…", 90, 255, 17, weight: .medium, color: muted)
        for i in messages.indices where t >= times[i] {
            let y = CGFloat(305 + i * 70)
            rect(90, y, 596, 53, NSColor(calibratedWhite: 0.96, alpha: 1), radius: 12)
            text(messages[i], 106, y + 14, 21)
        }
        rect(742, 232, 474, 388, .white, radius: 20)
        rect(764, 249, 430, 38, NSColor(calibratedWhite: 0.965, alpha: 1), radius: 10)
        text(korean ? "메뉴 막대" : "Menu bar", 782, 259, 14, color: muted)
        flame(1114, 252, 22, 28, score: score, phase: phase)
        text("9:41", 1150, 259, 13, weight: .medium)
        flame(908, 302, 142, 178, score: score, phase: phase)
        let state = score < 33 ? (korean ? "잔잔한 불" : "A quiet flame") : score < 66 ? (korean ? "피어나는 불" : "Getting warmer") : (korean ? "타오르는 불" : "Running hot")
        text(state, 870, 492, 23, weight: .medium)
        if alertVisible {
            rect(770, 536, 418, 63, NSColor(calibratedWhite: 0.94, alpha: 1), radius: 13)
            text(korean ? "분노 신호가 높아졌어요" : "Anger signals are high", 788, 545, 17, weight: .semibold)
            text(korean ? "잠깐 쉬어갈까요?" : "Time for a breather?", 788, 571, 16, color: muted)
        } else if t >= 11 {
            text(korean ? "10분 뒤 · 새 분노 신호 없이" : "10 min later · no new anger signals", 794, 551, 16, color: muted)
        } else {
            text(korean ? "신호가 쌓일수록 더 거세지는 불꽃" : "More signals. A livelier flame.", 808, 551, 17, color: muted)
        }
        text(t < 11 ? (korean ? "화를 알아차리고. 잠깐 쉬어가기." : "Notice the heat. Take a moment.") : (korean ? "작고 조용한, 나만의 휴식 신호." : "A small reminder to take a breath."), 66, 662, 26, weight: .medium)
        text("github.com/boxyhn/anger-rate", 66, 718, 22, weight: .semibold)
        text(korean ? "오픈소스 · 한국어 / English" : "Open source · English / 한국어", 835, 723, 18, color: muted)
    }
}
