/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "TLEngineIOPacket.h"

@interface TLEngineIOParser : NSObject

+ (TLEngineIOPacket *)parsePacketFromString:(NSString *)string;
+ (NSString *)serializePacket:(TLEngineIOPacket *)packet;

@end