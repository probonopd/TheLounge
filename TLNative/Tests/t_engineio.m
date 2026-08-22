/* t_engineio.m - ObjectTesting coverage for the Engine.IO parser.  Headless.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../EngineIO/TLEngineIOPacket.h"
#import "../EngineIO/TLEngineIOParser.h"

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];

	/* --- open packet --- */
	{
		NSString *raw = @"0{\"sid\":\"abc123\",\"upgrades\":[\"websocket\"],"
			"\"pingInterval\":25000,\"pingTimeout\":60000,\"maxPayload\":1000000}";
		TLEngineIOPacket *packet = [TLEngineIOParser parsePacketFromString:raw];
		PASS(packet != nil, "open packet parses");
		PASS(packet.type == TLEngineIOPacketTypeOpen, "open packet type is open");
		PASS([packet.data hasPrefix:@"{\"sid\""], "open packet data is JSON");

		NSData *jsonData = [packet.data dataUsingEncoding:NSUTF8StringEncoding];
		NSDictionary *info = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
		PASS([info[@"sid"] isEqualToString:@"abc123"], "sid extracted");
		PASS([info[@"pingInterval"] integerValue] == 25000, "pingInterval extracted");
		PASS([info[@"pingTimeout"] integerValue] == 60000, "pingTimeout extracted");
	}

	/* --- ping/pong --- */
	{
		TLEngineIOPacket *ping = [TLEngineIOParser parsePacketFromString:@"2"];
		PASS(ping.type == TLEngineIOPacketTypePing, "bare ping parsed");
		PASS([[ping data] length] == 0, "bare ping has no data");

		TLEngineIOPacket *probe = [TLEngineIOParser parsePacketFromString:@"2probe"];
		PASS(probe.type == TLEngineIOPacketTypePing, "probe ping parsed");
		PASS([probe.data isEqualToString:@"probe"], "probe ping data parsed");

		TLEngineIOPacket *pong = [TLEngineIOPacket packetWithType:TLEngineIOPacketTypePong data:@""];
		PASS([[TLEngineIOParser serializePacket:pong] isEqualToString:@"3"], "pong serialized");
	}

	/* --- message packets --- */
	{
		TLEngineIOPacket *msg = [TLEngineIOParser parsePacketFromString:@"42[\"auth:start\",123]"];
		PASS(msg.type == TLEngineIOPacketTypeMessage, "message packet parsed");
		PASS([msg.data isEqualToString:@"2[\"auth:start\",123]"], "message data is socket.io payload");
	}

	/* --- close, upgrade, noop --- */
	{
		PASS([TLEngineIOParser parsePacketFromString:@"1"].type == TLEngineIOPacketTypeClose,
			"close parsed");
		PASS([TLEngineIOParser parsePacketFromString:@"5"].type == TLEngineIOPacketTypeUpgrade,
			"upgrade parsed");
		PASS([TLEngineIOParser parsePacketFromString:@"6"].type == TLEngineIOPacketTypeNoop,
			"noop parsed");
	}

	/* --- invalid --- */
	{
		PASS([TLEngineIOParser parsePacketFromString:@""] == nil, "empty string rejected");
		PASS([TLEngineIOParser parsePacketFromString:@"x"] == nil, "non-digit rejected");
		PASS([TLEngineIOParser parsePacketFromString:@"9"] == nil, "out of range rejected");
	}

	/* --- serialization round trip --- */
	{
		TLEngineIOPacket *packet = [TLEngineIOPacket packetWithType:TLEngineIOPacketTypeMessage
			data:@"42[\"init\",{}]"];
		NSString *serialized = [TLEngineIOParser serializePacket:packet];
		PASS([serialized isEqualToString:@"442[\"init\",{}]"], "message serialization");
		TLEngineIOPacket *reparsed = [TLEngineIOParser parsePacketFromString:serialized];
		PASS(reparsed.type == TLEngineIOPacketTypeMessage, "round trip type");
		PASS([reparsed.data isEqualToString:@"42[\"init\",{}]"], "round trip data");
	}

	[arp release];
	return 0;
}