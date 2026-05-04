import AppKit

// MARK: - SearchViewController
// The floating panel's content: a search field on top, clip list below.
// The search field always holds focus; ↑↓/Enter/Esc are intercepted via delegate.

final class SearchViewController: NSViewController {

    var onPaste:   ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private var clips: [ClipStore.Clip] = []
    private var searchField: NSTextField!
    private var tableView:   NSTableView!
    private var scrollView:  NSScrollView!
    private var emptyLabel:  NSTextField!

    // MARK: - View lifecycle

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        root.blendingMode  = .behindWindow
        root.material      = .hudWindow
        root.state         = .active
        root.wantsLayer    = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        view = root

        setupSearchField()
        setupSeparator()
        setupTableView()
        setupEmptyLabel()
        setupKeyboardShortcutHint()
    }

    private func setupSearchField() {
        searchField = NSTextField(frame: .zero)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search clipboard history…"
        searchField.isBordered        = false
        searchField.drawsBackground   = false
        searchField.focusRingType     = .none
        searchField.font              = .systemFont(ofSize: 15, weight: .regular)
        searchField.textColor         = .labelColor
        searchField.delegate          = self
        view.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    private func setupSeparator() {
        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .separator
        view.addSubview(sep)
        NSLayoutConstraint.activate([
            sep.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            sep.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func setupTableView() {
        tableView = NSTableView()
        tableView.headerView              = nil
        tableView.rowHeight               = 50
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection    = false
        tableView.focusRingType           = .none
        tableView.backgroundColor         = .clear
        tableView.intercellSpacing        = NSSize(width: 0, height: 0)
        tableView.usesAutomaticRowHeights = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        col.isEditable = false
        tableView.addTableColumn(col)

        tableView.delegate   = self
        tableView.dataSource = self
        tableView.target     = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView     = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground  = false
        scrollView.borderType       = .noBorder
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 52),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -28),
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel = NSTextField(labelWithString: "No clips found")
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor  = .tertiaryLabelColor
        emptyLabel.font       = .systemFont(ofSize: 13)
        emptyLabel.isHidden   = true
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 14),
        ])
    }

    private func setupKeyboardShortcutHint() {
        let hint = NSTextField(labelWithString: "↑↓ navigate   ↩ paste   ⌘P pin   ⌘⌫ delete   esc dismiss")
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.textColor  = .quaternaryLabelColor
        hint.font       = .systemFont(ofSize: 10)
        hint.alignment  = .center
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            hint.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
    }

    // MARK: - Display

    func prepareForDisplay() {
        searchField.stringValue = ""
        reload(query: "")
        view.window?.makeFirstResponder(searchField)
    }

    func reset() {
        searchField.stringValue = ""
        clips = []
        tableView.reloadData()
    }

    private func reload(query: String) {
        clips = query.isEmpty
            ? ClipStore.shared.recent(limit: 200)
            : ClipStore.shared.search(query: query, limit: 200)
        tableView.reloadData()
        emptyLabel.isHidden = !clips.isEmpty
        if !clips.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - Actions

    @objc private func rowDoubleClicked() { pasteSelected() }

    private func pasteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < clips.count else { return }
        onPaste?(clips[row].content)
    }

    private func moveSelection(by delta: Int) {
        guard !clips.isEmpty else { return }
        let next = max(0, min(clips.count - 1, tableView.selectedRow + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < clips.count else { return }
        ClipStore.shared.delete(id: clips[row].id)
        reload(query: searchField.stringValue)
        NotificationCenter.default.post(name: .clipStoreDidChange, object: nil)
    }

    private func togglePinSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < clips.count else { return }
        ClipStore.shared.togglePin(id: clips[row].id)
        reload(query: searchField.stringValue)
        NotificationCenter.default.post(name: .clipStoreDidChange, object: nil)
    }
}

// MARK: - NSTextFieldDelegate

extension SearchViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        reload(query: searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            pasteSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?(); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1); return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1); return true
        case #selector(NSResponder.deleteBackward(_:)) where
            NSApp.currentEvent?.modifierFlags.contains(.command) == true:
            deleteSelected(); return true
        default:
            // ⌘P for pin (performKeyEquivalent doesn't fire in delegate; catch it here)
            if let e = NSApp.currentEvent,
               e.type == .keyDown,
               e.keyCode == 35,   // P
               e.modifierFlags.contains(.command) {
                togglePinSelected(); return true
            }
            return false
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension SearchViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { clips.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = ClipCellView()
        cell.configure(with: clips[row])
        return cell
    }
}

// MARK: - ClipCellView

final class ClipCellView: NSView {
    private let preview   = NSTextField(labelWithString: "")
    private let timestamp = NSTextField(labelWithString: "")
    private let pinIcon   = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        preview.translatesAutoresizingMaskIntoConstraints   = false
        timestamp.translatesAutoresizingMaskIntoConstraints = false
        pinIcon.translatesAutoresizingMaskIntoConstraints   = false

        preview.font              = .systemFont(ofSize: 13)
        preview.textColor         = .labelColor
        preview.lineBreakMode     = .byTruncatingTail
        preview.maximumNumberOfLines = 1

        timestamp.font            = .systemFont(ofSize: 11)
        timestamp.textColor       = .secondaryLabelColor
        timestamp.alignment       = .right

        pinIcon.image             = NSImage(systemSymbolName: "pin.fill",
                                           accessibilityDescription: nil)
        pinIcon.contentTintColor  = .systemOrange
        pinIcon.imageScaling      = .scaleProportionallyDown

        [preview, timestamp, pinIcon].forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            timestamp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            timestamp.centerYAnchor.constraint(equalTo: centerYAnchor),
            timestamp.widthAnchor.constraint(equalToConstant: 72),

            pinIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            pinIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: 10),
            pinIcon.heightAnchor.constraint(equalToConstant: 12),

            preview.leadingAnchor.constraint(equalTo: pinIcon.trailingAnchor, constant: 6),
            preview.trailingAnchor.constraint(equalTo: timestamp.leadingAnchor, constant: -8),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with clip: ClipStore.Clip) {
        let oneLiner = clip.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ↵ ")
        preview.stringValue   = oneLiner
        timestamp.stringValue = relativeTime(clip.ts)
        pinIcon.isHidden      = !clip.pinned
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        switch s {
        case 0..<60:     return "now"
        case 60..<3600:  return "\(s / 60)m"
        case 3600..<86400: return "\(s / 3600)h"
        case 86400..<604800: return "\(s / 86400)d"
        default:
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return f.string(from: date)
        }
    }
}
