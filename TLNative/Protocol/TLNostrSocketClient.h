/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "TLSocketIOClient.h"

// Channel/message ids synthesized by NOSTERN protocols live in a reserved
// high range so they never collide with The Lounge bouncer ids (which are
// small sequential integers) nor with ids from other relays. Each relay
// owns one STRIDE-sized slice; the slot is derived by (id - BASE) / STRIDE.
extern const uint64_t TLLoungeNostrIdBase;
extern const uint64_t TLLoungeNostrIdStride;
extern const uint64_t TLLoungeNostrIdMask;

// The Nosterm project's public "Demo Relay" (relay.nosterm.com), used as a
// convenient default so the client can join the public Nosterm network.
extern NSString *const TLLoungeNosternDefaultRelayURL;

@interface TLNostrSocketClient : NSObject <NSCopying>

@property (nonatomic, assign) id<TLSocketIOClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) NSString *relayURLString;

- (void)connectToServerURL:(NSURL *)serverURL;
- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments;
- (void)close;

@end
