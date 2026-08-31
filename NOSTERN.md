# NOSTERN - Protocol Specification

> NOSTERN is a NOSTR-based chat protocol implemented in this app **alongside**
> the existing The Lounge (`TLoungeProtocol_4_5`) protocol. It is not a wire
> format of its own; it is a thin mapping of the app's `TLoungeProtocol`
> contract onto the NOSTR relay protocol (NIP-01, NIP-28, NIP-42, and friends).
>
> Research note: no existing protocol named "NOSTERN" is published. This
> document therefore *defines* NOSTERN as "Nostr, adapted to the Lounge
> client's protocol interface". The wire protocol is vanilla NOSTR.
>
> Scope: this file is a specification for a future implementation. It is NOT
> committed (nostr-related, per project rule). When implemented it must NOT
> modify the existing The Lounge path; it adds a new, swappable protocol class.

## 1. Goals and non-goals

Goals:
- Let the app connect to a NOSTR relay (or relay set) and present channels,
  messages, and users through the existing UI unchanged.
- Reuse every model class (`TLServerState`, `TLNetwork`, `TLChannel`,
  `TLMessage`, `TLUser`) and the six `TLLounge*DidChangeNotification`s verbatim.
- Keep the existing `TLoungeSession` connection-state machine and reconnect
  logic untouched except for selecting the protocol class.
- **Offline catch-up is a core requirement, not optional history loading.** A
  user who goes offline must, on reconnect, see the messages they missed (as
  long as at least one connected relay still holds them). This is what makes a
  NOSTR backend feel like an IRC bouncer rather than a live-only chat client.

Non-goals (v1):
- No relay-enforced membership/moderation (that is NIP-29; see section 10).
- No encrypted DMs (NIP-17/44/59) in v1; only public NIP-28 channels and
  NIP-01 kind-1 notes.
- No new UI. The UI observes notifications only and never sees NOSTR ids.

## 2. Layering in this app

The transport chain is fixed and only the protocol object changes:

```
TLWebSocketTransport (libcurl CURLWS)
  -> TLEngineIOClient (EIO=4)        [NOT used by NOSTERN]
  -> TLSocketIOClient (Socket.IO v5) [NOT used by NOSTERN]
  -> TLSocketEventDispatcher         [REUSED: transport-agnostic]
  -> TLoungeProtocol_NOSTERN         [NEW: the swappable layer]
  -> model -> UI (notifications only)
```

NOSTERN does NOT use Engine.IO/Socket.IO. It talks raw WebSocket (NIP-01) to
relays. The `TLSocketEventDispatcher` is still reused as the in-process dispatch
mechanism: the NOSTERN transport delivers parsed relay messages to
`[self.dispatcher dispatchEvent:verb arguments:array]`, and `registerEventHandlers`
subscribes handlers exactly as `TLoungeProtocol_4_5` does. The session already
routes all incoming socket data through this dispatcher, so reusing it keeps the
session code unchanged.

## 3. Transport

- **WebSocket** to each relay. `ws://` or `wss://`, no fixed path.
- One WebSocket per relay; all subscriptions multiplexed over it.
- Connection is established by a NOSTERN transport (a `TLWebSocketTransport`
  variant that speaks NOSTR frames directly, bypassing Engine.IO/Socket.IO),
  yielding a `socketClient` object that supports `emitEvent:withArguments:` and
  a `TLSocketIOClientDelegate`-shaped callback. The base `TLoungeProtocol`
  already calls `self.socketClient emitEvent:withArguments:`, so NOSTERN only
  needs a Socket.IO-shaped emitter that, instead of wrapping in `4<payload>`,
  sends the bare NOSTR JSON array.
- NIP-11 relay info document (optional): HTTP GET with
  `Accept: application/nostr+json` for display/metadata.

## 4. Wire format

Every message is a **JSON array** (per NIP-01). First element is the verb; the
rest are payloads.

Client -> Relay:

| Verb   | Shape                                              | Purpose            |
|--------|----------------------------------------------------|--------------------|
| `EVENT`| `["EVENT", <event-json>]`                          | Publish an event   |
| `REQ`  | `["REQ", <sub_id>, <filter>, ...]`                 | Subscribe          |
| `CLOSE`| `["CLOSE", <sub_id>]`                              | End subscription   |
| `AUTH`| `["AUTH", <kind-22242-event-json>]`                | Authenticate (NIP-42) |
| `COUNT`| `["COUNT", <sub_id>, <filter>, ...]`               | Count (NIP-45, opt)|

Relay -> Client:

