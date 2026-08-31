/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeSession.h"
#import "TLoungeProtocol_4_5.h"
#import "TLoungeProtocol_Nosterm.h"
#import "TLNostrSocketClient.h"
#import "TLNostrCrypto.h"
#import "TLServerState.h"
#import "TLClientState.h"
#import "TLChannel.h"
#import "TLNetwork.h"
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

	id _socketClient;
	TLConnectionState _state;

	// Additional Nosterm relay connections that share this session's model
	// state. Indexed in parallel; each relay owns a STRIDE-sized slice of the
	// Nosterm id range so its channel/message ids route back to it.
	NSMutableArray *_relayClients;
	NSMutableArray *_relayProtocols;
	NSMutableArray *_relayURLs;
	NSMutableDictionary *_relayReconnectAttempts;
	NSMutableDictionary *_relayReconnectScheduled;
	NSMutableSet *_relayManuallyDisconnected;
}
@end

@interface TLoungeSession ()
{
	NSTimer *_probeTimer;
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

		_relayClients = [[NSMutableArray alloc] init];
		_relayProtocols = [[NSMutableArray alloc] init];
		_relayURLs = [[NSMutableArray alloc] init];
		_relayReconnectAttempts = [[NSMutableDictionary alloc] init];
		_relayReconnectScheduled = [[NSMutableDictionary alloc] init];
		_relayManuallyDisconnected = [[NSMutableSet alloc] init];

		BOOL useNostr = NO;
		NSString *scheme = [_serverURL scheme];
		if ([scheme isEqualToString:@"ws"] || [scheme isEqualToString:@"wss"]) {
			useNostr = YES;
		}
		if (useNostr) {
			_socketClient = [[TLNostrSocketClient alloc] init];
			[_socketClient setDelegate:self];
			TLoungeProtocol_Nosterm *nostr = [[TLoungeProtocol_Nosterm alloc]
				initWithSocketClient:(TLSocketIOClient *)_socketClient
				serverState:_serverState
				clientState:_clientState];
			_protocol = nostr;
			// The Nosterm primary claims slot 0 of the shared id range.
			nostr.channelIdBase = TLLoungeNostrIdBase;
		} else {
			_socketClient = [[TLSocketIOClient alloc] init];
			[_socketClient setDelegate:self];
			_protocol = [[TLoungeProtocol_4_5 alloc]
				initWithSocketClient:(TLSocketIOClient *)_socketClient
				serverState:_serverState
				clientState:_clientState];
		}
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
	[_relayClients release];
	[_relayProtocols release];
	[_relayURLs release];
	[_relayReconnectAttempts release];
	[_relayReconnectScheduled release];
	[_relayManuallyDisconnected release];
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

#pragma mark - Connection routing

// Returns the protocol that owns a given channel id. The Lounge ids are small
// integers below the Nosterm base; Nosterm ids carry their relay slot.
- (TLoungeProtocol *)protocolForChannelId:(NSInteger)channelId
{
	if (channelId < (NSInteger)TLLoungeNostrIdBase) {
		return _protocol;
	}
	uint64_t cid = (uint64_t)channelId;
	uint64_t slot = (cid - TLLoungeNostrIdBase) / TLLoungeNostrIdStride;
	if (slot == 0) {
		return _protocol;
	}
	NSInteger relayIdx = (NSInteger)slot - 1;
	if (relayIdx >= 0 && relayIdx < (NSInteger)[_relayProtocols count]) {
		return _relayProtocols[relayIdx];
	}
	return _protocol;
}

// Returns the protocol managing a given network so a join lands on the right
// relay when several are connected. Bouncer protocols return nil, so we fall
// back to the primary.
- (TLoungeProtocol *)protocolForNetwork:(TLNetwork *)network
{
	if (network == nil) {
		return _protocol;
	}
	if ([_protocol respondsToSelector:@selector(managedNetwork)] &&
		[_protocol managedNetwork] == network) {
		return _protocol;
	}
	for (TLoungeProtocol *protocol in _relayProtocols) {
		if ([protocol respondsToSelector:@selector(managedNetwork)] &&
			[protocol managedNetwork] == network) {
			return protocol;
		}
	}
	return _protocol;
}

- (void)joinChannelNamed:(NSString *)name forLobbyId:(NSInteger)lobbyId
{
	TLNetwork *network = [self.serverState networkContainingChannel:lobbyId];
	[[self protocolForNetwork:network] joinChannelNamed:name lobbyId:lobbyId];
}

- (void)joinExistingChannelNamed:(NSString *)name forLobbyId:(NSInteger)lobbyId
{
	TLNetwork *network = [self.serverState networkContainingChannel:lobbyId];
	[[self protocolForNetwork:network] joinExistingChannelNamed:name lobbyId:lobbyId];
}

- (TLoungeProtocol *)protocolForClient:(id)client
{
	if (client == _socketClient) {
		return _protocol;
	}
	NSUInteger idx = [_relayClients indexOfObject:client];
	if (idx != NSNotFound) {
		return _relayProtocols[idx];
	}
	return _protocol;
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
	[self stopProbeTimer];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(attemptReconnect) object:nil];
	for (id client in _relayClients) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(attemptRelayReconnect:) object:client];
		[(TLNostrSocketClient *)client close];
	}
	[_socketClient close];
	[self setState:TLConnectionStateDisconnected];
}

