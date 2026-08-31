/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeProtocol.h"

@interface TLoungeProtocol_Nosterm : TLoungeProtocol

// Per-connection offset into the shared Nosterm id range so multiple relays
// (and a Nosterm primary) produce disjoint, routable channel/message ids.
@property (nonatomic, assign) uint64_t channelIdBase;

// Nosterm is a relay protocol; the UI uses this to back "List all channels"
// with the known NIP-29 groups instead of an IRC-style channel directory.
- (BOOL)isNostermProtocol;
- (NSArray *)knownGroupNames;
- (void)ensureJoinedChannelId:(NSInteger)channelId;
- (void)deleteGroupChannelId:(NSInteger)channelId;
- (void)deleteAllOwnedGroups;

// NIP-19 identity of this relay connection, for the identity panel.
- (NSString *)nostermPublicKeyHex;
- (NSString *)nostermPublicKeyNpub;

@end
