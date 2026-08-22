/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class TLSocketIOClient;
@class TLServerState;
@class TLClientState;
@class TLSocketEventDispatcher;
@class TLoungeProtocol;

extern NSString *const TLLoungeNetworkListDidChangeNotification;
extern NSString *const TLLoungeChannelDidChangeNotification;
extern NSString *const TLLoungeMessagesDidChangeNotification;
extern NSString *const TLLoungeUserListDidChangeNotification;
extern NSString *const TLLoungeHistoryDidChangeNotification;

@protocol TLoungeProtocolDelegate <NSObject>

@optional
- (void)protocol:(TLoungeProtocol *)protocol didReceiveAuthStart:(NSNumber *)serverHash;
- (void)protocolDidAuthenticate:(TLoungeProtocol *)protocol;
- (void)protocol:(TLoungeProtocol *)protocol authenticationFailedWithError:(NSError *)error;
- (void)protocolDidBecomeReady:(TLoungeProtocol *)protocol;
- (void)protocol:(TLoungeProtocol *)protocol didFailWithError:(NSError *)error;

@end

@interface TLoungeProtocol : NSObject

@property (nonatomic, strong) TLSocketIOClient *socketClient;
@property (nonatomic, strong) TLServerState *serverState;
@property (nonatomic, strong) TLClientState *clientState;
@property (nonatomic, strong) TLSocketEventDispatcher *dispatcher;
@property (nonatomic, assign) id<TLoungeProtocolDelegate> delegate;

@property (nonatomic, readonly) BOOL isAuthenticated;
@property (nonatomic, readonly) BOOL isReady;
@property (nonatomic, readonly) NSString *pendingUsername;
@property (nonatomic, readonly) NSString *pendingPassword;
@property (nonatomic, readonly) NSString *pendingToken;

- (void)setAuthenticated:(BOOL)authenticated;
- (void)setReady:(BOOL)ready;

- (instancetype)initWithSocketClient:(TLSocketIOClient *)client
                         serverState:(TLServerState *)serverState
                         clientState:(TLClientState *)clientState;

- (void)registerEventHandlers;
- (void)resetSession;

- (void)setUsername:(NSString *)username password:(NSString *)password;
- (void)setUsername:(NSString *)username token:(NSString *)token;

- (void)performAuthentication;

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId;
- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId;
- (void)openChannelId:(NSInteger)channelId;
- (void)requestNamesForChannelId:(NSInteger)channelId;
- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId;
- (void)clearHistoryForChannelId:(NSInteger)channelId;
- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId;

@end