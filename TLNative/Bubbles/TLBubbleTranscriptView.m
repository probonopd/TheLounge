/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLBubbleTranscriptView.h"

#import "TLBubbleMessage.h"
#import "TLBubbleTheme.h"

#import <math.h>
#import <float.h>

// One laid-out entry of the transcript. Rectangles are stored in view
// coordinates after the bottom-anchoring pass, ready for direct drawing.
@interface TLBubbleCell : NSObject
{
@public
	TLBubbleMessage *_message;
	NSString *_senderName;
	NSImage *_avatar;
	NSRect _bubbleRect;
	NSRect _textRect;
	NSRect _avatarRect;
	BOOL _outgoing;
	BOOL _isTyping;
}

@end

@implementation TLBubbleCell

- (void)dealloc
{
	[_message release];
	[_senderName release];
	[_avatar release];
	[super dealloc];
}

@end

static NSAttributedString *TLAttributedFromString(NSString *text,
                                                  NSFont *font, NSColor *color)
{
	NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
	    font, NSFontAttributeName,
	    color, NSForegroundColorAttributeName,
	    nil];
	return [[[NSAttributedString alloc] initWithString:text
	                                           attributes:attrs] autorelease];
}

// Deterministic hue per sender so placeholder pictures stay recognizable.
static NSColor *TLPlaceholderColorForName(NSString *name)
{
	NSUInteger hash = 17;
	NSUInteger length = [name length];
	for (NSUInteger i = 0; i < length; i++) {
		hash = hash * 31 + [name characterAtIndex:i];
	}
	CGFloat hue = (CGFloat)(hash % 360) / 360.0;
	return [NSColor colorWithCalibratedHue:hue
	                             saturation:0.45
	                             brightness:0.78
	                                  alpha:1.0];
}

