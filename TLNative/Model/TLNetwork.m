/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLNetwork.h"

@implementation TLNetwork

- (instancetype)init
{
	self = [super init];
	if (self) {
		_uuid = @"";
		_name = @"";
		_nick = @"";
		_serverOptions = [[NSDictionary alloc] init];
		_connected = NO;
		_secure = NO;
		_channels = [[NSMutableArray alloc] init];
		_metadata = [[NSMutableDictionary alloc] init];
	}
	return self;
}

static id TLObject(id value)
{
	return ([value isKindOfClass:[NSNull class]] || value == nil) ? nil : value;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
	self = [self init];
	if (self) {
		if (TLObject(dict[@"uuid"])) {
			[self setUuid:[dict[@"uuid"] description]];
		}
		if (TLObject(dict[@"name"])) {
			[self setName:[dict[@"name"] description]];
		}
		if (TLObject(dict[@"nick"])) {
			[self setNick:[dict[@"nick"] description]];
		}
		if (TLObject(dict[@"serverOptions"])) {
			[self setServerOptions:dict[@"serverOptions"]];
		}
		if (TLObject(dict[@"status"])) {
			NSDictionary *status = dict[@"status"];
			if (status[@"connected"]) {
				_connected = [status[@"connected"] boolValue];
			}
			if (status[@"secure"]) {
				_secure = [status[@"secure"] boolValue];
			}
		}
		if (dict[@"channels"] && [dict[@"channels"] isKindOfClass:[NSArray class]]) {
			for (id c in dict[@"channels"]) {
				if ([c isKindOfClass:[NSDictionary class]]) {
					[_channels addObject:[[[TLChannel alloc] initWithDictionary:c] autorelease]];
				}
			}
		}
		NSArray *known = @[@"uuid", @"name", @"nick", @"serverOptions", @"status", @"channels"];
		NSMutableDictionary *rest = [dict mutableCopy];
		[rest removeObjectsForKeys:known];
		[_metadata release];
		_metadata = rest;
	}
	return self;
}

- (TLChannel *)channelWithIdentifier:(NSInteger)identifier
{
	for (TLChannel *c in _channels) {
		if (c.identifier == identifier) {
			return c;
		}
	}
	return nil;
}

- (TLChannel *)channelWithName:(NSString *)name
{
	NSString *lower = [name lowercaseString];
	for (TLChannel *c in _channels) {
		if ([c.name.lowercaseString isEqualToString:lower]) {
			return c;
		}
	}
	return nil;
}

- (void)addChannel:(TLChannel *)channel
{
	TLChannel *existing = [self channelWithIdentifier:channel.identifier];
	if (existing) {
		NSInteger idx = [_channels indexOfObject:existing];
		[_channels replaceObjectAtIndex:idx withObject:channel];
		return;
	}
	[_channels addObject:channel];
}

- (void)removeChannelWithIdentifier:(NSInteger)identifier
{
	TLChannel *existing = [self channelWithIdentifier:identifier];
	if (existing) {
		[_channels removeObject:existing];
	}
}

- (TLChannel *)lobby
{
	for (TLChannel *c in _channels) {
		if (c.isLobby) {
			return c;
		}
	}
	return nil;
}

- (NSInteger)badgeTotal
{
	NSInteger total = 0;
	TLChannel *lobbyChannel = [self lobby];
	if (lobbyChannel != nil) {
		total += [lobbyChannel unseen];
	}
	for (TLChannel *channel in _channels) {
		total += [channel badgeCount];
	}
	return total;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<TLNetwork %@ %@ (%lu channels)>", _uuid, _name,
		(unsigned long)[_channels count]];
}

@end