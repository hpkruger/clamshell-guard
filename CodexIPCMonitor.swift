import Foundation
import Darwin
import SQLite3

enum CodexMonitorAvailability: Equatable {
    case connecting
    case available
    case unavailable
}

struct CodexActivityState: Equatable {
    let availability: CodexMonitorAvailability
    let activeCount: Int

    static let connecting = CodexActivityState(availability: .connecting,
                                                activeCount: 0)
}

// Reads live task state from Codex Desktop's private per-user IPC router.
//
// SQLite is used only to discover candidate conversation IDs. Runtime status
// always comes from the Codex window that owns a conversation. Raw snapshots
// are neither logged nor retained: only "active" versus "not active" is kept.
final class CodexIPCMonitor {
    typealias UpdateHandler = (CodexActivityState) -> Void

    private let updateHandler: UpdateHandler
    private let queue = DispatchQueue(label: "com.machinefriendly.awaketoggle.codex-ipc")
    private let discoveryInterval: TimeInterval = 2
    private let candidateAgeSeconds: Int64 = 7 * 24 * 60 * 60
    private let maximumCandidateCount: Int32 = 250
    private let maximumFrameBytes = 64 * 1024 * 1024

    private var running = false
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var receiveBuffer = Data()
    private var initializeRequestID: String?
    private var initializeStartedAt: Date?
    private var clientID: String?
    private var subscribedConversationIDs = Set<String>()
    private var statusByConversationID: [String: String] = [:]
    private var ownerByConversationID: [String: String] = [:]
    private var revisionByConversationID: [String: Int] = [:]
    private var conversationsAwaitingOwner = Set<String>()
    private var availability: CodexMonitorAvailability = .connecting
    private var lastEmittedState: CodexActivityState?
    private var generation = 0

