/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

// Offline unit test for Nostr nickname resolution in TLoungeProtocol_NOSTERN.
//
// Nostr carries no per-message author name; names come from each user's kind 0
// metadata event (NIP-01), a replaceable event whose `content` is JSON with a
// `name` (handle) and optional `display_name` (richer name). The protocol
// fetches these per author pubkey, caches them, and displayNameForPubkey:
// resolves a pubkey to a real nickname. This test drives that path directly
// (feeding synthetic kind 0 events) without a live relay.
//
//   ./obj/t_nostern_nickname

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "TLoungeProtocol_NOSTERN.h"
#import "TLServerState.h"
#import "TLClientState.h"
#import "TLNetwork.h"
#import "TLChannel.h"
#import "TLMessage.h"

// The methods under test are private to the implementation; since the test
// binary compiles TLoungeProtocol_NOSTERN.m in-process, declaring a category
// is enough to call them.
@interface TLoungeProtocol_NOSTERN (NicknameTestAccess)
- (void)ensureKeypair;
- (NSString *)nosternPublicKeyHex;
- (NSString *)displayNameForPubkey:(NSString *)pubkey;
- (void)handleMetadataEvent:(NSDictionary *)event;
- (TLMessage *)messageFromEvent:(NSDictionary *)event channelId:(NSInteger)channelId;
@end

// A valid 64-hex seckey so ensureKeypair can derive a self pubkey.
static NSString *const kTestKey =
	@"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

static NSDictionary *Kind0Event(NSString *pubkey, NSString *content)
{
	return @{
		@"id": @"meta-event",
		@"pubkey": pubkey,
		@"created_at": @(1000),
		@"kind": @(0),
		@"tags": @[],
		@"content": content,
		@"sig": @"ignored"
	};
}

static NSDictionary *Kind42Event(NSString *pubkey, NSString *content)
{
	return @{
		@"id": @"chat-event",
		@"pubkey": pubkey,
		@"created_at": @(1001),
		@"kind": @(42),
		@"tags": @[],
		@"content": content,
		@"sig": @"ignored"
	};
}

int main(void)
{
	@autoreleasepool {
		TLServerState *ss = [[TLServerState alloc] init];
		TLClientState *cs = [[TLClientState alloc] init];

		TLoungeProtocol_NOSTERN *proto =
			[[TLoungeProtocol_NOSTERN alloc] initWithSocketClient:nil
			                                       serverState:ss
			                                      clientState:cs];
		[proto setUsername:@"tester" password:kTestKey];
		[proto ensureKeypair];

		NSString *selfPub = [proto nosternPublicKeyHex];
		NSString *author =
			@"abababababababababababababababababababababababababababababababab";
		NSString *author2 =
			@"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd";
		NSString *author3 =
			@"efefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefef";

		// --- Self is never resolved from metadata; it shows the local username.
		PASS(![author isEqualToString:selfPub],
			"test author pubkey differs from self pubkey");
		PASS([[proto displayNameForPubkey:selfPub] isEqualToString:@"tester"],
			"self pubkey resolves to the local username");

		// --- Unknown author: falls back to a truncated pubkey prefix.
		NSString *unresolved = [proto displayNameForPubkey:author];
		PASS([unresolved isEqualToString:[author substringToIndex:8]],
			"unresolved author shows truncated pubkey prefix");

		// --- kind 0 with display_name: display_name wins over name.
		[proto handleMetadataEvent:Kind0Event(author,
			@"{\"display_name\":\"Alice\",\"name\":\"alice\"}")];
		PASS([[proto displayNameForPubkey:author] isEqualToString:@"Alice"],
			"display_name is preferred over name");

		// --- kind 0 with only name: name is used.
		[proto handleMetadataEvent:Kind0Event(author2,
			@"{\"name\":\"bob\"}")];
		PASS([[proto displayNameForPubkey:author2] isEqualToString:@"bob"],
			"name is used when display_name is absent");

		// --- kind 0 with empty/garbage content: no name, falls back.
		[proto handleMetadataEvent:Kind0Event(author3, @"not json")];
		PASS([[proto displayNameForPubkey:author3]
				isEqualToString:[author3 substringToIndex:8]],
			"malformed metadata keeps the truncated-pubkey fallback");

		// --- Integration: a built chat message uses the resolved nickname.
		TLNetwork *net = [[TLNetwork alloc] init];
		[net setName:@"relay"];
		[net setUuid:@"relay"];
		[ss addNetwork:net];
		TLChannel *ch = [[TLChannel alloc] initWithDictionary:@{
			@"id": @(1),
			@"name": @"chan",
			@"type": @"channel",
			@"state": @(1)
		}];
		[net addChannel:ch];

		TLMessage *msg = [proto messageFromEvent:Kind42Event(author, @"hi Alice")
		                                channelId:1];
		PASS(msg != nil, "kind 42 event builds a TLMessage");
		PASS(msg.sender != nil, "built message has a sender");
		PASS([[msg.sender nick] isEqualToString:@"Alice"],
			"message sender nick uses the resolved display_name");

		// An author with no cached metadata yields the truncated fallback nick.
		TLMessage *msg2 = [proto messageFromEvent:Kind42Event(author3, @"hi")
		                                 channelId:1];
		PASS([[msg2.sender nick] isEqualToString:[author3 substringToIndex:8]],
			"uncached author message uses truncated fallback nick");

		// Cancel any coalesced refresh timer before tearing the protocol down.
		[NSObject cancelPreviousPerformRequestsWithTarget:proto
			selector:@selector(flushNameRefresh) object:nil];

		[proto release];
		[ch release];
		[net release];
		[cs release];
		[ss release];
		return 0;
	}
}
