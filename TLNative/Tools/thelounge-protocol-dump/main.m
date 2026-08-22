/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <signal.h>
#import <stdlib.h>

#import "TLEngineIOClient.h"
#import "TLSocketIOParser.h"
#import "TLSocketIOPacket.h"

#define kMaxDumpSeconds 90

static volatile sig_atomic_t g_sigintReceived = 0;

static void HandleSIGINT(int signo)
{
	(void)signo;
	g_sigintReceived = 1;
}

static BOOL IsSensitiveKey(NSString *key)
{
	return [key isEqualToString:@"password"] || [key isEqualToString:@"token"]
		|| [key isEqualToString:@"user"] || [key isEqualToString:@"sid"];
}

// Walk the parsed JSON object graph and replace the value under any
// sensitive key with a placeholder so credentials never leak into the dump.
static id RedactSensitive(id object)
{
	if ([object isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[object count]];
		NSEnumerator *keys = [object keyEnumerator];
		id key;
		while ((key = [keys nextObject])) {
			id value = [object objectForKey:key];
			if (IsSensitiveKey([key description])) {
				[result setObject:@"[REDACTED]" forKey:key];
			} else {
				[result setObject:RedactSensitive(value) forKey:key];
			}
		}
		return result;
	}
	if ([object isKindOfClass:[NSArray class]]) {
		NSMutableArray *result = [NSMutableArray arrayWithCapacity:[object count]];
		for (id item in object) {
			[result addObject:RedactSensitive(item)];
		}
		return result;
	}
	return object;
}

static NSString *JSONStringForObject(id object)
{
	if (!object) {
		return nil;
	}
	NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
	if (!data) {
		return nil;
	}
	return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

// The Lounge serves the socket.io endpoint at <installation-path>socket.io/
// with EIO=4 and a raw websocket transport; this mirrors TLSocketIOClient so
// we can drive TLEngineIOClient directly and still see the raw frames.
static NSURL *SocketIOURLFromServerURL(NSURL *serverURL)
{
	NSString *path = serverURL.path;
	if ([path length] == 0) {
		path = @"/";
	}
	if (![path hasSuffix:@"/"]) {
		path = [path stringByAppendingString:@"/"];
	}
	NSString *socketIOPath = [path stringByAppendingString:@"socket.io/"];

	NSString *scheme = [serverURL.scheme lowercaseString];
	NSString *wsScheme = @"wss";
	if (scheme && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"ws"])) {
		wsScheme = @"ws";
	}

	NSString *host = serverURL.host;
	if (!host) {
		host = @"localhost";
	}
	NSMutableString *hostPart = [NSMutableString stringWithString:host];
	NSNumber *port = serverURL.port;
	if (port) {
		[hostPart appendFormat:@":%@", port];
	} else if ([wsScheme isEqualToString:@"ws"]) {
		[hostPart appendString:@":80"];
	} else {
		[hostPart appendString:@":443"];
	}

	NSString *urlString = [NSString stringWithFormat:@"%@://%@%@?EIO=4&transport=websocket",
		wsScheme, hostPart, socketIOPath];
	return [NSURL URLWithString:urlString];
}

@interface ProtocolDumpDelegate : NSObject <TLEngineIOClientDelegate>
{
	TLEngineIOClient *_client;
	NSString *_username;
	NSString *_password;
	NSString *_token;
	BOOL _didSendAuth;
	BOOL _terminated;
	BOOL _failed;
	NSLock *_lock;
	NSTimeInterval _deadline;
	NSUInteger _maxSeconds;
}

- (instancetype)initWithClient:(TLEngineIOClient *)client username:(NSString *)username
	password:(NSString *)password token:(NSString *)token maxSeconds:(NSUInteger)maxSeconds;

- (BOOL)isTerminated;
- (BOOL)didFail;
- (void)tick:(NSTimer *)timer;

@end

@implementation ProtocolDumpDelegate

- (instancetype)initWithClient:(TLEngineIOClient *)client username:(NSString *)username
	password:(NSString *)password token:(NSString *)token maxSeconds:(NSUInteger)maxSeconds
{
	self = [super init];
	if (self) {
		_client = [client retain];
		_username = [username retain];
		_password = [password retain];
		_token = [token retain];
		_didSendAuth = NO;
		_terminated = NO;
		_failed = NO;
		_lock = [[NSLock alloc] init];
		_maxSeconds = maxSeconds;
		_deadline = [NSDate timeIntervalSinceReferenceDate] + (NSTimeInterval)maxSeconds;
	}
	return self;
}

- (void)dealloc
{
	[_client release];
	[_username release];
	[_password release];
	[_token release];
	[_lock release];
	[super dealloc];
}

- (void)setTerminated:(BOOL)terminated failed:(BOOL)failed
{
	[_lock lock];
	_terminated = terminated;
	_failed = failed;
	[_lock unlock];
}

- (BOOL)isTerminated
{
	BOOL result;
	[_lock lock];
	result = _terminated;
	[_lock unlock];
	return result;
}

- (BOOL)didFail
{
	BOOL result;
	[_lock lock];
	result = _failed;
	[_lock unlock];
	return result;
}

- (void)sendAuthWithClient:(TLEngineIOClient *)client
{
	[_lock lock];
	if (_didSendAuth) {
		[_lock unlock];
		return;
	}
	_didSendAuth = YES;
	[_lock unlock];

	NSMutableDictionary *credentials = [NSMutableDictionary dictionary];
	[credentials setObject:_username forKey:@"user"];
	if (_token) {
		[credentials setObject:_token forKey:@"token"];
	} else {
		[credentials setObject:_password forKey:@"password"];
	}

	TLSocketIOPacket *packet = [TLSocketIOPacket eventPacketWithName:@"auth:perform"
		arguments:@[credentials]];
	NSString *serialized = [TLSocketIOParser serializePacket:packet];
	printf("[TX] auth:perform\n");
	[client sendMessageData:serialized];
}

