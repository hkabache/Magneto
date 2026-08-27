import Foundation
import Testing

/// Sparkle's user driver delegate is made entirely of optional methods, dispatched by
/// selector. A Swift signature that drifts from the Objective-C one therefore turns the
/// feature off without a warning anywhere: the app would go back to opening its update
/// window by itself, in the middle of a dictation. These are the selectors exactly as
/// `SPUStandardUserDriverDelegate.h` declares them.
@Suite("Updater")
struct UpdaterTests {
    private let reminders = GentleReminders()

    @Test("the delegate answers to the selectors Sparkle calls")
    func selectorsMatchSparkle() {
        let selectors = [
            "supportsGentleScheduledUpdateReminders",
            "standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:",
            "standardUserDriverWillHandleShowingUpdate:forUpdate:state:",
            "standardUserDriverDidReceiveUserAttentionForUpdate:",
            "standardUserDriverWillFinishUpdateSession",
        ]
        for selector in selectors {
            #expect(reminders.responds(to: Selector(selector)), "\(selector)")
        }
    }

    @Test("gentle reminders are declared, otherwise Sparkle never asks")
    func gentleRemindersAreDeclared() {
        #expect(reminders.supportsGentleScheduledUpdateReminders)
    }
}
