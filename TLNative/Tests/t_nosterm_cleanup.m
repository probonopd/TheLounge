/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

// Removes NIP-29 groups the test identity published on the relay, so repeated
// live-test runs do not leave "tltest-"/"catchup-" groups cluttering a shared
// relay (and the real client that connects to it). Gated by TL_NOSTERM_TEST_KEY.
//
//   TL_NOSTERM_TEST_KEY=<64hex> ./obj/t_nosterm_cleanup
//
// Deletion is best-effort: it relies on the relay honoring NIP-09 (kind 5) and
// NIP-29 kind 9008. Groups still present after this run are not deletable on
// that relay.

#import <Foundation/Foundation.h>
#import "TLoungeSession.h"
#import "TLNostrCrypto.h"
#import "TLServerState.h"

static BOOL g_ready = NO;
static BOOL g_failed = NO;

static NSData *TLHexToData(NSString *hex)
{
	NSMutableData *data = [NSMutableData dataWithCapacity:[hex length] / 2];
	const char *c = [hex UTF8String];
	for (NSUInteger i = 0; i + 1 < [hex length]; i += 2) {
		char byteStr[3] = {c[i], c[i + 1], 0};
		unsigned char byte = (unsigned char)strtol(byteStr, NULL, 16);
		[data appendBytes:&byte length:1];
	}
	return data;
}

@interface CleanupObserver : NSObject
@end

@implementation CleanupObserver

- (void)stateChanged:(NSNotification *)notification
{
	NSInteger state = [notification.userInfo[@"state"] integerValue];
	if (state == TLConnectionStateReady) {
		g_ready = YES;
	}
	if (state == TLConnectionStateConnectionError ||
		state == TLConnectionStateAuthenticationFailed ||
		state == TLConnectionStateProtocolError) {
		g_failed = YES;
	}
}

- (void)didFail:(NSNotification *)notification
{
	g_failed = YES;
}

@end

int main(void)
{
	@autoreleasepool {
		const char *keyEnv = getenv("TL_NOSTERM_TEST_KEY");
		if (keyEnv == NULL || keyEnv[0] == '\0') {
			printf("SKIP: TL_NOSTERM_TEST_KEY is not set; "
			       "cleanup not run.\n");
			return 0;
		}
		NSString *key = [NSString stringWithUTF8String:keyEnv];
		if ([key length] != 64) {
			printf("SKIP: TL_NOSTERM_TEST_KEY must be 64 hex chars.\n");
			return 0;
		}

		NSString *relay = @"wss://chat.nosterm.com/relay";
		const char *relayEnv = getenv("TL_NOSTERM_TEST_RELAY");
		if (relayEnv != NULL && relayEnv[0] != '\0') {
			relay = [NSString stringWithUTF8String:relayEnv];
		}

		NSData *sk = TLHexToData(key);
		NSString *pubkey = [TLNostrCrypto publicKeyXOnlyHexFromPrivateKey:sk];
		printf("Cleaning up NIP-29 groups authored by %s on %s\n",
			[pubkey UTF8String], [relay UTF8String]);

		NSURL *url = [NSURL URLWithString:relay];
		TLoungeSession *session = [[TLoungeSession alloc] initWithServerURL:url
			username:@"tl-cleanup"];
		[session setPassword:key];

		CleanupObserver *observer = [[CleanupObserver alloc] init];
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:observer selector:@selector(stateChanged:)
			name:TLLoungeSessionStateDidChangeNotification object:session];
		[center addObserver:observer selector:@selector(didFail:)
			name:TLLoungeSessionErrorNotification object:session];

		[session connect];

		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
		while (!g_ready && !g_failed &&
			[[NSDate date] compare:deadline] == NSOrderedAscending) {
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
				beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
		}
		if (g_failed) {
			printf("ERROR: connection failed; cannot clean up.\n");
			[session disconnect];
			[observer release];
			[session release];
			return 1;
		}
		if (!g_ready) {
			printf("ERROR: timed out waiting for relay ready.\n");
			[session disconnect];
			[observer release];
			[session release];
			return 1;
		}

		[session deleteAllOwnedGroups];

		// Give the relay time to process the delete events.
		[NSThread sleepForTimeInterval:8.0];

		printf("Done. Any groups authored by this key were sent deletion "
		       "requests (kind 5 / kind 9008).\n");

		[session disconnect];
		[center removeObserver:observer];
		[observer release];
		[session release];
		return 0;
	}
}
