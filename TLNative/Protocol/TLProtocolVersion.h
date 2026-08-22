/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface TLProtocolVersion : NSObject

+ (NSString *)protocolVersion;
+ (NSString *)minimumServerVersion;
+ (NSString *)maximumServerVersion;
+ (BOOL)supportsServerVersion:(NSString *)version;

@end