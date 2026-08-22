# Architecture

## Layers

```text
GNUstep UI (AppKit)
      |
Application Model (TLServerState, TLClientState, ...)
      |
The Lounge Protocol Adapter (TLoungeProtocol_4_5)
      |
Socket.IO (TLSocketIOClient)
      |
Engine.IO (TLEngineIOClient)
      |
WebSocket (TLWebSocketTransport, libcurl)
      |
The Lounge server
      |
IRC networks
```

## Transport dependency decision (Phase 1)

Evaluated options for WebSocket + Socket.IO on GNUstep/Linux:

1. **GNUstep WebSocket libraries** - none shipped in the system GNUstep
   installation.
2. **C/C++ WebSocket libraries** - `libwebsockets` and `websocketpp` are not
   installed. **libcurl (8.14.1) is installed and ships a stable WebSocket
   API** (`curl_ws_send` / `curl_ws_recv`, `ws`/`wss` protocols). libcurl
   also provides TLS with certificate and hostname validation, redirect
   handling, HTTP proxies, and is already used across the system.
3. **Socket.IO C++ client** - not installed; adds a C++ dependency and an
   unfamiliar API. It is tied to specific socket.io versions and hard to keep
   version-pinned against The Lounge's socket.io 4.6.2.
4. **License** - libcurl is MIT-style (curl license); no GPL coupling.

Decision:

* **TLWebSocketTransport** wraps libcurl's WebSocket API (async reads via the
  curl multi interface on a dedicated network thread). All WebSocket framing,
  TLS, and connection state live behind this class.
* **TLEngineIOClient** and **TLSocketIOClient** are implemented in-project
  because the wire formats are small, stable, version-pinned
  (Engine.IO v4, Socket.IO v5) and must not depend on a third-party API.
* JSON is handled with GNUstep's `NSJSONSerialization`.

This satisfies SPEC section 8: existing implementations were evaluated, the
reliable one (libcurl) is wrapped behind project interfaces, and the rest of
the application depends only on the project's transport interfaces.

## Threading

* Main thread: GNUstep UI, `TLClientState`, model notifications.
* Network thread: libcurl multi loop feeding `TLWebSocketTransport`.
* Model mutations happen on the main thread. The transport/protocol layer
  delivers raw Socket.IO events to the protocol adapter; the adapter schedules
  model updates on the main thread (or the UI is only updated from the main
  thread through the notification path).
* All socket writes are serialized on the network thread.

## Versioning of the protocol adapter

`TLoungeProtocol` is the base class; `TLoungeProtocol_4_5` implements the
4.5.x protocol described in PROTOCOL.md. The UI and model layers
contain no The Lounge version-specific logic.

## Security

* TLS certificate and hostname validation always on (libcurl defaults).
* No JavaScript execution anywhere.
* Passwords and tokens kept in a secure credential store, never in property
  lists or logs.
* Server-provided content treated as untrusted.