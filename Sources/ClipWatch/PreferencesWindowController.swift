import AppKit
import ServiceManagement

// MARK: - PreferencesWindowController

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private init() {
        let vc = PreferencesViewController()
        let win = NSWindow(contentViewController: vc)
        win.title = "ClipWatch Preferences"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 560, height: 500))
        win.minSize = NSSize(width: 460, height: 400)
        win.center()
        super.init(window: win)
        win.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
    }
}

// MARK: - PreferencesViewController
//
// Full Auto Layout implementation:
//   • All fixed controls live in a vertical NSStackView pinned to the top.
//   • The excluded-apps scroll view is pinned to the bottom of the controls
//     stack and to the bottom of the view, so it expands and contracts as the
//     window is resized.
//   • The +/− buttons sit at the bottom-trailing corner of the view.

final class PreferencesViewController: NSViewController {

    private var shortcutField:    ShortcutRecorderField!
    private var menuCountStepper: NSStepper!
    private var menuCountLabel:   NSTextField!
    private var retentionSlider:  NSSlider!
    private var retentionLabel:   NSTextField!
    private var screenSegment:    NSSegmentedControl!
    private var loginToggle:      NSButton!
    private var excludedTable:    NSTableView!
    private var excludedList:     [String] = []

    private let margin: CGFloat       = 20
    private let labelWidth: CGFloat   = 180

    override func loadView() {
        view = NSView()
        buildUI()
        loadValues()
    }

    // MARK: - UI construction

