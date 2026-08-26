/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeProtocol_4_5.h"
#import "TLServerState.h"
#import "TLClientState.h"
#import "TLNetwork.h"
#import "TLChannel.h"
#import "TLMessage.h"
#import "TLUser.h"
#import "TLSocketIOClient.h"
#import "TLSocketEventDispatcher.h"
#import "TLLogger.h"

// Forward declaration; defined near reconcileChannel below.
static void TLSeedUnseenFromMessages(TLChannel *channel);

@implementation TLoungeProtocol_4_5

- (void)registerEventHandlers
{
	__block TLoungeProtocol_4_5 *weakSelf = self;

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		NSNumber *serverHash = [args count] > 0 ? args[0] : nil;
		if ([self.delegate respondsToSelector:@selector(protocol:didReceiveAuthStart:)]) {
			[self.delegate protocol:self didReceiveAuthStart:serverHash];
		}
		[self performAuthentication];
	} forEvent:@"auth:start"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self setAuthenticated:YES];
		if ([self.delegate respondsToSelector:@selector(protocolDidAuthenticate:)]) {
			[self.delegate protocolDidAuthenticate:self];
		}
	} forEvent:@"auth:success"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self setAuthenticated:NO];
		NSError *error = [NSError errorWithDomain:@"TLLoungeAuthErrorDomain"
			code:100
			userInfo:@{NSLocalizedDescriptionKey: @"Authentication failed"}];
		if ([self.delegate respondsToSelector:@selector(protocol:authenticationFailedWithError:)]) {
			[self.delegate protocol:self authenticationFailedWithError:error];
		}
	} forEvent:@"auth:failed"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		if ([args count] > 0 && [args[0] isKindOfClass:[NSDictionary class]]) {
			self.serverState.serverConfiguration = args[0];
		}
	} forEvent:@"configuration"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleInitEvent:args];
	} forEvent:@"init"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		if ([args count] > 0) {
			self.serverState.metadata[@"commands"] = args[0];
		}
	} forEvent:@"commands"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleMessageEvent:args];
	} forEvent:@"msg"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleMoreEvent:args];
	} forEvent:@"more"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNamesEvent:args];
	} forEvent:@"names"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleUsersEvent:args];
	} forEvent:@"users"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNetworkEvent:args];
	} forEvent:@"network"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNetworkOptionsEvent:args];
	} forEvent:@"network:options"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNetworkStatusEvent:args];
	} forEvent:@"network:status"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNetworkNameEvent:args];
	} forEvent:@"network:name"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNickEvent:args];
	} forEvent:@"nick"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		if ([args count] > 0) {
			self.serverState.activeChannelId = [args[0] integerValue];
		}
	} forEvent:@"open"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleJoinEvent:args];
	} forEvent:@"join"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handlePartEvent:args];
	} forEvent:@"part"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleQuitEvent:args];
	} forEvent:@"quit"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleTopicEvent:args];
	} forEvent:@"topic"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleChannelStateEvent:args];
	} forEvent:@"channel:state"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleMuteChangedEvent:args];
	} forEvent:@"mute:changed"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleHistoryClearEvent:args];
	} forEvent:@"history:clear"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleSyncSortNetworksEvent:args];
	} forEvent:@"sync_sort:networks"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleSyncSortChannelsEvent:args];
	} forEvent:@"sync_sort:channels"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		NSError *error = [NSError errorWithDomain:@"TLLoungeServerErrorDomain"
			code:101
			userInfo:@{NSLocalizedDescriptionKey: args.count ? [args[0] description] : @"Server error"}];
		if ([self.delegate respondsToSelector:@selector(protocol:didFailWithError:)]) {
			[self.delegate protocol:self didFailWithError:error];
		}
	} forEvent:@"error"];
}

- (void)performAuthentication
{
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];

	NSString *pw = self.pendingPassword;

	if ([pw length] > 0) {
		NSString *u = self.pendingUsername;
		if (u) { payload[@"user"] = u; }
		payload[@"password"] = pw;
	} else {
		NSString *tok = self.pendingToken;
		if ([tok length] > 0) {
			NSString *u = self.pendingUsername;
			if (u) { payload[@"user"] = u; }
			payload[@"token"] = tok;
			payload[@"lastMessage"] = @([self highestKnownMessageId]);
			payload[@"openChannel"] = self.clientState.selectedChannelId > 0
				? @(self.clientState.selectedChannelId)
				: [NSNull null];
			payload[@"hasConfig"] = @([self.serverState.serverConfiguration count] > 0);
		}
	}

	[[TLLogger sharedLogger] debug:@"auth:perform %@",
		[TLLogger redactSensitiveString:[payload description]]];
	[self.socketClient emitEvent:@"auth:perform" withArguments:@[payload]];
}

