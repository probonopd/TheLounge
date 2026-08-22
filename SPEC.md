# GNUstep Native Client for The Lounge

**Status:** Development specification
**Target:** GNUstep/Linux desktop
**Primary language:** Objective-C
**UI:** GNUstep GUI/AppKit-compatible APIs
**Protocol target:** The Lounge client/server protocol used by its web client
**Initial compatibility target:** The Lounge 4.5.x, with compatibility testing against later releases where practical

---

## 1. Project objective

Develop a native GNUstep desktop client for an existing The Lounge installation.

The application shall allow a user to:

* connect to a The Lounge server;
* authenticate;
* view networks, channels, queries, and other supported conversations;
* receive and send IRC messages through The Lounge;
* view users and channel state;
* view server-provided history;
* maintain unread/highlight state;
* automatically reconnect after connection loss;
* operate entirely through native GNUstep UI components.

The application must **not embed a browser, WebKit, WebView, or JavaScript runtime**.

The application shall communicate with The Lounge using the same client/server protocol used by the current The Lounge web client.

The Lounge's plugin/public API must **not** be treated as the native-client protocol.

---

# 2. Architectural principle

The system shall be divided into four distinct layers:

```text
┌─────────────────────────────────────────────┐
│                 GNUstep UI                  │
├─────────────────────────────────────────────┤
│             Application Model               │
├─────────────────────────────────────────────┤
│        The Lounge Protocol Adapter          │
├─────────────────────────────────────────────┤
│ Socket.IO / Engine.IO / WebSocket Transport │
└─────────────────────────────────────────────┘
                       │
                       ▼
               The Lounge Server
                       │
                       ▼
                  IRC networks
```

The UI must never manipulate raw Socket.IO or Engine.IO packets.

The transport layer must never contain GNUstep UI logic.

The The Lounge protocol adapter must be isolated from the application model and UI.

---

# 3. Important protocol requirement

The Lounge's public/plugin API is **not** the specification for this client.

The authoritative application-level protocol shall be determined from the source of the The Lounge web client corresponding to a pinned The Lounge release.

Before implementing application-level events, the developer shall produce:

```text
PROTOCOL.md
```

This document shall record:

* The Lounge version;
* source commit;
* Socket.IO version;
* Engine.IO version;
* connection path;
* authentication mechanism;
* session/cookie/token behavior;
* all required client-to-server events;
* all required server-to-client events;
* payload structures;
* initialization sequence;
* state synchronization behavior;
* history behavior;
* reconnection behavior;
* message/event semantics;
* protocol differences between tested The Lounge releases.

No undocumented event name or payload shall be invented when it can be determined from the web client source or observed protocol traffic.

---

# 4. Protocol reconnaissance phase

Protocol reconnaissance is a required development phase.

Before building the full UI, the developer shall inspect the pinned The Lounge source and, where necessary, capture sanitized traffic from an ordinary web-client session against a disposable test server.

The investigation shall cover at least:

```text
Connection
Authentication
Session restoration
Initial state
Networks
Channels
Queries
Users
Messages
History
Unread state
Highlights
Topic changes
Nick changes
Join/part/quit events
IRC commands
Disconnect
Reconnect
Errors
```

The resulting protocol specification shall include a table similar to:

| Direction       | Event            | Payload            | Purpose         | Required |
| --------------- | ---------------- | ------------------ | --------------- | -------- |
| Client → Server | `<actual event>` | `<actual payload>` | Authentication  | Yes      |
| Server → Client | `<actual event>` | `<actual payload>` | Initial state   | Yes      |
| Client → Server | `<actual event>` | `<actual payload>` | Send message    | Yes      |
| Server → Client | `<actual event>` | `<actual payload>` | Receive message | Yes      |

The actual event names and payloads must come from the selected The Lounge version.

---

# 5. Versioning

Protocol compatibility shall be associated with a specific The Lounge version/source revision.

