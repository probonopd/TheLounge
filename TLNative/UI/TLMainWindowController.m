/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLMainWindowController.h"

#import "TLInputTextView.h"
#import "TLDockBadge.h"
#import "TLoungeSession.h"
#import "TLServerState.h"
#import "TLNetwork.h"
#import "TLChannel.h"
#import "TLMessage.h"
#import "TLUser.h"
#import "TLPreferences.h"
#import "TLNostermGroupListController.h"
#import "TLApplicationDelegate.h"

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
	_searchResults = [[NSMutableArray alloc] init];
	_dockBadge = [[TLDockBadge alloc] init];
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
	// Open with the cursor already in the message composer so the user can
	// start typing without first clicking the text field.
	[window makeFirstResponder:_inputTextView];
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

	// The message pane stacks a filter box over the transcript so the search
	// field stays pinned to the top of the chat column while the transcript
	// below it resizes with the split.
	_messagePane = [[NSView alloc] initWithFrame:
		NSMakeRect(0, 0, NSWidth(contentBounds) - 190 - 150 - 2.0 * divider, splitHeight)];
	[_messagePane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

	_searchField = [[NSSearchField alloc] initWithFrame:
		NSMakeRect(0, [_messagePane bounds].size.height - 26.0,
			[_messagePane bounds].size.width, 26.0)];
	[_searchField setPlaceholderString:@"Filter messages"];
	[_searchField setTarget:self];
	[_searchField setDelegate:self];
	[_searchField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
	[_messagePane addSubview:_searchField];

	// The transcript fills the pane below the search field; its top is pinned
	// just under the field via the MaxY margin so it never overlaps it.
	[_messageView setFrame:NSMakeRect(0, 0, [_messagePane bounds].size.width,
		[_messagePane bounds].size.height - 26.0)];
	[_messageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable |
		NSViewMaxYMargin];
	[_messagePane addSubview:_messageView];

	[_splitView addSubview:_networkOutline];
	[_splitView addSubview:_messagePane];
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

	// Multi-line composer: Enter sends, Shift-Enter folds a newline into
	// the draft; the bar grows with the text up to a few lines.
	NSScrollView *inputScroll = [[NSScrollView alloc] initWithFrame:
		NSMakeRect(150, 5, NSWidth(contentBounds) - 150 - 70, 24)];
	[inputScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[inputScroll setHasVerticalScroller:NO];
	[inputScroll setBorderType:NSBezelBorder];
	_inputTextView = [[TLInputTextView alloc] initWithFrame:
		NSMakeRect(0, 0, [inputScroll contentSize].width,
		[inputScroll contentSize].height)];
	[_inputTextView setRichText:NO];
	[_inputTextView setDelegate:self];
	[_inputTextView setSendTarget:self action:@selector(sendInput:)];
	[inputScroll setDocumentView:_inputTextView];
	[_inputTextView release];
	[bar addSubview:inputScroll];
	[inputScroll release];

	_sendButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(NSWidth(contentBounds) - 64, 4, 60, 26)];
	[_sendButton setTitle:@"Send"];
	[_sendButton setButtonType:NSMomentaryLightButton];
	[_sendButton setBezelStyle:NSRoundedBezelStyle];
	[_sendButton setTarget:self];
	[_sendButton setAction:@selector(sendInput:)];
	[_sendButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	[bar addSubview:_sendButton];

	_composerBar = [bar retain];
	[contentView addSubview:bar];
	[bar release];
}

// Keeps the composer tall enough to show the whole draft, growing the bar
// (and shrinking the chat area) up to a few visible lines. The input sits
// with 5pt margins inside the bar, so bar height tracks input height.
- (void)updateComposerHeight
{
	NSSize used = [[_inputTextView layoutManager]
	    usedRectForTextContainer:[_inputTextView textContainer]].size;
	const CGFloat minInputHeight = 24.0;
	const CGFloat maxInputHeight = 58.0;
	CGFloat needed = MIN(MAX(ceil(used.height) + 2.0, minInputHeight), maxInputHeight);

	NSRect barFrame = [_composerBar frame];
	CGFloat currentInputHeight = barFrame.size.height - 10.0;
	CGFloat delta = needed - currentInputHeight;
	if (fabs(delta) < 1.0) {
		return;
	}
	barFrame.size.height += delta;
	[_composerBar setFrame:barFrame];

	NSRect splitFrame = [_splitView frame];
	splitFrame.origin.y += delta;
	splitFrame.size.height -= delta;
	[_splitView setFrame:splitFrame];
}

- (void)textDidChange:(NSNotification *)notification
{
	if (notification.object != _inputTextView) {
		return;
	}
	[self updateComposerHeight];
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
	[center addObserver:self selector:@selector(protocolNicknamesDidChange:)
		name:TLLoungeNicknamesDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolHistoryDidChange:)
		name:TLLoungeHistoryDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolSearchResultsDidChange:)
		name:TLLoungeSearchResultsDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(sessionStateDidChange:)
		name:TLLoungeSessionStateDidChangeNotification object:_session];
	[center addObserver:self selector:@selector(bubbleStyleDidChange:)
		name:TLBubbleStyleDidChangeNotification object:nil];
	// Any change that can move the unread totals must refresh the Dock badge.
	[center addObserver:self selector:@selector(updateDockBadge)
		name:TLLoungeNetworkListDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(updateDockBadge)
		name:TLLoungeChannelDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(updateDockBadge)
		name:TLLoungeMessagesDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(updateDockBadge)
		name:TLLoungeHistoryDidChangeNotification object:nil];
}

