/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeProtocol.h"

@interface TLoungeProtocol_NOSTERN : TLoungeProtocol

// Per-connection offset into the shared NOSTERN id range so multiple relays
// (and a NOSTERN primary) produce disjoint, routable channel/message ids.
@property (nonatomic, assign) uint64_t channelIdBase;

// NOSTERN is a relay protocol; the UI uses this to back "List all channels"
// with the known NIP-29 groups instead of an IRC-style channel directory.
- (BOOL)isNosternProtocol;
- (NSArray *)knownGroupNames;
- (void)ensureJoinedChannelId:(NSInteger)channelId;
- (void)deleteGroupChannelId:(NSInteger)channelId;
- (void)deleteAllOwnedGroups;

// NIP-19 identity of this relay connection, for the identity panel.
- (NSString *)nosternPublicKeyHex;
- (NSString *)nosternPublicKeyNpub;

@end
