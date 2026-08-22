/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLNetworkOutlineView.h"

#import "TLServerState.h"
#import "TLNetwork.h"
#import "TLChannel.h"

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
		_outlineView = [[NSOutlineView alloc] initWithFrame:
			NSMakeRect(0, 0, contentSize.width, contentSize.height)];
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"channel"];
		[column setWidth:contentSize.width];
		[column setResizingMask:NSTableColumnAutoresizingMask];
		[_outlineView addTableColumn:column];
		[_outlineView setOutlineTableColumn:column];
		[_outlineView setHeaderView:nil];
		[_outlineView setAutoresizesOutlineColumn:NO];
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
	NSInteger row = [self rowForChannelId:channelId];
	if (row >= 0) {
		[_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
			byExtendingSelection:NO];
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
	} else if ([item isKindOfClass:[TLChannel class]]) {
		TLChannel *channel = item;
		title = channel.name;
		if (channel.unread > 0) {
			title = [title stringByAppendingFormat:@" (%ld)", (long)channel.unread];
		}
		if (channel.highlight > 0) {
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
	// Network rows act as group headers and are not selectable.
	return [item isKindOfClass:[TLChannel class]];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger row = [_outlineView selectedRow];
	if (row < 0) {
		return;
	}
	id item = [_outlineView itemAtRow:row];
	if (![item isKindOfClass:[TLChannel class]]) {
		return;
	}
	TLChannel *channel = item;
	// Skip programmatic selections: they already set _selectedChannelId.
	if (_selectedChannelId == channel.identifier) {
		return;
	}
	_selectedChannelId = channel.identifier;
	if ([_delegate respondsToSelector:@selector(networkOutlineView:didSelectChannelId:)]) {
		[_delegate networkOutlineView:self didSelectChannelId:channel.identifier];
	}
}

- (void)dealloc
{
	[_scrollView release];
	[_outlineView release];
	[_serverState release];
	[super dealloc];
}

@end