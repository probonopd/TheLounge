GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = BubbleDemo

BubbleDemo_OBJC_FILES = main.m ../Bubbles/TLBubbleMessage.m \
                        ../Bubbles/TLBubbleTheme.m \
                        ../Bubbles/TLBubbleTranscriptView.m

ADDITIONAL_CPPFLAGS += -I$(CURDIR)/../Bubbles
# Zero-warning policy of the parent project applies here as well.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

include $(GNUSTEP_MAKEFILES)/application.make
