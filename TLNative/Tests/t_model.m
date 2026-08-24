/* t_model.m - ObjectTesting coverage for the application model.  Headless.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../Model/TLUser.h"
#import "../Model/TLMessage.h"
#import "../Model/TLChannel.h"
#import "../Model/TLNetwork.h"
#import "../Model/TLServerState.h"
#import "../Model/TLClientState.h"

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];

	/* --- TLUser parsing and mode state --- */
	{
		NSDictionary *op = @{@"nick": @"alice", @"mode": @"o", @"away": @"gone",
			@"modes": @[@"o"], @"lastMessage": @42};
		TLUser *user = [[TLUser alloc] initWithDictionary:op];
		PASS([user.nick isEqualToString:@"alice"], "user nick parsed");
		PASS([user.fullPrefix isEqualToString:@"@"], "operator prefix is @");
		PASS([user isOperator], "operator state detected");
		PASS(![user isVoice], "operator is not voiced");
		PASS(user.lastMessage == 42, "lastMessage parsed");
		[user release];

		TLUser *voice = [[TLUser alloc] initWithDictionary:@{@"nick": @"bob", @"mode": @"v"}];
		PASS([voice.fullPrefix isEqualToString:@"+"], "voice prefix is +");
		PASS([voice isVoice], "voice state detected");
		[voice release];

		TLUser *plain = [[TLUser alloc] initWithDictionary:@{@"nick": @"carol", @"mode": @""}];
		PASS([[plain fullPrefix] isEqualToString:@""], "no prefix for plain user");
		PASS(![plain isOperator] && ![plain isVoice], "plain user has no modes");
		[plain release];

		/* Unknown fields must not break parsing. */
		TLUser *future = [[TLUser alloc] initWithDictionary:@{
			@"nick": @"dave", @"someFutureField": @[@1, @2]
		}];
		PASS([future.nick isEqualToString:@"dave"], "user with unknown field parses");
		PASS(future.metadata[@"someFutureField"] != nil, "unknown field retained in metadata");
		[future release];
	}

	/* --- TLMessage parsing --- */
	{
		NSDictionary *d = @{
			@"id": @7,
			@"msgid": @"abc",
			@"type": @"message",
			@"text": @"hello world",
			@"time": @"2025-01-01T10:00:00.000Z",
			@"from": @{@"mode": @"", @"nick": @"alice"},
			@"self": @NO,
			@"highlight": @NO
		};
		TLMessage *msg = [[TLMessage alloc] initWithDictionary:d];
		PASS(msg.identifier == 7, "message id parsed");
		PASS(msg.type == TLMessageTypeMessage, "message type parsed");
		PASS([msg.rawText isEqualToString:@"hello world"], "message text parsed");
		PASS([msg.sender.nick isEqualToString:@"alice"], "sender parsed");
		PASS(msg.timestamp != nil, "timestamp parsed");
		NSDate *mid2025 = [NSDate dateWithString:@"2025-06-01 00:00:00 +0000"];
		PASS([msg.timestamp earlierDate:mid2025] == msg.timestamp, "timestamp is before mid 2025");
		[msg release];

		/* NICK message carries new_nick. */
		TLMessage *nick = [[TLMessage alloc] initWithDictionary:@{
			@"id": @8, @"type": @"nick", @"new_nick": @"newnick",
			@"from": @{@"mode": @"", @"nick": @"oldnick"}
		}];
		PASS(nick.type == TLMessageTypeNick, "nick type parsed");
		PASS([nick.newNick isEqualToString:@"newnick"], "new_nick parsed");
		PASS([nick isSystemMessage], "nick is a system message");
		PASS(![nick isAction], "nick is not an action");
		[nick release];

		/* ACTION messages render as "nick text". */
		TLMessage *action = [[TLMessage alloc] initWithDictionary:@{
			@"id": @9, @"type": @"action", @"text": @"waves",
			@"from": @{@"mode": @"", @"nick": @"bob"}
		}];
		PASS([action isAction], "action type parsed");
		PASS([action.displayText isEqualToString:@"bob waves"], "action display text");
		[action release];

		/* Type string round trip. */
		PASS([TLMessageTypeToString(TLMessageTypeNotice) isEqualToString:@"notice"], "type to string");
		PASS(TLMessageTypeFromString(@"quit") == TLMessageTypeQuit, "type from string");
		PASS(TLMessageTypeFromString(@"bogus") == TLMessageTypeUnhandled, "unknown type maps to unhandled");
	}

	/* --- TLChannel parsing and message/upsert behavior --- */
	{
		NSDictionary *d = @{
			@"id": @3,
			@"name": @"#general",
			@"type": @"channel",
			@"topic": @"welcome",
			@"unread": @2,
			@"highlight": @1,
			@"firstUnread": @10,
			@"muted": @NO,
			@"state": @1,
			@"messages": @[@{
				@"id": @10, @"type": @"message", @"text": @"one",
				@"from": @{@"mode": @"", @"nick": @"alice"}
			}],
			@"totalMessages": @50
		};
		TLChannel *chan = [[TLChannel alloc] initWithDictionary:d];
		PASS(chan.identifier == 3, "channel id parsed");
		PASS([chan.name isEqualToString:@"#general"], "channel name parsed");
		PASS(chan.type == TLChannelTypeChannel, "channel type parsed");
		PASS([chan isChannel] && ![chan isQuery] && ![chan isLobby], "channel kind flags");
		PASS(chan.unread == 2 && chan.highlight == 1, "unread and highlight parsed");
		PASS(chan.state == TLChannelStateJoined, "channel state parsed");
		PASS(chan.totalMessages == 50, "totalMessages parsed");
		PASS([chan.messages count] == 1, "one message parsed");
		PASS([[chan messageWithIdentifier:10].text isEqualToString:@"one"], "message lookup by id");
		[chan release];

		/* addMessage upserts by id. */
		TLChannel *c = [[TLChannel alloc] init];
		TLMessage *m1 = [[TLMessage alloc] initWithDictionary:@{@"id": @1, @"text": @"a",
			@"from": @{@"nick": @"x", @"mode": @""}}];
		TLMessage *m2 = [[TLMessage alloc] initWithDictionary:@{@"id": @2, @"text": @"b",
			@"from": @{@"nick": @"x", @"mode": @""}}];
		[c addMessage:m1];
		[c addMessage:m2];
		PASS([c.messages count] == 2, "two messages added");
		TLMessage *m1b = [[TLMessage alloc] initWithDictionary:@{@"id": @1, @"text": @"a2",
			@"from": @{@"nick": @"x", @"mode": @""}}];
		[c addMessage:m1b];
		PASS([c.messages count] == 2, "upsert keeps count at 2");
		PASS([[c messageWithIdentifier:1].text isEqualToString:@"a2"], "upsert replaced message");
		[c removeMessageWithIdentifier:2];
		PASS([c.messages count] == 1, "message removed");
		[m1 release]; [m2 release]; [m1b release]; [c release];

		/* prependMessages deduplicates. */
		TLChannel *p = [[TLChannel alloc] init];
		TLMessage *p1 = [[TLMessage alloc] initWithDictionary:@{@"id": @1, @"text": @"old",
			@"from": @{@"nick": @"x", @"mode": @""}}];
		TLMessage *p2 = [[TLMessage alloc] initWithDictionary:@{@"id": @2, @"text": @"older",
			@"from": @{@"nick": @"x", @"mode": @""}}];
		TLMessage *p3 = [[TLMessage alloc] initWithDictionary:@{@"id": @3, @"text": @"live",
			@"from": @{@"nick": @"x", @"mode": @""}}];
		[p addMessage:p3];
		[p prependMessages:@[p2, p1]];
		PASS([p.messages count] == 3, "prepend added two");
		PASS([p.messages[0].text isEqualToString:@"older"], "prepend kept order (older first)");
		TLMessage *dup = [[TLMessage alloc] initWithDictionary:@{@"id": @2, @"text": @"older",
			@"from": @{@"nick": @"x", @"mode": @""}}];
		[p prependMessages:@[dup]];
		PASS([p.messages count] == 3, "prepend deduplicates");
		[dup release];
		[p1 release]; [p2 release]; [p3 release]; [p release];

		/* Users map keyed by lowercase nick. */
		TLChannel *uc = [[TLChannel alloc] init];
		TLUser *u = [[TLUser alloc] initWithDictionary:@{@"nick": @"Nick", @"mode": @"o"}];
		[uc addUser:u];
		PASS([[uc userWithNick:@"NICK"] isEqual:u], "user lookup case-insensitive");
		[uc removeUserWithNick:@"nick"];
		PASS([uc userWithNick:@"nick"] == nil, "user removed");
		[u release]; [uc release];

		/* Unique prefix lookup for nick completion. */
		TLChannel *pc = [[TLChannel alloc] init];
		TLUser *pj = [[TLUser alloc] initWithDictionary:@{@"nick": @"jmaloney", @"mode": @""}];
		TLUser *pk = [[TLUser alloc] initWithDictionary:@{@"nick": @"Korne127", @"mode": @""}];
		[pc addUser:pj];
		[pc addUser:pk];
		PASS([[pc uniqueUserWithNickPrefix:@"J"] isEqual:pj], "prefix match is case-insensitive");
		PASS([pc uniqueUserWithNickPrefix:@"jma"] == pj, "longer prefix still matches");
		PASS([pc uniqueUserWithNickPrefix:@"zz"] == nil, "unknown prefix yields nothing");
		[pc addUser:[[TLUser alloc] initWithDictionary:@{@"nick": @"joe", @"mode": @""}]];
		PASS([pc uniqueUserWithNickPrefix:@"j"] == nil, "ambiguous prefix yields nothing");
		[pc release];

		/* Channel type round trip. */
		PASS([TLChannelTypeToString(TLChannelTypeQuery) isEqualToString:@"query"], "chan type to string");
		PASS(TLChannelTypeFromString(@"lobby") == TLChannelTypeLobby, "chan type from string");
	}

	/* --- TLNetwork and TLServerState --- */
	{
		NSDictionary *nd = @{
			@"uuid": @"net1",
			@"name": @"Libera",
			@"nick": @"mynick",
			@"serverOptions": @{@"CHANTYPES": @[@"#", @"&"], @"NETWORK": @"Libera.Chat"},
			@"status": @{@"connected": @YES, @"secure": @YES},
			@"channels": @[
				@{@"id": @1, @"name": @"Server", @"type": @"lobby"},
				@{@"id": @2, @"name": @"#general", @"type": @"channel"}
			]
		};
		TLNetwork *net = [[TLNetwork alloc] initWithDictionary:nd];
		PASS([net.uuid isEqualToString:@"net1"], "network uuid parsed");
		PASS(net.connected && net.secure, "network status parsed");
		PASS([net.channels count] == 2, "two channels parsed");
		PASS([net channelWithIdentifier:2] != nil, "channel lookup by id");
		PASS([net channelWithName:@"#GENERAL"] != nil, "channel lookup by name case-insensitive");
		PASS([[net lobby].name isEqualToString:@"Server"], "lobby found");
		[net release];

		TLServerState *state = [[TLServerState alloc] init];
		[state addNetwork:[[TLNetwork alloc] initWithDictionary:nd]];
		PASS([state.networks count] == 1, "network added");
		PASS([state networkWithUuid:@"net1"] != nil, "network lookup by uuid");
		PASS([state channelWithIdentifier:2] != nil, "channel lookup across networks");
		PASS([state networkContainingChannel:2].uuid == nil ||
			[[state networkContainingChannel:2].uuid isEqualToString:@"net1"],
			"network containing channel");
		[state clear];
		PASS([state.networks count] == 0, "state cleared");
		[state release];

		/* TLClientState reset. */
		TLClientState *cs = [[TLClientState alloc] init];
		cs.selectedChannelId = 5;
		cs.authenticated = YES;
		[cs resetForNewSession];
		PASS(cs.selectedChannelId == 0 && !cs.authenticated, "client state reset");
		[cs release];
	}

	[arp release];
	return 0;
}