import AppKit
import SwiftUI
import AngerCore

/// Original vector silhouettes from the approved flame prototype.
struct FlameView: View {
    var score: Double
    var isAnimating: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin = Date()
    @State private var phase = 0.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isAnimating || reduceMotion)) { context in
            let angle = reduceMotion ? 0 : phase + max(0, context.date.timeIntervalSince(origin)) * FlameMotion.frequency(score) * 2 * .pi
            Canvas { graphics, size in
                let level = FlameMotion.level(score)
                let paths = FlameGeometry.paths(level: level, phase: angle, score: score)
                let k = [1.0, 0.73, 0.95][level]
                graphics.scaleBy(x: size.width / 64, y: size.height / 80)
                graphics.translateBy(x: 32 * (1-k), y: 73 * (1-k))
                graphics.scaleBy(x: k, y: k)
                graphics.clip(to: paths.0)
                graphics.fill(paths.0, with: .foreground)
                graphics.blendMode = .destinationOut
                graphics.fill(paths.1, with: .color(.black))
            }
        }
        .onChange(of: score) { oldToNew in
            // Maintain phase across speed changes rather than restarting the flame.
            let now = Date()
            phase += max(0, now.timeIntervalSince(origin)) * FlameMotion.frequency(previousScore) * 2 * .pi
            origin = now
            previousScore = oldToNew
        }
        .onAppear { previousScore = score; origin = Date() }
        .onChange(of: isAnimating) { _ in origin = Date() }
        .accessibilityHidden(true)
    }
    @State private var previousScore = 0.0
}

enum FlameGeometry {
    static func paths(level: Int, phase: Double, score: Double) -> (Path, Path) {
        let strength = 1 + pow(min(100, max(0, score)) / 100, 2) * 0.65
        let a = sin(phase) * strength, b = sin(phase - 1.2) * strength, c = sin(phase + 1.5) * strength
        var outer = Path(), cut = Path()
        switch level {
        case 0:
            let tipX = 34+a*4.2, tipY = 18+c*0.6
            outer.move(to: CGPoint(x: 32, y: 73))
            outer.addCurve(to: CGPoint(x: 22, y: 60), control1: CGPoint(x: 24, y: 73), control2: CGPoint(x: 21, y: 67))
            outer.addCurve(to: CGPoint(x: tipX, y: tipY), control1: CGPoint(x: 23, y: 49), control2: CGPoint(x: 31+b, y: 40))
            outer.addCurve(to: CGPoint(x: 43, y: 59), control1: CGPoint(x: tipX+1, y: 36), control2: CGPoint(x: 42, y: 47))
            outer.addCurve(to: CGPoint(x: 32, y: 73), control1: CGPoint(x: 44, y: 67), control2: CGPoint(x: 40, y: 73))
            outer.closeSubpath()

        case 1:
            let tipX = 38+a*3, tipY = 7+b*1.3, sideX = 18+c*1.4, sideY = 26+b*2
            outer.move(to: CGPoint(x: 32, y: 73))
            outer.addCurve(to: CGPoint(x: 8, y: 51), control1: CGPoint(x: 18, y: 73), control2: CGPoint(x: 8, y: 64))
            outer.addCurve(to: CGPoint(x: sideX, y: sideY), control1: CGPoint(x: 8, y: 41), control2: CGPoint(x: sideX-4, y: sideY+5))
            outer.addCurve(to: CGPoint(x: 25, y: 38), control1: CGPoint(x: sideX+4, y: sideY-2), control2: CGPoint(x: 18, y: 40))
            outer.addCurve(to: CGPoint(x: tipX, y: tipY), control1: CGPoint(x: 34, y: 35), control2: CGPoint(x: tipX-3, y: tipY+12))
            outer.addCurve(to: CGPoint(x: 56, y: 46), control1: CGPoint(x: tipX+1, y: tipY-3), control2: CGPoint(x: 56, y: 25))
            outer.addCurve(to: CGPoint(x: 32, y: 73), control1: CGPoint(x: 58, y: 61), control2: CGPoint(x: 48, y: 73))
            outer.closeSubpath()
            cut.move(to: CGPoint(x: 31, y: 76))
            cut.addCurve(to: CGPoint(x: 25, y: 59), control1: CGPoint(x: 22, y: 71), control2: CGPoint(x: 22, y: 64))
            cut.addCurve(to: CGPoint(x: 32+b*1.8, y: 46+c*1.3), control1: CGPoint(x: 27, y: 55), control2: CGPoint(x: 30+b*1.8, y: 50+c))
            cut.addCurve(to: CGPoint(x: 38, y: 57), control1: CGPoint(x: 33+b, y: 52), control2: CGPoint(x: 34, y: 57))
            cut.addCurve(to: CGPoint(x: 40, y: 54), control1: CGPoint(x: 38, y: 54), control2: CGPoint(x: 40, y: 53))
            cut.addCurve(to: CGPoint(x: 35, y: 76), control1: CGPoint(x: 45, y: 65), control2: CGPoint(x: 42, y: 72))
            cut.closeSubpath()

        default:
            let tipX = 36+a*3.3, tipY = 5+b*1.6, lx = 15+b*1.6, ly = 24+c*3, rx = 51+c*1.7, ry = 29-b*3
            outer.move(to: CGPoint(x: 32, y: 73))
            outer.addCurve(to: CGPoint(x: 5, y: 50), control1: CGPoint(x: 15, y: 73), control2: CGPoint(x: 5, y: 64))
            outer.addCurve(to: CGPoint(x: lx, y: ly), control1: CGPoint(x: 5, y: 40), control2: CGPoint(x: lx-1, y: ly+9))
            outer.addCurve(to: CGPoint(x: 22, y: 40), control1: CGPoint(x: lx+4, y: ly+3), control2: CGPoint(x: 15, y: 37))
            outer.addCurve(to: CGPoint(x: 24, y: 20), control1: CGPoint(x: 25, y: 35), control2: CGPoint(x: 19, y: 28))
            outer.addCurve(to: CGPoint(x: tipX, y: tipY), control1: CGPoint(x: 28, y: 13), control2: CGPoint(x: tipX-1, y: tipY+2))
            outer.addCurve(to: CGPoint(x: 42, y: 33), control1: CGPoint(x: tipX-2, y: 15), control2: CGPoint(x: 34, y: 27))
            outer.addCurve(to: CGPoint(x: rx, y: ry), control1: CGPoint(x: 45, y: 35), control2: CGPoint(x: rx-1, y: ry+4))
            outer.addCurve(to: CGPoint(x: 51, y: 47), control1: CGPoint(x: rx+6, y: ry+7), control2: CGPoint(x: 49, y: 43))
            outer.addCurve(to: CGPoint(x: 58, y: 38), control1: CGPoint(x: 54, y: 49), control2: CGPoint(x: 57, y: 42))
            outer.addCurve(to: CGPoint(x: 32, y: 73), control1: CGPoint(x: 63, y: 57), control2: CGPoint(x: 52, y: 73))
            outer.closeSubpath()
            cut.move(to: CGPoint(x: 29, y: 76))
            cut.addCurve(to: CGPoint(x: 23, y: 56), control1: CGPoint(x: 20, y: 70), control2: CGPoint(x: 19, y: 62))
            cut.addCurve(to: CGPoint(x: 28, y: 60), control1: CGPoint(x: 24, y: 62), control2: CGPoint(x: 27, y: 63))
            cut.addCurve(to: CGPoint(x: 34+b*2, y: 44+c*1.4), control1: CGPoint(x: 29, y: 54), control2: CGPoint(x: 31+b*2, y: 47+c))
            cut.addCurve(to: CGPoint(x: 38, y: 58), control1: CGPoint(x: 33, y: 51), control2: CGPoint(x: 37, y: 54))
            cut.addCurve(to: CGPoint(x: 42, y: 52), control1: CGPoint(x: 40, y: 58), control2: CGPoint(x: 42, y: 54))
            cut.addCurve(to: CGPoint(x: 35, y: 76), control1: CGPoint(x: 47, y: 63), control2: CGPoint(x: 42, y: 73))
            cut.closeSubpath()

        }
        return (outer, cut)
    }
}


