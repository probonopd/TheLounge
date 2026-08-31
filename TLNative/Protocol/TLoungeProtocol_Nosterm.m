/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeProtocol_Nosterm.h"
#import "TLNostrCrypto.h"
#import "TLNostrSocketClient.h"
#import "TLSocketEventDispatcher.h"
#import "TLServerState.h"
#import "TLNetwork.h"
#import "TLChannel.h"
#import "TLMessage.h"
#import "TLUser.h"
#import "TLClientState.h"
#import "TLLogger.h"

#include <ctype.h>

// Search results use a private negative id space so they never collide with
// real (positive) relay message ids when the UI renders them alongside history.
static const NSInteger TLLoungeNostrSearchIdBase = -100000000;

@interface TLoungeProtocol_Nosterm ()
{
	TLNetwork *_relayNetwork;
	NSMutableDictionary *_intToNostrChannelId;
	NSMutableDictionary *_nostrChannelIdToInt;
	uint64_t _channelIdBase;
	// NIP-29 group addresses (relay:url:id) keyed alongside NIP-28 channel
	// event ids; lets a channel id resolve to its group address when sending.
	NSMutableSet *_nip29ChannelIds;
	NSMutableSet *_pendingEose;
	NSMutableArray *_searchResults;
	NSString *_searchSubId;
	NSInteger _searchChannelId;
	NSData *_privateKey;
	NSString *_pubkeyHex;
	NSString *_authChallenge;
	NSString *_authEventId;
	BOOL _ready;
	// Offline catch-up: per-channel cursor (most recent seen NOSTR id +
	// created_at) persisted to disk, plus an in-session dedup set so a message
	// delivered by both a global and a per-channel subscription is added once.
	NSMutableDictionary *_channelCursors;
	NSMutableSet *_seenEventIds;
	NSString *_storePath;
	// Event id of the kind 39000 we published when creating a group, so the
	// group can be deleted (kind 5) on test teardown.
	NSMutableDictionary *_groupEventIds;
	// Event ids already queued for deletion during a bulk cleanup, to avoid
	// re-deleting echoes of our own delete events.
	NSMutableSet *_cleanupDeletedIds;
	// Resolved Nostr display names, keyed by author pubkey (hex). Nostr has no
	// per-message nickname; names come from each user's kind 0 metadata event
	// (NIP-01), which we fetch once per pubkey and cache here.
	NSMutableDictionary *_pubkeyToName;
	// Pubkeys we have already asked the relay for (kind 0) so we don't open a
	// duplicate subscription for the same author.
	NSMutableSet *_requestedMeta;
	// Locally-added outgoing messages keyed by synthesized message id; lets
	// handleOk: remove the message from the channel if the relay rejects it,
	// and lets handleEvent: dedup the relay echo of an accepted message.
	NSMutableDictionary *_localMessageById;
	// Pending retries: event-id -> NSDictionary (event dict + channelId) for
	// messages rejected by the relay (e.g. timing race with 9021 join).
	NSMutableDictionary *_pendingRetries;
}
@end

@implementation TLoungeProtocol_Nosterm

- (instancetype)initWithSocketClient:(TLSocketIOClient *)client
                         serverState:(TLServerState *)serverState
                         clientState:(TLClientState *)clientState
{
	self = [super initWithSocketClient:client serverState:serverState clientState:clientState];
	if (self) {
		_intToNostrChannelId = [[NSMutableDictionary alloc] init];
		_nostrChannelIdToInt = [[NSMutableDictionary alloc] init];
		_nip29ChannelIds = [[NSMutableSet alloc] init];
		_pendingEose = [[NSMutableSet alloc] init];
		_searchResults = [[NSMutableArray alloc] init];
		_searchSubId = nil;
		_searchChannelId = 0;
		_privateKey = nil;
		_pubkeyHex = nil;
		_authChallenge = nil;
		_ready = NO;
		_channelCursors = [[NSMutableDictionary alloc] init];
		_seenEventIds = [[NSMutableSet alloc] init];
		_storePath = nil;
		_groupEventIds = [[NSMutableDictionary alloc] init];
		_cleanupDeletedIds = [[NSMutableSet alloc] init];
		_pubkeyToName = [[NSMutableDictionary alloc] init];
		_requestedMeta = [[NSMutableSet alloc] init];
		_localMessageById = [[NSMutableDictionary alloc] init];
		_pendingRetries = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_relayNetwork release];
	[_intToNostrChannelId release];
	[_nostrChannelIdToInt release];
	[_nip29ChannelIds release];
	[_pendingEose release];
	[_searchResults release];
	[_searchSubId release];
	[_channelCursors release];
	[_seenEventIds release];
	[_storePath release];
	[_groupEventIds release];
	[_cleanupDeletedIds release];
	[_pubkeyToName release];
	[_requestedMeta release];
	[_localMessageById release];
	[_pendingRetries release];
	[_privateKey release];
	[_pubkeyHex release];
	[_authChallenge release];
	[_authEventId release];
	[super dealloc];
}

#pragma mark - Identity

- (void)ensureKeypair
{
	if (_privateKey != nil) {
		NSLog(@"[NOSTERM] ensureKeypair: already have key, pubkey=%@", _pubkeyHex);
		return;
	}
	NSLog(@"[NOSTERM] ensureKeypair: no key yet, looking for one...");
	NSData *key = nil;
	NSString *candidate = [self.pendingPassword stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([candidate length] == 64) {
		const char *c = [candidate UTF8String];
		BOOL hex = YES;
		for (int i = 0; i < 64; i++) {
			if (!isxdigit((unsigned char)c[i])) {
				hex = NO;
				break;
			}
		}
		if (hex) {
			unsigned char bytes[32];
			for (int i = 0; i < 32; i++) {
				char b[3] = {c[i * 2], c[i * 2 + 1], 0};
				bytes[i] = (unsigned char)strtol(b, NULL, 16);
			}
			key = [NSData dataWithBytes:bytes length:32];
		}
	}
	if (key == nil) {
		key = [self loadPersistedKey];
		if (key != nil) {
			NSLog(@"[NOSTERM] ensureKeypair: loaded persisted key");
		}
	}
	if (key == nil) {
		key = [TLNostrCrypto randomPrivateKey];
		NSLog(@"[NOSTERM] ensureKeypair: generated new random key");
		[self persistKey:key];
	}
	_privateKey = [key retain];
	_pubkeyHex = [[TLNostrCrypto publicKeyXOnlyHexFromPrivateKey:_privateKey] retain];
	NSLog(@"[NOSTERM] ensureKeypair: ready, pubkey=%@", _pubkeyHex);
}

- (NSString *)relayURLString
{
	TLNostrSocketClient *client = (TLNostrSocketClient *)self.socketClient;
	return [client relayURLString];
}

- (TLNetwork *)managedNetwork
{
	return _relayNetwork;
}

- (BOOL)isNostermProtocol
{
	return YES;
}

- (NSString *)nostermPublicKeyHex
{
	return _pubkeyHex;
}

- (NSString *)nostermPublicKeyNpub
{
	if ([_pubkeyHex length] == 0) {
		return nil;
	}
	return [TLNostrCrypto npubFromPubkeyHex:_pubkeyHex];
}

- (NSArray *)knownGroupNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (NSNumber *cid in _nip29ChannelIds) {
		TLChannel *channel = [self.serverState channelWithIdentifier:[cid integerValue]];
		if (channel != nil && [channel.name length] > 0) {
			[names addObject:channel.name];
		}
	}
	[names sortUsingSelector:@selector(compare:)];
	return names;
}

