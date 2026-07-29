import Foundation

@main
struct ClamshellDisplaySleepControllerTests {
    static func main() {
        testSleepsOnceOnEnabledCloseTransition()
        testDoesNotSleepWhenProtectionIsDisabled()
        testDoesNotSleepWithoutOpenObservation()
        testUnavailableStateDoesNotCreateFalseTransition()
        print("ClamshellDisplaySleepController tests passed")
    }

    private static func testSleepsOnceOnEnabledCloseTransition() {
        var clamshellClosed = false
        var sleepCount = 0
        let controller = ClamshellDisplaySleepController(
            readClamshellState: { clamshellClosed },
            sleepDisplays: {
                sleepCount += 1
                return true
            },
            logger: { _ in }
        )

        controller.reconcile(keepAwakeEnabled: true)
        check(sleepCount == 0, "an open lid must not sleep displays")

        clamshellClosed = true
        controller.reconcile(keepAwakeEnabled: true)
        controller.reconcile(keepAwakeEnabled: true)
        check(sleepCount == 1, "a close transition should sleep displays once")

        clamshellClosed = false
        controller.reconcile(keepAwakeEnabled: true)
        clamshellClosed = true
        controller.reconcile(keepAwakeEnabled: true)
        check(sleepCount == 2, "a later close transition should sleep displays again")
    }

    private static func testDoesNotSleepWhenProtectionIsDisabled() {
        var clamshellClosed = false
        var sleepCount = 0
        let controller = ClamshellDisplaySleepController(
            readClamshellState: { clamshellClosed },
            sleepDisplays: {
                sleepCount += 1
                return true
            },
            logger: { _ in }
        )

        controller.reconcile(keepAwakeEnabled: false)
        clamshellClosed = true
        controller.reconcile(keepAwakeEnabled: false)
        controller.reconcile(keepAwakeEnabled: true)

        check(sleepCount == 0,
              "disabled protection and later enablement must not mimic a lid transition")
    }

    private static func testDoesNotSleepWithoutOpenObservation() {
        var sleepCount = 0
        let controller = ClamshellDisplaySleepController(
            readClamshellState: { true },
            sleepDisplays: {
                sleepCount += 1
                return true
            },
            logger: { _ in }
        )

        controller.reconcile(keepAwakeEnabled: true)
        check(sleepCount == 0,
              "starting while already closed must not blank an external display")
    }

    private static func testUnavailableStateDoesNotCreateFalseTransition() {
        var states: [Bool?] = [false, nil, true]
        var sleepCount = 0
        let controller = ClamshellDisplaySleepController(
            readClamshellState: { states.removeFirst() },
            sleepDisplays: {
                sleepCount += 1
                return true
            },
            logger: { _ in }
        )

        controller.reconcile(keepAwakeEnabled: true)
        controller.reconcile(keepAwakeEnabled: true)
        controller.reconcile(keepAwakeEnabled: true)

        check(sleepCount == 1,
              "an unavailable sample must preserve the last observed lid state")
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("ClamshellDisplaySleepController test failure: \(message)\n", stderr)
            exit(1)
        }
    }
}
