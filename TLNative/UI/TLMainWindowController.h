/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "TLNetworkOutlineView.h"
#import "TLMessageView.h"
#import "TLUserListView.h"

@class TLoungeSession;

@interface TLMainWindowController : NSWindowController <NSSplitViewDelegate,
	TLNetworkOutlineViewDelegate, TLMessageViewDelegate, NSWindowDelegate>
{
	TLoungeSession *_session;
	NSSplitView *_splitView;
	TLNetworkOutlineView *_networkOutline;
	TLMessageView *_messageView;
	TLUserListView *_userListView;
	NSTextField *_inputField;
	NSButton *_sendButton;
	NSTextField *_statusLabel;
	NSInteger _selectedChannelId;
	BOOL _loadingHistory;
}

@property (nonatomic, readonly) TLoungeSession *session;
@property (nonatomic, assign) NSInteger selectedChannelId;

- (instancetype)initWithSession:(TLoungeSession *)session;
- (void)selectChannelId:(NSInteger)channelId;
- (IBAction)sendInput:(id)sender;

@end