- (void)ensureJoinedChannelId:(NSInteger)channelId
{
	NSString *address = _intToNostrChannelId[@(channelId)];
	if (address != nil && [_nip29ChannelIds containsObject:@(channelId)]) {
		[self sendJoinForGroupAddress:address];
	}
}

// NIP-29 group ids are short, lowercase, and limited to a safe character set.
- (NSString *)normalizeGroupId:(NSString *)name
{
	NSString *s = [name stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([s hasPrefix:@"#"]) {
		s = [s substringFromIndex:1];
	}
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < [s length]; i++) {
		unichar c = [s characterAtIndex:i];
		if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
			[out appendFormat:@"%C", c];
		} else if (c >= 'A' && c <= 'Z') {
			[out appendFormat:@"%C", (unichar)(c - 'A' + 'a')];
		}
	}
	return [out length] > 0 ? [out copy] : nil;
}

- (NSString *)displayNameForPubkey:(NSString *)pubkey
{
	if ([pubkey isEqualToString:_pubkeyHex]) {
		NSString *name = [self.pendingUsername stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([name length] > 0) {
			return name;
		}
		return @"you";
	}
	NSString *cached = _pubkeyToName[pubkey];
	if ([cached length] > 0) {
		return cached;
	}
	// Trigger a background fetch of this author's kind 0 profile so the next
	// render can show a real name instead of the truncated pubkey.
	[self requestMetadataForPubkey:pubkey];
	if ([pubkey length] >= 8) {
		return [pubkey substringToIndex:8];
	}
	return pubkey;
}

#pragma mark - Nostr display names (kind 0 metadata)

- (void)requestMetadataForPubkey:(NSString *)pubkey
{
	if ([pubkey length] == 0 || [pubkey isEqualToString:_pubkeyHex]) {
		return;
	}
	if (_pubkeyToName[pubkey] != nil || [_requestedMeta containsObject:pubkey]) {
		return;
	}
	[_requestedMeta addObject:pubkey];
	NSString *subId = [NSString stringWithFormat:@"meta-%@", pubkey];
	[self sendReq:subId filter:@{
		@"kinds": @[@(0)],
		@"authors": @[pubkey],
		@"limit": @(1)
	}];
}

- (void)handleMetadataEvent:(NSDictionary *)event
{
	NSString *pubkey = [event[@"pubkey"] description];
	if ([pubkey length] == 0) {
		return;
	}
	id content = event[@"content"];
	NSString *name = nil;
	if ([content isKindOfClass:[NSString class]] && [content length] > 0) {
		NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
		NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:data
			options:0 error:NULL];
		if ([meta isKindOfClass:[NSDictionary class]]) {
			if ([meta[@"display_name"] length] > 0) {
				name = [meta[@"display_name"] description];
			} else if ([meta[@"name"] length] > 0) {
				name = [meta[@"name"] description];
			}
		}
	}
	NSLog(@"[NOSTERM] handleMetadata: pubkey=%@ name='%@' content=%@", pubkey, name, content);
	if ([name length] == 0) {
		return;
	}
	_pubkeyToName[pubkey] = name;
	[self scheduleNameRefresh];
}

// Coalesce the many kind 0 replies that arrive in a burst into a single UI
// refresh so we don't repopulate the transcript once per resolved author.
- (void)scheduleNameRefresh
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(flushNameRefresh) object:nil];
	[self performSelector:@selector(flushNameRefresh) withObject:nil afterDelay:0.4];
}

- (void)flushNameRefresh
{
	// Update every stored message whose author is now named, so the open
	// transcript shows the resolved nickname without waiting for a reopen.
	for (TLNetwork *network in self.serverState.networks) {
		for (TLChannel *channel in [network channels]) {
			for (TLMessage *message in [channel messages]) {
				TLUser *sender = message.sender;
				if (sender == nil) {
					continue;
				}
				NSString *resolved = _pubkeyToName[sender.username];
				if (resolved != nil && ![resolved isEqualToString:sender.nick]) {
					[sender setNick:resolved];
				}
			}
		}
	}
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNicknamesDidChangeNotification
		object:self];
}

#pragma mark - Identifier synthesis

- (NSInteger)channelIntIdForNostrId:(NSString *)nostrId
{
	NSNumber *existing = _nostrChannelIdToInt[nostrId];
	if (existing != nil) {
		return [existing integerValue];
	}
	uint64_t h = 1469598103934665603ULL;
	const char *c = [nostrId UTF8String];
	for (; *c != 0; c++) {
		h ^= (unsigned char)*c;
		h *= 1099511628211ULL;
	}
	NSInteger identifier = (NSInteger)(_channelIdBase + (h & TLLoungeNostrIdMask));
	if (identifier == 0) {
		identifier = 1;
	}
	_nostrChannelIdToInt[nostrId] = @(identifier);
	_intToNostrChannelId[@(identifier)] = nostrId;
	return identifier;
}

- (NSInteger)messageIntIdForNostrId:(NSString *)nostrId
{
	uint64_t h = 1469598103934665603ULL;
	const char *c = [nostrId UTF8String];
	for (; *c != 0; c++) {
		h ^= (unsigned char)*c;
		h *= 1099511628211ULL;
	}
	NSInteger identifier = (NSInteger)(_channelIdBase + (h & TLLoungeNostrIdMask));
	return identifier == 0 ? 1 : identifier;
}

#pragma mark - Relay network

- (void)ensureRelayNetwork
{
	if (_relayNetwork != nil) {
		NSLog(@"[NOSTERM] ensureRelayNetwork: already have network '%@'", _relayNetwork.name);
		return;
	}
	NSString *host = [[NSURL URLWithString:[self relayURLString]] host];
	if ([host length] == 0) {
		host = @"nostr";
	}
	NSLog(@"[NOSTERM] ensureRelayNetwork: creating network for host='%@' relay='%@'", host, [self relayURLString]);
	_relayNetwork = [[TLNetwork alloc] init];
	[_relayNetwork setUuid:host];
	[_relayNetwork setName:host];
	[_relayNetwork setConnected:YES];
	[self.serverState addNetwork:_relayNetwork];
	[self.serverState setCurrentUserNick:[self displayNameForPubkey:_pubkeyHex]];
	// Announce the new relay network immediately so it shows up in the outline
	// as soon as the socket opens, without waiting for the first subscription.
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification
		object:self];
}

#pragma mark - Handshake / subscriptions

- (void)transportDidConnect
{
	NSLog(@"[NOSTERM] transportDidConnect: relay connected, relay='%@'", [self relayURLString]);
	_ready = NO;
	[_pendingEose removeAllObjects];
	[self ensureKeypair];
	[self ensureRelayNetwork];
	[self loadLocalStore];

	// Signal auth start to the session state machine. The actual
	// protocolDidAuthenticate: call is deferred until either:
	//  - the relay sends an AUTH challenge and we complete the NIP-42
	//    handshake (handleOk: for the kind-22242 event), or
	//  - the bootstrap subscriptions return EOSE without a prior AUTH
	//    challenge, meaning the relay does not require authentication.
	[self.delegate protocol:self didReceiveAuthStart:@(0)];

	NSLog(@"[NOSTERM] transportDidConnect: sending initial subscriptions");
	[self sendReq:@"nostr-channels" filter:@{@"kinds": @[@(40)], @"limit": @(100)}];
	[self sendReq:@"nostr-groups" filter:@{@"kinds": @[@(39000), @(39002)], @"limit": @(200)}];
	[self sendReq:@"nostr-msgs" filter:@{@"kinds": @[@(42)], @"limit": @(200)}];
	// Bulk kind-0 metadata: many relays do not serve individual per-author
	// subscriptions for kind 0, but they do include kind 0 in a catch-all.
	// This covers display_name resolution for active users on the relay.
	[self sendReq:@"nostr-meta" filter:@{@"kinds": @[@(0)], @"limit": @(200)}];
	// Only bootstrap subscriptions that gate readiness go into _pendingEose.
	// nostr-groups is excluded: it streams hundreds of 39002 events and would
	// block becomeReady indefinitely on a busy relay.
	[_pendingEose addObject:@"nostr-channels"];
	[_pendingEose addObject:@"nostr-msgs"];

	[self resubscribeAllChannels];

	// Publish a kind-0 metadata event so other clients see our display name
	// instead of a truncated pubkey.
	[self publishKind0Metadata];
}

