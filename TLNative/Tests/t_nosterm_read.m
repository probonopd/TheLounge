/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

// CLI-only read test: connects to the Nosterm relay, subscribes to #general,
// collects messages, and prints the last 3 with resolved nicknames.
// No key needed - read-only, no auth required.
//
//   ./obj/t_nosterm_read

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "TLoungeSession.h"
#import "TLServerState.h"
#import "TLNetwork.h"
#import "TLChannel.h"
#import "TLMessage.h"
#import "TLNostrCrypto.h"
#import "TLLogger.h"

static BOOL g_ready = NO;
static BOOL g_messagesChanged = NO;

static BOOL TLWaitFor(BOOL *flag, NSTimeInterval timeout)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!*flag && [[NSDate date] compare:deadline] == NSOrderedAscending) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	}
	return *flag;
}

@interface ReadObserver : NSObject
@end

@implementation ReadObserver

- (void)stateChanged:(NSNotification *)notification
{
	NSInteger state = [notification.userInfo[@"state"] integerValue];
	if (state == TLConnectionStateReady) {
		g_ready = YES;
	}
}

- (void)messagesChanged:(NSNotification *)notification
{
	g_messagesChanged = YES;
}

@end

int main(void)
{
	@autoreleasepool {
		NSString *relay = @"wss://chat.nosterm.com/relay";
		const char *relayEnv = getenv("TL_NOSTERM_TEST_RELAY");
		if (relayEnv != NULL && relayEnv[0] != '\0') {
			relay = [NSString stringWithUTF8String:relayEnv];
		}

		[[TLLogger sharedLogger] setLevel:TLLogLevelWarning];

		NSURL *url = [NSURL URLWithString:relay];
		TLoungeSession *session = [[TLoungeSession alloc] initWithServerURL:url
			username:@"tl-read-test"];

		ReadObserver *observer = [[ReadObserver alloc] init];
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:observer selector:@selector(stateChanged:)
			name:TLLoungeSessionStateDidChangeNotification object:session];
		[center addObserver:observer selector:@selector(messagesChanged:)
			name:TLLoungeMessagesDidChangeNotification object:session];

		NSLog(@"Connecting to %@...", relay);
		[session connect];

		if (!TLWaitFor(&g_ready, 30.0)) {
			NSLog(@"FAIL: did not reach ready state within 30s");
			[session disconnect];
			[center removeObserver:observer];
			[observer release];
			[session release];
			return 1;
		}
		NSLog(@"Connected and ready.");

		// Channels arrive asynchronously from nostr-groups (kind 39000) after
		// becomeReady fires.  Wait up to 15s for #general to appear.
		TLChannel *general = nil;
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15.0];
		while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
			for (TLNetwork *n in session.serverState.networks) {
				for (TLChannel *c in n.channels) {
					if ([[c name] isEqualToString:@"general"]) {
						general = c;
						break;
					}
				}
				if (general != nil) break;
			}
			if (general != nil) break;
			g_messagesChanged = NO;
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
				beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
		}
		if (general == nil) {
			NSLog(@"FAIL: #general not found after 15s");
			for (TLNetwork *n in session.serverState.networks) {
				NSLog(@"  network '%@': %lu channels", [n name],
					(unsigned long)[[n channels] count]);
				for (TLChannel *c in n.channels) {
					NSLog(@"    ch '%@' id=%ld", [c name], (long)[c identifier]);
				}
			}
			[session disconnect];
			[center removeObserver:observer];
			[observer release];
			[session release];
			return 1;
		}

		// Wait for messages to stream in.
		NSLog(@"Collecting messages in #general (id %ld)...", (long)general.identifier);
		deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
		while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
			g_messagesChanged = NO;
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
				beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
		}

		NSArray *messages = [general messages];
		NSUInteger count = [messages count];
		NSLog(@"Total messages in #general: %lu", (unsigned long)count);

		if (count == 0) {
			NSLog(@"FAIL: no messages received");
			[session disconnect];
			[center removeObserver:observer];
			[observer release];
			[session release];
			return 1;
		}

		// Print last 3 with timestamps.
		NSLog(@"--- All %lu messages ---", (unsigned long)count);
		for (NSUInteger i = 0; i < count; i++) {
			TLMessage *m = [messages objectAtIndex:i];
			NSString *nick = [m sender] ? [[m sender] nick] : @"???";
			NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
			[fmt setDateFormat:@"HH:mm:ss"];
			NSLog(@"  [%lu] [%@] %@: %@", (unsigned long)i,
				[fmt stringFromDate:[m timestamp]], nick, [m text]);
			[fmt release];
		}

		[session disconnect];
		[center removeObserver:observer];
		[observer release];
		[session release];
		return 0;
	}
}
