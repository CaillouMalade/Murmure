import AppKit
import QuartzCore
import XCTest
@testable import MurmureUI

final class IndicatorTests: XCTestCase {
    func testAnimationStopsAndReduceMotionIsStatic() async throws {
        await MainActor.run {
            let view = DictationIndicator(frame: NSRect(x: 0, y: 0, width: 70, height: 24))
            view.reduceMotion = false; view.setPhase(.processing)
            XCTAssertTrue(view.hasActiveAnimations)
            view.setPhase(.idle); XCTAssertFalse(view.hasActiveAnimations)
            view.setPhase(.listening); view.setLevel(0.7); XCTAssertFalse(view.hasActiveAnimations)
            view.reduceMotion = true; view.setPhase(.processing); XCTAssertFalse(view.hasActiveAnimations)
        }
    }
    func testNativeIndicatorSnapshots() async throws {
        try await MainActor.run {
            guard let directory = ProcessInfo.processInfo.environment["MURMURE_SNAPSHOT_DIR"] else { return }
            let root = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let view = DictationIndicator(frame: NSRect(x: 0, y: 0, width: 70, height: 24))
            view.reduceMotion = true; view.needsLayout = true; view.layoutSubtreeIfNeeded()
            for (name, phase) in [("listening", DictationIndicator.Phase.listening), ("processing", .processing)] {
                view.setPhase(phase); view.setLevel(0.65)
                let width = 420, height = 144
                let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.scaleBy(x: 6, y: 6)
                view.layer!.render(in: context)
                let image = context.makeImage()!
                XCTAssertEqual(image.width, width); XCTAssertEqual(image.height, height)
                let bitmap = NSBitmapImageRep(cgImage: image)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: root.appendingPathComponent(name + ".png"))
            }
        }
    }
}
