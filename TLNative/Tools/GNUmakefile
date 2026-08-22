GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = thelounge-protocol-dump

thelounge-protocol-dump_OBJC_FILES = thelounge-protocol-dump/main.m \
    $(wildcard ../EngineIO/*.m) \
    $(wildcard ../SocketIO/*.m) \
    $(wildcard ../WebSocket/*.m) \
    $(wildcard ../Support/*.m)

ADDITIONAL_CPPFLAGS += -I$(CURDIR)/../EngineIO -I$(CURDIR)/../SocketIO \
                      -I$(CURDIR)/../WebSocket -I$(CURDIR)/../Support
# Model properties intentionally mirror The Lounge wire field names
# (newNick, newIdent, newHost, rawText) which trigger the Cocoa ownership
# naming heuristic; the names are correct for this project.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

ADDITIONAL_TOOL_LIBS += -lcurl

include $(GNUSTEP_MAKEFILES)/tool.make