- (TLoungeSession *)session
{
	return _session;
}

#pragma mark - Dock badge

- (void)clearDockBadge
{
	[_dockBadge clear];
}

// The Dock badge is exactly the sum of the per-channel badges drawn in the
// sidebar: both derive from -[TLNetwork badgeTotal], which is the lobby
// (server) unread plus every channel's badge count, so the Dock total can
// never diverge from the window's sum. The unseen count is client-side and
// window-visibility aware (see TLChannel), so it grows even for the active
// channel while the window is hidden.
- (void)updateDockBadge
{
	NSInteger total = 0;
	for (TLNetwork *network in _session.serverState.networks) {
		total += [network badgeTotal];
	}
	[_dockBadge updateWithUnreadCount:total];
}

// Treat the active channel as seen once the user can actually see it. This is
// called when a channel is selected, whenever a message arrives in the active
// channel, and whenever the window returns to a visible state. A miniaturized
// or hidden window means the content is not on screen, so the unseen count is
// left intact there - that is what lets the badge accumulate while the window
// is in the Dock. (WindowShade is a window-manager feature with no AppKit
// query, so it cannot be detected here; isVisible/isMiniaturized cover the
// cases AppKit exposes.)
- (void)markActiveChannelSeen
{
	NSWindow *window = [self window];
	if (![window isVisible] || [window isMiniaturized]) {
		return;
	}
	if (_selectedChannelId == 0) {
		return;
	}
	TLChannel *channel = [_session.serverState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	if (channel.unseen != 0 || channel.unseenHighlight != 0) {
		channel.unseen = 0;
		channel.unseenHighlight = 0;
		// Let the sidebar (and the badge observer below) refresh.
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(_selectedChannelId)}];
	}
	// The server/lobby unread is network-scoped, not tied to the channel being
	// viewed. While the user is engaged with a network (window visible, any of
	// its channels active), its server notices are considered seen, so clear
	// them the same way the active channel's unread is cleared.
	TLNetwork *activeNetwork =
		[_session.serverState networkContainingChannel:_selectedChannelId];
	TLChannel *lobby = [activeNetwork lobby];
	if (lobby != nil && lobby.identifier != _selectedChannelId &&
		(lobby.unseen != 0 || lobby.unseenHighlight != 0)) {
		lobby.unseen = 0;
		lobby.unseenHighlight = 0;
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(lobby.identifier)}];
	}
	[self updateDockBadge];
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
	[self resetFilterState];
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
	// The channel is now on screen, so clear its unread immediately instead
	// of waiting for the bouncer to echo the reset back.
	[self markActiveChannelSeen];
}

- (void)populateViewsForChannel:(TLChannel *)channel
{
	[_messageView setChannelId:channel.identifier];
	[_messageView clear];
	for (TLMessage *message in channel.messages) {
		if ([self message:message matchesFilter:_filterText]) {
			[_messageView appendMessage:message];
		}
	}
	// Show pending messages (typed while offline) at the bottom, dimmed.
	for (TLMessage *message in channel.pendingMessages) {
		[_messageView appendMessage:message];
	}
	[self updateHasMoreHistoryForChannelId:channel.identifier];
	if ([_filterText length] > 0) {
		// While filtering, the scroll-to-top handler runs a server search
		// rather than plain history, so reflect the search cursor instead.
		[_messageView setHasMoreHistory:_searchHasMore];
	}
	[_messageView scrollToBottom];
	[_userListView reloadWithChannel:channel];
	// The bouncer replays only messages newer than what this client last
	// saw, so a quiet channel can start out shorter than the viewport -
	// too short to ever reach the top by scrolling. Fetch older batches
	// until the transcript is scrollable.
	[self autoFillHistoryIfShortTranscript];
}