The initial implementation shall target:

```text
The Lounge 4.5.x
```

The exact tested release and source commit shall be recorded in `COMPATIBILITY.md`.

If later releases change the protocol, protocol-specific behavior shall be isolated rather than scattered throughout the application.

Preferred architecture:

```text
TLoungeProtocol
├── TLoungeProtocol_4_5
├── TLoungeProtocol_4_6
└── ...
```

A protocol implementation may also support a range of compatible releases when their behavior is demonstrably identical.

The UI and core model must not contain The Lounge version-specific logic.

---

# 6. Transport architecture

The transport subsystem shall be divided into:

```text
TLWebSocketTransport
TLEngineIOClient
TLSocketIOClient
TLoungeProtocol
TLoungeSession
```

## TLWebSocketTransport

Responsible only for:

* WebSocket connection;
* TLS;
* WebSocket frames;
* connection state;
* binary/text frame handling;
* clean shutdown.

It must not know about The Lounge events.

## TLEngineIOClient

Responsible for:

* Engine.IO handshake;
* packet framing;
* packet parsing;
* session ID;
* heartbeat;
* ping/pong;
* transport lifecycle.

## TLSocketIOClient

Responsible for:

* Socket.IO packet parsing;
* Socket.IO packet serialization;
* event emission;
* acknowledgements;
* errors;
* namespaces if required;
* binary events if required by the tested protocol.

## TLoungeProtocol

Responsible for:

* The Lounge authentication;
* initialization;
* application events;
* state updates;
* IRC operations;
* history;
* server notifications.

## TLoungeSession

Responsible for:

* user-visible connection lifecycle;
* authentication state;
* reconnect logic;
* model synchronization;
* session restoration.

---

# 7. Socket.IO and Engine.IO

The initial transport shall support the protocol versions actually used by the target The Lounge release.

Where applicable, this includes:

```text
Engine.IO v4
Socket.IO v4
```

The implementation must not assume that the package version and wire-protocol version are interchangeable concepts.

The exact versions shall be recorded in `COMPATIBILITY.md`.

The implementation should prefer WebSocket transport.

HTTP long-polling fallback is optional for the first release unless compatibility testing demonstrates that it is required.

---

# 8. Transport dependency decision

Do not automatically implement Engine.IO and Socket.IO from scratch.

Before doing so, evaluate:

1. existing GNUstep-compatible WebSocket libraries;
2. existing C/C++ WebSocket libraries;
3. the Socket.IO C++ client;
4. compatibility of those libraries with the target The Lounge release;
5. Objective-C/GNUstep integration complexity;
6. licensing implications.

If an existing implementation provides reliable compatibility, wrap it behind the project's transport interfaces.

The remainder of the application must not depend directly on a third-party Socket.IO API.

If no suitable implementation exists, implement the required Engine.IO and Socket.IO functionality within the project's transport layer.

---

# 9. Connection URL

The client shall support:

```text
https://example.org/
```

and installations hosted under a path, such as:

```text
https://example.org/thelounge/
```

The client must not assume that The Lounge is installed at `/`.

The implementation shall determine the correct Socket.IO path from the configured The Lounge installation and its actual web-client behavior.

TLS connections shall use:

```text
wss://
```

where appropriate.

---

# 10. Authentication

The login UI shall provide:

* Server URL;
* username;
* password;
* optional persistent-login setting.

Authentication must reproduce the mechanism used by the target The Lounge web client.

The developer shall determine whether authentication uses:

* HTTP requests;
* Socket.IO events;
* cookies;
* session identifiers;
* authentication tokens;
* a combination of these.

The client shall support session restoration if the server protocol provides it.

Credentials must never be written to normal logs.

Passwords must never be stored in a normal plist or configuration file.

Persistent credentials shall use an appropriate secure credential mechanism where available.

---

# 11. Connection state machine

Implement an explicit state machine:

