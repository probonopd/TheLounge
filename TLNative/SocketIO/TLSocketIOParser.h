/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "TLSocketIOPacket.h"

@interface TLSocketIOParser : NSObject

+ (TLSocketIOPacket *)parsePacketFromString:(NSString *)string;
+ (NSString *)serializePacket:(TLSocketIOPacket *)packet;

@end