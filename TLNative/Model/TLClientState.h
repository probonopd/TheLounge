/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface TLClientState : NSObject

@property (nonatomic, copy) NSString *selectedNetworkUuid;
@property (nonatomic, assign) NSInteger selectedChannelId;
@property (nonatomic, assign) BOOL authenticated;
@property (nonatomic, strong) NSMutableDictionary *windowState;
@property (nonatomic, strong) NSMutableDictionary *preferences;

- (void)resetForNewSession;

@end