- (void)repopulateActiveChannelCoalesced
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(repopulateActiveChannelNow) object:nil];
	[self performSelector:@selector(repopulateActiveChannelNow) withObject:nil afterDelay:0.12];
}

- (void)repopulateActiveChannelNow
{
	TLChannel *channel = [_session.serverState channelWithIdentifier:_selectedChannelId];
	if (channel) {
		[self populateViewsForChannel:channel];
	}
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
			if ([self message:message matchesFilter:_filterText]) {
				// A historical backfill can arrive newest-first; if the new
				// message is older than the transcript's current tail, rebuild
				// from the (timestamp-sorted) store instead of appending.
				TLChannel *ch = [_session.serverState channelWithIdentifier:channelId];
				BOOL outOfOrder = NO;
				if (ch != nil) {
					TLMessage *last = [[ch messages] lastObject];
					if (last != nil && message.timestamp != nil &&
						[message.timestamp compare:[last timestamp]] == NSOrderedAscending) {
						outOfOrder = YES;
					}
				}
			if (outOfOrder) {
				[self repopulateActiveChannelCoalesced];
			} else {
				[_messageView appendMessage:message];
			}
			}
		} else {
			// No specific message - pending messages were queued or flushed.
			// Repopulate to show/hide pending indicators.
			TLChannel *ch = [_session.serverState channelWithIdentifier:channelId];
			if (ch) {
				[self populateViewsForChannel:ch];
			}
		}
		[self updateHasMoreHistoryForChannelId:channelId];
		if ([_filterText length] > 0) {
			[_messageView setHasMoreHistory:_searchHasMore];
		}
		// The active channel is on screen, so its unseen count is cleared
		// immediately even though the protocol just incremented it.
		[self markActiveChannelSeen];
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
			// The first page of a freshly opened channel must show the newest
			// message at the bottom, so repopulate and scroll down. Once the
			// transcript already holds that channel's messages, later (older
			// history) batches arrive via the same notification but use prepend,
			// which keeps the current reading position in place.
			if ([_filterText length] == 0) {
				if ([_messageView isEmpty]) {
					[self populateViewsForChannel:channel];
				} else {
					[_messageView prependMessages:channel.messages];
				}
			}
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

// Nostr display names (kind 0 metadata) resolve asynchronously after the
// messages have already been rendered, so re-render the open transcript with
// the now-resolved nicknames.
- (void)protocolNicknamesDidChange:(NSNotification *)notification
{
	TLChannel *channel = [_session.serverState channelWithIdentifier:_selectedChannelId];
	if (channel) {
		[self populateViewsForChannel:channel];
	}
}

// The bouncer answered a backlog `search` with a page of matching messages.
// Merge them into the running result set, advance the pagination offset, and
// rebuild the filtered transcript. A short page means the backlog is done.
- (void)protocolSearchResultsDidChange:(NSNotification *)notification
{
	NSInteger channelId = [notification.userInfo[@"channelId"] integerValue];
	if (channelId != _selectedChannelId) {
		return;
	}
	NSArray *messages = notification.userInfo[@"messages"];
	NSInteger count = [notification.userInfo[@"count"] integerValue];
	if (count > 0 && [messages isKindOfClass:[NSArray class]]) {
		for (TLMessage *message in messages) {
			[_searchResults addObject:message];
		}
		_searchOffset += count;
	}
	// The bouncer caps each page at 100, so fewer returned means no more
	// matches remain for this term.
	_searchHasMore = (count >= 100);
	_searchLoading = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetSearchLoadingFlag) object:nil];
	[self rebuildTranscriptForFilter];
}

