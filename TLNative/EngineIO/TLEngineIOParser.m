/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLEngineIOParser.h"

@implementation TLEngineIOParser

+ (TLEngineIOPacket *)parsePacketFromString:(NSString *)string
{
	if ([string length] == 0) {
		return nil;
	}
	unichar first = [string characterAtIndex:0];
	NSInteger type = first - '0';
	if (type < 0 || type > 6) {
		return nil;
	}
	NSString *data = [string length] > 1 ? [string substringFromIndex:1] : @"";
	return [TLEngineIOPacket packetWithType:(TLEngineIOPacketType)type data:data];
}

+ (NSString *)serializePacket:(TLEngineIOPacket *)packet
{
	return [packet serialized];
}

@end