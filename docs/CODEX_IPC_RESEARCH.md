# Codex Desktop task-status research

Research date: 29 July 2026

## Purpose

AwakeToggle's AUTO mode needs to know whether Codex Desktop has any active
tasks. The original implementation used Codex lifecycle hooks to increment and
decrement a local marker count. That count can become stale when a hook is
missed, a task is cancelled, Codex exits unexpectedly, or hook approval and
configuration differ between installations.

This document records the replacement investigation so future maintenance does
not have to rediscover the private protocol from scratch.

## Result

The current Codex Desktop build exposes a per-user Unix-domain socket at:

```text
~/.codex/ipc/ipc.sock
```

An initialized client can broadcast that it is following a known conversation.
The Codex Desktop window that owns that conversation immediately returns a
state snapshot and subsequently streams state patches. The snapshot contains:

```json
{
  "conversationState": {
    "threadRuntimeStatus": {
      "type": "active",
      "activeFlags": []
    }
  }
}
```

This gives AwakeToggle the state Codex itself is using instead of requiring a
separate counter.

The IPC interface is private and unsupported. It can change in a future Codex
release, so failure must be treated as "status unavailable", never as proof
that there are no active tasks.

## Verified protocol

The following details were verified against the installed
`/Applications/ChatGPT.app` build and with read-only probes against the live
socket:

1. Each frame starts with a four-byte unsigned little-endian JSON payload
   length, followed by UTF-8 JSON.
2. The maximum frame length in the inspected implementation is 256 MiB.
   AwakeToggle deliberately imposes a lower 64 MiB limit and treats anything
   larger as incompatible rather than allocating up to the router maximum.
3. A client initializes with a request shaped like:

   ```json
   {
     "type": "request",
     "requestId": "<uuid>",
     "sourceClientId": "initializing-client",
     "version": 0,
     "method": "initialize",
     "params": {
       "clientType": "awaketoggle"
     }
   }
   ```

4. The successful response contains `result.clientId`.
5. For every candidate conversation ID, the client broadcasts:

   ```json
   {
     "type": "broadcast",
     "method": "thread-stream-following-changed",
     "sourceClientId": "<client id>",
     "version": 1,
     "params": {
       "conversationId": "<conversation id>",
       "hostId": "local",
       "following": true
     }
   }
   ```

6. If a connected Codex Desktop window owns the conversation, it sends a
   targeted `thread-stream-state-changed` broadcast. Its `params.change` is
   initially a `snapshot` and later a sequence of JSON patches.
7. Repeating `following: true` requests a fresh snapshot. This is useful for
   recovery, but should not be used as frequent polling because a snapshot can
   contain the complete conversation state.
8. Sending `following: false` removes the subscription. Socket disconnect also
   cleans up the follower registration.
9. When a conversation becomes an owner after an IPC client reconnects and it
   has no recorded followers, it broadcasts
   `thread-stream-following-status-requested`. Existing followers respond by
   broadcasting `thread-stream-following-changed` with `following: true`
   again. The owner then sends a fresh snapshot.

At the time of inspection, `thread-stream-following-changed` was protocol
version 1, `thread-stream-following-status-requested` was version 1, and
`thread-stream-state-changed` was version 11. AwakeToggle only sends the first
of these. It accepts incoming state messages by method and payload shape rather
than rejecting a future incoming version number.

The inspected owner accepts a following broadcast only when its version exactly
matches the version it knows. A version mismatch is ignored without an error or
acknowledgement. Because an unloaded historical conversation also produces no
response, silence alone cannot always prove that the protocol is incompatible.

## Discovering conversation IDs

The IPC follower operation requires a conversation ID. Codex's local state
database supplies candidates:

```text
~/.codex/state_5.sqlite
```

The `threads` table contains `id`, `updated_at`, and `archived`. It does not
contain live runtime status. AwakeToggle therefore uses SQLite only for
discovery, then asks the IPC owner for authoritative status.

The tested strategy is:

- Open the database read-only.
- Select non-archived IDs updated within the last seven days, newest first,
  with a bounded result count.
- Subscribe once to newly discovered IDs.
- Re-run the discovery query periodically so newly created tasks are found.

An active task updates its database row when work starts, so it enters the
candidate window. Loaded conversations respond to the follower broadcast;
unloaded historical conversations do not.

## Validation performed

Ten task IDs updated within the previous 24 hours were submitted to the current
socket. Three loaded conversations returned snapshots:

- two had `threadRuntimeStatus.type == "active"`;
- one had `threadRuntimeStatus.type == "idle"`.

Codex Desktop's own internal task listing independently reported the same two
active tasks and the same idle task.

