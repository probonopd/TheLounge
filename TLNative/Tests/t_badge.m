/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "TLNetwork.h"
#import "TLChannel.h"
#import "TLServerState.h"

static TLChannel *mk(NSInteger ident, NSString *name, TLChannelType type, NSInteger unseen, BOOL muted, TLChannelState st, BOOL closed)
{
	TLChannel *c = [[TLChannel alloc] initWithDictionary:@{
		@"id": @(ident), @"name": name, @"type": TLChannelTypeToString(type)}];
	c.unseen = unseen;
	c.unseenHighlight = 0;
	c.muted = muted;
	c.closed = closed;
	c.state = st;
	return c;
}

// Dock sum over the model (what -[TLNetwork badgeTotal] feeds the Dock).
static NSInteger dockSum(TLServerState *state)
{
	NSInteger total = 0;
	for (TLNetwork *net in state.networks) total += [net badgeTotal];
	return total;
}

// Pane sum: network row shows badgeTotal minus the VISIBLE channel badges
// (hidden/parted channels roll up into the network row), and visible channel
// rows show their own badge.
static NSInteger paneSum(TLServerState *state, BOOL expanded, NSArray *(^visible)(TLNetwork *))
{
	NSInteger pane = 0;
	for (TLNetwork *net in state.networks) {
		NSInteger total = [net badgeTotal];
		NSInteger perChannel = 0;
		if (expanded) {
			for (TLChannel *c in visible(net)) perChannel += [c badgeCount];
		}
		pane += (total - perChannel);
		if (expanded) {
			for (TLChannel *c in visible(net)) pane += [c badgeCount];
		}
	}
	return pane;
}

int main(void)
{
	@autoreleasepool {
		TLServerState *state = [[TLServerState alloc] init];
		TLNetwork *net = [[TLNetwork alloc] initWithDictionary:@{@"id": @"u1", @"name": @"NetOne"}];
		// lobby (server) unread=2, two joined channels, one PARTED channel
		// with unread=18 (hidden from the outline), one muted (unread=5).
		[net addChannel:mk(1, @"Server", TLChannelTypeLobby, 2, NO, TLChannelStateJoined, NO)];
		[net addChannel:mk(2, @"#big", TLChannelTypeChannel, 70, NO, TLChannelStateJoined, NO)];
		[net addChannel:mk(3, @"#small", TLChannelTypeChannel, 1, NO, TLChannelStateJoined, NO)];
		[net addChannel:mk(4, @"#parted", TLChannelTypeChannel, 18, NO, TLChannelStateParted, NO)];
		[net addChannel:mk(5, @"#muted", TLChannelTypeChannel, 5, YES, TLChannelStateJoined, NO)];
		[state addNetwork:net];

		// Visible == joined && !closed (matches visibleChannelsForNetwork).
		NSArray *(^visible)(TLNetwork *) = ^NSArray *(TLNetwork *n) {
			NSMutableArray *r = [NSMutableArray array];
			for (TLChannel *c in n.channels)
				if (c.state == TLChannelStateJoined && !c.closed) [r addObject:c];
			return r;
		};

		NSInteger dock = dockSum(state);
		NSInteger pane = paneSum(state, YES, visible);

		NSLog(@"dock=%ld paneExpanded=%ld", (long)dock, (long)pane);
		NSLog(@"badgeTotal=%ld (lobby2 + big70 + small1 + parted18 + muted0)", (long)[net badgeTotal]);

		if (dock == pane) { NSLog(@"PASS"); return 0; }
		NSLog(@"FAIL: dock != pane"); return 1;
	}
}