- (void)sendReq:(NSString *)subId filter:(NSDictionary *)filter
{
	[self.socketClient emitEvent:@"REQ" withArguments:@[subId, filter]];
}

// Publishes a kind-0 (NIP-01) metadata event so other clients see our display
// name instead of a bare truncated pubkey.  Best-effort: a failure here is not
// fatal.
- (void)publishKind0Metadata
{
	NSString *name = self.pendingUsername;
	if ([name length] == 0) {
		return;
	}
	[self ensureKeypair];
	NSDictionary *content = @{
		@"name": name,
		@"display_name": name
	};
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:content
		options:0 error:nil];
	NSString *jsonString = [[[NSString alloc] initWithData:jsonData
		encoding:NSUTF8StringEncoding] autorelease];
	NSDictionary *event = [TLNostrCrypto signedEventWithPubkey:_pubkeyHex
		createdAt:(NSUInteger)time(NULL)
		kind:0
		tags:@[]
		content:jsonString
		privateKey:_privateKey];
	if (event != nil) {
		[self.socketClient emitEvent:@"EVENT" withArguments:@[event]];
	}
}

#pragma mark - Offline catch-up

// Per-channel cursor: the most recent NOSTR event id + created_at we have
// persisted. Survives relaunch via a small per-relay plist so a reconnect can
// ask the relay for everything since the last message we saw.
- (NSInteger)cursorTimestampForChannel:(NSInteger)channelId
{
	NSDictionary *c = _channelCursors[@(channelId)];
	return c ? [c[@"ts"] integerValue] : 0;
}

- (void)recordEventSeen:(NSString *)nostrId timestamp:(NSInteger)ts forChannel:(NSInteger)channelId
{
	if ([nostrId length] > 0) {
		[_seenEventIds addObject:nostrId];
	}
	NSDictionary *cur = _channelCursors[@(channelId)];
	NSInteger curTs = cur ? [cur[@"ts"] integerValue] : 0;
	if (ts > curTs) {
		[_channelCursors setObject:@{@"id": (nostrId ?: @""), @"ts": @(ts)}
			forKey:@(channelId)];
		[self saveLocalStore];
	}
}

- (NSString *)storePath
{
	if (_storePath == nil) {
		NSString *host = [[NSURL URLWithString:[self relayURLString]] host];
		if ([host length] == 0) {
			host = @"nostr";
		}
		NSArray *dirs = NSSearchPathForDirectoriesInDomains(
			NSApplicationSupportDirectory, NSUserDomainMask, YES);
		NSString *dir = [dirs count] > 0 ? [dirs objectAtIndex:0] : NSTemporaryDirectory();
		dir = [dir stringByAppendingPathComponent:@"TheLounge"];
		[[NSFileManager defaultManager] createDirectoryAtPath:dir
			withIntermediateDirectories:YES attributes:nil error:NULL];
		_storePath = [[dir stringByAppendingPathComponent:
			[NSString stringWithFormat:@"nostr-cursor-%@.plist", host]] retain];
	}
	return _storePath;
}

- (void)loadLocalStore
{
	[_channelCursors removeAllObjects];
	NSDictionary *store = [NSDictionary dictionaryWithContentsOfFile:[self storePath]];
	if (store == nil) {
		return;
	}
	NSDictionary *cursors = store[@"cursors"];
	if (![cursors isKindOfClass:[NSDictionary class]]) {
		return;
	}
	for (id key in cursors) {
		NSNumber *ck = [key isKindOfClass:[NSNumber class]] ? key : @([key integerValue]);
		id val = [cursors objectForKey:key];
		if ([val isKindOfClass:[NSDictionary class]]) {
			[_channelCursors setObject:val forKey:ck];
		}
	}
}

- (void)saveLocalStore
{
	NSMutableDictionary *store = [NSMutableDictionary dictionary];
	store[@"cursors"] = _channelCursors;
	if (_privateKey != nil) {
		const unsigned char *bytes = [_privateKey bytes];
		if ([_privateKey length] == 32) {
			char hex[65];
			for (int i = 0; i < 32; i++) {
				snprintf(hex + i * 2, 3, "%02x", bytes[i]);
			}
			hex[64] = 0;
			store[@"privateKey"] = [NSString stringWithUTF8String:hex];
		}
	}
	[(NSDictionary *)store writeToFile:[self storePath] atomically:YES];
}

- (NSData *)loadPersistedKey
{
	NSDictionary *store = [NSDictionary dictionaryWithContentsOfFile:[self storePath]];
	NSString *hex = store[@"privateKey"];
	if (![hex isKindOfClass:[NSString class]] || [hex length] != 64) {
		return nil;
	}
	const char *c = [hex UTF8String];
	for (int i = 0; i < 64; i++) {
		if (!isxdigit((unsigned char)c[i])) {
			return nil;
		}
	}
	unsigned char bytes[32];
	for (int i = 0; i < 32; i++) {
		char b[3] = {c[i * 2], c[i * 2 + 1], 0};
		bytes[i] = (unsigned char)strtol(b, NULL, 16);
	}
	return [NSData dataWithBytes:bytes length:32];
}

- (void)persistKey:(NSData *)key
{
	[self saveLocalStore];
}

// Re-open a per-channel subscription bounded by that channel's cursor. A single
// message can arrive via both a global subscription and this one, so the
// per-message NOSTR id dedup (in the handlers) keeps it from being added twice.
- (void)resubscribeAllChannels
{
	for (NSNumber *cid in _intToNostrChannelId) {
		NSInteger channelId = [cid integerValue];
		NSString *address = _intToNostrChannelId[cid];
		NSString *subId = [NSString stringWithFormat:@"ch-%ld", (long)channelId];
		NSInteger since = [self cursorTimestampForChannel:channelId] + 1;
		NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	if ([_nip29ChannelIds containsObject:cid]) {
		[filter setObject:@[@(9)] forKey:@"kinds"];
		NSString *groupId = [self bareGroupIdForAddress:address];
		[filter setObject:@[groupId, address] forKey:@"#h"];
	} else {
			[filter setObject:@[@(42)] forKey:@"kinds"];
			[filter setObject:@[address] forKey:@"#e"];
		}
	[filter setObject:@(100) forKey:@"limit"];
	if (since > 1) {
		[filter setObject:@(since) forKey:@"since"];
	}
	[self sendReq:subId filter:filter];
}
}

- (void)registerEventHandlers
{
	__block typeof(self) weakSelf = self;
	[self.dispatcher registerHandler:^(NSArray *args) {
		[weakSelf handleEvent:args];
	} forEvent:@"EVENT"];
	[self.dispatcher registerHandler:^(NSArray *args) {
		[weakSelf handleEose:args];
	} forEvent:@"EOSE"];
	[self.dispatcher registerHandler:^(NSArray *args) {
		[weakSelf handleOk:args];
	} forEvent:@"OK"];
	[self.dispatcher registerHandler:^(NSArray *args) {
		[weakSelf handleAuth:args];
	} forEvent:@"AUTH"];
	[self.dispatcher registerHandler:^(NSArray *args) {
		[weakSelf handleNotice:args];
	} forEvent:@"NOTICE"];
	[self.dispatcher registerHandler:^(NSArray *args) {
		[weakSelf handleClosed:args];
	} forEvent:@"CLOSED"];
	[self.dispatcher registerHandler:^(NSArray *args) {
		[weakSelf handleCount:args];
	} forEvent:@"COUNT"];
}

