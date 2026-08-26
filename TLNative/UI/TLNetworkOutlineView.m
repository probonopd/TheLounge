/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLNetworkOutlineView.h"

#import "TLChannelBadgeCell.h"
#import "TLServerState.h"
#import "TLNetwork.h"
#import "TLChannel.h"

// NSView's default rightMouseDown: pops up menuForEvent:, so overriding it
// here is the portable way to attach context menus to rows.
@interface TLChannelOutlineView : NSOutlineView
{
	__unsafe_unretained id _menuOwner;
}
@property (nonatomic, assign) id menuOwner;
@end

@implementation TLChannelOutlineView
@synthesize menuOwner = _menuOwner;

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger row = [self rowAtPoint:point];
	if (row < 0) {
		return nil;
	}
	id item = [self itemAtRow:row];
	if (![item isKindOfClass:[TLNetwork class]] &&
		![item isKindOfClass:[TLChannel class]]) {
		return nil;
	}
	if ([self selectedRow] != row &&
		[item isKindOfClass:[TLChannel class]]) {
		// Right-click selects, matching standard desktop behavior and the
		// web client's context menu on the row under the cursor.
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
			byExtendingSelection:NO];
	}
	TLNetworkOutlineView *owner = (TLNetworkOutlineView *)_menuOwner;
	if (![owner.delegate respondsToSelector:
			@selector(networkOutlineView:contextMenuForRowItem:)]) {
		return nil;
	}
	return [owner.delegate networkOutlineView:owner contextMenuForRowItem:item];
}

@end

@implementation TLNetworkOutlineView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_selectedChannelId = 0;

		_scrollView = [[NSScrollView alloc] initWithFrame:[self bounds]];
		[_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[_scrollView setHasVerticalScroller:YES];
		[_scrollView setAutohidesScrollers:YES];
		[_scrollView setBorderType:NSBezelBorder];

		NSSize contentSize = [_scrollView contentSize];
		_outlineView = [[TLChannelOutlineView alloc] initWithFrame:
			NSMakeRect(0, 0, contentSize.width, contentSize.height)];
		[(TLChannelOutlineView *)_outlineView setMenuOwner:self];
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"channel"];
		[column setWidth:contentSize.width];
		[column setResizingMask:NSTableColumnAutoresizingMask];
		TLChannelBadgeCell *badgeCell = [[TLChannelBadgeCell alloc] init];
		[column setDataCell:badgeCell];
		[badgeCell release];
		[_outlineView addTableColumn:column];
		[_outlineView setOutlineTableColumn:column];
		[_outlineView setHeaderView:nil];
		[_outlineView setAutoresizesOutlineColumn:NO];
		[_outlineView setRowHeight:18.0];
		[_outlineView setAutoresizingMask:NSViewWidthSizable];
		[_outlineView setDataSource:self];
		[_outlineView setDelegate:self];
		[_outlineView setAllowsMultipleSelection:NO];
		[_scrollView setDocumentView:_outlineView];
		[column release];

		[self addSubview:_scrollView];
	}
	return self;
}

- (void)setServerState:(TLServerState *)serverState
{
	if (_serverState != serverState) {
		[_serverState release];
		_serverState = [serverState retain];
	}
}

- (TLServerState *)serverState
{
	return _serverState;
}

- (void)setDelegate:(id<TLNetworkOutlineViewDelegate>)delegate
{
	_delegate = delegate;
}

- (id<TLNetworkOutlineViewDelegate>)delegate
{
	return _delegate;
}

- (void)setSelectedChannelId:(NSInteger)selectedChannelId
{
	_selectedChannelId = selectedChannelId;
}

- (NSInteger)selectedChannelId
{
	return _selectedChannelId;
}

#pragma mark - Data

- (NSArray *)networks
{
	return _serverState ? [NSArray arrayWithArray:_serverState.networks] : [NSArray array];
}

