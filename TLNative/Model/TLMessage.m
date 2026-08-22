/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLMessage.h"

static NSDictionary *TLMessageTypeMap(void)
{
	static NSDictionary *map;
	if (!map) {
		// Static storage outlives the creating autorelease pool; the
		// literal must be retained to survive it.
		map = [@{
			@"unhandled": @(TLMessageTypeUnhandled),
			@"action": @(TLMessageTypeAction),
			@"away": @(TLMessageTypeAway),
			@"back": @(TLMessageTypeBack),
			@"error": @(TLMessageTypeError),
			@"invite": @(TLMessageTypeInvite),
			@"join": @(TLMessageTypeJoin),
			@"kick": @(TLMessageTypeKick),
			@"login": @(TLMessageTypeLogin),
			@"logout": @(TLMessageTypeLogout),
			@"message": @(TLMessageTypeMessage),
			@"mode": @(TLMessageTypeMode),
			@"mode_channel": @(TLMessageTypeModeChannel),
			@"mode_user": @(TLMessageTypeModeUser),
			@"monospace_block": @(TLMessageTypeMonospaceBlock),
			@"nick": @(TLMessageTypeNick),
			@"notice": @(TLMessageTypeNotice),
			@"part": @(TLMessageTypePart),
			@"quit": @(TLMessageTypeQuit),
			@"ctcp": @(TLMessageTypeCTCP),
			@"ctcp_request": @(TLMessageTypeCTCPRequest),
			@"chghost": @(TLMessageTypeChghost),
			@"topic": @(TLMessageTypeTopic),
			@"topic_set_by": @(TLMessageTypeTopicSetBy),
			@"whois": @(TLMessageTypeWhois),
			@"raw": @(TLMessageTypeRaw),
			@"plugin": @(TLMessageTypePlugin),
			@"wallops": @(TLMessageTypeWallops),
		} retain];
	}
	return map;
}

NSString *TLMessageTypeToString(TLMessageType type)
{
	for (NSString *key in TLMessageTypeMap()) {
		if ([[TLMessageTypeMap() objectForKey:key] integerValue] == type) {
			return key;
		}
	}
	return @"unhandled";
}

TLMessageType TLMessageTypeFromString(NSString *s)
{
	NSNumber *n = [TLMessageTypeMap() objectForKey:s ? s : @"unhandled"];
	return n ? [n integerValue] : TLMessageTypeUnhandled;
}

@implementation TLMessage

- (instancetype)init
{
	self = [super init];
	if (self) {
		_identifier = 0;
		_msgid = @"";
		_timestamp = [[NSDate date] retain];
		_sender = [[TLUser alloc] init];
		_channelId = 0;
		_type = TLMessageTypeMessage;
		_rawText = @"";
		_text = @"";
		_hostmask = @"";
		_target = nil;
		_self = NO;
		_highlight = NO;
		_showInActive = NO;
		_newNick = @"";
		_newIdent = @"";
		_newHost = @"";
		_ctcpMessage = @"";
		_command = @"";
		_invitedYou = NO;
		_gecos = @"";
		_account = NO;
		_users = [[NSArray alloc] init];
		_statusmsgGroup = @"";
		_params = [[NSArray alloc] init];
		_metadata = [[NSMutableDictionary alloc] init];
	}
	return self;
}

static id TLObject(id value)
{
	return ([value isKindOfClass:[NSNull class]] || value == nil) ? nil : value;
}

