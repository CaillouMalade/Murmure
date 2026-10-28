import AppKit
import XCTest
@testable import Murmure
import MurmureCore

final class SettingsTests: XCTestCase {
    func testSettingsTabsRenderWithoutActivatingAWindow() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let controller = SettingsWindow(settings: AppSettings(), localRoot: URL(fileURLWithPath: "/tmp/Murmure-test-local")) { _ in }
            let window = try XCTUnwrap(controller.window), content = try XCTUnwrap(window.contentView)
            defer { window.close() }
            func findTabs(_ view: NSView) -> NSTabView? {
                if let tabs = view as? NSTabView { return tabs }
                for child in view.subviews { if let tabs = findTabs(child) { return tabs } }
                return nil
            }
            let tabs = try XCTUnwrap(findTabs(content)); XCTAssertEqual(tabs.numberOfTabViewItems, 3)
            XCTAssertFalse(window.isVisible)
            for (index, name) in ["recordings", "dictation", "summaries"].enumerated() {
                tabs.selectTabViewItem(at: index); content.layoutSubtreeIfNeeded()
                let scroll = try XCTUnwrap(tabs.selectedTabViewItem?.view as? NSScrollView)
                XCTAssertGreaterThan(scroll.bounds.width, 400); XCTAssertTrue(scroll.hasVerticalScroller)
                if let directory = ProcessInfo.processInfo.environment["MURMURE_SNAPSHOT_DIR"] {
                    let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let root = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try data.write(to: root.appendingPathComponent("settings-" + name + ".png"))
                }
            }
        }
    }
}
