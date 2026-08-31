/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLMessageView.h"

#import "TLMessage.h"
#import "TLMessageRenderer.h"
#import "TLPreferences.h"
#import "TLBubbleMessage.h"
#import "TLBubbleTranscriptView.h"

@interface TLMessageView () <TLBubbleTranscriptViewDelegate>
@end

@implementation TLMessageView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_channelId = 0;
		_hasMoreHistory = NO;
		_messageIdentifiers = [[NSMutableSet alloc] init];
		_avatarCache = [[NSMutableDictionary alloc] init];

		_scrollView = [[NSScrollView alloc] initWithFrame:[self bounds]];
		[_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[_scrollView setHasVerticalScroller:YES];
		[_scrollView setAutohidesScrollers:YES];
		[_scrollView setBorderType:NSBezelBorder];

		// The clip view must report bounds changes so scrolling to the very
		// top can be detected and used to trigger history loading.
		NSClipView *clipView = [_scrollView contentView];
		[clipView setPostsBoundsChangedNotifications:YES];
		[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(clipViewBoundsDidChange:)
			name:NSViewBoundsDidChangeNotification object:clipView];

		_usesBubbles = TLPreferencesUseBubbles();
		if (_usesBubbles) {
			[self installTranscriptView];
		} else {
			[self installTextView];
		}

		[self addSubview:_scrollView];
	}
	return self;
}

- (void)installTextView
{
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
	[_textView setDelegate:self];
	[_scrollView setDocumentView:_textView];
}

- (void)installTranscriptView
{
	NSSize contentSize = [_scrollView contentSize];
	_transcriptView = [[TLBubbleTranscriptView alloc]
		initWithFrame:NSMakeRect(0, 0, contentSize.width, 100.0)
		        theme:nil];
	[_transcriptView setAutoresizingMask:NSViewWidthSizable];
	[_transcriptView setDelegate:self];
	[_scrollView setDocumentView:_transcriptView];
}

- (void)setUsesBubbles:(BOOL)flag
{
	if (_usesBubbles == flag) {
		return;
	}
	_usesBubbles = flag;

	// Drop the old renderer before installing the new one; the document
	// view holds its own reference, so nil it out first.
	[_scrollView setDocumentView:nil];
	[_textView release];
	_textView = nil;
	[_transcriptView release];
	_transcriptView = nil;

	if (_usesBubbles) {
		[self installTranscriptView];
	} else {
		[self installTextView];
	}
	[_messageIdentifiers removeAllObjects];
	[_avatarCache removeAllObjects];
}

- (BOOL)usesBubbles
{
	return _usesBubbles;
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

#pragma mark - Bubble conversion

// Initials avatar matching the nick color used by the text log.
- (NSImage *)avatarForNick:(NSString *)nick
{
	NSString *key = [nick length] > 0 ? nick : @"?";
	NSImage *cached = [_avatarCache objectForKey:key];
	if (cached) {
		return cached;
	}

	CGFloat side = 36.0;
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(side, side)];
	[image lockFocus];
	[[TLMessageRenderer colorForNick:key] setFill];
	[[NSBezierPath bezierPathWithOvalInRect:
		NSInsetRect(NSMakeRect(0, 0, side, side), 1.0, 1.0)] fill];
	NSString *initial = [TLMessageRenderer initialForNick:key];
	NSDictionary *attrs = [NSDictionary dictionaryWithObject:
		[NSFont boldSystemFontOfSize:15.0] forKey:NSFontAttributeName];
	NSSize textSize = [initial sizeWithAttributes:attrs];
	[[NSColor whiteColor] set];
	[initial drawAtPoint:NSMakePoint((side - textSize.width) / 2.0,
	    (side - textSize.height) / 2.0) withAttributes:attrs];
	[image unlockFocus];

	[_avatarCache setObject:image forKey:key];
	[image release];
	return image;
}