```text
Disconnected
    │
    ▼
Connecting
    │
    ▼
TransportConnected
    │
    ▼
SocketConnected
    │
    ▼
Authenticating
    │
    ▼
Initializing
    │
    ▼
Ready
```

Error states:

```text
AuthenticationFailed
ProtocolError
ServerDisconnected
ConnectionError
```

Transient state:

```text
Reconnecting
```

The UI shall expose the current state.

Examples:

```text
Connected
Connecting…
Reconnecting…
Disconnected
Authentication failed
```

State transitions must not depend on UI timing.

---

# 12. Application model

Separate server state from local UI state.

## TLServerState

Contains state received from or derived from The Lounge:

* networks;
* channels;
* queries;
* users;
* messages;
* current user;
* server capabilities;
* relevant server/session metadata.

## TLClientState

Contains local state:

* selected network;
* selected channel/query;
* unread state;
* window state;
* UI preferences;
* local display preferences.

This distinction must be maintained throughout the application.

---

# 13. TLNetwork

`TLNetwork` represents a network managed by The Lounge.

It should contain, where provided:

* stable network identifier;
* display name;
* hostname;
* connection state;
* channels;
* queries;
* network metadata;
* supported capabilities.

Unknown server fields should be retained in an extensible metadata structure where practical.

---

# 14. TLChannel

`TLChannel` shall represent supported conversation types.

At minimum, the model must be capable of representing:

```text
CHANNEL
QUERY
LOBBY
SPECIAL
```

where those concepts exist in the target protocol.

Properties should include, where applicable:

* stable channel identifier;
* name;
* type;
* topic;
* users;
* messages;
* unread count;
* highlight count;
* first unread message;
* channel state;
* metadata.

The model must not assume that all conversation types behave like ordinary IRC channels.

---

# 15. TLUser

`TLUser` shall support, where provided:

* nickname;
* username;
* hostname;
* away state;
* modes;
* operator state;
* voice state;
* IRC account information;
* IRCv3 information;
* additional metadata.

Unknown user fields shall not cause protocol failure.

---

# 16. TLMessage

`TLMessage` shall preserve semantic information rather than reducing messages immediately to display text.

Properties should include:

* stable message identifier;
* timestamp;
* sender;
* channel identifier;
* message type;
* raw text;
* parsed text;
* IRC tags;
* formatting information;
* highlight state;
* self/remote state;
* reply/reference metadata where available;
* extensible metadata.

The server-provided message identifier shall be preferred as the authoritative identity.

Any fallback deduplication algorithm must be explicitly treated as heuristic rather than guaranteed identity.

---

# 17. Event dispatcher

Implement:

```text
TLSocketEventDispatcher
```

The processing pipeline shall be:

```text
WebSocket
    ↓
Engine.IO
    ↓
Socket.IO
    ↓
The Lounge event
    ↓
TLSocketEventDispatcher
    ↓
TLoungeProtocol
    ↓
TLServerState
    ↓
UI notifications
```

The dispatcher shall convert raw protocol events into typed application operations.

The UI must never depend directly on event names from the wire protocol.

Unknown events should normally be ignored safely and optionally logged at debug level.

Unknown fields in known payloads should be preserved or ignored without terminating the session.

---

# 18. Initialization

After successful authentication, process the complete initialization/state synchronization sequence used by the target web client.

Do not assume event ordering unless the protocol source demonstrates that ordering is guaranteed.

Initialization shall construct a coherent `TLServerState`.

The application should not report itself as fully ready until the initial required state has been processed.

The initialization process must tolerate:

* optional events;
* unknown fields;
* known events arriving in a different order where permitted;
* errors;
* connection loss during initialization.

---

# 19. IRC operations

The native client shall support the user-facing operations required for normal IRC use.

Initial required operations include:

```text
Send message
Send notice
Join channel
Part channel
Change nickname
Change topic
Set/remove supported modes
Kick user where permitted
Ban user where permitted
Invite user where permitted
WHO/WHOIS where exposed by The Lounge
CTCP where exposed by The Lounge
```

