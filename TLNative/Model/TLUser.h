/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class TLChannel;

@interface TLUser : NSObject

@property (nonatomic, copy) NSString *nick;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *hostname;
@property (nonatomic, copy) NSString *away;
@property (nonatomic, copy) NSArray<NSString *> *modes;
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, assign) NSInteger lastMessage;
@property (nonatomic, strong) NSMutableDictionary *metadata;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

- (BOOL)isOperator;
- (BOOL)isVoice;
- (NSString *)fullPrefix;
- (NSString *)lowercaseNick;

@end