- (TLBubbleMessage *)bubbleMessageForChatMessage:(TLMessage *)message
{
	TLBubbleMessage *bubble = [[TLBubbleMessage alloc] init];
	NSString *nick = message.sender.nick ?: @"";
	bubble.outgoing = [message isSelf];
	bubble.plainLine = [message isSystemMessage];
	bubble.senderName = nick;
	// Same palette as the text log and the avatar, so one user always has
	// one color across all three renderings.
	if (![message isSystemMessage]) {
		bubble.senderColor = [TLMessageRenderer colorForNick:nick];
	}
	bubble.attributedText =
		[TLMessageRenderer attributedStringForBubbleBodyOfMessage:message];
	bubble.avatar = [self avatarForNick:nick];
	return [bubble autorelease];
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
	if (_usesBubbles) {
		[_transcriptView setAutoScrollsToBottom:wasAtBottom];
		[_transcriptView addMessage:[self bubbleMessageForChatMessage:message]];
		return;
	}
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

	if (_usesBubbles) {
		NSMutableArray *bubbles = [[NSMutableArray alloc]
			initWithCapacity:[messages count]];
		for (TLMessage *message in messages) {
			if ([_messageIdentifiers containsObject:@(message.identifier)]) {
				continue;
			}
			[_messageIdentifiers addObject:@(message.identifier)];
			[bubbles addObject:[self bubbleMessageForChatMessage:message]];
		}
		[_transcriptView prependMessages:bubbles];
		[bubbles release];
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
	if (_usesBubbles) {
		[_transcriptView clearMessages];
		return;
	}
	[[_textView textStorage] setAttributedString:
		[[[NSAttributedString alloc] init] autorelease]];
}

- (BOOL)isEmpty
{
	return [_messageIdentifiers count] == 0;
}

- (void)scrollToBottom
{
	if (_usesBubbles) {
		[_transcriptView scrollToBottom];
		return;
	}
	NSUInteger length = [[_textView textStorage] length];
	[_textView scrollRangeToVisible:NSMakeRange(length, 0)];
}

#pragma mark - Links

// Both transcript styles funnel link activation here; NSWorkspace hands the
// URL to whatever handler the desktop environment registers for it.
- (void)openLink:(NSURL *)url
{
	if (![[NSWorkspace sharedWorkspace] openURL:url]) {
		NSLog(@"The Lounge: failed to open link %@", url);
	}
}

- (BOOL)textView:(NSTextView *)textView
	clickedOnLink:(id)link
	      atIndex:(NSUInteger)charIndex
{
	NSURL *url = [link isKindOfClass:[NSURL class]]
	    ? (NSURL *)link
	    : [NSURL URLWithString:[link description]];
	if (url != nil) {
		[self openLink:url];
	}
	return YES;
}

- (void)transcriptViewDidActivateLink:(NSURL *)url
{
	[self openLink:url];
}

- (void)transcriptViewDidSelectSender:(NSString *)senderName
{
	if ([_delegate respondsToSelector:@selector(messageView:didSelectSenderNick:)]) {
		[_delegate messageView:self didSelectSenderNick:senderName];
	}
}

#pragma mark - Scrolling

- (CGFloat)documentHeight
{
	return _usesBubbles
	    ? [_transcriptView frame].size.height
	    : [_textView frame].size.height;
}

- (BOOL)isScrolledToBottom
{
	NSClipView *clipView = [_scrollView contentView];
	CGFloat bottomOrigin = [self documentHeight]
	    - NSHeight([clipView bounds]);
	return [clipView bounds].origin.y >= bottomOrigin - 2.0;
}

- (BOOL)isScrolledToTop
{
	// Both renderers lay their documents out flipped, so origin.y == 0 is
	// the top of the transcript.
	return [_scrollView contentView].bounds.origin.y <= 0.0;
}

- (BOOL)contentFillsViewport
{
	NSClipView *clipView = [_scrollView contentView];
	if (_usesBubbles) {
		return [self documentHeight]
		    > NSHeight([clipView bounds]) + 2.0;
	}
	// The frame only grows once layout has processed pending edits.
	[[_textView layoutManager] ensureLayoutForTextContainer:[_textView textContainer]];
	return [self documentHeight] > NSHeight([clipView bounds]) + 2.0;
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
	[_transcriptView release];
	[_avatarCache release];
	[_messageIdentifiers release];
	[super dealloc];
}

@end