static NSColor *TLLerpColor(NSColor *a, NSColor *b, CGFloat t)
{
	NSColor *ca = [a colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	NSColor *cb = [b colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	return [NSColor colorWithCalibratedRed:[ca redComponent] +
	            ([cb redComponent] - [ca redComponent]) * t
	                                     green:[ca greenComponent] +
	            ([cb greenComponent] - [ca greenComponent]) * t
	                                      blue:[ca blueComponent] +
	            ([cb blueComponent] - [ca blueComponent]) * t
	                                     alpha:[ca alphaComponent] +
	            ([cb alphaComponent] - [ca alphaComponent]) * t];
}

@implementation TLBubbleTranscriptView
{
	NSMutableArray *_messages;
	NSMutableArray *_cells;

	NSString *_typingSenderName;
	NSImage *_typingAvatar;
	BOOL _typingOutgoing;
	BOOL _typingVisible;

	TLBubbleTheme *_theme;

	// Set when content arrives; consumed at the end of the next relayout so
	// the scroll lands on a document whose height is already final.
	BOOL _pendingScrollToBottom;

	CGFloat _laidOutWidth;
	CGFloat _laidOutHeight;

	NSTextStorage *_textStorage;
	NSLayoutManager *_layoutManager;
	NSTextContainer *_textContainer;
}

@synthesize theme = _theme;

- (id)initWithFrame:(NSRect)frame theme:(TLBubbleTheme *)theme
{
	self = [super initWithFrame:frame];
	if (self) {
		_messages = [[NSMutableArray alloc] init];
		_cells = [[NSMutableArray alloc] init];

		_theme = [(theme ?: [TLBubbleTheme defaultTheme]) copy];

		_textStorage = [[NSTextStorage alloc] init];
		_layoutManager = [[NSLayoutManager alloc] init];
		[_textStorage addLayoutManager:_layoutManager];
		_textContainer = [[NSTextContainer alloc]
		    initWithContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
		[_textContainer setLineFragmentPadding:0.0];
		[_layoutManager addTextContainer:_textContainer];
	}
	return self;
}

- (id)initWithFrame:(NSRect)frame
{
	return [self initWithFrame:frame theme:nil];
}

- (void)setTheme:(TLBubbleTheme *)theme
{
	if (_theme != theme) {
		[_theme release];
		_theme = [theme copy];
		[self relayout];
	}
}

- (BOOL)isFlipped
{
	// Top-down layout matches reading order, and the AppKit text system
	// anchors attributed-string drawing at the rect top in flipped views.
	return YES;
}

#pragma mark Public API

- (void)addMessage:(TLBubbleMessage *)message
{
	if (message == nil) {
		return;
	}
	[_messages addObject:message];
	_pendingScrollToBottom = YES;
	[self relayout];
}

- (void)addMessages:(NSArray *)messages
{
	if ([messages count] == 0) {
		return;
	}
	[_messages addObjectsFromArray:messages];
	_pendingScrollToBottom = YES;
	[self relayout];
}

- (void)clearMessages
{
	[_messages removeAllObjects];
	_typingVisible = NO;
	_pendingScrollToBottom = NO;
	[self relayout];
}

- (void)showTypingIndicatorForSenderName:(NSString *)senderName
                                outgoing:(BOOL)outgoing
                                  avatar:(NSImage *)avatar
{
	[_typingSenderName release];
	_typingSenderName = [senderName copy];
	[_typingAvatar release];
	_typingAvatar = [avatar retain];
	_typingOutgoing = outgoing;
	_typingVisible = YES;
	_pendingScrollToBottom = YES;
	[self relayout];
}

- (void)hideTypingIndicator
{
	if (!_typingVisible) {
		return;
	}
	_typingVisible = NO;
	[_typingSenderName release];
	_typingSenderName = nil;
	[_typingAvatar release];
	_typingAvatar = nil;
	[self relayout];
}

- (void)scrollToBottom
{
	NSScrollView *scrollView = [self enclosingScrollView];
	if (scrollView == nil) {
		return;
	}
	// Flipped view: the newest content lives at the largest y.
	NSRect target = NSMakeRect(0.0, [self frame].size.height - 2.0, 1.0, 1.0);
	[self scrollRectToVisible:target];
}

#pragma mark Layout

- (NSAttributedString *)displayStringForMessage:(TLBubbleMessage *)message
{
	NSAttributedString *attributed = [message attributedText];
	if (attributed != nil) {
		return attributed;
	}
	NSString *text = [message text];
	if (text == nil) {
		text = @"";
	}
	NSColor *color = [message outgoing]
	    ? [_theme outgoingTextColor]
	    : [_theme incomingTextColor];
	return TLAttributedFromString(text, [_theme messageFont], color);
}

// Measures the string laid out at the given width. Returns the tight used
// size according to the text system, so bubble sizing follows real wrapping.
- (NSSize)measureString:(NSAttributedString *)string width:(CGFloat)width
{
	[_textStorage setAttributedString:string];
	[_textContainer setContainerSize:NSMakeSize(width, FLT_MAX)];
	NSRect used = [_layoutManager usedRectForTextContainer:_textContainer];
	return NSMakeSize(ceil(used.size.width), ceil(used.size.height));
}

- (void)appendCellWithMessage:(TLBubbleMessage *)message
                  typingState:(BOOL)isTyping
                      atTop:(CGFloat)top
                 transcriptWidth:(CGFloat)width
                          result:(TLBubbleCell **)outCell
                           height:(CGFloat *)outHeight
{
	TLBubbleTheme *t = _theme;
	CGFloat inset = t.paddingH;
	CGFloat maxBubbleWidth = floor(width * t.maxBubbleWidthRatio);
	CGFloat usableWidth = maxBubbleWidth - 2.0 * t.paddingH;

	TLBubbleCell *cell = [[TLBubbleCell alloc] init];
	cell->_message = [message retain];
	cell->_outgoing = [message outgoing];
	cell->_isTyping = isTyping;
	cell->_senderName = [[message senderName] copy];
	cell->_avatar = [[message avatar] retain];

	NSRect bubbleRect;
	NSRect textRect;
	CGFloat cellHeight;

	if (isTyping) {
		// Small transient cloud, deliberately lighter-weight than a sent
		// balloon so it never reads as a message.
		CGFloat h = floor(t.avatarSide * 0.52);
		CGFloat w = floor(t.avatarSide * 1.45);
		bubbleRect = NSMakeRect(0.0, top, w, h);
		cellHeight = h;
	} else {
		NSAttributedString *string = [self displayStringForMessage:message];
		NSSize ideal = [self measureString:string width:usableWidth];
		CGFloat textWidth = ideal.width;
		CGFloat textHeight = ideal.height;
		if (ideal.width > usableWidth || ideal.width <= 0.0) {
			textWidth = usableWidth;
			textHeight = [self measureString:string width:textWidth].height;
		}
		CGFloat bubbleWidth = ceil(textWidth) + 2.0 * t.paddingH + 4.0;
		CGFloat bubbleHeight = textHeight + 2.0 * t.paddingV;
		// Never let the caps collapse on one-line pills.
		CGFloat minHeight = 2.0 * t.cornerRadius;
		if (bubbleHeight < minHeight) {
			bubbleHeight = minHeight;
		}
		bubbleRect = NSMakeRect(0.0, top, bubbleWidth, bubbleHeight);
		textRect = NSMakeRect(t.paddingH, top + t.paddingV,
		                      textWidth + 4.0, textHeight);
		cellHeight = bubbleHeight;
	}

	// Horizontal placement: picture in the margin on the speaker's side,
	// balloon filling towards the opposite side.
	CGFloat avatarX = cell->_outgoing
	    ? width - inset - t.avatarSide
	    : inset;
	CGFloat bubbleX = cell->_outgoing
	    ? avatarX - t.avatarGap - bubbleRect.size.width
	    : inset + t.avatarSide + t.avatarGap;

	cell->_bubbleRect = NSMakeRect(bubbleX, top,
	                               bubbleRect.size.width, bubbleRect.size.height);
	if (!isTyping) {
		cell->_textRect = textRect;
		cell->_textRect.origin.x += bubbleX;
	}
	cell->_avatarRect = NSMakeRect(avatarX, top, t.avatarSide, t.avatarSide);

	[_cells addObject:cell];
	if (outCell != NULL) {
		*outCell = cell;
	}
	if (outHeight != NULL) {
		*outHeight = cellHeight;
	}
	[cell release];
}

#pragma mark Layout

// Rebuilds every cell rectangle. Content is laid out from the top and then
// pushed down so short transcripts hug the bottom edge, keeping the newest
// balloon next to the compose area like a conversation expects.
- (void)relayout
{
	NSRect bounds = [self bounds];
	CGFloat width = bounds.size.width;
	if (width <= 0.0) {
		return;
	}

	[_cells removeAllObjects];

	TLBubbleTheme *t = _theme;
	CGFloat topPad = t.messageGap * 0.5;
	CGFloat bottomPad = t.messageGap * 0.5;
	CGFloat cursor = topPad;

	NSUInteger count = [_messages count];
	for (NSUInteger i = 0; i < count; i++) {
		TLBubbleMessage *message = [_messages objectAtIndex:i];
		BOOL grouped = NO;
		if (i > 0) {
			TLBubbleMessage *previous = [_messages objectAtIndex:i - 1];
			grouped = [previous outgoing] == [message outgoing] &&
			    [[previous senderName] isEqualToString:[message senderName]];
		}
		cursor += grouped ? t.sameSpeakerGap : t.messageGap;

		CGFloat cellHeight = 0.0;
		[self appendCellWithMessage:message
		                typingState:NO
		                       atTop:cursor
		             transcriptWidth:width
		                      result:NULL
		                     height:&cellHeight];
		cursor += cellHeight;
	}

	if (_typingVisible) {
		// Typing state rides on a lightweight pseudo-message; only the
		// side, name and picture matter for its layout.
		TLBubbleMessage *typing = [[TLBubbleMessage alloc] init];
		typing.senderName = _typingSenderName;
		typing.outgoing = _typingOutgoing;
		cursor += t.messageGap;
		CGFloat cellHeight = 0.0;
		[self appendCellWithMessage:typing
		                typingState:YES
		                      atTop:cursor
		              transcriptWidth:width
		                       result:NULL
		                     height:&cellHeight];
		cursor += cellHeight;
		[typing release];
	}

	CGFloat contentHeight = cursor + bottomPad;

	// Anchor to the bottom while the transcript is shorter than the viewport.
	NSScrollView *scrollView = [self enclosingScrollView];
	CGFloat visibleHeight = scrollView != nil
	    ? [[scrollView contentView] bounds].size.height
	    : bounds.size.height;
	CGFloat newHeight = MAX(contentHeight, visibleHeight);
	CGFloat shift = newHeight - contentHeight;

	for (TLBubbleCell *cell in _cells) {
		cell->_bubbleRect.origin.y += shift;
		cell->_textRect.origin.y += shift;
		cell->_avatarRect.origin.y += shift;
	}

	_laidOutWidth = width;
	_laidOutHeight = newHeight;

	if (!NSEqualSizes(bounds.size, NSMakeSize(width, newHeight))) {
		[self setFrameSize:NSMakeSize(width, newHeight)];
	}
	[self setNeedsDisplay:YES];

	if (_pendingScrollToBottom) {
		_pendingScrollToBottom = NO;
		[self scrollToBottom];
	}
}

// Re-layout whenever the geometry may have drifted (window resizes happen
// behind our back through the autoresizing mask).
- (void)relayoutIfNeeded
{
	NSScrollView *scrollView = [self enclosingScrollView];
	CGFloat visibleHeight = scrollView != nil
	    ? [[scrollView contentView] bounds].size.height
	    : [self bounds].size.height;
	if ([self bounds].size.width != _laidOutWidth ||
	    MAX([self bounds].size.height, visibleHeight) != _laidOutHeight) {
		[self relayout];
	}
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
	[super resizeWithOldSuperviewSize:oldSize];
	[self relayoutIfNeeded];
}

#pragma mark Drawing

// Rounded rectangle assembled from OpenStep-era arc primitives; the tail is
// part of the same closed contour so translucent fills never show seams.
- (NSBezierPath *)balloonPathInRect:(NSRect)r
                       cornerRadius:(CGFloat)corner
                        withTail:(BOOL)withTail
                         tailLeft:(BOOL)tailLeft
{
	CGFloat radius = corner;
	radius = MIN(radius, r.size.width / 2.0);
	radius = MIN(radius, r.size.height / 2.0);

	CGFloat left = NSMinX(r);
	CGFloat right = NSMaxX(r);
	CGFloat top = NSMinY(r);
	CGFloat bottom = NSMaxY(r);

	NSBezierPath *path = [NSBezierPath bezierPath];
	[path moveToPoint:NSMakePoint(left + radius, top)];
	[path lineToPoint:NSMakePoint(right - radius, top)];

	[path appendBezierPathWithArcWithCenter:NSMakePoint(right - radius, top + radius)
	                                 radius:radius
	                              startAngle:270.0
	                                endAngle:360.0];
	[path lineToPoint:NSMakePoint(right, bottom - radius)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(right - radius, bottom - radius)
	                                 radius:radius
	                              startAngle:0.0
	                                endAngle:90.0];

	// Bottom edge, interrupted by the tail notch near the speaker side.
	if (withTail) {
		CGFloat tailLength = MIN(_theme.tailLength, r.size.height);
		CGFloat tailWidth = MIN(_theme.tailWidth, r.size.width / 3.0);
		if (tailLeft) {
			CGFloat xNear = left + radius + tailWidth;
			[path lineToPoint:NSMakePoint(xNear, bottom)];
			[path lineToPoint:NSMakePoint(left + radius + 1.0, bottom + tailLength)];
			[path lineToPoint:NSMakePoint(left + radius, bottom)];
		} else {
			CGFloat xNear = right - radius - tailWidth;
			[path lineToPoint:NSMakePoint(xNear, bottom)];
			[path lineToPoint:NSMakePoint(right - radius - 1.0, bottom + tailLength)];
			[path lineToPoint:NSMakePoint(right - radius, bottom)];
		}
	}

	[path lineToPoint:NSMakePoint(left + radius, bottom)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(left + radius, bottom - radius)
	                                 radius:radius
	                              startAngle:90.0
	                                endAngle:180.0];
	[path lineToPoint:NSMakePoint(left, top + radius)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(left + radius, top + radius)
	                                 radius:radius
	                              startAngle:180.0
	                                endAngle:270.0];
	[path closePath];

	return path;
}

// Cloud silhouette: two scallop bumps across the top plus the usual tail.
- (NSBezierPath *)cloudPathInRect:(NSRect)r tailLeft:(BOOL)tailLeft
{
	CGFloat capRadius = r.size.height / 2.0;
	CGFloat left = NSMinX(r);
	CGFloat right = NSMaxX(r);
	CGFloat top = NSMinY(r);
	CGFloat bottom = NSMaxY(r);
	NSBezierPath *path = [NSBezierPath bezierPath];
	CGFloat bumpRadius = (r.size.width - 2.0 * capRadius) / 4.0;
	CGFloat c1 = left + capRadius + bumpRadius;
	CGFloat c2 = left + capRadius + 3.0 * bumpRadius;
	[path moveToPoint:NSMakePoint(c1 - bumpRadius, top)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(c1, top)
	                                 radius:bumpRadius
	                              startAngle:180.0
	                                endAngle:360.0];
	[path lineToPoint:NSMakePoint(c2 - bumpRadius, top)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(c2, top)
	                                 radius:bumpRadius
	                              startAngle:180.0
	                                endAngle:360.0];
	[path lineToPoint:NSMakePoint(right - capRadius, top)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(right - capRadius, top + capRadius)
	                                 radius:capRadius
	                              startAngle:270.0
	                                endAngle:360.0];
	[path lineToPoint:NSMakePoint(right, bottom - capRadius)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(right - capRadius, bottom - capRadius)
	                                 radius:capRadius
	                              startAngle:0.0
	                                endAngle:90.0];
	CGFloat tailLength = MIN(_theme.tailLength, r.size.height);
	CGFloat tailWidth = MIN(_theme.tailWidth, r.size.width / 3.0);
	if (tailLeft) {
		[path lineToPoint:NSMakePoint(left + capRadius + tailWidth, bottom)];
		[path lineToPoint:NSMakePoint(left + capRadius + 1.0, bottom + tailLength)];
		[path lineToPoint:NSMakePoint(left + capRadius, bottom)];
	} else {
		[path lineToPoint:NSMakePoint(right - capRadius - tailWidth, bottom)];
		[path lineToPoint:NSMakePoint(right - capRadius - 1.0, bottom + tailLength)];
		[path lineToPoint:NSMakePoint(right - capRadius, bottom)];
	}
	[path lineToPoint:NSMakePoint(left + capRadius, bottom)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(left + capRadius, bottom - capRadius)
	                                 radius:capRadius
	                              startAngle:90.0
	                                endAngle:180.0];
	[path lineToPoint:NSMakePoint(left, top + capRadius)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(left + capRadius, top + capRadius)
	                                 radius:capRadius
	                              startAngle:180.0
	                                endAngle:270.0];
	[path closePath];
	return path;
}

// Vertical color ramp painted as thin strips inside the clipped balloon.
- (void)paintGradientInRect:(NSRect)r
                betweenTop:(NSColor *)topColor
                      mid:(NSColor *)midColor
                   bottom:(NSColor *)bottomColor
{
	const NSInteger steps = 48;
	CGFloat sliceHeight = ceil(r.size.height / (CGFloat)steps);
	for (NSInteger i = 0; i < steps; i++) {
		CGFloat t = (CGFloat)i / (CGFloat)(steps - 1);
		NSColor *color = t < 0.5
		    ? TLLerpColor(topColor, midColor, t * 2.0)
		    : TLLerpColor(midColor, bottomColor, (t - 0.5) * 2.0);
		NSRect strip = NSMakeRect(NSMinX(r),
		                          NSMinY(r) + (CGFloat)i * sliceHeight,
		                          r.size.width, sliceHeight);
		[color setFill];
		NSRectFillUsingOperation(strip, NSCompositeSourceOver);
	}
}

// Gel sheen fading out over the upper half of the balloon.
- (void)paintGlossInRect:(NSRect)r intensity:(CGFloat)intensity
{
	if (intensity <= 0.0) {
		return;
	}
	const NSInteger steps = 24;
	CGFloat span = r.size.height * 0.5;
	CGFloat sliceHeight = ceil(span / (CGFloat)steps);
	for (NSInteger i = 0; i < steps; i++) {
		CGFloat t = (CGFloat)i / (CGFloat)(steps - 1);
		CGFloat alpha = intensity * powf(1.0f - t, 1.7f);
		NSColor *color = [NSColor colorWithCalibratedWhite:1.0 alpha:alpha];
		NSRect strip = NSMakeRect(NSMinX(r),
		                          NSMinY(r) + (CGFloat)i * sliceHeight,
		                          r.size.width, sliceHeight);
		[color setFill];
		NSRectFillUsingOperation(strip, NSCompositeSourceOver);
	}
}

- (void)drawAvatarOfCell:(TLBubbleCell *)cell
{
	NSRect avatarRect = cell->_avatarRect;

	[[NSGraphicsContext currentContext] saveGraphicsState];
	NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:avatarRect];
	[circle addClip];

	NSImage *avatar = cell->_avatar;
	if (avatar != nil) {
		[avatar drawInRect:avatarRect
		           fromRect:NSZeroRect
		          operation:NSCompositeSourceOver
		           fraction:1.0];
	} else {
		NSColor *fill = TLPlaceholderColorForName(
		    cell->_senderName ?: @"?");
		[fill setFill];
		[circle fill];

		NSString *initial = @"?";
		if ([cell->_senderName length] > 0) {
			initial = [[cell->_senderName substringToIndex:1] uppercaseString];
		}
		NSFont *font = [NSFont boldSystemFontOfSize:15.0];
		NSDictionary *attrs = [NSDictionary dictionaryWithObject:font
		                                          forKey:NSFontAttributeName];
		NSSize textSize = [initial sizeWithAttributes:attrs];
		NSPoint origin = NSMakePoint(
		    NSMidX(avatarRect) - textSize.width / 2.0,
		    NSMidY(avatarRect) - textSize.height / 2.0);
		[[NSColor whiteColor] set];
		[initial drawAtPoint:origin withAttributes:attrs];
	}

	[[NSGraphicsContext currentContext] restoreGraphicsState];

	// Thin ring separates the picture from the transcript background.
	NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:
	    NSInsetRect(avatarRect, 0.5, 0.5)];
	[[NSColor colorWithCalibratedWhite:1.0 alpha:0.85] setStroke];
	[ring setLineWidth:1.0];
	[ring stroke];
}

- (void)drawBalloonOfCell:(TLBubbleCell *)cell
{
	NSRect bubbleRect = cell->_bubbleRect;
	NSColor *base = cell->_outgoing
	    ? [_theme outgoingColor]
	    : [_theme incomingColor];

	NSBezierPath *path = [self balloonPathInRect:bubbleRect
	                                cornerRadius:[_theme cornerRadius]
	                                    withTail:!cell->_isTyping
	                                       tailLeft:!cell->_outgoing];

	// Soft drop shadow beneath the whole silhouette.
	[[NSGraphicsContext currentContext] saveGraphicsState];
	NSShadow *shadow = [[NSShadow alloc] init];
	[shadow setShadowColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.30]];
	[shadow setShadowBlurRadius:3.0];
	[shadow setShadowOffset:NSMakeSize(0.0, 2.0)];
	[shadow set];
	[base setFill];
	[path fill];
	[[NSGraphicsContext currentContext] restoreGraphicsState];
	[shadow release];

	// Gradient, edge and gloss are all clipped to the silhouette.
	[[NSGraphicsContext currentContext] saveGraphicsState];
	[path addClip];
	[self paintGradientInRect:bubbleRect
	               betweenTop:TLBubbleLighten(base, 0.42)
	                          mid:base
	                       bottom:TLBubbleDarken(base, 0.14)];

	NSColor *edge = [TLBubbleDarken(base, 0.38) colorWithAlphaComponent:0.55];
	[edge setStroke];
	[path setLineWidth:1.0];
	[path stroke];

	[self paintGlossInRect:bubbleRect intensity:[_theme glossIntensity]];
	[[NSGraphicsContext currentContext] restoreGraphicsState];

	if (!cell->_isTyping) {
		NSAttributedString *string =
		    [self displayStringForMessage:cell->_message];
		[string drawInRect:cell->_textRect];
	}
}

