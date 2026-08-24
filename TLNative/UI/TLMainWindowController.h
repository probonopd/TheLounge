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

@interface TLMainWindowController : NSWindowController <NSSplitViewDelegate,
	TLNetworkOutlineViewDelegate, TLMessageViewDelegate, NSWindowDelegate,
	TLUserListViewDelegate, TLContextMenuActionDelegate, NSTextViewDelegate>
{
	TLoungeSession *_session;
	NSSplitView *_splitView;
	TLNetworkOutlineView *_networkOutline;
	TLMessageView *_messageView;
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
}

@property (nonatomic, readonly) TLoungeSession *session;
@property (nonatomic, assign) NSInteger selectedChannelId;

- (instancetype)initWithSession:(TLoungeSession *)session;
- (void)selectChannelId:(NSInteger)channelId;
- (IBAction)sendInput:(id)sender;

@end