static NSDate *TLParseISO8601(NSString *string)
{
	// The Lounge serializes message timestamps as ISO 8601 strings such as
	// "2025-06-01T12:00:00.000Z" via socket.io.
	NSArray *formats = @[
		@"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
		@"yyyy-MM-dd'T'HH:mm:ssXXXXX",
		@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
		@"yyyy-MM-dd'T'HH:mm:ssZZZZZ",
	];
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
	[formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
	for (NSString *format in formats) {
		[formatter setDateFormat:format];
		NSDate *date = [formatter dateFromString:string];
		if (date) {
			return date;
		}
	}
	return nil;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
	self = [self init];
	if (self) {
		if (dict[@"id"]) {
			_identifier = [dict[@"id"] integerValue];
		}
		if (TLObject(dict[@"msgid"])) {
			[self setMsgid:[dict[@"msgid"] description]];
		}
		if (TLObject(dict[@"text"])) {
			[self setRawText:[dict[@"text"] description]];
			_text = _rawText;
		}
		if (TLObject(dict[@"type"])) {
			_type = TLMessageTypeFromString([dict[@"type"] description]);
		}
		if (dict[@"time"]) {
			id t = TLObject(dict[@"time"]);
			// Direct ivar writes bypass the retained setter, so every
			// assignment must take ownership itself.
			NSDate *newTimestamp = nil;
			if ([t isKindOfClass:[NSDate class]]) {
				newTimestamp = [t retain];
			} else if ([t isKindOfClass:[NSString class]]) {
				newTimestamp = [TLParseISO8601(t) retain];
				if (!newTimestamp) {
					newTimestamp = [[NSDate dateWithString:t] retain];
				}
			} else if ([t isKindOfClass:[NSNumber class]]) {
				newTimestamp = [[NSDate dateWithTimeIntervalSince1970:[t doubleValue]] retain];
			}
			if (newTimestamp) {
				[_timestamp release];
				_timestamp = newTimestamp;
			}
		}
		if (TLObject(dict[@"from"])) {
			// init already installed a default sender; take it over before
			// replacing the ivar so the default does not leak.
			[_sender release];
			_sender = [[TLUser alloc] initWithDictionary:dict[@"from"]];
		}
		if (TLObject(dict[@"target"])) {
			_target = [[TLUser alloc] initWithDictionary:dict[@"target"]];
		}
		if (TLObject(dict[@"hostmask"])) {
			[self setHostmask:[dict[@"hostmask"] description]];
		}
		if (dict[@"self"]) {
			_self = [dict[@"self"] boolValue];
		}
		if (dict[@"highlight"]) {
			_highlight = [dict[@"highlight"] boolValue];
		}
		if (dict[@"showInActive"]) {
			_showInActive = [dict[@"showInActive"] boolValue];
		}
		if (TLObject(dict[@"new_nick"])) {
			[self setNewNick:[dict[@"new_nick"] description]];
		}
		if (TLObject(dict[@"new_ident"])) {
			[self setNewIdent:[dict[@"new_ident"] description]];
		}
		if (TLObject(dict[@"new_host"])) {
			[self setNewHost:[dict[@"new_host"] description]];
		}
		if (TLObject(dict[@"ctcpMessage"])) {
			[self setCtcpMessage:[dict[@"ctcpMessage"] description]];
		}
		if (TLObject(dict[@"command"])) {
			[self setCommand:[dict[@"command"] description]];
		}
		if (dict[@"invitedYou"]) {
			_invitedYou = [dict[@"invitedYou"] boolValue];
		}
		if (TLObject(dict[@"gecos"])) {
			[self setGecos:[dict[@"gecos"] description]];
		}
		if (dict[@"account"]) {
			_account = [dict[@"account"] boolValue];
		}
		if (dict[@"users"] && [dict[@"users"] isKindOfClass:[NSArray class]]) {
			NSMutableArray *u = [[NSMutableArray alloc] init];
			for (id n in dict[@"users"]) {
				[u addObject:[n description]];
			}
			_users = u;
		}
		if (TLObject(dict[@"statusmsgGroup"])) {
			[self setStatusmsgGroup:[dict[@"statusmsgGroup"] description]];
		}
		if (dict[@"params"] && [dict[@"params"] isKindOfClass:[NSArray class]]) {
			[self setParams:dict[@"params"]];
		}
		NSArray *known = @[
			@"id", @"msgid", @"text", @"type", @"time", @"from", @"target", @"hostmask",
			@"self", @"highlight", @"showInActive", @"new_nick", @"new_ident", @"new_host",
			@"ctcpMessage", @"command", @"invitedYou", @"gecos", @"account", @"users",
			@"statusmsgGroup", @"params"
		];
		NSMutableDictionary *rest = [dict mutableCopy];
		[rest removeObjectsForKeys:known];
		[_metadata release];
		_metadata = rest;
	}
	return self;
}

- (BOOL)isAction
{
	return _type == TLMessageTypeAction;
}

- (BOOL)isSystemMessage
{
	switch (_type) {
		case TLMessageTypeJoin:
		case TLMessageTypePart:
		case TLMessageTypeQuit:
		case TLMessageTypeNick:
		case TLMessageTypeTopic:
		case TLMessageTypeTopicSetBy:
		case TLMessageTypeMode:
		case TLMessageTypeModeChannel:
		case TLMessageTypeModeUser:
		case TLMessageTypeAway:
		case TLMessageTypeBack:
		case TLMessageTypeKick:
		case TLMessageTypeInvite:
		case TLMessageTypeChghost:
		case TLMessageTypeRaw:
		case TLMessageTypeWallops:
		case TLMessageTypeError:
			return YES;
		default:
			return NO;
	}
}

- (NSString *)displayText
{
	if (_type == TLMessageTypeAction && [_text length] > 0) {
		return [NSString stringWithFormat:@"%@ %@", _sender.nick, _text];
	}
	return _text;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<TLMessage %ld %@ %@>", (long)_identifier,
		TLMessageTypeToString(_type), _text];
}

@end