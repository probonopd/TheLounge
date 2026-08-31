/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLRelayConnectController;

@protocol TLRelayConnectControllerDelegate <NSObject>
- (void)relayController:(TLRelayConnectController *)controller
	didSubmitRelayURL:(NSURL *)relayURL
	username:(NSString *)username
	privateKey:(NSString *)privateKey;
@end

@interface TLRelayConnectController : NSWindowController
{
	NSTextField *_relayField;
	NSTextField *_nameField;
	NSSecureTextField *_keyField;
	NSButton *_connectButton;
	NSTextField *_statusLabel;
	id<TLRelayConnectControllerDelegate> _delegate;
}

@property (nonatomic, assign) id<TLRelayConnectControllerDelegate> delegate;

- (IBAction)connect:(id)sender;
- (void)setStatusText:(NSString *)text;
- (void)setConnectEnabled:(BOOL)enabled;

@end
