/* t_socketio.m - ObjectTesting coverage for the Socket.IO parser.  Headless.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../SocketIO/TLSocketIOPacket.h"
#import "../SocketIO/TLSocketIOParser.h"

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];

	/* --- namespace connect --- */
	{
		TLSocketIOPacket *packet = [TLSocketIOParser parsePacketFromString:@"0"];
		PASS(packet != nil, "connect packet parses");
		PASS(packet.type == TLSocketIOPacketTypeConnect, "connect packet type");
		PASS([packet.nsp isEqualToString:@"/"], "connect packet namespace is root");
	}

	{
		TLSocketIOPacket *packet = [TLSocketIOParser parsePacketFromString:@"0{\"sid\":\"s1\"}"];
		PASS(packet.type == TLSocketIOPacketTypeConnect, "connect with sid parses");
		PASS([packet.data[@"sid"] isEqualToString:@"s1"], "connect sid extracted");
	}

	/* --- event --- */
	{
		TLSocketIOPacket *packet = [TLSocketIOParser parsePacketFromString:@"2[\"auth:start\",123]"];
		PASS(packet.type == TLSocketIOPacketTypeEvent, "event packet type");
		PASS([[packet eventName] isEqualToString:@"auth:start"], "event name extracted");
		NSArray *args = [packet eventArguments];
		PASS([args count] == 1 && [args[0] integerValue] == 123, "event args extracted");
	}

	{
		TLSocketIOPacket *packet = [TLSocketIOParser
			parsePacketFromString:@"2[\"msg\",{\"chan\":5,\"msg\":{\"id\":1}}]"];
		PASS([[packet eventName] isEqualToString:@"msg"], "msg event name");
		PASS([packet eventArguments].count == 1, "msg has one argument");
		NSDictionary *arg = [packet eventArguments][0];
		PASS([arg[@"chan"] integerValue] == 5, "msg chan arg parsed");
	}

	/* --- event with ack id --- */
	{
		TLSocketIOPacket *packet = [TLSocketIOParser parsePacketFromString:@"21[\"ping\"]"];
		PASS(packet.packetId == 1, "ack id parsed");
		PASS([[packet eventName] isEqualToString:@"ping"], "event with ack id name");
	}

	/* --- named namespace --- */
	{
		TLSocketIOPacket *packet = [TLSocketIOParser
			parsePacketFromString:@"2/admin,[\"x\",1]"];
		PASS(packet != nil, "namespaced event parses");
		PASS([packet.nsp isEqualToString:@"/admin"], "namespaced nsp extracted");
		PASS([[packet eventName] isEqualToString:@"x"], "namespaced event name");
	}

	/* --- connect_error --- */
	{
		TLSocketIOPacket *packet = [TLSocketIOParser parsePacketFromString:@"4{\"message\":\"denied\"}"];
		PASS(packet.type == TLSocketIOPacketTypeConnectError, "connect_error type");
	}

	/* --- ack --- */
	{
		TLSocketIOPacket *packet = [TLSocketIOParser parsePacketFromString:@"31[]"];
		PASS(packet.type == TLSocketIOPacketTypeAck, "ack type");
		PASS(packet.packetId == 1, "ack id");
		PASS([packet.data isKindOfClass:[NSArray class]], "ack data is array");
	}

	/* --- serialization --- */
	{
		TLSocketIOPacket *event = [TLSocketIOPacket eventPacketWithName:@"auth:perform"
			arguments:@[@{@"user": @"u", @"password": @"p"}]];
		NSString *serialized = [TLSocketIOParser serializePacket:event];
		PASS([serialized hasPrefix:@"2[\"auth:perform\""], "event serialization prefix");
		PASS([serialized containsString:@"\"user\":\"u\""], "event serialization payload");

		NSString *connect = [TLSocketIOParser serializePacket:[TLSocketIOPacket connectPacket]];
		PASS([connect isEqualToString:@"0"], "connect serialization");

		NSString *disconnect = [TLSocketIOParser serializePacket:[TLSocketIOPacket disconnectPacket]];
		PASS([disconnect isEqualToString:@"1"], "disconnect serialization");
	}

	/* --- round trip --- */
	{
		TLSocketIOPacket *event = [TLSocketIOPacket eventPacketWithName:@"input"
			arguments:@[@{@"target": @3, @"text": @"/join #x"}]];
		NSString *serialized = [TLSocketIOParser serializePacket:event];
		TLSocketIOPacket *reparsed = [TLSocketIOParser parsePacketFromString:serialized];
		PASS(reparsed != nil, "round trip parses");
		PASS([[reparsed eventName] isEqualToString:@"input"], "round trip event name");
		NSDictionary *arg = [reparsed eventArguments][0];
		PASS([arg[@"target"] integerValue] == 3, "round trip target");
		PASS([arg[@"text"] isEqualToString:@"/join #x"], "round trip text");
	}

	/* --- invalid --- */
	{
		PASS([TLSocketIOParser parsePacketFromString:@""] == nil, "empty rejected");
		PASS([TLSocketIOParser parsePacketFromString:@"9x"] == nil, "bad type rejected");
		PASS([TLSocketIOParser parsePacketFromString:@"2notjson"] == nil, "bad json rejected");
	}

	[arp release];
	return 0;
}