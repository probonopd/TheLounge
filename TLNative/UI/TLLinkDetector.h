/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

// Shared URL support for both transcript styles: detecting links in raw
// text, decorating attributed strings, and hit-testing clicks against laid
// out text (used by the bubble renderer which draws strings itself).
@interface TLLinkDetector : NSObject

+ (NSArray<NSValue *> *)rangesOfLinksInString:(NSString *)s;
+ (NSAttributedString *)attributedStringWithLinksApplied:(NSAttributedString *)inString;
+ (NSURL *)linkAtPoint:(NSPoint)point
              inString:(NSAttributedString *)string
                width:(CGFloat)width;

@end
