import Foundation
import Darwin

@main
struct CodexIPCMonitorIntegration {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: CodexIPCMonitorIntegration <codex-home>\n", stderr)
            exit(2)
        }

        setenv("CODEX_HOME", CommandLine.arguments[1], 1)

        var observedStates: [CodexActivityState] = []
        var sawInitialActive = false
        var sawOwnerUnavailable = false
        var sawRecoveredActive = false
        var idleObservedAt: Date?
        var becameUnavailableAfterIdle = false
        var sawDuplicateCount = false
        var completed = false

        let monitor = CodexIPCMonitor { state in
            observedStates.append(state)
            if state.activeCount > 1 {
                sawDuplicateCount = true
            }

            if state.availability == .available && state.activeCount == 1 {
                if sawOwnerUnavailable {
                    sawRecoveredActive = true
                } else {
                    sawInitialActive = true
                }
            } else if sawInitialActive,
                      state.availability == .unavailable,
                      state.activeCount == 1 {
                sawOwnerUnavailable = true
            } else if sawRecoveredActive,
                      state.availability == .available,
                      state.activeCount == 0 {
                idleObservedAt = Date()
            } else if idleObservedAt != nil,
                      state.availability == .unavailable {
                becameUnavailableAfterIdle = true
            }
        }

        monitor.start()
        let deadline = Date().addingTimeInterval(12)
        while !completed && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if let idleObservedAt,
               Date().timeIntervalSince(idleObservedAt) >= 1 {
                completed = !becameUnavailableAfterIdle
                break
            }
        }
        monitor.stop()

        guard completed, !becameUnavailableAfterIdle, !sawDuplicateCount else {
            let summary = observedStates.map {
                "\($0.availability)/\($0.activeCount)"
            }.joined(separator: ", ")
            fputs("unexpected monitor states: \(summary)\n", stderr)
            exit(1)
        }

        print("CodexIPCMonitor side-task recovery integration test passed")
    }
}
