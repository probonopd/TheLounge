/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

// User-visible chat preferences backed by NSUserDefaults. Kept separate
// from the preferences panel so model/UI code can read settings without
// dragging in window code.

// Posted on the main thread whenever a preference below changes value.
extern NSString *const TLBubbleStyleDidChangeNotification;

// Speech-bubble transcript style instead of the classic text log.
BOOL TLPreferencesUseBubbles(void);
void TLPreferencesSetUseBubbles(BOOL flag);

// Last open channel per server, so reconnecting to the same server reopens
// the same tab. The stored dictionary has an "id" (NSInteger) and a "name"
// (NSString) entry; the id is authoritative, the name is the fallback when
// the server handed out new identifiers.
NSDictionary *TLPreferencesLastChannelForServer(NSString *server);
void TLPreferencesSetLastChannelId(NSInteger identifier
	, NSString *name
	, NSString *server);
