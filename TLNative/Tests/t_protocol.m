/* t_protocol.m - ObjectTesting coverage for the 4.5 protocol adapter.  Headless.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../Protocol/TLoungeProtocol_4_5.h"
#import "../Protocol/TLSocketEventDispatcher.h"
#import "../Model/TLServerState.h"
#import "../Model/TLClientState.h"
#import "../SocketIO/TLSocketIOClient.h"
#import "../Support/TLLogger.h"

@interface RecordingClient : TLSocketIOClient
@property (nonatomic, retain) NSMutableArray *emitted;
@end

@implementation RecordingClient
- (instancetype)init
{
	self = [super init];
	if (self) {
		_emitted = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	[_emitted addObject:@{@"event": eventName, @"args": arguments ? arguments : @[]}];
}
@end

static NSDictionary *LoadFixture(NSString *name)
{
	NSString *path = [@"Fixtures" stringByAppendingPathComponent:name];
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data) {
		return nil;
	}
	return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}

static NSDictionary *LastEvent(RecordingClient *client)
{
	return [client.emitted lastObject];
}

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];

	/* --- init builds a coherent server state --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];

		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		PASS(protocol.isReady, "protocol ready after init");
		PASS([state.networks count] == 1, "one network after init");
		TLNetwork *network = state.networks[0];
		PASS([network.uuid isEqualToString:@"2b6d9b7c-8f14-4c99-a"], "network uuid kept");
		PASS([network.name isEqualToString:@"Libera.Chat"], "network name kept");
		PASS(network.connected && network.secure, "network status kept");
		PASS([network.channels count] == 2, "two channels after init");
		TLChannel *chan = [network channelWithIdentifier:2];
		PASS(chan != nil, "channel 2 exists");
		PASS([chan.topic isEqualToString:@"General chat"], "channel topic kept");
		PASS(chan.unread == 1, "channel unread kept");
		PASS([chan.messages count] == 1, "channel has one message");
		PASS([[chan messageWithIdentifier:5].sender.nick isEqualToString:@"other"], "message sender kept");
		PASS([state.metadata[@"token"] isEqualToString:@"a1b2c3d4e5f6"], "session token retained");
		PASS([state.currentUserNick isEqualToString:@"testnick"], "current user nick from network");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- password authentication payload --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];

		[protocol setUsername:@"testuser" password:@"secret"];
		[protocol.dispatcher dispatchEvent:@"auth:start" arguments:@[@(123)]];

		NSDictionary *auth = LastEvent(client);
		PASS([auth[@"event"] isEqualToString:@"auth:perform"], "auth:perform emitted on auth:start");
		NSDictionary *payload = auth[@"args"][0];
		PASS([payload[@"user"] isEqualToString:@"testuser"], "auth payload user");
		PASS([payload[@"password"] isEqualToString:@"secret"], "auth payload password");
		PASS(payload[@"token"] == nil, "no token in password auth");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- token (session restore) authentication payload --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];

		/* Seed a message so lastMessage is computed. */
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];
		[client.emitted removeAllObjects];

		[protocol setUsername:@"testuser" token:@"mytoken"];
		[protocol.dispatcher dispatchEvent:@"auth:start" arguments:@[@(123)]];

		NSDictionary *auth = LastEvent(client);
		NSDictionary *payload = auth[@"args"][0];
		PASS([payload[@"user"] isEqualToString:@"testuser"], "token auth user");
		PASS([payload[@"token"] isEqualToString:@"mytoken"], "token auth token");
		PASS([payload[@"lastMessage"] integerValue] == 5, "lastMessage is highest known id");
		PASS([payload[@"hasConfig"] boolValue] == NO, "hasConfig false on fresh session");
		PASS([payload[@"openChannel"] isKindOfClass:[NSNull class]], "openChannel null when unset");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- msg event updates channel and posts notification --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		__block BOOL notified = NO;
		id observer = [[NSNotificationCenter defaultCenter]
			addObserverForName:TLLoungeMessagesDidChangeNotification
			object:protocol
			queue:nil
			usingBlock:^(NSNotification *note) {
				NSNumber *chanId = note.userInfo[@"channelId"];
				if ([chanId integerValue] == 2) {
					notified = YES;
				}
			}];

		[protocol.dispatcher dispatchEvent:@"msg" arguments:@[LoadFixture(@"msg.json")]];

		TLChannel *chan = [state channelWithIdentifier:2];
		PASS([[chan messageWithIdentifier:6].text isEqualToString:@"hello from alice"],
			"incoming message added");
		PASS(chan.unread == 2, "unread updated from msg event");
		PASS(chan.highlight == 1, "highlight updated from msg event");
		// The unseen count is client-side: it grows for every non-self
		// message regardless of the active channel or window visibility.
		PASS(chan.unseen == 1, "unseen incremented from msg event");
		PASS(chan.unseenHighlight == 1, "unseen highlight incremented");
		PASS(notified, "messages notification posted");

		[[NSNotificationCenter defaultCenter] removeObserver:observer];
		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- msg event maintains unread locally when fields are absent --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		// A regular message with no unread/highlight fields must bump the count.
		NSDictionary *plain = @{
			@"chan": @2,
			@"msg": @{
				@"from": @{@"nick": @"bob"},
				@"id": @7,
				@"text": @"plain",
				@"type": @"message",
				@"self": @NO,
				@"highlight": @NO,
				@"time": @"2025-06-01T12:06:00.000Z",
			},
		};
		[protocol.dispatcher dispatchEvent:@"msg" arguments:@[plain]];
		TLChannel *chan = [state channelWithIdentifier:2];
		PASS(chan.unread == 2, "unread incremented locally without payload field");
		PASS(chan.highlight == 0, "highlight unchanged for non-highlight msg");
		PASS(chan.unseen == 1, "unseen incremented locally without payload field");
		PASS(chan.unseenHighlight == 0, "unseen highlight unchanged for non-highlight msg");

		// A highlight message with no highlight field must bump the highlight.
		NSDictionary *hi = @{
			@"chan": @2,
			@"msg": @{
				@"from": @{@"nick": @"bob"},
				@"id": @8,
				@"text": @"ping",
				@"type": @"message",
				@"self": @NO,
				@"highlight": @YES,
				@"time": @"2025-06-01T12:07:00.000Z",
			},
		};
		[protocol.dispatcher dispatchEvent:@"msg" arguments:@[hi]];
		PASS(chan.unread == 3, "unread incremented for second msg");
		PASS(chan.highlight == 1, "highlight incremented for highlight msg");
		PASS(chan.unseen == 2, "unseen incremented for second msg");
		PASS(chan.unseenHighlight == 1, "unseen highlight incremented for highlight msg");

		// A self message must not count as unread.
		NSDictionary *selfMsg = @{
			@"chan": @2,
			@"msg": @{
				@"from": @{@"nick": @"me"},
				@"id": @9,
				@"text": @"mine",
				@"type": @"message",
				@"self": @YES,
				@"highlight": @NO,
				@"time": @"2025-06-01T12:08:00.000Z",
			},
		};
		[protocol.dispatcher dispatchEvent:@"msg" arguments:@[selfMsg]];
		PASS(chan.unread == 3, "self message does not increment unread");
		PASS(chan.unseen == 2, "self message does not increment unseen");

		// Technical/server status lines (connection errors, pings, ...) must
		// not bump the unseen count even though the bouncer counts them.
		NSDictionary *status = @{
			@"chan": @2,
			@"msg": @{
				@"id": @10,
				@"text": @"Server closed connection",
				@"type": @"message",
				@"self": @NO,
				@"time": @"2025-06-01T12:09:00.000Z",
			},
		};
		[protocol.dispatcher dispatchEvent:@"msg" arguments:@[status]];
		PASS(chan.unseen == 2, "technical status message does not increment unseen");
		PASS(chan.unseenHighlight == 1, "technical status message does not increment unseen highlight");

		// A non-conversational event with a sender (e.g. a quit) is also
		// excluded from the unseen count.
		NSDictionary *quit = @{
			@"chan": @2,
			@"msg": @{
				@"from": @{@"nick": @"bob"},
				@"id": @11,
				@"text": @"Remote host closed the connection",
				@"type": @"quit",
				@"self": @NO,
				@"time": @"2025-06-01T12:09:30.000Z",
			},
		};
		[protocol.dispatcher dispatchEvent:@"msg" arguments:@[quit]];
		PASS(chan.unseen == 2, "non-conversational event does not increment unseen");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- more event prepends history in order --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		[protocol.dispatcher dispatchEvent:@"more" arguments:@[LoadFixture(@"more.json")]];

		TLChannel *chan = [state channelWithIdentifier:2];
		PASS([chan.messages count] == 3, "history prepended to existing message");
		PASS(chan.totalMessages == 20, "totalMessages updated");
		PASS([[chan messageWithIdentifier:3].text isEqualToString:@"older message"],
			"oldest history message present");
		/* ordering: 3, 4 (history), then 5 (init message) */
		TLMessage *first = chan.messages[0];
		PASS(first.identifier == 3, "history ordering oldest first");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- names populates user list --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		[protocol.dispatcher dispatchEvent:@"names" arguments:@[LoadFixture(@"names.json")]];

		TLChannel *chan = [state channelWithIdentifier:2];
		PASS([chan.users count] == 3, "three users populated");
		TLUser *alice = [chan userWithNick:@"alice"];
		PASS(alice != nil && [alice isOperator], "alice is operator");
		TLUser *bob = [chan userWithNick:@"bob"];
		PASS(bob != nil && [bob isVoice], "bob is voiced");
		PASS(chan.numUsers == 3, "numUsers updated");
		NSArray *sorted = [chan sortedUsers];
		PASS([[sorted[0] nick] isEqualToString:@"alice"], "operators sorted first");
		PASS([[sorted[1] nick] isEqualToString:@"bob"], "voices sorted second");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- users event triggers a names request --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		[protocol.dispatcher dispatchEvent:@"users" arguments:@[@{@"chan": @2}]];

		NSDictionary *names = LastEvent(client);
		PASS([names[@"event"] isEqualToString:@"names"], "names requested after users event");
		PASS([names[@"args"][0][@"target"] integerValue] == 2, "names request targets channel");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- topic / nick / channel:state / part events --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		[protocol.dispatcher dispatchEvent:@"topic" arguments:@[@{@"chan": @2, @"topic": @"New topic"}]];
		PASS([[state channelWithIdentifier:2].topic isEqualToString:@"New topic"], "topic updated");

		[protocol.dispatcher dispatchEvent:@"nick" arguments:@[@{@"network": @"2b6d9b7c-8f14-4c99-a", @"nick": @"newnick"}]];
		PASS([[state.networks[0] nick] isEqualToString:@"newnick"], "network nick updated");
		PASS([state.currentUserNick isEqualToString:@"newnick"], "current user nick updated");

		[protocol.dispatcher dispatchEvent:@"channel:state" arguments:@[@{@"chan": @2, @"state": @0}]];
		PASS([state channelWithIdentifier:2].state == TLChannelStateParted, "channel state updated");

		[protocol.dispatcher dispatchEvent:@"join" arguments:@[@{
			@"network": @"2b6d9b7c-8f14-4c99-a",
			@"chan": @{@"id": @7, @"name": @"#new", @"type": @"channel", @"state": @1, @"messages": @[]},
			@"shouldOpen": @NO,
			@"index": @2
		}]];
		PASS([[state.networks[0] channelWithIdentifier:7].name isEqualToString:@"#new"],
			"join creates channel");

		[protocol.dispatcher dispatchEvent:@"part" arguments:@[@{@"chan": @7}]];
		PASS([state channelWithIdentifier:7] == nil, "part removes channel");

		[protocol.dispatcher dispatchEvent:@"network:status" arguments:@[@{
			@"network": @"2b6d9b7c-8f14-4c99-a", @"connected": @NO, @"secure": @YES
		}]];
		PASS(!state.networks[0].connected, "network:status updates connected");

		[protocol.dispatcher dispatchEvent:@"quit" arguments:@[@{@"network": @"2b6d9b7c-8f14-4c99-a"}]];
		PASS([state.networks count] == 0, "quit removes network");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- unknown events are ignored safely --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		NSDictionary *unknownEvent = @{@"x": @1};
		NSDictionary *orphanMsg = @{@"chan": @99, @"msg": @{@"id": @1}};
		PASS_RUNS([protocol.dispatcher dispatchEvent:@"some:future:event" arguments:@[unknownEvent]],
			"unknown event does not throw");
		PASS_RUNS([protocol.dispatcher dispatchEvent:@"msg" arguments:@[orphanMsg]],
			"msg for unknown channel does not throw");
		PASS([state.networks count] == 1, "state unchanged by unknown events");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- reconciliation: reconnect init merges instead of clobbering --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];

		/* A new live message arrives. */
		[protocol.dispatcher dispatchEvent:@"msg" arguments:@[LoadFixture(@"msg.json")]];

		/* Simulate a reconnect: the server sends only messages newer than lastMessage. */
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[@{
			@"active": @2,
			@"networks": @[@{
				@"uuid": @"2b6d9b7c-8f14-4c99-a",
				@"name": @"Libera.Chat",
				@"nick": @"testnick",
				@"serverOptions": @{},
				@"status": @{@"connected": @YES, @"secure": @YES},
				@"channels": @[
					@{@"id": @1, @"name": @"Server", @"type": @"lobby", @"state": @1, @"messages": @[]},
					@{@"id": @2, @"name": @"#general", @"topic": @"General chat",
						@"type": @"channel", @"state": @1,
						@"messages": @[@{
							@"from": @{@"mode": @"", @"nick": @"dave"},
							@"id": @7, @"text": @"after reconnect", @"type": @"message",
							@"self": @NO, @"time": @"2025-06-01T12:10:00.000Z"
						}]}
				]
			}]
		}]];

		PASS([state.networks count] == 1, "reconnect keeps one network");
		TLChannel *chan = [state channelWithIdentifier:2];
		PASS([chan messageWithIdentifier:7] != nil, "reconnect message present");
		PASS([[chan messageWithIdentifier:6].text isEqualToString:@"hello from alice"],
			"pre-existing live message preserved after reconnect");
		PASS([[chan messageWithIdentifier:5].text isEqualToString:@"welcome back"],
			"older init message preserved after reconnect");
		PASS(state.activeChannelId == 2, "reconnect active channel restored");

		[protocol release]; [state release]; [clientState release]; [client release];
	}

	/* --- reconnect re-authentication after a disconnect --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];

		/* First login with a password; init hands out a session token. */
		[protocol setUsername:@"testuser" password:@"secret"];
		[protocol.dispatcher dispatchEvent:@"auth:start" arguments:@[@(123)]];
		[protocol.dispatcher dispatchEvent:@"init" arguments:@[LoadFixture(@"init.json")]];
		[client.emitted removeAllObjects];

		/* Connection drops; resetSession runs and the automatic
		 * reconnect reaches auth:start again. */
		[protocol resetSession];
		[protocol.dispatcher dispatchEvent:@"auth:start" arguments:@[@(456)]];

		NSDictionary *reAuth = LastEvent(client);
		PASS([reAuth[@"event"] isEqualToString:@"auth:perform"], "re-auth emitted after reset");
		NSDictionary *rePayload = reAuth[@"args"][0];
		PASS([rePayload[@"user"] isEqualToString:@"testuser"], "reconnect auth user kept");
		PASS([rePayload[@"token"] isEqualToString:@"a1b2c3d4e5f6"],
			"reconnect uses session token from init");
		PASS(rePayload[@"password"] == nil, "password not replayed once token exists");
		PASS([rePayload[@"lastMessage"] integerValue] == 5, "reconnect auth carries lastMessage");

		[protocol release]; [state release]; [clientState release]; [client release];

		/* Without a token in init the original password must still be
		 * available for the reconnect. */
		RecordingClient *client2 = [[RecordingClient alloc] init];
		TLServerState *state2 = [[TLServerState alloc] init];
		TLClientState *clientState2 = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol2 = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client2 serverState:state2 clientState:clientState2];
		[protocol2 setUsername:@"testuser" password:@"secret"];
		[protocol2 resetSession];
		[protocol2.dispatcher dispatchEvent:@"auth:start" arguments:@[@(1)]];

		NSDictionary *pwPayload = LastEvent(client2)[@"args"][0];
		PASS([pwPayload[@"password"] isEqualToString:@"secret"], "password survives resetSession");

		[protocol2 release]; [state2 release]; [clientState2 release]; [client2 release];
	}

	/* --- server-side search request carries the query --- */
	{
		RecordingClient *client = [[RecordingClient alloc] init];
		TLServerState *state = [[TLServerState alloc] init];
		TLClientState *clientState = [[TLClientState alloc] init];
		TLoungeProtocol_4_5 *protocol = [[TLoungeProtocol_4_5 alloc]
			initWithSocketClient:client serverState:state clientState:clientState];

		// Backlog search goes through the dedicated `search` event, keyed by
		// network uuid and (lowercased) channel name rather than channel id.
		TLNetwork *net = [[TLNetwork alloc] initWithDictionary:
			@{@"uuid": @"net-uuid", @"name": @"net"}];
		TLChannel *chan = [[TLChannel alloc] initWithDictionary:
			@{@"id": @3, @"name": @"#Test", @"type": @"channel"}];
		[net addChannel:chan];
		[state addNetwork:net];

		[protocol searchMessagesForChannelId:3 term:@"hello" offset:0];
		NSDictionary *search = LastEvent(client);
		PASS([search[@"event"] isEqualToString:@"search"],
			"backlog search emits a search event");
		NSDictionary *searchArgs = search[@"args"][0];
		PASS([searchArgs[@"searchTerm"] isEqualToString:@"hello"],
			"search forwards the term");
		PASS([searchArgs[@"networkUuid"] isEqualToString:@"net-uuid"],
			"search targets the network by uuid");
		PASS([searchArgs[@"channelName"] isEqualToString:@"#test"],
			"search targets the channel by lowercased name");
		PASS([searchArgs[@"offset"] integerValue] == 0,
			"search starts at the first page");

		// The no-query history overload must not send a query key at all.
		[client.emitted removeAllObjects];
		[protocol loadMoreHistoryForChannelId:3 lastId:42];
		NSDictionary *plain = LastEvent(client);
		PASS([plain[@"args"][0][@"query"] isEqual:[NSNull null]] == NO &&
			plain[@"args"][0][@"query"] == nil,
			"plain history request omits the query");

		[protocol release]; [state release]; [clientState release]; [client release];
		[net release]; [chan release];
	}

	[arp release];
	return 0;
}