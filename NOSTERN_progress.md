# NOSTERN.md - Implementation Progress

Goal: produce `NOSTERN.md`, a protocol spec for NOSTERN (a NOSTR-based
protocol) to be implemented in this app alongside the existing TheLounge
protocol. This file tracks the research/authoring work. These files are NOT
to be git-committed (nostr-related per project rule).

## Tasks

- [ ] Research what NOSTERN is (web): transport, event model, relay protocol,
      how it differs from vanilla NOSTR.
- [ ] Analyze the existing `TLoungeProtocol` interface to define what a second
      protocol implementation must conform to (events in/out, model mapping).
- [ ] Draft `NOSTERN.md`: overview, wire format, event/command catalog,
      authentication, mapping to TLChannel/TLMessage/TLNetwork, and an
      integration plan against `TLoungeProtocol.h`.
- [ ] Review pass for accuracy and consistency with the codebase conventions.

## Log

| When | What |
|------|------|
| start | Dispatched research + code-analysis subagents. |
| research done | NOSTERN is not a published protocol; spec defines it as a NOSTR-based (NIP-01/28/42) chat protocol mapped onto the app's `TLoungeProtocol` contract. |
| code analysis done | Mapped the full `TLoungeProtocol` notification/userInfo contract, `TLoungeSession` delegation, and model classes a NOSTERN subclass must populate; identified the `NSInteger` id-synthesis requirement as the key risk. |
| draft done | Wrote `NOSTERN.md` (12 sections): transport, wire format, NIP-28 chat model, NIP-42 auth, id-synthesis, command/event catalog, model mapping, extension points, integration plan, open questions. |
| implemented | Wrote the protocol. Files added (NOT committed, nostr rule): |
| | - `Protocol/TLNostrCrypto.{h,m}` - BIP-340 Schnorr signing/verify + event id (OpenSSL/secp256k1). |
| | - `Protocol/TLNostrSocketClient.{h,m}` - raw NOSTR WebSocket over `TLWebSocketTransport`. |
| | - `Protocol/TLoungeProtocol_NOSTERN.{h,m}` - protocol subclass: handlers, id synthesis, NIP-42 auth, commands. |
| | - `Protocol/TLoungeProtocol.h/.m` - added `transportDidConnect` hook (no-op base). |
| | - `Protocol/TLoungeSession.m` - selects NOSTERN for `ws`/`wss` URLs; owns client/protocol. |
| | - `GNUmakefile` (app) - links `-lcrypto`; (tests) adds `t_nostr_crypto`. |
| | - `Tests/t_nostr_crypto.m` - 10 assertions incl. BIP-340 vector (pubkey of secret 3) + sign/verify. |
| build | App builds with zero warnings; `t_nostr_crypto` (10/10 pass), `t_protocol`, `t_badge` pass. |
| ui | Added `UI/TLRelayConnectController.{h,m}` (Relay URL / Display name / Private key dialog) and a "Connect to NOSTR Relay…" item in the Chat menu. `TLoungeSession` is now a container: the primary connection (The Lounge OR a `wss://` NOSTERN login) plus any number of added NOSTERN relays, all sharing one `TLServerState`, so relay networks appear alongside IRC networks in the same window. Per-relay id namespace (slot in a shared high id range) keeps channel/message ids routable back to the owning relay. |
| demo | `chat.nosterm.com` is a real, separate Nostr client (Robert Goodall) using **NIP-29** managed groups, not NIP-28. Its default relay is `wss://relay.nosterm.com` (the "Demo Relay", plus a Tor `.onion`). Added `TLLoungeNosternDefaultRelayURL` and: (a) the relay dialog is pre-filled with it; (b) a one-click **Chat > Connect to Nosterm Demo Relay** menu item. Per the user's decision, NOSTERN now speaks BOTH NIP-28 and NIP-29: `TLoungeProtocol_NOSTERN` subscribes to kind 40/42 (NIP-28) and kind 39000/39002 + 9 (NIP-29) simultaneously, so it auto-adapts to whatever a relay serves. NIP-29 groups become channels, kind 9 `h`-tagged messages become channel messages, and sending publishes the right kind per channel. |
| join+roster | Added NIP-29 group create/join and membership rosters. `TLoungeProtocol` gained `joinChannelNamed:lobbyId:` (base → `/join`) and `managedNetwork` (base → nil). `TLoungeProtocol_NOSTERN` overrides both: `joinChannelNamed:` normalizes the name to a group id, creates the channel locally, publishes kind `39000` (d=groupId, content {name}), and subscribes to the group's kind `9` messages; `managedNetwork` returns its relay network. `handleGroupMembers:` (kind `39002`) populates `TLChannel.users` (TLUser per `p` tag) and posts `TLLoungeUserListDidChangeNotification`. `TLoungeSession` routes joins via `protocolForNetwork:` (matches the owning relay) and `joinChannelNamed:forLobbyId:`. `TLMainWindowController`'s Join prompt now calls the session join method and auto-selects the resulting channel. |
| status | Implementation complete and building clean (app + `t_nostr_crypto` 10/10, `t_protocol`, `t_badge` pass). NOT git-committed (nostr-related per project rule). Open known risk: Nosterm's exact `h`-tag group-address format (`wss://relay.nosterm.com:general` assumed) must be confirmed against a live capture; if messages don't appear, the `h`-tag parsing in `handleGroupMessage` is the place to adjust. |
| live test | Added `Tests/t_nostern_live.m`, gated behind `TL_NOSTERN_TEST_KEY` (64-hex seckey; SKIPs cleanly with exit 0 if unset) so the real relay is only contacted when a secret is supplied. No secret is committed or logged; only the derived pubkey and relay host are printed. Optional `TL_NOSTERN_TEST_RELAY` (default `wss://chat.nosterm.com/relay`) and `TL_NOSTERN_TEST_DEBUG`. Asserts: live session reaches ready, relay network present, NIP-29 group created + visible, sent message echoed back (kind 9 round-trip), creator present in kind 39002 roster. All 5 pass against the real `chat.nosterm.com` relay, stable across repeated runs. |
| relay facts (chat.nosterm.com) | Software `nostermd 0.1.0` (NIPs 1,11,29,42). URL is `wss://chat.nosterm.com/relay` (NOT `wss://relay.nosterm.com`, which does not resolve). MOTD arrives as `NOTICE` arrays. NIP-29: kind 39000 `d` is the **bare** group id (`general`, `public`, `welcome`, `lobby`); kind 39002 `d` is the **full** group address `wss://chat.nosterm.com/relay:<id>`. Returned kind 9 events are tagged with the **bare** `h`; posting and the kind 9021 join must use the **full** address `h` or the relay rejects with `blocked: unknown group; send a join request (kind 9021) first`. nostermd only accepts posts to **open** groups, so group creation now sends an `open` tag in kind 39000. The 9021 join must be observed before kind 9 is accepted (test resends once after 2s if unechoed). |
| fixes found via live test | (1) `joinChannelNamed:` computed the channel int id before its `if` guard, so the guard never fired and the channel was never created; moved int-id inside the guard. (2) `handleGroupMembers` lookup missed because kind 39002 `d` is the full address while `handleGroupMetadata` (39000) `d` is bare; now tries full then bare. (3) subscriptions match `#h` on both full address and bare id. (4) NIP-29 group create now includes the `open` tag. (5) removed temporary debug logging. |
| spec: offline catch-up | Per user guidance, `NOSTERN.md` now lists offline catch-up as a **core v1 requirement** (not optional history loading). New section 9 defines: per-channel/per-relay cursor (`lastSeenEventID` + `lastSeenEventTimestamp`) persisted locally; reconnect subscription bounded by `since: <cursor>`; multi-relay deduplication by NOSTR `id`; and the two-layer model (relay history = authority for catch-up, local on-disk cache = immediate render + reconcile). Sections 9-13 renumbered accordingly; cross-references updated. NOT yet implemented in code. |
| impl: offline catch-up | Implemented in `TLoungeProtocol_NOSTERN.m`. Added per-channel cursor (`_channelCursors`, `{id,ts}`) persisted to a per-relay plist in `~/Library/Application Support/TheLounge/nostr-cursor-<host>.plist`; loaded in `transportDidConnect` and rewritten on each new most-recent message (`recordEventSeen:timestamp:forChannel:`). On (re)connect, `resubscribeAllChannels` re-opens a per-channel `ch-<id>` REQ bounded by `since: cursor+1` (kind 42 `#e` for NIP-28, kind 9 `#h` for NIP-29); channel creation / `joinChannelNamed:` / `openChannelId:` open the same bounded subscription. Relay replay + persisted cursor also catches up after a relaunch. Added `_seenEventIds` dedup set checked at the top of `handleChannelMessage:` / `handleGroupMessage:` so a message delivered by both a global and a per-channel subscription is added exactly once. New `Tests/t_nostern_catchup.m` (gated by `TL_NOSTERN_TEST_KEY`, like the live test) proves it: identity B posts while A is offline, A reconnects and replays B's message, with no duplicates. Builds clean (zero warnings). The local on-disk *message* cache (immediate render before reconnect) is still deferred; relay replay already covers "see missed messages". |