- (void)reconnect
{
	[self connect];
}

- (void)addRelayWithURL:(NSURL *)relayURL username:(NSString *)username
	privateKey:(NSString *)privateKey
{
	if (relayURL == nil) {
		NSLog(@"[NOSTERM-SESSION] addRelayWithURL: nil URL, aborting");
		return;
	}
	NSLog(@"[NOSTERM-SESSION] addRelayWithURL: %@ username=%@", relayURL, username);
	TLNostrSocketClient *client = [[TLNostrSocketClient alloc] init];
	[client setDelegate:self];
	TLoungeProtocol_Nosterm *protocol = [[TLoungeProtocol_Nosterm alloc]
		initWithSocketClient:(TLSocketIOClient *)client
		serverState:_serverState
		clientState:_clientState];
	// Each added relay gets the next slot in the shared Nosterm id range.
	uint64_t slot = (uint64_t)([_relayProtocols count] + 1);
	protocol.channelIdBase = TLLoungeNostrIdBase + slot * TLLoungeNostrIdStride;
	[protocol setUsername:username password:privateKey];
	protocol.delegate = self;

	[_relayClients addObject:client];
	[_relayProtocols addObject:protocol];
	[_relayURLs addObject:relayURL];
	[client release];
	[protocol release];

	[client connectToServerURL:relayURL];
}

#pragma mark - Relay management

- (NSArray<NSDictionary *> *)connectedRelays
{
	NSMutableArray *result = [NSMutableArray array];
	NSString *primaryKind = [_protocol isKindOfClass:[TLoungeProtocol_Nosterm class]]
		? @"nostern" : @"bouncer";
	BOOL primaryUp = (_state == TLConnectionStateReady);
	[result addObject:@{
		@"url": [self serverURLString] ?: @"",
		@"connected": @(primaryUp),
		@"kind": primaryKind,
		@"name": _username ?: @""
	}];
	for (NSUInteger i = 0; i < [_relayProtocols count]; i++) {
		NSURL *u = _relayURLs[i];
		id client = _relayClients[i];
		NSString *name = [[_relayProtocols objectAtIndex:i] pendingUsername] ?: @"";
		[result addObject:@{
			@"url": [u absoluteString] ?: @"",
			@"connected": @([(TLNostrSocketClient *)client isConnected]),
			@"kind": @"nostern",
			@"name": name
		}];
	}
	return result;
}

