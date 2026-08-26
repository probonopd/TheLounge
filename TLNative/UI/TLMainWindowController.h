/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "TLNetworkOutlineView.h"
#import "TLMessageView.h"
#import "TLUserListView.h"
#import "TLContextMenuBuilder.h"

@class TLoungeSession;
@class TLInputTextView;
@class TLDockBadge;
@class NSSearchField;

@interface TLMainWindowController : NSWindowController <NSSplitViewDelegate,
	TLNetworkOutlineViewDelegate, TLMessageViewDelegate, NSWindowDelegate,
	TLUserListViewDelegate, TLContextMenuActionDelegate, NSTextViewDelegate,
	NSControlTextEditingDelegate, NSTextFieldDelegate>
{
	TLoungeSession *_session;
	NSSplitView *_splitView;
	TLNetworkOutlineView *_networkOutline;
	NSView *_messagePane;
	TLMessageView *_messageView;
	NSSearchField *_searchField;
	TLUserListView *_userListView;
	TLInputTextView *_inputTextView;
	NSView *_composerBar;
	NSButton *_sendButton;
	NSTextField *_statusLabel;
	NSInteger _selectedChannelId;
	NSString *_selectedUserNick;
	BOOL _loadingHistory;
	// The stored-tab restore is tried once per connection; afterwards the
	// user's own selections win.
	BOOL _attemptedStoredChannelRestore;
	// Bounds how many history batches are fetched automatically to fill a
	// transcript shorter than the viewport; guards against a server that
	// keeps reporting more messages than it actually sends.
	NSInteger _autoHistoryBatches;
	// Reflects the total unread-message count in the Dock; nil when no Dock
	// service is reachable.
	TLDockBadge *_dockBadge;
	// Live text filter for the current channel's transcript. Non-empty, it
	// hides every message that does not contain the term, and the scroll-to-
	// top handler switches from plain history to a server-side search so the
	// bouncer's backlog is consulted too.
	NSString *_filterText;
	// Whether the bouncer may still have query matches older than what we
	// hold; drives the scroll-to-top search until a page comes back short.
	BOOL _searchHasMore;
	// Single-flight guard for in-flight server searches.
	BOOL _searchLoading;
	// Accumulated backlog search results, kept separate from channel.messages
	// so they never disturb normal history pagination; merged at render time.
	NSMutableArray *_searchResults;
	// Pagination cursor for the backlog search (the bouncer returns pages of
	// up to 100 matches keyed by this offset).
	NSInteger _searchOffset;
}

@property (nonatomic, readonly) TLoungeSession *session;
@property (nonatomic, assign) NSInteger selectedChannelId;

- (instancetype)initWithSession:(TLoungeSession *)session;
- (void)selectChannelId:(NSInteger)channelId;
- (IBAction)sendInput:(id)sender;
// Drop the Dock badge immediately; used when the application quits so no stale
// unread count remains on the icon.
- (void)clearDockBadge;

@end