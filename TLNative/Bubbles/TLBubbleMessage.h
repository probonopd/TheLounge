/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

// One entry of a conversation transcript. Plain attributed text is the
// canonical content; if attributedText is set it wins over text, which lets
// callers carry rich formatting without forcing them to build attribute
// dictionaries for simple messages.
@interface TLBubbleMessage : NSObject

@property (nonatomic, copy) NSString *senderName;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, retain) NSAttributedString *attributedText;
@property (nonatomic, assign) BOOL outgoing;
@property (nonatomic, retain) NSImage *avatar;

+ (instancetype)messageWithText:(NSString *)text
                     senderName:(NSString *)senderName
                       outgoing:(BOOL)outgoing;

@end
