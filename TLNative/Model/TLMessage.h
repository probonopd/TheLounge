/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "TLUser.h"

typedef NS_ENUM(NSInteger, TLMessageType) {
	TLMessageTypeUnhandled,
	TLMessageTypeAction,
	TLMessageTypeAway,
	TLMessageTypeBack,
	TLMessageTypeError,
	TLMessageTypeInvite,
	TLMessageTypeJoin,
	TLMessageTypeKick,
	TLMessageTypeLogin,
	TLMessageTypeLogout,
	TLMessageTypeMessage,
	TLMessageTypeMode,
	TLMessageTypeModeChannel,
	TLMessageTypeModeUser,
	TLMessageTypeMonospaceBlock,
	TLMessageTypeNick,
	TLMessageTypeNotice,
	TLMessageTypePart,
	TLMessageTypeQuit,
	TLMessageTypeCTCP,
	TLMessageTypeCTCPRequest,
	TLMessageTypeChghost,
	TLMessageTypeTopic,
	TLMessageTypeTopicSetBy,
	TLMessageTypeWhois,
	TLMessageTypeRaw,
	TLMessageTypePlugin,
	TLMessageTypeWallops,
};

NSString *TLMessageTypeToString(TLMessageType type);
TLMessageType TLMessageTypeFromString(NSString *s);

@interface TLMessage : NSObject

@property (nonatomic, assign) NSInteger identifier;
@property (nonatomic, copy) NSString *msgid;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong) TLUser *sender;
@property (nonatomic, assign) NSInteger channelId;
@property (nonatomic, assign) TLMessageType type;
@property (nonatomic, copy) NSString *rawText;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *hostmask;
@property (nonatomic, strong) TLUser *target;
@property (nonatomic, assign) BOOL self;
@property (nonatomic, assign) BOOL highlight;
@property (nonatomic, assign) BOOL showInActive;
@property (nonatomic, copy) NSString *newNick;
@property (nonatomic, copy) NSString *newIdent;
@property (nonatomic, copy) NSString *newHost;
@property (nonatomic, copy) NSString *ctcpMessage;
@property (nonatomic, copy) NSString *command;
@property (nonatomic, assign) BOOL invitedYou;
@property (nonatomic, copy) NSString *gecos;
@property (nonatomic, assign) BOOL account;
@property (nonatomic, copy) NSArray<NSString *> *users;
@property (nonatomic, copy) NSString *statusmsgGroup;
@property (nonatomic, copy) NSArray *params;
@property (nonatomic, strong) NSMutableDictionary *metadata;
@property (nonatomic, assign) BOOL pending;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

- (BOOL)isAction;
- (BOOL)isSystemMessage;
// YES only for genuine incoming chat (PRIVMSG/ACTION from a real sender),
// i.e. messages that should bump the unread/unseen badge. Server status
// lines (connection errors, pings, "Server closed connection") arrive as
// type `message` but with no `from`, and joins/parts/quits carry a sender
// but are not conversational, so neither should count.
- (BOOL)countsAsUnseen;
// Named accessor for the wire's "self" flag; the property name collides
// with -self from NSObject.
- (BOOL)isSelf;
- (NSString *)displayText;

@end