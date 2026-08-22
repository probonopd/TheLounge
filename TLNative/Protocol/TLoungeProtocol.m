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
NSString *const TLLoungeHistoryDidChangeNotification = @"TLLoungeHistoryDidChangeNotification";

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
	[_pendingToken release];
	_pendingToken = [@"" copy];
	[_pendingPassword release];
	_pendingPassword = [@"" copy];
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
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"names" withArguments:@[@{@"target": @(channelId)}]];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
{
	[self.socketClient emitEvent:@"more"
		withArguments:@[@{@"target": @(channelId), @"lastId": @(lastId), @"condensed": @NO}]];
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

- (BOOL)isAuthenticated
{
	return _isAuthenticated;
}

- (BOOL)isReady
{
	return _isReady;
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