#pragma mark - Event handlers

- (void)handleEvent:(NSArray *)args
{
	if ([args count] < 2) {
		NSLog(@"[NOSTERM] handleEvent: too few args (%lu)", (unsigned long)[args count]);
		return;
	}
	NSString *subId = [args[0] description];
	NSDictionary *event = args[1];
	if (![event isKindOfClass:[NSDictionary class]]) {
		NSLog(@"[NOSTERM] handleEvent: event is not a dict, class=%@", NSStringFromClass([event class]));
		return;
	}
	NSInteger kind = [event[@"kind"] integerValue];
	if (kind == 40) {
		[self handleChannelCreate:event];
	} else if (kind == 41) {
		[self handleChannelMetadataUpdate:event];
	} else if (kind == 42) {
		if (_searchSubId != nil && [subId isEqualToString:_searchSubId]) {
			[self handleSearchEvent:event];
		} else {
			[self handleChannelMessage:event];
		}
	} else if (kind == 39000) {
		if ([subId isEqualToString:@"nostr-cleanup"]) {
			// Bulk-cleanup query: delete every group we authored.
			[self deleteOwnedGroupEvent:event];
		} else {
			[self handleGroupMetadata:event];
		}
	} else if (kind == 39002) {
		[self handleGroupMembers:event];
	} else if (kind == 9) {
		if (_searchSubId != nil && [subId isEqualToString:_searchSubId]) {
			[self handleSearchEvent:event];
		} else {
			[self handleGroupMessage:event];
		}
	} else if (kind == 0) {
		[self handleMetadataEvent:event];
	}
}

- (void)handleChannelCreate:(NSDictionary *)event
{
	NSString *nostrId = [event[@"id"] description];
	if ([nostrId length] == 0) {
		return;
	}
	if (_nostrChannelIdToInt[nostrId] != nil) {
		return;
	}
	NSInteger intId = [self channelIntIdForNostrId:nostrId];

	NSString *name = @"channel";
	id content = event[@"content"];
	if ([content isKindOfClass:[NSString class]] && [content length] > 0) {
		NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
		NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		if ([meta isKindOfClass:[NSDictionary class]] && meta[@"name"]) {
			name = [meta[@"name"] description];
		}
	}

	[self ensureRelayNetwork];
	TLChannel *channel = [[TLChannel alloc] initWithDictionary:@{
		@"id": @(intId),
		@"name": name,
		@"type": @"channel",
		@"state": @(TLChannelStateJoined)
	}];
	[_relayNetwork addChannel:channel];
	[channel release];

	// Open a per-channel subscription bounded by this channel's cursor so the
	// most recent (or, on first discovery, all) messages are fetched.
	NSString *subId = [NSString stringWithFormat:@"ch-%ld", (long)intId];
	NSInteger since = [self cursorTimestampForChannel:intId] + 1;
	NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	[filter setObject:@[@(42)] forKey:@"kinds"];
	[filter setObject:@[nostrId] forKey:@"#e"];
	[filter setObject:@(100) forKey:@"limit"];
	if (since > 1) {
		[filter setObject:@(since) forKey:@"since"];
	}
	[self sendReq:subId filter:filter];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification
		object:self];
}

// NIP-28 kind-41: channel metadata update (name, about, picture).
- (void)handleChannelMetadataUpdate:(NSDictionary *)event
{
	// Find the root kind-40 event id from the "e" tag.
	NSString *rootNostrId = [self rootChannelNostrIdForEvent:event];
	if (rootNostrId == nil) {
		return;
	}
	NSNumber *intIdNum = _nostrChannelIdToInt[rootNostrId];
	if (intIdNum == nil) {
		return;
	}
	NSInteger channelId = [intIdNum integerValue];
	TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
	if (channel == nil) {
		return;
	}
	id content = event[@"content"];
	if (![content isKindOfClass:[NSString class]] || [content length] == 0) {
		return;
	}
	NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![meta isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSString *name = meta[@"name"];
	if ([name isKindOfClass:[NSString class]] && [name length] > 0) {
		[channel setName:name];
	}
	// "about" maps to channel.topic for the UI.
	NSString *about = meta[@"about"];
	if ([about isKindOfClass:[NSString class]] && [about length] > 0) {
		[channel setTopic:about];
	}
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeChannelDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(channelId)}];
}

- (NSString *)rootChannelNostrIdForEvent:(NSDictionary *)event
{
	NSArray *tags = event[@"tags"];
	if (![tags isKindOfClass:[NSArray class]]) {
		return nil;
	}
	for (id tag in tags) {
		if ([tag isKindOfClass:[NSArray class]] && [tag count] >= 2 &&
			[[tag[0] description] isEqualToString:@"e"]) {
			return [tag[1] description];
		}
	}
	return nil;
}

- (void)handleChannelMessage:(NSDictionary *)event
{
	NSString *nostrId = [event[@"id"] description];
	if ([nostrId length] > 0 && [_seenEventIds containsObject:nostrId]) {
		return;
	}
	NSString *channelNostrId = [self rootChannelNostrIdForEvent:event];
	if (channelNostrId == nil) {
		return;
	}
	NSNumber *intIdNum = _nostrChannelIdToInt[channelNostrId];
	if (intIdNum == nil) {
		return;
	}
	NSInteger channelId = [intIdNum integerValue];
	TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
	if (channel == nil) {
		return;
	}
	// If this is a relay echo of a locally-added outgoing message, clear
	// the pending flag instead of adding a duplicate.
	if ([nostrId length] > 0) {
		TLMessage *local = _localMessageById[nostrId];
		if (local != nil) {
			local.pending = NO;
			[_localMessageById removeObjectForKey:nostrId];
			[[NSNotificationCenter defaultCenter]
				postNotificationName:TLLoungeMessagesDidChangeNotification
				object:self
				userInfo:@{@"channelId": @(channelId)}];
			NSInteger ts = [event[@"created_at"] integerValue];
			[self recordEventSeen:nostrId timestamp:ts forChannel:channelId];
			return;
		}
	}

	TLMessage *message = [self messageFromEvent:event channelId:channelId];
	if (message == nil) {
		return;
	}
	[channel addMessage:message];
	if (!message.isSelf && channel.identifier != self.clientState.selectedChannelId) {
		channel.unseen++;
	}
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeMessagesDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(channelId), @"message": message}];
	[message release];

	NSInteger ts = [event[@"created_at"] integerValue];
	[self recordEventSeen:nostrId timestamp:ts forChannel:channelId];
}

- (TLMessage *)messageFromEvent:(NSDictionary *)event channelId:(NSInteger)channelId
{
	NSString *nostrId = [event[@"id"] description];
	if ([nostrId length] == 0) {
		return nil;
	}
	NSInteger intId = [self messageIntIdForNostrId:nostrId];
	NSString *pubkey = [event[@"pubkey"] description];
	BOOL isSelf = [pubkey isEqualToString:_pubkeyHex];
	[self requestMetadataForPubkey:pubkey];
	NSDictionary *dict = @{
		@"id": @(intId),
		@"msgid": nostrId,
		@"type": @"message",
		@"text": [event[@"content"] description],
		@"time": event[@"created_at"],
		@"self": @(isSelf),
		@"from": @{
			@"nick": [self displayNameForPubkey:pubkey],
			@"username": pubkey
		}
	};
	TLMessage *message = [[TLMessage alloc] initWithDictionary:dict];
	message.channelId = channelId;
	return message;
}

