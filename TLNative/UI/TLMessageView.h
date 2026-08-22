/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLMessage;
@class TLMessageView;

@protocol TLMessageViewDelegate <NSObject>
- (void)messageViewDidScrollToTop:(TLMessageView *)messageView;
@end

@interface TLMessageView : NSView
{
	NSScrollView *_scrollView;
	NSTextView *_textView;
	NSMutableSet *_messageIdentifiers;
	NSInteger _channelId;
	BOOL _hasMoreHistory;
	id<TLMessageViewDelegate> _delegate;
}

@property (nonatomic, assign) id<TLMessageViewDelegate> delegate;
@property (nonatomic, assign) NSInteger channelId;
@property (nonatomic, assign) BOOL hasMoreHistory;

- (void)appendMessage:(TLMessage *)message;
- (void)prependMessages:(NSArray *)messages;
- (void)clear;
- (void)scrollToBottom;

@end