struct FlameMenuLabel: View {
    var score: Double
    var isAnimating: Bool
    @StateObject private var frames = MenuFlameFrames()
    var body: some View {
        Image(nsImage: frames.image)
            .onAppear { frames.score = score; frames.running = isAnimating }
            .onChange(of: score) { frames.score = $0 }
            .onChange(of: isAnimating) { frames.running = $0 }
    }
}

@MainActor private final class MenuFlameFrames: ObservableObject {
    @Published var image = NSImage(size: NSSize(width: 17, height: 21))
    var score = 0.0 { didSet { draw() } }
    var running = true
    private var phase = 0.0
    private var last = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    init() {
        draw()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    deinit { timer?.invalidate() }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, now - last)
        last = now
        guard running, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        phase = (phase + dt * FlameMotion.frequency(score) * 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        draw()
    }
    private func draw() {
        let level = FlameMotion.level(score)
        let paths = FlameGeometry.paths(level: level, phase: phase, score: score)
        let result = NSImage(size: NSSize(width: 17, height: 21), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.scaleBy(x: rect.width / 64, y: rect.height / 80)
            let k = [1.0, 0.73, 0.95][level]
            context.translateBy(x: 32 * (1-k), y: 73 * (1-k))
            context.scaleBy(x: k, y: k)
            context.addPath(paths.0.cgPath)
            context.clip()
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(paths.0.cgPath)
            context.fillPath()
            context.setBlendMode(.clear)
            context.addPath(paths.1.cgPath)
            context.fillPath()
            context.restoreGState()
            return true
        }
        result.isTemplate = true
        image = result
    }
}
