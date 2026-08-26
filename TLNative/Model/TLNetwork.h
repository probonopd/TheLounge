/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "TLChannel.h"

@interface TLNetwork : NSObject

@property (nonatomic, copy) NSString *uuid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *nick;
@property (nonatomic, strong) NSDictionary *serverOptions;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) BOOL secure;
@property (nonatomic, strong) NSMutableArray<TLChannel *> *channels;
@property (nonatomic, strong) NSMutableDictionary *metadata;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

- (TLChannel *)channelWithIdentifier:(NSInteger)identifier;
- (TLChannel *)channelWithName:(NSString *)name;
- (void)addChannel:(TLChannel *)channel;
- (void)removeChannelWithIdentifier:(NSInteger)identifier;
- (TLChannel *)lobby;

// Total unread that belongs to this network for badge purposes: the lobby
// (server) unread plus every channel's badge count. The lobby is excluded
// from channel badge counts, so this never double-counts.
- (NSInteger)badgeTotal;

@end