/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLBubbleMessage;
@class TLBubbleTheme;

// Scrollable transcript of speech balloons. Incoming messages hug the left
// margin with the speaker picture beside them, outgoing messages hug the
// right margin - the geometry itself communicates authorship. The view is a
// self-contained NSView and can be embedded in any NSScrollView; it holds no
// references to other application objects.
@interface TLBubbleTranscriptView : NSView

@property (nonatomic, retain) TLBubbleTheme *theme;

- (id)initWithFrame:(NSRect)frame theme:(TLBubbleTheme *)theme;

- (void)addMessage:(TLBubbleMessage *)message;
- (void)addMessages:(NSArray *)messages;
- (void)clearMessages;

// Transient state while a participant is composing; rendered as a small
// cloud beside that participant's picture until hidden or replaced.
- (void)showTypingIndicatorForSenderName:(NSString *)senderName
                                outgoing:(BOOL)outgoing
                                  avatar:(NSImage *)avatar;
- (void)hideTypingIndicator;

- (void)scrollToBottom;

@end
