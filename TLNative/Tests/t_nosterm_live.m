/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

// Live Nosterm integration test against a real relay.
//
// This test talks to a real NOSTR relay over the network and publishes events
// (a NIP-29 group plus messages). It is gated behind an environment variable
// that holds the NOSTR private key (seckey). The key is NEVER printed, logged,
// or embedded here; the test only reads it from the environment at runtime and
// passes it to the session as the password. If the variable is unset the test
// prints a SKIP notice and exits 0 so it never fails in an unconfigured run.
//
//   export TL_NOSTERM_TEST_KEY=<64-hex-char seckey>
//   export TL_NOSTERM_TEST_RELAY=wss://relay.nosterm.com   # optional
//   ./obj/t_nosterm_live
//
// WARNING: the key in TL_NOSTERM_TEST_KEY controls a real NOSTR identity. Run
// this only with a key you are willing to publish test events under. Never
// commit a value for it.

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "TLoungeSession.h"
#import "TLServerState.h"
#import "TLNetwork.h"
#import "TLChannel.h"
#import "TLMessage.h"
#import "TLUser.h"
#import "TLNostrCrypto.h"
#import "TLLogger.h"

static BOOL g_ready = NO;
static BOOL g_failed = NO;
static NSString *g_failMessage = nil;
static BOOL g_messagesChanged = NO;
static BOOL g_usersChanged = NO;

// g_failMessage is set from notification observers and read later in main, so
// it must be retained; an autoreleased description would dangle by the time we
// log it.
static void TLSetFailMessage(NSString *message)
{
	[g_failMessage release];
	g_failMessage = [message retain];
}

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

// Pumps the main runloop (the transport delivers events to the main thread via
// performSelectorOnMainThread) until `flag` is set or `timeout` elapses.
static BOOL TLWaitFor(BOOL *flag, NSTimeInterval timeout)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!*flag && [[NSDate date] compare:deadline] == NSOrderedAscending) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	}
	return *flag;
}

@interface LiveObserver : NSObject
@end

@implementation LiveObserver

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
		TLSetFailMessage([NSString stringWithFormat:
			@"connection state %ld", (long)state]);
	}
}

- (void)didFail:(NSNotification *)notification
{
	g_failed = YES;
	NSError *error = notification.userInfo[@"error"];
	TLSetFailMessage([error localizedDescription]);
}

- (void)messagesChanged:(NSNotification *)notification
{
	g_messagesChanged = YES;
}

- (void)usersChanged:(NSNotification *)notification
{
	g_usersChanged = YES;
}

@end

static TLChannel *TLFindChannelNamed(TLoungeSession *session, NSString *name)
{
	for (TLNetwork *network in session.serverState.networks) {
		for (TLChannel *channel in network.channels) {
			if ([[channel name] isEqualToString:name]) {
				return channel;
			}
		}
	}
	return nil;
}