- (void)sessionStateDidChange:(NSNotification *)notification
{
	if (notification.object != _session) {
		return;
	}
	[_statusLabel setStringValue:TLConnectionStateDisplayString(_session.state)];
	// Color the status label to reflect connection health at a glance.
	switch (_session.state) {
		case TLConnectionStateReconnecting:
		case TLConnectionStateConnectionError:
		case TLConnectionStateServerDisconnected:
			[_statusLabel setTextColor:[NSColor colorWithCalibratedRed:0.85
				green:0.35 blue:0.25 alpha:1.0]];
			break;
		case TLConnectionStateReady:
			[_statusLabel setTextColor:[NSColor colorWithCalibratedRed:0.25
				green:0.70 blue:0.35 alpha:1.0]];
			break;
		default:
			[_statusLabel setTextColor:[NSColor controlTextColor]];
			break;
	}
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
	NSString *text = [[_inputTextView string]
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
	[_inputTextView setString:@""];
	[self updateComposerHeight];
}

// Tab completes the word before the cursor to a nick of the current
// channel, but only when exactly one user matches; anything ambiguous is
// left untouched rather than guessing.
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	// Name-based selector comparison: robust even where SEL pointers are
	// not guaranteed identical across modules.
	BOOL isTab = [NSStringFromSelector(command) isEqualToString:@"insertTab:"];
	if (!isTab || textView != _inputTextView) {
		return NO;
	}

	NSString *text = [textView string];
	NSUInteger cursor = NSMaxRange([textView selectedRange]);
	NSUInteger start = cursor;
	NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	while (start > 0 && ![spaces characterIsMember:[text characterAtIndex:start - 1]]) {
		start--;
	}
	if (cursor <= start) {
		return YES;
	}

	TLChannel *channel = [_session.serverState channelWithIdentifier:_selectedChannelId];
	TLUser *match = [channel uniqueUserWithNickPrefix:
	    [text substringWithRange:NSMakeRange(start, cursor - start)]];
	if (!match) {
		return YES;
	}

	// A completion that starts the line reads as an address; mid-sentence
	// it is just a mention.
	NSString *nick = [match nick];
	NSString *replacement = (start == 0)
	    ? [nick stringByAppendingString:@": "]
	    : [nick stringByAppendingString:@" "];
	NSString *newText = [NSString stringWithFormat:@"%@%@%@",
	    [text substringToIndex:start], replacement,
	    [text substringFromIndex:cursor]];
	[textView setString:newText];
	[textView setSelectedRange:NSMakeRange(start + [replacement length], 0)];
	return YES;
}

#pragma mark - Window title

- (void)setWindowTitle
{
	NSString *title = nil;
	if (_session.serverURLString.length > 0) {
		title = [self serverHostname];
	} else {
		title = @"The Lounge";
	}
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
	[self requestOlderContentForSelectedChannel];
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
// would be impossible. Suppressed while a filter is active, because in that
// mode scroll-to-top means "search the server", not "load older history".
- (void)autoFillHistoryIfShortTranscript
{
	if ([_filterText length] > 0) {
		return;
	}
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

#pragma mark - Transcript filtering / server search

// Forgets all filter state; called when switching channels and on teardown so
// a previous search can never leak into the next channel.
- (void)resetFilterState
{
	[_filterText release];
	_filterText = nil;
	[_searchResults removeAllObjects];
	_searchOffset = 0;
	_searchHasMore = NO;
	_searchLoading = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(applySearchFilter) object:nil];
	if (_searchField && ![[_searchField stringValue] isEqualToString:@""]) {
		[_searchField setStringValue:@""];
	}
}

// Live filtering as the user types; debounced so we rebuild at most once the
// typing settles rather than on every keystroke.
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] != _searchField) {
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(applySearchFilter) object:nil];
	[self performSelector:@selector(applySearchFilter) withObject:nil afterDelay:0.3];
}

- (void)applySearchFilter
{
	NSString *term = [[_searchField stringValue]
		stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[_filterText release];
	_filterText = ([term length] > 0) ? [term retain] : nil;
	// A fresh term starts a new server search from the first page of the
	// backlog; discard any previous results.
	[_searchResults removeAllObjects];
	_searchOffset = 0;
	_searchHasMore = ([_filterText length] > 0);
	_searchLoading = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetSearchLoadingFlag) object:nil];
	[self rebuildTranscriptForFilter];
	if ([_filterText length] > 0) {
		// The bouncer may hold matches older than what we downloaded; fetch
		// the first page of server-side matches immediately so the filter is
		// not limited to already-loaded messages.
		[self requestServerSearchForSelectedChannel];
	}
}

