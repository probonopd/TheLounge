/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLNetworkOutlineView;
@class TLServerState;

@protocol TLNetworkOutlineViewDelegate <NSObject>
- (void)networkOutlineView:(TLNetworkOutlineView *)outline didSelectChannelId:(NSInteger)channelId;
@optional
// Returned menu is popped up at the mouse; item is a TLNetwork or TLChannel.
- (NSMenu *)networkOutlineView:(TLNetworkOutlineView *)outline contextMenuForRowItem:(id)item;
@end

// The GNUstep data source/delegate protocols do not mark their optional
// methods as optional, so conformance is not declared here; the required
// methods are implemented in the class.
@interface TLNetworkOutlineView : NSView
{
	NSScrollView *_scrollView;
	NSOutlineView *_outlineView;
	TLServerState *_serverState;
	NSInteger _selectedChannelId;
	BOOL _selectedItemIsNetworkRow;
	id<TLNetworkOutlineViewDelegate> _delegate;
}

@property (nonatomic, assign) id<TLNetworkOutlineViewDelegate> delegate;
@property (nonatomic, retain) TLServerState *serverState;
@property (nonatomic, assign) NSInteger selectedChannelId;

- (void)reloadData;
- (void)selectChannelId:(NSInteger)channelId;

@end