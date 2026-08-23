/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLChannel;
@class TLUserListView;

@protocol TLUserListViewDelegate <NSObject>
@optional
// Row indexes match -sortedUsers order; returned menu is popped at the mouse.
- (NSMenu *)userListView:(TLUserListView *)view contextMenuForRow:(NSInteger)row;
// Fires with -1 when the selection goes away (e.g. after a reload).
- (void)userListView:(TLUserListView *)view didSelectRow:(NSInteger)row;
@end

@interface TLUserListView : NSView <NSTableViewDataSource>
{
	NSScrollView *_scrollView;
	NSTableView *_tableView;
	TLChannel *_channel;
	id<TLUserListViewDelegate> _delegate;
}

@property (nonatomic, assign) id<TLUserListViewDelegate> delegate;
@property (nonatomic, readonly) NSInteger selectedUserRow;

- (void)reloadWithChannel:(TLChannel *)channel;
// Selects and reveals the row of the given nick; NO when that user is not
// in the current channel.
- (BOOL)selectUserWithNick:(NSString *)nick;

@end
