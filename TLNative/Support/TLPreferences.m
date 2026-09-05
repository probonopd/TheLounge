/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLPreferences.h"

NSString *const TLBubbleStyleDidChangeNotification =
	@"TLBubbleStyleDidChangeNotification";

static NSString * const TLUseBubblesKey = @"TLUseBubbleStyle";
static NSString * const TLPlaySoundOnIncomingMessagesKey = @"TLPlaySoundOnIncomingMessages";
static NSString * const TLLastChannelsKey = @"TLLastOpenChannels";

@interface TLPreferences : NSObject
+ (void)initialize;
@end

@implementation TLPreferences

+ (void)initialize
{
	if (self == [TLPreferences class]) {
		NSDictionary *defaults = [NSDictionary dictionaryWithObjectsAndKeys:
			@YES, TLPlaySoundOnIncomingMessagesKey, nil];
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
	}
}

BOOL TLPreferencesUseBubbles(void)
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:TLUseBubblesKey];
}

void TLPreferencesSetUseBubbles(BOOL flag)
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL current = [defaults boolForKey:TLUseBubblesKey];
	if (current == flag) {
		return;
	}
	[defaults setBool:flag forKey:TLUseBubblesKey];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:TLBubbleStyleDidChangeNotification object:nil];
}

BOOL TLPreferencesPlaySoundOnIncomingMessages(void)
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:TLPlaySoundOnIncomingMessagesKey];
}

void TLPreferencesSetPlaySoundOnIncomingMessages(BOOL flag)
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:flag forKey:TLPlaySoundOnIncomingMessagesKey];
}

NSDictionary *TLPreferencesLastChannelForServer(NSString *server)
{
	if ([server length] == 0) {
		return nil;
	}
	NSDictionary *all = [[NSUserDefaults standardUserDefaults]
		dictionaryForKey:TLLastChannelsKey];
	return [all objectForKey:server];
}

void TLPreferencesSetLastChannelId(NSInteger identifier
	, NSString *name
	, NSString *server)
{
	if ([server length] == 0) {
		return;
	}
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *all = [[[defaults
		dictionaryForKey:TLLastChannelsKey] mutableCopy] autorelease];
	if (all == nil) {
		all = [NSMutableDictionary dictionary];
	}
	[all setObject:[NSDictionary dictionaryWithObjectsAndKeys:
		@(identifier), @"id", name ?: @"", @"name", nil]
		forKey:server];
	[defaults setObject:all forKey:TLLastChannelsKey];
}

@end
