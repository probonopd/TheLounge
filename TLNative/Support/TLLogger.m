/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLLogger.h"

static TLLogger *sharedInstance;
static NSLock *loggerLock;

@implementation TLLogger

+ (instancetype)sharedLogger
{
	if (!loggerLock) {
		loggerLock = [[NSLock alloc] init];
	}
	[loggerLock lock];
	if (!sharedInstance) {
		sharedInstance = [[TLLogger alloc] init];
	}
	[loggerLock unlock];
	return sharedInstance;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_level = TLLogLevelInfo;
		_protocolTraceEnabled = NO;
	}
	return self;
}

static NSString *TLLevelName(TLLogLevel level)
{
	switch (level) {
		case TLLogLevelError:
			return @"ERROR";
		case TLLogLevelWarning:
			return @"WARN";
		case TLLogLevelInfo:
			return @"INFO";
		case TLLogLevelDebug:
			return @"DEBUG";
		case TLLogLevelTrace:
			return @"TRACE";
	}
	return @"?";
}

- (void)log:(TLLogLevel)level message:(NSString *)message
{
	if (level > _level) {
		return;
	}
	NSLog(@"[%@] %@", TLLevelName(level), message);
}

- (void)error:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:TLLogLevelError message:msg];
	[msg release];
}

- (void)warning:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:TLLogLevelWarning message:msg];
	[msg release];
}

- (void)info:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:TLLogLevelInfo message:msg];
	[msg release];
}

- (void)debug:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:TLLogLevelDebug message:msg];
	[msg release];
}

- (void)trace:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:TLLogLevelTrace message:msg];
	[msg release];
}

+ (NSString *)redactSensitiveString:(NSString *)string
{
	NSMutableString *s = [string mutableCopy];

	NSArray *patterns = @[
		@"(\"password\"\\s*:\\s*\")[^\"]*(\")",
		@"(\"token\"\\s*:\\s*\")[^\"]*(\")",
		@"(\"user\"\\s*:\\s*\")[^\"]*(\")",
		@"(password=)[^&\\s\"']+",
		@"(token=)[^&\\s\"']+",
		@"(AuthToken\\s*=\\s*)[^;\\r\\n]+",
		@"(\"sid\"\\s*:\\s*\")[^\"]*(\")",
	];

	for (NSString *pattern in patterns) {
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
			options:0
			error:NULL];
		NSString *replaced = [regex stringByReplacingMatchesInString:s
			options:0
			range:NSMakeRange(0, [s length])
			withTemplate:@"$1<redacted>$2"];
		s = [replaced mutableCopy];
	}

	return s;
}

@end