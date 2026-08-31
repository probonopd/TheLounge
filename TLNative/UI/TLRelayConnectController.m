/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLRelayConnectController.h"
#import "TLNostrSocketClient.h"

@implementation TLRelayConnectController

- (instancetype)init
{
	NSRect contentRect = NSMakeRect(0, 0, 440, 250);
	NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
		styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	[window setTitle:@"Connect to Nosterm Relay"];
	[window setReleasedWhenClosed:NO];
	[window center];

	self = [super initWithWindow:window];
	[window release];
	if (self) {
		[self buildContentViewForWindow:window];
	}
	return self;
}

- (void)addRowWithLabel:(NSString *)title
	field:(NSTextField *)field
	toView:(NSView *)content
	y:(CGFloat)y
	width:(CGFloat)contentWidth
{
	const CGFloat labelWidth = 110.0;

	NSTextField *label = [self labelWithTitle:title
		frame:NSMakeRect(24.0, y + 3.0, labelWidth, 17.0)];
	[label setAutoresizingMask:NSViewMinYMargin];
	[content addSubview:label];

	[field setFrame:NSMakeRect(24.0 + labelWidth + 8.0, y,
		contentWidth - 2.0 * 24.0 - labelWidth - 8.0, 22.0)];
	[field setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[content addSubview:field];
}

- (void)buildContentViewForWindow:(NSWindow *)window
{
	NSView *contentView = [window contentView];
	CGFloat width = NSWidth([window contentRectForFrameRect:[window frame]]);
	const CGFloat sideMargin = 24.0;
	const CGFloat bottomMargin = 12.0;
	CGFloat y = NSHeight([window contentRectForFrameRect:[window frame]])
	    - 15.0 - 22.0;

	_relayField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 10, 22)];
	[_relayField setStringValue:TLLoungeNosternDefaultRelayURL];
	[_relayField setPlaceholderString:@"wss://relay.example.com"];
	[self addRowWithLabel:@"Relay URL" field:_relayField
		toView:contentView y:y width:width];
	y -= 30.0;

	_nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 10, 22)];
	[_nameField setPlaceholderString:@"display name (optional)"];
	[self addRowWithLabel:@"Display name" field:_nameField
		toView:contentView y:y width:width];
	y -= 30.0;

	_keyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 10, 22)];
	[_keyField setPlaceholderString:@"private key hex (optional, 64 chars)"];
	[self addRowWithLabel:@"Private key" field:_keyField
		toView:contentView y:y width:width];
	y -= 12.0;

	_connectButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(width - sideMargin - 100.0,
			bottomMargin + 16.0 + 12.0, 100.0, 20.0)];
	[_connectButton setButtonType:NSMomentaryLightButton];
	[_connectButton setBezelStyle:NSRoundedBezelStyle];
	[_connectButton setTitle:@"Connect"];
	[_connectButton setTarget:self];
	[_connectButton setAction:@selector(connect:)];
	[_connectButton setKeyEquivalent:@"\r"];
	[_connectButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
	[contentView addSubview:_connectButton];

	_statusLabel = [[NSTextField alloc] initWithFrame:
		NSMakeRect(sideMargin, bottomMargin,
			width - 2.0 * sideMargin, 16.0)];
	[_statusLabel setEditable:NO];
	[_statusLabel setSelectable:NO];
	[_statusLabel setBezeled:NO];
	[_statusLabel setDrawsBackground:NO];
	[_statusLabel setTextColor:[NSColor colorWithCalibratedWhite:0.30 alpha:1.0]];
	[_statusLabel setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
	[contentView addSubview:_statusLabel];
}

- (NSTextField *)labelWithTitle:(NSString *)title frame:(NSRect)frame
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	[label setStringValue:title];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setAlignment:NSRightTextAlignment];
	return [label autorelease];
}

- (void)showWindow:(id)sender
{
	[super showWindow:sender];
	[[self window] makeFirstResponder:_relayField];
}

- (IBAction)connect:(id)sender
{
	NSString *relayText = [[_relayField stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([relayText length] == 0) {
		[self setStatusText:@"Please enter the relay URL."];
		NSBeep();
		return;
	}
	if (![relayText hasPrefix:@"ws://"] && ![relayText hasPrefix:@"wss://"]) {
		relayText = [@"wss://" stringByAppendingString:relayText];
	}
	NSURL *relayURL = [NSURL URLWithString:relayText];
	if (!relayURL || [[relayURL host] length] == 0) {
		[self setStatusText:@"The relay URL is not valid."];
		NSBeep();
		return;
	}

	NSString *privateKey = [_keyField stringValue];
	privateKey = [privateKey stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([privateKey length] > 0 && [privateKey length] != 64) {
		[self setStatusText:@"Private key must be 64 hex characters."];
		NSBeep();
		return;
	}

	NSString *username = [[_nameField stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	[_connectButton setEnabled:NO];
	[self setStatusText:@"Connecting..."];
	if ([_delegate respondsToSelector:@selector(relayController:didSubmitRelayURL:
		username:privateKey:)]) {
		[_delegate relayController:self didSubmitRelayURL:relayURL
			username:username privateKey:privateKey];
	}
}

- (void)setStatusText:(NSString *)text
{
	[_statusLabel setStringValue:text ? text : @""];
}

- (void)setConnectEnabled:(BOOL)enabled
{
	[_connectButton setEnabled:enabled];
}

- (void)dealloc
{
	[_relayField release];
	[_nameField release];
	[_keyField release];
	[_connectButton release];
	[_statusLabel release];
	[super dealloc];
}

@end