- (void)handleEose:(NSArray *)args
{
	if ([args count] == 0) {
		return;
	}
	NSString *subId = [args[0] description];
	[_pendingEose removeObject:subId];

	// If the relay returned EOSE on the bootstrap subscriptions without
	// first sending an AUTH challenge, it does not require NIP-42 auth.
	// Complete the auth handshake now so the session reaches Ready state.
	// Guard with isAuthenticated to avoid calling the delegate twice.
	if (_authChallenge == nil && !_ready && ![self isAuthenticated]) {
		NSLog(@"[NOSTERM] handleEose: no AUTH challenge received, relay does not require auth");
		[self setAuthenticated:YES];
		[self.delegate protocolDidAuthenticate:self];
	}

	if (_searchSubId != nil && [subId isEqualToString:_searchSubId]) {
		[self finishSearch];
		return;
	}
	// Once the group directory has been read, open a second subscription for
	// the messages of every discovered NIP-29 group.
	if ([subId isEqualToString:@"nostr-groups"] && [_nostrChannelIdToInt count] > 0) {
		NSMutableArray *addresses = [NSMutableArray array];
		for (NSString *key in _nostrChannelIdToInt) {
			if ([key hasPrefix:@"ws"]) {
				[addresses addObject:key];
			}
		}
		if ([addresses count] > 0) {
			NSMutableArray *hValues = [NSMutableArray array];
			for (NSString *addr in addresses) {
				[hValues addObject:addr];
				[hValues addObject:[self bareGroupIdForAddress:addr]];
			}
			[self sendReq:@"nostr-group-msgs" filter:@{
				@"kinds": @[@(9)],
				@"#h": hValues,
				@"limit": @(200)
			}];
			// Not added to _pendingEose: group messages are supplementary
			// and should not gate the ready state.
		}
	}
	if (_ready) {
		return;
	}
	if ([_pendingEose count] == 0) {
		[self becomeReady];
	}
}

- (void)becomeReady
{
	NSLog(@"[NOSTERM] becomeReady: all subscriptions EOSE'd, becoming ready");
	_ready = YES;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification
		object:self];
	[self setReady:YES];
	[self.delegate protocolDidBecomeReady:self];
}

- (void)handleOk:(NSArray *)args
{
	if ([args count] < 2) {
		return;
	}
	NSString *eventId = [args count] >= 1 ? [args[0] description] : nil;
	BOOL accepted = [args[1] boolValue];
	NSLog(@"[NOSTERM] handleOk: eventId=%@ accepted=%d args=%@", eventId, accepted, args);

	// NIP-42: relay acknowledges our kind-22242 auth event.
	if ([eventId isEqualToString:_authEventId]) {
		if (accepted) {
			NSLog(@"[NOSTERM] handleOk: NIP-42 auth accepted");
			[self setAuthenticated:YES];
			[self.delegate protocolDidAuthenticate:self];
		} else {
			NSString *msg = [args count] >= 3 ? [args[2] description] : @"auth rejected";
			NSLog(@"[NOSTERM] handleOk: NIP-42 auth REJECTED: %@", msg);
			[self.delegate protocol:self didFailWithError:
				[NSError errorWithDomain:@"TLNostermAuthDomain" code:1
				userInfo:@{NSLocalizedDescriptionKey:
					[NSString stringWithFormat:@"Authentication failed: %@", msg]}]];
		}
		[_authEventId release];
		_authEventId = nil;
		return;
	}

	if (accepted) {
		if (eventId != nil) {
			TLMessage *local = _localMessageById[eventId];
			if (local != nil) {
				local.pending = NO;
				[_localMessageById removeObjectForKey:eventId];
				[[NSNotificationCenter defaultCenter]
					postNotificationName:TLLoungeMessagesDidChangeNotification
					object:self
					userInfo:@{@"channelId": @(local.channelId)}];
			}
		}
	} else {
		NSString *msg = [args count] >= 3 ? [args[2] description] : @"rejected";
		[[TLLogger sharedLogger] error:@"Nosterm event %@ rejected: %@", eventId, msg];
		if (eventId != nil) {
			TLMessage *local = _localMessageById[eventId];
			if (local != nil) {
				NSInteger channelId = local.channelId;
				NSString *text = local.text;
				[_localMessageById removeObjectForKey:eventId];
				TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
				if (channel != nil) {
					[channel removeMessageWithIdentifier:local.identifier];
					[[NSNotificationCenter defaultCenter]
						postNotificationName:TLLoungeMessagesDidChangeNotification
						object:self
						userInfo:@{@"channelId": @(channelId)}];
				}
				NSMutableDictionary *retry = [NSMutableDictionary dictionary];
				retry[@"text"] = text;
				retry[@"channelId"] = @(channelId);
				_pendingRetries[eventId] = retry;
				[self performSelector:@selector(retryPendingEvent:) withObject:eventId afterDelay:2.0];
			}
		}
	}
}

- (void)retryPendingEvent:(NSString *)eventId
{
	NSDictionary *retry = _pendingRetries[eventId];
	if (retry == nil) {
		return;
	}
	[_pendingRetries removeObjectForKey:eventId];
	NSString *text = retry[@"text"];
	NSInteger channelId = [retry[@"channelId"] integerValue];
	[self sendMessage:text toChannelId:channelId];
}

#pragma mark - NIP-29 managed groups

- (NSString *)firstTagValue:(NSString *)tagName inEvent:(NSDictionary *)event
{
	NSArray *tags = event[@"tags"];
	if (![tags isKindOfClass:[NSArray class]]) {
		return nil;
	}
	for (id tag in tags) {
		if ([tag isKindOfClass:[NSArray class]] && [tag count] >= 2 &&
			[[tag[0] description] isEqualToString:tagName]) {
			return [tag[1] description];
		}
	}
	return nil;
}

// NIP-29 group address is "<relay-url>:<group-id>"; bare ids are also mapped
// so message h tags that omit the relay prefix still resolve.
- (NSString *)groupAddressForId:(NSString *)groupId
{
	return [NSString stringWithFormat:@"%@:%@", [self relayURLString], groupId];
}

// nostermd tags kind 9/9021 with the bare group id on the wire, but only
// accepts posts/joins keyed by the full NIP-29 address (<relay>:<id>); publish
// with the full address.
- (NSString *)bareGroupIdForAddress:(NSString *)address
{
	NSRange r = [address rangeOfString:@":" options:NSBackwardsSearch];
	if (r.location != NSNotFound && r.location + 1 < [address length]) {
		return [address substringFromIndex:r.location + 1];
	}
	return address;
}

// nostermd rejects kind 9 until it has seen a kind 9021 join for the group,
// keyed by the full NIP-29 address. Send it whenever we learn of or open a
// group so posting is always permitted.
- (void)sendJoinForGroupAddress:(NSString *)address
{
	[self ensureKeypair];
	// NIP-29 requires the h tag to be the bare group id, not a qualified address.
	NSString *groupId = [self bareGroupIdForAddress:address];
	NSDictionary *join = [TLNostrCrypto signedEventWithPubkey:_pubkeyHex
		createdAt:(NSUInteger)time(NULL)
		kind:9021
		tags:@[@[@"h", groupId]]
		content:@""
		privateKey:_privateKey];
	if (join != nil) {
		[self.socketClient emitEvent:@"EVENT" withArguments:@[join]];
	}
}