| Verb     | Shape                                            | Purpose                  |
|----------|--------------------------------------------------|--------------------------|
| `EVENT`  | `["EVENT", <sub_id>, <event-json>]`              | Matching event           |
| `EOSE`   | `["EOSE", <sub_id>]`                             | End of stored events     |
| `OK`     | `["OK", <event_id>, <bool>, <message>]`          | Publish acceptance       |
| `CLOSED` | `["CLOSED", <sub_id>, <message>]`                | Subscription refused     |
| `NOTICE` | `["NOTICE", <string>]`                           | Human-readable info      |
| `AUTH`   | `["AUTH", <challenge-string>]`                   | Relay demands auth       |
| `COUNT`  | `["COUNT", <sub_id>, <count-json>]`              | Count result             |

`<sub_id>` is an arbitrary non-empty string, max 64 chars, scoped per connection.

### Event object (NIP-01)

```json
{
  "id":       "<64 hex sha256 of serialized [0,pubkey,created_at,kind,tags,content]>",
  "pubkey":   "<64 hex secp256k1 pubkey>",
  "created_at": 1700000000,
  "kind":     1,
  "tags":     [["e","<id>","","root"], ["p","<pubkey>"]],
  "content":  "hello world",
  "sig":      "<128 hex BIP-340 schnorr sig>"
}
```

The client MUST verify `id` and `sig` before trusting any event. `created_at` is
Unix seconds.

### Filters (NIP-01)

```json
{ "ids":[...], "authors":[...], "kinds":[...], "#e":[...], "#p":[...],
  "#h":[...], "since":<int>, "until":<int>, "limit":<int>, "search":"..." }
```

## 5. Chat model (NIP-28 public channels)

NOSTERN maps the app's IRC-style channels onto **NIP-28 public chat**:

| NOSTR kind | Meaning             | Key tags / content                              |
|------------|---------------------|------------------------------------------------|
| 40         | Channel create      | `content` = JSON `{name,about,picture}`; event **id = channel id** |
| 41         | Channel metadata    | `e` -> kind-40 id (`root`); `content` = JSON    |
| 42         | Channel message     | `e` -> channel id (`root`); `p` -> mentions; `content` = text |
| 43         | Hide message        | `e` -> kind-42 id (per-viewer)                  |
| 44         | Mute user           | `p` -> pubkey (per-viewer)                      |

To read a channel: `REQ` with `{"kinds":[42], "#e":[channelId], "limit":100}`.
Presence/typing/join-part are not in NIP-28 core; NOSTERN v1 treats channels as
always-joined public rooms (no IRC join/part semantics). See section 10 for
extension points.

A "network" in the app has no NOSTR equivalent. NOSTERN models the relay set as
**one synthetic `TLNetwork`** (or one per relay) whose `uuid` is a stable string
(e.g. the relay URL or a hash of the configured relay set). Channels are NIP-28
kind-40 channels discovered via subscription.

## 6. Authentication (NIP-42)

- The relay MAY send `["AUTH", "<challenge>"]`.
- The client responds `["AUTH", <kind-22242 event>]` with `content:""` and tags
  `[["relay","wss://relay"], ["challenge","<challenge>"]]`.
- The relay replies `["OK", <auth-event-id>, true, ""]`.

Identity is a secp256k1 keypair, not a username/password. NOSTERN still drives
the app's `TLConnectionState` machine through the `TLoungeProtocolDelegate`:
on relay `AUTH` challenge -> `didReceiveAuthStart:` (-> `Authenticating`), after
sending a valid kind-22242 -> `setAuthenticated:YES` + `protocolDidAuthenticate:`
(-> `Initializing`), and once the initial subscription set returns `EOSE` and
the synthetic `init` is posted -> `protocolDidBecomeReady:` (-> `Ready`).

Credential persistence: `TLoungeSession` already stores a token string; NOSTERN
reuses that path to persist the NOSTR auth token / pubkey so reconnects skip
re-auth when the relay accepts the cached credential.

## 7. The `NSInteger` identifier problem (critical)

