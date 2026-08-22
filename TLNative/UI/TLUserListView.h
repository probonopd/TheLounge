/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLChannel;

@interface TLUserListView : NSView <NSTableViewDataSource>
{
	NSScrollView *_scrollView;
	NSTableView *_tableView;
	TLChannel *_channel;
}

- (void)reloadWithChannel:(TLChannel *)channel;

@end