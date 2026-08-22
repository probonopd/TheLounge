/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLSocketIOPacket.h"

@implementation TLSocketIOPacket

+ (instancetype)eventPacketWithName:(NSString *)name arguments:(NSArray *)arguments
{
	TLSocketIOPacket *packet = [[[TLSocketIOPacket alloc] init] autorelease];
	packet.type = TLSocketIOPacketTypeEvent;
	packet.nsp = @"/";
	packet.packetId = -1;
	packet.data = arguments ? [@[name] arrayByAddingObjectsFromArray:arguments] : @[name];
	return packet;
}

+ (instancetype)connectPacket
{
	TLSocketIOPacket *packet = [[[TLSocketIOPacket alloc] init] autorelease];
	packet.type = TLSocketIOPacketTypeConnect;
	packet.nsp = @"/";
	packet.packetId = -1;
	return packet;
}

+ (instancetype)disconnectPacket
{
	TLSocketIOPacket *packet = [[[TLSocketIOPacket alloc] init] autorelease];
	packet.type = TLSocketIOPacketTypeDisconnect;
	packet.nsp = @"/";
	packet.packetId = -1;
	return packet;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_type = TLSocketIOPacketTypeEvent;
		_nsp = @"/";
		_packetId = -1;
		_data = nil;
	}
	return self;
}

- (NSString *)eventName
{
	if (![_data isKindOfClass:[NSArray class]] || [_data count] == 0) {
		return @"";
	}
	return [[_data objectAtIndex:0] description];
}

- (NSArray *)eventArguments
{
	if (![_data isKindOfClass:[NSArray class]] || [_data count] == 0) {
		return @[];
	}
	return [_data subarrayWithRange:NSMakeRange(1, [_data count] - 1)];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<TLSocketIOPacket type=%ld nsp=%@ id=%ld data=%@>",
		(long)_type, _nsp, (long)_packetId, _data];
}

@end