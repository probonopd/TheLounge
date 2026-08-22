/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLMessageRenderer.h"
#import "TLMessage.h"

static NSColor *TLDefaultTextColor(void)
{
	// The message surface follows the light system theme, so body text
	// uses the standard label color instead of a fixed near-white.
	return [NSColor controlTextColor];
}

// Dark theme approximation used as the foreground when reverse video has no
// explicit color pair to swap into.
static NSColor *TLReverseForegroundColor(void)
{
	return [NSColor colorWithCalibratedWhite:0.13 alpha:1.0];
}

static NSFont *TLFontFor(BOOL bold, BOOL italic)
{
	NSFont *font = bold ? [NSFont boldSystemFontOfSize:12.0] : [NSFont systemFontOfSize:12.0];
	if (italic) {
		font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask];
	}
	return font;
}

static NSColor *TLColorFromRGB(NSInteger r, NSInteger g, NSInteger b)
{
	return [NSColor colorWithCalibratedRed:(r / 255.0) green:(g / 255.0) blue:(b / 255.0) alpha:1.0];
}

// Standard mIRC 16 color palette shared with the The Lounge web client.
static NSColor *TLColorForCode(NSInteger code)
{
	static NSColor *table[16] = {0};
	// Retained once so the palette outlives the autorelease pool.
	if (!table[0]) {
		table[0] = [TLColorFromRGB(255, 255, 255) retain];
		table[1] = [TLColorFromRGB(0, 0, 0) retain];
		table[2] = [TLColorFromRGB(0, 0, 128) retain];
		table[3] = [TLColorFromRGB(0, 128, 0) retain];
		table[4] = [TLColorFromRGB(128, 0, 0) retain];
		table[5] = [TLColorFromRGB(128, 0, 128) retain];
		table[6] = [TLColorFromRGB(255, 128, 0) retain];
		table[7] = [TLColorFromRGB(128, 128, 0) retain];
		table[8] = [TLColorFromRGB(255, 255, 0) retain];
		table[9] = [TLColorFromRGB(0, 255, 0) retain];
		table[10] = [TLColorFromRGB(0, 128, 128) retain];
		table[11] = [TLColorFromRGB(0, 255, 255) retain];
		table[12] = [TLColorFromRGB(0, 0, 255) retain];
		table[13] = [TLColorFromRGB(255, 0, 255) retain];
		table[14] = [TLColorFromRGB(128, 128, 128) retain];
		table[15] = [TLColorFromRGB(192, 192, 192) retain];
	}
	if (code < 0 || code > 15) {
		return TLDefaultTextColor();
	}
	return table[code];
}

// Bright material palette that stays readable on a dark background.
static NSArray *TLNickColorPalette(void)
{
	static NSArray *palette;
	if (!palette) {
		NSColor *colors[] = {
			TLColorFromRGB(229, 115, 115),
			TLColorFromRGB(240, 98, 146),
			TLColorFromRGB(186, 104, 200),
			TLColorFromRGB(149, 117, 205),
			TLColorFromRGB(100, 181, 246),
			TLColorFromRGB(77, 208, 225),
			TLColorFromRGB(129, 199, 132),
			TLColorFromRGB(174, 213, 129),
			TLColorFromRGB(255, 183, 77),
			TLColorFromRGB(255, 138, 101),
		};
		palette = [[NSArray alloc] initWithObjects:colors count:10];
	}
	return palette;
}

static NSUInteger TLNickHash(NSString *nick)
{
	NSString *lower = [nick lowercaseString];
	NSUInteger h = 0;
	for (NSUInteger i = 0; i < [lower length]; i++) {
		h = h * 31 + [lower characterAtIndex:i];
	}
	return h;
}

static NSInteger TLDigitValue(unichar c)
{
	if (c >= '0' && c <= '9') {
		return c - '0';
	}
	if (c >= 'a' && c <= 'f') {
		return c - 'a' + 10;
	}
	if (c >= 'A' && c <= 'F') {
		return c - 'A' + 10;
	}
	return -1;
}

// Consumes up to two decimal digits at pos, storing the value in codeOut.
// Returns the new position; leaves codeOut at -1 when no digit is present.
static NSUInteger TLReadColorCode(NSString *text, NSUInteger pos, NSUInteger len, NSInteger *codeOut)
{
	if (pos >= len) {
		return pos;
	}
	NSInteger first = TLDigitValue([text characterAtIndex:pos]);
	if (first < 0 || first > 9) {
		return pos;
	}
	pos++;
	NSInteger value = first;
	if (pos < len) {
		NSInteger second = TLDigitValue([text characterAtIndex:pos]);
		if (second >= 0 && second <= 9) {
			value = first * 10 + second;
			pos++;
		}
	}
	*codeOut = value;
	return pos;
}