- (void)drawTypingDotsOfCell:(TLBubbleCell *)cell
{
	NSRect bubbleRect = cell->_bubbleRect;
	CGFloat dotRadius = 1.8;
	CGFloat spacing = dotRadius * 4.0;
	CGFloat centerY = NSMidY(bubbleRect);
	CGFloat startX = NSMidX(bubbleRect) - spacing;
	NSColor *dotColor = [NSColor colorWithCalibratedWhite:0.35 alpha:0.55];
	[dotColor setFill];
	for (NSInteger i = 0; i < 3; i++) {
		NSRect dot = NSMakeRect(startX + (CGFloat)i * spacing - dotRadius,
		                        centerY - dotRadius,
		                        dotRadius * 2.0, dotRadius * 2.0);
		[[NSBezierPath bezierPathWithOvalInRect:dot] fill];
	}
}

- (void)drawRect:(NSRect)dirtyRect
{
	[self relayoutIfNeeded];

	[_theme.transcriptBackground setFill];
	NSRectFillUsingOperation([self bounds], NSCompositeSourceOver);

	for (TLBubbleCell *cell in _cells) {
		[[NSGraphicsContext currentContext] saveGraphicsState];
		[self drawAvatarOfCell:cell];
		[[NSGraphicsContext currentContext] restoreGraphicsState];
	}

	// Balloons are painted after all avatars so a long transcript never
	// lets a bubble overlap a neighbouring picture.
	for (TLBubbleCell *cell in _cells) {
		if (cell->_isTyping) {
			NSBezierPath *cloud = [self cloudPathInRect:cell->_bubbleRect
			                                   tailLeft:!cell->_outgoing];
			[[_theme typingColor] setFill];
			[cloud fill];
			[[NSColor colorWithCalibratedWhite:0.55 alpha:0.45] setStroke];
			[cloud setLineWidth:1.0];
			[cloud stroke];
			[self drawTypingDotsOfCell:cell];
		} else {
			[self drawBalloonOfCell:cell];
		}
	}
}

- (void)dealloc
{
	[_messages release];
	[_cells release];
	[_typingSenderName release];
	[_typingAvatar release];
	[_theme release];
	[_textStorage release];
	[_layoutManager release];
	[_textContainer release];
	[super dealloc];
}

@end
