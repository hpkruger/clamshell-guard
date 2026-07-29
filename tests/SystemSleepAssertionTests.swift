import Foundation
import IOKit

@main
struct SystemSleepAssertionTests {
    static func main() {
        testIdempotentLifecycle()
        testCreateFailureCanRetry()
        testReleaseFailureCanRetry()
        print("SystemSleepAssertion tests passed")
    }

    private static func testIdempotentLifecycle() {
        var createCount = 0
        var releasedIDs: [IOPMAssertionID] = []
        let assertion = SystemSleepAssertion(
            createAssertion: { _, assertionID in
                createCount += 1
                assertionID.pointee = 42
                return kIOReturnSuccess
            },
            releaseAssertion: { assertionID in
                releasedIDs.append(assertionID)
                return kIOReturnSuccess
            },
            logger: { _ in }
        )

        check(assertion.setActive(true), "first activation should succeed")
        check(assertion.setActive(true), "second activation should be idempotent")
        check(assertion.isActive, "assertion should be active")
        check(createCount == 1, "assertion should be created once")

        check(assertion.setActive(false), "first release should succeed")
        check(assertion.setActive(false), "second release should be idempotent")
        check(!assertion.isActive, "assertion should be inactive")
        check(releasedIDs == [42], "created assertion should be released once")
    }

    private static func testCreateFailureCanRetry() {
        var createCount = 0
        let assertion = SystemSleepAssertion(
            createAssertion: { _, assertionID in
                createCount += 1
                if createCount == 1 {
                    return kIOReturnError
                }
                assertionID.pointee = 7
                return kIOReturnSuccess
            },
            releaseAssertion: { _ in kIOReturnSuccess },
            logger: { _ in }
        )

        check(!assertion.setActive(true), "failed create should be reported")
        check(!assertion.isActive, "failed create must not mark the assertion active")
        check(assertion.setActive(true), "create should be retried")
        check(assertion.isActive, "successful retry should become active")
        check(createCount == 2, "create should be attempted twice")
    }

    private static func testReleaseFailureCanRetry() {
        var releaseCount = 0
        let assertion = SystemSleepAssertion(
            createAssertion: { _, assertionID in
                assertionID.pointee = 99
                return kIOReturnSuccess
            },
            releaseAssertion: { assertionID in
                check(assertionID == 99, "release should receive the live assertion ID")
                releaseCount += 1
                return releaseCount == 1 ? kIOReturnError : kIOReturnSuccess
            },
            logger: { _ in }
        )

        check(assertion.setActive(true), "activation should succeed")
        check(!assertion.setActive(false), "failed release should be reported")
        check(assertion.isActive, "failed release should remain retryable")
        check(assertion.setActive(false), "release should be retried")
        check(!assertion.isActive, "successful retry should become inactive")
        check(releaseCount == 2, "release should be attempted twice")
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("SystemSleepAssertion test failure: \(message)\n", stderr)
            exit(1)
        }
    }
}