// Case-insensitive substring match against the message body and the sender's
// nick, which is what a user expects from a transcript filter.
- (BOOL)message:(TLMessage *)message matchesFilter:(NSString *)filter
{
	if ([filter length] == 0) {
		return YES;
	}
	NSString *needle = [filter lowercaseString];
	if ([[[message text] lowercaseString] rangeOfString:needle].location
		!= NSNotFound) {
		return YES;
	}
	TLUser *sender = [message sender];
	NSString *nick = sender ? [sender nick] : nil;
	if (nick && [[nick lowercaseString] rangeOfString:needle].location
		!= NSNotFound) {
		return YES;
	}
	return NO;
}

// Rebuilds the transcript from the channel's messages plus any server-side
// search results, keeping only those that match the active filter. The two
// sources are merged and deduplicated (by time+author+text, since search
// results carry synthetic ids) and ordered chronologically so backlog matches
// interleave correctly with the messages we already hold.
- (void)rebuildTranscriptForFilter
{
	TLChannel *channel =
		[_session.serverState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	[_messageView clear];

	NSMutableArray *combined = [NSMutableArray array];
	for (TLMessage *message in channel.messages) {
		[combined addObject:message];
	}
	for (TLMessage *message in _searchResults) {
		[combined addObject:message];
	}
	[combined sortUsingComparator:^NSComparisonResult(TLMessage *a, TLMessage *b) {
		return [a.timestamp compare:b.timestamp];
	}];

	NSMutableSet *seen = [NSMutableSet set];
	for (TLMessage *message in combined) {
		if (![self message:message matchesFilter:_filterText]) {
			continue;
		}
		NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
			[message.timestamp description], [message text] ?: @"",
			[message sender] ? [[message sender] nick] : @""];
		if ([seen containsObject:key]) {
			continue;
		}
		[seen addObject:key];
		[_messageView appendMessage:message];
	}

	if ([_filterText length] > 0) {
		[_messageView setHasMoreHistory:_searchHasMore];
	} else {
		[self updateHasMoreHistoryForChannelId:_selectedChannelId];
	}
}

// Scroll-to-top routes to a server search while filtering, otherwise to the
// usual older-history fetch.
- (void)requestOlderContentForSelectedChannel
{
	if ([_filterText length] > 0) {
		[self requestServerSearchForSelectedChannel];
	} else {
		[self requestOlderHistoryForSelectedChannel];
	}
}

// Asks the bouncer to search its stored backlog for the active filter term and
// merge the page of matches into the transcript. Pagination is by `offset`
// (the bouncer returns at most 100 per page); when a page comes back short the
// search is exhausted. Single-flight via _searchLoading; a lost response clears
// the flag after 10 seconds.
- (void)requestServerSearchForSelectedChannel
{
	if (_searchLoading || !_searchHasMore) {
		return;
	}
	TLChannel *channel =
		[_session.serverState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	_searchLoading = YES;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetSearchLoadingFlag) object:nil];
	[self performSelector:@selector(resetSearchLoadingFlag)
		withObject:nil afterDelay:10.0];
	[_session searchMessagesForChannelId:channel.identifier
		term:_filterText offset:_searchOffset];
}

