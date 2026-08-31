/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLNostermGroupListController.h"

@implementation TLNostermGroupListController

- (instancetype)initWithGroupNames:(NSArray *)groupNames
{
	NSRect contentRect = NSMakeRect(0, 0, 360, 320);
	NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
		styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	[window setTitle:@"NIP-29 Groups"];
	[window setReleasedWhenClosed:NO];
	[window center];

	self = [super initWithWindow:window];
	[window release];
	if (self) {
		_groupNames = [groupNames copy];
		[self buildContentViewForWindow:window];
	}
	return self;
}

- (void)dealloc
{
	[_groupNames release];
	[_selectedGroupName release];
	[super dealloc];
}

- (void)buildContentViewForWindow:(NSWindow *)window
{
	NSView *contentView = [window contentView];
	CGFloat width = NSWidth([window contentRectForFrameRect:[window frame]]);

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
		NSMakeRect(24.0, 60.0, width - 48.0,
			NSHeight([window contentRectForFrameRect:[window frame]]) - 60.0 - 56.0)];
	[scroll setHasVerticalScroller:YES];
	[scroll setBorderType:NSBezelBorder];
	[scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

	_tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[col setTitle:@"Group"];
	[col setWidth:width - 48.0];
	[_tableView addTableColumn:col];
	[col release];
	[_tableView setHeaderView:nil];
	[_tableView setDataSource:self];
	[_tableView setDelegate:self];
	[_tableView setTarget:self];
	[_tableView setDoubleAction:@selector(openFromDoubleClick:)];
	[scroll setDocumentView:_tableView];
	[_tableView release];
	[contentView addSubview:scroll];
	[scroll release];

	_openButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(width - 24.0 - 100.0, 16.0, 100.0, 24.0)];
	[_openButton setBezelStyle:NSRoundedBezelStyle];
	[_openButton setTitle:@"Open"];
	[_openButton setKeyEquivalent:@"\r"];
	[_openButton setTarget:self];
	[_openButton setAction:@selector(open:)];
	[_openButton setEnabled:([_groupNames count] > 0)];
	[contentView addSubview:_openButton];
	[_openButton release];

	NSButton *cancel = [[NSButton alloc] initWithFrame:
		NSMakeRect(width - 24.0 - 100.0 - 12.0 - 100.0, 16.0, 100.0, 24.0)];
	[cancel setBezelStyle:NSRoundedBezelStyle];
	[cancel setTitle:@"Cancel"];
	[cancel setKeyEquivalent:@"\033"];
	[cancel setTarget:self];
	[cancel setAction:@selector(cancel:)];
	[contentView addSubview:cancel];
	[cancel release];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[_groupNames count];
}

- (id)tableView:(NSTableView *)tableView
	objectValueForTableColumn:(NSTableColumn *)tableColumn
	row:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[_groupNames count]) {
		return @"";
	}
	return [_groupNames objectAtIndex:row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[_openButton setEnabled:([_tableView selectedRow] >= 0)];
}

// Double-clicking a group opens it directly, matching the web client's list.
- (void)openFromDoubleClick:(id)sender
{
	[self open:self];
}

- (IBAction)open:(id)sender
{
	NSInteger row = [_tableView selectedRow];
	if (row < 0 || row >= (NSInteger)[_groupNames count]) {
		return;
	}
	[_selectedGroupName release];
	_selectedGroupName = [[_groupNames objectAtIndex:row] copy];
	[NSApp stopModalWithCode:1];
}

- (IBAction)cancel:(id)sender
{
	[NSApp stopModalWithCode:0];
}

@end
