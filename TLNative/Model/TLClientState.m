/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLClientState.h"

@implementation TLClientState

- (instancetype)init
{
	self = [super init];
	if (self) {
		_selectedNetworkUuid = @"";
		_selectedChannelId = 0;
		_authenticated = NO;
		_windowState = [[NSMutableDictionary alloc] init];
		_preferences = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)resetForNewSession
{
	_selectedNetworkUuid = @"";
	_selectedChannelId = 0;
	_authenticated = NO;
	[_windowState removeAllObjects];
}

@end