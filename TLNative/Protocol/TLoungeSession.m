/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeSession.h"
#import "TLoungeProtocol_4_5.h"
#import "TLServerState.h"
#import "TLClientState.h"
#import "TLChannel.h"
#import "TLSocketIOClient.h"
#import "TLSocketEventDispatcher.h"
#import "TLLogger.h"

NSString *const TLLoungeSessionStateDidChangeNotification = @"TLLoungeSessionStateDidChangeNotification";
NSString *const TLLoungeSessionDidBecomeReadyNotification = @"TLLoungeSessionDidBecomeReadyNotification";
NSString *const TLLoungeSessionErrorNotification = @"TLLoungeSessionErrorNotification";

NSString *TLConnectionStateDisplayString(TLConnectionState state)
{
	switch (state) {
		case TLConnectionStateDisconnected:
			return @"Disconnected";
		case TLConnectionStateConnecting:
			return @"Connecting...";
		case TLConnectionStateTransportConnected:
			return @"Connected";
		case TLConnectionStateSocketConnected:
			return @"Connected";
		case TLConnectionStateAuthenticating:
			return @"Authenticating...";
		case TLConnectionStateInitializing:
			return @"Loading...";
		case TLConnectionStateReady:
			return @"Connected";
		case TLConnectionStateReconnecting:
			return @"Reconnecting...";
		case TLConnectionStateAuthenticationFailed:
			return @"Authentication failed";
		case TLConnectionStateProtocolError:
			return @"Protocol error";
		case TLConnectionStateServerDisconnected:
			return @"Disconnected";
		case TLConnectionStateConnectionError:
			return @"Connection error";
	}
	return @"";
}

@interface TLoungeSession () <TLSocketIOClientDelegate, TLoungeProtocolDelegate>
{
	NSURL *_serverURL;
	NSString *_username;
	NSString *_password;
	NSString *_sessionToken;
	BOOL _remember;
	BOOL _manualDisconnect;
	BOOL _reconnectScheduled;
	NSInteger _reconnectAttempt;

	TLSocketIOClient *_socketClient;
	TLConnectionState _state;
}
@end

@implementation TLoungeSession

- (instancetype)initWithServerURL:(NSURL *)url username:(NSString *)username
{
	self = [super init];
	if (self) {
		_serverURL = [url retain];
		_username = [username retain];
		_password = @"";
		_sessionToken = @"";
		_remember = NO;
		_manualDisconnect = YES;
		_reconnectScheduled = NO;
		_reconnectAttempt = 0;
		_state = TLConnectionStateDisconnected;

		_serverState = [[TLServerState alloc] init];
		_clientState = [[TLClientState alloc] init];
		_socketClient = [[TLSocketIOClient alloc] init];
		_socketClient.delegate = self;

		_protocol = [[TLoungeProtocol_4_5 alloc] initWithSocketClient:_socketClient
			serverState:_serverState
			clientState:_clientState];
		_protocol.delegate = self;
	}
	return self;
}

- (void)dealloc
{
	[self disconnect];
	[_serverURL release];
	[_username release];
	[_password release];
	[_sessionToken release];
	[_serverState release];
	[_clientState release];
	[_socketClient release];
	[_protocol release];
	[super dealloc];
}

- (NSString *)serverURLString
{
	return [_serverURL absoluteString];
}

- (void)setPassword:(NSString *)password
{
	[_password release];
	_password = [password retain];
	[_protocol setUsername:_username password:_password];
}

- (void)setSessionToken:(NSString *)token
{
	[_sessionToken release];
	_sessionToken = [token retain];
	[_protocol setUsername:_username token:_sessionToken];
}

- (void)setRemember:(BOOL)remember
{
	_remember = remember;
}

- (void)connect
{
	_manualDisconnect = NO;
	_reconnectAttempt = 0;
	_reconnectScheduled = NO;

	[self setState:TLConnectionStateConnecting];
	[_socketClient connectToServerURL:_serverURL];
}

- (void)disconnect
{
	_manualDisconnect = YES;
	_reconnectScheduled = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(attemptReconnect) object:nil];
	[_socketClient close];
	[self setState:TLConnectionStateDisconnected];
}

- (void)reconnect
{
	[self connect];
}

