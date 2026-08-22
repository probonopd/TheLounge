/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLProtocolVersion.h"

@implementation TLProtocolVersion

+ (NSString *)protocolVersion
{
	return @"4.5";
}

+ (NSString *)minimumServerVersion
{
	return @"4.5.0";
}

+ (NSString *)maximumServerVersion
{
	return @"4.5.x";
}

+ (BOOL)supportsServerVersion:(NSString *)version
{
	if (!version) {
		return YES;
	}
	NSArray *parts = [version componentsSeparatedByString:@"."];
	if ([parts count] < 2) {
		return NO;
	}
	NSInteger major = [parts[0] integerValue];
	NSInteger minor = [parts[1] integerValue];
	return major == 4 && (minor == 5 || minor == 6 || minor == 4);
}

@end