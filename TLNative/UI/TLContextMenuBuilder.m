/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLContextMenuBuilder.h"

// The concrete target behind every menu item; NSMenuItem retains its target,
// so the sink lives as long as the menu it belongs to.  Items carry their
// action in representedObject, keeping the menu construction data-driven and
// testable without a running session.
@interface _TLContextMenuSink : NSObject
{
	id<TLContextMenuActionDelegate> _actionDelegate;
}
- (instancetype)initWithDelegate:(id<TLContextMenuActionDelegate>)delegate;
@end

@implementation _TLContextMenuSink

- (instancetype)initWithDelegate:(id<TLContextMenuActionDelegate>)delegate
{
	self = [super init];
	if (self) {
		_actionDelegate = delegate;
	}
	return self;
}

- (void)menuItemActivated:(NSMenuItem *)sender
{
	NSDictionary *action = [sender representedObject];
	NSString *kind = action[@"action"];
	NSInteger channelId = [action[@"channelId"] integerValue];

	if ([kind isEqualToString:@"run"]) {
		[_actionDelegate contextMenuRunCommand:action[@"command"]
			onChannelId:channelId];
	} else if ([kind isEqualToString:@"switch"]) {
		[_actionDelegate contextMenuSwitchToChannelId:channelId];
	} else if ([kind isEqualToString:@"mute"]) {
		[_actionDelegate contextMenuSetMuted:[action[@"muted"] boolValue]
			forChannelId:channelId];
	} else if ([kind isEqualToString:@"clearHistory"]) {
		[_actionDelegate contextMenuClearHistoryForChannelId:channelId];
	} else if ([kind isEqualToString:@"close"]) {
		[_actionDelegate contextMenuCloseChannelId:channelId
			isLobby:[action[@"isLobby"] boolValue]];
	} else if ([kind isEqualToString:@"joinPrompt"]) {
		[_actionDelegate contextMenuJoinPromptForLobbyId:channelId];
	} else if ([kind isEqualToString:@"topicPrompt"]) {
		[_actionDelegate contextMenuEditTopicForChannelId:channelId];
	}
}

@end

@implementation TLContextMenuBuilder

+ (BOOL)mode:(NSString *)p1 canActOnMode:(NSString *)p2
	inSymbols:(NSArray<NSString *> *)symbols
{
	if ([p1 length] == 0 || [p2 length] == 0) {
		return NO;
	}
	NSUInteger i1 = [symbols indexOfObject:p1];
	NSUInteger i2 = [symbols indexOfObject:p2];
	// An unknown rank acts on nothing (mirrors the web client's indexOf -1).
	if (i1 == NSNotFound || i2 == NSNotFound) {
		return NO;
	}
	BOOL ownerOrOp = ([p1 isEqualToString:@"~"] || [p1 isEqualToString:@"@"]);
	return ownerOrOp ? (i1 <= i2) : (i1 < i2);
}

#pragma mark - Item helpers

// Human-readable channel type used by the Mute label, matching the web
// client's humanFriendlyChanTypeMap.
+ (NSString *)humanTypeNameForChannel:(TLChannel *)channel
{
	switch (channel.type) {
	case TLChannelTypeLobby:
		return @"network";
	case TLChannelTypeQuery:
		return @"conversation";
	default:
		return @"channel";
	}
}

+ (NSMenuItem *)actionItemWithTitle:(NSString *)title
	action:(NSDictionary *)action
	sink:(_TLContextMenuSink *)sink
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
		action:@selector(menuItemActivated:) keyEquivalent:@""];
	[item setTarget:sink];
	[item setRepresentedObject:action];
	return [item autorelease];
}

+ (void)addCommandItemToMenu:(NSMenu *)menu
	title:(NSString *)title
	command:(NSString *)command
	channelId:(NSInteger)channelId
	sink:(_TLContextMenuSink *)sink
{
	NSMenuItem *item = [self actionItemWithTitle:title
		action:@{@"action": @"run", @"command": command,
			@"channelId": @(channelId)}
		sink:sink];
	[menu addItem:item];
}