static NSUInteger TLParseMIRCColor(NSString *text, NSUInteger i, NSColor **fgOut, NSColor **bgOut)
{
	NSUInteger len = [text length];
	NSUInteger p = i + 1;
	NSInteger fgCode = -1;
	NSInteger bgCode = -1;
	p = TLReadColorCode(text, p, len, &fgCode);
	if (p < len && [text characterAtIndex:p] == ',') {
		p++;
		NSInteger bg;
		p = TLReadColorCode(text, p, len, &bg);
		if (bg != -1) {
			bgCode = bg;
		}
	}
	// Codes above 15 are malformed and fall back to the default color.
	*fgOut = (fgCode != -1 && fgCode <= 15) ? TLColorForCode(fgCode) : TLDefaultTextColor();
	*bgOut = (bgCode != -1 && bgCode <= 15) ? TLColorForCode(bgCode) : nil;
	return p;
}

static NSUInteger TLParseHexColor(NSString *text, NSUInteger i, NSColor **fgOut, NSColor **bgOut)
{
	NSUInteger len = [text length];
	NSUInteger p = i + 1;
	NSColor *fg = TLDefaultTextColor();
	NSColor *bg = nil;
	// A malformed hex sequence resets colors and leaves the digits as text.
	if (p + 5 < len) {
		NSInteger rgb[6];
		BOOL ok = YES;
		for (int k = 0; k < 6; k++) {
			NSInteger v = TLDigitValue([text characterAtIndex:p + k]);
			if (v < 0) {
				ok = NO;
				break;
			}
			rgb[k] = v;
		}
		if (ok) {
			fg = TLColorFromRGB(rgb[0] * 16 + rgb[1], rgb[2] * 16 + rgb[3], rgb[4] * 16 + rgb[5]);
			p += 6;
			if (p < len && [text characterAtIndex:p] == ',') {
				p++;
				if (p + 5 < len) {
					NSInteger rgb2[6];
					BOOL ok2 = YES;
					for (int k = 0; k < 6; k++) {
						NSInteger v = TLDigitValue([text characterAtIndex:p + k]);
						if (v < 0) {
							ok2 = NO;
							break;
						}
						rgb2[k] = v;
					}
					if (ok2) {
						bg = TLColorFromRGB(rgb2[0] * 16 + rgb2[1], rgb2[2] * 16 + rgb2[3], rgb2[4] * 16 + rgb2[5]);
						p += 6;
					}
				}
			}
		}
	}
	*fgOut = fg;
	*bgOut = bg;
	return p;
}

static NSString *TLTimeString(NSDate *date)
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"HH:mm"];
	NSString *result = [formatter stringFromDate:date];
	[formatter release];
	return result;
}

typedef struct {
	BOOL bold;
	BOOL italic;
	BOOL underline;
	BOOL strike;
	BOOL reverse;
	NSColor *fg;
	NSColor *bg;
} TLFormatState;

static NSDictionary *TLAttributesForState(TLFormatState state, NSColor *defaultFG)
{
	NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
	[attrs setObject:TLFontFor(state.bold, state.italic) forKey:NSFontAttributeName];
	NSColor *effFG = state.fg ? state.fg : defaultFG;
	NSColor *effBG = state.bg;
	if (state.reverse) {
		// Reverse video swaps the current pair; without explicit colors it
		// becomes a light highlight with dark text.
		NSColor *swap = effFG;
		effFG = effBG ? effBG : TLReverseForegroundColor();
		effBG = swap;
	}
	[attrs setObject:effFG forKey:NSForegroundColorAttributeName];
	if (effBG) {
		[attrs setObject:effBG forKey:NSBackgroundColorAttributeName];
	}
	if (state.underline) {
		[attrs setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle] forKey:NSUnderlineStyleAttributeName];
	}
	if (state.strike) {
		[attrs setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle] forKey:NSStrikethroughStyleAttributeName];
	}
	return attrs;
}

static void TLFlushChunk(NSMutableAttributedString *result, NSMutableString *chunk,
	TLFormatState state, NSColor *defaultFG)
{
	if ([chunk length] == 0) {
		return;
	}
	NSDictionary *attrs = TLAttributesForState(state, defaultFG);
	NSAttributedString *segment = [[NSAttributedString alloc] initWithString:chunk attributes:attrs];
	[result appendAttributedString:segment];
	[segment release];
	[chunk setString:@""];
}