- (void)attemptReconnect
{
	_reconnectScheduled = NO;
	if (_manualDisconnect) {
		return;
	}
	[[TLLogger sharedLogger] info:@"Attempting reconnect (attempt %ld)", (long)_reconnectAttempt];
	[self setState:TLConnectionStateReconnecting];
	[_socketClient connectToServerURL:_serverURL];
}

- (void)scheduleReconnect
{
	if (_manualDisconnect || _reconnectScheduled) {
		return;
	}
	_reconnectScheduled = YES;
	_reconnectAttempt++;

	NSTimeInterval delay = 1.0;
	for (NSInteger i = 1; i < _reconnectAttempt && delay < 30.0; i++) {
		delay *= 2.0;
	}
	delay = MIN(delay, 30.0);
	// Randomized jitter: up to 30% of the current delay.
	NSTimeInterval jitter = ((double)(arc4random() % 1000) / 1000.0) * 0.3 * delay;
	delay += jitter;

	[[TLLogger sharedLogger] info:@"Reconnecting in %.1f seconds (attempt %ld)", delay,
		(long)_reconnectAttempt];
	[self setState:TLConnectionStateReconnecting];
	[self performSelector:@selector(attemptReconnect) withObject:nil afterDelay:delay];
}

- (void)setState:(TLConnectionState)state
{
	if (_state == state) {
		return;
	}
	_state = state;
	[[TLLogger sharedLogger] info:@"Connection state: %@", TLConnectionStateDisplayString(state)];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeSessionStateDidChangeNotification
		object:self
		userInfo:@{@"state": @(state)}];
}

#pragma mark - User operations

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	[self.protocol sendMessage:text toChannelId:channelId];
}

- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId
{
	[self.protocol sendCommand:command toChannelId:channelId];
}

- (void)openChannelId:(NSInteger)channelId
{
	_clientState.selectedChannelId = channelId;
	[self.protocol openChannelId:channelId];
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
	[self.protocol requestNamesForChannelId:channelId];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
{
	[self.protocol loadMoreHistoryForChannelId:channelId lastId:lastId];
}

#pragma mark - TLSocketIOClientDelegate (network thread)

- (void)socketIOClientDidConnect:(TLSocketIOClient *)client
{
	[self performSelectorOnMainThread:@selector(handleSocketConnected)
		withObject:nil
		waitUntilDone:NO];
}

- (void)socketIOClient:(TLSocketIOClient *)client didReceiveEvent:(NSString *)eventName arguments:(NSArray *)arguments
{
	NSDictionary *payload = @{@"event": eventName, @"args": arguments ? arguments : @[]};
	[self performSelectorOnMainThread:@selector(handleSocketEvent:)
		withObject:payload
		waitUntilDone:NO];
}

- (void)socketIOClientDidDisconnect:(TLSocketIOClient *)client
{
	[self performSelectorOnMainThread:@selector(handleSocketDisconnected)
		withObject:nil
		waitUntilDone:NO];
}

- (void)socketIOClient:(TLSocketIOClient *)client didFailWithError:(NSError *)error
{
	NSDictionary *payload = @{@"error": error};
	[self performSelectorOnMainThread:@selector(handleSocketFailure:)
		withObject:payload
		waitUntilDone:NO];
}

#pragma mark - Main thread handlers

- (void)handleSocketConnected
{
	[self setState:TLConnectionStateSocketConnected];
}

- (void)handleSocketEvent:(id)payload
{
	NSString *eventName = payload[@"event"];
	NSArray *arguments = payload[@"args"];

	// One malformed event must not take down event processing for the
	// whole session; log it and keep going.
	@try {
		[self.protocol.dispatcher dispatchEvent:eventName arguments:arguments];
	}
	@catch (NSException *exception) {
		[[TLLogger sharedLogger] error:@"Event '%@' failed: %@", eventName,
			[exception reason]];
	}
}

- (void)handleSocketDisconnected
{
	if (_state == TLConnectionStateReady) {
		// An established session dropped unexpectedly; tell the UI so it
		// can inform the user while the automatic reconnect runs.
		NSError *error = [NSError errorWithDomain:@"TLLoungeSessionErrorDomain"
			code:1
			userInfo:@{NSLocalizedDescriptionKey:
				@"The connection to the server was lost."}];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeSessionErrorNotification
			object:self
			userInfo:@{@"error": error, @"recoverable": @YES}];
	}
	if (_state == TLConnectionStateReady ||
		_state == TLConnectionStateConnecting ||
		_state == TLConnectionStateAuthenticating ||
		_state == TLConnectionStateInitializing ||
		_state == TLConnectionStateReconnecting) {
		[self.protocol resetSession];
		[self scheduleReconnect];
		return;
	}
	if (_state == TLConnectionStateConnectionError || _state == TLConnectionStateServerDisconnected) {
		[self.protocol resetSession];
		[self scheduleReconnect];
	}
}

