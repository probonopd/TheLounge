/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLUserListView.h"

#import "TLChannel.h"
#import "TLUser.h"
#import "TLMessageRenderer.h"

@implementation TLUserListView

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
		_tableView = [[NSTableView alloc] initWithFrame:
			NSMakeRect(0, 0, contentSize.width, contentSize.height)];
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"user"];
		[column setWidth:contentSize.width];
		[column setResizingMask:NSTableColumnAutoresizingMask];
		[_tableView addTableColumn:column];
		[_tableView setHeaderView:nil];
		[_tableView setDataSource:self];
		[_tableView setAllowsMultipleSelection:NO];
		[_tableView setAutoresizingMask:NSViewWidthSizable];
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