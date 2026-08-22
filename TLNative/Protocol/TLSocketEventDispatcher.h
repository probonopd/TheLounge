/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef void (^TLEventHandler)(NSArray *arguments);

@interface TLSocketEventDispatcher : NSObject

- (void)registerHandler:(TLEventHandler)handler forEvent:(NSString *)eventName;
- (void)unregisterEvent:(NSString *)eventName;
- (BOOL)hasHandlerForEvent:(NSString *)eventName;
- (void)dispatchEvent:(NSString *)eventName arguments:(NSArray *)arguments;

@end