int main(void)
{
	@autoreleasepool {
		const char *keyEnv = getenv("TL_NOSTERM_TEST_KEY");
		if (keyEnv == NULL || keyEnv[0] == '\0') {
			printf("SKIP: TL_NOSTERM_TEST_KEY is not set; "
			       "live relay test not run.\n");
			return 0;
		}
		NSString *key = [NSString stringWithUTF8String:keyEnv];
		if ([key length] != 64) {
			printf("SKIP: TL_NOSTERM_TEST_KEY must be 64 hex chars; "
			       "live relay test not run.\n");
			return 0;
		}

		NSString *relay = @"wss://chat.nosterm.com/relay";
		const char *relayEnv = getenv("TL_NOSTERM_TEST_RELAY");
		if (relayEnv != NULL && relayEnv[0] != '\0') {
			relay = [NSString stringWithUTF8String:relayEnv];
		}

		// Derive the public key only to assert membership; the secret key is
		// never logged or echoed.
		NSData *sk = TLHexToData(key);
		NSString *pubkey = [TLNostrCrypto publicKeyXOnlyHexFromPrivateKey:sk];

		[[TLLogger sharedLogger] setLevel:TLLogLevelWarning];
		if (getenv("TL_NOSTERM_TEST_DEBUG") != NULL) {
			[[TLLogger sharedLogger] setLevel:TLLogLevelDebug];
		}

		NSURL *url = [NSURL URLWithString:relay];
		TLoungeSession *session = [[TLoungeSession alloc] initWithServerURL:url
			username:@"tl-live-test"];
		[session setPassword:key];

		LiveObserver *observer = [[LiveObserver alloc] init];
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:observer selector:@selector(stateChanged:)
			name:TLLoungeSessionStateDidChangeNotification object:session];
		[center addObserver:observer selector:@selector(didFail:)
			name:TLLoungeSessionErrorNotification object:session];
		[center addObserver:observer selector:@selector(messagesChanged:)
			name:TLLoungeMessagesDidChangeNotification object:session];
		[center addObserver:observer selector:@selector(usersChanged:)
			name:TLLoungeUserListDidChangeNotification object:session];

		NSString *host = [url host];
		NSLog(@"Connecting to relay %@ (pubkey %@)", host, pubkey);
		[session connect];

		PASS(TLWaitFor(&g_ready, 40.0), "live session reached ready state");
		if (!g_ready) {
			if (g_failMessage != nil) {
				NSLog(@"Connection failed: %@", g_failMessage);
			}
			[session disconnect];
			[center removeObserver:observer];
			[observer release];
			[session release];
			[g_failMessage release];
			g_failMessage = nil;
			return 1;
		}

		TLNetwork *relayNet = nil;
		for (TLNetwork *n in session.serverState.networks) {
			if ([[n name] isEqualToString:host]) {
				relayNet = n;
				break;
			}
		}
		PASS(relayNet != nil, "relay network present after connect");
		NSInteger lobbyId = 0;
		if (relayNet != nil && [relayNet lobby] != nil) {
			lobbyId = [[relayNet lobby] identifier];
		}

		// A uniquely named group so concurrent runs do not collide.
		NSString *groupName = [NSString stringWithFormat:@"tltest-%08x",
			(unsigned)arc4random()];
		NSLog(@"Creating NIP-29 group %@", groupName);
		g_messagesChanged = NO;
		g_usersChanged = NO;
		[session joinChannelNamed:groupName forLobbyId:lobbyId];
		for (TLNetwork *n in session.serverState.networks) {
			NSLog(@"NET '%@' channels=%lu", [n name],
				(unsigned long)[[n channels] count]);
			for (TLChannel *c in [n channels]) {
				NSLog(@"  CH id=%ld name='%@'", (long)[c identifier], [c name]);
			}
		}

		BOOL channelAppeared = NO;
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
		TLChannel *channel = nil;
		while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
			channel = TLFindChannelNamed(session, groupName);
			if (channel != nil) {
				channelAppeared = YES;
				break;
			}
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
				beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
		}
		PASS(channelAppeared, "NIP-29 group created locally and visible");

		if (channel != nil) {
			NSString *text = [NSString stringWithFormat:
				@"hello from t_nosterm_live %08x", (unsigned)arc4random()];
			NSLog(@"Sending message to %@", groupName);
			[session sendMessage:text toChannelId:channel.identifier];

			BOOL echoed = NO;
			BOOL resent = NO;
			NSDate *start = [NSDate date];
			NSDate *msgDeadline = [NSDate dateWithTimeIntervalSinceNow:25.0];
			while ([[NSDate date] compare:msgDeadline] == NSOrderedAscending) {
				for (TLMessage *m in channel.messages) {
					if ([[m text] isEqualToString:text]) {
						echoed = YES;
						break;
					}
				}
				if (echoed) {
					break;
				}
				// The relay may need a moment to apply the kind 9021 join
				// before accepting posts, so resend once if unechoed.
				if (!resent && [start timeIntervalSinceNow] < -2.0) {
					[session sendMessage:text toChannelId:channel.identifier];
					resent = YES;
				}
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
					beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
			}
			PASS(echoed, "sent message was echoed back by the relay (round-trip)");

			BOOL member = NO;
			NSDate *userDeadline = [NSDate dateWithTimeIntervalSinceNow:25.0];
			while ([[NSDate date] compare:userDeadline] == NSOrderedAscending) {
				for (TLUser *u in [[channel users] allValues]) {
					if ([[u username] isEqualToString:pubkey]) {
						member = YES;
						break;
					}
				}
				if (member) {
					break;
				}
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
					beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
			}
			PASS(member, "creator present in NIP-29 membership roster (kind 39002)");
		}

		// Test hygiene: remove the group we published so it does not accumulate
		// on the shared relay and clutter the real client.
		if (channel != nil) {
			[session deleteGroupChannelId:channel.identifier];
			// Let the delete events flush before tearing down the socket.
			[NSThread sleepForTimeInterval:2.0];
		}

		[session disconnect];
		[center removeObserver:observer];
		[observer release];
		[session release];
		return 0;
	}
}