- (void)disconnectRelayWithURL:(NSURL *)url
{
	if (url == nil) {
		return;
	}
	NSString *target = [url absoluteString];
	for (NSUInteger i = 0; i < [_relayURLs count]; i++) {
		if ([[[_relayURLs objectAtIndex:i] absoluteString]
			isEqualToString:target]) {
			id client = [_relayClients objectAtIndex:i];
			[_relayManuallyDisconnected addObject:client];
			[(TLNostrSocketClient *)client close];
			[_relayReconnectScheduled removeObjectForKey:client];
			[_relayReconnectAttempts removeObjectForKey:client];
			[_relayClients removeObjectAtIndex:i];
			[_relayProtocols removeObjectAtIndex:i];
			[_relayURLs removeObjectAtIndex:i];
			return;
		}
	}
}

- (NSString *)nostermPublicKeyHex
{
	for (TLoungeProtocol_Nosterm *p in _relayProtocols) {
		NSString *hex = [p nostermPublicKeyHex];
		if ([hex length] > 0) {
			return hex;
		}
	}
	if ([_protocol isKindOfClass:[TLoungeProtocol_Nosterm class]]) {
		return [(TLoungeProtocol_Nosterm *)_protocol nostermPublicKeyHex];
	}
	return nil;
}

- (NSString *)nostermPublicKeyNpub
{
	NSString *hex = [self nostermPublicKeyHex];
	if ([hex length] == 0) {
		return nil;
	}
	return [TLNostrCrypto npubFromPubkeyHex:hex];
}

#pragma mark - Reconnect (primary)

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
	// Start a fast probe that tries to reconnect every 3 seconds. If the
	// network returns before the backoff timer fires, this catches it early.
	if (!_probeTimer) {
		_probeTimer = [[NSTimer scheduledTimerWithTimeInterval:3.0
			target:self selector:@selector(probeConnectivity:) userInfo:nil
			repeats:YES] retain];
	}
}

#pragma mark - Reconnect (relays)

- (void)attemptRelayReconnect:(id)client
{
	[_relayReconnectScheduled removeObjectForKey:client];
	if ([_relayManuallyDisconnected containsObject:client]) {
		return;
	}
	NSUInteger idx = [_relayClients indexOfObject:client];
	if (idx == NSNotFound) {
		return;
	}
	[(TLNostrSocketClient *)client connectToServerURL:_relayURLs[idx]];
}

- (void)scheduleRelayReconnect:(id)client
{
	if ([_relayManuallyDisconnected containsObject:client]) {
		return;
	}
	if ([_relayReconnectScheduled[client] boolValue]) {
		return;
	}
	_relayReconnectScheduled[client] = @YES;
	NSInteger attempt = [_relayReconnectAttempts[client] integerValue] + 1;
	_relayReconnectAttempts[client] = @(attempt);

	NSTimeInterval delay = 1.0;
	for (NSInteger i = 1; i < attempt && delay < 30.0; i++) {
		delay *= 2.0;
	}
	delay = MIN(delay, 30.0);
	NSTimeInterval jitter = ((double)(arc4random() % 1000) / 1000.0) * 0.3 * delay;
	delay += jitter;
	[[TLLogger sharedLogger] info:@"Reconnecting relay in %.1f seconds (attempt %ld)", delay,
		(long)attempt];
	[self performSelector:@selector(attemptRelayReconnect:) withObject:client afterDelay:delay];
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

#pragma mark - Pending message queue

- (void)flushPendingMessages
{
	for (TLNetwork *net in _serverState.networks) {
		for (TLChannel *channel in net.channels) {
			NSArray *pending = [NSArray arrayWithArray:channel.pendingMessages];
			[channel removeAllPendingMessages];
			for (TLMessage *msg in pending) {
				TLoungeProtocol *proto = [self protocolForChannelId:channel.identifier];
				if ([proto isConnected]) {
					[proto sendMessage:msg.text toChannelId:channel.identifier];
				} else {
					// Connection dropped again between flush start and this message;
					// put it back.
					[channel addPendingMessage:msg];
				}
			}
		}
	}
}

- (void)stopProbeTimer
{
	if (_probeTimer) {
		[_probeTimer invalidate];
		[_probeTimer release];
		_probeTimer = nil;
	}
}

- (void)probeConnectivity:(NSTimer *)timer
{
	if (_manualDisconnect || _reconnectScheduled || _state != TLConnectionStateReconnecting) {
		return;
	}
	// Fast path: the probe beat the backoff timer. Try connecting now.
	[[TLLogger sharedLogger] info:@"Probe: attempting reconnect (attempt %ld)",
		(long)_reconnectAttempt];
	[self attemptReconnect];
}

#pragma mark - User operations

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	TLoungeProtocol *proto = [self protocolForChannelId:channelId];
	if (![proto isConnected]) {
		TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
		if (channel) {
			TLMessage *msg = [[[TLMessage alloc] init] autorelease];
			msg.channelId = channelId;
			msg.text = text;
			msg.rawText = text;
			msg.timestamp = [NSDate date];
			msg.type = TLMessageTypeMessage;
			msg.self = YES;
			msg.pending = YES;
			TLUser *me = [[[TLUser alloc] init] autorelease];
			me.nick = _serverState.currentUserNick;
			if (!me.nick || [me.nick length] == 0) {
				me.nick = _username;
			}
			msg.sender = me;
			[channel addPendingMessage:msg];
			[[NSNotificationCenter defaultCenter]
				postNotificationName:TLLoungeMessagesDidChangeNotification
				object:self
				userInfo:@{@"channelId": @(channelId)}];
		}
		return;
	}
	[proto sendMessage:text toChannelId:channelId];
}

- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId
{
	TLoungeProtocol *proto = [self protocolForChannelId:channelId];
	if (![proto isConnected]) {
		TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
		if (channel) {
			TLMessage *msg = [[[TLMessage alloc] init] autorelease];
			msg.channelId = channelId;
			msg.text = command;
			msg.rawText = command;
			msg.timestamp = [NSDate date];
			msg.type = TLMessageTypeMessage;
			msg.self = YES;
			msg.pending = YES;
			TLUser *me = [[[TLUser alloc] init] autorelease];
			me.nick = _serverState.currentUserNick;
			if (!me.nick || [me.nick length] == 0) {
				me.nick = _username;
			}
			msg.sender = me;
			[channel addPendingMessage:msg];
			[[NSNotificationCenter defaultCenter]
				postNotificationName:TLLoungeMessagesDidChangeNotification
				object:self
				userInfo:@{@"channelId": @(channelId)}];
		}
		return;
	}
	[proto sendCommand:command toChannelId:channelId];
}

- (void)openChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] openChannelId:channelId];
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] requestNamesForChannelId:channelId];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
{
	[[self protocolForChannelId:channelId] loadMoreHistoryForChannelId:channelId lastId:lastId];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query
{
	[[self protocolForChannelId:channelId] loadMoreHistoryForChannelId:channelId
		lastId:lastId query:query];
}

- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset
{
	[[self protocolForChannelId:channelId] searchMessagesForChannelId:channelId
		term:term offset:offset];
}

- (void)clearHistoryForChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] clearHistoryForChannelId:channelId];
}

- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] setMuted:muted forChannelId:channelId];
}

- (void)ensureJoinedChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] ensureJoinedChannelId:channelId];
}

- (void)deleteGroupChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] deleteGroupChannelId:channelId];
}

- (void)deleteAllOwnedGroups
{
	NSMutableArray *protocols = [NSMutableArray array];
	if (_protocol != nil) {
		[protocols addObject:_protocol];
	}
	for (TLoungeProtocol *protocol in _relayProtocols) {
		[protocols addObject:protocol];
	}
	for (TLoungeProtocol *protocol in protocols) {
		[protocol deleteAllOwnedGroups];
	}
}

#pragma mark - TLSocketIOClientDelegate (network thread)

- (void)socketIOClientDidConnect:(TLSocketIOClient *)client
{
	if (client == _socketClient) {
		NSLog(@"[NOSTERM-SESSION] socketIOClientDidConnect: primary client connected");
		[self performSelectorOnMainThread:@selector(handleSocketConnected)
			withObject:nil
			waitUntilDone:NO];
	} else {
		NSLog(@"[NOSTERM-SESSION] socketIOClientDidConnect: relay client connected");
		TLoungeProtocol *protocol = [self protocolForClient:client];
		[protocol performSelectorOnMainThread:@selector(transportDidConnect)
			withObject:nil
			waitUntilDone:NO];
	}
}

