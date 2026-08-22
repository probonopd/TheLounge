/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLChannel.h"

static NSDictionary *TLChannelTypeMap(void)
{
	static NSDictionary *map;
	if (!map) {
		// The static outlives the creating autorelease pool, so it must
		// own its reference (an autoreased literal would dangle).
		map = [@{
			@"channel": @(TLChannelTypeChannel),
			@"lobby": @(TLChannelTypeLobby),
			@"query": @(TLChannelTypeQuery),
			@"special": @(TLChannelTypeSpecial),
		} retain];
	}
	return map;
}

NSString *TLChannelTypeToString(TLChannelType type)
{
	for (NSString *key in TLChannelTypeMap()) {
		if ([[TLChannelTypeMap() objectForKey:key] integerValue] == type) {
			return key;
		}
	}
	return @"channel";
}

TLChannelType TLChannelTypeFromString(NSString *s)
{
	NSNumber *n = [TLChannelTypeMap() objectForKey:s ? s : @"channel"];
	return n ? [n integerValue] : TLChannelTypeChannel;
}

@implementation TLChannel

- (instancetype)init
{
	self = [super init];
	if (self) {
		_identifier = 0;
		_name = @"";
		_type = TLChannelTypeChannel;
		_topic = @"";
		_key = @"";
		_unread = 0;
		_highlight = 0;
		_firstUnread = 0;
		_muted = NO;
		_state = TLChannelStateParted;
		_specialType = @"";
		_data = nil;
		_closed = NO;
		_numUsers = 0;
		_totalMessages = 0;
		_messages = [[NSMutableArray alloc] init];
		_users = [[NSMutableDictionary alloc] init];
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
		if (dict[@"id"]) {
			_identifier = [dict[@"id"] integerValue];
		}
		if (TLObject(dict[@"name"])) {
			[self setName:[dict[@"name"] description]];
		}
		if (TLObject(dict[@"type"])) {
			_type = TLChannelTypeFromString([dict[@"type"] description]);
		}
		if (TLObject(dict[@"topic"])) {
			[self setTopic:[dict[@"topic"] description]];
		}
		if (TLObject(dict[@"key"])) {
			[self setKey:[dict[@"key"] description]];
		}
		if (dict[@"unread"]) {
			_unread = [dict[@"unread"] integerValue];
		}
		if (dict[@"highlight"]) {
			_highlight = [dict[@"highlight"] integerValue];
		}
		if (dict[@"firstUnread"]) {
			_firstUnread = [dict[@"firstUnread"] integerValue];
		}
		if (dict[@"muted"]) {
			_muted = [dict[@"muted"] boolValue];
		}
		if (dict[@"state"]) {
			_state = [dict[@"state"] integerValue];
		}
		if (TLObject(dict[@"special"])) {
			[self setSpecialType:[dict[@"special"] description]];
		}
		if (TLObject(dict[@"data"])) {
			[self setData:dict[@"data"]];
		}
		if (dict[@"closed"]) {
			_closed = [dict[@"closed"] boolValue];
		}
		if (dict[@"num_users"]) {
			_numUsers = [dict[@"num_users"] integerValue];
		}
		if (dict[@"totalMessages"]) {
			_totalMessages = [dict[@"totalMessages"] integerValue];
		}
		if (dict[@"messages"] && [dict[@"messages"] isKindOfClass:[NSArray class]]) {
			for (id m in dict[@"messages"]) {
				if ([m isKindOfClass:[NSDictionary class]]) {
					[_messages addObject:[[[TLMessage alloc] initWithDictionary:m] autorelease]];
				}
			}
		}
		NSArray *known = @[
			@"id", @"name", @"type", @"topic", @"key", @"unread", @"highlight",
			@"firstUnread", @"muted", @"state", @"special", @"data", @"closed",
			@"num_users", @"totalMessages", @"messages"
		];
		NSMutableDictionary *rest = [dict mutableCopy];
		[rest removeObjectsForKeys:known];
		[_metadata release];
		_metadata = rest;
	}
	return self;
}

- (TLUser *)userWithNick:(NSString *)nick
{
	return _users[[nick lowercaseString]];
}

- (void)addUser:(TLUser *)user
{
	if (!user.nick) {
		return;
	}
	_users[[user.nick lowercaseString]] = user;
}

- (void)removeUserWithNick:(NSString *)nick
{
	[_users removeObjectForKey:[nick lowercaseString]];
}

- (NSArray<TLUser *> *)sortedUsers
{
	NSArray *all = [_users allValues];
	NSArray *modesOrder = @[@"o", @"v", @"h", @"q", @"a"];
	NSMutableArray *arr = [all sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
		TLUser *ua = a;
		TLUser *ub = b;
		NSInteger ia = [modesOrder indexOfObject:ua.mode];
		NSInteger ib = [modesOrder indexOfObject:ub.mode];
		if (ia == NSNotFound) {
			ia = [modesOrder count];
		}
		if (ib == NSNotFound) {
			ib = [modesOrder count];
		}
		if (ia != ib) {
			return ia < ib ? NSOrderedAscending : NSOrderedDescending;
		}
		return [ua.nick localizedCaseInsensitiveCompare:ub.nick];
	}].mutableCopy;
	return arr;
}

- (TLMessage *)messageWithIdentifier:(NSInteger)identifier
{
	for (TLMessage *m in _messages) {
		if (m.identifier == identifier) {
			return m;
		}
	}
	return nil;
}

- (void)addMessage:(TLMessage *)message
{
	TLMessage *existing = [self messageWithIdentifier:message.identifier];
	if (existing) {
		NSInteger idx = [_messages indexOfObject:existing];
		[_messages replaceObjectAtIndex:idx withObject:message];
		return;
	}
	[_messages addObject:message];
}

- (void)removeMessageWithIdentifier:(NSInteger)identifier
{
	TLMessage *existing = [self messageWithIdentifier:identifier];
	if (existing) {
		[_messages removeObject:existing];
	}
}

- (void)prependMessages:(NSArray<TLMessage *> *)messages
{
	NSMutableArray *newMessages = [[NSMutableArray alloc] init];
	for (TLMessage *m in messages) {
		TLMessage *existing = [self messageWithIdentifier:m.identifier];
		if (!existing) {
			[newMessages addObject:m];
		}
	}
	[newMessages addObjectsFromArray:_messages];
	[_messages release];
	_messages = newMessages;
}

- (BOOL)isChannel
{
	return _type == TLChannelTypeChannel;
}

- (BOOL)isQuery
{
	return _type == TLChannelTypeQuery;
}

- (BOOL)isLobby
{
	return _type == TLChannelTypeLobby;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<TLChannel %ld %@ (%@)>", (long)_identifier, _name,
		TLChannelTypeToString(_type)];
}

@end