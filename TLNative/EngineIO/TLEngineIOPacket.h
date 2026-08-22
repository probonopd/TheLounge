/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TLEngineIOPacketType) {
	TLEngineIOPacketTypeOpen = 0,
	TLEngineIOPacketTypeClose = 1,
	TLEngineIOPacketTypePing = 2,
	TLEngineIOPacketTypePong = 3,
	TLEngineIOPacketTypeMessage = 4,
	TLEngineIOPacketTypeUpgrade = 5,
	TLEngineIOPacketTypeNoop = 6,
};

NSString *TLEngineIOPacketTypeToChar(TLEngineIOPacketType type);

@interface TLEngineIOPacket : NSObject

@property (nonatomic, assign) TLEngineIOPacketType type;
@property (nonatomic, copy) NSString *data;

+ (instancetype)packetWithType:(TLEngineIOPacketType)type data:(NSString *)data;

- (NSString *)serialized;

@end