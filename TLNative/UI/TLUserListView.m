/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLUserListView.h"

#import "TLChannel.h"
#import "TLUser.h"
#import "TLMessageRenderer.h"

// NSView's default rightMouseDown: pops up menuForEvent:, so overriding it
// here is the portable way to attach context menus to rows.
@interface TLUserListTableView : NSTableView
{
	__unsafe_unretained id _menuOwner;
}
@property (nonatomic, assign) id menuOwner;
@end

@implementation TLUserListTableView
@synthesize menuOwner = _menuOwner;

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger row = [self rowAtPoint:point];
	if (row < 0) {
		return nil;
	}
	if ([self selectedRow] != row) {
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
			byExtendingSelection:NO];
	}
	TLUserListView *owner = (TLUserListView *)_menuOwner;
	if (![owner.delegate respondsToSelector:
			@selector(userListView:contextMenuForRow:)]) {
		return nil;
	}
	return [owner.delegate userListView:owner contextMenuForRow:row];
}

@end

@implementation TLUserListView
@synthesize delegate = _delegate;

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_scrollView = [[NSScrollView alloc] initWithFrame:[self bounds]];
		[_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[_scrollView setHasVerticalScroller:YES];
		[_scrollView setAutohidesScrollers:YES];
		[_scrollView setBorderType:NSBezelBorder];

		NSSize contentSize = [_scrollView contentSize];
		_tableView = [[TLUserListTableView alloc] initWithFrame:
			NSMakeRect(0, 0, contentSize.width, contentSize.height)];
		[(TLUserListTableView *)_tableView setMenuOwner:self];
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"user"];
		[column setWidth:contentSize.width];
		[column setResizingMask:NSTableColumnAutoresizingMask];
		[_tableView addTableColumn:column];
		[_tableView setHeaderView:nil];
		[_tableView setDataSource:self];
		[_tableView setAllowsMultipleSelection:NO];
		[_tableView setAutoresizingMask:NSViewWidthSizable];
		// The delegate methods (selection tracking) live in this class; the
		// protocol is deliberately not declared (GNUstep marks nothing
		// optional, so declaring it would demand every method).
		[_tableView setDelegate:self];
		[_scrollView setDocumentView:_tableView];
		[column release];

		[self addSubview:_scrollView];
	}
	return self;
}

- (void)reloadWithChannel:(TLChannel *)channel
{
	[channel retain];
	[_channel release];
	_channel = channel;
	[_tableView reloadData];
	// Row indexes may no longer match the selection after a reload.
	NSInteger row = [_tableView selectedRow];
	if (row >= (NSInteger)[_channel.sortedUsers count]) {
		[_tableView deselectAll:nil];
		row = -1;
	}
	if ([_delegate respondsToSelector:@selector(userListView:didSelectRow:)]) {
		[_delegate userListView:self didSelectRow:row];
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	if ([_delegate respondsToSelector:@selector(userListView:didSelectRow:)]) {
		[_delegate userListView:self didSelectRow:[_tableView selectedRow]];
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return _channel ? (NSInteger)[_channel.sortedUsers count] : 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn
	row:(NSInteger)row
{
	TLUser *user = [_channel.sortedUsers objectAtIndex:(NSUInteger)row];
	return [TLMessageRenderer attributedStringForNick:user.nick mode:user.mode];
}

- (void)dealloc
{
	[_scrollView release];
	[_tableView release];
	[_channel release];
	[super dealloc];
}

@end