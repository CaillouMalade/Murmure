import AppKit

@MainActor
final class TranscriptWindow: NSWindowController {
    private let text: String
    private let file: URL
    init(text: String, file: URL, notice: String? = nil) {
        self.text = text; self.file = file
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Murmure Transcript"; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 400, height: 280)
        super.init(window: window)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = NSTextView(); view.isEditable = false; view.isSelectable = true; view.string = text
        view.font = .systemFont(ofSize: 15); view.textContainerInset = NSSize(width: 16, height: 16)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyText))
        let reveal = NSButton(title: "Show file", target: self, action: #selector(revealFile))
        let buttons = NSStackView(views: [reveal, NSView(), copy]); buttons.orientation = .horizontal
        scroll.translatesAutoresizingMaskIntoConstraints = false; buttons.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(scroll); content.addSubview(buttons)
            if let notice, !notice.isEmpty {
                let label = NSTextField(wrappingLabelWithString: notice); label.textColor = .secondaryLabelColor
                label.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(label)
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), label.topAnchor.constraint(equalTo: content.topAnchor, constant: 14), scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8)])
            } else { scroll.topAnchor.constraint(equalTo: content.topAnchor).isActive = true }
            NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12), buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)])
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func copyText() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    @objc private func revealFile() { NSWorkspace.shared.activateFileViewerSelecting([file]) }
}
