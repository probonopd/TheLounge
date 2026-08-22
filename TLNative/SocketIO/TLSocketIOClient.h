/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class TLSocketIOClient;

@protocol TLSocketIOClientDelegate <NSObject>

@optional
- (void)socketIOClientDidConnect:(TLSocketIOClient *)client;
- (void)socketIOClient:(TLSocketIOClient *)client didReceiveEvent:(NSString *)eventName arguments:(NSArray *)arguments;
- (void)socketIOClientDidDisconnect:(TLSocketIOClient *)client;
- (void)socketIOClient:(TLSocketIOClient *)client didFailWithError:(NSError *)error;

@end

@interface TLSocketIOClient : NSObject

@property (nonatomic, assign) id<TLSocketIOClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;

- (void)connectToServerURL:(NSURL *)serverURL;
- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments;
- (void)close;

@end