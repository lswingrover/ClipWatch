import Foundation

// MARK: - Prefs: UserDefaults keys and defaults

public enum Prefs {
    public static let hotkeyKeyCode   = "hotkeyKeyCode"    // Int  (default 9 = V)
    public static let hotkeyModifiers = "hotkeyModifiers"  // Int  (default ⌥⌘)
    public static let menuItemCount   = "menuItemCount"    // Int  (default 10)
    public static let retentionDays   = "retentionDays"    // Int  (default 365)
    public static let screenFocusMode = "screenFocusMode"  // String "activeApp" | "cursor"
    public static let excludedApps    = "excludedApps"     // [String] bundle IDs
    public static let excludedURLs    = "excludedURLs"     // [String] domain/URL patterns
    public static let secureMode      = "secureMode"       // Bool — require Touch ID to open panel
    public static let unlockDuration  = "unlockDuration"   // Int  — seconds to stay unlocked (0=always ask, -1=session)
    public static let launchAtLogin   = "launchAtLogin"    // Bool
    public static let pollInterval    = "pollInterval"     // Double — seconds between clipboard checks

    public static let defaultExcludedApps: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword-osx",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword4",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
    ]

    public static func menuCount() -> Int {
        let v = UserDefaults.standard.integer(forKey: menuItemCount)
        return (v >= 5 && v <= 25) ? v : 10
    }

    public static func hotkeyVirtualKey() -> Int {
        let v = UserDefaults.standard.integer(forKey: hotkeyKeyCode)
        return v > 0 ? v : 9  // default V
    }

    public static func hotkeyModifierFlags() -> Int {
        let v = UserDefaults.standard.integer(forKey: hotkeyModifiers)
        // default: option (524288) + command (1048576) = 1572864
        return v > 0 ? v : 1572864
    }

    public static func isSecureModeEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: secureMode)
    }

    /// Seconds to stay unlocked after a successful Touch ID authentication.
    /// 0 = authenticate every use; -1 = stay unlocked until app restarts.
    public static func unlockDurationSeconds() -> Int {
        // UserDefaults returns 0 for missing keys, which is our "every use" default — no special casing needed.
        return UserDefaults.standard.integer(forKey: unlockDuration)
    }

    public static func screenMode() -> String {
        let v = UserDefaults.standard.string(forKey: screenFocusMode) ?? ""
        return v.isEmpty ? "activeApp" : v
    }

    /// Poll interval in seconds. Clamped to 0.5–5.0; defaults to 1.0 s.
    public static func pollIntervalSeconds() -> TimeInterval {
        let v = UserDefaults.standard.double(forKey: pollInterval)
        return (v >= 0.5 && v <= 5.0) ? v : 1.0
    }
}
