/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLEngineIOPacket.h"

NSString *TLEngineIOPacketTypeToChar(TLEngineIOPacketType type)
{
	switch (type) {
		case TLEngineIOPacketTypeOpen:
			return @"0";
		case TLEngineIOPacketTypeClose:
			return @"1";
		case TLEngineIOPacketTypePing:
			return @"2";
		case TLEngineIOPacketTypePong:
			return @"3";
		case TLEngineIOPacketTypeMessage:
			return @"4";
		case TLEngineIOPacketTypeUpgrade:
			return @"5";
		case TLEngineIOPacketTypeNoop:
			return @"6";
	}
	return @"?";
}

@implementation TLEngineIOPacket

+ (instancetype)packetWithType:(TLEngineIOPacketType)type data:(NSString *)data
{
	TLEngineIOPacket *packet = [[[TLEngineIOPacket alloc] init] autorelease];
	packet.type = type;
	packet.data = data ? data : @"";
	return packet;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_type = TLEngineIOPacketTypeNoop;
		_data = @"";
	}
	return self;
}

- (NSString *)serialized
{
	return [NSString stringWithFormat:@"%@%@", TLEngineIOPacketTypeToChar(_type), _data];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<TLEngineIOPacket %@ %@>", TLEngineIOPacketTypeToChar(_type), _data];
}

@end