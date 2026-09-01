/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "TLLoginController.h"
#import "TLRelayConnectController.h"

@class TLoungeSession;
@class TLMainWindowController;
@class TLNetwork;

@interface TLApplicationDelegate : NSObject <NSApplicationDelegate, TLLoginControllerDelegate,
	TLRelayConnectControllerDelegate>

@property (nonatomic, readonly) TLoungeSession *session;

// Saves the current Lounge and Nosterm servers to the persistent list so
// they can be restored on the next launch.
- (void)saveCurrentServers;
// Removes a specific server from the saved list by its URL string.
- (void)removeServerFromSavedList:(NSString *)serverURLString;

@end