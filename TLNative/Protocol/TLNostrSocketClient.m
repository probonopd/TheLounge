/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLNostrSocketClient.h"
#import "TLSocketIOClient.h"
#import "TLWebSocketTransport.h"
#import "TLLogger.h"

@interface TLNostrSocketClient () <TLWebSocketTransportDelegate>
{
	TLWebSocketTransport *_transport;
	NSString *_relayURLString;
}
@end

const uint64_t TLLoungeNostrIdBase = 0x1000000000000000ULL;   // 2^60
const uint64_t TLLoungeNostrIdStride = 0x0800000000000000ULL; // 2^59
const uint64_t TLLoungeNostrIdMask = 0x07FFFFFFFFFFFFFFULL;   // STRIDE - 1

NSString *const TLLoungeNostermDefaultRelayURL = @"wss://chat.nosterm.com/relay";

@implementation TLNostrSocketClient

- (instancetype)init
{
	self = [super init];
	if (self) {
		_transport = [[TLWebSocketTransport alloc] init];
		_transport.delegate = self;
	}
	return self;
}

- (void)dealloc
{
	[_transport setDelegate:nil];
	[_transport release];
	[_relayURLString release];
	[super dealloc];
}

// GNUstep copies arguments passed through performSelectorOnMainThread: and
// performSelector:withObject:afterDelay: (to hand them safely across threads).
// A socket client is a stable per-connection handle, so copying returns the
// same instance retained rather than a true clone.
- (id)copyWithZone:(NSZone *)zone
{
	return [self retain];
}

- (BOOL)isConnected
{
	return _transport.state == TLWebSocketStateOpen;
}

- (NSString *)relayURLString
{
	return _relayURLString;
}

- (void)connectToServerURL:(NSURL *)serverURL
{
	[_relayURLString release];
	_relayURLString = [[serverURL absoluteString] retain];
	[_transport connectToURL:serverURL];
}

- (void)close
{
	[_transport close];
}

- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	NSMutableArray *frame = [NSMutableArray arrayWithObject:eventName ? eventName : @""];
	if (arguments) {
		[frame addObjectsFromArray:arguments];
	}
	NSError *error = nil;
	NSData *json = [NSJSONSerialization dataWithJSONObject:frame options:0 error:&error];
	if (!json) {
		return;
	}
	[_transport sendData:json isText:YES];
}

#pragma mark - TLWebSocketTransportDelegate

- (void)webSocketDidOpen:(TLWebSocketTransport *)transport
{
	if ([_delegate respondsToSelector:@selector(socketIOClientDidConnect:)]) {
		[_delegate socketIOClientDidConnect:(TLSocketIOClient *)self];
	}
}

- (void)webSocket:(TLWebSocketTransport *)transport didReceiveData:(NSData *)data isText:(BOOL)isText
{
	NSError *error = nil;
	id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (![obj isKindOfClass:[NSArray class]] || [obj count] == 0) {
		return;
	}
	NSString *verb = [obj[0] description];
	NSArray *arguments = ([obj count] > 1)
		? [obj subarrayWithRange:NSMakeRange(1, [obj count] - 1)]
		: @[];
	if ([_delegate respondsToSelector:@selector(socketIOClient:didReceiveEvent:arguments:)]) {
		[_delegate socketIOClient:(TLSocketIOClient *)self didReceiveEvent:verb arguments:arguments];
	}
}

- (void)webSocket:(TLWebSocketTransport *)transport didFailWithError:(NSError *)error
{
	if ([_delegate respondsToSelector:@selector(socketIOClient:didFailWithError:)]) {
		[_delegate socketIOClient:(TLSocketIOClient *)self didFailWithError:error];
	}
}

- (void)webSocketDidClose:(TLWebSocketTransport *)transport
{
	if ([_delegate respondsToSelector:@selector(socketIOClientDidDisconnect:)]) {
		[_delegate socketIOClientDidDisconnect:(TLSocketIOClient *)self];
	}
}

@end
