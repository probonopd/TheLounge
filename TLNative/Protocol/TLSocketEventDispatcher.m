/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLSocketEventDispatcher.h"
#import "TLLogger.h"

@interface TLSocketEventDispatcher ()
{
	NSMutableDictionary<NSString *, TLEventHandler> *_handlers;
}
@end

@implementation TLSocketEventDispatcher

- (instancetype)init
{
	self = [super init];
	if (self) {
		_handlers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)registerHandler:(TLEventHandler)handler forEvent:(NSString *)eventName
{
	if (!handler || !eventName) {
		return;
	}
	_handlers[eventName] = [handler copy];
}

- (void)unregisterEvent:(NSString *)eventName
{
	[_handlers removeObjectForKey:eventName];
}

- (BOOL)hasHandlerForEvent:(NSString *)eventName
{
	return _handlers[eventName] != nil;
}

- (void)dispatchEvent:(NSString *)eventName arguments:(NSArray *)arguments
{
	TLEventHandler h = _handlers[eventName];
	if (h) {
		h(arguments ? arguments : @[]);
	}
}

@end