These shall be implemented using the **actual The Lounge client protocol**, not by assuming that the native client should send raw IRC protocol directly.

The native client shall never connect directly to IRC networks.

The conceptual flow is:

```text
User action
    ↓
The Lounge client operation
    ↓
The Lounge server
    ↓
IRC network
```

---

# 20. Messages

The first release shall support at least:

* normal messages;
* notices;
* actions;
* joins;
* parts;
* quits;
* nick changes;
* topic changes;
* mode changes;
* server messages;
* errors;
* away notifications;
* supported CTCP messages;
* IRCv3 tags where exposed by The Lounge.

The exact event mappings shall be documented in `PROTOCOL.md`.

---

# 21. Native message rendering

Messages shall be represented semantically in the model and rendered natively.

Preferred pipeline:

```text
TLMessage
    ↓
Message parser
    ↓
Attributed representation
    ↓
GNUstep native view
```

Use GNUstep attributed-string APIs where available.

Do not use WebKit/WebView as a message renderer.

Do not execute JavaScript or interpret arbitrary HTML supplied by the server.

---

# 22. IRC formatting

Support, where present in the protocol:

* bold;
* italic;
* underline;
* strikethrough;
* foreground colors;
* background colors;
* reverse video;
* reset.

Raw message data must remain available even after formatting has been parsed.

Formatting must not destroy the original message content.

---

# 23. History

History is a required feature.

The client shall support the history mechanism used by the target The Lounge release.

It must:

* load initial history;
* display historical messages;
* support loading older history where the server supports it;
* preserve ordering;
* distinguish historical data from live data internally;
* avoid duplicate messages;
* reconcile history with live messages;
* use server-provided message identifiers where available.

The implementation must test the race where live messages arrive while a history request is outstanding.

---

# 24. Unread and highlight state

Maintain unread and highlight state independently of the currently displayed view.

Support:

* unread count;
* highlight count;
* first unread message where provided;
* clearing unread state when appropriate;
* restoring unread state after reconnect.

Local UI state must not be confused with server-provided unread state.

---

# 25. Channel navigation

The user shall be able to:

* switch networks;
* switch channels;
* switch private conversations;
* switch supported special/lobby views;
* close or hide conversations where supported;
* identify the active conversation;
* see unread counts;
* see highlights.

The application shall preserve the selected conversation locally and restore it after successful reconnection when possible.

---

# 26. Reconnection

Implement automatic reconnection using:

```text
Exponential backoff
Maximum delay
Randomized jitter
```

A reasonable starting policy is:

```text
1s
2s
4s
8s
16s
30s maximum
```

with jitter applied.

On reconnection:

1. establish a new transport session;
2. authenticate or restore the session;
3. perform the required synchronization;
4. reconcile the existing local model;
5. restore selected UI state;
6. reconcile unread/history state;
7. resume normal operation.

Do not blindly replay previously sent IRC operations.

Only operations with an explicit protocol acknowledgement may be considered for retry, and retries must be carefully defined to avoid duplicate IRC actions.

---

# 27. Reconciliation

The client must treat reconnect synchronization as reconciliation rather than simply appending new data.

The implementation must prevent duplicate:

* networks;
* channels;
* users;
* messages.

Existing objects should be updated where stable identifiers match.

Removed server objects must be removed or marked appropriately.

The reconciliation algorithm shall be tested against:

* channel creation during disconnect;
* channel removal during disconnect;
* messages arriving while disconnected;
* nickname changes;
* user list changes;
* history changes.

---

# 28. Threading

Network operations must never block the main GNUstep UI thread.

Recommended architecture:

```text
Main thread
    │
    ├── UI
    ├── client state
    └── model notifications

Network queue
    │
    ├── WebSocket
    ├── Engine.IO
    ├── Socket.IO
    └── The Lounge protocol
```