- (void)resetSearchLoadingFlag
{
	_searchLoading = NO;
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
	if ([command isEqualToString:@"/list"]) {
		TLNetwork *network =
			[_session.serverState networkContainingChannel:channelId];
		if ([self isNostermNetwork:network]) {
			[self showNostermGroupListForNetwork:network];
			return;
		}
	}
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
	// the bouncer normalize the target. Nosterm relays handle joining by
	// creating/subscribing to a NIP-29 group instead.
	[_session joinExistingChannelNamed:name forLobbyId:lobbyId];

	// If the join produced a channel we can see, bring it into view.
	for (TLNetwork *network in _session.serverState.networks) {
		for (TLChannel *channel in network.channels) {
			if ([channel.name isEqualToString:name]) {
				[self selectChannelId:channel.identifier];
				return;
			}
		}
	}
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

- (void)contextMenuForgetNetworkForChannelId:(NSInteger)channelId
{
	TLNetwork *network = [_session.serverState networkContainingChannel:channelId];
	if (!network) {
		return;
	}
	NSString *name = network.name ?: @"this server";
	if (![self confirmTitled:@"Forget server"
		message:[NSString stringWithFormat:
			@"Are you sure you want to forget %@? It will be removed from the sidebar "
			"and will not reconnect on next launch.", name]
		button:@"Forget"]) {
		return;
	}
	TLoungeProtocol *proto = [_session protocolForNetwork:network];
	if ([proto isNostermProtocol]) {
		// Nosterm relay: find the matching relay URL and disconnect.
		for (NSDictionary *relay in [_session connectedRelays]) {
			NSURL *url = [NSURL URLWithString:relay[@"url"]];
			if (url && [[relay objectForKey:@"kind"] isEqualToString:@"nosterm"]) {
				// Match by network name (relay display name).
				if ([relay[@"name"] isEqualToString:network.name]) {
					[[NSApp delegate] removeServerFromSavedList:relay[@"url"]];
					[_session disconnectRelayWithURL:url];
					return;
				}
			}
		}
	} else {
		// Lounge bouncer: remove from saved list and disconnect.
		[[NSApp delegate] removeServerFromSavedList:[_session serverURLString]];
		[_session sendCommand:@"/quit" toChannelId:channelId];
	}
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
	if (network == nil) {
		return;
	}
	if ([self isNostermNetwork:network]) {
		[self showNostermGroupListForNetwork:network];
		return;
	}
	[self contextMenuRunCommand:@"/list"
		onChannelId:[[network lobby] identifier]];
}

// A Nosterm relay has no IRC-style channel directory, so "List all channels"
// presents the groups we already know about instead of sending a no-op /list.
- (BOOL)isNostermNetwork:(TLNetwork *)network
{
	if (network == nil) {
		return NO;
	}
	TLoungeProtocol *proto = [_session protocolForNetwork:network];
	return proto != nil && [proto isNostermProtocol];
}

- (void)showNostermGroupListForNetwork:(TLNetwork *)network
{
	TLoungeProtocol *proto = [_session protocolForNetwork:network];
	NSArray *names = [proto knownGroupNames];
	if ([names count] == 0) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"No NIP-29 groups known"];
		[alert setInformativeText:
			@"This Nosterm relay has no known NIP-29 groups yet. "
			@"Join or create one from Join Channel."];
		[alert addButtonWithTitle:@"OK"];
		[alert runModal];
		[alert release];
		return;
	}
	TLNostermGroupListController *panel =
		[[TLNostermGroupListController alloc] initWithGroupNames:names];
	[panel.window center];
	NSInteger result = [NSApp runModalForWindow:panel.window];
	if (result == 1 && [panel.selectedGroupName length] > 0) {
		[self openNostermGroupNamed:panel.selectedGroupName
			inNetwork:network];
	}
	[panel close];
	[panel release];
}

- (void)openNostermGroupNamed:(NSString *)name inNetwork:(TLNetwork *)network
{
	for (TLChannel *ch in [network channels]) {
		if ([[ch name] isEqualToString:name]) {
			// Re-send the group join in case it was missed, so posting is
			// permitted even if the group was only discovered via metadata.
			[_session ensureJoinedChannelId:[ch identifier]];
			[self selectChannelId:[ch identifier]];
			return;
		}
	}
	NSInteger lobbyId = [network lobby] ? [[network lobby] identifier] : 0;
	[_session joinChannelNamed:name forLobbyId:lobbyId];
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
		// Kick and mode have additional rank checks below; Whois, Ignore,
		// Query are simply enabled when a user is selected.
		if (action != @selector(chatKickSelectedUser:) &&
			action != @selector(chatSetMode:)) {
			return YES;
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

	// Actions forwarded to the app delegate (menu items target it directly).
	if (action == @selector(connectToRelay:) ||
		action == @selector(connectToDemoRelay:) ||
		action == @selector(connectToLounge:)) {
		return YES;
	}

	// Actions not implemented here must fall through so the responder chain
	// can deliver them to the app delegate (e.g. connectToRelay:).
	return NO;
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

// The window returning to the screen means the user can see the active
// channel again, so drop its unread count right away.
- (void)windowDidBecomeKey:(NSNotification *)notification
{
	[self markActiveChannelSeen];
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
	[self markActiveChannelSeen];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[_session release];
	[_splitView release];
	[_networkOutline release];
	[_messagePane release];
	[_messageView release];
	[_searchField release];
	[_searchResults release];
	[_userListView release];
	[_inputTextView release];
	[_composerBar release];
	[_dockBadge release];
	[_sendButton release];
	[_statusLabel release];
	[super dealloc];
}

@end