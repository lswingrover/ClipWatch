import AppKit
import ServiceManagement

// MARK: - PreferencesWindowController

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private init() {
        let vc = PreferencesViewController()
        let win = NSWindow(contentViewController: vc)
        win.title = "ClipWatch Preferences"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 480, height: 430))
        win.center()
        super.init(window: win)
        win.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        // Re-register hotkey in case user changed it
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
    }
}

// MARK: - PreferencesViewController

final class PreferencesViewController: NSViewController {

    // Controls
    private var shortcutField:    ShortcutRecorderField!
    private var menuCountStepper: NSStepper!
    private var menuCountLabel:   NSTextField!
    private var retentionSlider:  NSSlider!
    private var retentionLabel:   NSTextField!
    private var screenSegment:    NSSegmentedControl!
    private var loginToggle:      NSButton!
    private var excludedTable:    NSTableView!
    private var excludedList:     [String] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 430))
        buildUI()
        loadValues()
    }

    // MARK: - UI Construction

    private func buildUI() {
        var y: CGFloat = 390

        func label(_ text: String, bold: Bool = false) -> NSTextField {
            let f = NSTextField(labelWithString: text)
            f.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
            return f
        }

        func addRow(title: NSTextField, control: NSView, atY: inout CGFloat) {
            title.frame = NSRect(x: 20, y: atY, width: 160, height: 20)
            control.frame.origin = NSPoint(x: 190, y: atY)
            view.addSubview(title)
            view.addSubview(control)
            atY -= 36
        }

        // ── Hotkey ──────────────────────────────────────────────────────────
        let sectionHotkey = label("Hotkey", bold: true)
        sectionHotkey.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        view.addSubview(sectionHotkey)
        y -= 28

        shortcutField = ShortcutRecorderField(frame: NSRect(x: 190, y: y, width: 180, height: 24))
        view.addSubview(label("Open panel"))
        view.subviews.last!.frame = NSRect(x: 20, y: y, width: 160, height: 20)
        view.addSubview(shortcutField)
        y -= 36

        // ── Menu ────────────────────────────────────────────────────────────
        let sectionMenu = label("Menu", bold: true)
        sectionMenu.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        view.addSubview(sectionMenu)
        y -= 28

        let stepperRow = NSStackView()
        stepperRow.orientation = .horizontal
        stepperRow.spacing = 6
        menuCountLabel = NSTextField(labelWithString: "10")
        menuCountLabel.frame = NSRect(x: 0, y: 0, width: 28, height: 20)
        menuCountStepper = NSStepper(frame: NSRect(x: 0, y: 0, width: 19, height: 24))
        menuCountStepper.minValue = 5
        menuCountStepper.maxValue = 25
        menuCountStepper.increment = 1
        menuCountStepper.target = self
        menuCountStepper.action = #selector(stepperChanged)
        stepperRow.addArrangedSubview(menuCountLabel)
        stepperRow.addArrangedSubview(menuCountStepper)
        stepperRow.frame = NSRect(x: 190, y: y, width: 80, height: 24)

        view.addSubview(label("Recent items in menu"))
        view.subviews.last!.frame = NSRect(x: 20, y: y, width: 160, height: 20)
        view.addSubview(stepperRow)
        y -= 36

        // ── History ─────────────────────────────────────────────────────────
        let sectionHistory = label("History", bold: true)
        sectionHistory.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        view.addSubview(sectionHistory)
        y -= 28

        retentionLabel = NSTextField(labelWithString: "365 days")
        retentionLabel.frame = NSRect(x: 20, y: y, width: 80, height: 20)
        retentionSlider = NSSlider(frame: NSRect(x: 110, y: y, width: 220, height: 20))
        retentionSlider.minValue = 30
        retentionSlider.maxValue = 730
        retentionSlider.numberOfTickMarks = 0
        retentionSlider.allowsTickMarkValuesOnly = false
        retentionSlider.target = self
        retentionSlider.action = #selector(sliderChanged)
        view.addSubview(retentionLabel)
        view.addSubview(retentionSlider)
        y -= 36

        // ── Screen ──────────────────────────────────────────────────────────
        let sectionScreen = label("Panel appears on", bold: false)
        sectionScreen.frame = NSRect(x: 20, y: y, width: 160, height: 20)
        view.addSubview(sectionScreen)

        screenSegment = NSSegmentedControl(
            labels: ["Active app's screen", "Screen with cursor"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(screenModeChanged)
        )
        screenSegment.frame = NSRect(x: 190, y: y - 2, width: 240, height: 24)
        view.addSubview(screenSegment)
        y -= 36

        // ── Login ───────────────────────────────────────────────────────────
        loginToggle = NSButton(checkboxWithTitle: "Launch ClipWatch at login",
                               target: self, action: #selector(loginToggled))
        loginToggle.frame = NSRect(x: 20, y: y, width: 300, height: 20)
        view.addSubview(loginToggle)
        y -= 44

        // ── Excluded apps ────────────────────────────────────────────────────
        let sectionExcl = label("Never capture from these apps", bold: true)
        sectionExcl.frame = NSRect(x: 20, y: y, width: 320, height: 20)
        view.addSubview(sectionExcl)
        y -= 28

        excludedTable = NSTableView(frame: .zero)
        excludedTable.headerView = nil
        excludedTable.rowHeight = 18
        excludedTable.focusRingType = .none
        let exCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bundleID"))
        exCol.isEditable = false
        excludedTable.addTableColumn(exCol)
        excludedTable.delegate = self
        excludedTable.dataSource = self

        let exScroll = NSScrollView(frame: NSRect(x: 20, y: y - 80, width: 300, height: 80))
        exScroll.documentView = excludedTable
        exScroll.hasVerticalScroller = true
        exScroll.borderType = .bezelBorder
        view.addSubview(exScroll)

        let addBtn = NSButton(title: "+", target: self, action: #selector(addExcluded))
        addBtn.frame = NSRect(x: 326, y: y - 56, width: 24, height: 24)
        addBtn.bezelStyle = .regularSquare
        let remBtn = NSButton(title: "−", target: self, action: #selector(removeExcluded))
        remBtn.frame = NSRect(x: 356, y: y - 56, width: 24, height: 24)
        remBtn.bezelStyle = .regularSquare
        view.addSubview(addBtn)
        view.addSubview(remBtn)
    }

    // MARK: - Load / Save Values

    private func loadValues() {
        shortcutField.loadFromDefaults()

        let count = Prefs.menuCount()
        menuCountStepper.intValue = Int32(count)
        menuCountLabel.stringValue = "\(count)"

        let days = UserDefaults.standard.integer(forKey: Prefs.retentionDays)
        retentionSlider.intValue = Int32(days > 0 ? days : 365)
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
        alert.messageText    = "Add excluded app"
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

final class ShortcutRecorderField: NSTextField {

    private let keyNames: [Int: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
        11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",
        31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",
        18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",25:"9",26:"7",28:"8",29:"0",
        47:".",44:"/",27:"-",24:"=",33:"[",30:"]",
        48:"Tab",49:"Space",36:"Return",51:"Delete",53:"Esc",
        123:"←",124:"→",125:"↓",126:"↑",
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = true
        isBezeled  = true
        bezelStyle = .roundedBezel
        isEditable = false
        isSelectable = false
        alignment  = .center
        placeholderString = "Click to record…"
    }
    required init?(coder: NSCoder) { fatalError() }

    func loadFromDefaults() {
        let kc   = Prefs.hotkeyVirtualKey()
        let mods = NSEvent.ModifierFlags(rawValue: UInt(Prefs.hotkeyModifierFlags()))
        stringValue = describe(keyCode: kc, modifiers: mods)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.isEmpty else { return }   // bare key without modifier = ignore
        let kc = Int(event.keyCode)
        UserDefaults.standard.set(kc, forKey: Prefs.hotkeyKeyCode)
        UserDefaults.standard.set(Int(mods.rawValue), forKey: Prefs.hotkeyModifiers)
        stringValue = describe(keyCode: kc, modifiers: mods)
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
    }

    private func describe(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control)  { s += "⌃" }
        if modifiers.contains(.option)   { s += "⌥" }
        if modifiers.contains(.shift)    { s += "⇧" }
        if modifiers.contains(.command)  { s += "⌘" }
        s += keyNames[keyCode] ?? "?"
        return s
    }

    // Draw a subtle "recording" border when focused
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { placeholderString = "Press shortcut…" }
        return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { placeholderString = "Click to record…" }
        return result
    }
}