Model notifications consumed by the UI must be marshalled onto the main thread.

All socket writes shall be serialized.

Connection state transitions shall be synchronized.

The implementation must safely handle:

* disconnect during connect;
* shutdown during reconnect;
* incoming events during initialization;
* concurrent UI commands;
* duplicate authentication callbacks.

---

# 29. TLS and security

The client shall:

* support HTTPS;
* support WSS;
* validate TLS certificates;
* validate hostnames;
* reject invalid certificates by default;
* never disable TLS verification globally;
* never execute JavaScript received from the server;
* treat all server-provided content as untrusted;
* enforce reasonable packet/message size limits;
* protect credentials and tokens from logs.

Any future self-signed certificate workflow must require explicit user confirmation.

---

# 30. URL handling

URLs appearing in messages shall be treated as untrusted input.

The client may recognize and open supported schemes through the operating system.

It must not:

* execute arbitrary shell commands;
* interpret message content as scripts;
* automatically execute downloaded files;
* invoke arbitrary URI schemes without validation.

---

# 31. Logging

Implement:

```text
TLLogger
```

with:

```text
error
warning
info
debug
trace
```

Normal logging must never include:

* passwords;
* authentication tokens;
* session cookies;
* private message contents.

A protocol trace mode may be provided for development.

Protocol traces must redact credentials and other sensitive authentication material.

---

# 32. Preferences

Persist:

* server profiles;
* usernames;
* UI preferences;
* window geometry;
* selected theme;
* display preferences.

Passwords and authentication secrets must not be stored in ordinary property lists.

Use an appropriate secure credential store when available.

---

# 33. Native GNUstep UI

The application shall use GNUstep-native controls.

A suggested layout is:

```text
┌──────────────────────────────────────────────────────────┐
│ File  Edit  View  Window  Help                           │
├───────────────┬───────────────────────┬──────────────────┤
│ Networks      │ #channel              │ Users            │
│               │                       │                  │
│ Network A     │ alice: hello          │ @alice           │
│ Network B     │ bob: hi               │ +bob             │
│               │                       │ carol            │
│ Channels      │                       │                  │
│ #general      │                       │                  │
│ #development  │                       │                  │
├───────────────┴───────────────────────┴──────────────────┤
│ Message / Command input                         [Send]   │
└──────────────────────────────────────────────────────────┘
```

The exact UI layout may differ.

The following must be native:

* menus;
* windows;
* channel lists;
* message views;
* user lists;
* input controls;
* dialogs;
* notifications where supported.

---

# 34. Commands and input

The input control shall support ordinary messages and appropriate client commands.

The implementation must distinguish:

```text
client-local command
```

from:

```text
IRC/The Lounge operation
```

Client-local commands should not be sent to the server unnecessarily.

IRC operations shall be translated into the corresponding The Lounge protocol operation.

---

# 35. Notifications

The architecture should support desktop notifications for:

* highlights;
* private messages;
* mentions.

Notification support may initially be limited to platforms where GNUstep provides a suitable native mechanism.

Notifications must respect local user preferences.

---

# 36. Multi-account support

Multi-account support is not required for the first release.

The architecture should nevertheless avoid global singletons that make multiple sessions impossible to add later.

Each account/server connection should conceptually have its own:

```text
TLoungeSession
TLServerState
TLClientState
```

---

# 37. Proxy support

Proxy support is not required for the initial release.

The transport interfaces should avoid making direct proxy support impossible later.

Potential future support:

* HTTP proxy;
* HTTPS proxy;
* SOCKS5.

---

# 38. Protocol capability handling

The client shall tolerate unknown events and fields wherever safely possible.

Optional capabilities shall be represented explicitly.

Example:

```text
Feature                     Supported
--------------------------------------
Basic messaging              yes
History                      yes
IRC formatting               yes
Replies                      optional
Advanced IRCv3               optional
Search                       later
```

