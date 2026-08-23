/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

// All visual tunables of the bubble renderer live here so that layout and
// drawing code stay independent of any particular palette. Instances are
// plain value-like objects; the transcript view copies on assignment.
@interface TLBubbleTheme : NSObject <NSCopying>

// Bubble silhouette
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat tailLength;
@property (nonatomic, assign) CGFloat tailWidth;

// Text insets inside the bubble
@property (nonatomic, assign) CGFloat paddingH;
@property (nonatomic, assign) CGFloat paddingV;

// Margin reserved for the speaker picture
@property (nonatomic, assign) CGFloat avatarSide;
@property (nonatomic, assign) CGFloat avatarGap;

// Vertical rhythm
@property (nonatomic, assign) CGFloat messageGap;
@property (nonatomic, assign) CGFloat sameSpeakerGap;

// Fraction of the transcript width a bubble may occupy at most
@property (nonatomic, assign) CGFloat maxBubbleWidthRatio;

// Gloss strength of the top sheen (0 = matte)
@property (nonatomic, assign) CGFloat glossIntensity;

@property (nonatomic, strong) NSFont *messageFont;

// Outgoing = warm gold, incoming = cool blue, typing = pale neutral.
@property (nonatomic, strong) NSColor *outgoingColor;
@property (nonatomic, strong) NSColor *incomingColor;
@property (nonatomic, strong) NSColor *typingColor;
@property (nonatomic, strong) NSColor *outgoingTextColor;
@property (nonatomic, strong) NSColor *incomingTextColor;
@property (nonatomic, strong) NSColor *transcriptBackground;

+ (instancetype)defaultTheme;

@end

// Derive gradient stops, borders and shadows from a base color.
// amount > 0 blends toward white, amount < 0 toward black.
NSColor *TLBubbleLighten(NSColor *color, CGFloat amount);
NSColor *TLBubbleDarken(NSColor *color, CGFloat amount);

// Lifts a user's nick color towards white so a balloon can carry the
// speaker's hue while staying pastel enough for dark body text.
NSColor *TLBubbleTintFromUserColor(NSColor *userColor);
