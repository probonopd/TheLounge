/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "TLChannel.h"
#import "TLNetwork.h"
#import "TLUser.h"

@class TLContextMenuBuilder;

// Receives the concrete actions behind context-menu items; implemented by
// the main window controller, which owns the session.
@protocol TLContextMenuActionDelegate <NSObject>
- (void)contextMenuSwitchToChannelId:(NSInteger)channelId;
- (void)contextMenuRunCommand:(NSString *)command onChannelId:(NSInteger)channelId;
- (void)contextMenuSetMuted:(BOOL)muted forChannelId:(NSInteger)channelId;
- (void)contextMenuClearHistoryForChannelId:(NSInteger)channelId;
- (void)contextMenuCloseChannelId:(NSInteger)channelId isLobby:(BOOL)isLobby;
- (void)contextMenuJoinPromptForLobbyId:(NSInteger)lobbyId;
- (void)contextMenuEditTopicForChannelId:(NSInteger)channelId;
- (void)contextMenuForgetNetworkForChannelId:(NSInteger)channelId;
@end

@interface TLContextMenuBuilder : NSObject

// Mirrors the web client's prefix-rank comparison used to gate the mode
// actions in the user menu: "~@" act on their own rank or below, everyone
// else strictly below.
+ (BOOL)mode:(NSString *)p1 canActOnMode:(NSString *)p2
	inSymbols:(NSArray<NSString *> *)symbols;

// "network", "channel", or "conversation" - used by the Mute labels.
+ (NSString *)humanTypeNameForChannel:(TLChannel *)channel;

+ (NSMenu *)channelMenuForChannel:(TLChannel *)channel
	network:(TLNetwork *)network
	myNick:(NSString *)myNick
	delegate:(id<TLContextMenuActionDelegate>)delegate;

+ (NSMenu *)userMenuForUser:(TLUser *)user
	channel:(TLChannel *)channel
	network:(TLNetwork *)network
	myNick:(NSString *)myNick
	delegate:(id<TLContextMenuActionDelegate>)delegate;

@end
