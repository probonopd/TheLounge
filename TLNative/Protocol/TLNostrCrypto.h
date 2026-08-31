/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface TLNostrCrypto : NSObject

// A fresh 32-byte secp256k1 private key.
+ (NSData *)randomPrivateKey;

// x-only (32-byte) hex public key for a 32-byte private key.
+ (NSString *)publicKeyXOnlyHexFromPrivateKey:(NSData *)sk;

// NIP-01 event id: SHA256 of the canonical serialized event, as 64-char hex.
+ (NSString *)eventIdWithPubkey:(NSString *)pubkeyHex
                       createdAt:(NSUInteger)createdAt
                            kind:(NSInteger)kind
                            tags:(NSArray *)tags
                         content:(NSString *)content;

// BIP-340 Schnorr signature of a 64-char event id, as 128-char hex.
+ (NSString *)signEventId:(NSString *)eventIdHex privateKey:(NSData *)sk;

// Builds a fully-signed event dictionary (id, pubkey, created_at, kind, tags,
// content, sig) ready to be sent to a relay.
+ (NSDictionary *)signedEventWithPubkey:(NSString *)pubkeyHex
                              createdAt:(NSUInteger)createdAt
                                   kind:(NSInteger)kind
                                   tags:(NSArray *)tags
                                content:(NSString *)content
                              privateKey:(NSData *)sk;

// Verifies a BIP-340 signature over a 32-byte message (the event id).
+ (BOOL)verifySignature:(NSString *)sigHex
        pubkeyXOnlyHex:(NSString *)pubkeyHex
              message:(NSData *)msg;

// NIP-19 bech32 encoding used for human-readable keys. Nostr uses the
// original bech32 alphabet (not bech32m), lowercase.
+ (NSString *)bech32EncodeWithHrp:(NSString *)hrp data:(NSData *)data;

// Decodes a bech32 string, returning the payload bytes. When expectedHrp is
// non-nil it must match the string's human-readable part or nil is returned.
// Returns nil on any malformed input or failed checksum.
+ (NSData *)bech32DecodeWithExpectedHrp:(NSString *)expectedHrp
                                 string:(NSString *)string;

// npub/nsec (NIP-19) helpers built on the bech32 encoder.
+ (NSString *)npubFromPubkeyHex:(NSString *)pubkeyHex;
+ (NSString *)npubFromPrivateKey:(NSData *)sk;
+ (NSString *)nsecFromPrivateKey:(NSData *)sk;

@end
