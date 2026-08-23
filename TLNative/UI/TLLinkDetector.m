/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLLinkDetector.h"

// Chars that may appear inside a URL: RFC 3986 set plus brackets and
// parentheses, so wiki-style URLs with parentheses stay intact.
static NSCharacterSet *TLURLCharSet(void)
{
	static NSCharacterSet *set = nil;
	if (set == nil) {
		NSMutableCharacterSet *m =
		    [NSMutableCharacterSet characterSetWithCharactersInString:
		 @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#@!$&*+=%"];
		[m addCharactersInString:@"(),;[]"];
		set = m;
	}
	return set;
}

// Punctuation that usually ends a sentence rather than the URL itself.
static BOOL TLIsTrailingPunctuation(unichar c)
{
	switch (c) {
		case (unichar)46: /* . */
		case (unichar)44: /* , */
		case (unichar)59: /* ; */
		case (unichar)58: /* : */
		case (unichar)33: /* ! */
		case (unichar)63: /* ? */
		case (unichar)34: /* double quote */
		case (unichar)39: /* apostrophe */
			return YES;
		default:
			return NO;
	}
}

@implementation TLLinkDetector

+ (NSArray<NSValue *> *)rangesOfLinksInString:(NSString *)s
{
	NSMutableArray *ranges = [NSMutableArray array];
	NSUInteger len = [s length];

	for (NSUInteger i = 0; i < len;) {
		BOOL matched = NO;
		NSUInteger start = i;

		unichar c = [s characterAtIndex:i];
		if ((c == (unichar)104 /* h */) || (c == (unichar)72 /* H */)) {
			NSString *scheme =
			    [s substringWithRange:NSMakeRange(i, MIN((NSUInteger)8, len - i))];
			matched = ([scheme hasPrefix:@"http://"] ||
			          [scheme hasPrefix:@"https://"]);
		} else if ((c == (unichar)105 /* i */) ||
		           (c == (unichar)73 /* I */)) {
			NSString *scheme =
			    [s substringWithRange:NSMakeRange(i, MIN((NSUInteger)6, len - i))];
			matched = ([scheme hasPrefix:@"irc://"] ||
			          [scheme hasPrefix:@"ircs://"]);
		} else if ((c == (unichar)119 /* w */) ||
		           (c == (unichar)87 /* W */)) {
			NSString *prefix4 =
			    [s substringWithRange:NSMakeRange(i, MIN((NSUInteger)4, len - i))];
			BOOL atWordBoundary =
			    (i == 0 ||
			     ![[NSCharacterSet alphanumericCharacterSet]
			               characterIsMember:[s characterAtIndex:i - 1]]);
			matched = atWordBoundary && [prefix4 isEqualToString:@"www."];
		}

		i++;
		if (!matched) {
			continue;
		}

		NSUInteger end = start;
		while ((end < len) &&
		       [TLURLCharSet() characterIsMember:[s characterAtIndex:end]]) {
			end++;
		}
		// Trim trailing sentence punctuation.
		while ((end > start) &&
		       TLIsTrailingPunctuation([s characterAtIndex:(end - 1)])) {
			end--;
		}
		// A closing bracket belongs to the URL only when its opener
		// also sits inside the range (wiki-style parenthesized URLs).
		while (end > start) {
			unichar last = [s characterAtIndex:(end - 1)];
			unichar opener = (last == (unichar)41 /* ) */)
			                     ? (unichar)40 /* ( */
			                     : ((last == (unichar)93 /* ] */)
			                         ? (unichar)91 /* [ */
			                         : (unichar)0);
			if (opener == (unichar)0) {
				break;
			}
			NSString *needle =
			    [NSString stringWithFormat:@"%C", opener];
			NSRange soFar = NSMakeRange(start, end - start);
			if ([s rangeOfString:needle
			        options:NSLiteralSearch
			        range:soFar].location != NSNotFound) {
				break;
			}
			end--;
		}

		if (end > start) {
			[ranges addObject:
			    [NSValue valueWithRange:NSMakeRange(start, end - start)]];
		}
	}
	return ranges;
}

+ (NSAttributedString *)attributedStringWithLinksApplied:
    (NSAttributedString *)inString
{
	NSArray<NSValue *> *ranges =
	    [self rangesOfLinksInString:[inString string]];
	NSMutableAttributedString *result =
	    [[NSMutableAttributedString alloc]
	        initWithAttributedString:inString];

	[ranges enumerateObjectsUsingBlock:^(NSValue *value,
	                                     NSUInteger idx,
	                                     BOOL *stop) {
		NSRange r = [value rangeValue];
		NSString *raw = [[inString string] substringWithRange:r];
		NSURL *url = [NSURL URLWithString:raw];
		if (url == nil) {
			return;
		}
		[result addAttribute:NSLinkAttributeName
		                value:url
		                range:r];
		// Underline unstyled links for affordance; keep IRC colors.
		if ([result attribute:NSUnderlineStyleAttributeName
		                atIndex:r.location
		          effectiveRange:NULL] == nil) {
			[result addAttribute:NSUnderlineStyleAttributeName
			    value:[NSNumber numberWithInteger:
			                NSUnderlineStyleSingle]
			    range:r];
		}
	}];
	return [result autorelease];
}

+ (NSURL *)linkAtPoint:(NSPoint)point
              inString:(NSAttributedString *)string
                width:(CGFloat)width
{
	NSTextStorage *storage =
	    [[NSTextStorage alloc] initWithAttributedString:string];
	NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
	[storage addLayoutManager:layoutManager];
	NSTextContainer *container =
	    [[NSTextContainer alloc]
	        initWithContainerSize:NSMakeSize(width, FLT_MAX)];
	[container setLineFragmentPadding:0.0];
	[layoutManager addTextContainer:container];

	// GNUstep text system: point to glyph, glyph to character.
	NSUInteger glyphIndex = [layoutManager
	    glyphIndexForPoint:point
	          inTextContainer:container
	    fractionOfDistanceThroughGlyph:NULL];
	NSURL *link = nil;
	if (glyphIndex != NSNotFound) {
		NSUInteger charIndex = [layoutManager
		    characterIndexForGlyphAtIndex:glyphIndex];
		if (charIndex != NSNotFound && charIndex < [string length]) {
			// The point must sit on the line fragment itself; clicks on
			// blank space below or beside the text never open links.
			NSRect lineRect = [layoutManager
			    lineFragmentRectForGlyphAtIndex:glyphIndex
			                       effectiveRange:NULL];
			if (NSPointInRect(point, lineRect)) {
				link = [[storage attribute:NSLinkAttributeName
				                   atIndex:charIndex
				             effectiveRange:NULL] retain];
			}
		}
	}
	[storage release];
	[layoutManager release];
	[container release];
	return [link autorelease];
}

@end