- (NSInteger)highestKnownMessageId
{
	NSInteger highest = -1;
	for (TLNetwork *network in self.serverState.networks) {
		for (TLChannel *channel in network.channels) {
			for (TLMessage *message in channel.messages) {
				if (message.identifier > highest) {
					highest = message.identifier;
				}
			}
		}
	}
	return highest;
}

- (void)handleInitEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];

	[[TLLogger sharedLogger] debug:@"[RX] INIT: parsing payload (%lu keys)",
		(unsigned long)[payload count]];

	TLServerState *newState = [[[TLServerState alloc] initWithInitPayload:payload] autorelease];

	if (payload[@"token"]) {
		newState.metadata[@"token"] = payload[@"token"];
	}

	if ([self.serverState.networks count] == 0) {
		// First connection: build a fresh state.
		self.serverState.networks = newState.networks;
		// Seed unseen from genuinely unread chat, excluding the bouncer's
		// over-counting of technical/server status lines.
		for (TLNetwork *network in self.serverState.networks) {
			for (TLChannel *channel in network.channels) {
				TLSeedUnseenFromMessages(channel);
			}
		}
	} else {
		// Reconnection: reconcile the incoming state with the existing local
		// model so no messages, channels or networks are lost or duplicated.
		[self reconcileWithState:newState];
	}

	self.serverState.activeChannelId = newState.activeChannelId;
	self.serverState.serverConfiguration = newState.serverConfiguration.count
		? newState.serverConfiguration
		: self.serverState.serverConfiguration;

	// Retain any session token for fast re-authentication after reconnect.
	if (newState.metadata[@"token"]) {
		self.serverState.metadata[@"token"] = newState.metadata[@"token"];
		// Promote the fresh token over the login credentials so the next
		// auth:perform resumes the session (token + lastMessage) instead
		// of replaying the raw password.
		[self adoptSessionToken:newState.metadata[@"token"]];
	}

	[self updateCurrentUserNick];

	[self setReady:YES];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];

	if ([self.delegate respondsToSelector:@selector(protocolDidBecomeReady:)]) {
		[self.delegate protocolDidBecomeReady:self];
	}
}

- (void)updateCurrentUserNick
{
	for (TLNetwork *network in self.serverState.networks) {
		if ([network.nick length] > 0) {
			self.serverState.currentUserNick = network.nick;
			return;
		}
	}
}

- (void)reconcileWithState:(TLServerState *)incoming
{
	// Merge networks that exist locally, add networks that are new.
	for (TLNetwork *newNetwork in incoming.networks) {
		TLNetwork *existing = [self.serverState networkWithUuid:newNetwork.uuid];
		if (existing) {
			[self reconcileNetwork:newNetwork into:existing];
		} else {
			[self.serverState addNetwork:newNetwork];
		}
	}

	// Remove networks the server no longer knows about.
	NSMutableArray *toRemove = [NSMutableArray array];
	for (TLNetwork *existing in self.serverState.networks) {
		if (![incoming networkWithUuid:existing.uuid]) {
			[toRemove addObject:existing.uuid];
		}
	}
	for (NSString *uuid in toRemove) {
		[self.serverState removeNetworkWithUuid:uuid];
	}
}

- (void)reconcileNetwork:(TLNetwork *)newNetwork into:(TLNetwork *)existing
{
	existing.name = newNetwork.name;
	if ([newNetwork.nick length] > 0) {
		existing.nick = newNetwork.nick;
	}
	if (newNetwork.serverOptions) {
		existing.serverOptions = newNetwork.serverOptions;
	}
	existing.connected = newNetwork.connected;
	existing.secure = newNetwork.secure;

	// Merge channels.
	for (TLChannel *newChannel in newNetwork.channels) {
		TLChannel *existingChannel = [existing channelWithIdentifier:newChannel.identifier];
		if (existingChannel) {
			[self reconcileChannel:newChannel into:existingChannel];
		} else {
			[existing addChannel:newChannel];
			// Seed the client-side unseen count, excluding technical/server
			// messages, for a freshly added channel.
			TLSeedUnseenFromMessages(newChannel);
		}
	}

	// Remove channels the server no longer knows about.
	NSMutableArray *toRemove = [NSMutableArray array];
	for (TLChannel *existingChannel in existing.channels) {
		if (![newNetwork channelWithIdentifier:existingChannel.identifier]) {
			[toRemove addObject:@(existingChannel.identifier)];
		}
	}
	for (NSNumber *chanId in toRemove) {
		[existing removeChannelWithIdentifier:[chanId integerValue]];
	}
}

