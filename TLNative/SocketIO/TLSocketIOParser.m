/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLSocketIOParser.h"
#import "TLLogger.h"

@implementation TLSocketIOParser

+ (TLSocketIOPacket *)parsePacketFromString:(NSString *)string
{
	NSUInteger length = [string length];
	if (length == 0) {
		return nil;
	}

	NSUInteger i = 0;
	unichar c = [string characterAtIndex:0];
	NSInteger type = c - '0';
	if (type < 0 || type > 6) {
		return nil;
	}

	TLSocketIOPacket *packet = [[[TLSocketIOPacket alloc] init] autorelease];
	packet.type = (TLSocketIOPacketType)type;

	// Binary attachment count.
	if (type == TLSocketIOPacketTypeBinaryEvent || type == TLSocketIOPacketTypeBinaryAck) {
		NSUInteger start = i + 1;
		BOOL found = NO;
		for (NSUInteger j = start; j < length; j++) {
			unichar dc = [string characterAtIndex:j];
			if (dc == '-') {
				i = j;
				found = YES;
				break;
			}
			if (dc < '0' || dc > '9') {
				break;
			}
		}
		if (!found) {
			return nil;
		}
	}

	// Namespace.
	BOOL hasNsp = NO;
	if (i + 1 < length && [string characterAtIndex:i + 1] == '/') {
		NSUInteger start = i + 1;
		NSUInteger j = start;
		while (j < length && [string characterAtIndex:j] != ',') {
			j++;
		}
		packet.nsp = [string substringWithRange:NSMakeRange(start, j - start)];
		i = j;
		hasNsp = YES;
	}
	if (!hasNsp) {
		packet.nsp = @"/";
	}

	// Packet id.
	if (i + 1 < length) {
		unichar n = [string characterAtIndex:i + 1];
		if (n >= '0' && n <= '9') {
			NSUInteger start = i + 1;
			NSUInteger j = start;
			while (j < length && [string characterAtIndex:j] >= '0' && [string characterAtIndex:j] <= '9') {
				j++;
			}
			packet.packetId = [[string substringWithRange:NSMakeRange(start, j - start)] integerValue];
			// Leave i at the last id digit so JSON data begins at i+1,
			// mirroring the reference socket.io-parser.
			i = j - 1;
		}
	}

	// JSON data.
	if (i + 1 < length) {
		NSString *json = [string substringFromIndex:i + 1];
		if ([json length] > 0) {
			NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
			id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
			if (payload && [self isPayloadValid:packet.type payload:payload]) {
				packet.data = payload;
			} else {
				return nil;
			}
		}
	}

	return packet;
}

+ (BOOL)isPayloadValid:(TLSocketIOPacketType)type payload:(id)payload
{
	switch (type) {
		case TLSocketIOPacketTypeConnect:
			return [payload isKindOfClass:[NSDictionary class]];
		case TLSocketIOPacketTypeDisconnect:
			return payload == nil;
		case TLSocketIOPacketTypeConnectError:
			return [payload isKindOfClass:[NSString class]] || [payload isKindOfClass:[NSDictionary class]];
		case TLSocketIOPacketTypeEvent:
		case TLSocketIOPacketTypeBinaryEvent:
		case TLSocketIOPacketTypeAck:
		case TLSocketIOPacketTypeBinaryAck:
			return [payload isKindOfClass:[NSArray class]];
	}
	return NO;
}

+ (NSString *)serializePacket:(TLSocketIOPacket *)packet
{
	NSMutableString *str = [NSMutableString stringWithFormat:@"%ld", (long)packet.type];

	if (packet.type == TLSocketIOPacketTypeBinaryEvent || packet.type == TLSocketIOPacketTypeBinaryAck) {
		[str appendFormat:@"%ld-", (long)[packet.data count]];
	}

	if (packet.nsp && ![packet.nsp isEqualToString:@"/"]) {
		[str appendFormat:@"%@,", packet.nsp];
	}

	if (packet.packetId >= 0) {
		[str appendFormat:@"%ld", (long)packet.packetId];
	}

	if (packet.data) {
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:packet.data options:0 error:NULL];
		if (jsonData) {
			[str appendString:[[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease]];
		}
	}

	return str;
}

@end