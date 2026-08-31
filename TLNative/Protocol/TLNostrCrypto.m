/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLNostrCrypto.h"

#include <openssl/sha.h>
#include <openssl/ec.h>
#include <openssl/obj_mac.h>
#include <openssl/bn.h>

@implementation TLNostrCrypto

static NSData *TLSHA256(NSData *data)
{
	unsigned char out[32];
	SHA256(data.bytes, data.length, out);
	return [NSData dataWithBytes:out length:32];
}

static NSString *TLHexFromData(NSData *data)
{
	const unsigned char *bytes = data.bytes;
	NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
	for (NSUInteger i = 0; i < data.length; i++) {
		[hex appendFormat:@"%02x", bytes[i]];
	}
	return hex;
}

static NSData *TLDataFromHex(NSString *hex)
{
	if (hex == nil || [hex length] % 2 != 0) {
		return nil;
	}
	NSMutableData *data = [NSMutableData dataWithCapacity:[hex length] / 2];
	const char *c = [hex UTF8String];
	for (NSUInteger i = 0; i < [hex length]; i += 2) {
		char byteStr[3] = {c[i], c[i + 1], 0};
		unsigned char byte = (unsigned char)strtol(byteStr, NULL, 16);
		[data appendBytes:&byte length:1];
	}
	return data;
}