After implementation, a standalone build of `CodexIPCMonitor` observed the
current live task and reported `connecting / 0`, `connecting / 1`, then
`available / 1`. The installed app was also tested from a known OFF baseline:
AUTO changed `SleepDisabled` from `0` to `1` within three seconds and it
remained `1` beyond the ten-second grace window. ON opened no Codex IPC
connection, while AUTO did.

The repository's fake-router integration test additionally verifies:

- an initial active snapshot is observed before the monitor settles as
  available;
- an owner disconnect preserves the last active count but changes availability
  to unavailable;
- `thread-stream-following-status-requested` causes AwakeToggle to reassert
  `following: true`;
- a fresh snapshot from the replacement owner restores availability; and
- a subsequent active-to-idle patch is applied without treating a later idle
  owner disconnect as an unknown active task.

Run this coverage with:

```bash
./tests/run.sh
```

The initial active and idle snapshots, aggregate count, and active AUTO
transition were therefore verified. Further release testing should still
cover:

- normal task completion;
- user cancellation;
- force-quitting Codex;
- Codex restart;
- AwakeToggle restart;
- concurrent tasks;
- a Codex application update.

## Approaches rejected

### Hook-maintained counter

Hooks describe events, but a counter is only correct if every matching start
and stop event is delivered and processed. Cancellation and process failure can
leave stale state. The hook solution was therefore removed rather than retained
as a second source of truth.

### Generic IPC `thread/list` request

An unofficial Codex IPC proof of concept wraps `thread/list` in a
`send-cli-request-for-host` request. Its framing and initialization information
were useful, but that request returned `no-client-found` with the current
Desktop build. Current connected Desktop IPC clients expose the thread-follower
messages, not that generic request route.

Do not copy the proof of concept wholesale: it also contains mutating commands,
and protocol versions shown there are already older than the inspected build.

### Separate `codex app-server`

The official app-server protocol has proper `thread/status/changed` events with
active and idle states. However, a separately launched app-server does not
currently attach to the live app-server instance and in-memory task state owned
by Codex Desktop. The documented app-server control socket is a separate
interface, not the Desktop IPC socket.

### Process monitoring

Codex can be active while waiting, sleeping, or awaiting approval with no useful
CPU signal. One app-server process also serves multiple tasks, so process
existence cannot produce a reliable active-task count.

### Log-database inference

`~/.codex/logs_2.sqlite` contains turn events, but correlating all start and
completion records to Desktop conversations is implementation-dependent.
Reading a large diagnostic database is also less direct and more
privacy-sensitive than consuming the runtime state already published on IPC.

## Security and privacy

- The inspected router creates its IPC directory with mode `0700` and socket
  with mode `0600`.
- AwakeToggle must verify that the directory and socket are owned by the current
  user before connecting.
- The socket has no additional application-level authentication; same-user
  filesystem access is its security boundary.
- Snapshots may contain conversation history and other task data. AwakeToggle
  must extract only `threadRuntimeStatus`, must not persist the payload, and
  must never log raw messages.
- The monitor is local-only and performs no network requests.

## Failure behavior

AUTO mode distinguishes these states:

- **available with active tasks**: keep awake;
- **available with no active tasks**: allow sleep after the ten-second grace
  period;
- **unavailable or incompatible**: show a status-unavailable message and avoid
  claiming there are zero active tasks.

The connection should be retried after failure. On reconnect, clear stale IPC
state, rediscover candidate IDs, and request fresh snapshots.

If an active conversation's owner disconnects, retain its last known active
status and treat the monitor as unavailable until a replacement owner supplies
a valid snapshot. An idle conversation cannot begin new work without an owner,
so its status does not need the same fail-safe. The replacement owner can
recover existing followers with
`thread-stream-following-status-requested`.

Initial availability uses a one-second settling window after candidate
subscriptions are sent. This is a heuristic rather than a protocol
acknowledgement: unloaded historical conversations intentionally remain silent.
Detectable socket, database, framing, and payload failures become unavailable,
but a future owner that silently ignores the current following method or
version may be indistinguishable from having no loaded conversations. A Codex
application update therefore remains a required compatibility smoke test.

## Sources

- [Official Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [OpenAI Codex issue #25914: attach to an active Desktop thread](https://github.com/openai/codex/issues/25914)
- [OpenAI Codex issue #21743: Desktop app-server control-socket limitation](https://github.com/openai/codex/issues/21743)
- [OpenAI Codex issue #21806: thread-stream snapshot overload report](https://github.com/openai/codex/issues/21806)
- [Unofficial Codex IPC Tool proof of concept](https://gist.github.com/InfinityMod/ecc1f441f7447824ff114b8a41debec2)