// Seed the client-side unseen counts from the bouncer baseline, but exclude
// technical/server messages (which the bouncer counts in `unread`). We count
// only genuinely unread chat among the messages we actually received, then add
// the remainder of the server's unread total (messages not sent to us because
// they fall outside the loaded window) unchanged.
static void TLSeedUnseenFromMessages(TLChannel *channel)
{
	if (channel.firstUnread == 0) {
		channel.unseen = 0;
		channel.unseenHighlight = 0;
		return;
	}
	NSInteger loadedUnread = 0;
	NSInteger loadedUnseen = 0;
	NSInteger loadedUnseenHl = 0;
	for (TLMessage *m in channel.messages) {
		if (m.identifier < channel.firstUnread) {
			continue;
		}
		loadedUnread++;
		if ([m countsAsUnseen]) {
			loadedUnseen++;
			if (m.highlight) {
				loadedUnseenHl++;
			}
		}
	}
	NSInteger remainder = channel.unread - loadedUnread;
	if (remainder < 0) {
		remainder = 0;
	}
	channel.unseen = loadedUnseen + remainder;
	channel.unseenHighlight = loadedUnseenHl;
}

- (void)reconcileChannel:(TLChannel *)newChannel into:(TLChannel *)existing
{
	existing.name = newChannel.name;
	existing.topic = newChannel.topic;
	existing.key = newChannel.key;
	existing.unread = newChannel.unread;
	existing.highlight = newChannel.highlight;
	existing.firstUnread = newChannel.firstUnread;
	existing.muted = newChannel.muted;
	existing.state = newChannel.state;
	existing.specialType = newChannel.specialType;
	existing.closed = newChannel.closed;
	existing.numUsers = newChannel.numUsers;
	existing.totalMessages = newChannel.totalMessages;

	// The incoming channel carries messages newer than the client's last seen
	// id (plus up to 100). Append them, deduplicating by server id.
	for (TLMessage *message in newChannel.messages) {
		[existing addMessage:message];
	}

	// Seed the client-side unseen from genuinely unread chat messages, so the
	// bouncer's over-counting of technical/server messages does not inflate
	// the badge. Only seed until we start counting locally, so later syncs do
	// not clobber counts accumulated while the window was hidden.
	if (existing.unseen == 0) {
		TLSeedUnseenFromMessages(existing);
	}
}

- (void)handleMessageEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];
	NSDictionary *msgDict = payload[@"msg"];
	if (![msgDict isKindOfClass:[NSDictionary class]]) {
		return;
	}

	TLChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (!channel) {
		[[TLLogger sharedLogger] debug:@"msg for unknown channel %ld, ignoring", (long)chanId];
		return;
	}

	TLMessage *message = [[TLMessage alloc] initWithDictionary:msgDict];
	message.channelId = chanId;
	[channel addMessage:message];

	// The bouncer does not always include the absolute unread/highlight
	// counts on every `msg` event, so we maintain them locally (SPEC #24:
	// "maintain independently of the currently displayed view"). Use the
	// server value when supplied, otherwise count the message ourselves.
	// The channel being viewed is never counted as unread, matching the
	// bouncer, which stops incrementing it once the channel is open.
	BOOL isActiveChannel = (self.serverState.activeChannelId == chanId);

	if (payload[@"unread"]) {
		channel.unread = [payload[@"unread"] integerValue];
	} else if (!isActiveChannel && [message countsAsUnseen]) {
		channel.unread += 1;
	}

	if (payload[@"highlight"]) {
		channel.highlight = [payload[@"highlight"] integerValue];
	} else if (!isActiveChannel && [message countsAsUnseen] &&
		[message highlight]) {
		channel.highlight += 1;
	}

	// The unseen count is purely client-side and window-visibility aware: it
	// grows for every message the user has not actually looked at, including
	// the active channel while the window is hidden. The controller clears it
	// for the active channel once the window is on screen. Technical/server
	// status lines are excluded so they do not inflate the badge.
	if ([message countsAsUnseen]) {
		channel.unseen += 1;
		if ([message highlight]) {
			channel.unseenHighlight += 1;
		}
	}

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeMessagesDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId), @"message": message}];
}

- (void)handleMoreEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];
	NSArray *messages = payload[@"messages"];

	TLChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (!channel) {
		return;
	}
	if (payload[@"totalMessages"]) {
		channel.totalMessages = [payload[@"totalMessages"] integerValue];
	}

	if ([messages isKindOfClass:[NSArray class]]) {
		NSMutableArray *newMessages = [NSMutableArray array];
		for (id m in messages) {
			if ([m isKindOfClass:[NSDictionary class]]) {
				TLMessage *message = [[TLMessage alloc] initWithDictionary:m];
				message.channelId = chanId;
				if (![channel messageWithIdentifier:message.identifier]) {
					[newMessages addObject:message];
				}
			}
		}
		[channel prependMessages:newMessages];
	}

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeHistoryDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId)}];
}

