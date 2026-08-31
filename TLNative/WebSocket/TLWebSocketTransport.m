/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLWebSocketTransport.h"

#include <curl/curl.h>
#include <sys/select.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

#import "TLLogger.h"

@interface TLWebSocketTransport ()
{
	TLWebSocketState _state;
	NSThread *_thread;
	NSURL *_url;
	CURL *_curl;
	int _sockfd;
	int _wakePipe[2];
	NSLock *_sendLock;
	NSMutableArray *_sendQueue;
	BOOL _stop;
	NSMutableData *_pendingFragment;
	BOOL _pendingFragmentText;
}
@end

@implementation TLWebSocketTransport

- (instancetype)init
{
	self = [super init];
	if (self) {
		_state = TLWebSocketStateDisconnected;
		_sockfd = -1;
		_wakePipe[0] = -1;
		_wakePipe[1] = -1;
		_sendLock = [[NSLock alloc] init];
		// Convenience constructors return autoreleased objects; owned
		// ivars must retain them or they dangle once the creating
		// pool drains.
		_sendQueue = [[NSMutableArray alloc] init];
		_stop = NO;
		_pendingFragment = [[NSMutableData alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[self close];
	[_pendingFragment release];
	[_sendLock release];
	[_sendQueue release];
	[super dealloc];
}

- (void)connectToURL:(NSURL *)url
{
	if (_state != TLWebSocketStateDisconnected) {
		return;
	}
	if (_thread != nil && ![_thread isFinished]) {
		// A previous attempt is still winding down (its thread can block
		// inside curl_easy_perform for the connect timeout). Cancel it before
		// starting a new thread so two runloops never race on the shared CURL
		// handle.
		[self close];
	}
	_url = [url retain];
	_state = TLWebSocketStateConnecting;
	_stop = NO;
	_thread = [[NSThread alloc] initWithTarget:self selector:@selector(runLoop) object:nil];
	[_thread start];
}

- (void)runLoop
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	CURLcode res;

	_curl = curl_easy_init();
	if (!_curl) {
		[self failWithCode:CURLE_OUT_OF_MEMORY message:@"curl_easy_init failed"];
		[pool drain];
		return;
	}

	curl_easy_setopt(_curl, CURLOPT_URL, [[_url absoluteString] UTF8String]);
	// CURLOPT_CONNECT_ONLY with value 2 enables WebSocket mode (curl >= 8.0.1).
	curl_easy_setopt(_curl, CURLOPT_CONNECT_ONLY, 2L);
	curl_easy_setopt(_curl, CURLOPT_FOLLOWLOCATION, 1L);
	curl_easy_setopt(_curl, CURLOPT_MAXREDIRS, 5L);
	curl_easy_setopt(_curl, CURLOPT_CONNECTTIMEOUT, 30L);
	curl_easy_setopt(_curl, CURLOPT_USERAGENT, "TLounge/1.0");

	// TLS verification stays on by default.

	res = curl_easy_perform(_curl);
	if (res != CURLE_OK) {
		[self failWithCode:res message:[NSString stringWithFormat:@"%s", curl_easy_strerror(res)]];
		curl_easy_cleanup(_curl);
		_curl = NULL;
		[pool drain];
		return;
	}

	res = curl_easy_getinfo(_curl, CURLINFO_ACTIVESOCKET, &_sockfd);
	if (res != CURLE_OK || _sockfd < 0) {
		[self failWithCode:CURLE_COULDNT_CONNECT message:@"no active socket"];
		curl_easy_cleanup(_curl);
		_curl = NULL;
		[pool drain];
		return;
	}

	if (pipe(_wakePipe) != 0) {
		[self failWithCode:CURLE_COULDNT_CONNECT message:@"pipe() failed"];
		curl_easy_cleanup(_curl);
		_curl = NULL;
		[pool drain];
		return;
	}

	// A blocking pipe read on an empty pipe blocks forever instead of
	// returning 0, which would stall the select loop; drain it non-blocking.
	int pipeFlags = fcntl(_wakePipe[0], F_GETFL, 0);
	if (pipeFlags >= 0) {
		fcntl(_wakePipe[0], F_SETFL, pipeFlags | O_NONBLOCK);
	}

	_state = TLWebSocketStateOpen;
	if ([_delegate respondsToSelector:@selector(webSocketDidOpen:)]) {
		[_delegate webSocketDidOpen:self];
	}

	[self ioLoop];

	_state = TLWebSocketStateDisconnected;
	if ([_delegate respondsToSelector:@selector(webSocketDidClose:)]) {
		[_delegate webSocketDidClose:self];
	}

	if (_wakePipe[0] >= 0) {
		close(_wakePipe[0]);
		close(_wakePipe[1]);
		_wakePipe[0] = -1;
		_wakePipe[1] = -1;
	}
	if (_curl) {
		curl_easy_cleanup(_curl);
		_curl = NULL;
	}
	[_url release];
	_url = nil;

	[pool drain];
}

- (void)failWithCode:(CURLcode)code message:(NSString *)message
{
	_state = TLWebSocketStateDisconnected;
	NSError *error = [NSError errorWithDomain:@"TLWebSocketErrorDomain"
		code:code
		userInfo:@{NSLocalizedDescriptionKey: message}];
	if ([_delegate respondsToSelector:@selector(webSocket:didFailWithError:)]) {
		[_delegate webSocket:self didFailWithError:error];
	}
}

- (void)ioLoop
{
	while (!_stop) {
		fd_set readfds;
		FD_ZERO(&readfds);
		FD_SET(_sockfd, &readfds);
		int maxfd = _sockfd;
		if (_wakePipe[0] >= 0) {
			FD_SET(_wakePipe[0], &readfds);
			if (_wakePipe[0] > maxfd) {
				maxfd = _wakePipe[0];
			}
		}

		struct timeval timeout;
		timeout.tv_sec = 5;
		timeout.tv_usec = 0;

		int sel = select(maxfd + 1, &readfds, NULL, NULL, &timeout);
		if (_stop) {
			break;
		}
		if (sel < 0) {
			if (errno == EINTR) {
				continue;
			}
			break;
		}
		if (sel == 0) {
			if (_stop) {
				break;
			}
			continue;
		}

		if (_wakePipe[0] >= 0 && FD_ISSET(_wakePipe[0], &readfds)) {
			char buf[64];
			while (read(_wakePipe[0], buf, sizeof(buf)) > 0) {
			}
			[self drainSendQueue];
		}

		if (FD_ISSET(_sockfd, &readfds)) {
			if (![self receiveLoop]) {
				break;
			}
		}
	}
}

- (BOOL)receiveLoop
{
	char buffer[16384];
	size_t received;
	const struct curl_ws_frame *meta;
	CURLcode res;

	// Read until no more data is available without blocking.
	while (1) {
		received = 0;
		res = curl_ws_recv(_curl, buffer, sizeof(buffer), &received, &meta);
		if (res == CURLE_AGAIN) {
			return YES;
		}
		if (res != CURLE_OK) {
			// Connection closed or fatal error.
			return NO;
		}
		if (received == 0) {
			return YES;
		}

		unsigned int flags = meta->flags;

		// WebSocket control frames are handled by libcurl at the protocol level.
		if (flags & (CURLWS_PING | CURLWS_PONG)) {
			continue;
		}
		if (flags & CURLWS_CLOSE) {
			return NO;
		}

		// A single frame may be split across several curl_ws_recv calls.
		// meta->offset is 0 only for the first chunk of a frame, and
		// meta->bytesleft reports how much of the payload is still pending,
		// so accumulate chunks until the frame is complete.
		NSData *chunk = [NSData dataWithBytes:buffer length:received];
		BOOL frameStart = (meta->offset == 0);
		if (frameStart && !(flags & CURLWS_CONT)) {
			_pendingFragmentText = (flags & CURLWS_TEXT) != 0;
		}
		[_pendingFragment appendData:chunk];

		if (meta->bytesleft > 0) {
			continue;
		}

		NSData *fullMessage = [NSData dataWithData:_pendingFragment];
		[_pendingFragment setLength:0];

		if ([_delegate respondsToSelector:@selector(webSocket:didReceiveData:isText:)]) {
			[_delegate webSocket:self didReceiveData:fullMessage isText:_pendingFragmentText];
		}
	}
	return YES;
}

- (void)sendData:(NSData *)data isText:(BOOL)isText
{
	if (_state != TLWebSocketStateOpen) {
		return;
	}
	[_sendLock lock];
	[_sendQueue addObject:@[data, isText ? @"text" : @"binary"]];
	[_sendLock unlock];
	[self wakeLoop];
}

- (void)wakeLoop
{
	if (_wakePipe[1] >= 0) {
		char b = 1;
		write(_wakePipe[1], &b, 1);
	}
}

- (void)drainSendQueue
{
	while (1) {
		[_sendLock lock];
		if ([_sendQueue count] == 0) {
			[_sendLock unlock];
			return;
		}
		NSArray *item = [[_sendQueue objectAtIndex:0] retain];
		[_sendQueue removeObjectAtIndex:0];
		[_sendLock unlock];

		NSData *data = [[item objectAtIndex:0] retain];
		BOOL isText = [[item objectAtIndex:1] isEqualToString:@"text"];
		[item release];

		const char *bytes = [data bytes];
		size_t length = [data length];
		size_t offset = 0;

		while (offset < length) {
			size_t sent;
			CURLcode res = curl_ws_send(_curl, bytes + offset, length - offset, &sent, 0,
				isText ? CURLWS_TEXT : CURLWS_BINARY);
			if (res == CURLE_AGAIN) {
				continue;
			}
			if (res != CURLE_OK) {
				[data release];
				_stop = YES;
				return;
			}
			offset += sent;
		}
		[data release];
	}
}

- (void)close
{
	if (_thread == nil) {
		return;
	}
	_stop = YES;
	if (_wakePipe[1] >= 0) {
		[self wakeLoop];
	}
	// The background thread can be blocked inside curl_easy_perform for up to
	// CURLOPT_CONNECTTIMEOUT (30s) on an unreachable host. We must wait for it
	// to finish before releasing anything: runLoop cleans up the CURL handle
	// and URL at its very end, so once the thread has exited those ivars are
	// safe to touch. Releasing earlier lets the still-running thread
	// dereference freed memory and crash the process on exit.
	for (int i = 0; i < 4000 && ![_thread isFinished]; i++) {
		[NSThread sleepForTimeInterval:0.01];
	}
	[_thread release];
	_thread = nil;
}

@end