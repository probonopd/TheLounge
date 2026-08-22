/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLServerState.h"

@implementation TLServerState

- (instancetype)init
{
	self = [super init];
	if (self) {
		_networks = [[NSMutableArray alloc] init];
		_activeChannelId = 0;
		_currentUserNick = @"";
		// alloc is pool-independent: the retain setter will release
		// exactly what we own here (autoreleased literals would be
		// over-released by the setter while the pool still owns them).
		_serverConfiguration = [[NSDictionary alloc] init];
		_metadata = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (instancetype)initWithInitPayload:(NSDictionary *)payload
{
	self = [self init];
	if (self) {
		if (payload[@"active"]) {
			_activeChannelId = [payload[@"active"] integerValue];
		}
		if (payload[@"networks"] && [payload[@"networks"] isKindOfClass:[NSArray class]]) {
			for (id n in payload[@"networks"]) {
				if ([n isKindOfClass:[NSDictionary class]]) {
					[_networks addObject:[[[TLNetwork alloc] initWithDictionary:n] autorelease]];
				}
			}
		}
		NSArray *known = @[@"active", @"networks", @"token"];
		NSMutableDictionary *rest = [payload mutableCopy];
		[rest removeObjectsForKeys:known];
		[_metadata release];
		_metadata = rest;
	}
	return self;
}

- (TLNetwork *)networkWithUuid:(NSString *)uuid
{
	for (TLNetwork *n in _networks) {
		if ([n.uuid isEqualToString:uuid]) {
			return n;
		}
	}
	return nil;
}

- (void)addNetwork:(TLNetwork *)network
{
	TLNetwork *existing = [self networkWithUuid:network.uuid];
	if (existing) {
		NSInteger idx = [_networks indexOfObject:existing];
		[_networks replaceObjectAtIndex:idx withObject:network];
		return;
	}
	[_networks addObject:network];
}

- (void)removeNetworkWithUuid:(NSString *)uuid
{
	TLNetwork *existing = [self networkWithUuid:uuid];
	if (existing) {
		[_networks removeObject:existing];
	}
}

- (TLChannel *)channelWithIdentifier:(NSInteger)identifier
{
	for (TLNetwork *n in _networks) {
		TLChannel *c = [n channelWithIdentifier:identifier];
		if (c) {
			return c;
		}
	}
	return nil;
}

- (TLNetwork *)networkContainingChannel:(NSInteger)identifier
{
	for (TLNetwork *n in _networks) {
		if ([n channelWithIdentifier:identifier]) {
			return n;
		}
	}
	return nil;
}

- (void)clear
{
	[_networks removeAllObjects];
	_activeChannelId = 0;
	_currentUserNick = @"";
	[_serverConfiguration release];
	_serverConfiguration = [[NSDictionary alloc] init];
	[_metadata removeAllObjects];
}

@end