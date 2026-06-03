// ClipWatchCore unit tests
import Testing
import Foundation
@testable import ClipWatchCore

// MARK: - LockManager Tests
//
// Design notes:
//   - Suite is .serialized because LockManager.shared and Prefs.defaults are
//     process-level singletons. Parallel execution would race on shared state.
//   - Each test creates its own UserDefaults suite (unique UUID) so tests
//     never read values written by a sibling test.
//   - resetForTesting(locked:) cancels timers and sets isLocked directly,
//     bypassing keychain + Prefs so the test controls initial state.
//   - idle timer tests use idleLockSecondsOverride = 0.1 to avoid waiting 60s.
//
// Acceptance criteria (GH#1):
//   - All three clipwatch-companion skills handle 423 gracefully.    [SKILL.md]
//   - swift test green with LockManager coverage.                    [this file]

@Suite("LockManager", .serialized)
struct LockManagerTests {

    // MARK: - Helpers

    /// Create a fresh, empty UserDefaults suite for one test.
    /// UUID in the name guarantees no cross-test pollution even within a suite run.
    private func makeTestDefaults() -> UserDefaults {
        let name = "com.test.clipwatch.lock.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: name)!
        ud.removePersistentDomain(forName: name)
        return ud
    }

    // MARK: - State transition tests

    @Test("lock() sets isLocked = true")
    @MainActor func lockSetsLocked() {
        let ud = makeTestDefaults()
        ud.set(true, forKey: Prefs.secureMode)
        Prefs.defaults = ud
        LockManager.shared.resetForTesting(locked: false)

        LockManager.shared.lock()

        #expect(LockManager.shared.isLocked == true)
    }

    @Test("recordUnlock() clears isLocked")
    @MainActor func recordUnlockClearsLocked() {
        let ud = makeTestDefaults()
        ud.set(true, forKey: Prefs.secureMode)
        Prefs.defaults = ud
        LockManager.shared.resetForTesting(locked: true)

        LockManager.shared.recordUnlock()

        #expect(LockManager.shared.isLocked == false)
    }

    @Test("lock -> unlock -> lock round-trip")
    @MainActor func lockUnlockLockRoundTrip() {
        let ud = makeTestDefaults()
        ud.set(true, forKey: Prefs.secureMode)
        Prefs.defaults = ud
        LockManager.shared.resetForTesting(locked: false)

        LockManager.shared.lock()
        #expect(LockManager.shared.isLocked == true)

        LockManager.shared.recordUnlock()
        #expect(LockManager.shared.isLocked == false)

        LockManager.shared.lock()
        #expect(LockManager.shared.isLocked == true)
    }

    // MARK: - Secure-mode-off bypass

    @Test("secure mode OFF: lock() is a no-op")
    @MainActor func secureModeOffBypassesLock() {
        let ud = makeTestDefaults()
        ud.set(false, forKey: Prefs.secureMode)   // secure mode OFF
        Prefs.defaults = ud
        LockManager.shared.resetForTesting(locked: false)

        LockManager.shared.lock()   // should be a no-op

        #expect(LockManager.shared.isLocked == false)
    }

    @Test("secure mode OFF: tryUnlock completes true without biometrics")
    func tryUnlockSecureModeOffSkipsBiometrics() async {
        let ud = makeTestDefaults()
        ud.set(false, forKey: Prefs.secureMode)
        Prefs.defaults = ud
        await MainActor.run { LockManager.shared.resetForTesting(locked: true) }

        let result = await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                LockManager.shared.tryUnlock(reason: "unit test") { cont.resume(returning: $0) }
            }
        }

        #expect(result == true)
    }

    // MARK: - secureModeDidChange

    @Test("secureModeDidChange to ON locks immediately")
    @MainActor func secureModeToOnLocks() {
        let ud = makeTestDefaults()
        ud.set(false, forKey: Prefs.secureMode)
        Prefs.defaults = ud
        LockManager.shared.resetForTesting(locked: false)

        // Simulate user enabling Secure Mode in Preferences
        ud.set(true, forKey: Prefs.secureMode)
        LockManager.shared.secureModeDidChange()

        #expect(LockManager.shared.isLocked == true)
    }

    @Test("secureModeDidChange to OFF unlocks immediately")
    @MainActor func secureModeToOffUnlocks() {
        let ud = makeTestDefaults()
        ud.set(true, forKey: Prefs.secureMode)
        Prefs.defaults = ud
        LockManager.shared.resetForTesting(locked: true)

        // Simulate user disabling Secure Mode in Preferences
        ud.set(false, forKey: Prefs.secureMode)
        LockManager.shared.secureModeDidChange()

        #expect(LockManager.shared.isLocked == false)
    }

    // MARK: - Idle timer

    @Test("idle timer fires and locks after interval")
    func idleTimerFiresAndLocks() async throws {
        let ud = makeTestDefaults()
        ud.set(true, forKey: Prefs.secureMode)
        ud.set(1, forKey: Prefs.idleLockMinutes)   // 1 min normally; overridden below
        Prefs.defaults = ud

        await MainActor.run {
            LockManager.shared.resetForTesting(locked: false)
            // Override to 100 ms so the timer fires in the test budget.
            // scheduleIdleLock() respects this override before checking Prefs.
            LockManager.shared.idleLockSecondsOverride = 0.1
            LockManager.shared.scheduleIdleLock()
        }

        // Give the RunLoop time to fire the 100 ms timer.
        try await Task.sleep(nanoseconds: 250_000_000)   // 250 ms

        let nowLocked = await MainActor.run { LockManager.shared.isLocked }
        #expect(nowLocked == true)

        // Cleanup
        await MainActor.run {
            LockManager.shared.idleLockSecondsOverride = nil
            LockManager.shared.resetForTesting(locked: false)
        }
    }

    @Test("idle timer does not fire when idleLockMinutes = 0")
    func idleTimerDisabledWhenZeroMinutes() async throws {
        let ud = makeTestDefaults()
        ud.set(true, forKey: Prefs.secureMode)
        ud.set(0, forKey: Prefs.idleLockMinutes)   // 0 = disabled
        Prefs.defaults = ud

        await MainActor.run {
            LockManager.shared.resetForTesting(locked: false)
            // No override -- scheduleIdleLock should early-return when mins == 0
            LockManager.shared.idleLockSecondsOverride = nil
            LockManager.shared.scheduleIdleLock()
        }

        // Wait long enough that a misfired timer would have locked
        try await Task.sleep(nanoseconds: 150_000_000)   // 150 ms

        let nowLocked = await MainActor.run { LockManager.shared.isLocked }
        #expect(nowLocked == false)
    }
}
