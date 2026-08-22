# AGENTS.md

TheLounge.app: a native GNUstep/AppKit (Objective-C) desktop client for The Lounge IRC bouncer. Speaks the The Lounge client protocol (Socket.IO v5 / Engine.IO v4 over WebSocket via libcurl). No embedded browser/JS runtime. Not a git repository.

## Build

GNUstep is installed at `/System`, not `/usr/GNUstep`. Source the env first:

```sh
source /System/Library/Makefiles/GNUstep.sh
```

- App: `cd TLNative && make` -> `TheLounge.app` (application.make, install domain SYSTEM)
- Tests: `cd TLNative/Tests && make`, then run `./obj/t_model`, `./obj/t_engineio`, `./obj/t_socketio`, `./obj/t_protocol` directly (`gmake check` is NOT wired)
- Tool: `cd TLNative/Tools && make` -> `./obj/thelounge-protocol-dump`
- `make clean` before rebuilding when changing sources; zero warnings is a hard requirement (fix every warning, never suppress beyond the one flag below)

Links `-lcurl` (libcurl 8.14.1 with `ws`/`wss`). Compiler is clang.

## Non-ARC rules (differ from default ObjC, easy to get wrong)

- Manual retain/release, `[super dealloc]`. No ARC anywhere.
- `__weak` is a compile error. Blocks that capture `self` must use `__block` (MRC `__block` does not retain, so no cycle). Delegate properties are `assign`.
- No GCD/dispatch at all; use NSLock/`performSelectorOnMainThread`.
- Model properties `newNick`, `newIdent`, `newHost`, `rawText` intentionally mirror wire field names and trip clang's Cocoa ownership heuristic - the `-Wno-objc-property-matches-cocoa-ownership-rule` flag in all three GNUmakefiles must stay.
- All three GNUmakefiles pin `GNUSTEP_INSTALLATION_DOMAIN = SYSTEM`. Never install to LOCAL; verify `/Local/Applications` etc. has no leftovers after `make install`.

## Wire layering (subtle, get this right)

Chain: `TLWebSocketTransport` (libcurl CURLWS, connect-only + select loop) -> `TLEngineIOClient` (EIO=4) -> `TLSocketIOClient` (Socket.IO v5) -> `TLSocketEventDispatcher` -> `TLoungeProtocol_4_5` -> model. The UI only observes notifications (`TLLounge*DidChangeNotification`) and never touches raw packets.

- On the wire messages look like `4<payload>` (Engine.IO `4` = message). The Engine.IO client strips that prefix, so `TLSocketIOParser` receives the bare payload e.g. `2["event",...]`. When parsing Socket.IO packets, do NOT feed the parser `42...` strings; tests use `2[...]`.
- Endpoint: `<install-path>socket.io/?EIO=4&transport=websocket`; scheme http->ws, https->wss; path must end with `/`.
- Auth: server `auth:start(hash)` -> client `auth:perform` `{user,password}` or `{user,token,...}` -> `auth:success` -> `configuration` -> `push:issubscribed` -> `init{active,networks}`.
- Server `id` is authoritative for messages. Reconnect `init` only returns messages with `id > lastMessage` (max 100), so on reconnect the handler MUST merge into existing state, not replace it (`handleInitEvent` reconciliation).
- Protocol is pinned to The Lounge 4.5.0 (commit `dd2108fa8096949473f8e94dd937461a71d0442d`).

## Verification

- Unit tests are parser/model-level (165 assertions, all green). Live integration confirmed against `https://lounge.assassinate-you.net/` (The Lounge 4.5.2): connect, Engine.IO open, Socket.IO connect, `auth:start`/`auth:perform`/`auth:success`, `configuration`, `init` (55 KB payload), `commands`. Test via `thelounge-protocol-dump <url> <user> --password <pw>` (output auto-redacted).
- Large WebSocket frames are split across many `curl_ws_recv` calls WITHOUT `CURLWS_CONT`; reassemble using `curl_ws_frame.offset`/`bytesleft` (frame complete when `bytesleft==0`). See `receiveLoop` in TLWebSocketTransport.m.
- `SPEC.md` is the authoritative spec (see "# 48. Compatibility documentation" before claiming any compatibility). `PROTOCOL.md` is the pinned wire reference; `ARCHITECTURE.md` has the transport/threading/security decisions; `COMPATIBILITY.md` tracks what is actually implemented.

## Style

- New files: BSD-2-Clause header `Copyright (c) 2026 Simon Peter` (project has no GPL).
- No em-dashes (plain `-`), no "WiFi"/"Wi-Fi" (use "WLAN").
- Comments only explain WHY, never WHAT.