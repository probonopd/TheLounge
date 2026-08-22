# Compatibility

This document records the protocol compatibility status of the native GNUstep
client against The Lounge, following the structure required by SPEC section 48.
No compatibility with an untested release is claimed.

| Item | Value |
| ---- | ----- |
| The Lounge version | 4.5.x (4.5.0) |
| Pinned source commit | `dd2108fa8096949473f8e94dd937461a71d0442d` (tag `v4.5.0`) |
| Protocol implementation | `TLoungeProtocol_4_5` |
| Transport | WebSocket via libcurl (`CURLWS`) |
| Engine.IO wire protocol | v4 (`EIO=4`) |
| Socket.IO wire protocol | v5 |
| Reference packages | socket.io 4.6.2 (server), socket.io-client 4.5.0 |
| Authentication behavior | Password login and session-token restore (fast auth) via the Socket.IO `auth:start` / `auth:perform` / `auth:success` flow; see below |
| Connection URL | `<install-path>socket.io/?EIO=4&transport=websocket` |
| Test date | 2026-08-20 |
| Test environment | GNUstep on Linux, clang, libcurl 8.14.1 |

## Authentication behavior

After the Socket.IO connection and namespace connect complete, the server
emits `auth:start` (with a `serverHash`); the client answers `auth:perform`,
either with `{user, password}` on first login or with
`{user, token, lastMessage, openChannel, hasConfig}` for session restore; the
server then emits `auth:failed` on failure or, on success, `auth:success`
followed by `configuration`, `push:issubscribed`, `init` (which carries the
generated session token on first login), and `commands`. The token is
persisted in a secure credential store and used for fast auth on subsequent
connections.

## Known supported features

Implemented and covered by unit/parser-level tests:

- Connection to an installation at `/` or under a non-root URL path.
- Password authentication and session-token restore (fast auth) with
  `lastMessage`, `openChannel`, and `hasConfig`.
- Session token persistence in a secure credential store.
- Networks, channels, queries, lobby, and special views from `init`,
  `network`, and `join`.
- Receiving and sending messages, actions, and notices; sending commands via
  `input` (including join, part, nick, topic, mode, kick, ban, invite, whois,
  ctcp, msg, say, query).
- Join, part, quit, nick change, topic change, mode change, channel state
  (joined/parted), and mute state events.
- History: initial messages from `init`, older history loaded via `more`,
  deduplication by server message id.
- Unread and highlight counts, cleared by `open` and restored on reconnect.
- User lists via `names` / `users` with operator and voice state.
- Network options, status, name, and reorder events; channel reorder;
  `history:clear`.
- Automatic reconnection with exponential backoff (1s, 2s, 4s, 8s, 16s,
  capped at 30s) plus randomized jitter, followed by session restore and
  reconciliation of the local model.
- TLS with certificate and hostname validation (libcurl defaults).
- Message types modeled: message, action, notice, join, part, quit, nick,
  topic, mode, mode_channel, mode_user, kick, invite, away, back, error,
  ctcp, whois, raw, wallops.
- Context menus on channels/networks (sidebar) and users (user list) with
  the same items as the The Lounge v4.5 web client: join prompt, list
  channels/ignored/banned, disconnect/connect, edit topic, whois, ignore,
  query/direct messages, clear history (with confirmation), mute/unmute,
  leave/close/remove network (with confirmation), and operator actions
  (give/revoke owner/admin/operator/half-op/voice, kick) gated by the same
  prefix-rank rules as `generateUserContextMenu`. Not yet offered:
  "Edit this network…" (needs a network editor UI and the network editing
  protocol).

## Known unsupported features

Honest list of what is not implemented:

- HTTP long-polling fallback. The client connects with
  `transport=websocket` only.
- Binary events (`BINARY_EVENT` / `BINARY_ACK`). Only needed for The Lounge's
  upload feature, which is out of scope for version 1.
- Plugins and embedded media previews (`msg:preview`, `msg:special` are
  ignored).
- Search (`search:results` is ignored).
- Desktop notifications for highlights and private messages.
- Multi-account UI.
- Mentions history (`mentions:list`), sessions list (`sessions:list`),
  `change-password`, `sign-out`, `upload:auth`, `push:*`, and `changelog`
  events are ignored safely.
- Message types without a model mapping: `unhandled`, `login`, `logout`,
  `monospace_block`, `ctcp_request`, `chghost`, `topic_set_by`, `plugin`.
- Retry of IRC operations after reconnect. Commands are not acknowledged at
  the protocol level, so no command is replayed (deliberately, per SPEC).

## Known protocol differences

- Reconnect synchronization is merge-not-replace: incoming `init`/`network`
  state is reconciled against the existing local model (networks, channels,
  users, messages) and deduplicated by server id, rather than replacing it.
- The websocket-direct connect with `transport=websocket` skips the
  ping-probe/upgrade handshake described in the reference Engine.IO sequence.
  The client processes the `open` packet directly and proceeds to
  Socket.IO traffic in Engine.IO `message` packets.

## Test status

Unit and parser-level tests (Engine.IO, Socket.IO, protocol dispatch, model
updates, reconciliation) are all green (165 assertions across `t_model`,
`t_engineio`, `t_socketio`, `t_protocol`).

A live integration test was run on 2026-08-20 against a public The Lounge
instance at `https://lounge.assassinate-you.net/` (server-reported version
**4.5.2**) using the `thelounge-protocol-dump` diagnostic tool with a
password login. The full connection, authentication, and initialization
sequence succeeded end to end:

- Engine.IO `open` packet with `sid`/`pingInterval`/`pingTimeout`;
- Socket.IO `connect`;
- `auth:start` challenge, `auth:perform` reply, `auth:success`;
- `configuration`, `push:issubscribed`, then `init` with a 55 KB payload
  (multiple networks/channels/queries, messages, user list) parsed as valid
  JSON, and the `commands` list;
- large WebSocket frames (init > 16 KB, split across many libcurl reads)
  are reassembled correctly via the frame `offset`/`bytesleft` metadata;
- sensitive fields (`password`, `sid`) are redacted in tool output.

The client interoperates with The Lounge 4.5.2 (a later 4.5.x release than
the pinned 4.5.0 study target) for connection, auth, and initialization.
No messaging, history, or reconnection exchange over a live server has been
exercised yet; the reference pins The Lounge 4.5.0 (commit `dd2108fa`), and
no other major release has been tested.