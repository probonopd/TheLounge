/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLEngineIOClient.h"
#import "TLWebSocketTransport.h"
#import "TLEngineIOPacket.h"
#import "TLEngineIOParser.h"
#import "TLLogger.h"

@interface TLEngineIOClient () <TLWebSocketTransportDelegate>
{
	TLWebSocketTransport *_transport;
	BOOL _isOpen;
	NSString *_sessionId;
	NSTimeInterval _pingInterval;
	NSTimeInterval _pingTimeout;
	NSTimeInterval _lastActivity;
	NSThread *_watchdogThread;
	BOOL _watchdogRunning;
	BOOL _closing;
	NSLock *_stateLock;
}
@end

@implementation TLEngineIOClient

- (instancetype)init
{
	self = [super init];
	if (self) {
		_transport = [[TLWebSocketTransport alloc] init];
		_transport.delegate = self;
		_isOpen = NO;
		_sessionId = @"";
		_pingInterval = 25000;
		_pingTimeout = 20000;
		_lastActivity = 0;
		_watchdogRunning = NO;
		_closing = NO;
		_stateLock = [[NSLock alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[self close];
	[_transport release];
	[_sessionId release];
	[_stateLock release];
	[super dealloc];
}

- (void)connectToURL:(NSURL *)url
{
	[_stateLock lock];
	_closing = NO;
	_isOpen = NO;
	[_stateLock unlock];
	[_transport connectToURL:url];
}

- (void)sendMessageData:(NSString *)data
{
	TLEngineIOPacket *packet = [TLEngineIOPacket packetWithType:TLEngineIOPacketTypeMessage data:data];
	NSData *payload = [[packet serialized] dataUsingEncoding:NSUTF8StringEncoding];
	[_transport sendData:payload isText:YES];
}

- (void)sendPacket:(TLEngineIOPacket *)packet
{
	NSData *payload = [[packet serialized] dataUsingEncoding:NSUTF8StringEncoding];
	[_transport sendData:payload isText:YES];
}

- (void)close
{
	[_stateLock lock];
	if (_closing) {
		[_stateLock unlock];
		return;
	}
	_closing = YES;
	_isOpen = NO;
	[_stateLock unlock];

	_watchdogRunning = NO;
	[_transport close];
}

- (void)startWatchdog
{
	_watchdogRunning = YES;
	_lastActivity = [NSDate timeIntervalSinceReferenceDate];
	_watchdogThread = [[NSThread alloc] initWithTarget:self
		selector:@selector(watchdogLoop)
		object:nil];
	[_watchdogThread start];
}

- (void)watchdogLoop
{
	while (_watchdogRunning) {
		[NSThread sleepForTimeInterval:1.0];
		if (!_watchdogRunning) {
			break;
		}
		NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
		NSTimeInterval deadline = _pingInterval + _pingTimeout + 5.0;
		if (now - _lastActivity > deadline) {
			if (!_closing) {
				TLLogger *logger = [TLLogger sharedLogger];
				[logger debug:@"Engine.IO heartbeat timeout"];
			}
			[self notifyHeartbeatTimeout];
			break;
		}
	}
}

- (void)notifyHeartbeatTimeout
{
	[_stateLock lock];
	if (_closing) {
		[_stateLock unlock];
		return;
	}
	_closing = YES;
	_isOpen = NO;
	[_stateLock unlock];

	_watchdogRunning = NO;
	NSError *error = [NSError errorWithDomain:@"TLEngineIOErrorDomain"
		code:1
		userInfo:@{NSLocalizedDescriptionKey: @"Heartbeat timeout"}];
	if ([_delegate respondsToSelector:@selector(engineIOClient:didFailWithError:)]) {
		[_delegate engineIOClient:self didFailWithError:error];
	}
	[_transport close];
}

#pragma mark - TLWebSocketTransportDelegate

- (void)webSocketDidOpen:(TLWebSocketTransport *)transport
{
	// Engine.IO open packet arrives next.
}

- (void)webSocket:(TLWebSocketTransport *)transport didReceiveData:(NSData *)data isText:(BOOL)isText
{
	if (!isText) {
		return;
	}
	NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!string) {
		return;
	}
	TLEngineIOPacket *packet = [TLEngineIOParser parsePacketFromString:string];
	[string release];
	if (!packet) {
		return;
	}

	_lastActivity = [NSDate timeIntervalSinceReferenceDate];

	switch (packet.type) {
		case TLEngineIOPacketTypeOpen:
			[self handleOpenPacket:packet];
			break;
		case TLEngineIOPacketTypePing:
			[self sendPacket:[TLEngineIOPacket packetWithType:TLEngineIOPacketTypePong data:packet.data]];
			break;
		case TLEngineIOPacketTypePong:
			break;
		case TLEngineIOPacketTypeMessage:
			if ([_delegate respondsToSelector:@selector(engineIOClient:didReceiveMessageData:)]) {
				[_delegate engineIOClient:self didReceiveMessageData:packet.data];
			}
			break;
		case TLEngineIOPacketTypeClose:
			[self notifyServerClose];
			break;
		case TLEngineIOPacketTypeUpgrade:
		case TLEngineIOPacketTypeNoop:
		default:
			break;
	}
}

- (void)webSocket:(TLWebSocketTransport *)transport didFailWithError:(NSError *)error
{
	[_stateLock lock];
	BOOL wasOpen = _isOpen;
	_isOpen = NO;
	_closing = YES;
	[_stateLock unlock];
	_watchdogRunning = NO;

	if ([_delegate respondsToSelector:@selector(engineIOClient:didFailWithError:)]) {
		[_delegate engineIOClient:self didFailWithError:error];
	} else if (wasOpen && [_delegate respondsToSelector:@selector(engineIOClientDidClose:)]) {
		[_delegate engineIOClientDidClose:self];
	}
}

- (void)webSocketDidClose:(TLWebSocketTransport *)transport
{
	[_stateLock lock];
	BOOL wasOpen = _isOpen;
	_isOpen = NO;
	_closing = YES;
	[_stateLock unlock];
	_watchdogRunning = NO;

	if (wasOpen && [_delegate respondsToSelector:@selector(engineIOClientDidClose:)]) {
		[_delegate engineIOClientDidClose:self];
	}
}

- (void)handleOpenPacket:(TLEngineIOPacket *)packet
{
	NSData *data = [packet.data dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *info = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![info isKindOfClass:[NSDictionary class]]) {
		NSError *error = [NSError errorWithDomain:@"TLEngineIOErrorDomain"
			code:2
			userInfo:@{NSLocalizedDescriptionKey: @"Invalid Engine.IO open packet"}];
		if ([_delegate respondsToSelector:@selector(engineIOClient:didFailWithError:)]) {
			[_delegate engineIOClient:self didFailWithError:error];
		}
		return;
	}

	if (info[@"sid"]) {
		[_sessionId release];
		_sessionId = [[info[@"sid"] description] retain];
	}
	if (info[@"pingInterval"]) {
		_pingInterval = [info[@"pingInterval"] doubleValue];
	}
	if (info[@"pingTimeout"]) {
		_pingTimeout = [info[@"pingTimeout"] doubleValue];
	}

	[_stateLock lock];
	_isOpen = YES;
	[_stateLock unlock];

	[self startWatchdog];

	if ([_delegate respondsToSelector:@selector(engineIOClientDidOpen:)]) {
		[_delegate engineIOClientDidOpen:self];
	}
}

- (void)notifyServerClose
{
	[_stateLock lock];
	if (_closing) {
		[_stateLock unlock];
		return;
	}
	_closing = YES;
	_isOpen = NO;
	[_stateLock unlock];
	_watchdogRunning = NO;

	if ([_delegate respondsToSelector:@selector(engineIOClientDidClose:)]) {
		[_delegate engineIOClientDidClose:self];
	}
}

- (BOOL)isOpen
{
	return _isOpen;
}

- (NSString *)sessionId
{
	return _sessionId;
}

- (NSTimeInterval)pingInterval
{
	return _pingInterval;
}

- (NSTimeInterval)pingTimeout
{
	return _pingTimeout;
}

@end