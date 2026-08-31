/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "TLNostrCrypto.h"

static NSData *TLHexToData(NSString *hex)
{
	NSMutableData *data = [NSMutableData dataWithCapacity:[hex length] / 2];
	const char *c = [hex UTF8String];
	for (NSUInteger i = 0; i < [hex length]; i += 2) {
		char byteStr[3] = {c[i], c[i + 1], 0};
		unsigned char byte = (unsigned char)strtol(byteStr, NULL, 16);
		[data appendBytes:&byte length:1];
	}
	return data;
}

int main(void)
{
	@autoreleasepool {
		// The x-only public key for the private key 0x03 is a fixed BIP-340
		// test value; testing it pins the secp256k1 EC math.
		unsigned char k3[32] = {0};
		k3[31] = 3;
		NSData *sk3 = [NSData dataWithBytes:k3 length:32];
		NSString *pub3 = [TLNostrCrypto publicKeyXOnlyHexFromPrivateKey:sk3];
		PASS([pub3 isEqualToString:
			@"f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"],
			"x-only pubkey of secret 3 matches the BIP-340 value");

		NSData *sk = [TLNostrCrypto randomPrivateKey];
		PASS([sk length] == 32, "random private key is 32 bytes");
		NSString *pub = [TLNostrCrypto publicKeyXOnlyHexFromPrivateKey:sk];
		PASS([pub length] == 64, "derived public key is 64 hex chars");

		NSString *eventId = [TLNostrCrypto eventIdWithPubkey:pub
			createdAt:1700000000 kind:1 tags:@[@[@"e", @"abc"]] content:@"hello"];
		PASS([eventId length] == 64, "event id is 64 hex chars");

		NSString *sig = [TLNostrCrypto signEventId:eventId privateKey:sk];
		PASS([sig length] == 128, "signature is 128 hex chars");

		NSData *msg = TLHexToData(eventId);
		PASS([TLNostrCrypto verifySignature:sig pubkeyXOnlyHex:pub message:msg],
			"signature verifies against its event id");

		NSMutableData *tampered = [msg mutableCopy];
		((unsigned char *)tampered.mutableBytes)[0] ^= 1;
		PASS(![TLNostrCrypto verifySignature:sig pubkeyXOnlyHex:pub message:tampered],
			"tampered message fails verification");
		[tampered release];

		NSData *sk2 = [TLNostrCrypto randomPrivateKey];
		NSString *pub2 = [TLNostrCrypto publicKeyXOnlyHexFromPrivateKey:sk2];
		PASS(![TLNostrCrypto verifySignature:sig pubkeyXOnlyHex:pub2 message:msg],
			"signature fails under a different public key");

		NSDictionary *event = [TLNostrCrypto signedEventWithPubkey:pub
			createdAt:1700000000 kind:42
			tags:@[@[@"e", @"chan"]] content:@"hi" privateKey:sk];
		PASS(event != nil && [event[@"sig"] length] == 128 &&
			[event[@"id"] length] == 64, "signedEvent builds a complete event");
		NSData *msg2 = TLHexToData(event[@"id"]);
		PASS([TLNostrCrypto verifySignature:event[@"sig"]
			pubkeyXOnlyHex:pub message:msg2],
			"signedEvent signature verifies");

		// NIP-19 bech32: the BIP-173 empty-payload vector pins the
		// exact bech32 algorithm (not bech32m). The lowercase HRP "a"
		// yields "a12uel5l"; the uppercase "A" variant is "a1g7sgd8".
		NSString *emptyBech = [TLNostrCrypto bech32EncodeWithHrp:@"a"
			data:[NSData data]];
		PASS([emptyBech isEqualToString:@"a12uel5l"],
			"bech32(a, empty) equals the BIP-173 vector");
		NSData *decodedEmpty = [TLNostrCrypto
			bech32DecodeWithExpectedHrp:@"a" string:@"a12uel5l"];
		PASS(decodedEmpty != nil && [decodedEmpty length] == 0,
			"bech32 decode round-trips the empty vector");

		// npub/nsec round-trip: encode a key, decode it back to the same
		// bytes. This validates the 8<->5 bit conversion and checksum.
		NSString *npub = [TLNostrCrypto npubFromPrivateKey:sk];
		PASS([npub hasPrefix:@"npub1"] && [npub length] == 63,
			"npub is a 63-char bech32 string");
		NSData *pubData = [TLNostrCrypto bech32DecodeWithExpectedHrp:@"npub"
			string:npub];
		NSData *expectedPub = TLHexToData(pub);
		PASS(pubData != nil && [pubData isEqual:expectedPub],
			"npub decodes back to the public key bytes");

		NSString *nsec = [TLNostrCrypto nsecFromPrivateKey:sk];
		PASS([nsec hasPrefix:@"nsec1"], "nsec carries the nsec prefix");
		NSData *skData = [TLNostrCrypto bech32DecodeWithExpectedHrp:@"nsec"
			string:nsec];
		PASS(skData != nil && [skData isEqual:sk],
			"nsec decodes back to the private key bytes");

		PASS([TLNostrCrypto bech32DecodeWithExpectedHrp:@"npub"
			string:nsec] == nil,
			"decoding an nsec as npub fails the hrp check");
	}
	return 0;
}