- (void)handleNamesEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"id"] integerValue];
	NSArray *users = payload[@"users"];

	TLChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (!channel) {
		return;
	}

	[channel.users removeAllObjects];
	if ([users isKindOfClass:[NSArray class]]) {
		for (id u in users) {
			if ([u isKindOfClass:[NSDictionary class]]) {
				[channel addUser:[[TLUser alloc] initWithDictionary:u]];
			}
		}
	}
	channel.numUsers = [channel.users count];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeUserListDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId)}];
}

- (void)handleUsersEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];

	TLChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (!channel) {
		return;
	}
	// The user list changed; the server expects the client to request the new
	// list. Clear stale users so the UI reflects the transition immediately.
	[channel.users removeAllObjects];
	channel.numUsers = 0;

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeUserListDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId)}];

	[self requestNamesForChannelId:chanId];
}

- (void)handleNetworkEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSDictionary *networkDict = payload[@"network"];
	if (![networkDict isKindOfClass:[NSDictionary class]]) {
		return;
	}

	TLNetwork *network = [[TLNetwork alloc] initWithDictionary:networkDict];
	[self.serverState addNetwork:network];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
}

- (void)handleNetworkOptionsEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	TLNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	if (network && [payload[@"serverOptions"] isKindOfClass:[NSDictionary class]]) {
		network.serverOptions = payload[@"serverOptions"];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
	}
}

- (void)handleNetworkStatusEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	TLNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	if (network) {
		network.connected = [payload[@"connected"] boolValue];
		network.secure = [payload[@"secure"] boolValue];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
	}
}

- (void)handleNetworkNameEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	TLNetwork *network = [self.serverState networkWithUuid:payload[@"uuid"]];
	if (network) {
		if (payload[@"name"]) {
			network.name = [payload[@"name"] description];
		}
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
	}
}

- (void)handleNickEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	TLNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	if (network) {
		if (payload[@"nick"]) {
			network.nick = [payload[@"nick"] description];
			self.serverState.currentUserNick = network.nick;
		}
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
	}
}

- (void)handleJoinEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	TLNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	NSDictionary *chanDict = payload[@"chan"];
	if (!network || ![chanDict isKindOfClass:[NSDictionary class]]) {
		return;
	}

	TLChannel *channel = [[TLChannel alloc] initWithDictionary:chanDict];
	[network addChannel:channel];

	if ([payload[@"shouldOpen"] boolValue] && channel.identifier > 0) {
		self.clientState.selectedChannelId = channel.identifier;
	}

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
}

- (void)handlePartEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];

	TLNetwork *network = [self.serverState networkContainingChannel:chanId];
	if (network) {
		[network removeChannelWithIdentifier:chanId];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
	}
}

- (void)handleQuitEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSString *uuid = payload[@"network"];
	if ([uuid isKindOfClass:[NSString class]]) {
		[self.serverState removeNetworkWithUuid:uuid];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
	}
}

- (void)handleTopicEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];
	TLChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (channel) {
		if (payload[@"topic"]) {
			channel.topic = [payload[@"topic"] description];
		}
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(chanId)}];
	}
}

- (void)handleChannelStateEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];
	TLChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (channel) {
		channel.state = [payload[@"state"] integerValue];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(chanId)}];
	}
}

- (void)handleMuteChangedEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"target"] integerValue];
	TLChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (channel) {
		channel.muted = [payload[@"status"] boolValue];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(chanId)}];
	}
}

- (void)handleHistoryClearEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"target"] integerValue];
	TLChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (channel) {
		[channel.messages removeAllObjects];
		channel.unread = 0;
		channel.highlight = 0;
		channel.unseen = 0;
		channel.unseenHighlight = 0;
		channel.firstUnread = 0;
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeMessagesDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(chanId)}];
	}
}

- (void)handleSyncSortNetworksEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSArray *order = payload[@"order"];
	if (![order isKindOfClass:[NSArray class]]) {
		return;
	}
	NSMutableArray *reordered = [NSMutableArray array];
	for (NSString *uuid in order) {
		TLNetwork *network = [self.serverState networkWithUuid:uuid];
		if (network) {
			[reordered addObject:network];
		}
	}
	for (TLNetwork *network in self.serverState.networks) {
		if (![reordered containsObject:network]) {
			[reordered addObject:network];
		}
	}
	self.serverState.networks = reordered;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
}

- (void)handleSyncSortChannelsEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	TLNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	NSArray *order = payload[@"order"];
	if (!network || ![order isKindOfClass:[NSArray class]]) {
		return;
	}
	NSMutableArray *reordered = [NSMutableArray array];
	for (NSNumber *chanId in order) {
		TLChannel *channel = [network channelWithIdentifier:[chanId integerValue]];
		if (channel) {
			[reordered addObject:channel];
		}
	}
	for (TLChannel *channel in network.channels) {
		if (![reordered containsObject:channel]) {
			[reordered addObject:channel];
		}
	}
	network.channels = reordered;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification object:self];
}

@end