#pragma mark - TLEngineIOClientDelegate

- (void)engineIOClientDidOpen:(TLEngineIOClient *)client
{
	printf("[TX] SOCKET.IO connect\n");
	[client sendMessageData:@"0"];
}

- (void)engineIOClient:(TLEngineIOClient *)client didReceiveMessageData:(NSString *)data
{
	printf("[RX] ENGINE.IO MESSAGE %s\n", [data UTF8String]);

	TLSocketIOPacket *packet = [TLSocketIOParser parsePacketFromString:data];
	if (!packet) {
		printf("[RX] SOCKET.IO EVENT\n");
		printf("[RX] EVENT: (unparseable)\n");
		printf("[RX] PAYLOAD: (none)\n");
		return;
	}

	printf("[RX] SOCKET.IO EVENT\n");

	NSString *eventName = @"";
	NSString *typeLabel = @"";
	switch (packet.type) {
		case TLSocketIOPacketTypeConnect:
			typeLabel = @"(connect)";
			break;
		case TLSocketIOPacketTypeDisconnect:
			typeLabel = @"(disconnect)";
			break;
		case TLSocketIOPacketTypeAck:
			typeLabel = @"(ack)";
			break;
		case TLSocketIOPacketTypeConnectError:
			typeLabel = @"(connect_error)";
			break;
		case TLSocketIOPacketTypeBinaryAck:
			typeLabel = @"(binary_ack)";
			break;
		case TLSocketIOPacketTypeEvent:
		case TLSocketIOPacketTypeBinaryEvent:
			eventName = [packet eventName];
			break;
	}
	if ([typeLabel length] > 0) {
		printf("[RX] EVENT: %s\n", [typeLabel UTF8String]);
	} else {
		printf("[RX] EVENT: %s\n", [eventName UTF8String]);
	}

	id sanitized = RedactSensitive(packet.data);
	NSString *payload = JSONStringForObject(sanitized);
	if (!payload) {
		payload = @"(none)";
	}
	printf("[RX] PAYLOAD: %s\n", [payload UTF8String]);

	if (packet.type == TLSocketIOPacketTypeEvent && [eventName isEqualToString:@"auth:start"]) {
		[self sendAuthWithClient:client];
	}
}

- (void)engineIOClientDidClose:(TLEngineIOClient *)client
{
	(void)client;
	printf("[*] connection closed\n");
	[self setTerminated:YES failed:NO];
}

- (void)engineIOClient:(TLEngineIOClient *)client didFailWithError:(NSError *)error
{
	(void)client;
	printf("[*] connection failed: %s\n", [[error localizedDescription] UTF8String]);
	[self setTerminated:YES failed:YES];
}

- (void)tick:(NSTimer *)timer
{
	(void)timer;
	if (g_sigintReceived) {
		printf("[*] interrupted, closing connection\n");
		[_client close];
		exit(0);
	}
	if ([self isTerminated]) {
		[_client close];
		exit([self didFail] ? 1 : 0);
	}
	if ([NSDate timeIntervalSinceReferenceDate] >= _deadline) {
		printf("[*] dump finished after %lu seconds\n", (unsigned long)_maxSeconds);
		[_client close];
		exit(0);
	}
}

@end

static int PrintUsage(void)
{
	printf("Usage: thelounge-protocol-dump <server-url> <username> --password <password>\n");
	printf("       thelounge-protocol-dump <server-url> <username> --token <token>\n");
	return 2;
}

int main(int argc, char **argv)
{
	(void)argc;
	(void)argv;

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	setvbuf(stdout, NULL, _IOLBF, 0);

	NSArray *args = [[NSProcessInfo processInfo] arguments];
	if ([args count] != 5) {
		int code = PrintUsage();
		[pool drain];
		return code;
	}

	NSString *serverURLString = [args objectAtIndex:1];
	NSString *username = [args objectAtIndex:2];
	NSString *mode = [args objectAtIndex:3];
	NSString *secret = [args objectAtIndex:4];

	NSString *password = nil;
	NSString *token = nil;
	if ([mode isEqualToString:@"--password"]) {
		password = secret;
	} else if ([mode isEqualToString:@"--token"]) {
		token = secret;
	} else {
		int code = PrintUsage();
		[pool drain];
		return code;
	}

	NSURL *serverURL = [NSURL URLWithString:serverURLString];
	NSURL *socketIOURL = serverURL ? SocketIOURLFromServerURL(serverURL) : nil;
	if (!socketIOURL) {
		printf("Invalid server URL: %s\n", [serverURLString UTF8String]);
		[pool drain];
		return 1;
	}

	signal(SIGINT, HandleSIGINT);

	TLEngineIOClient *client = [[TLEngineIOClient alloc] init];
	ProtocolDumpDelegate *delegate = [[ProtocolDumpDelegate alloc]
		initWithClient:client username:username password:password token:token
		maxSeconds:kMaxDumpSeconds];
	client.delegate = delegate;

	printf("Connecting to %s\n", [[socketIOURL absoluteString] UTF8String]);
	[client connectToURL:socketIOURL];

	[NSTimer scheduledTimerWithTimeInterval:0.25
		target:delegate selector:@selector(tick:) userInfo:nil repeats:YES];
	[[NSRunLoop currentRunLoop] run];

	[client release];
	[delegate release];
	[pool drain];
	return 0;
}