/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TLSocketIOPacketType) {
	TLSocketIOPacketTypeConnect = 0,
	TLSocketIOPacketTypeDisconnect = 1,
	TLSocketIOPacketTypeEvent = 2,
	TLSocketIOPacketTypeAck = 3,
	TLSocketIOPacketTypeConnectError = 4,
	TLSocketIOPacketTypeBinaryEvent = 5,
	TLSocketIOPacketTypeBinaryAck = 6,
};

@interface TLSocketIOPacket : NSObject

@property (nonatomic, assign) TLSocketIOPacketType type;
@property (nonatomic, copy) NSString *nsp;
@property (nonatomic, assign) NSInteger packetId;
@property (nonatomic, strong) id data;

+ (instancetype)eventPacketWithName:(NSString *)name arguments:(NSArray *)arguments;
+ (instancetype)connectPacket;
+ (instancetype)disconnectPacket;

- (NSString *)eventName;
- (NSArray *)eventArguments;

@end