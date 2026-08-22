# PROTOCOL.md - How The Lounge.app talks to the server

The Lounge.app speaks the same application protocol as the official The
Lounge web client, over Socket.IO v5 / Engine.IO v4 on WebSocket. This
document describes that conversation end to end: connection setup, framing,
authentication, state synchronization, and every event either side sends.

Pinned reference: The Lounge **4.5.0**
(commit `dd2108fa8094947473f8e94dd937461a71d0442d`, tag `v4.5.0`),
socket.io 4.6.2 / socket.io-client 4.5.0, wire protocols Socket.IO v5 and
Engine.IO v4 (`EIO=4`).

The Lounge is itself the IRC client. TheLounge.app never talks to IRC
networks directly; it is one more client of the The Lounge server, which
keeps the IRC session alive independently of any single connected client.

## 1. Endpoint and transport

The Socket.IO endpoint is at the The Lounge installation path plus
`socket.io/`:

    https://example.org/           ->  wss://example.org/socket.io/?EIO=4&transport=websocket
    https://example.org/thelounge/ ->  wss://example.org/thelounge/socket.io/?EIO=4&transport=websocket

The installation path must not be assumed to be `/`. The client derives it
from the configured server URL (path kept, trailing slash ensured); scheme
maps http->ws, https->wss.

Transport is WebSocket only (libcurl `CURLOPT_CONNECT_ONLY=2`). TLS
certificate and hostname verification are always on.

### Frame delivery note (libcurl)

libcurl may split one WebSocket frame across several `curl_ws_recv` calls,
without setting `CURLWS_CONT` on continuations. Frames are reassembled using
`curl_ws_frame.offset` (0 marks the first chunk) until
`curl_ws_frame.bytesleft == 0`.

## 2. Framing

### Engine.IO v4 packets

Each Engine.IO packet is one leading digit followed by its payload:

| Code | Type    | Direction | Meaning                          |
| ---- | ------- | --------- | -------------------------------- |
| 0    | open    | S -> C    | handshake JSON                   |
| 1    | close   | S/C       | close transport                  |
| 2    | ping    | S -> C    | heartbeat probe                  |
| 3    | pong    | C -> S    | heartbeat reply                  |
| 4    | message | both      | carries one Socket.IO packet     |
| 5    | upgrade | C -> S    | (informational here)             |
| 6    | noop    | S -> C    | keepalive                        |

Connection sequence over a fresh WebSocket:

1. Server sends `0{"sid":..,"pingInterval":25000,"pingTimeout":60000,..}`.
2. Client sends `40` (Socket.IO CONNECT, see below). The websocket transport
   is already chosen, so the polling-probe upgrade dance does not apply.
3. All further traffic travels as Engine.IO `4` messages:
   `4<socket.io-payload>`.

Heartbeat: the server sends `2`; the client answers `3` immediately. A
watchdog closes the connection if nothing arrives for
`pingInterval + pingTimeout + margin` (~50 s at default settings).

### Socket.IO v5 packets

Inside Engine.IO `4` messages, each packet is a type digit, optional
namespace, optional ack id, then JSON data:

| Code | Type          |
| ---- | ------------- |
| 0    | CONNECT       |
| 1    | DISCONNECT    |
| 2    | EVENT         |
| 3    | ACK           |
| 4    | CONNECT_ERROR |
| 5    | BINARY_EVENT  |

Events carry a JSON array whose first element is the event name:

    42["auth:perform",{"user":"u","password":"p"}]

The Lounge uses only the default namespace (`/`, empty prefix). Binary
events are not used by this protocol surface. Acknowledgements (`42<id>[...]`
answered by `43<id>[...]`) exist in Socket.IO but The Lounge does all
request/response at the event level; the client never needs to answer acks.

## 3. Authentication

There is no authentication at the transport layer. After namespace CONNECT:

1. Server emits `auth:start(serverHash:number)`. A changed `serverHash` on a
   later connection means the server restarted.
2. Client emits exactly one `auth:perform`:

   Password (first login):

        ["auth:perform", {"user":"<u>", "password":"<p>"}]

   Fast auth (session restore):

        ["auth:perform", {
            "user": "<u>",
            "token": "<token>",
            "lastMessage": <highest known msg id, -1 if none>,
            "openChannel": <selected channel id or null>,
            "hasConfig": <true if configuration was received this session>
        }]

   Public-mode servers authenticate automatically and skip this step.
3. Failure: server emits `auth:failed`.
4. Success, in order: `auth:success`; then, when `hasConfig` was false,
   `configuration` and `push:issubscribed`; then `init`; then `commands`.

After a successful `auth:perform` the server rejects further attempts on the
same socket. On first password login the `init` payload carries `"token"` -
persist it (user + token, file permissions 0600) and use fast auth from then
on. Tokens and passwords must never appear in logs.

## 4. State: the `init` payload

    { "active": <channel id or null>,
      "networks": [ <network> ... ],
      "token": "<first password login only>" }

