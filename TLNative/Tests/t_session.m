/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "TLoungeSession.h"
#import "TLServerState.h"
#import "TLNetwork.h"
#import "TLLogger.h"

static BOOL g_ready = NO;
static BOOL g_failed = NO;
static NSString *g_failMessage = nil;

@interface TestObserver : NSObject
@end

@implementation TestObserver

- (void)sessionStateDidChange:(NSNotification *)notification
{
	TLoungeSession *session = notification.object;
	NSInteger state = [notification.userInfo[@"state"] integerValue];
	NSLog(@"State changed: %ld", (long)state);

	if (state == TLConnectionStateReady) {
		NSLog(@"READY - connection successful!");
		NSLog(@"Networks: %lu", (unsigned long)[session.serverState.networks count]);
		for (id net in session.serverState.networks) {
			NSLog(@"  Network: %@", [net name]);
		}
		g_ready = YES;
	}
}

- (void)sessionDidFailWithError:(NSNotification *)notification
{
	NSError *error = notification.userInfo[@"error"];
	NSLog(@"FAILED: %@", [error localizedDescription]);
	g_failed = YES;
	g_failMessage = [error localizedDescription];
}

@end

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	[[TLLogger sharedLogger] setLevel:TLLogLevelInfo];

	NSURL *url = [NSURL URLWithString:@"https://"];
	TLoungeSession *session = [[TLoungeSession alloc] initWithServerURL:url
		username:@""];
	[session setPassword:@""];

	TestObserver *observer = [[TestObserver alloc] init];
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:observer selector:@selector(sessionStateDidChange:)
		name:TLLoungeSessionStateDidChangeNotification object:session];
	[center addObserver:observer selector:@selector(sessionDidFailWithError:)
		name:TLLoungeSessionErrorNotification object:session];

	[session connect];

	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
	while (!g_ready && !g_failed && [[NSDate date] compare:deadline] == NSOrderedAscending) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
	}

	if (g_ready) {
		NSLog(@"TEST PASSED: connected and ready");
	} else if (g_failed) {
		NSLog(@"TEST FAILED: %@", g_failMessage);
	} else {
		NSLog(@"TEST TIMEOUT");
	}

	[session disconnect];
	[center removeObserver:observer];
	[observer release];
	[session release];
	[pool drain];
	return g_ready ? 0 : 1;
}