#pragma mark - Channel menu

+ (NSMenu *)channelMenuForChannel:(TLChannel *)channel
	network:(TLNetwork *)network
	myNick:(NSString *)myNick
	delegate:(id<TLContextMenuActionDelegate>)delegate
{
	_TLContextMenuSink *sink = [[_TLContextMenuSink alloc]
		initWithDelegate:delegate];
	[sink autorelease];

	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Context Menu"];

	NSInteger channelId = channel.identifier;

	// Header item switches to the channel, like the web client's link.
	NSMenuItem *header = [self actionItemWithTitle:
		[channel.name length] > 0 ? channel.name : @"(unnamed)"
		action:@{@"action": @"switch", @"channelId": @(channelId)}
		sink:sink];
	[menu addItem:header];
	[menu addItem:[NSMenuItem separatorItem]];

	if (channel.type == TLChannelTypeLobby) {
		NSMenuItem *join = [self actionItemWithTitle:@"Join a channel…"
			action:@{@"action": @"joinPrompt", @"channelId": @(channelId)}
			sink:sink];
		[menu addItem:join];
		[self addCommandItemToMenu:menu title:@"List all channels"
			command:@"/list" channelId:channelId sink:sink];
		[self addCommandItemToMenu:menu title:@"List ignored users"
			command:@"/ignorelist" channelId:channelId sink:sink];
		[self addCommandItemToMenu:menu
			title:network.connected ? @"Disconnect" : @"Connect"
			command:network.connected ? @"/disconnect" : @"/connect"
			channelId:channelId sink:sink];
	}

	if (channel.type == TLChannelTypeChannel) {
		NSMenuItem *topic = [self actionItemWithTitle:@"Edit topic"
			action:@{@"action": @"topicPrompt", @"channelId": @(channelId)}
			sink:sink];
		[menu addItem:topic];
		[self addCommandItemToMenu:menu title:@"List banned users"
			command:@"/banlist" channelId:channelId sink:sink];
	}

	if (channel.type == TLChannelTypeQuery) {
		NSString *nick = channel.name;
		[self addCommandItemToMenu:menu title:@"User information"
			command:[@"/whois " stringByAppendingString:nick]
			channelId:channelId sink:sink];
		[self addCommandItemToMenu:menu title:@"Ignore user"
			command:[@"/ignore " stringByAppendingString:nick]
			channelId:channelId sink:sink];
	}

	if (channel.type == TLChannelTypeChannel ||
		channel.type == TLChannelTypeQuery) {
		NSMenuItem *clear = [self actionItemWithTitle:@"Clear history"
			action:@{@"action": @"clearHistory", @"channelId": @(channelId)}
			sink:sink];
		[menu addItem:clear];
	}

	if (channel.type != TLChannelTypeSpecial) {
		NSString *type = [self humanTypeNameForChannel:channel];
		NSString *label = channel.muted
			? [NSString stringWithFormat:@"Unmute %@", type]
			: [NSString stringWithFormat:@"Mute %@", type];
		NSMenuItem *mute = [self actionItemWithTitle:label
			action:@{@"action": @"mute", @"channelId": @(channelId),
				@"muted": @(!channel.muted)}
			sink:sink];
		[menu addItem:mute];
	}

	NSString *closeLabel;
	switch (channel.type) {
	case TLChannelTypeLobby:
		closeLabel = @"Remove";
		break;
	case TLChannelTypeChannel:
		closeLabel = @"Leave";
		break;
	default:
		closeLabel = @"Close";
		break;
	}
	NSMenuItem *close = [self actionItemWithTitle:closeLabel
		action:@{@"action": @"close", @"channelId": @(channelId),
			@"isLobby": @(channel.type == TLChannelTypeLobby)}
		sink:sink];
	[menu addItem:close];

	[menu autorelease];
	return menu;
}