The client must not terminate a connection merely because it receives an unknown optional event.

Unsupported required protocol behavior shall produce a clear protocol error.

---

# 39. Error types

Define typed application errors, for example:

```text
TLConnectionError
TLAuthenticationError
TLProtocolError
TLServerError
TLNetworkError
TLTimeoutError
TLUnsupportedFeatureError
```

Errors displayed to users shall be human-readable.

Raw packet data shall be reserved for developer diagnostics.

---

# 40. Application shutdown

On application shutdown:

1. stop accepting new commands;
2. stop reconnect timers;
3. close the Socket.IO session;
4. close Engine.IO;
5. close WebSocket;
6. terminate networking queues;
7. persist preferences;
8. exit cleanly.

The client must not assume that closing the native application should terminate the user's IRC connection on The Lounge.

The Lounge is responsible for maintaining its server-side IRC session.

---

# 41. GNUstep compatibility

The application shall target:

```text
GNUstep Base
GNUstep GUI
```

and AppKit-compatible GNUstep APIs.

Avoid Apple-only APIs unless a GNUstep implementation is verified.

Do not require:

* Cocoa-only frameworks;
* WebKit;
* WebView;
* JavaScriptCore;
* Objective-C APIs unavailable on the target GNUstep environment.

The project shall compile and run on at least one current GNUstep/Linux environment.

---

# 42. Suggested repository structure

```text
TLNative/
├── App/
│   ├── main.m
│   ├── TLApplicationDelegate.*
│   └── ...
│
├── Model/
│   ├── TLServerState.*
│   ├── TLClientState.*
│   ├── TLNetwork.*
│   ├── TLChannel.*
│   ├── TLUser.*
│   └── TLMessage.*
│
├── Protocol/
│   ├── TLoungeProtocol.*
│   ├── TLoungeProtocol_4_5.*
│   ├── TLoungeSession.*
│   ├── TLSocketEventDispatcher.*
│   └── TLProtocolVersion.*
│
├── SocketIO/
│   ├── TLSocketIOClient.*
│   ├── TLSocketIOPacket.*
│   └── TLSocketIOParser.*
│
├── EngineIO/
│   ├── TLEngineIOClient.*
│   ├── TLEngineIOPacket.*
│   └── TLEngineIOParser.*
│
├── WebSocket/
│   ├── TLWebSocketTransport.*
│   └── ...
│
├── UI/
│   ├── TLMainWindowController.*
│   ├── TLNetworkView.*
│   ├── TLChannelView.*
│   ├── TLUserListView.*
│   ├── TLMessageView.*
│   ├── TLLoginController.*
│   └── ...
│
├── Tests/
│   ├── EngineIO/
│   ├── SocketIO/
│   ├── Protocol/
│   ├── Model/
│   └── Integration/
│
├── Tools/
│   └── thelounge-protocol-dump/
│
├── PROTOCOL.md
├── ARCHITECTURE.md
├── COMPATIBILITY.md
└── README.md
```

If an external Socket.IO implementation is adopted, the corresponding directories may instead contain adapter interfaces.

---

# 43. Developer diagnostic tool

Provide a development-only tool:

```text
thelounge-protocol-dump
```

It shall connect to a test The Lounge server and display:

```text
Engine.IO packet
Socket.IO packet
event name
decoded payload
```

Example:

```text
[RX] ENGINE.IO MESSAGE
[RX] SOCKET.IO EVENT
[RX] EVENT: <event-name>
[RX] PAYLOAD: <sanitized payload>
```

Sensitive authentication fields must be automatically redacted.

This tool is intended to assist protocol development and regression testing.

---

# 44. Testing requirements

## 44.1 Unit tests

Test:

* WebSocket framing;
* Engine.IO packet parsing;
* Engine.IO serialization;
* heartbeat;
* Socket.IO packet parsing;
* Socket.IO serialization;
* acknowledgements;
* JSON parsing;
* protocol event dispatch;
* model updates;
* IRC formatting;
* deduplication;
* reconnection state machine.