The app's model and session **only** address channels and messages by `NSInteger
identifier` (`TLServerState channelWithIdentifier:`, `TLChannel
messageWithIdentifier:`, etc.). NOSTR uses 32-byte hex/bech32 ids and pubkeys.
Therefore NOSTERN MUST:

1. Synthesize **stable** `NSInteger` ids for every channel and message. A
   deterministic hash (e.g. FNV/SipHash) of the NOSTR event id/pubkey, masked to
   a positive `NSInteger` range, is sufficient and stable across reconnects.
2. Store the NOSTR-native id in `metadata` on the `TLChannel`/`TLMessage` and
   keep a reverse map (pubkey/event-id -> `NSInteger`) owned by the protocol
   instance, so outgoing operations (`sendMessage`, `loadMoreHistory`,
   `search`) can recover the real NOSTR target from the `NSInteger` the UI passes
   back.
3. For search results, reuse the existing `TLLoungeSearchResultIdBase`
   (`-100000000`) negative-id space so synthetic results never collide with real
   ids.

This is invisible to the UI: the UI only ever passes the `NSInteger` it was
given. The mapping lives entirely inside `TLoungeProtocol_NOSTERN`.

## 8. Command/event catalog mapping

### Outgoing (app method -> NOSTR operation)

| `TLoungeProtocol` method                          | NOSTERN behavior                                                        |
|---------------------------------------------------|-------------------------------------------------------------------------|
| `sendMessage:toChannelId:`                        | Publish kind-42 event with `e` -> channel NOSTR id (`root`), `content` = text |
| `sendCommand:toChannelId:`                        | Same as `sendMessage:` (no IRC `/commands` in v1)                       |
| `openChannelId:`                                  | Ensure a `REQ` subscription for the channel's kind-42 stream (idempotent)|
| `requestNamesForChannelId:`                       | No NOSTR `names`; synthesize user list from message `pubkey`s seen      |
| `loadMoreHistoryForChannelId:lastId:query:`       | New `REQ`/`COUNT` with `until` = oldest seen `created_at`, `limit`, optional `search` (NIP-50) |
| `searchMessagesForChannelId:term:offset:`         | `REQ` with `search` filter (NIP-50) or relay-specific query; page by `offset` |
| `clearHistoryForChannelId:`                       | Local only: empty `channel.messages` and reset unread; no NOSTR event   |
| `setMuted:forChannelId:`                          | Local only: set `channel.muted`; optionally publish NIP-51 mute list    |

### Incoming (relay message -> app notification)

| Relay verb / NOSTR kind                | App action                                                                 |
|----------------------------------------|----------------------------------------------------------------------------|
| `EVENT` kind-40                        | Create/update `TLChannel`; post `TLLoungeNetworkListDidChangeNotification` |
| `EVENT` kind-41                        | Update `channel.topic`/metadata; post `TLLoungeChannelDidChangeNotification`|
| `EVENT` kind-42                        | Build `TLMessage`, `addMessage:`, post `TLLoungeMessagesDidChangeNotification` |
| `EVENT` kind-1 (DM/notes, if enabled)  | Map to `TLMessageTypeMessage`; `self` set when local key authored          |
| `EOSE` on bootstrap subs              | Trigger synthetic `init` -> `setReady:` + `protocolDidBecomeReady:`         |
| `OK` / `CLOSED` / `NOTICE` / `AUTH`   | Map to connection-state transitions / errors / NIP-42 challenge            |

All notifications use the **exact** `userInfo` keys from `TLoungeProtocol.h`:
- `TLLoungeNetworkListDidChangeNotification`: no userInfo
- `TLLoungeChannelDidChangeNotification`: `@{@"channelId": @(chanId)}`
- `TLLoungeMessagesDidChangeNotification`: `@{@"channelId":..., @"message":message}` or `@{@"channelId":...}` for clear
- `TLLoungeUserListDidChangeNotification`: `@{@"channelId":...}`
- `TLLoungeHistoryDidChangeNotification`: `@{@"channelId":...}`
- `TLLoungeSearchResultsDidChangeNotification`: `@{@"channelId":..., @"messages":..., @"count":...}`

### Model field mapping

- `TLNetwork.uuid` = stable relay-set id; `name` = relay host; `nick` = NOSTR
  display name/pubkey; `connected`/`secure` = relay WebSocket state.
- `TLChannel.identifier` = synthesized `NSInteger` (section 7); `name` = NIP-28
  channel name; `type` = `TLChannelTypeChannel`; `lobby` = none in v1 (no server
  buffer), so `badgeTotal` reduces to the channel sum.
- `TLMessage.identifier` = synthesized `NSInteger`; `channelId` = synthesized
  channel id; `sender` = `TLUser` with `nick` = NOSTR display name; `timestamp` =
  `created_at` seconds (already normalized by `TLMessage`); `type` =
  `TLMessageTypeMessage`; `self` = authored by local key.
- `TLUser.nick` = NOSTR display name; `username`/`hostname` repurposed to pubkey.

## 9. Offline catch-up (core requirement)

A NOSTR relay **stores and forwards** events; Nosterm's relay config exposes a
`RELAY_RETENTION_DAYS` (0 = keep indefinitely). There is also a local client
cache (browser IndexedDB in Nosterm; for the native client, a local on-disk
store - see below). The native client must treat relay-side history as the
authoritative source for recovering missed messages and must recover it on
every (re)connect, not only on first join.

### Per-channel/per-relay cursor

For every channel/relay pair the client keeps a resumable cursor:

- `lastSeenEventID` - the NOSTR event id of the most recent message the client
  has persisted for that channel.
- `lastSeenEventTimestamp` - the `created_at` (epoch seconds) of that event.

Both are persisted locally (a small plist/store keyed by `(relayURL, channelId)`),
independent of the relay, so reconnect never loses the cursor.

### Reconnect subscription

On (re)connect, instead of (or in addition to) an open-ended subscription, the
client issues a filter bounded by the cursor:

```
{ "kinds": [...], "#h": [...], "since": <lastSeenEventTimestamp + 1> }
```

This pulls exactly the events the client missed while offline. Live events
(those with `created_at` newer than the cursor) continue to flow through the
same handlers; the only difference is the lower bound. The cursor is advanced
as each message is persisted, so a mid-stream reconnect resumes correctly
without re-fetching.

### Multi-relay deduplication

When more than one relay is connected (Nosterm federation), the same event can
arrive through several relay paths. Incoming events MUST be deduplicated by
NOSTR `id` before they become `TLMessage`s - a single `(id)` map per channel
suffices. This is the same concern as the existing The Lounge `init`
reconciliation (section 7 / `handleInitEvent`): merge, never replace.

### Local cache vs relay history

- **Relay history** is the source of truth for catch-up; the client always
  asks the relay for `since: <cursor>`.
- **Local cache** (the persisted `TLMessage` store) lets already-seen messages
  survive a relaunch/offline period without a network round-trip and is what
  the UI renders immediately on open. It is a cache, not the authority: on
  reconnect the relay is still queried and the local store is reconciled
  (merged, deduped by `id`) with whatever the relay returns.

This is explicitly a v1 requirement. It is not "load older history on scroll"
(the `until`/`limit` paging in section 4.1); it is the automatic
recovery of missed messages on reconnect.

## 10. Extension points (non-v1)

- **NIP-29 groups**: relay-enforced membership/moderation; model as a
  `TLNetwork` whose channels carry an `h` tag. Adds join/part semantics.
- **NIP-17/44/59 encrypted DMs**: map to `TLChannelTypeQuery` with gift-wrapped
  `TLMessage`s; decrypt with the local NOSTR key.
- **NIP-51 mute lists**: persist `setMuted:` as a kind-10000 list.
- **Presence/typing**: app-level kinds (cf. Nymchat 24420/24421); not in core.

## 11. Integration plan (when implementing)

Files to add (NO modifications to existing protocol code):
- `TLNative/Protocol/TLoungeProtocol_NOSTERN.h/.m` - subclass of `TLoungeProtocol`,
  overriding `registerEventHandlers`, `performAuthentication`, and all
  `send*/open*/request*/loadMore*/search*/clear*/setMuted:` methods; owns the
  `NSInteger`<->NOSTR id maps.
- `TLNative/Transport/TLNostrWebSocketTransport.h/.m` - raw WebSocket relay
  client exposing the `TLSocketIOClient`-shaped emitter/delegate used by the base
  class.
- A way to select the protocol: extend `TLoungeSession` (or add a session flag)
  so `init` instantiates `TLoungeProtocol_NOSTERN` instead of
  `TLoungeProtocol_4_5`. The rest of the session (reconnect, credential
  persistence, state machine) is reused unchanged.

Confirm with the UI team that the six notifications and `userInfo` keys above are
sufficient; they are, because they are already the full contract used by
`TLMainWindowController`.

## 12. Open questions

1. Should v1 support multiple relays (one `TLNetwork` each) or collapse to one?
2. Is the NOSTR keypair provided by the user, or generated and stored locally?
3. Do we need NIP-50 full-text search, or is `until`/`limit` history paging enough?
4. How are channels discovered - a fixed configured list, or by scanning kind-40
   events from followed pubkeys?

## 13. Sources

- NIP-01 basic protocol and event structure
- NIP-11 relay information document
- NIP-28 public chat (kinds 40-44)
- NIP-29 relay-based groups
- NIP-42 authentication (kind 22242)
- NIP-45 COUNT (optional)
- NIP-50 search (optional)
- NIP-51 lists (mute, optional)
- NIP-17/44/59 encrypted direct messages (future)
