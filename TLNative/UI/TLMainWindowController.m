/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLMainWindowController.h"

#import "TLoungeSession.h"
#import "TLServerState.h"
#import "TLNetwork.h"
#import "TLChannel.h"
#import "TLMessage.h"
#import "TLUser.h"

@implementation TLMainWindowController

- (instancetype)initWithSession:(TLoungeSession *)session
{
	NSRect contentRect = NSMakeRect(0, 0, 900, 560);
	NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
		styleMask:(NSTitledWindowMask | NSClosableWindowMask |
			NSMiniaturizableWindowMask | NSResizableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	NSString *savedFrame = [[NSUserDefaults standardUserDefaults]
		stringForKey:@"TLMainWindowFrame"];
	if ([savedFrame length] > 0) {
		// Restore the last-used frame before the window is ordered front.
		[window setFrame:NSRectFromString(savedFrame) display:NO];
	}
	[window setReleasedWhenClosed:NO];
	[window setDelegate:self];

	self = [super initWithWindow:window];
	[window release];
	if (self) {
	_session = [session retain];
	_selectedChannelId = 0;
	_loadingHistory = NO;
	[self buildInterfaceForWindow:window];
	// The outline reads directly from the session state; the same
	// TLServerState object is mutated in place across reconnects.
	[_networkOutline setServerState:_session.serverState];
	[self registerForNotifications];
	[_statusLabel setStringValue:TLConnectionStateDisplayString(_session.state)];
	[self setWindowTitle];
	// The network-list notification usually fired while only the login
	// window existed, so populate from current state right away.
	[_networkOutline reloadData];
	[self ensureSelectedChannelPopulated];
	}
	return self;
}

- (void)buildInterfaceForWindow:(NSWindow *)window
{
	NSView *contentView = [window contentView];
	NSRect contentBounds = [contentView bounds];
	const CGFloat barHeight = 34.0;

	_splitView = [[NSSplitView alloc] initWithFrame:
		NSMakeRect(0, barHeight, NSWidth(contentBounds), NSHeight(contentBounds) - barHeight)];
	[_splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[_splitView setVertical:YES];
	[_splitView setDelegate:self];

	CGFloat divider = [_splitView dividerThickness];
	CGFloat splitHeight = NSHeight([_splitView frame]);

	_networkOutline = [[TLNetworkOutlineView alloc] initWithFrame:
		NSMakeRect(0, 0, 190, splitHeight)];
	[_networkOutline setAutoresizingMask:NSViewHeightSizable];
	[_networkOutline setDelegate:self];

	_messageView = [[TLMessageView alloc] initWithFrame:
		NSMakeRect(0, 0, NSWidth(contentBounds) - 190 - 150 - 2.0 * divider, splitHeight)];
	[_messageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[_messageView setDelegate:self];

	_userListView = [[TLUserListView alloc] initWithFrame:
		NSMakeRect(0, 0, 150, splitHeight)];
	[_userListView setAutoresizingMask:NSViewHeightSizable];

	[_splitView addSubview:_networkOutline];
	[_splitView addSubview:_messageView];
	[_splitView addSubview:_userListView];
	[contentView addSubview:_splitView];

	NSView *bar = [[NSView alloc] initWithFrame:
		NSMakeRect(0, 0, NSWidth(contentBounds), barHeight)];
	[bar setAutoresizingMask:NSViewWidthSizable];

	_statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 9, 130, 16)];
	[_statusLabel setEditable:NO];
	[_statusLabel setSelectable:NO];
	[_statusLabel setBezeled:NO];
	[_statusLabel setDrawsBackground:NO];
	[_statusLabel setAutoresizingMask:NSViewMaxYMargin];
	[bar addSubview:_statusLabel];

	_inputField = [[NSTextField alloc] initWithFrame:
		NSMakeRect(150, 5, NSWidth(contentBounds) - 150 - 70, 24)];
	[_inputField setTarget:self];
	[_inputField setAction:@selector(sendInput:)];
	[_inputField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
	[bar addSubview:_inputField];

	_sendButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(NSWidth(contentBounds) - 64, 4, 60, 26)];
	[_sendButton setTitle:@"Send"];
	[_sendButton setButtonType:NSMomentaryLightButton];
	[_sendButton setBezelStyle:NSRoundedBezelStyle];
	[_sendButton setTarget:self];
	[_sendButton setAction:@selector(sendInput:)];
	[_sendButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	[bar addSubview:_sendButton];

	[contentView addSubview:bar];
	[bar release];
}

- (void)registerForNotifications
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(protocolNetworkListDidChange:)
		name:TLLoungeNetworkListDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolChannelDidChange:)
		name:TLLoungeChannelDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolMessagesDidChange:)
		name:TLLoungeMessagesDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolUserListDidChange:)
		name:TLLoungeUserListDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolHistoryDidChange:)
		name:TLLoungeHistoryDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(sessionStateDidChange:)
		name:TLLoungeSessionStateDidChangeNotification object:_session];
}