---

## 44.2 Golden protocol fixtures

Create sanitized protocol fixtures for:

```text
Authentication
Initial synchronization
Network creation/update
Channel creation/update
User list
Receive message
Send message
History
Join
Part
Quit
Nick change
Topic change
Disconnect
Reconnect
Error
```

Tests shall verify:

```text
wire data
    ↓
transport parser
    ↓
protocol event
    ↓
model mutation
```

produces the expected result.

Fixtures must not contain real credentials, session tokens, or private conversations.

---

# 45. Integration testing

Use a disposable The Lounge test installation.

Test at minimum:

* successful authentication;
* failed authentication;
* initial state;
* multiple networks;
* channels;
* private conversations;
* sending a message;
* receiving a message;
* JOIN;
* PART;
* NICK;
* topic changes;
* user changes;
* history;
* unread state;
* highlight state;
* disconnect;
* reconnect;
* server-side state changes while disconnected.

Test both direct installation and installation under a non-root URL path where possible.

---

# 46. Reconnection integration tests

Explicitly test:

### Disconnect while idle

Expected:

```text
Disconnected
→ Reconnecting
→ Connected
```

### Disconnect while receiving messages

The client must not lose or duplicate messages that become available during synchronization.

### Disconnect during history loading

The client must recover without corrupting history ordering.

### Disconnect during authentication

The authentication state must reset correctly.

### Disconnect during initialization

Partial initialization must not leave the model permanently inconsistent.

### Repeated disconnects

The application must not create multiple reconnect loops.

---

# 47. UI tests

Test:

* login failure;
* connection status;
* network switching;
* channel switching;
* private conversation switching;
* message rendering;
* user list updates;
* unread counters;
* highlights;
* history loading;
* reconnect status;
* application shutdown.

---

# 48. Compatibility documentation

`COMPATIBILITY.md` shall contain:

```text
The Lounge version
Source commit
Socket.IO package version
Engine.IO protocol version
Transport behavior
Authentication behavior
Known supported features
Known unsupported features
Known protocol differences
Test date
Test environment
```

Example:

```text
The Lounge: 4.5.x
Protocol implementation: TLoungeProtocol_4_5
Transport: WebSocket
Socket.IO: <verified version>
Engine.IO: <verified version>
GNUstep: <verified version>
Platform: Linux
```

Do not claim compatibility with an untested release.

---

# 49. Initial feature scope

## Required for version 1

* server profile creation;
* server URL;
* authentication;
* secure session handling;
* TLS;
* connection status;
* networks;
* channels;
* private conversations;
* channel switching;
* message sending;
* message receiving;
* joins;
* parts;
* quits;
* nickname changes;
* topic display;
* user list;
* unread counts;
* highlights;
* server history;
* automatic reconnection;
* native message rendering;
* basic IRC formatting.

## Secondary features

* notices;
* actions;
* CTCP;
* channel modes;
* user modes;
* WHOIS;
* desktop notifications;
* advanced IRCv3 features.

## Later features

* search;
* message replies;
* advanced previews;
* multi-account UI;
* themes beyond the initial implementation;
* file-related features;
* plugin support.

---

# 50. Non-goals

Version 1 shall not:

* connect directly to IRC networks;
* implement a separate IRC client/server stack;
* require a The Lounge plugin;
* modify The Lounge;
* embed a browser;
* embed WebKit;
* execute JavaScript;
* implement the The Lounge public plugin API as the client protocol;
* store plaintext passwords;
* replay arbitrary commands after reconnection.

---

# 51. Development sequence

The implementation shall proceed in this order.

## Phase 0 — Protocol reconnaissance

Produce:

```text
PROTOCOL.md
```

Determine:

