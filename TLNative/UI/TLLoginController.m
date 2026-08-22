/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLLoginController.h"

@implementation TLLoginController

- (instancetype)init
{
	NSRect contentRect = NSMakeRect(0, 0, 420, 280);
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

- (void)buildContentViewForWindow:(NSWindow *)window
{
	NSView *contentView = [window contentView];

	_serverField = [[NSTextField alloc] initWithFrame:NSMakeRect(115, 236, 285, 22)];
	NSString *savedURL = [[NSUserDefaults standardUserDefaults]
		stringForKey:@"ServerURL"];
	if ([savedURL length] > 0) {
		[_serverField setStringValue:savedURL];
	} else {
		[_serverField setStringValue:@"https://"];
	}
	[_serverField setPlaceholderString:@"https://lounge.example.com"];
	[contentView addSubview:[self labelWithTitle:@"Server URL"
		frame:NSMakeRect(20, 240, 90, 17)]];
	[contentView addSubview:_serverField];

	_usernameField = [[NSTextField alloc] initWithFrame:NSMakeRect(115, 204, 285, 22)];
	NSString *savedUsername = [[NSUserDefaults standardUserDefaults]
		stringForKey:@"Username"];
	if ([savedUsername length] > 0) {
		[_usernameField setStringValue:savedUsername];
	}
	[contentView addSubview:[self labelWithTitle:@"Username"
		frame:NSMakeRect(20, 208, 90, 17)]];
	[contentView addSubview:_usernameField];

	_passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(115, 172, 285, 22)];
	[contentView addSubview:[self labelWithTitle:@"Password"
		frame:NSMakeRect(20, 176, 90, 17)]];
	[contentView addSubview:_passwordField];

	_rememberButton = [[NSButton alloc] initWithFrame:NSMakeRect(115, 142, 200, 18)];
	[_rememberButton setButtonType:NSSwitchButton];
	[_rememberButton setTitle:@"Remember me"];
	if ([[NSUserDefaults standardUserDefaults] objectForKey:@"RememberMe"] != nil) {
		[_rememberButton setState:[[NSUserDefaults standardUserDefaults]
			boolForKey:@"RememberMe"] ? NSOnState : NSOffState];
	} else {
		[_rememberButton setState:NSOnState];
	}
	[contentView addSubview:_rememberButton];

	_connectButton = [[NSButton alloc] initWithFrame:NSMakeRect(300, 96, 100, 26)];
	[_connectButton setButtonType:NSMomentaryLightButton];
	[_connectButton setBezelStyle:NSRoundedBezelStyle];
	[_connectButton setTitle:@"Connect"];
	[_connectButton setTarget:self];
	[_connectButton setAction:@selector(connect:)];
	[_connectButton setKeyEquivalent:@"\r"];
	[contentView addSubview:_connectButton];

	_statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 24, 380, 16)];
	[_statusLabel setEditable:NO];
	[_statusLabel setSelectable:NO];
	[_statusLabel setBezeled:NO];
	[_statusLabel setDrawsBackground:NO];
	[_statusLabel setTextColor:[NSColor colorWithCalibratedWhite:0.30 alpha:1.0]];
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

- (IBAction)connect:(id)sender
{
	NSString *serverText = [[_serverField stringValue]
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