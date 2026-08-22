# The Lounge

The Lounge is a native GNUstep desktop client for
[The Lounge](https://thelounge.chat/), a self-hosted IRC bouncer. It speaks
the same client/server protocol as the The Lounge web client, so it connects
to an existing The Lounge installation and never connects to IRC networks
directly.

It is written in Objective-C and built entirely from native GNUstep/AppKit
components. There is **no embedded browser, WebKit, WebView, or JavaScript
runtime** anywhere in the application.

## Status

Working:

- Login with password; the session token returned by the server is stored
  (file permissions 0600) and reused for fast re-authentication.
- Server URL, username and "remember me" flag persist across launches.
- Sidebar with networks and channels (unread counts, highlight bolding),
  message pane (mIRC formatting, colors, actions), user list with mode
  prefixes.
- Channel switching marks channels read (`open`), requests user lists,
  restores history; scrolling to the top loads older messages (`more`).
- Sending: plain text as message, `/command` lines forwarded for the server
  to parse.
- Automatic reconnection with exponential backoff and jitter; on reconnect a
  delta `init` is merged into existing state (no duplicates).
- Main window size and position persist across launches.
- Native main menu: About panel, Hide/Show, Close Window (Cmd-W), standard
  Edit keys, Window menu with window list.

Known limitations:

- Network creation/editing (`network:new`/`network:edit`) not yet in the UI.
- Settings (`setting:*`), mentions and session lists are ignored.
- IRC color codes 0 (white) and other bright palette entries are hard to read
  on the light theme.

## Requirements

- GNUstep with AppKit (verified: gnustep-make 2.9.3, GNUstep Base 1.31.1 on
  Debian Linux). GNUstep GUI is required.
- clang (Objective-C compiler).
- libcurl 8.x with WebSocket support (`ws`/`wss` protocols, `curl_ws_send` /
  `curl_ws_recv`). Verified: libcurl 8.14.1.
- A running The Lounge server, 4.5.x or compatible.

## Build

```sh
source /System/Library/Makefiles/GNUstep.sh
cd TLNative
make
```

The build must complete with zero warnings.

## Install

```sh
sudo make install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
```

The GNUmakefile pins `GNUSTEP_INSTALLATION_DOMAIN = SYSTEM`; nothing may be
installed to the LOCAL domain. After installing, verify there are no
leftovers under `/Local/Applications` or `/Local/Library`.

The bundle directory stays `TheLounge.app` (gnustep-make does not accept
spaces in APP_NAME); the user-visible application name is set to
"The Lounge" via `ApplicationName`/`CFBundleName` in the Info.plist, which
also feeds the generated `.desktop` entry.

## Run

```sh
openapp TheLounge
```

or directly:

```sh
/System/Applications/TheLounge.app/TheLounge
```

First run: enter the server URL (for example
`https://lounge.example.net/`), your The Lounge username and password, and
press Connect. On success the login window closes and the chat window opens.
On later runs the connection fields are pre-filled and the stored session
token authenticates without a password.

## Tests

Unit tests live in `TLNative/Tests`. Build and run them:

```sh
cd TLNative/Tests
make
./obj/t_model      # model objects and wire parsing
./obj/t_engineio   # Engine.IO packets
./obj/t_socketio   # Socket.IO packets
./obj/t_protocol   # event dispatch, model updates, reconciliation
./obj/t_session    # live end-to-end session against a real server
```

`t_model`, `t_engineio`, `t_socketio` and `t_protocol` are offline parser
tests; `t_session` connects to a configured The Lounge server and runs a
full connect/auth/init/message cycle (server URL configurable at the top of
the file). See COMPATIBILITY.md for the servers tested.

## Developer tool

`TLNative/Tools/thelounge-protocol-dump` connects to a The Lounge server and
prints each Engine.IO packet, Socket.IO packet, event name and decoded
payload, with authentication fields redacted automatically:

```text
[RX] EVENT: init
[RX] PAYLOAD: {...}
```

Development and regression testing only; not part of the shipped app.

## Architecture

Four layers (details in ARCHITECTURE.md):

1. **GNUstep UI (AppKit)** - login window, main window (network outline,
   message view, user list, input bar), menus. The UI never touches raw
   packets; it observes model notifications only.
2. **Application model** - `TLServerState`, `TLClientState`, `TLNetwork`,
   `TLChannel`, `TLUser`, `TLMessage`. Mutations happen on the main thread.
3. **Protocol adapter** - `TLoungeProtocol_4_5` pins The Lounge 4.5 behavior;
   `TLoungeSession` owns connection lifecycle, authentication state,
   reconnect/backoff and token persistence.
4. **Transport** - `TLSocketIOClient` (Socket.IO v5), `TLEngineIOClient`
   (Engine.IO v4) and `TLWebSocketTransport` (libcurl `CURLWS`). All I/O on
   one dedicated network thread; sends serialized through a queue; inbound
   events marshalled to the main thread.

Security: TLS verification always on, no JavaScript anywhere, passwords and
tokens never written to logs or property lists (the token file is chmod
0600).

## Documentation

- `PROTOCOL.md` - how the client talks to the server (concise wire reference).
- `SPEC.md` - the development specification.
- `ARCHITECTURE.md` - transport, threading and security decisions.
- `COMPATIBILITY.md` - what has actually been tested against which releases.
