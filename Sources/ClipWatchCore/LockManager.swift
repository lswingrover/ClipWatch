import Foundation
import LocalAuthentication
import Security

// MARK: - LockManager
//
// Central lock/unlock state for ClipWatch.
//
// Architecture:
//   - isLocked reflects the current in-app lock state.
//   - Keychain item (kSecAttrAccessibleWhenUnlocked) stores the last-unlock
//     timestamp. Reading the item succeeds only when the macOS login keychain
//     is unlocked (screen not locked). This ties ClipWatch to the system
//     keychain, mirroring 1Password vault protection model.
//   - Screen sleep: AppDelegate checks Prefs.lockOnSleepEnabled() then calls
//     lock(). Screen wake: AppDelegate calls checkKeychainUnlock() to silently
//     re-unlock if the window is still valid and the keychain is readable.
//   - Idle timer: resets on touchActivity(). Fires lock() after idleLockMinutes.
//
// Thread safety: all public methods must be called on the main thread.
//
// GH: lswingrover/clipwatch#2
public final class LockManager {

    public static let shared = LockManager()

    // MARK: - State

    public private(set) var isLocked: Bool
    private var autoLockTimer: Timer?
    private var idleTimer:     Timer?
    private let keychainService = "com.louisswingrover.clipwatch"
    private let keychainAccount = "unlock-state"

    // Overrides the idle-lock interval for unit tests (nil = use Prefs, production default).
    // Setting this bypasses the minutes-based Prefs value so tests can use sub-second
    // intervals without waiting 60+ seconds for a timer to fire.
    public var idleLockSecondsOverride: TimeInterval? = nil

    private init() {
        isLocked = Prefs.isSecureModeEnabled()
        if Prefs.isSecureModeEnabled() {
            checkKeychainUnlock()
        }
    }

    // MARK: - Public API

    public func lock() {
        guard Prefs.isSecureModeEnabled() else { return }
        isLocked = true
        cancelTimers()
        deleteKeychainState()
        NotificationCenter.default.post(name: .clipWatchDidLock, object: nil)
    }

    public func recordUnlock() {
        isLocked = false
        writeKeychainState()
        scheduleAutoLock()
        scheduleIdleLock()
        NotificationCenter.default.post(name: .clipWatchDidUnlock, object: nil)
    }

    /// Prompt Touch ID / Apple Watch / Mac password.
    /// LAContext .deviceOwnerAuthentication covers all three automatically.
    public func tryUnlock(reason: String, completion: @escaping (Bool) -> Void) {
        guard Prefs.isSecureModeEnabled() else { completion(true); return }
        if !isLocked { completion(true); return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            recordUnlock(); completion(true); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] ok, _ in
            DispatchQueue.main.async {
                if ok { self?.recordUnlock() }
                completion(ok)
            }
        }
    }

    /// Called on screen wake. Silently re-unlocks if the keychain token is
    /// still readable and the unlock window has not expired.
    public func checkKeychainUnlock() {
        guard Prefs.isSecureModeEnabled() else { return }
        guard let state = readKeychainState() else { return }
        let secs = Prefs.unlockDurationSeconds()
        if secs == -1 { recordUnlock(); return }
        if secs > 0, Date().timeIntervalSince(state.lastUnlock) < Double(secs) {
            recordUnlock()
        }
    }

    /// Reset the idle timer. Call on any meaningful ClipWatch interaction.
    public func touchActivity() {
        guard !isLocked, Prefs.isSecureModeEnabled() else { return }
        scheduleIdleLock()
    }

    /// Called when Secure Mode toggled in Preferences.
    public func secureModeDidChange() {
        if Prefs.isSecureModeEnabled() {
            isLocked = true
            cancelTimers()
            deleteKeychainState()
            NotificationCenter.default.post(name: .clipWatchDidLock, object: nil)
        } else {
            isLocked = false
            cancelTimers()
            deleteKeychainState()
            NotificationCenter.default.post(name: .clipWatchDidUnlock, object: nil)
        }
    }

    // MARK: - Test support

    /// Reset internal state for unit tests. Never call from production code.
    /// Sets isLocked and cancels any running timers so each test starts clean.
    internal func resetForTesting(locked: Bool) {
        cancelTimers()
        isLocked = locked
    }

    // MARK: - Auto-lock timer (unlock duration)

    private func scheduleAutoLock() {
        autoLockTimer?.invalidate()
        let secs = Prefs.unlockDurationSeconds()
        guard secs > 0 else { return }
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: Double(secs), repeats: false) { [weak self] _ in
            self?.lock()
        }
    }

    // MARK: - Idle lock timer

    internal func scheduleIdleLock() {
        idleTimer?.invalidate()
        let interval: TimeInterval
        if let override = idleLockSecondsOverride {
            // Test override: skip the minutes-to-seconds conversion so tests
            // can fire the timer in milliseconds rather than waiting 60+ seconds.
            interval = override
        } else {
            let mins = Prefs.idleLockIntervalMinutes()
            guard mins > 0 else { return }
            interval = Double(mins * 60)
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.lock()
        }
    }

    private func cancelTimers() {
        autoLockTimer?.invalidate(); autoLockTimer = nil
        idleTimer?.invalidate();     idleTimer     = nil
    }

    // MARK: - Keychain

    private struct UnlockState: Codable { let lastUnlock: Date }

    private func writeKeychainState() {
        guard let data = try? JSONEncoder().encode(UnlockState(lastUnlock: Date())) else { return }
        let q: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    keychainService,
            kSecAttrAccount:    keychainAccount,
            kSecValueData:      data,
            // Inaccessible when screen is locked -- ties ClipWatch to the
            // macOS user keychain state, just like 1Password.
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    private func readKeychainState() -> UnlockState? {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = try? JSONDecoder().decode(UnlockState.self, from: data) else { return nil }
        return s
    }

    private func deleteKeychainState() {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                  kSecAttrService: keychainService, kSecAttrAccount: keychainAccount]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Notification names
public extension Notification.Name {
    static let clipWatchDidLock   = Notification.Name("com.louisswingrover.clipwatch.didLock")
    static let clipWatchDidUnlock = Notification.Name("com.louisswingrover.clipwatch.didUnlock")
}
