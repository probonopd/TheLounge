/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

// Coverage for the bubble-style chat integration: preference storage, the
// bubble body renderer and the transcript view primitives the message view
// relies on (prepend for history loading, plain status lines). Headless.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"

#import "TLBubbleMessage.h"
#import "TLBubbleTranscriptView.h"
#import "TLMessage.h"
#import "TLUser.h"
#import "TLMessageRenderer.h"
#import "TLPreferencesController.h"
#import "TLLinkDetector.h"

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];

	// Fonts and the transcript's theme need the AppKit backend; NSMenu and
	// NSView work headless once the shared application exists.
	[NSApplication sharedApplication];

	// --- Preferences -----------------------------------------------------
	{
		BOOL original = TLPreferencesUseBubbles();

		TLPreferencesSetUseBubbles(!original);
		PASS(TLPreferencesUseBubbles() == !original,
			"preference setter roundtrips");

		__block BOOL notified = NO;
		id observer = [[NSNotificationCenter defaultCenter]
			addObserverForName:TLBubbleStyleDidChangeNotification
			                object:nil
			                 queue:nil
			            usingBlock:^(NSNotification *note) {
				notified = YES;
			}];
		TLPreferencesSetUseBubbles(original);
		PASS(notified, "flipping the style posts a change notification");
		[[NSNotificationCenter defaultCenter] removeObserver:observer];

		TLPreferencesSetUseBubbles(original);
		PASS(TLPreferencesUseBubbles() == original,
			"preference restored to original value");

		// --- Last-channel memory -----------------------------------------
		NSString *server = [NSString stringWithFormat:@"test://%d", getpid()];
		NSDictionary *saved = TLPreferencesLastChannelForServer(server);
		PASS(saved == nil, "no stored tab for an unknown server");

		TLPreferencesSetLastChannelId(42, @"#lounge", server);
		saved = TLPreferencesLastChannelForServer(server);
		PASS([saved[@"id"] integerValue] == 42 &&
		     [saved[@"name"] isEqual:@"#lounge"],
		    "stored tab keeps id and name");
		TLPreferencesSetLastChannelId(43, @"#other", server);
		saved = TLPreferencesLastChannelForServer(server);
		PASS([saved[@"id"] integerValue] == 43 &&
		     [saved[@"name"] isEqual:@"#other"],
		    "storing again replaces the previous tab");
		PASS(TLPreferencesLastChannelForServer(@"other://server") == nil,
		    "servers do not share their stored tab");
	}

	// --- Bubble messages -------------------------------------------------
	{
		TLBubbleMessage *m = [TLBubbleMessage messageWithText:@"hi"
		                                           senderName:@"alice"
		                                              outgoing:NO];
		PASS(m.plainLine == NO, "plainLine defaults to NO");
		m.plainLine = YES;
		PASS(m.plainLine == YES, "plainLine roundtrips");
	}

	// --- Transcript view -------------------------------------------------
	{
		TLBubbleTranscriptView *tv = [[TLBubbleTranscriptView alloc]
			initWithFrame:NSMakeRect(0, 0, 400, 300) theme:nil];
		PASS([tv messageCount] == 0, "new transcript is empty");

		TLBubbleMessage *a = [TLBubbleMessage messageWithText:@"first"
		                                           senderName:@"alice"
		                                              outgoing:NO];
		TLBubbleMessage *b = [TLBubbleMessage messageWithText:@"second"
		                                           senderName:@"bob"
		                                              outgoing:YES];
		[tv addMessages:[NSArray arrayWithObjects:a, b, nil]];
		PASS([tv messageCount] == 2, "addMessages appends");
		NSString *firstText = [[[tv messages] objectAtIndex:0] text];
		NSString *secondText = [[[tv messages] objectAtIndex:1] text];
		PASS([firstText isEqual:@"first"] && [secondText isEqual:@"second"],
			"append keeps conversation order");

		TLBubbleMessage *older = [TLBubbleMessage messageWithText:@"older"
		                                                senderName:@"carol"
		                                                   outgoing:NO];
		[tv prependMessages:[NSArray arrayWithObject:older]];
		PASS([tv messageCount] == 3, "prependMessages grows the transcript");
		PASS([[tv messages] objectAtIndex:0] == older,
			"prepend inserts at the top");

		[tv prependMessages:nil];
		[tv prependMessages:[NSArray array]];
		PASS([tv messageCount] == 3, "empty/nil prepend is a no-op");

		[tv clearMessages];
		PASS([tv messageCount] == 0, "clearMessages empties the transcript");
		[tv release];
	}

	// --- Renderer: bubble body ------------------------------------------
	{
		TLUser *sender = [[TLUser alloc] init];
		sender.nick = @"alice";

		NSDate *when = [NSDate date];
		NSString *clock = nil;
		{
			NSDateFormatter *f = [[NSDateFormatter alloc] init];
			[f setDateFormat:@"HH:mm"];
			clock = [f stringFromDate:when];
			[f release];
		}

		TLMessage *chat = [[TLMessage alloc] init];
		chat.type = TLMessageTypeMessage;
		chat.sender = sender;
		chat.timestamp = when;
		chat.text = @"hello world";
		NSAttributedString *body =
			[TLMessageRenderer attributedStringForBubbleBodyOfMessage:chat];
		PASS(body != nil && [[body string] rangeOfString:@"hello world"].location != NSNotFound,
			"bubble body contains the formatted text");
		PASS([[body string] hasPrefix:clock],
			"bubble body starts with the timestamp");
		PASS([[body string] rangeOfString:@"alice:"].location == NSNotFound,
			"bubble body omits the nick prefix (authorship comes from layout)");
		[chat release];

		TLMessage *action = [[TLMessage alloc] init];
		action.type = TLMessageTypeAction;
		action.sender = sender;
		action.timestamp = when;
		action.text = @"waves";
		body = [TLMessageRenderer attributedStringForBubbleBodyOfMessage:action];
		PASS([body length] > 0 &&
			[[body string] rangeOfString:@"* alice waves"].location != NSNotFound,
			"action renders as '* nick waves'");
		[action release];

		TLMessage *join = [[TLMessage alloc] init];
		join.type = TLMessageTypeJoin;
		join.sender = sender;
		join.timestamp = when;
		join.text = @"alice has joined";
		body = [TLMessageRenderer attributedStringForBubbleBodyOfMessage:join];
		PASS([body length] > 0 &&
			[[body string] rangeOfString:@"alice has joined"].location != NSNotFound,
			"system line keeps its display text");
		PASS([[body string] hasPrefix:clock] == NO,
			"system line carries no timestamp");
		[join release];

		body = [TLMessageRenderer attributedStringForBubbleBodyOfMessage:nil];
		PASS([body length] == 0, "nil message yields an empty body");

		[sender release];
	}

	// --- Links ------------------------------------------------------------
	{
		NSArray *ranges = [TLLinkDetector rangesOfLinksInString:
		    @"look at https://example.com/a?b=1 now"];
		PASS([ranges count] == 1, "one https link detected");
		NSRange r = [[ranges objectAtIndex:0] rangeValue];
		NSString *got = [@"look at https://example.com/a?b=1 now"
		    substringWithRange:r];
		PASS([got isEqualToString:@"https://example.com/a?b=1"],
			"https range is exact");

		ranges = [TLLinkDetector rangesOfLinksInString:
		    @"visit www.example.org/x, please"];
		r = [[ranges objectAtIndex:0] rangeValue];
		got = [@"visit www.example.org/x, please" substringWithRange:r];
		PASS([ranges count] == 1 && [got isEqualToString:@"www.example.org/x"],
			"bare www link drops trailing comma");

		ranges = [TLLinkDetector rangesOfLinksInString:
		    @"(see https://x.example/a) end"];
		r = [[ranges objectAtIndex:0] rangeValue];
		got = [@"(see https://x.example/a) end" substringWithRange:r];
		PASS([got isEqualToString:@"https://x.example/a"],
			"unbalanced closing paren is not part of the URL");

		ranges = [TLLinkDetector rangesOfLinksInString:
		    @"wiki: https://en.wikipedia.org/wiki/A_(b) ok"];
		r = [[ranges objectAtIndex:0] rangeValue];
		got = [@"wiki: https://en.wikipedia.org/wiki/A_(b) ok"
		    substringWithRange:r];
		PASS([got isEqualToString:@"https://en.wikipedia.org/wiki/A_(b)"],
			"balanced parens stay inside the URL");

		ranges = [TLLinkDetector rangesOfLinksInString:
		    @"join irc://irc.example.net/#room or nothing hello world"];
		PASS([ranges count] == 1, "irc scheme detected");

		ranges = [TLLinkDetector rangesOfLinksInString:@"no links here"];
		PASS([ranges count] == 0, "plain text has no links");

		NSString *wiki = @"https://github.com/gershwin-desktop/"
		    "gershwin-desktop/wiki/Changelog-2026%E2%80%9009#the-lounge";
		ranges = [TLLinkDetector rangesOfLinksInString:wiki];
		PASS([ranges count] == 1 &&
		     NSEqualRanges([[ranges objectAtIndex:0] rangeValue],
		                   NSMakeRange(0, [wiki length])),
		    "percent-encoded wiki URL parses to the very end");

		TLUser *sender = [[TLUser alloc] init];
		sender.nick = @"alice";
		TLMessage *chat = [[TLMessage alloc] init];
		chat.type = TLMessageTypeMessage;
		chat.sender = sender;
		chat.timestamp = [NSDate date];
		chat.text = @"try www.gershwin.io";
		NSAttributedString *body =
		    [TLMessageRenderer attributedStringForMessage:chat];
		NSString *plain = [body string];
		NSRange linkRange = [plain rangeOfString:@"www.gershwin.io"];
		id linkValue = [body attribute:NSLinkAttributeName
		                       atIndex:linkRange.location
		                 effectiveRange:NULL];
		PASS(linkValue != nil &&
		     [linkValue isKindOfClass:[NSURL class]],
		    "classic line carries an NSURL link attribute");

		NSAttributedString *bubbleBody =
		    [TLMessageRenderer attributedStringForBubbleBodyOfMessage:chat];
		linkValue = [bubbleBody attribute:NSLinkAttributeName
		                          atIndex:[[bubbleBody string]
		                              rangeOfString:@"www.gershwin.io"].location
		                    effectiveRange:NULL];
		PASS(linkValue != nil,
		    "bubble body carries the link attribute too");
		[chat release];
		[sender release];

		// Hit-testing: click the middle of the link's own line fragment.
		NSRange bubbleLinkRange =
		    [[bubbleBody string] rangeOfString:@"www.gershwin.io"];
		NSTextStorage *storage = [[NSTextStorage alloc]
		    initWithAttributedString:bubbleBody];
		NSLayoutManager *lm = [[NSLayoutManager alloc] init];
		[storage addLayoutManager:lm];
		NSTextContainer *tc = [[NSTextContainer alloc]
		    initWithContainerSize:NSMakeSize(300.0, FLT_MAX)];
		[tc setLineFragmentPadding:0.0];
		[lm addTextContainer:tc];
		[lm ensureLayoutForTextContainer:tc];
		NSRange glyphRange = [lm glyphRangeForCharacterRange:bubbleLinkRange
		                             actualCharacterRange:NULL];
		NSRect glyphRect = [lm boundingRectForGlyphRange:glyphRange
		                                 inTextContainer:tc];
		NSPoint inside = NSMakePoint(NSMidX(glyphRect), NSMidY(glyphRect));
		NSURL *hit = [TLLinkDetector linkAtPoint:inside
		                                  inString:bubbleBody width:300.0];
		PASS(hit != nil && [hit isKindOfClass:[NSURL class]],
		    "linkAtPoint finds a URL on the link glyphs");
		NSPoint below = NSMakePoint(10.0, NSMaxY(glyphRect) + 40.0);
		hit = [TLLinkDetector linkAtPoint:below inString:bubbleBody width:300.0];
		PASS(hit == nil, "clicking blank space yields no link");
		[tc release];
		[lm release];
		[storage release];
	}

	[arp release];
	return 0;
}
