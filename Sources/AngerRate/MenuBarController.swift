// Contains portions adapted from RunCat Neo, Copyright 2026 Kyome22 (Takuto Nakamura).
// Those portions are licensed under Apache-2.0; see THIRD_PARTY_NOTICES.md.
import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import AngerCore

/// Keep animation updates out of SwiftUI's menu-label snapshot/layout pipeline.
@MainActor final class MenuBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let frames = MenuFlameAnimator()
    private var iconView: MenuIconView?
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        item.length = 35
        if let button = item.button {
#if arch(arm64)
            button.image = frames.image
#endif
            button.wantsLayer = true
            let host = MenuIconView(frame: button.bounds, animator: frames)
            host.autoresizingMask = [.width, .height]
            button.addSubview(host)
            iconView = host
        }
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        // Static template is the fallback on inactive displays; active display uses the layer.
        frames.onImage = { [weak self] image in
#if arch(arm64)
            self?.item.button?.image = image
#endif
        }
        model.$score.removeDuplicates().sink { [weak self] score in
            self?.frames.score = score
            self?.updateAccessibility(score: score)
        }.store(in: &subscriptions)
        model.$isMonitoring.removeDuplicates().sink { [weak self] in
            self?.frames.running = $0
        }.store(in: &subscriptions)
        model.$appLanguage.removeDuplicates().sink { [weak self] language in
            guard let self else { return }
            self.updateAccessibility(score: self.model.score, language: language)
        }.store(in: &subscriptions)
        frames.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        observe(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { controller in
            controller.frames.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        observe(NSWorkspace.screensDidSleepNotification) { $0.frames.screenAwake = false }
        observe(NSWorkspace.screensDidWakeNotification) { $0.frames.screenAwake = true }
        observe(NSWorkspace.willSleepNotification) { $0.frames.screenAwake = false }
        observe(NSWorkspace.didWakeNotification) { $0.frames.screenAwake = true }
    }

    private func observe(_ name: Notification.Name, action: @escaping @MainActor (MenuBarController) -> Void) {
        let token = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        workspaceObservers.append(token)
    }

    private func updateAccessibility(score: Double, language: AppLanguage? = nil) {
        let label = AppText(language ?? model.appLanguage)("분노 정도", "Anger level") + " \(Int(score))"
        item.button?.setAccessibilityLabel(label)
        item.button?.toolTip = label
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Destroy the hidden panel so its TimelineView cannot keep rendering.
            popover.contentViewController = NSHostingController(rootView: MainPanel(model: model))
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    deinit {
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}

/// Empty host handles appearance and layout only; Core Animation owns frame playback.
private final class MenuIconView: NSView {
    private let animator: MenuFlameAnimator
    private let eraser = CALayer()

    init(frame: NSRect, animator: MenuFlameAnimator) {
        self.animator = animator
        super.init(frame: frame)
        wantsLayer = true
#if arch(arm64)
        // RunCat Neo's static-fallback erasing approach, adapted for our native status item.
        let filter = CIFilter.sourceOutCompositing()
        filter.backgroundImage = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 17, height: 21))
        eraser.backgroundFilters = [filter]
        layer?.addSublayer(eraser)
#endif
        layer?.addSublayer(animator.layer)
        layout()
        updateTint()
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = CGRect(x: (bounds.width - 17) / 2, y: (bounds.height - 21) / 2, width: 17, height: 21)
        eraser.frame = rect
        animator.layer.frame = rect
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTint()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTint()
    }
    private func updateTint() {
        (window?.effectiveAppearance ?? effectiveAppearance).performAsCurrentDrawingAppearance {
            animator.setTint(NSColor.textColor.cgColor)
        }
    }
}
