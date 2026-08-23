/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class TLMessage;

// Renders TLMessage objects and raw IRC-formatted text into attributed
// strings for display in the native message view.
@interface TLMessageRenderer : NSObject

// Full rendered line for one message, including timestamp and nick prefix
// where applicable. Applies IRC formatting to the text.
+ (NSAttributedString *)attributedStringForMessage:(TLMessage *)message;

// Bubble-style variant: the balloon body only. Authorship is conveyed by the
// transcript layout (side, avatar), so regular messages carry a small
// timestamp and the formatted text but no "nick:" prefix; system lines keep
// their plain display text; actions render as "* nick did something".
+ (NSAttributedString *)attributedStringForBubbleBodyOfMessage:(TLMessage *)message;

// Applies IRC formatting (bold, italic, underline, strikethrough, colors,
// reverse, reset) to raw text. The input is not modified.
+ (NSAttributedString *)attributedStringForText:(NSString *)text;

// Rendered nick for the user list, including mode prefix if given.
+ (NSAttributedString *)attributedStringForNick:(NSString *)nick mode:(NSString *)mode;

// Deterministic, stable color derived from the nick.
+ (NSColor *)colorForNick:(NSString *)nick;

// The font used for message text.
+ (NSFont *)baseFont;

@end