- (void)handleSocketFailure:(NSDictionary *)payload
{
	NSError *error = payload[@"error"];
	[[TLLogger sharedLogger] error:@"Socket failure: %@", [error localizedDescription]];
	[self setState:TLConnectionStateConnectionError];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeSessionErrorNotification
		object:self
		userInfo:@{@"error": error}];
	[self.protocol resetSession];
	[self scheduleReconnect];
}

#pragma mark - TLoungeProtocolDelegate (main thread)

- (void)protocol:(TLoungeProtocol *)protocol didReceiveAuthStart:(NSNumber *)serverHash
{
	[self setState:TLConnectionStateAuthenticating];
}

- (void)protocolDidAuthenticate:(TLoungeProtocol *)protocol
{
	[self setState:TLConnectionStateInitializing];
}

- (void)protocol:(TLoungeProtocol *)protocol authenticationFailedWithError:(NSError *)error
{
	[self setState:TLConnectionStateAuthenticationFailed];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeSessionErrorNotification
		object:self
		userInfo:@{@"error": error}];
}

- (void)protocolDidBecomeReady:(TLoungeProtocol *)protocol
{
	_clientState.authenticated = YES;
	_reconnectAttempt = 0;
	_reconnectScheduled = NO;

	// Persist the session token received on first login.
	if (self.serverState.metadata[@"token"]) {
		NSString *token = self.serverState.metadata[@"token"];
		[_sessionToken release];
		_sessionToken = [token retain];
		if (_remember) {
			[self persistSessionToken:token];
		}
	}

	// Restore the previously selected channel if it still exists.
	NSInteger restoreChannel = _clientState.selectedChannelId;
	if (restoreChannel > 0) {
		TLChannel *channel = [self.serverState channelWithIdentifier:restoreChannel];
		if (!channel) {
			_clientState.selectedChannelId = 0;
		}
	}

	[self setState:TLConnectionStateReady];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeSessionDidBecomeReadyNotification object:self];
}

- (void)protocol:(TLoungeProtocol *)protocol didFailWithError:(NSError *)error
{
	[self setState:TLConnectionStateProtocolError];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeSessionErrorNotification
		object:self
		userInfo:@{@"error": error}];
}

#pragma mark - Credential persistence

- (NSString *)tokenFilePath
{
	NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
		NSUserDomainMask, YES) firstObject];
	NSString *dir = [appSupport stringByAppendingPathComponent:@"The Lounge"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:dir
			withIntermediateDirectories:YES
			attributes:@{NSFilePosixPermissions: @0700}
			error:NULL];
	}
	return [dir stringByAppendingPathComponent:@"session-token"];
}

- (void)persistSessionToken:(NSString *)token
{
	NSDictionary *data = @{@"server": _serverURL.absoluteString, @"user": _username, @"token": token};
	NSError *error = nil;
	NSData *json = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
	if (!json) {
		[[TLLogger sharedLogger] error:@"Failed to serialize session token: %@",
			[error localizedDescription]];
		return;
	}
	NSDictionary *attrs = @{NSFilePosixPermissions: @0600};
	NSString *path = [self tokenFilePath];
	[json writeToFile:path options:NSAtomicWrite error:&error];
	if (!error) {
		[[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:path error:&error];
	}
	if (error) {
		[[TLLogger sharedLogger] error:@"Failed to store session token: %@",
			[error localizedDescription]];
	}
}

- (NSString *)retrieveStoredToken
{
	NSString *path = [self tokenFilePath];
	NSData *json = [NSData dataWithContentsOfFile:path];
	if (!json) {
		return @"";
	}
	NSDictionary *data = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
	if (![data isKindOfClass:[NSDictionary class]]) {
		return @"";
	}
	// Only restore the token if it belongs to this server+user combination.
	if (![data[@"server"] isEqualToString:_serverURL.absoluteString] ||
		![data[@"user"] isEqualToString:_username]) {
		return @"";
	}
	return data[@"token"];
}

- (void)clearStoredToken
{
	NSString *path = [self tokenFilePath];
	if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}
}

@end