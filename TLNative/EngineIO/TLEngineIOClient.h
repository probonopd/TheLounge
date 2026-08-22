/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class TLEngineIOClient;

@protocol TLEngineIOClientDelegate <NSObject>

@optional
- (void)engineIOClientDidOpen:(TLEngineIOClient *)client;
- (void)engineIOClient:(TLEngineIOClient *)client didReceiveMessageData:(NSString *)data;
- (void)engineIOClientDidClose:(TLEngineIOClient *)client;
- (void)engineIOClient:(TLEngineIOClient *)client didFailWithError:(NSError *)error;

@end

@interface TLEngineIOClient : NSObject

@property (nonatomic, assign) id<TLEngineIOClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isOpen;
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, readonly) NSTimeInterval pingInterval;
@property (nonatomic, readonly) NSTimeInterval pingTimeout;

- (void)connectToURL:(NSURL *)url;
- (void)sendMessageData:(NSString *)data;
- (void)close;

@end