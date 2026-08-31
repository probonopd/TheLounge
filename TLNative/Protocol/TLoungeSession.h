/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "TLoungeProtocol.h"

@class TLServerState;
@class TLClientState;

extern NSString *const TLLoungeSessionStateDidChangeNotification;
extern NSString *const TLLoungeSessionDidBecomeReadyNotification;
extern NSString *const TLLoungeSessionErrorNotification;

typedef NS_ENUM(NSInteger, TLConnectionState) {
	TLConnectionStateDisconnected = 0,
	TLConnectionStateConnecting = 1,
	TLConnectionStateTransportConnected = 2,
	TLConnectionStateSocketConnected = 3,
	TLConnectionStateAuthenticating = 4,
	TLConnectionStateInitializing = 5,
	TLConnectionStateReady = 6,
	TLConnectionStateReconnecting = 7,
	TLConnectionStateAuthenticationFailed = 8,
	TLConnectionStateProtocolError = 9,
	TLConnectionStateServerDisconnected = 10,
	TLConnectionStateConnectionError = 11,
};

NSString *TLConnectionStateDisplayString(TLConnectionState state);

@interface TLoungeSession : NSObject

@property (nonatomic, readonly) TLConnectionState state;
@property (nonatomic, readonly) TLServerState *serverState;
@property (nonatomic, readonly) TLClientState *clientState;
@property (nonatomic, readonly) NSString *serverURLString;
@property (nonatomic, readonly) NSString *username;
@property (nonatomic, strong) TLoungeProtocol *protocol;

- (instancetype)initWithServerURL:(NSURL *)url username:(NSString *)username;

- (void)setPassword:(NSString *)password;
- (void)setSessionToken:(NSString *)token;
- (void)setRemember:(BOOL)remember;

- (void)connect;
- (void)disconnect;
- (void)reconnect;

// Adds a NOSTERN relay connection that shares this session's server/model
// state, so its channels appear alongside the primary connection's networks.
- (void)addRelayWithURL:(NSURL *)relayURL username:(NSString *)username
	privateKey:(NSString *)privateKey;

// Joins (or creates, for NOSTERN) a channel/group on the network that owns the
// given lobby id, routing to the protocol that manages that network.
- (void)joinChannelNamed:(NSString *)name forLobbyId:(NSInteger)lobbyId;

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId;
- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId;
- (void)openChannelId:(NSInteger)channelId;
- (void)requestNamesForChannelId:(NSInteger)channelId;
- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId;
- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query;
- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset;
- (void)clearHistoryForChannelId:(NSInteger)channelId;
- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId;
- (void)ensureJoinedChannelId:(NSInteger)channelId;

// Deletes groups the NOSTERN test identity created on the relay (test hygiene).
- (void)deleteGroupChannelId:(NSInteger)channelId;
- (void)deleteAllOwnedGroups;

// Returns the protocol managing the given network/channel (the primary bouncer
// protocol, or a NOSTERN relay protocol). Used by the UI to branch behavior.
- (TLoungeProtocol *)protocolForNetwork:(TLNetwork *)network;
- (TLoungeProtocol *)protocolForChannelId:(NSInteger)channelId;

// Relay management (Nosterm client). Each entry is a dictionary with keys
// "url" (NSString), "connected" (NSNumber BOOL), "kind" (NSString:
// "nostern" or "bouncer"), and "name" (NSString display name or @"").
- (NSArray<NSDictionary *> *)connectedRelays;
- (void)disconnectRelayWithURL:(NSURL *)url;

// The Nosterm identity in NIP-19 form (npub), or nil when the session has no
// Nostern relay attached yet. Used by the identity panel.
- (NSString *)nosternPublicKeyNpub;
- (NSString *)nosternPublicKeyHex;

- (void)persistSessionToken:(NSString *)token;
- (NSString *)retrieveStoredToken;
- (void)clearStoredToken;

@end