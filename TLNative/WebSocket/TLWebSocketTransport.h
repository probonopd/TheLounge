/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TLWebSocketState) {
	TLWebSocketStateDisconnected = 0,
	TLWebSocketStateConnecting = 1,
	TLWebSocketStateOpen = 2,
	TLWebSocketStateClosing = 3,
};

@class TLWebSocketTransport;

@protocol TLWebSocketTransportDelegate <NSObject>

@optional
- (void)webSocketDidOpen:(TLWebSocketTransport *)transport;
- (void)webSocket:(TLWebSocketTransport *)transport didReceiveData:(NSData *)data isText:(BOOL)isText;
- (void)webSocket:(TLWebSocketTransport *)transport didFailWithError:(NSError *)error;
- (void)webSocketDidClose:(TLWebSocketTransport *)transport;

@end

@interface TLWebSocketTransport : NSObject

@property (nonatomic, assign) id<TLWebSocketTransportDelegate> delegate;
@property (nonatomic, readonly) TLWebSocketState state;

- (void)connectToURL:(NSURL *)url;
- (void)sendData:(NSData *)data isText:(BOOL)isText;
- (void)close;

@end