/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLMessageView.h"

#import "TLMessage.h"
#import "TLMessageRenderer.h"

@implementation TLMessageView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_channelId = 0;
		_hasMoreHistory = NO;
		_messageIdentifiers = [[NSMutableSet alloc] init];

		_scrollView = [[NSScrollView alloc] initWithFrame:[self bounds]];
		[_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[_scrollView setHasVerticalScroller:YES];
		[_scrollView setAutohidesScrollers:YES];
		[_scrollView setBorderType:NSBezelBorder];

		NSSize contentSize = [_scrollView contentSize];
		_textView = [[NSTextView alloc] initWithFrame:
			NSMakeRect(0, 0, contentSize.width, contentSize.height)];
		[_textView setMinSize:NSMakeSize(0.0, contentSize.height)];
		[_textView setMaxSize:NSMakeSize(1.0e7, 1.0e7)];
		[_textView setVerticallyResizable:YES];
		[_textView setHorizontallyResizable:NO];
		[_textView setAutoresizingMask:NSViewWidthSizable];
		[[_textView textContainer] setContainerSize:NSMakeSize(contentSize.width, 1.0e7)];
		[[_textView textContainer] setWidthTracksTextView:YES];
		[_textView setEditable:NO];
		[_textView setSelectable:YES];
		[_textView setAllowsUndo:NO];
		[_scrollView setDocumentView:_textView];

		// The clip view must report bounds changes so scrolling to the very
		// top can be detected and used to trigger history loading.
		NSClipView *clipView = [_scrollView contentView];
		[clipView setPostsBoundsChangedNotifications:YES];
		[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(clipViewBoundsDidChange:)
			name:NSViewBoundsDidChangeNotification object:clipView];

		[self addSubview:_scrollView];
	}
	return self;
}

- (void)setDelegate:(id<TLMessageViewDelegate>)delegate
{
	_delegate = delegate;
}

- (id<TLMessageViewDelegate>)delegate
{
	return _delegate;
}

- (void)setChannelId:(NSInteger)channelId
{
	_channelId = channelId;
}

- (NSInteger)channelId
{
	return _channelId;
}

- (void)setHasMoreHistory:(BOOL)hasMoreHistory
{
	_hasMoreHistory = hasMoreHistory;
}

- (BOOL)hasMoreHistory
{
	return _hasMoreHistory;
}

#pragma mark - Content

- (void)appendMessage:(TLMessage *)message
{
	if (!message) {
		return;
	}
	if ([_messageIdentifiers containsObject:@(message.identifier)]) {
		return;
	}
	[_messageIdentifiers addObject:@(message.identifier)];

	BOOL wasAtBottom = [self isScrolledToBottom];
	[[_textView textStorage] appendAttributedString:
		[TLMessageRenderer attributedStringForMessage:message]];
	[[_textView textStorage] appendAttributedString:
		[[[NSAttributedString alloc] initWithString:@"\n"] autorelease]];
	if (wasAtBottom) {
		[self scrollToBottom];
	}
}

- (void)prependMessages:(NSArray *)messages
{
	if (!messages || [messages count] == 0) {
		return;
	}

	NSMutableAttributedString *inserted = [[NSMutableAttributedString alloc] init];
	BOOL firstInserted = YES;
	for (TLMessage *message in messages) {
		if ([_messageIdentifiers containsObject:@(message.identifier)]) {
			continue;
		}
		[_messageIdentifiers addObject:@(message.identifier)];
		if (!firstInserted) {
			[inserted appendAttributedString:
				[[[NSAttributedString alloc] initWithString:@"\n"] autorelease]];
		}
		[inserted appendAttributedString:
			[TLMessageRenderer attributedStringForMessage:message]];
		firstInserted = NO;
	}
	if ([inserted length] == 0) {
		[inserted release];
		return;
	}
	[inserted appendAttributedString:
		[[[NSAttributedString alloc] initWithString:@"\n"] autorelease]];

	NSUInteger insertedLength = [inserted length];
	NSClipView *clipView = [_scrollView contentView];
	CGFloat oldOriginY = [clipView bounds].origin.y;

	[[_textView textStorage] beginEditing];
	[[_textView textStorage] insertAttributedString:inserted atIndex:0];
	[[_textView textStorage] endEditing];
	[inserted release];

	// The document grows at the top; shift the scroll offset down by the
	// inserted height so the previously visible messages stay on screen.
	NSLayoutManager *layoutManager = [_textView layoutManager];
	NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:
		NSMakeRange(0, insertedLength) actualCharacterRange:NULL];
	[layoutManager ensureLayoutForGlyphRange:glyphRange];
	NSRect insertedBounds = [layoutManager boundingRectForGlyphRange:glyphRange
		inTextContainer:[_textView textContainer]];
	CGFloat addedHeight = NSHeight(insertedBounds);
	if (addedHeight > 0.0) {
		NSPoint newOrigin = [clipView bounds].origin;
		newOrigin.y = oldOriginY + addedHeight;
		[clipView scrollToPoint:newOrigin];
	}
}

- (void)clear
{
	[_messageIdentifiers removeAllObjects];
	[[_textView textStorage] setAttributedString:
		[[[NSAttributedString alloc] init] autorelease]];
}

- (void)scrollToBottom
{
	NSUInteger length = [[_textView textStorage] length];
	[_textView scrollRangeToVisible:NSMakeRange(length, 0)];
}

#pragma mark - Scrolling

- (BOOL)isScrolledToBottom
{
	NSClipView *clipView = [_scrollView contentView];
	CGFloat documentHeight = NSHeight([_textView frame]);
	CGFloat visibleHeight = NSHeight([clipView bounds]);
	CGFloat bottomOrigin = documentHeight - visibleHeight;
	return [clipView bounds].origin.y >= bottomOrigin - 2.0;
}

- (BOOL)isScrolledToTop
{
	// The text view is flipped, so origin.y == 0 is the top of the document.
	return [_scrollView contentView].bounds.origin.y <= 0.0;
}

- (void)clipViewBoundsDidChange:(NSNotification *)notification
{
	if (!_hasMoreHistory || ![_delegate respondsToSelector:@selector(messageViewDidScrollToTop:)]) {
		return;
	}
	if ([self isScrolledToTop]) {
		[_delegate messageViewDidScrollToTop:self];
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_scrollView release];
	[_textView release];
	[_messageIdentifiers release];
	[super dealloc];
}

@end