/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLMessage;
@class TLMessageView;
@class TLBubbleTranscriptView;

@protocol TLMessageViewDelegate <NSObject>
- (void)messageViewDidScrollToTop:(TLMessageView *)messageView;
@end

// Channel transcript container. Renders either the classic text log or the
// speech-bubble style; switching styles rebuilds the content view empty, so
// callers must repopulate afterwards.
@interface TLMessageView : NSView
{
	NSScrollView *_scrollView;
	NSTextView *_textView;
	TLBubbleTranscriptView *_transcriptView;
	NSMutableDictionary *_avatarCache;
	NSMutableSet *_messageIdentifiers;
	NSInteger _channelId;
	BOOL _hasMoreHistory;
	BOOL _usesBubbles;
	id<TLMessageViewDelegate> _delegate;
}

@property (nonatomic, assign) id<TLMessageViewDelegate> delegate;
@property (nonatomic, assign) NSInteger channelId;
@property (nonatomic, assign) BOOL hasMoreHistory;

- (void)setUsesBubbles:(BOOL)flag;
- (BOOL)usesBubbles;

- (void)appendMessage:(TLMessage *)message;
- (void)prependMessages:(NSArray *)messages;
- (void)clear;
- (void)scrollToBottom;

// NO when the transcript is shorter than the visible area, so there is
// nothing to scroll; callers use this to fetch older messages instead of
// waiting for a scroll-to-top that can never happen.
- (BOOL)contentFillsViewport;

@end
