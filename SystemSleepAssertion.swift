import Foundation
import IOKit.pwr_mgt

/// A process-scoped IOKit assertion that prevents system sleep while active.
///
/// Unlike the global `pmset disablesleep` setting, this assertion is
/// automatically released by macOS if AwakeToggle exits or crashes.
final class SystemSleepAssertion {
    typealias CreateAssertion = (
        _ reason: CFString,
        _ assertionID: UnsafeMutablePointer<IOPMAssertionID>
    ) -> IOReturn
    typealias ReleaseAssertion = (_ assertionID: IOPMAssertionID) -> IOReturn

    private let reason: CFString
    private let createAssertion: CreateAssertion
    private let releaseAssertion: ReleaseAssertion
    private let logger: (String) -> Void
    private var assertionID: IOPMAssertionID?

    var isActive: Bool {
        assertionID != nil
    }

    init(
        reason: String = "AwakeToggle is keeping the system awake",
        createAssertion: @escaping CreateAssertion = { reason, assertionID in
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                assertionID
            )
        },
        releaseAssertion: @escaping ReleaseAssertion = { assertionID in
            IOPMAssertionRelease(assertionID)
        },
        logger: @escaping (String) -> Void = { NSLog("%@", $0) }
    ) {
        self.reason = reason as CFString
        self.createAssertion = createAssertion
        self.releaseAssertion = releaseAssertion
        self.logger = logger
    }

    deinit {
        guard let assertionID else { return }
        _ = releaseAssertion(assertionID)
    }

    /// Reconcile the held assertion with the requested state.
    ///
    /// Calls are idempotent. A failed create or release remains retryable on the
    /// next reconciliation tick.
    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        if active {
            guard assertionID == nil else { return true }

            var newAssertionID = IOPMAssertionID(0)
            let result = createAssertion(reason, &newAssertionID)
            guard result == kIOReturnSuccess else {
                logger("AwakeToggle could not create PreventSystemSleep assertion: \(result)")
                return false
            }

            assertionID = newAssertionID
            return true
        }

        guard let existingAssertionID = assertionID else { return true }
        let result = releaseAssertion(existingAssertionID)
        guard result == kIOReturnSuccess else {
            logger("AwakeToggle could not release PreventSystemSleep assertion: \(result)")
            return false
        }

        assertionID = nil
        return true
    }
}