// Channels shown in the tree: joined channels and queries (the lobby is
// joined as well). Parted and closed channels stay hidden until rejoined.
- (NSArray *)visibleChannelsForNetwork:(TLNetwork *)network
{
	NSMutableArray *result = [NSMutableArray array];
	for (TLChannel *channel in network.channels) {
		if (channel.state != TLChannelStateJoined || channel.closed) {
			continue;
		}
		[result addObject:channel];
	}
	[result sortUsingComparator:^NSComparisonResult(TLChannel *a, TLChannel *b) {
		BOOL aLobby = (a.type == TLChannelTypeLobby);
		BOOL bLobby = (b.type == TLChannelTypeLobby);
		if (aLobby != bLobby) {
			return aLobby ? NSOrderedAscending : NSOrderedDescending;
		}
		return [[a.name lowercaseString] compare:[b.name lowercaseString]];
	}];
	return result;
}

- (void)reloadData
{
	[_outlineView reloadData];
	// Networks stay expanded so the channel list is always visible.
	for (TLNetwork *network in [self networks]) {
		if (![_outlineView isItemExpanded:network]) {
			[_outlineView expandItem:network];
		}
	}
	if (_selectedChannelId > 0) {
		[self selectChannelId:_selectedChannelId];
	}
}

- (void)selectChannelId:(NSInteger)channelId
{
	_selectedChannelId = channelId;
	NSInteger row;
	if (_selectedItemIsNetworkRow) {
		// The user clicked a network header; keep the highlight there while
		// showing its lobby instead of jumping down to the lobby row.
		TLNetwork *network = _serverState ?
			[_serverState networkContainingChannel:channelId] : nil;
		row = network ? [_outlineView rowForItem:network]
			: [self rowForChannelId:channelId];
	} else {
		row = [self rowForChannelId:channelId];
	}
	if (row >= 0) {
		if ([_outlineView selectedRow] != row) {
			[_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:
				(NSUInteger)row] byExtendingSelection:NO];
		}
	}
}

