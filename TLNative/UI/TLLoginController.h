/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLLoginController;

@protocol TLLoginControllerDelegate <NSObject>
- (void)loginController:(TLLoginController *)controller
	didSubmitServerURL:(NSURL *)serverURL
	username:(NSString *)username
	password:(NSString *)password
	remember:(BOOL)remember;
@end

@interface TLLoginController : NSWindowController
{
	NSTextField *_serverField;
	NSTextField *_usernameField;
	NSSecureTextField *_passwordField;
	NSButton *_rememberButton;
	NSButton *_connectButton;
	NSTextField *_statusLabel;
	id<TLLoginControllerDelegate> _delegate;
}

@property (nonatomic, assign) id<TLLoginControllerDelegate> delegate;

- (IBAction)connect:(id)sender;
- (void)setStatusText:(NSString *)text;
- (void)prepareForRetry;

@end