static NSData *TLTaggedHash(NSString *tag, NSData *data)
{
	NSData *tagBytes = [tag dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char th[32];
	SHA256(tagBytes.bytes, tagBytes.length, th);
	NSMutableData *h = [NSMutableData dataWithBytes:th length:32];
	[h appendBytes:th length:32];
	[h appendData:data];
	unsigned char out[32];
	SHA256(h.bytes, h.length, out);
	return [NSData dataWithBytes:out length:32];
}

static NSData *TLSeria256(BIGNUM *bn)
{
	unsigned char buf[32];
	memset(buf, 0, sizeof(buf));
	BN_bn2binpad(bn, buf, 32);
	return [NSData dataWithBytes:buf length:32];
}

static EC_GROUP *TLSecp256k1Group(void)
{
	return EC_GROUP_new_by_curve_name(NID_secp256k1);
}

+ (NSData *)randomPrivateKey
{
	EC_GROUP *group = TLSecp256k1Group();
	BIGNUM *n = BN_new();
	BN_CTX *ctx = BN_CTX_new();
	EC_GROUP_get_order(group, n, ctx);
	BIGNUM *priv = BN_new();
	do {
		NSMutableData *buf = [NSMutableData dataWithLength:32];
		arc4random_buf(buf.mutableBytes, 32);
		BN_bin2bn(buf.bytes, 32, priv);
	} while (BN_is_zero(priv) || BN_ucmp(priv, n) >= 0);
	NSData *result = TLSeria256(priv);
	BN_free(priv);
	BN_free(n);
	BN_CTX_free(ctx);
	EC_GROUP_free(group);
	return result;
}

+ (NSString *)publicKeyXOnlyHexFromPrivateKey:(NSData *)sk
{
	if (sk == nil || [sk length] != 32) {
		return nil;
	}
	EC_GROUP *group = TLSecp256k1Group();
	BN_CTX *ctx = BN_CTX_new();
	BIGNUM *priv = BN_new();
	BN_bin2bn(sk.bytes, 32, priv);
	EC_POINT *P = EC_POINT_new(group);
	EC_POINT_mul(group, P, priv, NULL, NULL, ctx);
	BIGNUM *X = BN_new();
	BIGNUM *Y = BN_new();
	EC_POINT_get_affine_coordinates(group, P, X, Y, ctx);
	NSData *pub = TLSeria256(X);
	NSString *hex = TLHexFromData(pub);
	BN_free(X);
	BN_free(Y);
	EC_POINT_free(P);
	BN_free(priv);
	BN_CTX_free(ctx);
	EC_GROUP_free(group);
	return hex;
}

+ (NSString *)eventIdWithPubkey:(NSString *)pubkeyHex
                      createdAt:(NSUInteger)createdAt
                           kind:(NSInteger)kind
                           tags:(NSArray *)tags
                        content:(NSString *)content
{
	NSData *pubJson = [NSJSONSerialization dataWithJSONObject:pubkeyHex ? pubkeyHex : @"" options:0 error:NULL];
	NSData *contentJson = [NSJSONSerialization dataWithJSONObject:content ? content : @"" options:0 error:NULL];
	NSData *tagsJson = [NSJSONSerialization dataWithJSONObject:tags ? tags : @[] options:0 error:NULL];
	NSString *pubStr = [[NSString alloc] initWithData:pubJson encoding:NSUTF8StringEncoding];
	NSString *tagsStr = [[NSString alloc] initWithData:tagsJson encoding:NSUTF8StringEncoding];
	NSString *contentStr = [[NSString alloc] initWithData:contentJson encoding:NSUTF8StringEncoding];
	NSString *serialized = [NSString stringWithFormat:@"[0,%@,%lu,%ld,%@,%@]",
		pubStr, (unsigned long)createdAt, (long)kind, tagsStr, contentStr];
	NSData *serializedData = [serialized dataUsingEncoding:NSUTF8StringEncoding];
	return TLHexFromData(TLSHA256(serializedData));
}

+ (NSString *)signEventId:(NSString *)eventIdHex privateKey:(NSData *)sk
{
	if (sk == nil || [sk length] != 32 || [eventIdHex length] != 64) {
		return nil;
	}
	NSData *msg = TLDataFromHex(eventIdHex);
	if (msg == nil) {
		return nil;
	}
	EC_GROUP *group = TLSecp256k1Group();
	BN_CTX *ctx = BN_CTX_new();
	BIGNUM *n = BN_new();
	EC_GROUP_get_order(group, n, ctx);

	BIGNUM *priv = BN_new();
	BN_bin2bn(sk.bytes, 32, priv);

	EC_POINT *P = EC_POINT_new(group);
	EC_POINT_mul(group, P, priv, NULL, NULL, ctx);
	BIGNUM *X = BN_new();
	BIGNUM *Y = BN_new();
	EC_POINT_get_affine_coordinates(group, P, X, Y, ctx);

	BIGNUM *d = BN_new();
	if (BN_is_odd(Y)) {
		BN_sub(d, n, priv);
	} else {
		BN_copy(d, priv);
	}
	NSData *Pbytes = TLSeria256(X);
	NSData *dbytes = TLSeria256(d);

	unsigned char zero[32];
	memset(zero, 0, sizeof(zero));
	NSData *auxrand = [NSData dataWithBytes:zero length:32];
	NSMutableData *auxInput = [NSMutableData dataWithData:auxrand];
	[auxInput appendData:dbytes];
	NSData *t = TLTaggedHash(@"BIP0340/aux", auxInput);

	NSMutableData *nonceInput = [NSMutableData dataWithData:t];
	[nonceInput appendData:Pbytes];
	[nonceInput appendData:msg];
	NSData *k0bytes = TLTaggedHash(@"BIP0340/nonce", nonceInput);

	BIGNUM *k = BN_new();
	BN_bin2bn(k0bytes.bytes, 32, k);
	BN_mod(k, k, n, ctx);
	if (BN_is_zero(k)) {
		BN_free(X); BN_free(Y); BN_free(d); BN_free(k); BN_free(priv);
		BN_free(n); BN_CTX_free(ctx);
		EC_POINT_free(P); EC_GROUP_free(group);
		return nil;
	}

	EC_POINT *Rp = EC_POINT_new(group);
	EC_POINT_mul(group, Rp, k, NULL, NULL, ctx);
	BIGNUM *Rx = BN_new();
	BIGNUM *Ry = BN_new();
	EC_POINT_get_affine_coordinates(group, Rp, Rx, Ry, ctx);
	if (BN_is_odd(Ry)) {
		BN_sub(k, n, k);
		EC_POINT_mul(group, Rp, k, NULL, NULL, ctx);
		EC_POINT_get_affine_coordinates(group, Rp, Rx, Ry, ctx);
	}
	NSData *RxBytes = TLSeria256(Rx);

	NSMutableData *challengeInput = [NSMutableData dataWithData:RxBytes];
	[challengeInput appendData:Pbytes];
	[challengeInput appendData:msg];
	NSData *ebytes = TLTaggedHash(@"BIP0340/challenge", challengeInput);
	BIGNUM *e = BN_new();
	BN_bin2bn(ebytes.bytes, 32, e);
	BN_mod(e, e, n, ctx);

	BIGNUM *ed = BN_new();
	BN_mod_mul(ed, e, d, n, ctx);
	BIGNUM *s = BN_new();
	BN_mod_add(s, k, ed, n, ctx);

	NSData *RxOut = TLSeria256(Rx);
	NSData *sOut = TLSeria256(s);
	NSMutableData *sig = [NSMutableData dataWithData:RxOut];
	[sig appendData:sOut];

	BN_free(X); BN_free(Y); BN_free(d); BN_free(k); BN_free(priv);
	BN_free(n); BN_free(e); BN_free(ed); BN_free(s);
	BN_CTX_free(ctx);
	EC_POINT_free(P); EC_POINT_free(Rp); EC_GROUP_free(group);

	return TLHexFromData(sig);
}

+ (NSDictionary *)signedEventWithPubkey:(NSString *)pubkeyHex
                              createdAt:(NSUInteger)createdAt
                                   kind:(NSInteger)kind
                                   tags:(NSArray *)tags
                                content:(NSString *)content
                              privateKey:(NSData *)sk
{
	NSString *eventId = [self eventIdWithPubkey:pubkeyHex
	                                    createdAt:createdAt
	                                         kind:kind
	                                         tags:tags
	                                      content:content];
	NSString *sig = [self signEventId:eventId privateKey:sk];
	if (sig == nil) {
		return nil;
	}
	return @{
		@"id": eventId,
		@"pubkey": pubkeyHex,
		@"created_at": @(createdAt),
		@"kind": @(kind),
		@"tags": tags ? tags : @[],
		@"content": content ? content : @"",
		@"sig": sig
	};
}

+ (BOOL)verifySignature:(NSString *)sigHex
       pubkeyXOnlyHex:(NSString *)pubkeyHex
             message:(NSData *)msg
{
	if (sigHex == nil || [sigHex length] != 128 || [pubkeyHex length] != 64 || msg == nil) {
		return NO;
	}
	NSData *sig = TLDataFromHex(sigHex);
	NSData *px = TLDataFromHex(pubkeyHex);
	if (sig == nil || px == nil || [sig length] != 64 || [px length] != 32) {
		return NO;
	}
	EC_GROUP *group = TLSecp256k1Group();
	BN_CTX *ctx = BN_CTX_new();
	BIGNUM *n = BN_new();
	EC_GROUP_get_order(group, n, ctx);
	BIGNUM *p = BN_new();
	EC_GROUP_get_curve(group, p, NULL, NULL, ctx);

	BIGNUM *Rx = BN_new();
	BIGNUM *s = BN_new();
	BN_bin2bn(sig.bytes, 32, Rx);
	BN_bin2bn(sig.bytes + 32, 32, s);
	if (BN_ucmp(s, n) >= 0) {
		BN_free(n); BN_free(p); BN_free(Rx); BN_free(s);
		BN_CTX_free(ctx); EC_GROUP_free(group);
		return NO;
	}

	BIGNUM *X = BN_new();
	BN_bin2bn(px.bytes, 32, X);
	BIGNUM *y2 = BN_new();
	BN_mod_sqr(y2, X, p, ctx);
	BN_mod_mul(y2, y2, X, p, ctx);
	BIGNUM *seven = BN_new();
	BN_set_word(seven, 7);
	BN_mod_add(y2, y2, seven, p, ctx);
	BIGNUM *Y = BN_mod_sqrt(NULL, y2, p, ctx);
	if (Y == NULL) {
		BN_free(n); BN_free(p); BN_free(Rx); BN_free(s); BN_free(X);
		BN_free(y2); BN_free(seven);
		BN_CTX_free(ctx); EC_GROUP_free(group);
		return NO;
	}
	if (BN_is_odd(Y)) {
		BN_sub(Y, p, Y);
	}
	EC_POINT *P = EC_POINT_new(group);
	EC_POINT_set_affine_coordinates(group, P, X, Y, ctx);

	NSMutableData *ein = [NSMutableData dataWithBytes:sig.bytes length:32];
	[ein appendData:px];
	[ein appendData:msg];
	NSData *ebytes = TLTaggedHash(@"BIP0340/challenge", ein);
	BIGNUM *e = BN_new();
	BN_bin2bn(ebytes.bytes, 32, e);
	BN_mod(e, e, n, ctx);

	BIGNUM *negE = BN_new();
	BN_sub(negE, n, e);
	EC_POINT *Rcheck = EC_POINT_new(group);
	EC_POINT_mul(group, Rcheck, s, P, negE, ctx);

	BIGNUM *Cx = BN_new();
	BIGNUM *Cy = BN_new();
	EC_POINT_get_affine_coordinates(group, Rcheck, Cx, Cy, ctx);
	BOOL ok = (BN_ucmp(Cx, Rx) == 0) && !BN_is_odd(Cy);

	BN_free(n); BN_free(p); BN_free(Rx); BN_free(s); BN_free(X);
	BN_free(y2); BN_free(seven); BN_free(Y); BN_free(e); BN_free(negE);
	BN_free(Cx); BN_free(Cy);
	EC_POINT_free(P); EC_POINT_free(Rcheck);
	BN_CTX_free(ctx); EC_GROUP_free(group);
	return ok;
}

#pragma mark - NIP-19 bech32

// BIP-173 bech32 (lowercase). Nostr uses this alphabet, not bech32m.
static const char *TL_BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
static const int8_t TL_BECH32_CHARSET_REV[128] = {
	-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
	-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
	-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
	15,-1,10,17,21,20,26,30, 7, 5,-1,-1,-1,-1,-1,-1,
	-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
	-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
	-1,29,-1,24,13,25, 9, 8,23,-1,18,22,31,27,19,-1,
	 1, 0, 3,16,11,28,12,14, 6, 4, 2,-1,-1,-1,-1,-1
};

static uint32_t TLBech32Polymod(const uint8_t *values, size_t len)
{
	static const uint32_t GEN[5] = {0x3b6a57b2, 0x26508e6d,
		0x1ea119fa, 0x3d4233dd, 0x2a1462b3};
	uint32_t chk = 1;
	for (size_t i = 0; i < len; i++) {
		uint8_t top = (uint8_t)(chk >> 25);
		chk = ((chk & 0x1FFFFFF) << 5) ^ values[i];
		for (int j = 0; j < 5; j++) {
			if ((top >> j) & 1) {
				chk ^= GEN[j];
			}
		}
	}
	return chk;
}

static void TLBech32HrpExpand(NSString *hrp, uint8_t *out, size_t *outLen)
{
	NSData *d = [hrp dataUsingEncoding:NSUTF8StringEncoding];
	const uint8_t *b = d.bytes;
	size_t n = d.length;
	for (size_t i = 0; i < n; i++) {
		out[i] = b[i] >> 5;
	}
	out[n] = 0;
	for (size_t i = 0; i < n; i++) {
		out[n + 1 + i] = b[i] & 0x1f;
	}
	*outLen = n * 2 + 1;
}

// Constant 1 selects bech32 (not bech32m) checksum.
static void TLBech32CreateChecksum(NSString *hrp, const uint8_t *data,
	size_t dataLen, uint8_t *out5, size_t *outLen)
{
	uint8_t ext[128];
	size_t extLen = 0;
	TLBech32HrpExpand(hrp, ext, &extLen);
	size_t total = extLen + dataLen + 6;
	uint8_t *values = (uint8_t *)malloc(total);
	memcpy(values, ext, extLen);
	memcpy(values + extLen, data, dataLen);
	for (int i = 0; i < 6; i++) {
		values[extLen + dataLen + i] = 0;
	}
	uint32_t polymod = TLBech32Polymod(values, total) ^ 1;
	for (int i = 0; i < 6; i++) {
		out5[i] = (uint8_t)((polymod >> (5 * (5 - i))) & 31);
	}
	*outLen = 6;
	free(values);
}

static int TLBech32ConvertBits(uint8_t *out, size_t *outLen,
	const uint8_t *in, size_t inLen, int frombits, int tobits, int pad)
{
	uint32_t acc = 0;
	int bits = 0;
	size_t o = 0;
	int maxv = (1 << tobits) - 1;
	for (size_t i = 0; i < inLen; i++) {
		acc = (acc << frombits) | in[i];
		bits += frombits;
		while (bits >= tobits) {
			bits -= tobits;
			out[o++] = (uint8_t)((acc >> bits) & maxv);
		}
	}
	if (pad) {
		if (bits) {
			out[o++] = (uint8_t)((acc << (tobits - bits)) & maxv);
		}
	} else if (bits >= frombits || ((acc << (tobits - bits)) & maxv)) {
		return 0;
	}
	*outLen = o;
	return 1;
}

+ (NSString *)bech32EncodeWithHrp:(NSString *)hrp data:(NSData *)data
{
	if (hrp == nil || data == nil) {
		return nil;
	}
	size_t inLen = data.length;
	size_t cap = inLen * 8 / 5 + 2;
	uint8_t *conv = (uint8_t *)malloc(cap);
	size_t convLen = 0;
	if (!TLBech32ConvertBits(conv, &convLen, data.bytes, inLen, 8, 5, 1)) {
		free(conv);
		return nil;
	}
	uint8_t checksum[6];
	size_t csLen = 0;
	TLBech32CreateChecksum(hrp, conv, convLen, checksum, &csLen);
	NSMutableString *s = [NSMutableString stringWithFormat:@"%@1",
		[hrp lowercaseString]];
	for (size_t i = 0; i < convLen; i++) {
		[s appendFormat:@"%c", TL_BECH32_CHARSET[conv[i]]];
	}
	for (int i = 0; i < 6; i++) {
		[s appendFormat:@"%c", TL_BECH32_CHARSET[checksum[i]]];
	}
	free(conv);
	return s;
}

+ (NSData *)bech32DecodeWithExpectedHrp:(NSString *)expectedHrp
                                 string:(NSString *)string
{
	if (string == nil) {
		return nil;
	}
	NSString *lower = [string lowercaseString];
	NSRange sep = [lower rangeOfString:@"1"];
	if (sep.location == NSNotFound || sep.location == 0) {
		return nil;
	}
	NSString *hrp = [lower substringToIndex:sep.location];
	if (expectedHrp != nil &&
		![hrp isEqualToString:[expectedHrp lowercaseString]]) {
		return nil;
	}
	const char *c = [lower UTF8String];
	size_t dataStart = sep.location + 1;
	size_t dataLen = [lower length] - dataStart;
	if (dataLen < 6) {
		return nil;
	}
	uint8_t *conv = (uint8_t *)malloc(dataLen);
	for (size_t i = 0; i < dataLen; i++) {
		int chv = (unsigned char)c[dataStart + i];
		int8_t v = (chv < 128) ? TL_BECH32_CHARSET_REV[chv] : -1;
		if (v < 0) {
			free(conv);
			return nil;
		}
		conv[i] = (uint8_t)v;
	}
	uint8_t ext[128];
	size_t extLen = 0;
	TLBech32HrpExpand(hrp, ext, &extLen);
	size_t total = extLen + dataLen;
	uint8_t *values = (uint8_t *)malloc(total);
	memcpy(values, ext, extLen);
	memcpy(values + extLen, conv, dataLen);
	// A valid bech32 code word has polymod == 1 (checksum was (poly ^ 1)).
	uint32_t pm = TLBech32Polymod(values, total);
	free(values);
	if (pm != 1) {
		free(conv);
		return nil;
	}
	size_t payloadLen = dataLen - 6;
	size_t cap = payloadLen * 5 / 8 + 2;
	uint8_t *out = (uint8_t *)malloc(cap);
	size_t outLen = 0;
	if (!TLBech32ConvertBits(out, &outLen, conv, payloadLen, 5, 8, 0)) {
		free(conv);
		free(out);
		return nil;
	}
	NSData *result = [NSData dataWithBytes:out length:outLen];
	free(conv);
	free(out);
	return result;
}

+ (NSString *)npubFromPubkeyHex:(NSString *)pubkeyHex
{
	NSData *d = TLDataFromHex(pubkeyHex);
	if (d == nil || [d length] != 32) {
		return nil;
	}
	return [self bech32EncodeWithHrp:@"npub" data:d];
}

+ (NSString *)npubFromPrivateKey:(NSData *)sk
{
	NSString *pub = [self publicKeyXOnlyHexFromPrivateKey:sk];
	return [self npubFromPubkeyHex:pub];
}

+ (NSString *)nsecFromPrivateKey:(NSData *)sk
{
	if (sk == nil || [sk length] != 32) {
		return nil;
	}
	return [self bech32EncodeWithHrp:@"nsec" data:sk];
}

@end
