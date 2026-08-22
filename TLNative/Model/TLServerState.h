/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "TLNetwork.h"

@interface TLServerState : NSObject

@property (nonatomic, strong) NSMutableArray<TLNetwork *> *networks;
@property (nonatomic, assign) NSInteger activeChannelId;
@property (nonatomic, copy) NSString *currentUserNick;
@property (nonatomic, strong) NSDictionary *serverConfiguration;
@property (nonatomic, strong) NSMutableDictionary *metadata;

- (instancetype)initWithInitPayload:(NSDictionary *)payload;

- (TLNetwork *)networkWithUuid:(NSString *)uuid;
- (void)addNetwork:(TLNetwork *)network;
- (void)removeNetworkWithUuid:(NSString *)uuid;

- (TLChannel *)channelWithIdentifier:(NSInteger)identifier;
- (TLNetwork *)networkContainingChannel:(NSInteger)identifier;

- (void)clear;

@end