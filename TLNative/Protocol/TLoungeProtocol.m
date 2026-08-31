/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeProtocol.h"
#import "TLServerState.h"
#import "TLClientState.h"
#import "TLSocketIOClient.h"
#import "TLSocketEventDispatcher.h"

NSString *const TLLoungeNetworkListDidChangeNotification = @"TLLoungeNetworkListDidChangeNotification";
NSString *const TLLoungeChannelDidChangeNotification = @"TLLoungeChannelDidChangeNotification";
NSString *const TLLoungeMessagesDidChangeNotification = @"TLLoungeMessagesDidChangeNotification";
NSString *const TLLoungeUserListDidChangeNotification = @"TLLoungeUserListDidChangeNotification";
NSString *const TLLoungeNicknamesDidChangeNotification = @"TLLoungeNicknamesDidChangeNotification";
NSString *const TLLoungeHistoryDidChangeNotification = @"TLLoungeHistoryDidChangeNotification";
NSString *const TLLoungeSearchResultsDidChangeNotification = @"TLLoungeSearchResultsDidChangeNotification";

@interface TLoungeProtocol ()
{
	NSString *_pendingUsername;
	NSString *_pendingPassword;
	NSString *_pendingToken;
	BOOL _isAuthenticated;
	BOOL _isReady;
}
@end

@implementation TLoungeProtocol

- (instancetype)initWithSocketClient:(TLSocketIOClient *)client
                         serverState:(TLServerState *)serverState
                         clientState:(TLClientState *)clientState
{
	self = [super init];
	if (self) {
		_socketClient = client;
		_serverState = serverState;
		_clientState = clientState;
		_dispatcher = [[TLSocketEventDispatcher alloc] init];
		_pendingUsername = [@"" copy];
		_pendingPassword = [@"" copy];
		_pendingToken = [@"" copy];
		_isAuthenticated = NO;
		_isReady = NO;
		[self registerEventHandlers];
	}
	return self;
}

- (void)registerEventHandlers
{
	// Overridden by protocol version implementations.
}

- (void)transportDidConnect
{
	// No-op for The Lounge; overridden by relay-style protocols.
}

- (void)dealloc
{
	[_pendingUsername release];
	[_pendingPassword release];
	[_pendingToken release];
	[super dealloc];
}

- (void)resetSession
{
	_isAuthenticated = NO;
	_isReady = NO;
	// Credentials are deliberately kept: the automatic reconnect must be
	// able to re-authenticate. This object is discarded together with its
	// credentials whenever the user starts a new login anyway.
}

- (void)setUsername:(NSString *)username password:(NSString *)password
{
	[_pendingUsername release];
	_pendingUsername = [username ? username : @"" copy];
	[_pendingPassword release];
	_pendingPassword = [password ? password : @"" copy];
	[_pendingToken release];
	_pendingToken = [@"" copy];
}

- (void)setUsername:(NSString *)username token:(NSString *)token
{
	[_pendingUsername release];
	_pendingUsername = [username ? username : @"" copy];
	[_pendingToken release];
	_pendingToken = [token ? token : @"" copy];
	[_pendingPassword release];
	_pendingPassword = [@"" copy];
}

- (void)adoptSessionToken:(NSString *)token
{
	[_pendingToken release];
	_pendingToken = [token copy];
	[_pendingPassword release];
	_pendingPassword = [@"" copy];
}

- (void)performAuthentication
{
	// Overridden by protocol version implementations.
}

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"input"
		withArguments:@[@{@"target": @(channelId), @"text": text}]];
}

- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId
{
	[self sendMessage:command toChannelId:channelId];
}

- (void)openChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"open" withArguments:@[@(channelId)]];
	// The bouncer does not always push a channel's backlog in response to
	// `open`; request the most recent page explicitly. Omitting `lastId` makes
	// the server return the tail (newest page) rather than older-than-0.
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	[payload setObject:@(channelId) forKey:@"target"];
	[payload setObject:@NO forKey:@"condensed"];
	[self.socketClient emitEvent:@"more" withArguments:@[payload]];
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"names" withArguments:@[@{@"target": @(channelId)}]];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
{
	[self loadMoreHistoryForChannelId:channelId lastId:lastId query:nil];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query
{
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	[payload setObject:@(channelId) forKey:@"target"];
	[payload setObject:@(lastId) forKey:@"lastId"];
	[payload setObject:@NO forKey:@"condensed"];
	if ([query length] > 0) {
		[payload setObject:query forKey:@"query"];
	}
	[self.socketClient emitEvent:@"more" withArguments:@[payload]];
}

// The Lounge bouncer searches its stored backlog through a dedicated `search`
// event (distinct from `more`), keyed by network uuid and (lowercased) channel
// name rather than the channel id the client uses elsewhere.
- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset
{
	TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
	TLNetwork *network = [self.serverState networkContainingChannel:channelId];
	if (!channel || !network || [term length] == 0) {
		return;
	}
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	[payload setObject:term forKey:@"searchTerm"];
	[payload setObject:[network.uuid description] forKey:@"networkUuid"];
	[payload setObject:[[channel.name description] lowercaseString]
		forKey:@"channelName"];
	[payload setObject:@(offset) forKey:@"offset"];
	[self.socketClient emitEvent:@"search" withArguments:@[payload]];
}

- (void)clearHistoryForChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"history:clear" withArguments:@[@{@"target": @(channelId)}]];
}

- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"mute:change"
		withArguments:@[@{@"target": @(channelId), @"setMutedTo": @(muted)}]];
}

- (void)joinChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId
{
	NSString *command = [NSString stringWithFormat:@"/join %@", name];
	[self sendCommand:command toChannelId:lobbyId];
}

- (TLNetwork *)managedNetwork
{
	return nil;
}

- (BOOL)isNosternProtocol
{
	return NO;
}

- (NSArray *)knownGroupNames
{
	return @[];
}

- (void)ensureJoinedChannelId:(NSInteger)channelId
{
}

- (void)deleteGroupChannelId:(NSInteger)channelId
{
}

- (void)deleteAllOwnedGroups
{
}

- (BOOL)isAuthenticated
{
	return _isAuthenticated;
}

- (BOOL)isReady
{
	return _isReady;
}

- (BOOL)isConnected
{
	return [self.socketClient isConnected];
}

- (void)setAuthenticated:(BOOL)authenticated
{
	_isAuthenticated = authenticated;
}

- (void)setReady:(BOOL)ready
{
	_isReady = ready;
}

- (NSString *)pendingUsername
{
	return _pendingUsername;
}

- (NSString *)pendingPassword
{
	return _pendingPassword;
}

- (NSString *)pendingToken
{
	return _pendingToken;
}

@end