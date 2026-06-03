import Foundation

// MARK: - Prefs: UserDefaults keys and defaults
public enum Prefs {
    public static let hotkeyKeyCode    = "hotkeyKeyCode"    // Int  (default 9 = V)
    public static let hotkeyModifiers  = "hotkeyModifiers"  // Int  (default option+command)
    public static let menuItemCount    = "menuItemCount"    // Int  (default 10)
    public static let retentionDays    = "retentionDays"    // Int  (default 365)
    public static let screenFocusMode  = "screenFocusMode"  // String "activeApp" | "cursor"
    public static let excludedApps     = "excludedApps"     // [String] bundle IDs
    public static let excludedURLs     = "excludedURLs"     // [String] domain/URL patterns
    public static let secureMode       = "secureMode"       // Bool -- require auth to open panel
    public static let unlockDuration   = "unlockDuration"   // Int  -- seconds (0=every use, -1=session)
    public static let lockOnSleep      = "lockOnSleep"      // Bool -- lock when device sleeps/locks
    public static let idleLockMinutes  = "idleLockMinutes"  // Int  -- 0=never, else minutes of inactivity
    public static let launchAtLogin    = "launchAtLogin"    // Bool
    public static let pollInterval     = "pollInterval"     // Double -- seconds between clipboard checks

    public static let defaultExcludedApps: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword-osx",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword4",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
    ]

    // Injectable UserDefaults — override in unit tests to avoid polluting UserDefaults.standard.
    // Production code always uses the default (.standard). Tests swap this per-suite.
    public static var defaults: UserDefaults = .standard

    public static func menuCount() -> Int {
        let v = defaults.integer(forKey: menuItemCount)
        return (v >= 5 && v <= 25) ? v : 10
    }

    public static func hotkeyVirtualKey() -> Int {
        let v = defaults.integer(forKey: hotkeyKeyCode)
        return v > 0 ? v : 9  // default V
    }

    public static func hotkeyModifierFlags() -> Int {
        let v = defaults.integer(forKey: hotkeyModifiers)
        // default: option (524288) + command (1048576) = 1572864
        return v > 0 ? v : 1_572_864
    }

    public static func isSecureModeEnabled() -> Bool {
        defaults.bool(forKey: secureMode)
    }

    /// Seconds to stay unlocked after successful auth.
    /// 0 = authenticate every use; -1 = stay unlocked until app restarts.
    public static func unlockDurationSeconds() -> Int {
        defaults.integer(forKey: unlockDuration)
    }

    /// Whether to lock when the device sleeps or the screen locks. Default true.
    public static func lockOnSleepEnabled() -> Bool {
        if defaults.object(forKey: lockOnSleep) == nil { return true }  // default true
        return defaults.bool(forKey: lockOnSleep)
    }

    /// Minutes of ClipWatch inactivity before auto-locking. 0 = never (disabled).
    public static func idleLockIntervalMinutes() -> Int {
        max(0, defaults.integer(forKey: idleLockMinutes))
    }

    public static func screenMode() -> String {
        let v = defaults.string(forKey: screenFocusMode) ?? ""
        return v.isEmpty ? "activeApp" : v
    }

    /// Poll interval in seconds. Clamped to 0.5-5.0; defaults to 1.0 s.
    public static func pollIntervalSeconds() -> TimeInterval {
        let v = defaults.double(forKey: pollInterval)
        return (v >= 0.5 && v <= 5.0) ? v : 1.0
    }
}
