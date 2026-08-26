/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "TLMessage.h"
#import "TLUser.h"

typedef NS_ENUM(NSInteger, TLChannelType) {
	TLChannelTypeChannel,
	TLChannelTypeLobby,
	TLChannelTypeQuery,
	TLChannelTypeSpecial,
};

typedef NS_ENUM(NSInteger, TLChannelState) {
	TLChannelStateParted = 0,
	TLChannelStateJoined = 1,
};

NSString *TLChannelTypeToString(TLChannelType type);
TLChannelType TLChannelTypeFromString(NSString *s);

@interface TLChannel : NSObject

@property (nonatomic, assign) NSInteger identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) TLChannelType type;
@property (nonatomic, copy) NSString *topic;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) NSInteger unread;
@property (nonatomic, assign) NSInteger highlight;
// Client-side "not yet seen by the user" counts, independent of the bouncer's
// unread (which the server freezes at 0 for the open channel). These grow for
// every message the user has not looked at - including the active channel
// while the window is hidden - and are cleared when the channel is viewed.
@property (nonatomic, assign) NSInteger unseen;
@property (nonatomic, assign) NSInteger unseenHighlight;
@property (nonatomic, assign) NSInteger firstUnread;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) TLChannelState state;
@property (nonatomic, copy) NSString *specialType;
@property (nonatomic, strong) id data;
@property (nonatomic, assign) BOOL closed;
@property (nonatomic, assign) NSInteger numUsers;
@property (nonatomic, assign) NSInteger totalMessages;
@property (nonatomic, strong) NSMutableArray<TLMessage *> *messages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TLUser *> *users;
@property (nonatomic, strong) NSMutableDictionary *metadata;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

- (TLUser *)userWithNick:(NSString *)nick;
// The one user whose nick starts with the prefix (case-insensitive); nil
// when no user or more than one user matches.
- (TLUser *)uniqueUserWithNickPrefix:(NSString *)prefix;
- (void)addUser:(TLUser *)user;
- (void)removeUserWithNick:(NSString *)nick;
- (NSArray<TLUser *> *)sortedUsers;

- (TLMessage *)messageWithIdentifier:(NSInteger)identifier;
- (void)addMessage:(TLMessage *)message;
- (void)removeMessageWithIdentifier:(NSInteger)identifier;
- (void)prependMessages:(NSArray<TLMessage *> *)messages;

- (BOOL)isChannel;
- (BOOL)isQuery;
- (BOOL)isLobby;

@end