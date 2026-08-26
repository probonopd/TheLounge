/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLDockBadge.h"

#import <Foundation/NSConnection.h>
#import <Foundation/NSDistantObject.h>

// The Dock service registers itself under this well-known name. Kept as a
// local constant because we do not link the workspace that defines it.
static NSString * const TLDockServiceName = @"DockIcon";

@implementation TLDockBadge
{
	id<DockService> _proxy;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		// The Dock is a separate process; resolve its distributed-object
		// endpoint once and keep the proxy. If no Dock is running the
		// connection fails and the badge simply stays inert.
		NSConnection *conn = [NSConnection
			connectionWithRegisteredName:TLDockServiceName host:nil];
		if (conn) {
			NSDistantObject *root = (NSDistantObject *)[conn rootProxy];
			[root setProtocolForProxy:@protocol(DockService)];
			_proxy = (id<DockService>)[root retain];
		}
	}
	return self;
}

- (void)dealloc
{
	[_proxy release];
	[super dealloc];
}

- (void)updateWithUnreadCount:(NSInteger)count
{
	if (!_proxy) {
		return;
	}
	int64_t badge = (int64_t)(count > 0 ? count : 0);
	[_proxy setBadgeCount:badge];
	[_proxy setCountVisible:(badge > 0)];
}

@end
