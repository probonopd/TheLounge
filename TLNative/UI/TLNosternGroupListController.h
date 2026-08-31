/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

// A small modal panel that lists the NIP-29 groups a NOSTERN relay currently
// knows about, so the "List all channels" action has something meaningful to
// show (a NOSTERN relay has no IRC-style channel directory to query).
@interface TLNosternGroupListController : NSWindowController
    <NSTableViewDataSource, NSTableViewDelegate>
{
	NSTableView *_tableView;
	NSButton *_openButton;
	NSArray *_groupNames;
	NSString *_selectedGroupName;
}

@property (nonatomic, copy) NSArray *groupNames;
@property (nonatomic, copy) NSString *selectedGroupName;

- (instancetype)initWithGroupNames:(NSArray *)groupNames;

@end
