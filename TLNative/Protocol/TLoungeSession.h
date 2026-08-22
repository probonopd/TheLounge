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

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId;
- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId;
- (void)openChannelId:(NSInteger)channelId;
- (void)requestNamesForChannelId:(NSInteger)channelId;
- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId;

- (void)persistSessionToken:(NSString *)token;
- (NSString *)retrieveStoredToken;
- (void)clearStoredToken;

@end