// Deletes a single group we created, by the kind 39000 event id we published.
// Best-effort: relies on the relay honoring NIP-09 (kind 5) deletion and/or
// NIP-29 kind 9008 delete-group.
- (void)deleteGroupChannelId:(NSInteger)channelId
{
	NSString *evId = _groupEventIds[@(channelId)];
	NSString *address = _intToNostrChannelId[@(channelId)];
	if (evId == nil) {
		return;
	}
	[self ensureKeypair];
	[self publishGroupDeletionWithEventId:evId address:address];
}

// Asks the relay for every kind 39000 we published (authored by our key) and
// deletes each, used to clean up test artifacts left on a shared relay.
- (void)deleteAllOwnedGroups
{
	[self ensureKeypair];
	NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	[filter setObject:@[@(39000)] forKey:@"kinds"];
	[filter setObject:@[_pubkeyHex] forKey:@"authors"];
	[filter setObject:@(500) forKey:@"limit"];
	[self sendReq:@"nostr-cleanup" filter:filter];
}

- (void)publishGroupDeletionWithEventId:(NSString *)evId address:(NSString *)address
{
	if (evId == nil || [_cleanupDeletedIds containsObject:evId]) {
		return;
	}
	[_cleanupDeletedIds addObject:evId];
	[self ensureKeypair];
	NSDictionary *del = [TLNostrCrypto signedEventWithPubkey:_pubkeyHex
		createdAt:(NSUInteger)time(NULL)
		kind:5
		tags:@[@[@"e", evId]]
		content:@""
		privateKey:_privateKey];
	if (del != nil) {
		[self.socketClient emitEvent:@"EVENT" withArguments:@[del]];
	}
	if (address != nil) {
		NSDictionary *dg = [TLNostrCrypto signedEventWithPubkey:_pubkeyHex
			createdAt:(NSUInteger)time(NULL)
			kind:9008
			tags:@[@[@"h", address]]
			content:@""
			privateKey:_privateKey];
		if (dg != nil) {
			[self.socketClient emitEvent:@"EVENT" withArguments:@[dg]];
		}
	}
}

- (void)deleteOwnedGroupEvent:(NSDictionary *)event
{
	NSString *evId = [event[@"id"] description];
	if ([evId length] == 0) {
		return;
	}
	NSString *address = nil;
	NSString *rawH = [self firstTagValue:@"h" inEvent:event];
	if (rawH != nil) {
		address = rawH;
	} else {
		NSString *groupId = [self firstTagValue:@"d" inEvent:event];
		if (groupId != nil) {
			address = [self groupAddressForId:groupId];
		}
	}
	[self publishGroupDeletionWithEventId:evId address:address];
}

- (void)handleGroupMetadata:(NSDictionary *)event
{
	NSString *groupId = [self firstTagValue:@"d" inEvent:event];
	if ([groupId length] == 0) {
		return;
	}
	// Test artifacts (the live integration tests publish groups with these
	// prefixes) are not real user groups; never surface them as channels or
	// in the group list. They are deleted from the relay by the tests, but
	// this keeps a polluted relay from cluttering the sidebar meanwhile.
	if ([groupId hasPrefix:@"tltest-"] || [groupId hasPrefix:@"catchup-"] ||
	    [groupId hasPrefix:@"thelounge-test-"]) {
		return;
	}
	NSString *address = [self groupAddressForId:groupId];
	if (_nostrChannelIdToInt[address] != nil) {
		return;
	}
	NSInteger intId = [self channelIntIdForNostrId:address];

	NSString *name = groupId;
	id content = event[@"content"];
	if ([content isKindOfClass:[NSString class]] && [content length] > 0) {
		NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
		NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		if ([meta isKindOfClass:[NSDictionary class]] && meta[@"name"]) {
			name = [meta[@"name"] description];
		}
	}

	[self ensureRelayNetwork];
	TLChannel *channel = [[TLChannel alloc] initWithDictionary:@{
		@"id": @(intId),
		@"name": name,
		@"type": @"channel",
		@"state": @(TLChannelStateJoined)
	}];
	[_relayNetwork addChannel:channel];
	[channel release];

	// Index the group under both its canonical address and its bare id.
	_nostrChannelIdToInt[address] = @(intId);
	_nostrChannelIdToInt[groupId] = @(intId);
	_intToNostrChannelId[@(intId)] = address;
	[_nip29ChannelIds addObject:@(intId)];

	// Join the group (kind 9021) so the relay lets us post. Discovery alone
	// only shows the group; without the join, posting is rejected.
	[self sendJoinForGroupAddress:address];

	// Open a per-channel subscription bounded by this channel's cursor.
	NSString *subId = [NSString stringWithFormat:@"ch-%ld", (long)intId];
	NSInteger since = [self cursorTimestampForChannel:intId] + 1;
	NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	[filter setObject:@[@(9)] forKey:@"kinds"];
	[filter setObject:@[address, groupId] forKey:@"#h"];
	[filter setObject:@(100) forKey:@"limit"];
	if (since > 1) {
		[filter setObject:@(since) forKey:@"since"];
	}
	[self sendReq:subId filter:filter];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeNetworkListDidChangeNotification
		object:self];
}

- (void)handleGroupMessage:(NSDictionary *)event
{
	NSString *nostrId = [event[@"id"] description];
	if ([nostrId length] > 0 && [_seenEventIds containsObject:nostrId]) {
		return;
	}
	NSString *rawH = [self firstTagValue:@"h" inEvent:event];
	NSString *rawG = [self firstTagValue:@"g" inEvent:event];
	NSString *address = rawH;
	if (address == nil) {
		// Some relays emit a bare group id; qualify it with our relay.
		NSString *groupId = rawG;
		if (groupId != nil) {
			address = [self groupAddressForId:groupId];
		}
	}
	if (address == nil) {
		return;
	}
	NSNumber *intIdNum = _nostrChannelIdToInt[address];
	if (intIdNum == nil) {
		return;
	}
	NSInteger channelId = [intIdNum integerValue];
	TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
	if (channel == nil) {
		return;
	}
	// If this is a relay echo of a locally-added outgoing message, clear
	// the pending flag instead of adding a duplicate.
	if ([nostrId length] > 0) {
		TLMessage *local = _localMessageById[nostrId];
		if (local != nil) {
			local.pending = NO;
			[_localMessageById removeObjectForKey:nostrId];
			[[NSNotificationCenter defaultCenter]
				postNotificationName:TLLoungeMessagesDidChangeNotification
				object:self
				userInfo:@{@"channelId": @(channelId)}];
			NSInteger ts = [event[@"created_at"] integerValue];
			[self recordEventSeen:nostrId timestamp:ts forChannel:channelId];
			return;
		}
	}

	TLMessage *message = [self groupMessageFromEvent:event channelId:channelId];
	if (message == nil) {
		return;
	}
	[channel addMessage:message];
	if (!message.isSelf && channel.identifier != self.clientState.selectedChannelId) {
		channel.unseen++;
	}
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeMessagesDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(channelId), @"message": message}];
	[message release];

	NSInteger ts = [event[@"created_at"] integerValue];
	[self recordEventSeen:nostrId timestamp:ts forChannel:channelId];
}

- (TLMessage *)groupMessageFromEvent:(NSDictionary *)event channelId:(NSInteger)channelId
{
	NSString *nostrId = [event[@"id"] description];
	if ([nostrId length] == 0) {
		return nil;
	}
	NSInteger intId = [self messageIntIdForNostrId:nostrId];
	NSString *pubkey = [event[@"pubkey"] description];
	BOOL isSelf = [pubkey isEqualToString:_pubkeyHex];
	[self requestMetadataForPubkey:pubkey];
	NSDictionary *dict = @{
		@"id": @(intId),
		@"msgid": nostrId,
		@"type": @"message",
		@"text": [event[@"content"] description],
		@"time": event[@"created_at"],
		@"self": @(isSelf),
		@"from": @{
			@"nick": [self displayNameForPubkey:pubkey],
			@"username": pubkey
		}
	};
	TLMessage *message = [[TLMessage alloc] initWithDictionary:dict];
	message.channelId = channelId;
	return message;
}

