/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLLoginController.h"

@implementation TLLoginController

- (instancetype)init
{
	NSRect contentRect = NSMakeRect(0, 0, 420, 220);
	NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
		styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	[window setTitle:@"Connect to The Lounge"];
	// The controller owns the window across close/show cycles, so a close
	// must not deallocate it while the controller still references it.
	[window setReleasedWhenClosed:NO];
	[window center];

	self = [super initWithWindow:window];
	[window release];
	if (self) {
		[self buildContentViewForWindow:window];
	}
	return self;
}

// Lays out one labeled input row per the Gershwin appearance metrics:
// right-aligned label column, 22px field, rows top-anchored with a 30px
// rhythm (8px gap + 22px control).
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
	// GNUstep inflates the contentView by ~5px; laying out against the
	// window's own content width keeps the side margins symmetric.
	CGFloat width = NSWidth([window contentRectForFrameRect:[window frame]]);
	const CGFloat sideMargin = 24.0;
	const CGFloat bottomMargin = 12.0;
	CGFloat y = NSHeight([window contentRectForFrameRect:[window frame]])
	    - 15.0 - 22.0;

	_serverField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 10, 22)];
	NSString *savedURL = [[NSUserDefaults standardUserDefaults]
		stringForKey:@"ServerURL"];
	if ([savedURL length] > 0) {
		[_serverField setStringValue:savedURL];
	} else {
		[_serverField setStringValue:@"https://"];
	}
	[_serverField setPlaceholderString:@"https://lounge.example.com"];
	[self addRowWithLabel:@"Server URL" field:_serverField
		toView:contentView y:y width:width];
	y -= 30.0;

	_usernameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 10, 22)];
	NSString *savedUsername = [[NSUserDefaults standardUserDefaults]
		stringForKey:@"Username"];
	if ([savedUsername length] > 0) {
		[_usernameField setStringValue:savedUsername];
	}
	[self addRowWithLabel:@"Username" field:_usernameField
		toView:contentView y:y width:width];
	y -= 30.0;

	_passwordField = [[NSSecureTextField alloc] initWithFrame:
		NSMakeRect(0, 0, 10, 22)];
	[self addRowWithLabel:@"Password" field:_passwordField
		toView:contentView y:y width:width];
	y -= 12.0;

	_rememberButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(sideMargin + 110.0 + 8.0, y - 18.0,
			NSWidth([contentView frame]) - sideMargin - 118.0, 18.0)];
	[_rememberButton setButtonType:NSSwitchButton];
	[_rememberButton setTitle:@"Remember me"];
	[_rememberButton setAutoresizingMask:NSViewMinYMargin];
	if ([[NSUserDefaults standardUserDefaults] objectForKey:@"RememberMe"] != nil) {
		[_rememberButton setState:[[NSUserDefaults standardUserDefaults]
			boolForKey:@"RememberMe"] ? NSOnState : NSOffState];
	} else {
		[_rememberButton setState:NSOnState];
	}
	[contentView addSubview:_rememberButton];

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

// The cursor belongs in the first field the user still has to fill in;
// the bare scheme template in the server field counts as "to be filled".
- (void)focusFirstEmptyField
{
	NSArray *fields = [NSArray arrayWithObjects:
	    _serverField, _usernameField, _passwordField, nil];
	for (NSTextField *field in fields) {
		NSString *value = [field stringValue];
		if ([value length] == 0 || [value isEqualToString:@"https://"]) {
			[[self window] makeFirstResponder:field];
			return;
		}
	}
}

- (void)showWindow:(id)sender
{
	[super showWindow:sender];
	[self focusFirstEmptyField];
}

- (IBAction)connect:(id)sender
{	NSString *serverText = [[_serverField stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([serverText length] == 0) {
		[self setStatusText:@"Please enter the server URL."];
		NSBeep();
		return;
	}
	// Users habitually omit the scheme; default to HTTPS rather than
	// rejecting the input.
	if (![serverText hasPrefix:@"http://"] && ![serverText hasPrefix:@"https://"]) {
		serverText = [@"https://" stringByAppendingString:serverText];
	}
	NSURL *serverURL = [NSURL URLWithString:serverText];
	if (!serverURL || [[serverURL host] length] == 0) {
		[self setStatusText:@"The server URL is not valid."];
		NSBeep();
		return;
	}
	NSString *username = [[_usernameField stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([username length] == 0) {
		[self setStatusText:@"Please enter your username."];
		NSBeep();
		return;
	}

	NSString *password = [_passwordField stringValue];
	BOOL remember = ([_rememberButton state] == NSOnState);

	// Persist the connection details so the next launch starts pre-filled.
	// The password is intentionally never stored here; the session-token
	// mechanism handles re-authentication for remembered logins.
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:serverText forKey:@"ServerURL"];
	[defaults setObject:username forKey:@"Username"];
	[defaults setBool:remember forKey:@"RememberMe"];

	[_connectButton setEnabled:NO];
	[self setStatusText:@"Connecting..."];
	if ([_delegate respondsToSelector:@selector(loginController:didSubmitServerURL:
		username:password:remember:)]) {
		[_delegate loginController:self didSubmitServerURL:serverURL
			username:username password:password remember:remember];
	}
}

- (void)setStatusText:(NSString *)text
{
	[_statusLabel setStringValue:text ? text : @""];
}

- (void)prepareForRetry
{
	[_connectButton setEnabled:YES];
	[self setStatusText:@""];
	[_passwordField setStringValue:@""];
	[self focusFirstEmptyField];
}

- (void)dealloc
{
	[_serverField release];
	[_usernameField release];
	[_passwordField release];
	[_rememberButton release];
	[_connectButton release];
	[_statusLabel release];
	[super dealloc];
}

@end