    private func buildUI() {
        // ── Top controls stack ────────────────────────────────────────────────
        let controlsStack = NSStackView()
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.orientation = .vertical
        controlsStack.alignment   = .leading
        controlsStack.spacing     = 8
        view.addSubview(controlsStack)

        // Hotkey
        controlsStack.addArrangedSubview(sectionHeader("Hotkey"))
        shortcutField = ShortcutRecorderField(frame: .zero)
        shortcutField.translatesAutoresizingMaskIntoConstraints = false
        shortcutField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        shortcutField.heightAnchor.constraint(equalToConstant: 26).isActive = true
        controlsStack.addArrangedSubview(makeRow("Open panel", shortcutField))
        controlsStack.setCustomSpacing(14, after: controlsStack.arrangedSubviews.last!)

        // Menu
        controlsStack.addArrangedSubview(sectionHeader("Menu"))
        menuCountLabel   = NSTextField(labelWithString: "10")
        menuCountStepper = NSStepper()
        menuCountStepper.minValue = 5; menuCountStepper.maxValue = 25
        menuCountStepper.increment = 1
        menuCountStepper.target = self; menuCountStepper.action = #selector(stepperChanged)
        let stepperStack = NSStackView(views: [menuCountLabel, menuCountStepper])
        stepperStack.orientation = .horizontal; stepperStack.spacing = 4
        controlsStack.addArrangedSubview(makeRow("Recent items in menu", stepperStack))
        controlsStack.setCustomSpacing(14, after: controlsStack.arrangedSubviews.last!)

        // History
        controlsStack.addArrangedSubview(sectionHeader("History"))
        retentionLabel = NSTextField(labelWithString: "365 days")
        retentionLabel.translatesAutoresizingMaskIntoConstraints = false
        retentionLabel.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        retentionSlider = NSSlider()
        retentionSlider.minValue = 30; retentionSlider.maxValue = 730
        retentionSlider.target = self; retentionSlider.action = #selector(sliderChanged)
        retentionSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlsStack.addArrangedSubview(makeRow(retentionLabel, retentionSlider))

        // Panel screen
        screenSegment = NSSegmentedControl(
            labels: ["Active App", "Cursor"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(screenModeChanged)
        )
        controlsStack.addArrangedSubview(makeRow("Panel appears on", screenSegment))
        controlsStack.setCustomSpacing(14, after: controlsStack.arrangedSubviews.last!)

        // Login at login
        loginToggle = NSButton(checkboxWithTitle: "Launch ClipWatch at login",
                               target: self, action: #selector(loginToggled))
        controlsStack.addArrangedSubview(loginToggle)
        controlsStack.setCustomSpacing(18, after: controlsStack.arrangedSubviews.last!)

        // Excluded apps header (last item in fixed stack)
        controlsStack.addArrangedSubview(sectionHeader("Never capture from these apps"))

        // ── Excluded apps scroll view (expands with window) ───────────────────
        excludedTable = NSTableView()
        excludedTable.headerView    = nil
        excludedTable.rowHeight     = 18
        excludedTable.focusRingType = .none
        let exCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bundleID"))
        exCol.isEditable = false
        excludedTable.addTableColumn(exCol)
        excludedTable.delegate   = self
        excludedTable.dataSource = self

        let exScroll = NSScrollView()
        exScroll.translatesAutoresizingMaskIntoConstraints = false
        exScroll.documentView        = excludedTable
        exScroll.hasVerticalScroller = true
        exScroll.borderType          = .bezelBorder
        view.addSubview(exScroll)

        // ── +/− buttons ───────────────────────────────────────────────────────
        let addBtn = NSButton(title: "+", target: self, action: #selector(addExcluded))
        addBtn.bezelStyle = .regularSquare
        let remBtn = NSButton(title: "−", target: self, action: #selector(removeExcluded))
        remBtn.bezelStyle = .regularSquare
        let btnRow = NSStackView(views: [addBtn, remBtn])
        btnRow.translatesAutoresizingMaskIntoConstraints = false
        btnRow.orientation = .horizontal
        btnRow.spacing = 4
        view.addSubview(btnRow)

        // ── Constraints ───────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // Controls stack: flush to top-left, full width
            controlsStack.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            controlsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            controlsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),

            // Scroll view: below controls, fills remaining height
            exScroll.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 8),
            exScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            exScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            exScroll.bottomAnchor.constraint(equalTo: btnRow.topAnchor, constant: -6),

            // Buttons: bottom-trailing corner
            btnRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            btnRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -margin),
        ])
    }

    // MARK: - Layout helpers

    private func sectionHeader(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .boldSystemFont(ofSize: 13)
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }

    /// Two-column row: fixed-width string label on the left, control on the right.
    private func makeRow(_ labelText: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: labelText)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        return makeRow(label, control)
    }

    /// Two-column row: arbitrary left view + control on the right.
    private func makeRow(_ left: NSView, _ right: NSView) -> NSView {
        left.translatesAutoresizingMaskIntoConstraints  = false
        right.translatesAutoresizingMaskIntoConstraints = false
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [left, right])
        stack.orientation  = .horizontal
        stack.alignment    = .centerY
        stack.spacing      = 12
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: - Load / Save values

    private func loadValues() {
        shortcutField.loadFromDefaults()

        let count = Prefs.menuCount()
        menuCountStepper.intValue  = Int32(count)
        menuCountLabel.stringValue = "\(count)"

        let days = UserDefaults.standard.integer(forKey: Prefs.retentionDays)
        retentionSlider.intValue   = Int32(days > 0 ? days : 365)
        retentionLabel.stringValue = "\(retentionSlider.intValue) days"

        screenSegment.selectedSegment = Prefs.screenMode() == "cursor" ? 1 : 0

        excludedList = UserDefaults.standard.stringArray(forKey: Prefs.excludedApps)
            ?? Prefs.defaultExcludedApps
        excludedTable.reloadData()

        if #available(macOS 13.0, *) {
            loginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func stepperChanged() {
        let v = Int(menuCountStepper.intValue)
        menuCountLabel.stringValue = "\(v)"
        UserDefaults.standard.set(v, forKey: Prefs.menuItemCount)
        NotificationCenter.default.post(name: .clipStoreDidChange, object: nil)
    }

    @objc private func sliderChanged() {
        let v = Int(retentionSlider.intValue)
        retentionLabel.stringValue = "\(v) days"
        UserDefaults.standard.set(v, forKey: Prefs.retentionDays)
    }

    @objc private func screenModeChanged() {
        let mode = screenSegment.selectedSegment == 0 ? "activeApp" : "cursor"
        UserDefaults.standard.set(mode, forKey: Prefs.screenFocusMode)
    }

    @objc private func loginToggled() {
        if #available(macOS 13.0, *) {
            do {
                if loginToggle.state == .on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }

    @objc private func addExcluded() {
        let alert = NSAlert()
        alert.messageText     = "Add excluded app"
        alert.informativeText = "Enter the bundle identifier (e.g. com.apple.Safari):"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let id = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !excludedList.contains(id) else { return }
        excludedList.append(id)
        saveExcluded()
        excludedTable.reloadData()
    }

    @objc private func removeExcluded() {
        let row = excludedTable.selectedRow
        guard row >= 0 else { return }
        excludedList.remove(at: row)
        saveExcluded()
        excludedTable.reloadData()
    }

    private func saveExcluded() {
        UserDefaults.standard.set(excludedList, forKey: Prefs.excludedApps)
    }
}

// MARK: - Excluded apps table

extension PreferencesViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { excludedList.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let f = NSTextField(labelWithString: excludedList[row])
        f.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        return f
    }
}