- (void)handleAuth:(NSArray *)args
{
	if ([args count] == 0) {
		return;
	}
	[_authChallenge release];
	_authChallenge = [[args[0] description] retain];
	NSLog(@"[NOSTERM] handleAuth: relay challenged us, challenge=%@", _authChallenge);
	[self sendAuthEvent];
}

- (void)sendAuthEvent
{
	if (_authChallenge == nil || _privateKey == nil) {
		return;
	}
	NSString *relay = [self relayURLString];
	NSDictionary *event = [TLNostrCrypto signedEventWithPubkey:_pubkeyHex
		createdAt:(NSUInteger)time(NULL)
		kind:22242
		tags:@[@[@"relay", relay ? relay : @""], @[@"challenge", _authChallenge]]
		content:@""
		privateKey:_privateKey];
	if (event != nil) {
		[_authEventId release];
		_authEventId = [[event objectForKey:@"id"] retain];
		NSLog(@"[NOSTERM] sendAuthEvent: sending kind-22242 auth event, eventId=%@", _authEventId);
		[self.socketClient emitEvent:@"AUTH" withArguments:@[event]];
	}
}

- (void)handleNotice:(NSArray *)args
{
	NSString *msg = [args count] >= 1 ? [args[0] description] : @"";
	[[TLLogger sharedLogger] info:@"Nosterm notice: %@", msg];
	// Surface relay-originated warnings/errors to the UI.
	if ([msg length] > 0) {
		NSError *error = [NSError errorWithDomain:@"TLNostermRelayDomain" code:2
			userInfo:@{NSLocalizedDescriptionKey:
				[NSString stringWithFormat:@"Relay: %@", msg]}];
		[self.delegate protocol:self didFailWithError:error];
	}
}

- (void)handleClosed:(NSArray *)args
{
	NSString *subId = [args count] >= 1 ? [args[0] description] : @"";
	NSString *msg = [args count] >= 2 ? [args[1] description] : @"";
	[[TLLogger sharedLogger] info:@"Nosterm subscription closed: subId='%@' reason='%@'", subId, msg];
	// A closed subscription means no events will flow for that filter.
	if ([msg length] > 0) {
		NSError *error = [NSError errorWithDomain:@"TLNostermRelayDomain" code:3
			userInfo:@{NSLocalizedDescriptionKey:
				[NSString stringWithFormat:@"Subscription '%@' closed: %@", subId, msg]}];
		[self.delegate protocol:self didFailWithError:error];
	}
}

- (void)handleCount:(NSArray *)args
{
	// NIP-45 count results are informational for now.
}

#pragma mark - Outgoing commands

- (void)performAuthentication
{
	if (_authChallenge != nil) {
		[self sendAuthEvent];
	}
}

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	if ([text length] == 0) {
		return;
	}
	NSString *address = _intToNostrChannelId[@(channelId)];
	if (address == nil) {
		return;
	}
	[self ensureKeypair];
	NSDictionary *event;
	if ([_nip29ChannelIds containsObject:@(channelId)]) {
		NSString *groupId = [self bareGroupIdForAddress:address];
		NSMutableArray *tags = [NSMutableArray arrayWithObject:@[@"h", groupId]];
		TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
		if (channel != nil) {
			NSArray *msgs = channel.messages;
			NSUInteger count = [msgs count];
			NSUInteger start = count > 5 ? count - 5 : 0;
			for (NSUInteger i = start; i < count; i++) {
				TLMessage *m = (TLMessage *)msgs[i];
				NSString *prevId = m.msgid;
				if ([prevId length] > 0) {
					[tags addObject:@[@"previous", prevId]];
				}
			}
		}
		event = [TLNostrCrypto signedEventWithPubkey:_pubkeyHex
			createdAt:(NSUInteger)time(NULL)
			kind:9
			tags:tags
			content:text
			privateKey:_privateKey];
	} else {
		event = [TLNostrCrypto signedEventWithPubkey:_pubkeyHex
			createdAt:(NSUInteger)time(NULL)
			kind:42
			tags:@[@[@"e", address, @"", @"root"]]
			content:text
			privateKey:_privateKey];
	}
	if (event == nil) {
		return;
	}
	NSString *eventId = [event objectForKey:@"id"];
	NSInteger msgIntId = [self messageIntIdForNostrId:eventId];
	TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
	if (channel == nil) {
		return;
	}
	TLMessage *message = [[TLMessage alloc] initWithDictionary:@{
		@"id": @(msgIntId),
		@"msgid": eventId,
		@"type": @"message",
		@"text": text,
		@"time": event[@"created_at"],
		@"self": @(YES),
		@"from": @{
			@"nick": [self displayNameForPubkey:_pubkeyHex],
			@"username": _pubkeyHex
		}
	}];
	message.channelId = channelId;
	message.pending = YES;
	[channel addMessage:message];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeMessagesDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(channelId), @"message": message}];
	_localMessageById[eventId] = message;
	[message release];
	[self.socketClient emitEvent:@"EVENT" withArguments:@[event]];
}

- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId
{
	[self sendMessage:command toChannelId:channelId];
}

- (void)openChannelId:(NSInteger)channelId
{
	NSString *address = _intToNostrChannelId[@(channelId)];
	if (address == nil) {
		return;
	}
	NSString *subId = [NSString stringWithFormat:@"ch-%ld", (long)channelId];
	NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	if ([_nip29ChannelIds containsObject:@(channelId)]) {
		[filter setObject:@[@(9)] forKey:@"kinds"];
		NSString *groupId = [self bareGroupIdForAddress:address];
		[filter setObject:@[groupId, address] forKey:@"#h"];
	} else {
		[filter setObject:@[@(42)] forKey:@"kinds"];
		[filter setObject:@[address] forKey:@"#e"];
	}
	// Fetch the most recent page rather than only what is newer than the
	// local cursor: the cursor is already advanced by the global catch-up
	// subscriptions, so gating on it would return nothing on a re-open and
	// leave the transcript empty until the user scrolls (which issues a
	// history fetch without the cursor bound).
	[filter setObject:@((NSUInteger)time(NULL)) forKey:@"until"];
	[filter setObject:@(100) forKey:@"limit"];
	[self sendReq:subId filter:filter];
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
	// NOSTR has no names command; participants accrue from message senders
	// and from NIP-29 membership (kind 39002) events.
}

#pragma mark - NIP-29 group creation / join

