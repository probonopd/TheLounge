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

@interface TLApplicationDelegate : NSObject <NSApplicationDelegate, TLLoginControllerDelegate,
	TLRelayConnectControllerDelegate>

@property (nonatomic, readonly) TLoungeSession *session;

@end