// MARK: - ShortcutRecorderField
//
// Custom NSControl (NOT NSTextField) so mouseDown and keyDown are delivered
// directly without going through the field-editor machinery.
//
// Usage:
//   1. Click the control — it enters recording mode (accent border, prompt text)
//   2. Press any key combo with at least one modifier — saves and exits recording
//   3. Press Esc without a modifier — cancels recording without changing the hotkey

final class ShortcutRecorderField: NSControl {

    private let keyNames: [Int: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
        11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",
        31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",
        18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",25:"9",26:"7",28:"8",29:"0",
        47:".",44:"/",27:"-",24:"=",33:"[",30:"]",
        48:"Tab",49:"Space",36:"↩",51:"⌫",53:"Esc",
        123:"←",124:"→",125:"↓",126:"↑",
    ]

    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius    = 5
        layer?.borderWidth     = 1
        applyBorderColor()
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    func loadFromDefaults() { needsDisplay = true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text: String
        let color: NSColor
        if isRecording {
            text  = "Press shortcut…"
            color = .secondaryLabelColor
        } else {
            let kc   = Prefs.hotkeyVirtualKey()
            let mods = NSEvent.ModifierFlags(rawValue: UInt(Prefs.hotkeyModifierFlags()))
            text  = describe(keyCode: kc, modifiers: mods)
            color = .labelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 13),
            .foregroundColor: color,
        ]
        let s  = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width  - sz.width)  / 2,
                           y: (bounds.height - sz.height) / 2))
    }

    // MARK: - Focus

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isRecording = true
        applyBorderColor()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isRecording = false
        applyBorderColor()
        needsDisplay = true
        return true
    }

    private func applyBorderColor() {
        layer?.borderColor = (isRecording
            ? NSColor.controlAccentColor
            : NSColor.separatorColor).cgColor
    }

    // MARK: - Key capture

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Esc with no modifier = cancel
        if event.keyCode == 53 && mods.isEmpty {
            window?.makeFirstResponder(nil)
            return
        }

        // Require at least one modifier so bare letter keys are ignored
        guard !mods.isEmpty else { return }

        let kc = Int(event.keyCode)
        UserDefaults.standard.set(kc,                 forKey: Prefs.hotkeyKeyCode)
        UserDefaults.standard.set(Int(mods.rawValue), forKey: Prefs.hotkeyModifiers)
        needsDisplay = true
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        window?.makeFirstResponder(nil)
    }

    // MARK: - Formatting

    private func describe(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += keyNames[keyCode] ?? "?"
        return s
    }
}