- (TLoungeSession *)session
{
	return _session;
}

- (void)setSelectedChannelId:(NSInteger)selectedChannelId
{
	_selectedChannelId = selectedChannelId;
}

- (NSInteger)selectedChannelId
{
	return _selectedChannelId;
}

#pragma mark - Channel selection

- (void)selectChannelId:(NSInteger)channelId
{
	TLChannel *channel = [_session.serverState channelWithIdentifier:channelId];
	if (!channel) {
		return;
	}
	_selectedChannelId = channelId;
	_loadingHistory = NO;
	[_networkOutline setSelectedChannelId:channelId];
	[_networkOutline selectChannelId:channelId];
	[_session openChannelId:channelId];
	if ([channel isChannel] || [channel isQuery]) {
		[_session requestNamesForChannelId:channelId];
	}
	[self populateViewsForChannel:channel];
	[self setWindowTitle];
}

- (void)populateViewsForChannel:(TLChannel *)channel
{
	[_messageView setChannelId:channel.identifier];
	[_messageView clear];
	for (TLMessage *message in channel.messages) {
		[_messageView appendMessage:message];
	}
	[self updateHasMoreHistoryForChannelId:channel.identifier];
	[_messageView scrollToBottom];
	[_userListView reloadWithChannel:channel];
}

- (void)updateHasMoreHistoryForChannelId:(NSInteger)channelId
{
	if (channelId != _selectedChannelId) {
		return;
	}
	TLChannel *channel = [_session.serverState channelWithIdentifier:channelId];
	BOOL more = (channel &&
		channel.totalMessages > (NSInteger)[channel.messages count]);
	[_messageView setHasMoreHistory:more];
}

- (TLChannel *)defaultChannelInServerState:(TLServerState *)serverState
{
	for (TLNetwork *network in serverState.networks) {
		TLChannel *lobby = [network lobby];
		if (lobby) {
			return lobby;
		}
		for (TLChannel *channel in network.channels) {
			if (channel.state == TLChannelStateJoined) {
				return channel;
			}
		}
	}
	return nil;
}

#pragma mark - Protocol notifications

- (void)protocolNetworkListDidChange:(NSNotification *)notification
{
	[_networkOutline reloadData];
	[self ensureSelectedChannelPopulated];
	[self setWindowTitle];
}

- (void)protocolChannelDidChange:(NSNotification *)notification
{
	[_networkOutline reloadData];
	[self ensureSelectedChannelPopulated];
	[self setWindowTitle];
}

- (void)protocolMessagesDidChange:(NSNotification *)notification
{
	NSInteger channelId = [notification.userInfo[@"channelId"] integerValue];
	TLMessage *message = notification.userInfo[@"message"];
	[_networkOutline reloadData];
	if (_selectedChannelId == channelId) {
		if (message) {
			[_messageView appendMessage:message];
		}
		[self updateHasMoreHistoryForChannelId:channelId];
	}
	[self setWindowTitle];
}

- (void)protocolHistoryDidChange:(NSNotification *)notification
{
	NSInteger channelId = [notification.userInfo[@"channelId"] integerValue];
	_loadingHistory = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetHistoryLoadingFlag) object:nil];
	[_networkOutline reloadData];
	if (_selectedChannelId == channelId) {
		TLChannel *channel = [_session.serverState channelWithIdentifier:channelId];
		if (channel) {
			[_messageView prependMessages:channel.messages];
		}
		[self updateHasMoreHistoryForChannelId:channelId];
	}
	[self setWindowTitle];
}