* authentication;
* session behavior;
* Socket.IO namespace/path;
* event names;
* payloads;
* initialization;
* state synchronization;
* messaging;
* history;
* reconnect behavior.

Do not build the full UI during this phase.

---

## Phase 1 — Dependency and transport evaluation

Determine whether an existing Socket.IO/WebSocket implementation can be used.

Prefer a maintained implementation over writing a complete protocol stack unnecessarily.

Produce the transport decision in `ARCHITECTURE.md`.

---

## Phase 2 — Transport

Implement and test:

```text
WebSocket
↓
Engine.IO
↓
Socket.IO
```

or integrate the selected external implementation behind the project's interfaces.

---

## Phase 3 — Authentication/session

Implement:

```text
connect
→ authenticate
→ session established
```

including failure and reconnect behavior.

---

## Phase 4 — Initial synchronization

Implement:

```text
authentication
→ initial state
→ TLServerState
```

without building the complete UI yet.

---

## Phase 5 — Application model

Implement:

```text
TLServerState
TLClientState
TLNetwork
TLChannel
TLUser
TLMessage
```

with unit tests.

---

## Phase 6 — Messaging and history

Implement:

* receive messages;
* send messages;
* IRC events;
* history;
* unread state;
* highlights;
* reconciliation.

---

## Phase 7 — Reconnection

Implement and test:

```text
disconnect
→ backoff
→ reconnect
→ authenticate/session restore
→ synchronize
→ reconcile
```

---

## Phase 8 — Native UI

Build the GNUstep interface only after the protocol and model layers are functional.

---

## Phase 9 — Compatibility and packaging

Test against the target The Lounge release and later compatible releases where practical.

Produce:

* build instructions;
* compatibility documentation;
* protocol fixtures;
* developer diagnostic tool;
* release package.

---

# 52. Definition of done

The project is complete when a user can:

1. Launch the GNUstep application.
2. Enter an HTTPS The Lounge server URL.
3. Authenticate successfully.
4. See the available networks.
5. See channels and private conversations.
6. Select a conversation.
7. See server-provided history.
8. Receive live messages.
9. Send messages.
10. See joins, parts, quits, and nickname changes.
11. See topic changes.
12. See users and relevant user state.
13. See unread and highlight state.
14. Disconnect from the network.
15. Have the client automatically reconnect.
16. Recover coherent state after reconnection.
17. Continue using the application without restarting.
18. Close the native client without terminating The Lounge's persistent IRC session.
19. Perform all of the above without WebKit, WebView, a browser, or JavaScript.

---

# 53. Acceptance criteria

The implementation shall not be considered complete merely because it can establish a WebSocket connection.

The following must all work against a real disposable The Lounge installation:

```text
✓ Authentication
✓ Initial synchronization
✓ Network display
✓ Channel display
✓ User display
✓ History
✓ Receive message
✓ Send message
✓ IRC state changes
✓ Unread/highlight state
✓ Disconnect
✓ Reconnect
✓ State reconciliation
✓ TLS
✓ Native UI
```

The protocol implementation must also be covered by automated tests using sanitized fixtures.

---

# 54. Final implementation rule

The central engineering rule is:

> **The native client is an implementation of The Lounge's client protocol, not an implementation of its public plugin API and not a direct IRC client.**

The architecture shall therefore remain:

```text
GNUstep UI
     ↓
Application model
     ↓
The Lounge protocol adapter
     ↓
Socket.IO
     ↓
Engine.IO
     ↓
WebSocket
     ↓
The Lounge
     ↓
IRC
```

The **The Lounge protocol adapter is the version-sensitive component**.

Everything above it should remain as independent as possible from The Lounge's JavaScript implementation details.

Everything below it should remain independent of GNUstep UI details.

The first development milestone is therefore **not the main window**. It is a verified, version-pinned `PROTOCOL.md` accompanied by sanitized protocol fixtures proving that the native client can authenticate, initialize, receive a message, send a message, load history, and reconnect successfully.
