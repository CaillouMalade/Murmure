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
            @MainActor func findTabs(_ view: NSView) -> NSTabView? {
                if let tabs = view as? NSTabView { return tabs }
                for child in view.subviews { if let tabs = findTabs(child) { return tabs } }
                return nil
            }
            let tabs = try XCTUnwrap(findTabs(content)); XCTAssertEqual(tabs.numberOfTabViewItems, 4)
            XCTAssertFalse(window.isVisible)
            for (index, name) in ["setup", "recordings", "dictation", "summaries"].enumerated() {
                tabs.selectTabViewItem(at: index); content.layoutSubtreeIfNeeded()
                let scroll = try XCTUnwrap(tabs.selectedTabViewItem?.view as? NSScrollView)
                XCTAssertGreaterThan(scroll.bounds.width, 400); XCTAssertTrue(scroll.hasVerticalScroller)
                @MainActor func checkGrids(_ view: NSView) {
                    if let grid = view as? NSGridView {
                        XCTAssertEqual(grid.column(at: 0).width, 160)
                        XCTAssertGreaterThan(grid.cell(atColumnIndex: 1, rowIndex: 0).contentView?.frame.width ?? 0, 250)
                    }
                    for child in view.subviews { checkGrids(child) }
                }
                if let document = scroll.documentView { checkGrids(document) }
                if let directory = ProcessInfo.processInfo.environment["MURMURE_SNAPSHOT_DIR"] {
                    let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let root = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try data.write(to: root.appendingPathComponent("settings-" + name + ".png"))
                    if name == "setup", let document = scroll.documentView {
                        document.scroll(NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                        content.layoutSubtreeIfNeeded()
                        let bottom = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                        content.cacheDisplay(in: content.bounds, to: bottom)
                        try XCTUnwrap(bottom.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("settings-setup-model.png"))
                    }
                }
            }
        }
    }
    func testRecoveryWindowRendersNoticeWithoutBecomingVisible() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let controller = TranscriptWindow(text: "Bonjour, café et décisions.", file: URL(fileURLWithPath: "/tmp/transcript.md"), notice: "The editor did not confirm text insertion. Check the field before using Copy to avoid inserting it twice.")
            let window = try XCTUnwrap(controller.window), content = try XCTUnwrap(window.contentView)
            defer { window.close() }
            content.layoutSubtreeIfNeeded(); XCTAssertFalse(window.isVisible)
            if let directory = ProcessInfo.processInfo.environment["MURMURE_SNAPSHOT_DIR"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("dictation-recovery.png"))
            }
        }
    }
}