- (void)socketIOClient:(TLSocketIOClient *)client didReceiveEvent:(NSString *)eventName arguments:(NSArray *)arguments
{
	TLoungeProtocol *protocol = [self protocolForClient:client];
	NSDictionary *payload = @{
		@"event": eventName,
		@"args": arguments ? arguments : @[],
		@"protocol": protocol
	};
	[self performSelectorOnMainThread:@selector(handleSocketEvent:)
		withObject:payload
		waitUntilDone:NO];
}

- (void)socketIOClientDidDisconnect:(TLSocketIOClient *)client
{
	if (client == _socketClient) {
		[self performSelectorOnMainThread:@selector(handleSocketDisconnected)
			withObject:nil
			waitUntilDone:NO];
	} else {
		[self performSelectorOnMainThread:@selector(handleRelayDisconnected:)
			withObject:client
			waitUntilDone:NO];
	}
}

- (void)socketIOClient:(TLSocketIOClient *)client didFailWithError:(NSError *)error
{
	if (client == _socketClient) {
		NSDictionary *payload = @{@"error": error};
		[self performSelectorOnMainThread:@selector(handleSocketFailure:)
			withObject:payload
			waitUntilDone:NO];
	} else {
		[[TLLogger sharedLogger] error:@"Relay socket failure: %@",
			[error localizedDescription]];
		[self scheduleRelayReconnect:client];
	}
}

#pragma mark - Main thread handlers

- (void)handleSocketConnected
{
	[self setState:TLConnectionStateSocketConnected];
	[self.protocol transportDidConnect];
}

- (void)handleSocketEvent:(id)payload
{
	TLoungeProtocol *protocol = payload[@"protocol"];
	NSString *eventName = payload[@"event"];
	NSArray *arguments = payload[@"args"];

	// One malformed event must not take down event processing for the
	// whole session; log it and keep going.
	@try {
		[protocol.dispatcher dispatchEvent:eventName arguments:arguments];
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

- (void)handleRelayDisconnected:(id)client
{
	[[TLLogger sharedLogger] info:@"Relay disconnected: %@", [client description]];
	TLoungeProtocol *protocol = [self protocolForClient:client];
	[protocol resetSession];
	[self scheduleRelayReconnect:client];
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
	if (protocol != _protocol) {
		return;
	}
	[self setState:TLConnectionStateAuthenticating];
}

- (void)protocolDidAuthenticate:(TLoungeProtocol *)protocol
{
	if (protocol != _protocol) {
		return;
	}
	[self setState:TLConnectionStateInitializing];
}

- (void)protocol:(TLoungeProtocol *)protocol authenticationFailedWithError:(NSError *)error
{
	if (protocol != _protocol) {
		return;
	}
	// A rejected stored token cannot recover on its own; drop it so the
	// next login falls back to the password the user types.
	if ([_password length] == 0 && [_sessionToken length] > 0) {
		[self clearStoredToken];
	}
	[self setState:TLConnectionStateAuthenticationFailed];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeSessionErrorNotification
		object:self
		userInfo:@{@"error": error}];
}

- (void)protocolDidBecomeReady:(TLoungeProtocol *)protocol
{
	if (protocol != _protocol) {
		// A relay finished loading; its networks were already announced via
		// the per-protocol notifications, so nothing more to do here.
		return;
	}
	_clientState.authenticated = YES;
	_reconnectAttempt = 0;
	_reconnectScheduled = NO;
	[self stopProbeTimer];

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
	// Flush any messages the user typed while the connection was down.
	[self flushPendingMessages];
}

- (void)protocol:(TLoungeProtocol *)protocol didFailWithError:(NSError *)error
{
	if (protocol != _protocol) {
		// Relay-originated errors are informational; log them but do not
		// tear down the session or transition the primary state machine.
		[[TLLogger sharedLogger] error:@"Relay error: %@",
			[error localizedDescription]];
		return;
	}
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
