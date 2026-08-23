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
#import "TLPreferences.h"

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
	[_userListView setDelegate:self];

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
	[center addObserver:self selector:@selector(bubbleStyleDidChange:)
		name:TLBubbleStyleDidChangeNotification object:nil];
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
	_autoHistoryBatches = 0;
	[_selectedUserNick release];
	_selectedUserNick = nil;
	// Remember the open tab for the next visit to this server.
	TLPreferencesSetLastChannelId(channelId, channel.name,
	    _session.serverURLString);
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
	// The bouncer replays only messages newer than what this client last
	// saw, so a quiet channel can start out shorter than the viewport -
	// too short to ever reach the top by scrolling. Fetch older batches
	// until the transcript is scrollable.
	[self autoFillHistoryIfShortTranscript];
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

// The tab that was open on this server last time, matched by identifier
// first and by name second; identifiers are server-assigned and can change.
- (TLChannel *)storedChannelInServerState:(TLServerState *)serverState
{
	NSDictionary *saved =
	    TLPreferencesLastChannelForServer(_session.serverURLString);
	if (saved == nil) {
		return nil;
	}
	NSInteger storedId = [saved[@"id"] integerValue];
	NSString *name = saved[@"name"];
	if (storedId > 0) {
		TLChannel *byId = [serverState channelWithIdentifier:storedId];
		if (byId) {
			return byId;
		}
	}
	if ([name length] > 0) {
		for (TLNetwork *network in serverState.networks) {
			TLChannel *lobby = [network lobby];
			if ([lobby.name isEqualToString:name]) {
				return lobby;
			}
			for (TLChannel *channel in network.channels) {
				if ([channel.name isEqualToString:name]) {
					return channel;
				}
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
		// A batch may still have left the transcript shorter than the
		// viewport; keep going until scrolling becomes possible.
		[self autoFillHistoryIfShortTranscript];
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

// Rebuilds the transcript in the newly selected style; the current channel
// is repopulated from server state, so nothing is lost.
- (void)bubbleStyleDidChange:(NSNotification *)notification
{
	BOOL bubbles = TLPreferencesUseBubbles();
	if ([_messageView usesBubbles] == bubbles) {
		return;
	}
	[_messageView setUsesBubbles:bubbles];
	TLChannel *channel =
		[_session.serverState channelWithIdentifier:_selectedChannelId];
	if (channel) {
		[self populateViewsForChannel:channel];
	}
}

- (void)ensureSelectedChannelPopulated
{
	TLServerState *serverState = _session.serverState;
	TLChannel *channel = nil;
	if (_selectedChannelId > 0) {
		channel = [serverState channelWithIdentifier:_selectedChannelId];
	}
	// The stored tab is only consulted until the first successful
	// selection; afterwards the user drives.
	if (!channel && !_attemptedStoredChannelRestore) {
		_attemptedStoredChannelRestore = YES;
		channel = [self storedChannelInServerState:serverState];
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
	[self requestOlderHistoryForSelectedChannel];
}

// Asks the bouncer for one batch of messages older than the oldest one we
// hold. Single-flight via _loadingHistory; a lost response clears the flag
// after 10 seconds.
- (void)requestOlderHistoryForSelectedChannel
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

// Keeps requesting older batches while the transcript is too short to be
// scrollable; otherwise reaching the top - and with it history loading -
// would be impossible.
- (void)autoFillHistoryIfShortTranscript
{
	if (!_messageView.hasMoreHistory || [_messageView contentFillsViewport]) {
		return;
	}
	// Hard cap so a misbehaving server cannot keep us fetching forever.
	if (_autoHistoryBatches >= 10) {
		return;
	}
	if (_loadingHistory) {
		return;
	}
	_autoHistoryBatches++;
	[self requestOlderHistoryForSelectedChannel];
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

- (NSMenu *)networkOutlineView:(TLNetworkOutlineView *)outline contextMenuForRowItem:(id)item
{
	TLNetwork *network = nil;
	TLChannel *channel = nil;
	if ([item isKindOfClass:[TLNetwork class]]) {
		network = item;
		channel = [network lobby];
	} else if ([item isKindOfClass:[TLChannel class]]) {
		channel = item;
		network = [_session.serverState networkContainingChannel:channel.identifier];
	}
	if (!channel || !network) {
		return nil;
	}
	NSString *myNick = _session.serverState.currentUserNick ?: network.nick;
	return [TLContextMenuBuilder channelMenuForChannel:channel
		network:network myNick:myNick delegate:self];
}

#pragma mark - TLUserListViewDelegate

- (void)userListView:(TLUserListView *)view didSelectRow:(NSInteger)row
{
	[_selectedUserNick release];
	_selectedUserNick = nil;
	if (row < 0) {
		return;
	}
	TLChannel *channel = [_session.serverState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	NSArray *users = [channel sortedUsers];
	if (row >= (NSInteger)[users count]) {
		return;
	}
	_selectedUserNick = [[[users objectAtIndex:(NSUInteger)row] nick] copy];
}

- (void)messageView:(TLMessageView *)messageView didSelectSenderNick:(NSString *)nick
{
	// Clicking a speaker picture behaves like clicking that user's row:
	// the selection change keeps every Chat-menu action in sync.
	[_userListView selectUserWithNick:nick];
}

- (NSMenu *)userListView:(TLUserListView *)view contextMenuForRow:(NSInteger)row
{
	TLChannel *channel = [_session.serverState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return nil;
	}
	NSArray *users = [channel sortedUsers];
	if (row < 0 || row >= (NSInteger)[users count]) {
		return nil;
	}
	TLNetwork *network = [_session.serverState networkContainingChannel:channel.identifier];
	if (!network) {
		return nil;
	}
	NSString *myNick = _session.serverState.currentUserNick ?: network.nick;
	return [TLContextMenuBuilder userMenuForUser:[users objectAtIndex:(NSUInteger)row]
		channel:channel network:network myNick:myNick delegate:self];
}

#pragma mark - TLContextMenuActionDelegate

- (void)contextMenuSwitchToChannelId:(NSInteger)channelId
{
	[self selectChannelId:channelId];
}

- (void)contextMenuRunCommand:(NSString *)command onChannelId:(NSInteger)channelId
{
	[_session sendCommand:command toChannelId:channelId];
}

- (void)contextMenuSetMuted:(BOOL)muted forChannelId:(NSInteger)channelId
{
	[_session setMuted:muted forChannelId:channelId];
}

- (void)contextMenuClearHistoryForChannelId:(NSInteger)channelId
{
	TLChannel *channel = [_session.serverState channelWithIdentifier:channelId];
	NSString *name = channel.name ?: @"this channel";
	if (![self confirmTitled:@"Clear history"
		message:[NSString stringWithFormat:
			@"Are you sure you want to clear history for %@? This cannot be undone.",
			name]
		button:@"Clear history"]) {
		return;
	}
	[_session clearHistoryForChannelId:channelId];
}

- (void)contextMenuCloseChannelId:(NSInteger)channelId isLobby:(BOOL)isLobby
{
	if (isLobby) {
		TLNetwork *network = [_session.serverState networkContainingChannel:channelId];
		NSString *name = network.name ?: @"the network";
		if (![self confirmTitled:@"Remove network"
			message:[NSString stringWithFormat:
				@"Are you sure you want to quit and remove %@? This cannot be undone.",
				name]
			button:@"Remove network"]) {
			return;
		}
		[_session sendCommand:@"/quit" toChannelId:channelId];
		return;
	}
	// The server-side /close parts channels and closes queries.
	[_session sendCommand:@"/close" toChannelId:channelId];
}

- (void)contextMenuJoinPromptForLobbyId:(NSInteger)lobbyId
{
	NSString *name = [self runTextPromptTitled:@"Join a channel"
		label:@"Channel name:" defaultValue:@""];
	name = [name stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([name length] == 0) {
		return;
	}
	// The web client also accepts bare names; pass through unchanged and let
	// the bouncer normalize the target.
	[_session sendCommand:[@"/join " stringByAppendingString:name]
		toChannelId:lobbyId];
}

- (void)contextMenuEditTopicForChannelId:(NSInteger)channelId
{
	TLChannel *channel = [_session.serverState channelWithIdentifier:channelId];
	if (!channel) {
		return;
	}
	NSString *topic = [self runTextPromptTitled:@"Edit topic"
		label:[NSString stringWithFormat:@"Topic for %@:", channel.name]
		defaultValue:channel.topic ?: @""];
	topic = [topic stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([topic length] == 0) {
		return;
	}
	[_session sendCommand:[NSString stringWithFormat:@"/topic %@", topic]
		toChannelId:channelId];
}

#pragma mark - Context menu prompts

- (BOOL)confirmTitled:(NSString *)title message:(NSString *)message
	button:(NSString *)button
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:title];
	[alert setInformativeText:message];
	[alert addButtonWithTitle:button];
	[alert addButtonWithTitle:@"Cancel"];
	NSInteger result = [alert runModal];
	[alert release];
	return result == NSAlertFirstButtonReturn;
}

- (void)textPromptConfirmed:(id)sender
{
	[NSApp stopModalWithCode:1];
}

- (void)textPromptCancelled:(id)sender
{
	[NSApp stopModalWithCode:0];
}

- (NSString *)runTextPromptTitled:(NSString *)title
	label:(NSString *)label
	defaultValue:(NSString *)defaultValue
{
	// GNUstep's NSAlert has no accessory views, so text prompts get their
	// own small modal panel.
	NSWindow *panel = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(0, 0, 320, 120)
		styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	[panel setTitle:title];
	[panel setReleasedWhenClosed:NO];
	[panel center];

	NSView *content = [panel contentView];
	NSRect bounds = [content bounds];

	BOOL hasLabel = [label length] > 0;
	CGFloat inputY = hasLabel ? NSHeight(bounds) - 68 : NSHeight(bounds) - 40;

	if (hasLabel) {
		NSTextField *labelField = [[NSTextField alloc] initWithFrame:
			NSMakeRect(16, NSHeight(bounds) - 36, NSWidth(bounds) - 32, 18)];
		[labelField setEditable:NO];
		[labelField setSelectable:NO];
		[labelField setBordered:NO];
		[labelField setBezeled:NO];
		[labelField setDrawsBackground:NO];
		[labelField setStringValue:label];
		[content addSubview:labelField];
		[labelField release];
	}

	NSTextField *input = [[NSTextField alloc] initWithFrame:
		NSMakeRect(16, inputY, NSWidth(bounds) - 32, 24)];
	[input setStringValue:defaultValue ?: @""];
	[input setTarget:self];
	[input setAction:@selector(textPromptConfirmed:)];
	[content addSubview:input];

	NSButton *cancelButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(NSWidth(bounds) - 140, 14, 60, 26)];
	[cancelButton setTitle:@"Cancel"];
	[cancelButton setButtonType:NSMomentaryLightButton];
	[cancelButton setBezelStyle:NSRoundedBezelStyle];
	[cancelButton setTarget:self];
	[cancelButton setAction:@selector(textPromptCancelled:)];
	[content addSubview:cancelButton];
	[cancelButton release];

	NSButton *okButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(NSWidth(bounds) - 74, 14, 58, 26)];
	[okButton setTitle:@"OK"];
	[okButton setButtonType:NSMomentaryLightButton];
	[okButton setBezelStyle:NSRoundedBezelStyle];
	[okButton setKeyEquivalent:@"\r"];
	[okButton setTarget:self];
	[okButton setAction:@selector(textPromptConfirmed:)];
	[content addSubview:okButton];
	[okButton release];

	[[self window] addChildWindow:panel ordered:NSWindowAbove];
	[panel makeKeyAndOrderFront:nil];
	[panel makeFirstResponder:input];
	NSString *value = nil;
	if ([NSApp runModalForWindow:panel] == 1) {
		value = [[input stringValue] retain];
	}
	[[self window] removeChildWindow:panel];
	[panel orderOut:nil];
	[panel release];
	return [value autorelease];
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

#pragma mark - Chat main-menu actions

// The channel whose network-scoped commands apply: the selected channel's
// lobby.  Falls back to the first network when nothing is selected.
- (TLNetwork *)currentChatNetwork
{
	if (_selectedChannelId > 0) {
		return [_session.serverState networkContainingChannel:_selectedChannelId];
	}
	TLServerState *state = _session.serverState;
	return [state.networks count] > 0 ? [state.networks objectAtIndex:0] : nil;
}

- (TLChannel *)currentChatChannel
{
	return _selectedChannelId > 0
		? [_session.serverState channelWithIdentifier:_selectedChannelId]
		: nil;
}

- (TLUser *)selectedChatUserInChannel:(TLChannel *)channel
{
	if (!_selectedUserNick) {
		return nil;
	}
	return [channel userWithNick:_selectedUserNick];
}

- (void)chatToggleConnection:(id)sender
{
	TLNetwork *network = [self currentChatNetwork];
	if (!network) {
		return;
	}
	NSString *command = network.connected ? @"/disconnect" : @"/connect";
	[_session sendCommand:command toChannelId:[[network lobby] identifier]];
}

- (void)chatRemoveNetwork:(id)sender
{
	TLNetwork *network = [self currentChatNetwork];
	if (network) {
		[self contextMenuCloseChannelId:[[network lobby] identifier] isLobby:YES];
	}
}

- (void)chatJoinChannel:(id)sender
{
	TLNetwork *network = [self currentChatNetwork];
	if (network) {
		[self contextMenuJoinPromptForLobbyId:[[network lobby] identifier]];
	}
}

- (void)chatListChannels:(id)sender
{
	TLNetwork *network = [self currentChatNetwork];
	if (network) {
		[self contextMenuRunCommand:@"/list"
			onChannelId:[[network lobby] identifier]];
	}
}

- (void)chatListIgnoredUsers:(id)sender
{
	TLNetwork *network = [self currentChatNetwork];
	if (network) {
		[self contextMenuRunCommand:@"/ignorelist"
			onChannelId:[[network lobby] identifier]];
	}
}

- (void)chatListBannedUsers:(id)sender
{
	TLChannel *channel = [self currentChatChannel];
	if ([channel isChannel]) {
		[self contextMenuRunCommand:@"/banlist" onChannelId:channel.identifier];
	}
}

- (void)chatEditTopic:(id)sender
{
	TLChannel *channel = [self currentChatChannel];
	if ([channel isChannel]) {
		[self contextMenuEditTopicForChannelId:channel.identifier];
	}
}

- (void)chatClearHistory:(id)sender
{
	TLChannel *channel = [self currentChatChannel];
	if (channel) {
		[self contextMenuClearHistoryForChannelId:channel.identifier];
	}
}

- (void)chatToggleMuted:(id)sender
{
	TLChannel *channel = [self currentChatChannel];
	if (channel && channel.type != TLChannelTypeSpecial) {
		[self contextMenuSetMuted:!channel.muted forChannelId:channel.identifier];
	}
}

- (void)chatCloseCurrent:(id)sender
{
	TLChannel *channel = [self currentChatChannel];
	if (channel) {
		[self contextMenuCloseChannelId:channel.identifier
			isLobby:(channel.type == TLChannelTypeLobby)];
	}
}

- (NSString *)commandForSelectedUser:(NSString *)verb
{
	TLChannel *channel = [self currentChatChannel];
	if (!channel || !_selectedUserNick) {
		return nil;
	}
	return [NSString stringWithFormat:@"/%@ %@", verb, _selectedUserNick];
}

- (void)chatWhoisSelectedUser:(id)sender
{
	NSString *command = [self commandForSelectedUser:@"whois"];
	if (command) {
		[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
	}
}

- (void)chatIgnoreSelectedUser:(id)sender
{
	NSString *command = [self commandForSelectedUser:@"ignore"];
	if (command) {
		[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
	}
}

- (void)chatQuerySelectedUser:(id)sender
{
	NSString *command = [self commandForSelectedUser:@"query"];
	if (command) {
		[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
	}
}

- (void)chatKickSelectedUser:(id)sender
{
	NSString *command = [self commandForSelectedUser:@"kick"];
	if (command) {
		[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
	}
}

- (void)chatSetMode:(NSMenuItem *)sender
{
	NSDictionary *spec = [sender representedObject];
	NSString *command = [NSString stringWithFormat:@"/mode %@%@ %@",
		[spec[@"give"] boolValue] ? @"+" : @"-",
		spec[@"mode"], _selectedUserNick];
	[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	SEL action = [menuItem action];
	TLChannel *channel = [self currentChatChannel];
	TLNetwork *network = [self currentChatNetwork];

	if (action == @selector(chatToggleConnection:)) {
		[menuItem setTitle:network.connected ? @"Disconnect" : @"Connect"];
		return network != nil;
	}
	if (action == @selector(chatRemoveNetwork:) ||
		action == @selector(chatJoinChannel:) ||
		action == @selector(chatListChannels:) ||
		action == @selector(chatListIgnoredUsers:)) {
		return network != nil;
	}
	if (action == @selector(chatListBannedUsers:) ||
		action == @selector(chatEditTopic:)) {
		return [channel isChannel];
	}
	if (action == @selector(chatClearHistory:)) {
		return channel != nil &&
			([channel isChannel] || [channel isQuery]);
	}
	if (action == @selector(chatToggleMuted:)) {
		if (!channel || channel.type == TLChannelTypeSpecial) {
			return NO;
		}
		NSString *type = [TLContextMenuBuilder humanTypeNameForChannel:channel];
		[menuItem setTitle:[NSString stringWithFormat:
			channel.muted ? @"Unmute %@" : @"Mute %@", type]];
		return YES;
	}
	if (action == @selector(chatCloseCurrent:)) {
		if (!channel) {
			return NO;
		}
		switch (channel.type) {
		case TLChannelTypeChannel:
			[menuItem setTitle:@"Leave"];
			break;
		case TLChannelTypeLobby:
			[menuItem setTitle:@"Leave Network"];
			break;
		default:
			[menuItem setTitle:@"Close"];
			break;
		}
		return YES;
	}

	BOOL userAction = (action == @selector(chatWhoisSelectedUser:) ||
		action == @selector(chatIgnoreSelectedUser:) ||
		action == @selector(chatQuerySelectedUser:) ||
		action == @selector(chatKickSelectedUser:) ||
		action == @selector(chatSetMode:));
	if (userAction) {
		if (!channel || !_selectedUserNick ||
			[channel userWithNick:_selectedUserNick] == nil) {
			return NO;
		}
		if (action != @selector(chatSetMode:)) {
			[menuItem setTitle:[menuItem.title stringByReplacingOccurrencesOfString:
				@"Selected User" withString:_selectedUserNick]];
		}
	}

	if (action == @selector(chatKickSelectedUser:)) {
		// Same eligibility rule as the context menu: at least half-op (or
		// operator on servers without half-ops), target unranked or below.
		TLUser *me = [channel userWithNick:_session.serverState.currentUserNick
			?: [self currentChatNetwork].nick ?: @""];
		TLUser *target = [self selectedChatUserInChannel:channel];
		if (!me || [me.modes count] == 0 || !target) {
			return NO;
		}
		NSDictionary *prefixOptions =
			[[self currentChatNetwork] serverOptions][@"PREFIX"];
		NSArray *symbols = prefixOptions[@"symbols"];
		NSString *myTop = [me.modes objectAtIndex:0];
		NSString *requirement = [symbols containsObject:@"%"] ? @"%" : @"@";
		BOOL atLeastHalfOp = ![TLContextMenuBuilder mode:requirement
			canActOnMode:myTop inSymbols:symbols];
		BOOL targetBelowUs = ([target.modes count] == 0 ||
			[TLContextMenuBuilder mode:myTop
				canActOnMode:[target.modes objectAtIndex:0]
				inSymbols:symbols]);
		return atLeastHalfOp && targetBelowUs;
	}

	if (action == @selector(chatSetMode:)) {
		TLUser *me = [channel userWithNick:_session.serverState.currentUserNick
			?: [self currentChatNetwork].nick ?: @""];
		TLUser *target = [self selectedChatUserInChannel:channel];
		if (!me || [me.modes count] == 0 || !target) {
			return NO;
		}
		NSDictionary *prefixOptions =
			[[self currentChatNetwork] serverOptions][@"PREFIX"];
		NSArray *symbols = prefixOptions[@"symbols"];
		NSString *myTop = [me.modes objectAtIndex:0];
		NSDictionary *spec = [menuItem representedObject];
		NSString *symbol = spec[@"symbol"];
		BOOL give = [spec[@"give"] boolValue];
		BOOL rankOk = [TLContextMenuBuilder mode:myTop canActOnMode:symbol
			inSymbols:symbols];
		BOOL stateOk = give
			? ![target.modes containsObject:symbol]
			: [target.modes containsObject:symbol];
		return rankOk && stateOk;
	}

	return YES;
}

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