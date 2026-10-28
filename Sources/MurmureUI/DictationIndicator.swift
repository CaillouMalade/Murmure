import AppKit
import QuartzCore

/// A native menu-bar control, with no display link or idle animation.
@MainActor
public final class DictationIndicator: NSView {
    public static let preferredSize = NSSize(width: 58, height: 24)
    public enum Phase { case idle, preparing, listening, processing }
    public private(set) var phase = Phase.idle
    private let capsule = CALayer()
    private var bars: [CALayer] = []
    private let heights: [CGFloat] = [5, 7.5, 9, 8, 6, 4.5]
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet { applyPhase() }
    }
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(capsule)
        capsule.backgroundColor = NSColor.black.cgColor
        capsule.borderColor = NSColor(white: 0.14, alpha: 1).cgColor
        capsule.borderWidth = 0.75
        for _ in heights {
            let bar = CALayer(); bar.backgroundColor = NSColor.white.cgColor
            capsule.addSublayer(bar); bars.append(bar)
        }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
    public override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        capsule.frame = bounds.insetBy(dx: 1, dy: 1)
        capsule.cornerRadius = capsule.bounds.height / 2
        let width: CGFloat = 2, gap: CGFloat = 1.8
        let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * gap
        for (index, bar) in bars.enumerated() {
            let height = heights[index]
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            bar.position = CGPoint(x: (capsule.bounds.width - total) / 2 + CGFloat(index) * (width + gap) + width / 2, y: capsule.bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }
    public func setPhase(_ value: Phase) {
        guard phase != value else { return }
        phase = value; applyPhase()
    }
    private func applyPhase() {
        for bar in bars { bar.removeAllAnimations() }
        capsule.removeAllAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for bar in bars { bar.transform = CATransform3DIdentity; bar.opacity = phase == .preparing ? 0.5 : 1 }
        CATransaction.commit()
        guard !reduceMotion, phase == .processing || phase == .preparing else { return }
        for (index, bar) in bars.enumerated() {
            let wave = CAKeyframeAnimation(keyPath: "transform.scale.y")
            wave.values = [0.55, 1.15, 0.55]; wave.keyTimes = [0, 0.45, 1]
            wave.duration = 0.95; wave.repeatCount = .infinity
            wave.beginTime = CACurrentMediaTime() + Double(index) * 0.075
            wave.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            bar.add(wave, forKey: "processing")
        }
    }
    public func setLevel(_ value: Float) {
        guard phase == .listening, !reduceMotion else { return }
        let level = CGFloat(max(0, min(1, value)))
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(0.09)
        for (index, bar) in bars.enumerated() {
            let shape = CGFloat([0.5, 0.8, 1, 0.9, 0.65, 0.4][index])
            bar.transform = CATransform3DMakeScale(1, 0.5 + level * shape * 0.8, 1)
        }
        CATransaction.commit()
    }
    public var hasActiveAnimations: Bool { bars.contains { !($0.animationKeys() ?? []).isEmpty } }
}
