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
#import "TLBubbleTheme.h"
#import "TLMessage.h"
#import "TLUser.h"
#import "TLMessageRenderer.h"
#import "TLPreferencesController.h"
#import "TLLinkDetector.h"
#import "TLUserListView.h"
#import "TLMessageView.h"
#import "TLChannel.h"

// The silhouette builder is private to the view; declaring the category
// here just lets the test call it.
@interface TLBubbleTranscriptView (TailTesting)
- (NSBezierPath *)balloonPathInRect:(NSRect)r cornerRadius:(CGFloat)corner
                           withTail:(BOOL)withTail tailLeft:(BOOL)tailLeft;
@end

// The sender-forwarding hop inside the message view is likewise private.
@interface TLMessageView (SenderTesting)
- (void)transcriptViewDidSelectSender:(NSString *)senderName;
@end

static NSInteger g_lastSeenRow = -99;
static NSString *g_lastSeenNick = nil;

@interface RowRecorder : NSObject <TLUserListViewDelegate, TLMessageViewDelegate>
@end

@implementation RowRecorder
- (void)userListView:(TLUserListView *)view didSelectRow:(NSInteger)row
{
	g_lastSeenRow = row;
}
- (void)messageViewDidScrollToTop:(TLMessageView *)messageView {}
- (void)messageView:(TLMessageView *)messageView didSelectSenderNick:(NSString *)nick
{
	[g_lastSeenNick release];
	g_lastSeenNick = [nick copy];
}
@end

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

		NSColor *user = [NSColor colorWithCalibratedRed:0.9
		                                          green:0.45
		                                           blue:0.45
		                                          alpha:1.0];
		m.senderColor = user;
		PASS([m.senderColor isEqual:user], "senderColor roundtrips");

		// The balloon fill must be a lifted version of the nick color so
		// bubbles stay pastel while still reading as "that user's" hue.
		NSColor *tint = TLBubbleTintFromUserColor(user);
		CGFloat br = 0.0;
		CGFloat bt = 0.0;
		[tint getHue:NULL saturation:NULL brightness:&br alpha:NULL];
		[user getHue:NULL saturation:NULL brightness:&bt alpha:NULL];
		PASS(br > bt, "bubble tint is lighter than the user color");
		CGFloat th = 0.0;
		CGFloat uh = 0.0;
		[tint getHue:&th saturation:NULL brightness:NULL alpha:NULL];
		[user getHue:&uh saturation:NULL brightness:NULL alpha:NULL];
		PASS(fabs(th - uh) < 0.02, "bubble tint keeps the user's hue");
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

	// --- Balloon callout geometry ----------------------------------------
	{
		TLBubbleTranscriptView *tv = [[TLBubbleTranscriptView alloc]
			initWithFrame:NSMakeRect(0, 0, 400, 300) theme:nil];
		NSRect br = NSMakeRect(60.0, 100.0, 90.0, 28.0);

		NSBezierPath *left = [tv balloonPathInRect:br cornerRadius:11.0
		                                  withTail:YES tailLeft:YES];
		PASS([left containsPoint:NSMakePoint(NSMinX(br) - 4.5, NSMinY(br) + 16.0)],
			"callout protrudes on the avatar side (left)");
		PASS(![left containsPoint:NSMakePoint(NSMaxX(br) + 4.5, NSMinY(br) + 16.0)],
			"no callout on the far side of a left-tailed balloon");
		PASS(![left containsPoint:NSMakePoint(
		    NSMidX(br), NSMinY(br) - 4.0)],
			"callout no longer hangs off the bottom edge");

		NSBezierPath *right = [tv balloonPathInRect:br cornerRadius:11.0
		                                   withTail:YES tailLeft:NO];
		PASS([right containsPoint:NSMakePoint(NSMaxX(br) + 4.5, NSMinY(br) + 16.0)],
			"callout protrudes on the avatar side (right)");

		NSBezierPath *plain = [tv balloonPathInRect:br cornerRadius:11.0
		                                   withTail:NO tailLeft:YES];
		PASS(![plain containsPoint:NSMakePoint(NSMinX(br) - 4.5, NSMinY(br) + 16.0)],
			"tailless balloon does not protrude");

		// On a tall balloon the nub must sit in the upper half, where the
		// avatar hangs; on short pills every point borders the picture.
		NSRect tall = NSMakeRect(60.0, 100.0, 90.0, 60.0);
		NSBezierPath *tallRight = [tv balloonPathInRect:tall cornerRadius:11.0
		                                       withTail:YES tailLeft:NO];
		BOOL upper = NO;
		BOOL lower = NO;
		for (CGFloat y = NSMinY(tall); y < NSMaxY(tall); y += 1.0) {
			if ([tallRight containsPoint:NSMakePoint(NSMaxX(tall) + 3.0, y)]) {
				if (y < NSMidY(tall)) {
					upper = YES;
				} else {
					lower = YES;
				}
			}
		}
		PASS(upper && !lower, "callout points at the avatar's height");
		[tv release];
	}

	// --- Avatar click selects the speaker in the user list ---------------
	{
		TLChannel *channel = [[TLChannel alloc] initWithDictionary:@{
			@"id": @2, @"name": @"#sel", @"type": @"channel", @"state": @1,
			@"messages": @[] }];
		[channel addUser:[[TLUser alloc] initWithDictionary:
		    @{@"nick": @"alice", @"mode": @"o", @"away": @""}]];
		[channel addUser:[[TLUser alloc] initWithDictionary:
		    @{@"nick": @"bob", @"mode": @"v", @"away": @""}]];
		[channel addUser:[[TLUser alloc] initWithDictionary:
		    @{@"nick": @"carol", @"mode": @"", @"away": @""}]];

		TLUserListView *list = [[TLUserListView alloc]
			initWithFrame:NSMakeRect(0, 0, 120, 200)];
		RowRecorder *rec = [[RowRecorder alloc] init];
		g_lastSeenRow = -99;
		[list setDelegate:rec];
		[list reloadWithChannel:channel];
		PASS([list selectedUserRow] == -1, "nothing selected after reload");

		PASS([list selectUserWithNick:@"bob"], "selectUserWithNick finds bob");
		PASS([list selectedUserRow] == 1, "bob's row became selected");
		PASS(g_lastSeenRow == 1, "selection change reached the delegate");
		PASS(![list selectUserWithNick:@"zed"], "unknown nick is not selectable");

		TLMessageView *mv = [[TLMessageView alloc]
			initWithFrame:NSMakeRect(0, 0, 300, 200)];
		if (![mv usesBubbles]) {
			[mv setUsesBubbles:YES];
		}
		[mv setDelegate:rec];
		[mv transcriptViewDidSelectSender:@"bob"];
		PASS([g_lastSeenNick isEqualToString:@"bob"],
			"sender selection forwarded to the message view delegate");

		[mv release];
		[rec release];
		[list release];
		[channel release];
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

		// The detector caches its character set in a static; the cache must
		// survive the autorelease pool that created it (this crashed live
		// when the second message was rendered after a pool drain).
		{
			NSAutoreleasePool *inner = [NSAutoreleasePool new];
			[TLLinkDetector rangesOfLinksInString:@"warmup https://a.example"];
			[inner release];
		}
		ranges = [TLLinkDetector rangesOfLinksInString:
		    @"second pass https://b.example after pool drain"];
		PASS([ranges count] == 1, "detector cache outlives its pool");

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
