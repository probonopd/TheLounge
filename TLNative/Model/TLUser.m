/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLUser.h"

@implementation TLUser

- (instancetype)init
{
	self = [super init];
	if (self) {
		_nick = @"";
		_username = @"";
		_hostname = @"";
		_away = @"";
		_modes = [[NSArray alloc] init];
		_mode = @"";
		_lastMessage = 0;
		_metadata = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
	self = [self init];
	if (self) {
		if (dict[@"nick"] && ![dict[@"nick"] isKindOfClass:[NSNull class]]) {
			[self setNick:[dict[@"nick"] description]];
		}
		if (dict[@"username"] && ![dict[@"username"] isKindOfClass:[NSNull class]]) {
			[self setUsername:[dict[@"username"] description]];
		}
		if (dict[@"hostname"] && ![dict[@"hostname"] isKindOfClass:[NSNull class]]) {
			[self setHostname:[dict[@"hostname"] description]];
		}
		if (dict[@"away"] && ![dict[@"away"] isKindOfClass:[NSNull class]]) {
			[self setAway:[dict[@"away"] description]];
		}
		if (dict[@"mode"] && ![dict[@"mode"] isKindOfClass:[NSNull class]]) {
			[self setMode:[dict[@"mode"] description]];
		}
		if (dict[@"modes"] && [dict[@"modes"] isKindOfClass:[NSArray class]]) {
			NSMutableArray *ms = [[NSMutableArray alloc] init];
			for (id m in dict[@"modes"]) {
				[ms addObject:[m description]];
			}
			_modes = ms;
		}
		if (dict[@"lastMessage"]) {
			_lastMessage = [dict[@"lastMessage"] integerValue];
		}
		// Unknown fields are retained so later protocol versions stay harmless.
		NSMutableDictionary *rest = [dict mutableCopy];
		[rest removeObjectsForKeys:@[@"nick", @"username", @"hostname", @"away", @"mode",
			@"modes", @"lastMessage"]];
		[_metadata release];
		_metadata = rest;
	}
	return self;
}

- (BOOL)isOperator
{
	if ([_mode isEqualToString:@"o"]) {
		return YES;
	}
	return [_modes containsObject:@"o"];
}

- (BOOL)isVoice
{
	if ([_mode isEqualToString:@"v"]) {
		return YES;
	}
	return [_modes containsObject:@"v"];
}

- (NSString *)fullPrefix
{
	if ([self isOperator]) {
		return @"@";
	}
	if ([self isVoice]) {
		return @"+";
	}
	return @"";
}

- (NSString *)lowercaseNick
{
	return [_nick lowercaseString];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<TLUser %@>", _nick];
}

@end