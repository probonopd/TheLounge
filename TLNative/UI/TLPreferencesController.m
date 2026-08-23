/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLPreferencesController.h"

// Code-built preferences panel. Layout follows the Gershwin appearance
// metrics: 24px side margins, 15px top margin, 20px bottom margin.

@implementation TLPreferencesController

- (instancetype)init
{
	NSRect contentRect = NSMakeRect(0, 0, 380, 130);
	NSWindow *window = [[NSWindow alloc]
		initWithContentRect:contentRect
		              styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		                backing:NSBackingStoreBuffered
		                  defer:NO];
	[window setTitle:@"The Lounge Preferences"];
	[window setReleasedWhenClosed:NO];
	[window center];

	self = [super initWithWindow:window];
	[window release];
	if (self) {
		[self buildInterface];
	}
	return self;
}

- (void)buildInterface
{
	NSView *content = [[self window] contentView];
	CGFloat width = NSWidth([content bounds]);
	const CGFloat sideMargin = 24.0;
	const CGFloat topMargin = 15.0;

	_bubblesCheckbox = [[NSButton alloc] initWithFrame:
		NSMakeRect(sideMargin, NSHeight([content bounds]) - topMargin - 18.0,
			width - 2.0 * sideMargin, 18.0)];
	[_bubblesCheckbox setButtonType:NSSwitchButton];
	[_bubblesCheckbox setTitle:@"Show chat as speech bubbles"];
	[_bubblesCheckbox setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[_bubblesCheckbox setTarget:self];
	[_bubblesCheckbox setAction:@selector(toggleBubbles:)];
	[_bubblesCheckbox setState:TLPreferencesUseBubbles() ? NSOnState : NSOffState];
	[content addSubview:_bubblesCheckbox];

	NSTextField *hint = [[NSTextField alloc] initWithFrame:
		NSMakeRect(sideMargin, 30.0, width - 2.0 * sideMargin, 34.0)];
	[hint setEditable:NO];
	[hint setSelectable:NO];
	[hint setBordered:NO];
	[hint setBezeled:NO];
	[hint setDrawsBackground:NO];
	[hint setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[hint setTextColor:[NSColor disabledControlTextColor]];
	[hint setStringValue:@"Renders conversations in the iChat-style Aqua look "
		@"with avatars and tails instead of a plain text log."];
	[hint setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[content addSubview:hint];
	[hint release];
}

- (void)toggleBubbles:(id)sender
{
	TLPreferencesSetUseBubbles([_bubblesCheckbox state] == NSOnState);
}

- (void)showWindow:(id)sender
{
	// Reflect changes made elsewhere while the panel was closed.
	[_bubblesCheckbox setState:
		TLPreferencesUseBubbles() ? NSOnState : NSOffState];
	[super showWindow:sender];
}

- (void)dealloc
{
	[_bubblesCheckbox release];
	[super dealloc];
}

@end
