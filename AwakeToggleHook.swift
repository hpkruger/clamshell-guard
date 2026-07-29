import CryptoKit
import Darwin
import Foundation

// Receives Codex hook JSON on stdin and maintains one marker per active turn.
// Only start events originating from the macOS Codex app are accepted; stop
// events can always remove an existing marker so cleanup remains reliable.

struct HookPayload: Decodable {
    let sessionID: String
    let turnID: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
    }
}

struct TurnMarker: Codable {
    let sessionID: String
    let turnID: String
    let appServerPID: Int32
    let startedAt: Date
}

func parentPID(of pid: pid_t) -> pid_t? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    let result = mib.withUnsafeMutableBufferPointer {
        sysctl($0.baseAddress, u_int($0.count), &info, &size, nil, 0)
    }
    return result == 0 ? info.kp_eproc.e_ppid : nil
}

func executablePath(of pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cString: buffer)
}

func codexDesktopAppServerPID() -> pid_t? {
    var pid = getppid()
    for _ in 0..<12 where pid > 1 {
        if let path = executablePath(of: pid),
           path.hasSuffix(".app/Contents/Resources/codex") {
            let appURL = URL(fileURLWithPath: path)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            if Bundle(url: appURL)?.bundleIdentifier == "com.openai.codex" {
                return pid
            }
        }
        guard let next = parentPID(of: pid), next != pid else { break }
        pid = next
    }
    return nil
}

func markerDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory,
                             in: .userDomainMask)[0]
        .appendingPathComponent("AwakeToggle/active-turns", isDirectory: true)
}

func markerURL(sessionID: String, turnID: String) -> URL {
    let digest = SHA256.hash(data: Data("\(sessionID):\(turnID)".utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    return markerDirectory().appendingPathComponent("\(digest).json")
}

func readPayload() -> HookPayload? {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return try? JSONDecoder().decode(HookPayload.self, from: data)
}

func removeSessionMarkers(_ sessionID: String) {
    let directory = markerDirectory()
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ) else { return }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    for file in files {
        guard let data = try? Data(contentsOf: file),
              let marker = try? decoder.decode(TurnMarker.self, from: data),
              marker.sessionID == sessionID else { continue }
        try? FileManager.default.removeItem(at: file)
    }
}

guard CommandLine.arguments.count == 2,
      let payload = readPayload() else {
    exit(0)
}

let action = CommandLine.arguments[1]
let directory = markerDirectory()
try? FileManager.default.createDirectory(at: directory,
                                         withIntermediateDirectories: true)

switch action {
case "start":
    guard let turnID = payload.turnID,
          let appServerPID = codexDesktopAppServerPID() else {
        exit(0)
    }
    let marker = TurnMarker(sessionID: payload.sessionID,
                            turnID: turnID,
                            appServerPID: appServerPID,
                            startedAt: Date())
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(marker) {
        try? data.write(to: markerURL(sessionID: payload.sessionID, turnID: turnID),
                        options: .atomic)
    }

case "stop":
    if let turnID = payload.turnID {
        try? FileManager.default.removeItem(
            at: markerURL(sessionID: payload.sessionID, turnID: turnID)
        )
    }

case "session-end":
    removeSessionMarkers(payload.sessionID)

default:
    break
}
