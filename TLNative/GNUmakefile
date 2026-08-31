GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = TheLounge

TheLounge_OBJC_FILES = $(wildcard App/*.m UI/*.m Model/*.m Protocol/*.m \
                             SocketIO/*.m EngineIO/*.m WebSocket/*.m Support/*.m \
                             Bubbles/*.m)

# TheLoungeInfo.plist is picked up automatically by gnustep-make and merged
# into the generated Info.plist (see Instance/rules.make GNUSTEP_PLIST_DEPEND).
ADDITIONAL_CPPFLAGS += -I$(CURDIR)/App -I$(CURDIR)/UI -I$(CURDIR)/Model \
                       -I$(CURDIR)/Protocol -I$(CURDIR)/SocketIO \
                       -I$(CURDIR)/EngineIO -I$(CURDIR)/WebSocket \
                       -I$(CURDIR)/Support -I$(CURDIR)/Bubbles
# Model properties intentionally mirror The Lounge wire field names
# (newNick, newIdent, newHost, rawText) which trigger the Cocoa ownership
# naming heuristic; the names are correct for this project.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

ADDITIONAL_GUI_LIBS += -lcurl -lcrypto

# App icon is placed in Resources/ of the .app bundle.
TheLounge_RESOURCE_FILES = TheLounge.png

include $(GNUSTEP_MAKEFILES)/application.make