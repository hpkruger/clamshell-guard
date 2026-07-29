import Foundation
import IOKit

/// Puts connected displays to sleep once when the lid closes while keep-awake
/// protection is enabled.
final class ClamshellDisplaySleepController {
    typealias ReadClamshellState = () -> Bool?
    typealias SleepDisplays = () -> Bool

    private let readClamshellState: ReadClamshellState
    private let sleepDisplays: SleepDisplays
    private let logger: (String) -> Void
    private var previousClamshellState: Bool?

    init(
        readClamshellState: @escaping ReadClamshellState = {
            ClamshellDisplaySleepController.currentClamshellState()
        },
        sleepDisplays: @escaping SleepDisplays = {
            ClamshellDisplaySleepController.putDisplaysToSleep()
        },
        logger: @escaping (String) -> Void = { NSLog("%@", $0) }
    ) {
        self.readClamshellState = readClamshellState
        self.sleepDisplays = sleepDisplays
        self.logger = logger
    }

    /// Reconcile the latest lid state with the previous observation.
    ///
    /// The command runs only on an observed open-to-closed transition. Merely
    /// enabling keep-awake while the lid is already closed does not blank an
    /// external display, and repeated polling while closed does not retrigger it.
    func reconcile(keepAwakeEnabled: Bool) {
        guard let clamshellClosed = readClamshellState() else { return }
        defer { previousClamshellState = clamshellClosed }

        guard keepAwakeEnabled,
              previousClamshellState == false,
              clamshellClosed else {
            return
        }

        if !sleepDisplays() {
            logger("Clamshell Guard could not put connected displays to sleep")
        }
    }

    private static func currentClamshellState() -> Bool? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        return value as? Bool
    }

    private static func putDisplaysToSleep() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
