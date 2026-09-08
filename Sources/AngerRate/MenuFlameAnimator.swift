// Contains portions adapted from RunCat Neo, Copyright 2026 Kyome22 (Takuto Nakamura).
// Those portions are licensed under Apache-2.0; see THIRD_PARTY_NOTICES.md.
import AppKit
import QuartzCore
import AngerCore

/// Uses RunCat Neo's cached-contents/mask animation approach; see docs/PERFORMANCE.md.
/// The flame geometry is AngerRate's own. No per-frame app timer or image-view updates.
@MainActor final class MenuFlameAnimator {
    let layer = CALayer()
    private let maskLayer = CALayer()
    private let now: () -> CFTimeInterval
    private var phase = 0.0
    private var lastTime: CFTimeInterval
    private var frameScore: Int?
    private(set) var cachedFrames: [CGImage] = []
    private(set) var image = NSImage(size: NSSize(width: 17, height: 21))
    var onImage: ((NSImage) -> Void)?
    var score = 0.0 {
        willSet { advanceClock() }
        didSet { if oldValue != score { refresh() } }
    }
    var running = false {
        willSet { advanceClock() }
        didSet { refresh() }
    }
    var reduceMotion = false {
        willSet { advanceClock() }
        didSet { refresh() }
    }
    var screenAwake = true {
        willSet { advanceClock() }
        didSet { refresh() }
    }
    var isAnimating: Bool { running && !reduceMotion && screenAwake }
    var currentPhase: Double {
        let elapsed = isAnimating ? max(0, now() - lastTime) * FlameMotion.frequency(score) : 0
        return (phase + elapsed).truncatingRemainder(dividingBy: 1)
    }
    var contentsAnimation: CAKeyframeAnimation? {
        maskLayer.animation(forKey: "flame") as? CAKeyframeAnimation
    }

    init(now: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.now = now
        lastTime = now()
        layer.frame = CGRect(x: 0, y: 0, width: 17, height: 21)
        layer.contentsScale = 2
        maskLayer.frame = layer.bounds
        maskLayer.contentsScale = 2
        layer.mask = maskLayer
        layer.backgroundColor = NSColor.labelColor.cgColor
        refresh()
    }

    private func advanceClock() {
        phase = currentPhase
        lastTime = now()
    }

    func setTint(_ color: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color
        CATransaction.commit()
    }

    private func refresh() {
        let bucket = Int(min(100, max(0, score)))
        let changedFrames = frameScore != bucket
        if changedFrames {
            // Only the current integer score's cycle is retained (24 small 2x images).
            // The exact score continues to control speed; all 33/66 band boundaries remain exact.
            let frames = (0..<24).compactMap { Self.render(score: Double(bucket), phase: Double($0) / 24 * 2 * .pi) }
            guard frames.count == 24 else { return }
            cachedFrames = frames
            frameScore = bucket
            image = NSImage(cgImage: frames[0], size: NSSize(width: 17, height: 21))
            image.isTemplate = true
            onImage?(image)
        }
        guard !cachedFrames.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if changedFrames || contentsAnimation == nil {
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = cachedFrames + [cachedFrames[0]]
            animation.keyTimes = (0...24).map { NSNumber(value: Double($0) / 24) }
            animation.duration = 1
            // Explicit past cycle epoch: unlike zero, CA will not replace it with insertion time.
            animation.beginTime = -1
            animation.calculationMode = .discrete
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            maskLayer.add(animation, forKey: "flame")
        }
        maskLayer.contents = cachedFrames[Int(currentPhase * 24) % 24]
        // Rebase local layer time before changing speed; phase never resets on score/pause changes.
        maskLayer.timeOffset = currentPhase
        maskLayer.beginTime = layer.convertTime(now(), from: nil)
        maskLayer.speed = isAnimating ? Float(FlameMotion.frequency(score)) : 0
        CATransaction.commit()
    }

    private static func render(score: Double, phase: Double) -> CGImage? {
        guard let context = CGContext(data: nil, width: 34, height: 42,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let level = FlameMotion.level(score)
        let paths = FlameGeometry.paths(level: level, phase: phase, score: score)
        context.translateBy(x: 0, y: 42)
        context.scaleBy(x: 34.0 / 64, y: -42.0 / 80)
        let scale = [1.0, 0.73, 0.95][level]
        context.translateBy(x: 32 * (1 - scale), y: 73 * (1 - scale))
        context.scaleBy(x: scale, y: scale)
        context.addPath(paths.0.cgPath)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(paths.0.cgPath)
        context.fillPath()
        context.setBlendMode(.clear)
        context.addPath(paths.1.cgPath)
        context.fillPath()
        return context.makeImage()
    }
}