Network:

    { "uuid", "name", "nick",
      "serverOptions": {CHANTYPES, PREFIX{symbol/mode maps}, NETWORK},
      "status": {"connected": bool, "secure": bool},
      "channels": [ <channel> ... ] }

Channel:

    { "id", "name", "type": channel|lobby|query|special,
      "state": PARTED=0|JOINED=1, "topic", "key",
      "unread", "highlight", "firstUnread", "muted", "closed",
      "totalMessages", "num_users",
      "messages": [ <message> ... ] }

Message volume rules:

* Fresh login: active channel gets up to 100 most recent messages, every
  other channel exactly 1 (for the sidebar preview).
* Fast auth with `lastMessage > -1`: only messages with `id > lastMessage`,
  capped at 100. The client MUST merge these into existing model state
  instead of replacing it.

## 5. Server -> client events

Handled by the client:

| Event                | Payload                                | Action |
| -------------------- | -------------------------------------- | ------ |
| `auth:start`         | `serverHash`                           | trigger `auth:perform` |
| `auth:success`       | -                                      | authenticated; expect configuration/init |
| `auth:failed`        | -                                      | show auth error |
| `configuration`      | config object                          | store server configuration |
| `init`               | `{active,networks,token?}`             | build/merge server state; ready |
| `commands`           | `[string]`                             | available input commands |
| `msg`                | `{chan, msg, highlight?, unread?}`     | append message, update unread |
| `more`               | `{chan, messages[], totalMessages}`    | prepend history page |
| `names`              | `{id, users[]}`                        | replace channel user list |
| `users`              | `{chan}`                               | users changed; request `names` |
| `open`               | `channelId`                            | mark opened/cleared unread |
| `join`               | `{shouldOpen, network(uuid), chan}`    | add channel, optionally select |
| `part`               | `{chan}`                               | remove channel |
| `quit`               | `{network}`                            | remove network |
| `nick`               | `{network, nick}`                      | own nick changed |
| `network`            | `{network}`                            | add/update network |
| `network:options`    | `{network, serverOptions}`             | update IRC options |
| `network:status`     | `{network, connected, secure}`         | update status badge |
| `network:name`       | `{uuid, name}`                         | rename network |
| `topic`              | `{chan, topic}`                        | update topic |
| `channel:state`      | `{chan, state}`                        | JOINED/PARTED |
| `mute:changed`       | `{target, status}`                     | mute flag |
| `history:clear`      | `{target}`                             | clear channel history |
| `sync_sort:networks` | `{order:[uuid]}`                       | reorder networks |
| `sync_sort:channels` | `{network, order:[id]}`                | reorder channels |
| `error`              | any                                    | error notification |

Ignorable optional events (safe for this client): `push:*`, `setting:new`,
`setting:all`, `mentions:list`, `sessions:list`, `sign-out`, `connecting`,
`changelog`, `msg:preview`, `msg:special`, `search:results`,
`change-password`, `upload:auth`, `network:info` (reply to `network:get`,
which this client does not send yet).

## 6. Client -> server events

| Event           | Payload                                   | Used for |
| --------------- | ----------------------------------------- | -------- |
| `auth:perform`  | see section 3                             | authenticate |
| `input`         | `{target: channelId, text}`               | send message or command |
| `open`          | `channelId`                               | mark read when switching |
| `names`         | `{target: channelId}`                     | request user list |
| `more`          | `{target, lastId, condensed:false}`       | request older history |
| `history:clear` | `{target}`                                | clear history |

Sending: `text` without leading `/` is a plain message. `/command args` is a
command line parsed by the server (`//` escapes to a literal message). The
client keeps the slash intact and lets the server parse - e.g.
`/join #room` runs JOIN and produces a `join` event with `shouldOpen`.

## 7. History and identity

* Message `id`: monotonically increasing integer, authoritative for ordering
  and dedup. `msgid` (IRCv3) is an optional stable id.
* `more` returns strictly older messages than `lastId`, max 100 (1000 when
  `condensed:true`).
* Commands receive no protocol-level acknowledgement; the client must not
  replay them on reconnect.

## 8. Unread state

Channels carry `unread`, `highlight`, `firstUnread`. Each `msg` event reports
the post-update values. Opening a channel resets local counters and the
client sends `open`. On reconnect, server-side values in the merged `init`
win over stale local ones.

## 9. Reconnection

1. Transport or socket drops; client backs off exponentially (1 s base,
   x2 per attempt, 30 s cap) with jitter, then reconnects.
2. New Engine.IO/Socket.IO handshake; server emits `auth:start`.
3. Client fast-auths with stored token, `lastMessage` (highest known id),
   `openChannel`, `hasConfig:false` on a new socket.
4. Merge the delta `init` into local state; do not replace it.
5. If `serverHash` differs from the previous connection, the server
   restarted; treat state as fresh.

Closing TheLounge.app never terminates the user's IRC presence; the bouncer
stays connected to networks.

## 10. Redaction

Any protocol trace output must redact `password`, `token`, and session
credentials. The development tool `thelounge-protocol-dump` applies this
automatically.
