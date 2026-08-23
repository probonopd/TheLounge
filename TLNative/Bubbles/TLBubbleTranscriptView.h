/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLBubbleMessage;
@class TLBubbleTheme;
@class TLBubbleTranscriptView;

@protocol TLBubbleTranscriptViewDelegate <NSObject>
@optional
- (void)transcriptViewDidActivateLink:(NSURL *)url;
@end

// Scrollable transcript of speech balloons. Incoming messages hug the left
// margin with the speaker picture beside them, outgoing messages hug the
// right margin - the geometry itself communicates authorship. The view is a
// self-contained NSView and can be embedded in any NSScrollView; it holds no
// references to other application objects.
@interface TLBubbleTranscriptView : NSView

@property (nonatomic, retain) TLBubbleTheme *theme;
@property (nonatomic, assign) id<TLBubbleTranscriptViewDelegate> delegate;

- (id)initWithFrame:(NSRect)frame theme:(TLBubbleTheme *)theme;

- (void)addMessage:(TLBubbleMessage *)message;
- (void)addMessages:(NSArray *)messages;
// Inserts older entries at the top (history loading); keeps the viewport
// anchored to the content the reader was looking at.
- (void)prependMessages:(NSArray *)messages;
- (void)clearMessages;

@property (nonatomic, readonly, copy) NSArray *messages;
@property (nonatomic, readonly) NSUInteger messageCount;
// When NO, appends do not move the viewport; callers that preserve the
// reader's position while scrolled up turn this off before adding.
@property (nonatomic, assign) BOOL autoScrollsToBottom;

// Transient state while a participant is composing; rendered as a small
// cloud beside that participant's picture until hidden or replaced.
- (void)showTypingIndicatorForSenderName:(NSString *)senderName
                                outgoing:(BOOL)outgoing
                                  avatar:(NSImage *)avatar;
- (void)hideTypingIndicator;

- (void)scrollToBottom;

@end