static NSAttributedString *TLParseFormattedText(NSString *text, BOOL initialItalic, NSColor *defaultFG)
{
	if (!text) {
		text = @"";
	}
	if (!defaultFG) {
		defaultFG = TLDefaultTextColor();
	}
	NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
	NSMutableString *chunk = [[NSMutableString alloc] initWithCapacity:[text length] + 16];
	TLFormatState state;
	state.bold = NO;
	state.italic = initialItalic;
	state.underline = NO;
	state.strike = NO;
	state.reverse = NO;
	state.fg = nil;
	state.bg = nil;
	NSUInteger i = 0;
	NSUInteger len = [text length];
	while (i < len) {
		unichar c = [text characterAtIndex:i];
		switch (c) {
			case 0x02:
				TLFlushChunk(result, chunk, state, defaultFG);
				state.bold = YES;
				i++;
				break;
			case 0x1D:
				TLFlushChunk(result, chunk, state, defaultFG);
				state.italic = YES;
				i++;
				break;
			case 0x1F:
				TLFlushChunk(result, chunk, state, defaultFG);
				state.underline = YES;
				i++;
				break;
			case 0x1E:
				TLFlushChunk(result, chunk, state, defaultFG);
				state.strike = YES;
				i++;
				break;
			case 0x16:
				TLFlushChunk(result, chunk, state, defaultFG);
				state.reverse = YES;
				i++;
				break;
			case 0x0F:
				TLFlushChunk(result, chunk, state, defaultFG);
				state.bold = NO;
				state.italic = initialItalic;
				state.underline = NO;
				state.strike = NO;
				state.reverse = NO;
				state.fg = nil;
				state.bg = nil;
				i++;
				break;
			case 0x03:
				TLFlushChunk(result, chunk, state, defaultFG);
				i = TLParseMIRCColor(text, i, &state.fg, &state.bg);
				break;
			case 0x04:
				TLFlushChunk(result, chunk, state, defaultFG);
				i = TLParseHexColor(text, i, &state.fg, &state.bg);
				break;
			default:
				[chunk appendFormat:@"%C", c];
				i++;
				break;
		}
	}
	TLFlushChunk(result, chunk, state, defaultFG);
	[chunk release];
	return [result autorelease];
}

@implementation TLMessageRenderer

+ (NSFont *)baseFont
{
	return [NSFont systemFontOfSize:12.0];
}

+ (NSColor *)colorForNick:(NSString *)nick
{
	if (!nick || [nick length] == 0) {
		return TLDefaultTextColor();
	}
	return [TLNickColorPalette() objectAtIndex:(TLNickHash(nick) % [TLNickColorPalette() count])];
}

+ (NSAttributedString *)attributedStringForNick:(NSString *)nick mode:(NSString *)mode
{
	if (!nick) {
		nick = @"";
	}
	NSString *prefix = mode ? mode : @"";
	NSString *full = ([prefix length] > 0) ? [NSString stringWithFormat:@"%@%@", prefix, nick] : nick;
	NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
		[self baseFont], NSFontAttributeName,
		[self colorForNick:nick], NSForegroundColorAttributeName,
		nil];
	return [[[NSAttributedString alloc] initWithString:full attributes:attrs] autorelease];
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
{
	return TLParseFormattedText(text, NO, TLDefaultTextColor());
}

+ (NSAttributedString *)attributedStringForMessage:(TLMessage *)message
{
	if (!message) {
		return [[[NSAttributedString alloc] initWithString:@""] autorelease];
	}
	if ([message isSystemMessage]) {
		NSString *text = [message displayText];
		if (!text || [text length] == 0) {
			text = [message text];
		}
		if (!text) {
			text = @"";
		}
		NSColor *gray = [NSColor colorWithCalibratedWhite:0.30 alpha:1.0];
		return TLParseFormattedText(text, NO, gray);
	}
	if ([message isAction]) {
		NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
		NSDictionary *italicAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
			TLFontFor(NO, YES), NSFontAttributeName,
			TLDefaultTextColor(), NSForegroundColorAttributeName,
			nil];
		[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@"* " attributes:italicAttrs] autorelease]];
		if (message.sender) {
			NSString *nick = message.sender.nick ? message.sender.nick : @"";
			NSDictionary *nickAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
				TLFontFor(NO, YES), NSFontAttributeName,
				[self colorForNick:nick], NSForegroundColorAttributeName,
				nil];
			[line appendAttributedString:[[[NSAttributedString alloc] initWithString:nick attributes:nickAttrs] autorelease]];
			[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@" " attributes:italicAttrs] autorelease]];
		}
		NSString *text = [message text];
		if (text && [text length] > 0) {
			[line appendAttributedString:TLParseFormattedText(text, YES, TLDefaultTextColor())];
		}
		return [line autorelease];
	}
	NSDate *timestamp = message.timestamp ? message.timestamp : [NSDate date];
	NSString *nick = message.sender.nick ? message.sender.nick : @"";
	NSDictionary *defAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
		[self baseFont], NSFontAttributeName,
		TLDefaultTextColor(), NSForegroundColorAttributeName,
		nil];
	NSDictionary *nickAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
		[self baseFont], NSFontAttributeName,
		[self colorForNick:nick], NSForegroundColorAttributeName,
		nil];
	NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
	[line appendAttributedString:[[[NSAttributedString alloc] initWithString:TLTimeString(timestamp) attributes:defAttrs] autorelease]];
	[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@"  " attributes:defAttrs] autorelease]];
	[line appendAttributedString:[[[NSAttributedString alloc] initWithString:nick attributes:nickAttrs] autorelease]];
	[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@": " attributes:defAttrs] autorelease]];
	NSString *display = [message displayText];
	if (!display) {
		display = @"";
	}
	[line appendAttributedString:TLParseFormattedText(display, NO, TLDefaultTextColor())];
	return [line autorelease];
}

@end