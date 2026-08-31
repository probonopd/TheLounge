include $(GNUSTEP_MAKEFILES)/common.make

TEST_TOOL_NAME = t_model t_engineio t_socketio t_protocol t_session t_contextmenu \
                 t_bubbles t_badge t_nostr_crypto t_nosterm_live t_nosterm_catchup \
                 t_nosterm_cleanup t_nosterm_nickname t_nosterm_read

ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/TestFramework \
                       -I../Model -I../EngineIO -I../SocketIO -I../Protocol \
                       -I../Support -I../WebSocket -I../UI -I../Bubbles
# Model properties intentionally mirror The Lounge wire field names
# (newNick, newIdent, newHost, rawText) which trigger the Cocoa ownership
# naming heuristic; the names are correct for this project.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

MODEL_SRC = ../Model/TLUser.m ../Model/TLMessage.m ../Model/TLChannel.m \
            ../Model/TLNetwork.m ../Model/TLServerState.m ../Model/TLClientState.m
EIO_SRC = ../EngineIO/TLEngineIOPacket.m ../EngineIO/TLEngineIOParser.m
SIO_SRC = ../SocketIO/TLSocketIOPacket.m ../SocketIO/TLSocketIOParser.m
PROTO_SRC = ../Protocol/TLProtocolVersion.m ../Protocol/TLSocketEventDispatcher.m \
            ../Protocol/TLNostrCrypto.m ../Protocol/TLNostrSocketClient.m \
            ../Protocol/TLoungeProtocol.m ../Protocol/TLoungeProtocol_4_5.m \
            ../Protocol/TLoungeProtocol_Nosterm.m \
            ../Protocol/TLoungeSession.m
SUPPORT_SRC = ../Support/TLLogger.m

t_model_OBJC_FILES = t_model.m $(MODEL_SRC)
t_engineio_OBJC_FILES = t_engineio.m $(EIO_SRC) $(SUPPORT_SRC)
t_socketio_OBJC_FILES = t_socketio.m $(SIO_SRC) $(SUPPORT_SRC) $(EIO_SRC)
t_protocol_OBJC_FILES = t_protocol.m $(PROTO_SRC) $(MODEL_SRC) $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m

t_protocol_TOOL_LIBS += -lcurl -lcrypto

t_session_OBJC_FILES = t_session.m $(PROTO_SRC) $(MODEL_SRC) $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m
t_session_TOOL_LIBS += -lcurl -lcrypto

# The context menu builder is AppKit code; NSMenu/NSMenuItem work headless.
UI_SRC = ../UI/TLContextMenuBuilder.m

t_contextmenu_OBJC_FILES = t_contextmenu.m $(UI_SRC) $(MODEL_SRC)
t_contextmenu_TOOL_LIBS += -lgnustep-gui

BUBBLE_SRC = ../Bubbles/TLBubbleMessage.m ../Bubbles/TLBubbleTheme.m \
             ../Bubbles/TLBubbleTranscriptView.m

# The transcript view is AppKit code; NSView/NSTextStorage work headless.
t_bubbles_OBJC_FILES = t_bubbles.m $(BUBBLE_SRC) ../UI/TLMessageRenderer.m \
            ../UI/TLLinkDetector.m ../UI/TLUserListView.m ../UI/TLMessageView.m \
            ../Support/TLPreferences.m $(MODEL_SRC)
t_bubbles_TOOL_LIBS += -lgnustep-gui

t_badge_OBJC_FILES = t_badge.m $(MODEL_SRC)
t_badge_TOOL_LIBS += -lgnustep-gui

t_nostr_crypto_OBJC_FILES = t_nostr_crypto.m ../Protocol/TLNostrCrypto.m
t_nostr_crypto_TOOL_LIBS += -lcrypto

# Live relay integration test. Reads TL_NOSTERM_TEST_KEY (and optionally
# TL_NOSTERM_TEST_RELAY) from the environment; SKIPs cleanly when unset.
t_nosterm_live_OBJC_FILES = t_nosterm_live.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m
t_nosterm_live_TOOL_LIBS += -lcurl -lcrypto

# Offline catch-up test: a message posted by a second identity while the first
# is offline must replay on the first's reconnect. Same gating as the live test.
t_nosterm_catchup_OBJC_FILES = t_nosterm_catchup.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m
t_nosterm_catchup_TOOL_LIBS += -lcurl -lcrypto

# Cleanup: deletes NIP-29 groups the test identity published on the relay, so
# repeated live runs do not leave "tltest-"/"catchup-" groups behind. Gated by
# TL_NOSTERM_TEST_KEY, same as the other live tests.
t_nosterm_cleanup_OBJC_FILES = t_nosterm_cleanup.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m
t_nosterm_cleanup_TOOL_LIBS += -lcurl -lcrypto

# Offline nickname-resolution unit test: drives kind 0 metadata parsing and
# displayNameForPubkey: directly, no relay required.
t_nosterm_nickname_OBJC_FILES = t_nosterm_nickname.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m
t_nosterm_nickname_TOOL_LIBS += -lcurl -lcrypto

# Read-only relay test: connects to #general and prints the last 3 messages.
t_nosterm_read_OBJC_FILES = t_nosterm_read.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m
t_nosterm_read_TOOL_LIBS += -lcurl -lcrypto

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/test-tool.make