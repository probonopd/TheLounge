/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "TLBubbleMessage.h"
#import "TLBubbleTheme.h"
#import "TLBubbleTranscriptView.h"

// Standalone rendering check for the bubble transcript. Builds a window,
// fills the transcript with a representative conversation (short, long and
// wrapped messages on both sides, consecutive same-speaker grouping, a
// custom-colored attributed message and the typing cloud), then just runs.
@interface DemoDelegate : NSObject
{
	NSWindow *_window;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
@end

@implementation DemoDelegate

- (NSImage *)initialsAvatar:(NSString *)initial red:(CGFloat)red
	green:(CGFloat)green blue:(CGFloat)blue
{
	NSRect rect = NSMakeRect(0, 0, 36, 36);
	NSImage *image = [[NSImage alloc] initWithSize:rect.size];
	[image lockFocus];
	[[NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0] set];
	NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:
	    NSInsetRect(rect, 1, 1)];
	[circle fill];
	NSDictionary *attrs = [NSDictionary dictionaryWithObject:
	    [NSFont boldSystemFontOfSize:15.0] forKey:NSFontAttributeName];
	NSSize size = [initial sizeWithAttributes:attrs];
	[[NSColor whiteColor] set];
	[initial drawAtPoint:NSMakePoint((36 - size.width) / 2.0,
	    (36 - size.height) / 2.0) withAttributes:attrs];
	[image unlockFocus];
	return [image autorelease];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSRect frame = NSMakeRect(100, 100, 520, 430);
	_window = [[NSWindow alloc]
	    initWithContentRect:frame
	                  styleMask:NSTitledWindowMask |
	                            NSClosableWindowMask |
	                            NSMiniaturizableWindowMask |
	                            NSResizableWindowMask
	                    backing:NSBackingStoreBuffered
	                      defer:NO];
	[_window setTitle:@"Bubble Transcript"];
	[_window setReleasedWhenClosed:NO];

	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:
	    [[_window contentView] bounds]];
	[scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setAutohidesScrollers:YES];
	[scrollView setBorderType:NSBezelBorder];
	[[_window contentView] addSubview:scrollView];

	TLBubbleTranscriptView *transcript =
	    [[TLBubbleTranscriptView alloc] initWithFrame:
	        NSMakeRect(0, 0, [scrollView contentSize].width, 100)
	                                       theme:nil];
	[scrollView setDocumentView:transcript];

	NSImage *alice = [self initialsAvatar:@"A" red:0.30 green:0.45 blue:0.75];
	NSImage *me = [self initialsAvatar:@"S" red:0.80 green:0.50 blue:0.20];

	NSString *longText = @"This is a considerably longer message so the "
	    "balloon has to wrap over several lines; sizing must follow the "
	    "text system measurement instead of guessing string widths.";

	NSMutableArray *messages = [NSMutableArray array];
	[messages addObject:[TLBubbleMessage messageWithText:@"Hi there!"
	                                          senderName:@"alice"
	                                             outgoing:NO]];
	[messages addObject:[TLBubbleMessage messageWithText:@"Hey! How is it going?"
	                                          senderName:@"steve"
	                                             outgoing:YES]];
	[messages addObject:[TLBubbleMessage messageWithText:@"Pretty good. "
	                          @"Just trying out the new transcript view."
	                                          senderName:@"alice"
	                                             outgoing:NO]];
	[messages addObject:[TLBubbleMessage messageWithText:longText
	                                          senderName:@"steve"
	                                             outgoing:YES]];

	NSMutableAttributedString *rich = [[NSMutableAttributedString alloc]
	    initWithString:@"styled text works too"];
	[rich addAttribute:NSFontAttributeName
	             value:[NSFont boldSystemFontOfSize:13.0]
	             range:NSMakeRange(0, 6)];
	[rich addAttribute:NSForegroundColorAttributeName
	             value:[NSColor colorWithCalibratedRed:0.55 green:0.10
	                                                 blue:0.35 alpha:1.0]
	             range:NSMakeRange(7, 4)];
	[messages addObject:[TLBubbleMessage messageWithText:nil
	                                          senderName:@"steve"
	                                             outgoing:YES]];
	TLBubbleMessage *richMessage = [messages lastObject];
	richMessage.attributedText = rich;
	richMessage.avatar = me;
	[rich release];

	[messages addObject:[TLBubbleMessage messageWithText:@"Nice."
	                                          senderName:@"alice"
	                                             outgoing:NO]];
	[messages addObject:[TLBubbleMessage messageWithText:@"One more from me."
	                                          senderName:@"steve"
	                                             outgoing:YES]];
	[messages addObject:[TLBubbleMessage messageWithText:@"Same speaker again, "
	                          @"grouped with a tighter gap."
	                                          senderName:@"steve"
	                                             outgoing:YES]];
	[messages addObject:[TLBubbleMessage messageWithText:@":)"
	                                          senderName:@"alice"
	                                             outgoing:NO]];

	for (TLBubbleMessage *m in messages) {
		if ([m outgoing]) {
			m.avatar = me;
		} else {
			m.avatar = alice;
		}
	}

	[transcript addMessages:messages];

	// Remote participant composing right now.
	[transcript showTypingIndicatorForSenderName:@"alice"
	                                    outgoing:NO
	                                      avatar:alice];

	[_window makeKeyAndOrderFront:self];
	[transcript scrollToBottom];
}

@end

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSApplication *app = [NSApplication sharedApplication];
	DemoDelegate *delegate = [[DemoDelegate alloc] init];
	[app setDelegate:delegate];
	[app run];

	[delegate release];
	[pool drain];
	return 0;
}