    init(updateHandler: @escaping UpdateHandler) {
        self.updateHandler = updateHandler
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.availability = .connecting
            self.emitState()

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(),
                           repeating: self.discoveryInterval,
                           leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            guard running else { return }
            running = false
            timer?.cancel()
            timer = nil
            unsubscribeAll()
            disconnect(nextAvailability: .unavailable)
        }
    }

    private func tick() {
        guard running else { return }

        if socketFD < 0 {
            connect()
            return
        }

        guard clientID != nil else {
            if let started = initializeStartedAt,
               Date().timeIntervalSince(started) > 5 {
                disconnect(nextAvailability: .unavailable)
            }
            return
        }

        discoverAndSubscribe()
    }

    private func connect() {
        guard validateIPCPath() else {
            setAvailability(.unavailable)
            return
        }

        let path = ipcSocketURL.path
        let pathBytes = Array(path.utf8) + [0]
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            setAvailability(.unavailable)
            return
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            setAvailability(.unavailable)
            return
        }

        var noSigPipe: Int32 = 1
        _ = withUnsafePointer(to: &noSigPipe) {
            setsockopt(descriptor,
                       SOL_SOCKET,
                       SO_NOSIGPIPE,
                       $0,
                       socklen_t(MemoryLayout<Int32>.size))
        }

        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: pathBytes)
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor,
                               $0,
                               socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            setAvailability(.unavailable)
            return
        }

        let currentFlags = fcntl(descriptor, F_GETFL)
        if currentFlags >= 0 {
            _ = fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK)
        }

        socketFD = descriptor
        receiveBuffer.removeAll(keepingCapacity: true)
        generation += 1
        setAvailability(.connecting)

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor,
                                                   queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailableData()
        }
        readSource = source
        source.resume()

        let requestID = UUID().uuidString
        initializeRequestID = requestID
        initializeStartedAt = Date()
        let message: [String: Any] = [
            "type": "request",
            "requestId": requestID,
            "sourceClientId": "initializing-client",
            "version": 0,
            "method": "initialize",
            "params": ["clientType": "awaketoggle"]
        ]
        guard send(message) else {
            disconnect(nextAvailability: .unavailable)
            return
        }
    }

    private func readAvailableData() {
        guard socketFD >= 0 else { return }

        var temporary = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(socketFD, &temporary, temporary.count)
            if count > 0 {
                receiveBuffer.append(temporary, count: count)
                if receiveBuffer.count > maximumFrameBytes + 4 {
                    disconnect(nextAvailability: .unavailable)
                    return
                }
                processFrames()
                guard socketFD >= 0 else { return }
                continue
            }

            if count == 0 {
                disconnect(nextAvailability: .unavailable)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }
            if errno == EINTR {
                continue
            }
            disconnect(nextAvailability: .unavailable)
            return
        }
    }

    private func processFrames() {
        while receiveBuffer.count >= 4 {
            let payloadLength = receiveBuffer.prefix(4).enumerated().reduce(0) {
                $0 | (Int($1.element) << (8 * $1.offset))
            }
            guard payloadLength >= 0, payloadLength <= maximumFrameBytes else {
                disconnect(nextAvailability: .unavailable)
                return
            }
            guard receiveBuffer.count >= payloadLength + 4 else { return }

            let payload = receiveBuffer.subdata(in: 4..<(payloadLength + 4))
            receiveBuffer.removeSubrange(0..<(payloadLength + 4))
            guard let object = try? JSONSerialization.jsonObject(with: payload),
                  let message = object as? [String: Any] else {
                disconnect(nextAvailability: .unavailable)
                return
            }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "response":
            handleResponse(message)
        case "broadcast":
            handleBroadcast(message)
        case "client-discovery-request":
            handleClientDiscoveryRequest(message)
        default:
            break
        }
    }

    private func handleClientDiscoveryRequest(_ message: [String: Any]) {
        guard let requestID = message["requestId"] as? String else { return }
        _ = send([
            "type": "client-discovery-response",
            "requestId": requestID,
            "response": ["canHandle": false]
        ])
    }

    private func handleResponse(_ message: [String: Any]) {
        guard let requestID = message["requestId"] as? String,
              requestID == initializeRequestID else { return }

        guard message["resultType"] as? String == "success",
              message["method"] as? String == "initialize",
              let result = message["result"] as? [String: Any],
              let assignedClientID = result["clientId"] as? String else {
            disconnect(nextAvailability: .unavailable)
            return
        }

        clientID = assignedClientID
        initializeRequestID = nil
        initializeStartedAt = nil
        discoverAndSubscribe()
    }

    private func handleBroadcast(_ message: [String: Any]) {
        guard let method = message["method"] as? String else { return }

        if method == "client-status-changed" {
            handleClientStatusChanged(message)
            return
        }

        if method == "thread-stream-following-status-requested" {
            handleFollowingStatusRequested(message)
            return
        }

        guard method == "thread-stream-state-changed",
              let params = message["params"] as? [String: Any],
              params["hostId"] as? String == "local",
              let conversationID = params["conversationId"] as? String,
              subscribedConversationIDs.contains(conversationID),
              let change = params["change"] as? [String: Any],
              let changeType = change["type"] as? String else { return }

        let sourceClientID = message["sourceClientId"] as? String
        switch changeType {
        case "snapshot":
            guard let conversationState = change["conversationState"] as? [String: Any],
                  let runtimeStatus = conversationState["threadRuntimeStatus"]
                    as? [String: Any],
                  let statusType = runtimeStatus["type"] as? String else {
                requestFreshSnapshot(for: conversationID)
                return
            }
            statusByConversationID[conversationID] = statusType
            conversationsAwaitingOwner.remove(conversationID)
            if let sourceClientID {
                ownerByConversationID[conversationID] = sourceClientID
            }
            if let revision = integer(change["revision"]) {
                revisionByConversationID[conversationID] = revision
            }
            emitState()

        case "patches":
            handlePatches(change,
                          conversationID: conversationID,
                          sourceClientID: sourceClientID)

        default:
            break
        }
    }

    private func handlePatches(_ change: [String: Any],
                               conversationID: String,
                               sourceClientID: String?) {
        guard !conversationsAwaitingOwner.contains(conversationID) else {
            requestFreshSnapshot(for: conversationID)
            return
        }

        if let owner = ownerByConversationID[conversationID],
           let sourceClientID,
           owner != sourceClientID {
            requestFreshSnapshot(for: conversationID)
            return
        }

        if let expectedBase = revisionByConversationID[conversationID],
           let actualBase = integer(change["baseRevision"]),
           expectedBase != actualBase {
            requestFreshSnapshot(for: conversationID)
            return
        }

        guard let patches = change["patches"] as? [[String: Any]] else {
            requestFreshSnapshot(for: conversationID)
            return
        }

        var statusChanged = false
        var needsSnapshot = false
        for patch in patches {
            guard let rawPath = patch["path"] as? [Any] else { continue }
            let path = rawPath.compactMap { element -> String? in
                if let text = element as? String { return text }
                if let number = element as? NSNumber { return number.stringValue }
                return nil
            }
            guard path.first == "threadRuntimeStatus" else { continue }

            let operation = patch["op"] as? String
            if operation == "remove" {
                needsSnapshot = true
                continue
            }

            if path.count == 1,
               let value = patch["value"] as? [String: Any],
               let statusType = value["type"] as? String {
                statusByConversationID[conversationID] = statusType
                statusChanged = true
            } else if path.count == 2,
                      path[1] == "type",
                      let statusType = patch["value"] as? String {
                statusByConversationID[conversationID] = statusType
                statusChanged = true
            } else {
                needsSnapshot = true
            }
        }

        if let revision = integer(change["revision"]) {
            revisionByConversationID[conversationID] = revision
        }
        if needsSnapshot {
            requestFreshSnapshot(for: conversationID)
        } else if statusChanged {
            emitState()
        }
    }

    private func handleFollowingStatusRequested(_ message: [String: Any]) {
        guard let params = message["params"] as? [String: Any],
              params["hostId"] as? String == "local",
              let conversationID = params["conversationId"] as? String,
              subscribedConversationIDs.contains(conversationID) else { return }

        sendFollowing(conversationID: conversationID, following: true)
    }

    private func handleClientStatusChanged(_ message: [String: Any]) {
        guard let params = message["params"] as? [String: Any],
              params["status"] as? String == "disconnected",
              let disconnectedClientID = params["clientId"] as? String else { return }

        let affected = ownerByConversationID.compactMap {
            $0.value == disconnectedClientID ? $0.key : nil
        }
        guard !affected.isEmpty else { return }

        for conversationID in affected {
            let wasActive = statusByConversationID[conversationID] == "active"
            ownerByConversationID.removeValue(forKey: conversationID)
            revisionByConversationID.removeValue(forKey: conversationID)
            if wasActive {
                conversationsAwaitingOwner.insert(conversationID)
            } else {
                statusByConversationID.removeValue(forKey: conversationID)
            }
            requestFreshSnapshot(for: conversationID)
        }
        if conversationsAwaitingOwner.isEmpty {
            emitState()
        } else {
            setAvailability(.unavailable)
        }
    }

    private func discoverAndSubscribe() {
        guard clientID != nil else { return }
        guard let candidates = discoverCandidateConversationIDs() else {
            setAvailability(.unavailable)
            return
        }

        let removed = subscribedConversationIDs.subtracting(candidates)
        for conversationID in removed {
            sendFollowing(conversationID: conversationID, following: false)
            statusByConversationID.removeValue(forKey: conversationID)
            ownerByConversationID.removeValue(forKey: conversationID)
            revisionByConversationID.removeValue(forKey: conversationID)
            conversationsAwaitingOwner.remove(conversationID)
        }

        let added = candidates.subtracting(subscribedConversationIDs)
        subscribedConversationIDs = candidates
        for conversationID in added {
            sendFollowing(conversationID: conversationID, following: true)
        }

        guard socketFD >= 0, clientID != nil else { return }
        guard conversationsAwaitingOwner.isEmpty else {
            setAvailability(.unavailable)
            return
        }
        if availability == .available {
            emitState()
            return
        }

        let currentGeneration = generation
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self,
                  self.running,
                  self.generation == currentGeneration,
                  self.clientID != nil,
                  self.conversationsAwaitingOwner.isEmpty else { return }
            self.setAvailability(.available)
        }
    }

    private func discoverCandidateConversationIDs() -> Set<String>? {
        guard let databaseURL = stateDatabaseURL else { return nil }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        let query = """
            SELECT id
            FROM threads
            WHERE archived = 0 AND updated_at >= ?
            ORDER BY updated_at DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if statement != nil { sqlite3_finalize(statement) }
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let cutoff = Int64(Date().timeIntervalSince1970) - candidateAgeSeconds
        sqlite3_bind_int64(statement, 1, cutoff)
        sqlite3_bind_int(statement, 2, maximumCandidateCount)

        var result = Set<String>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                guard let text = sqlite3_column_text(statement, 0) else { continue }
                result.insert(String(cString: text))
            } else if step == SQLITE_DONE {
                return result
            } else {
                return nil
            }
        }
    }

    private func sendFollowing(conversationID: String, following: Bool) {
        guard let clientID else { return }
        let message: [String: Any] = [
            "type": "broadcast",
            "method": "thread-stream-following-changed",
            "sourceClientId": clientID,
            "version": 1,
            "params": [
                "conversationId": conversationID,
                "hostId": "local",
                "following": following
            ]
        ]
        if !send(message) {
            disconnect(nextAvailability: .unavailable)
        }
    }

    private func requestFreshSnapshot(for conversationID: String) {
        guard subscribedConversationIDs.contains(conversationID) else { return }
        sendFollowing(conversationID: conversationID, following: true)
    }

    private func unsubscribeAll() {
        guard socketFD >= 0, clientID != nil else { return }
        for conversationID in Array(subscribedConversationIDs) {
            sendFollowing(conversationID: conversationID, following: false)
        }
    }

    private func send(_ message: [String: Any]) -> Bool {
        guard socketFD >= 0,
              JSONSerialization.isValidJSONObject(message),
              let payload = try? JSONSerialization.data(withJSONObject: message),
              payload.count <= maximumFrameBytes else { return false }

        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)

        return frame.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(socketFD,
                                         baseAddress.advanced(by: offset),
                                         rawBuffer.count - offset)
                if count > 0 {
                    offset += count
                    continue
                }
                if count < 0 && errno == EINTR {
                    continue
                }
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    var item = pollfd(fd: socketFD,
                                      events: Int16(POLLOUT),
                                      revents: 0)
                    if Darwin.poll(&item, 1, 1_000) > 0 {
                        continue
                    }
                }
                return false
            }
            return true
        }
    }

    private func disconnect(nextAvailability: CodexMonitorAvailability) {
        generation += 1
        readSource?.cancel()
        readSource = nil
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
        receiveBuffer.removeAll(keepingCapacity: true)
        initializeRequestID = nil
        initializeStartedAt = nil
        clientID = nil
        subscribedConversationIDs.removeAll()
        statusByConversationID.removeAll()
        ownerByConversationID.removeAll()
        revisionByConversationID.removeAll()
        conversationsAwaitingOwner.removeAll()
        setAvailability(nextAvailability)
    }

    private func setAvailability(_ next: CodexMonitorAvailability) {
        availability = next
        emitState()
    }

    private func emitState() {
        let activeCount = statusByConversationID.values.reduce(0) {
            $0 + ($1 == "active" ? 1 : 0)
        }
        let state = CodexActivityState(availability: availability,
                                       activeCount: activeCount)
        guard state != lastEmittedState else { return }
        lastEmittedState = state
        let updateHandler = updateHandler
        DispatchQueue.main.async {
            updateHandler(state)
        }
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private var codexHomeURL: URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !configured.isEmpty {
            return URL(fileURLWithPath: NSString(string: configured)
                .expandingTildeInPath,
                       isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private var ipcDirectoryURL: URL {
        codexHomeURL.appendingPathComponent("ipc", isDirectory: true)
    }

    private var ipcSocketURL: URL {
        ipcDirectoryURL.appendingPathComponent("ipc.sock")
    }

    private var stateDatabaseURL: URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: codexHomeURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return entries.compactMap { url -> (version: Int, url: URL)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite") else {
                return nil
            }
            let start = name.index(name.startIndex, offsetBy: "state_".count)
            let end = name.index(name.endIndex, offsetBy: -".sqlite".count)
            guard start < end, let version = Int(name[start..<end]) else {
                return nil
            }
            return (version, url)
        }
        .max { $0.version < $1.version }?
        .url
    }

    private func validateIPCPath() -> Bool {
        var directoryInfo = stat()
        var socketInfo = stat()
        guard lstat(ipcDirectoryURL.path, &directoryInfo) == 0,
              lstat(ipcSocketURL.path, &socketInfo) == 0 else { return false }

        let currentUID = getuid()
        let directoryType = directoryInfo.st_mode & mode_t(S_IFMT)
        let socketType = socketInfo.st_mode & mode_t(S_IFMT)
        let unsafeWriteBits = mode_t(S_IWGRP | S_IWOTH)

        return directoryType == mode_t(S_IFDIR)
            && socketType == mode_t(S_IFSOCK)
            && directoryInfo.st_uid == currentUID
            && socketInfo.st_uid == currentUID
            && directoryInfo.st_mode & unsafeWriteBits == 0
            && socketInfo.st_mode & unsafeWriteBits == 0
    }
}