- (NSInteger)rowForChannelId:(NSInteger)channelId
{
	for (TLNetwork *network in [self networks]) {
		if ([_outlineView rowForItem:network] < 0) {
			continue;
		}
		for (TLChannel *channel in [self visibleChannelsForNetwork:network]) {
			if (channel.identifier == channelId) {
				return [_outlineView rowForItem:channel];
			}
		}
	}
	return -1;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item
{
	if (item == nil) {
		return (NSInteger)[[self networks] count];
	}
	if ([item isKindOfClass:[TLNetwork class]]) {
		return (NSInteger)[[self visibleChannelsForNetwork:item] count];
	}
	return 0;
}

- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item
{
	if (item == nil) {
		return [[self networks] objectAtIndex:(NSUInteger)index];
	}
	return [[self visibleChannelsForNetwork:item] objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item
{
	return [item isKindOfClass:[TLNetwork class]];
}

- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)tableColumn
	byItem:(id)item
{
	return @"";
}

#pragma mark - NSOutlineViewDelegate

- (void)outlineView:(NSOutlineView *)outline willDisplayCell:(id)cell
	forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	NSString *title = @"";
	// GNUstep takes a zero font size literally; ask for the real defaults.
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	if ([item isKindOfClass:[TLNetwork class]]) {
		TLNetwork *network = item;
		title = [network.name length] > 0 ? network.name : @"Network";
		font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
		// badgeTotal is the network's server (lobby) unread plus every
		// channel's badge count. To keep "sum of every badge in the pane ==
		// Dock badge" without double-counting, the network row shows the full
		// total when collapsed (channels hidden), and only the residual not
		// already shown per-channel when expanded (i.e. the server unread).
		BOOL expanded = [_outlineView isItemExpanded:network];
		NSInteger total = [network badgeTotal];
		NSInteger perChannel = 0;
		if (expanded) {
			// Only visible (joined, unclosed) channels are drawn as rows, so
			// the residual must subtract just those; unread in parted/closed
			// channels rolls up into the network row instead of disappearing
			// (which had made the Dock exceed the pane sum).
			for (TLChannel *channel in [self visibleChannelsForNetwork:network]) {
				perChannel += [channel badgeCount];
			}
		}
		NSInteger networkBadge = total - perChannel;
		if ([cell respondsToSelector:@selector(setUnseen:)]) {
			[cell setUnseen:networkBadge];
		}
	} else if ([item isKindOfClass:[TLChannel class]]) {
		TLChannel *channel = item;
		title = channel.name;
		// Surface the client-side unseen count as a red badge on the cell
		// (see TLChannelBadgeCell). The same badgeCount drives the Dock badge,
		// so the two can never disagree (muted/lobby count as zero).
		if ([cell respondsToSelector:@selector(setUnseen:)]) {
			[cell setUnseen:[channel badgeCount]];
		}
		if (channel.unseenHighlight > 0 && [channel badgeCount] > 0) {
			font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
		}
	}
	// Theme cells snapshot the text color into their attributed title at
	// setTitle: time, so the color must be assigned first.
	if ([cell respondsToSelector:@selector(setTextColor:)]) {
		[cell setTextColor:[NSColor controlTextColor]];
	}
	[cell setTitle:title];
	[cell setFont:font];
}

- (BOOL)outlineView:(NSOutlineView *)outline shouldSelectItem:(id)item
{
	// Networks act as their own selection target so they can be chatted in
	// (the lobby), not just expanded.
	return [item isKindOfClass:[TLNetwork class]] ||
		[item isKindOfClass:[TLChannel class]];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger row = [_outlineView selectedRow];
	if (row < 0) {
		return;
	}
	id item = [_outlineView itemAtRow:row];
	TLChannel *channel = nil;
	if ([item isKindOfClass:[TLNetwork class]]) {
		channel = [(TLNetwork *)item lobby];
		_selectedItemIsNetworkRow = YES;
		// Clicking a network name clears its server/lobby unread, exactly as
		// clicking a channel clears that channel's unread. Without this the
		// count would only reset for the network currently engaged via a
		// channel, so a clicked-but-not-engaged network kept its badge.
		if (channel != nil && (channel.unseen != 0 || channel.unseenHighlight != 0)) {
			channel.unseen = 0;
			channel.unseenHighlight = 0;
			[[NSNotificationCenter defaultCenter]
				postNotificationName:TLLoungeChannelDidChangeNotification
				object:self
				userInfo:@{@"channelId": @(channel.identifier)}];
		}
	} else if ([item isKindOfClass:[TLChannel class]]) {
		channel = item;
		_selectedItemIsNetworkRow = NO;
	}
	if (!channel) {
		return;
	}
	// Skip programmatic selections: they already set _selectedChannelId.
	if (_selectedChannelId == channel.identifier) {
		return;
	}
	_selectedChannelId = channel.identifier;
	if ([_delegate respondsToSelector:@selector(networkOutlineView:didSelectChannelId:)]) {
		[_delegate networkOutlineView:self didSelectChannelId:channel.identifier];
	}
}

- (BOOL)outlineView:(NSOutlineView *)outline shouldCollapseItem:(id)item
{
	if ([item isKindOfClass:[TLNetwork class]]) {
		TLChannel *lobby = [(TLNetwork *)item lobby];
		if (lobby != nil && (lobby.unseen != 0 || lobby.unseenHighlight != 0)) {
			lobby.unseen = 0;
			lobby.unseenHighlight = 0;
			[[NSNotificationCenter defaultCenter]
				postNotificationName:TLLoungeChannelDidChangeNotification
				object:self
				userInfo:@{@"channelId": @(lobby.identifier)}];
		}
	}
	return YES;
}

- (void)dealloc
{
	[_scrollView release];
	[_outlineView release];
	[_serverState release];
	[super dealloc];
}

@end