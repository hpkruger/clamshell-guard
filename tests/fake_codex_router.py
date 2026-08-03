#!/usr/bin/env python3

import json
import os
import socket
import sqlite3
import struct
import sys
import time
from pathlib import Path


CONVERSATION_ID = "00000000-0000-0000-0000-000000000001"
SIDE_AGENT_ID = "00000000-0000-0000-0000-000000000002"


def send_frame(connection: socket.socket, message: dict) -> None:
    payload = json.dumps(message, separators=(",", ":")).encode()
    connection.sendall(struct.pack("<I", len(payload)) + payload)


def receive_frames(connection: socket.socket, buffer: bytearray) -> list[dict]:
    try:
        chunk = connection.recv(65536)
    except socket.timeout:
        return []
    if not chunk:
        raise EOFError
    buffer.extend(chunk)

    messages = []
    while len(buffer) >= 4:
        payload_length = struct.unpack("<I", buffer[:4])[0]
        if len(buffer) < payload_length + 4:
            break
        payload = bytes(buffer[4 : payload_length + 4])
        del buffer[: payload_length + 4]
        messages.append(json.loads(payload))
    return messages


def state_snapshot(
    owner: str,
    revision: int,
    status: str,
    conversation_id: str,
    side_agent_status: str | None = None,
) -> dict:
    conversation_state = {
        "threadRuntimeStatus": {"type": status, "activeFlags": []}
    }
    if side_agent_status is not None:
        conversation_state["turns"] = [
            {
                "items": [
                    {
                        "type": "collabAgentToolCall",
                        "agentsStates": {
                            SIDE_AGENT_ID: {"status": side_agent_status}
                        },
                    }
                ]
            }
        ]

    return {
        "type": "broadcast",
        "method": "thread-stream-state-changed",
        "sourceClientId": owner,
        "version": 11,
        "params": {
            "conversationId": conversation_id,
            "hostId": "local",
            "change": {
                "type": "snapshot",
                "revision": revision,
                "conversationState": conversation_state,
            },
        },
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fake_codex_router.py <codex-home>", file=sys.stderr)
        return 2

    codex_home = Path(sys.argv[1])
    ipc_directory = codex_home / "ipc"
    ipc_directory.mkdir(parents=True, mode=0o700)
    os.chmod(ipc_directory, 0o700)

    database = sqlite3.connect(codex_home / "state_5.sqlite")
    database.execute(
        "CREATE TABLE threads (id TEXT PRIMARY KEY, updated_at INTEGER, archived INTEGER)"
    )
    database.execute(
        "INSERT INTO threads VALUES (?, ?, 0)",
        (CONVERSATION_ID, int(time.time())),
    )
    database.execute(
        "INSERT INTO threads VALUES (?, ?, 0)",
        (SIDE_AGENT_ID, int(time.time())),
    )
    database.commit()
    database.close()

    socket_path = ipc_directory / "ipc.sock"
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(socket_path))
    os.chmod(socket_path, 0o600)
    server.listen(1)
    (codex_home / "ready").touch()

    connection, _ = server.accept()
    connection.settimeout(0.05)
    buffer = bytearray()
    initialized = False
    following_count = 0
    side_snapshot_sent = False
    disconnect_at = None
    status_request_sent = False
    status_request_at = None
    recovery_snapshot_sent = False
    side_agent_completion_at = None
    idle_disconnect_at = None
    deadline = time.monotonic() + 12

    try:
        while time.monotonic() < deadline:
            now = time.monotonic()
            if disconnect_at is not None and now >= disconnect_at:
                send_frame(
                    connection,
                    {
                        "type": "broadcast",
                        "method": "client-status-changed",
                        "sourceClientId": "router",
                        "params": {
                            "clientId": "owner-1",
                            "status": "disconnected",
                        },
                    },
                )
                disconnect_at = None
                status_request_at = now + 0.2

            if status_request_at is not None and now >= status_request_at:
                send_frame(
                    connection,
                    {
                        "type": "broadcast",
                        "method": "thread-stream-following-status-requested",
                        "sourceClientId": "owner-2",
                        "version": 1,
                        "params": {
                            "conversationId": CONVERSATION_ID,
                            "hostId": "local",
                        },
                    },
                )
                status_request_at = None
                status_request_sent = True

            if (
                status_request_sent
                and following_count >= 3
                and not recovery_snapshot_sent
            ):
                send_frame(
                    connection,
                    state_snapshot(
                        "owner-2",
                        2,
                        "idle",
                        CONVERSATION_ID,
                        "running",
                    ),
                )
                recovery_snapshot_sent = True
                side_agent_completion_at = now + 3.5

            if (
                side_agent_completion_at is not None
                and now >= side_agent_completion_at
            ):
                send_frame(
                    connection,
                    {
                        "type": "broadcast",
                        "method": "thread-stream-state-changed",
                        "sourceClientId": "owner-2",
                        "version": 11,
                        "params": {
                            "conversationId": CONVERSATION_ID,
                            "hostId": "local",
                            "change": {
                                "type": "patches",
                                "baseRevision": 2,
                                "revision": 3,
                                "patches": [
                                    {
                                        "op": "replace",
                                        "path": [
                                            "turns",
                                            0,
                                            "items",
                                            0,
                                            "agentsStates",
                                            SIDE_AGENT_ID,
                                            "status",
                                        ],
                                        "value": "completed",
                                    }
                                ],
                            },
                        },
                    },
                )
                send_frame(
                    connection,
                    {
                        "type": "broadcast",
                        "method": "thread-stream-state-changed",
                        "sourceClientId": "side-owner",
                        "version": 11,
                        "params": {
                            "conversationId": SIDE_AGENT_ID,
                            "hostId": "local",
                            "change": {
                                "type": "patches",
                                "baseRevision": 1,
                                "revision": 2,
                                "patches": [
                                    {
                                        "op": "replace",
                                        "path": [
                                            "threadRuntimeStatus",
                                            "type",
                                        ],
                                        "value": "idle",
                                    }
                                ],
                            },
                        },
                    },
                )
                side_agent_completion_at = None
                idle_disconnect_at = now + 0.2

            if idle_disconnect_at is not None and now >= idle_disconnect_at:
                send_frame(
                    connection,
                    {
                        "type": "broadcast",
                        "method": "client-status-changed",
                        "sourceClientId": "router",
                        "params": {
                            "clientId": "owner-2",
                            "status": "disconnected",
                        },
                    },
                )
                idle_disconnect_at = None

            try:
                messages = receive_frames(connection, buffer)
            except EOFError:
                break

            for message in messages:
                if message.get("method") == "initialize":
                    send_frame(
                        connection,
                        {
                            "type": "response",
                            "requestId": message["requestId"],
                            "resultType": "success",
                            "method": "initialize",
                            "result": {"clientId": "awake-test"},
                        },
                    )
                    initialized = True
                    continue

                if (
                    initialized
                    and message.get("method") == "thread-stream-following-changed"
                    and message.get("params", {}).get("following") is True
                ):
                    followed_id = message.get("params", {}).get("conversationId")
                    if followed_id == SIDE_AGENT_ID and not side_snapshot_sent:
                        send_frame(
                            connection,
                            state_snapshot(
                                "side-owner",
                                1,
                                "active",
                                SIDE_AGENT_ID,
                            ),
                        )
                        side_snapshot_sent = True
                    elif followed_id == CONVERSATION_ID:
                        following_count += 1
                    if followed_id == CONVERSATION_ID and following_count == 1:
                        send_frame(
                            connection,
                            state_snapshot(
                                "owner-1",
                                1,
                                "idle",
                                CONVERSATION_ID,
                                "running",
                            ),
                        )
                        disconnect_at = time.monotonic() + 1.5

        if not recovery_snapshot_sent:
            print(
                "monitor did not reassert following after the owner requested status",
                file=sys.stderr,
            )
            return 1
        return 0
    finally:
        connection.close()
        server.close()


if __name__ == "__main__":
    raise SystemExit(main())
