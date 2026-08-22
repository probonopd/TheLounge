/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TLLogLevel) {
	TLLogLevelError = 0,
	TLLogLevelWarning = 1,
	TLLogLevelInfo = 2,
	TLLogLevelDebug = 3,
	TLLogLevelTrace = 4,
};

@interface TLLogger : NSObject

@property (nonatomic, assign) TLLogLevel level;
@property (nonatomic, assign) BOOL protocolTraceEnabled;

+ (instancetype)sharedLogger;

- (void)log:(TLLogLevel)level message:(NSString *)message;
- (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)warning:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)trace:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

+ (NSString *)redactSensitiveString:(NSString *)string;

@end