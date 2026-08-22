include $(GNUSTEP_MAKEFILES)/common.make

TEST_TOOL_NAME = t_model t_engineio t_socketio t_protocol t_session

ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/TestFramework \
                      -I../Model -I../EngineIO -I../SocketIO -I../Protocol \
                      -I../Support -I../WebSocket
# Model properties intentionally mirror The Lounge wire field names
# (newNick, newIdent, newHost, rawText) which trigger the Cocoa ownership
# naming heuristic; the names are correct for this project.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

MODEL_SRC = ../Model/TLUser.m ../Model/TLMessage.m ../Model/TLChannel.m \
            ../Model/TLNetwork.m ../Model/TLServerState.m ../Model/TLClientState.m
EIO_SRC = ../EngineIO/TLEngineIOPacket.m ../EngineIO/TLEngineIOParser.m
SIO_SRC = ../SocketIO/TLSocketIOPacket.m ../SocketIO/TLSocketIOParser.m
PROTO_SRC = ../Protocol/TLProtocolVersion.m ../Protocol/TLSocketEventDispatcher.m \
            ../Protocol/TLoungeProtocol.m ../Protocol/TLoungeProtocol_4_5.m \
            ../Protocol/TLoungeSession.m
SUPPORT_SRC = ../Support/TLLogger.m

t_model_OBJC_FILES = t_model.m $(MODEL_SRC)
t_engineio_OBJC_FILES = t_engineio.m $(EIO_SRC) $(SUPPORT_SRC)
t_socketio_OBJC_FILES = t_socketio.m $(SIO_SRC) $(SUPPORT_SRC) $(EIO_SRC)
t_protocol_OBJC_FILES = t_protocol.m $(PROTO_SRC) $(MODEL_SRC) $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m

t_protocol_TOOL_LIBS += -lcurl

t_session_OBJC_FILES = t_session.m $(PROTO_SRC) $(MODEL_SRC) $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            ../WebSocket/TLWebSocketTransport.m ../EngineIO/TLEngineIOClient.m \
            ../SocketIO/TLSocketIOClient.m
t_session_TOOL_LIBS += -lcurl

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/test-tool.make