- (void)protocolUserListDidChange:(NSNotification *)notification
{
	NSInteger channelId = [notification.userInfo[@"channelId"] integerValue];
	if (_selectedChannelId != channelId) {
		return;
	}
	TLChannel *channel = [_session.serverState channelWithIdentifier:channelId];
	if (channel) {
		[_userListView reloadWithChannel:channel];
	}
}

- (void)sessionStateDidChange:(NSNotification *)notification
{
	if (notification.object != _session) {
		return;
	}
	[_statusLabel setStringValue:TLConnectionStateDisplayString(_session.state)];
}

- (void)ensureSelectedChannelPopulated
{
	TLServerState *serverState = _session.serverState;
	TLChannel *channel = nil;
	if (_selectedChannelId > 0) {
		channel = [serverState channelWithIdentifier:_selectedChannelId];
	}
	if (!channel) {
		channel = [self defaultChannelInServerState:serverState];
	}
	if (!channel) {
		return;
	}
	if (_selectedChannelId == channel.identifier && _messageView.channelId == channel.identifier) {
		return;
	}
	[self selectChannelId:channel.identifier];
}

#pragma mark - Sending

- (IBAction)sendInput:(id)sender
{
	if (_selectedChannelId <= 0) {
		return;
	}
	NSString *text = [[_inputField stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([text length] == 0) {
		return;
	}
	// The Lounge expects commands with the leading slash intact; the session
	// layer forwards the raw line to the bouncer which does the parsing.
	if ([text hasPrefix:@"/"]) {
		[_session sendCommand:text toChannelId:_selectedChannelId];
	} else {
		[_session sendMessage:text toChannelId:_selectedChannelId];
	}
	[_inputField setStringValue:@""];
}

#pragma mark - Window title

- (void)setWindowTitle
{
	NSString *title = [self serverHostname];
	TLChannel *channel = nil;
	if (_selectedChannelId > 0) {
		channel = [_session.serverState channelWithIdentifier:_selectedChannelId];
	}
	if (channel && [channel.name length] > 0) {
		title = [title stringByAppendingFormat:@" - %@", channel.name];
	}
	[[self window] setTitle:title];
}

- (NSString *)serverHostname
{
	NSURL *url = [NSURL URLWithString:_session.serverURLString];
	NSString *host = [url host];
	if ([host length] == 0) {
		return _session.serverURLString;
	}
	return host;
}

#pragma mark - History loading

- (void)messageViewDidScrollToTop:(TLMessageView *)messageView
{
	if (_loadingHistory) {
		return;
	}
	TLChannel *channel = [_session.serverState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	if (channel.totalMessages <= (NSInteger)[channel.messages count]) {
		[_messageView setHasMoreHistory:NO];
		return;
	}
	TLMessage *firstMessage = [channel.messages firstObject];
	if (!firstMessage) {
		return;
	}
	_loadingHistory = YES;
	// Guard against a lost "more" response leaving the flag stuck on.
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetHistoryLoadingFlag) object:nil];
	[self performSelector:@selector(resetHistoryLoadingFlag) withObject:nil afterDelay:10.0];
	[_session loadMoreHistoryForChannelId:channel.identifier lastId:firstMessage.identifier];
}

- (void)resetHistoryLoadingFlag
{
	_loadingHistory = NO;
}

#pragma mark - TLNetworkOutlineViewDelegate

- (void)networkOutlineView:(TLNetworkOutlineView *)outline didSelectChannelId:(NSInteger)channelId
{
	[self selectChannelId:channelId];
}

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin
	ofSubviewAt:(NSInteger)dividerIndex
{
	if (dividerIndex == 0) {
		return 150.0;
	}
	return proposedMin;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax
	ofSubviewAt:(NSInteger)dividerIndex
{
	if (dividerIndex == 1) {
		return NSWidth([splitView bounds]) - 120.0;
	}
	return proposedMax;
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(id)sender
{
	[NSApp terminate:self];
	return YES;
}

- (void)windowDidMove:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults]
		setObject:NSStringFromRect([[self window] frame])
		forKey:@"TLMainWindowFrame"];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults]
		setObject:NSStringFromRect([[self window] frame])
		forKey:@"TLMainWindowFrame"];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[_session release];
	[_splitView release];
	[_networkOutline release];
	[_messageView release];
	[_userListView release];
	[_inputField release];
	[_sendButton release];
	[_statusLabel release];
	[super dealloc];
}

@end