#pragma mark - User menu

+ (NSString *)modeNameForMode:(NSString *)mode
{
	NSDictionary *names = @{@"q": @"owner", @"a": @"admin",
		@"o": @"operator", @"h": @"half-op", @"v": @"voice"};
	NSString *name = names[mode];
	return name ?: [NSString stringWithFormat:@"mode %@", mode];
}

+ (NSMenu *)userMenuForUser:(TLUser *)user
	channel:(TLChannel *)channel
	network:(TLNetwork *)network
	myNick:(NSString *)myNick
	delegate:(id<TLContextMenuActionDelegate>)delegate
{
	_TLContextMenuSink *sink = [[_TLContextMenuSink alloc]
		initWithDelegate:delegate];
	[sink autorelease];

	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Context Menu"];

	NSString *nick = user.nick;
	NSInteger channelId = channel.identifier;

	NSMenuItem *header = [self actionItemWithTitle:nick
		action:@{@"action": @"run",
			@"command": [@"/whois " stringByAppendingString:nick],
			@"channelId": @(channelId)}
		sink:sink];
	[menu addItem:header];
	[menu addItem:[NSMenuItem separatorItem]];

	[self addCommandItemToMenu:menu title:@"User information"
		command:[@"/whois " stringByAppendingString:nick]
		channelId:channelId sink:sink];
	[self addCommandItemToMenu:menu title:@"Ignore user"
		command:[@"/ignore " stringByAppendingString:nick]
		channelId:channelId sink:sink];
	[self addCommandItemToMenu:menu title:@"Direct messages"
		command:[@"/query " stringByAppendingString:nick]
		channelId:channelId sink:sink];

	// Mode actions require our own presence with a mode in this channel,
	// exactly like the web client bails without currentChannelUser.modes.
	TLUser *myUser = [channel userWithNick:myNick]
		?: [channel userWithNick:network.nick];
	if (!myUser || [myUser.modes count] == 0) {
		[menu autorelease];
		return menu;
	}

	NSDictionary *prefixOptions = network.serverOptions[@"PREFIX"];
	NSArray *prefixList = prefixOptions[@"prefix"];
	NSArray *symbols = prefixOptions[@"symbols"];
	NSString *myTop = [myUser.modes objectAtIndex:0];

	for (NSDictionary *entry in prefixList) {
		NSString *symbol = entry[@"symbol"];
		NSString *mode = entry[@"mode"];
		if (![self mode:myTop canActOnMode:symbol inSymbols:symbols]) {
			continue;
		}
		BOOL has = [user.modes containsObject:symbol];
		NSString *sign = has ? @"-" : @"+";
		NSString *verb = has ? @"Revoke" : @"Give";
		NSString *label = [NSString stringWithFormat:@"%@ %@ (%@%@)",
			verb, [self modeNameForMode:mode], sign, mode];
		NSString *command = [NSString stringWithFormat:@"/mode %@%@ %@",
			sign, mode, nick];
		[self addCommandItemToMenu:menu title:label
			command:command channelId:channelId sink:sink];
	}

	// Kick eligibility mirrors the web client: we must be at least half-op
	// (or operator when the server has no half-ops), and the target must be
	// unranked or below us.
	NSString *requirement = [symbols containsObject:@"%"] ? @"%" : @"@";
	BOOL atLeastHalfOp = ![self mode:requirement canActOnMode:myTop
		inSymbols:symbols];
	BOOL targetBelowUs;
	if ([user.modes count] == 0) {
		targetBelowUs = YES;
	} else {
		targetBelowUs = [self mode:myTop
			canActOnMode:[user.modes objectAtIndex:0] inSymbols:symbols];
	}
	if (atLeastHalfOp && targetBelowUs) {
		[self addCommandItemToMenu:menu title:@"Kick"
			command:[@"/kick " stringByAppendingString:nick]
			channelId:channelId sink:sink];
	}

	[menu autorelease];
	return menu;
}

@end