- (void)joinChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId
{
	NSString *groupId = [self normalizeGroupId:name];
	if ([groupId length] == 0) {
		return;
	}
	NSString *address = [self groupAddressForId:groupId];
	[self ensureKeypair];
	[self ensureRelayNetwork];

	if (_nostrChannelIdToInt[address] == nil) {
		// channelIntIdForNostrId: populates the id maps, so the guard above
		// must be checked before computing the id or it would never fire.
		NSInteger intId = [self channelIntIdForNostrId:address];
		// Create the group locally so it appears immediately, then publish
		// the kind 39000 metadata (the relay echoes it back via our open
		// subscription, which the dedup guard ignores).
		TLChannel *channel = [[TLChannel alloc] initWithDictionary:@{
			@"id": @(intId),
			@"name": name,
			@"type": @"channel",
			@"state": @(TLChannelStateJoined)
		}];
		[_relayNetwork addChannel:channel];
		[channel release];
		_nostrChannelIdToInt[address] = @(intId);
		_nostrChannelIdToInt[groupId] = @(intId);
		_intToNostrChannelId[@(intId)] = address;
		[_nip29ChannelIds addObject:@(intId)];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:TLLoungeNetworkListDidChangeNotification
			object:self];

		NSDictionary *content = @{@"name": name};
		NSData *json = [NSJSONSerialization dataWithJSONObject:content options:0 error:NULL];
		NSString *contentStr = [[NSString alloc] initWithData:json
			encoding:NSUTF8StringEncoding];
		// nostermd only allows posting to "open" groups, so mark the group
		// open when creating it.
		NSDictionary *event = [TLNostrCrypto signedEventWithPubkey:_pubkeyHex
			createdAt:(NSUInteger)time(NULL)
			kind:39000
			tags:@[@[@"d", groupId], @[@"open"]]
			content:contentStr
			privateKey:_privateKey];
		// Remember the published event id so the group can be deleted on
		// teardown (test hygiene); the relay persists kind 39000 otherwise.
		NSString *evId = [event objectForKey:@"id"];
		if (evId != nil) {
			_groupEventIds[@(intId)] = evId;
		}
		[contentStr release];
		if (event != nil) {
			[self.socketClient emitEvent:@"EVENT" withArguments:@[event]];
		}
	}

	// Join the group (kind 9021) so the relay lets us post and tracks
	// membership; nostermd rejects kind 9 until a join request is seen. The
	// join is keyed by the full NIP-29 group address, matching kind 9.
	[self sendJoinForGroupAddress:address];

	// Always (re)subscribe to the group's messages, whether new or existing.
	// NIP-29 subscriptions filter on the bare group id; include the full
	// address too for relays that index by the qualified form. Bound by the
	// channel cursor so a rejoin replays messages missed while offline.
	NSInteger channelId = [self channelIntIdForNostrId:address];
	NSString *subId = [NSString stringWithFormat:@"ch-%ld", (long)channelId];
	NSInteger since = [self cursorTimestampForChannel:channelId] + 1;
	NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	[filter setObject:@[@(9)] forKey:@"kinds"];
	[filter setObject:@[address, groupId] forKey:@"#h"];
	[filter setObject:@(100) forKey:@"limit"];
	if (since > 1) {
		[filter setObject:@(since) forKey:@"since"];
	}
	[self sendReq:subId filter:filter];
}

- (void)handleGroupMembers:(NSDictionary *)event
{
	NSString *groupId = [self firstTagValue:@"d" inEvent:event];
	if ([groupId length] == 0) {
		return;
	}
	NSString *address = [self groupAddressForId:groupId];
	NSNumber *intIdNum = _nostrChannelIdToInt[address] ?: _nostrChannelIdToInt[groupId];

	NSArray *tags = event[@"tags"];
	if (![tags isKindOfClass:[NSArray class]]) {
		return;
	}
	// Always request metadata for every member pubkey, even if the group
	// channel has not been created yet (no kind-39000 was received).
	for (id tag in tags) {
		if ([tag isKindOfClass:[NSArray class]] && [tag count] >= 2 &&
			[[tag[0] description] isEqualToString:@"p"]) {
			NSString *pubkey = [tag[1] description];
			[self requestMetadataForPubkey:pubkey];
		}
	}
	// Only update the channel's user list if the group is known.
	if (intIdNum == nil) {
		return;
	}
	TLChannel *channel = [self.serverState channelWithIdentifier:[intIdNum integerValue]];
	if (channel == nil) {
		return;
	}

	for (id tag in tags) {
		if ([tag isKindOfClass:[NSArray class]] && [tag count] >= 2 &&
			[[tag[0] description] isEqualToString:@"p"]) {
			NSString *pubkey = [tag[1] description];
			[self requestMetadataForPubkey:pubkey];
			TLUser *user = [[TLUser alloc] initWithDictionary:@{
				@"nick": [self displayNameForPubkey:pubkey],
				@"username": pubkey
			}];
			[channel addUser:user];
			[user release];
		}
	}
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeUserListDidChangeNotification
		object:self
		userInfo:@{@"channelId": intIdNum}];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
{
	(void)lastId;
	[self loadMoreHistoryForChannelId:channelId lastId:lastId query:nil];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query
{
	(void)lastId;
	(void)query;
	NSString *address = _intToNostrChannelId[@(channelId)];
	if (address == nil) {
		return;
	}
	TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
	NSUInteger until = (NSUInteger)time(NULL);
	if (channel != nil && [channel.messages count] > 0) {
		TLMessage *oldest = [channel.messages firstObject];
		until = (NSUInteger)[oldest.timestamp timeIntervalSince1970] - 1;
	}
	NSString *subId = [NSString stringWithFormat:@"hist-%ld", (long)channelId];
	NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	if ([_nip29ChannelIds containsObject:@(channelId)]) {
		[filter setObject:@[@(9)] forKey:@"kinds"];
		NSString *groupId = [self bareGroupIdForAddress:address];
		[filter setObject:@[groupId, address] forKey:@"#h"];
	} else {
		[filter setObject:@[@(42)] forKey:@"kinds"];
		[filter setObject:@[address] forKey:@"#e"];
	}
	[filter setObject:@(until) forKey:@"until"];
	[filter setObject:@(100) forKey:@"limit"];
	[self sendReq:subId filter:filter];
}

- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset
{
	NSString *address = _intToNostrChannelId[@(channelId)];
	if (address == nil || [term length] == 0) {
		return;
	}
	[_searchResults removeAllObjects];
	_searchChannelId = channelId;
	[_searchSubId release];
	_searchSubId = [[NSString stringWithFormat:@"search-%ld", (long)channelId] retain];

	NSInteger limit = 100 + offset;
	NSMutableDictionary *filter = [NSMutableDictionary dictionary];
	if ([_nip29ChannelIds containsObject:@(channelId)]) {
		[filter setObject:@[@(9)] forKey:@"kinds"];
		[filter setObject:@[address] forKey:@"#h"];
	} else {
		[filter setObject:@[@(42)] forKey:@"kinds"];
		[filter setObject:@[address] forKey:@"#e"];
	}
	[filter setObject:term forKey:@"search"];
	[filter setObject:@(limit) forKey:@"limit"];
	[self sendReq:_searchSubId filter:filter];
}

- (void)handleSearchEvent:(NSDictionary *)event
{
	NSInteger kind = [event[@"kind"] integerValue];
	TLMessage *message;
	if (kind == 9) {
		message = [self groupMessageFromEvent:event channelId:_searchChannelId];
	} else {
		message = [self messageFromEvent:event channelId:_searchChannelId];
	}
	if (message == nil) {
		return;
	}
	NSInteger idx = [_searchResults count];
	message.identifier = TLLoungeNostrSearchIdBase - idx;
	[_searchResults addObject:message];
	[message release];
}

- (void)finishSearch
{
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeSearchResultsDidChangeNotification
		object:self
		userInfo:@{
			@"channelId": @(_searchChannelId),
			@"messages": _searchResults,
			@"count": @([_searchResults count])
		}];
	[_searchResults removeAllObjects];
	[_searchSubId release];
	_searchSubId = nil;
	_searchChannelId = 0;
}

- (void)clearHistoryForChannelId:(NSInteger)channelId
{
	TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
	if (channel == nil) {
		return;
	}
	[channel.messages removeAllObjects];
	channel.unseen = 0;
	channel.unseenHighlight = 0;
	channel.firstUnread = 0;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeMessagesDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(channelId)}];
}

- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId
{
	TLChannel *channel = [self.serverState channelWithIdentifier:channelId];
	if (channel == nil) {
		return;
	}
	channel.muted = muted;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLLoungeChannelDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(channelId)}];
}

@end
