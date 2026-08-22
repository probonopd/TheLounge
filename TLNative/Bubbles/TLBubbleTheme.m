/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLBubbleTheme.h"

// amount > 0 blends toward white, amount < 0 toward black. Used to derive
// gradient stops, borders and shadows from a single base color per side.
static NSColor *TLBlendColor(NSColor *color, CGFloat amount)
{
	NSColor *c = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	CGFloat r = [c redComponent];
	CGFloat g = [c greenComponent];
	CGFloat b = [c blueComponent];
	CGFloat a = [c alphaComponent];

	if (amount >= 0.0) {
		return [NSColor colorWithCalibratedRed:r + (1.0 - r) * amount
		                                 green:g + (1.0 - g) * amount
		                                  blue:b + (1.0 - b) * amount
		                                 alpha:a];
	}

	CGFloat k = 1.0 + amount;
	return [NSColor colorWithCalibratedRed:r * k
	                                 green:g * k
	                                  blue:b * k
	                                 alpha:a];
}

@implementation TLBubbleTheme

+ (instancetype)defaultTheme
{
	static TLBubbleTheme *theme = nil;
	if (theme == nil) {
		theme = [[TLBubbleTheme alloc] init];
	}
	return theme;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_cornerRadius = 11.0;
		_tailLength = 7.0;
		_tailWidth = 10.0;

		_paddingH = 10.0;
		_paddingV = 6.0;

		_avatarSide = 36.0;
		_avatarGap = 8.0;

		_messageGap = 9.0;
		_sameSpeakerGap = 4.0;

		_maxBubbleWidthRatio = 0.65;
		_glossIntensity = 0.45;

		_messageFont = [[NSFont systemFontOfSize:13.0] retain];

		_outgoingColor = [[NSColor colorWithCalibratedRed:0.98 green:0.77
		                                             blue:0.18 alpha:1.0] retain];
		_incomingColor = [[NSColor colorWithCalibratedRed:0.62 green:0.69
		                                             blue:0.82 alpha:1.0] retain];
		_typingColor = [[NSColor colorWithCalibratedWhite:0.88 alpha:0.90] retain];

		_outgoingTextColor = [[NSColor colorWithCalibratedRed:0.28 green:0.16
		                                                 blue:0.02 alpha:1.0] retain];
		_incomingTextColor = [[NSColor colorWithCalibratedRed:0.10 green:0.14
		                                                 blue:0.24 alpha:1.0] retain];

		_transcriptBackground = [[NSColor colorWithCalibratedWhite:0.96 alpha:1.0] retain];
	}
	return self;
}

- (void)setMessageFont:(NSFont *)font
{
	if (_messageFont != font) {
		[_messageFont release];
		_messageFont = [font copy];
	}
}

- (void)setOutgoingColor:(NSColor *)color
{
	if (_outgoingColor != color) {
		[_outgoingColor release];
		_outgoingColor = [color retain];
	}
}

- (void)setIncomingColor:(NSColor *)color
{
	if (_incomingColor != color) {
		[_incomingColor release];
		_incomingColor = [color retain];
	}
}

- (void)setTypingColor:(NSColor *)color
{
	if (_typingColor != color) {
		[_typingColor release];
		_typingColor = [color retain];
	}
}

- (void)setOutgoingTextColor:(NSColor *)color
{
	if (_outgoingTextColor != color) {
		[_outgoingTextColor release];
		_outgoingTextColor = [color retain];
	}
}

- (void)setIncomingTextColor:(NSColor *)color
{
	if (_incomingTextColor != color) {
		[_incomingTextColor release];
		_incomingTextColor = [color retain];
	}
}

- (void)setTranscriptBackground:(NSColor *)color
{
	if (_transcriptBackground != color) {
		[_transcriptBackground release];
		_transcriptBackground = [color retain];
	}
}

- (id)copyWithZone:(NSZone *)zone
{
	TLBubbleTheme *copy = [[[self class] allocWithZone:zone] init];
	copy.cornerRadius = _cornerRadius;
	copy.tailLength = _tailLength;
	copy.tailWidth = _tailWidth;
	copy.paddingH = _paddingH;
	copy.paddingV = _paddingV;
	copy.avatarSide = _avatarSide;
	copy.avatarGap = _avatarGap;
	copy.messageGap = _messageGap;
	copy.sameSpeakerGap = _sameSpeakerGap;
	copy.maxBubbleWidthRatio = _maxBubbleWidthRatio;
	copy.glossIntensity = _glossIntensity;
	copy.messageFont = _messageFont;
	copy.outgoingColor = _outgoingColor;
	copy.incomingColor = _incomingColor;
	copy.typingColor = _typingColor;
	copy.outgoingTextColor = _outgoingTextColor;
	copy.incomingTextColor = _incomingTextColor;
	copy.transcriptBackground = _transcriptBackground;
	return copy;
}

- (void)dealloc
{
	[_messageFont release];
	[_outgoingColor release];
	[_incomingColor release];
	[_typingColor release];
	[_outgoingTextColor release];
	[_incomingTextColor release];
	[_transcriptBackground release];
	[super dealloc];
}

@end

NSColor *TLBubbleLighten(NSColor *color, CGFloat amount)
{
	return TLBlendColor(color, amount);
}

NSColor *TLBubbleDarken(NSColor *color, CGFloat amount)
{
	return TLBlendColor(color, -amount);
}
