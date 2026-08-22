/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLApplicationDelegate.h"

#import "TLoungeSession.h"
#import "TLMainWindowController.h"

@interface TLApplicationDelegate ()
{
	TLoungeSession *_session;
	TLLoginController *_loginController;
	TLMainWindowController *_mainWindowController;
}
- (void)showAlertWithTitle:(NSString *)title detail:(NSString *)detail hint:(NSString *)hint;
@end

@implementation TLApplicationDelegate

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_session release];
	[_loginController release];
	[_mainWindowController release];
	[super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	[self buildMainMenu];
	[self showLoginWindow];
}

- (void)buildMainMenu
{
	NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

	// Application menu: the first submenu is treated as the app menu.
	NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"The Lounge"
		action:NULL keyEquivalent:@""];
	NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"The Lounge"];
	[appMenu addItemWithTitle:@"About The Lounge"
		action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Hide The Lounge"
		action:@selector(hide:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:@"Hide Others"
		action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:@"Show All"
		action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Quit The Lounge"
		action:@selector(terminate:) keyEquivalent:@"q"];
	[appItem setSubmenu:appMenu];
	[mainMenu addItem:appItem];
	[NSApp setAppleMenu:appMenu];
	[appMenu release];
	[appItem release];

	NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File"
		action:NULL keyEquivalent:@""];
	NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
	[fileMenu addItemWithTitle:@"Close Window"
		action:@selector(performClose:) keyEquivalent:@"w"];
	[fileItem setSubmenu:fileMenu];
	[mainMenu addItem:fileItem];
	[fileMenu release];
	[fileItem release];

	NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
		action:NULL keyEquivalent:@""];
	NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
	[editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
	[editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
	[editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
	[editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
	[editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
	[editItem setSubmenu:editMenu];
	[mainMenu addItem:editItem];
	[editMenu release];
	[editItem release];

	// The empty View menu only confuses; drop it.
	// Window menu keeps Minimize/Zoom and doubles as the windows list.

	NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window"
		action:NULL keyEquivalent:@""];
	NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
	[windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:)
		keyEquivalent:@"m"];
	[windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
	[windowMenu addItem:[NSMenuItem separatorItem]];
	[windowMenu addItemWithTitle:@"Bring All to Front"
		action:@selector(arrangeInFront:) keyEquivalent:@""];
	[windowItem setSubmenu:windowMenu];
	[mainMenu addItem:windowItem];
	[NSApp setWindowsMenu:windowMenu];
	[windowMenu release];
	[windowItem release];

	[NSApp setMainMenu:mainMenu];
	[mainMenu release];
}

- (void)showLoginWindow
{
	if (!_loginController) {
		_loginController = [[TLLoginController alloc] init];
		_loginController.delegate = self;
	}
	[_loginController prepareForRetry];
	[_loginController showWindow:self];
	[[_loginController window] makeKeyAndOrderFront:self];
	[NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - TLLoginControllerDelegate

- (void)loginController:(TLLoginController *)controller
	didSubmitServerURL:(NSURL *)serverURL
	username:(NSString *)username
	password:(NSString *)password
	remember:(BOOL)remember
{
	[_session release];
	_session = [[TLoungeSession alloc] initWithServerURL:serverURL username:username];

	NSString *storedToken = [_session retrieveStoredToken];
	if ([storedToken length] > 0) {
		[_session setSessionToken:storedToken];
	} else {
		[_session setPassword:password];
		[_session setRemember:remember];
	}

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(sessionStateDidChange:)
		name:TLLoungeSessionStateDidChangeNotification object:_session];
	[center addObserver:self selector:@selector(sessionDidBecomeReady:)
		name:TLLoungeSessionDidBecomeReadyNotification object:_session];
	[center addObserver:self selector:@selector(sessionDidFailWithError:)
		name:TLLoungeSessionErrorNotification object:_session];

	[controller setStatusText:@"Connecting..."];
	[_session connect];
}

#pragma mark - Session notifications

- (void)sessionDidBecomeReady:(NSNotification *)notification
{
	if (notification.object != _session) {
		return;
	}
	[self showMainInterface];
}

- (void)sessionStateDidChange:(NSNotification *)notification
{
	if (notification.object != _session) {
		return;
	}
	if (_session.state == TLConnectionStateReady) {
		[self showMainInterface];
	}
}

- (void)sessionDidFailWithError:(NSNotification *)notification
{
	if (notification.object != _session) {
		return;
	}
	NSError *error = notification.userInfo[@"error"];
	NSString *message = [error localizedDescription];
	if ([message length] == 0) {
		message = @"The connection to the server failed.";
	}

	if ([notification.userInfo[@"recoverable"] boolValue]) {
		// The session reconnects on its own; keep the chat window up and
		// only inform the user about the drop.
		[self showAlertWithTitle:@"Connection Lost"
			detail:message
			hint:@"The Lounge will keep trying to reconnect in the background."];
		return;
	}

	NSString *title = @"Connection Failed";
	NSString *hint = @"Check the server URL and your network connection, then try again.";
	switch ([_session state]) {
		case TLConnectionStateAuthenticationFailed:
			title = @"Authentication Failed";
			hint = @"Check your username and password, then try again.";
			break;
		case TLConnectionStateProtocolError:
			title = @"Protocol Error";
			hint = @"The server sent an unexpected response. It may be running "
				"an incompatible The Lounge version.";
			break;
		default:
			break;
	}
	[self showAlertWithTitle:title detail:message hint:hint];
	[self tearDownMainInterface];
	[self showLoginWindow];
}

- (void)showAlertWithTitle:(NSString *)title detail:(NSString *)detail hint:(NSString *)hint
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSCriticalAlertStyle];
	[alert setMessageText:title];
	NSString *text = detail;
	if ([hint length] > 0) {
		text = [NSString stringWithFormat:@"%@\n\n%@", detail, hint];
	}
	[alert setInformativeText:text];
	[alert addButtonWithTitle:@"OK"];
	[alert runModal];
	[alert release];
}

// The desktop environment terminates applications when their last window
// closes; this application manages its own window lifecycle instead.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return NO;
}

- (void)showMainInterface
{
	if (_mainWindowController) {
		return;
	}
	_mainWindowController = [[TLMainWindowController alloc] initWithSession:_session];
	[_mainWindowController showWindow:self];
	[NSApp activateIgnoringOtherApps:YES];

	// Close the login window only after the main window is on screen;
	// closing it first would make this the last-window-closed moment.
	[_loginController close];
	[_loginController release];
	_loginController = nil;
}

- (void)tearDownMainInterface
{
	if (!_mainWindowController) {
		return;
	}
	[[_mainWindowController window] close];
	[_mainWindowController release];
	_mainWindowController = nil;
}

- (void)showAlertWithMessage:(NSString *)message
{
	NSAlert *alert = [NSAlert alertWithMessageText:@"The Lounge"
		defaultButton:@"OK" alternateButton:nil otherButton:nil
		informativeTextWithFormat:@"%@", message];
	[alert runModal];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[_session disconnect];
}

- (TLoungeSession *)session
{
	return _session;
}

@end