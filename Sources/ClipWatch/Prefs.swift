import Foundation

// MARK: - Prefs: UserDefaults keys and defaults

enum Prefs {
    static let hotkeyKeyCode   = "hotkeyKeyCode"    // Int  (default 9 = V)
    static let hotkeyModifiers = "hotkeyModifiers"  // Int  (default ⌥⌘)
    static let menuItemCount   = "menuItemCount"    // Int  (default 10)
    static let retentionDays   = "retentionDays"    // Int  (default 365)
    static let screenFocusMode = "screenFocusMode"  // String "activeApp" | "cursor"
    static let excludedApps    = "excludedApps"     // [String] bundle IDs
    static let launchAtLogin   = "launchAtLogin"    // Bool

    static let defaultExcludedApps: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword-osx",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword4",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
    ]

    static func menuCount() -> Int {
        let v = UserDefaults.standard.integer(forKey: menuItemCount)
        return (v >= 5 && v <= 25) ? v : 10
    }

    static func hotkeyVirtualKey() -> Int {
        let v = UserDefaults.standard.integer(forKey: hotkeyKeyCode)
        return v > 0 ? v : 9  // default V
    }

    static func hotkeyModifierFlags() -> Int {
        let v = UserDefaults.standard.integer(forKey: hotkeyModifiers)
        // default: option (524288) + command (1048576) = 1572864
        return v > 0 ? v : 1572864
    }

    static func screenMode() -> String {
        let v = UserDefaults.standard.string(forKey: screenFocusMode) ?? ""
        return v.isEmpty ? "activeApp" : v
    }
}
