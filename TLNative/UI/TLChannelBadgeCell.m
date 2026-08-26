/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLChannelBadgeCell.h"

@implementation TLChannelBadgeCell

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	if (_unseen <= 0) {
		[super drawInteriorWithFrame:cellFrame inView:controlView];
		return;
	}
	// Height available for the badge; keep it inside the row with a little
	// margin so it never clips the text baseline.
	CGFloat h = cellFrame.size.height - 4.0;
	if (h < 12.0) {
		h = 12.0;
	}
	if (h > cellFrame.size.height) {
		h = cellFrame.size.height;
	}

	NSString *label = (_unseen > 99)
		? @"99+"
		: [NSString stringWithFormat:@"%ld", (long)_unseen];
	NSDictionary *attrs = @{
		NSFontAttributeName: [NSFont boldSystemFontOfSize:10.0],
		NSForegroundColorAttributeName: [NSColor whiteColor]
	};
	NSSize sz = [label sizeWithAttributes:attrs];

	// A single digit fits in a circle; longer numbers get a pill that grows
	// with the text so the count stays readable.
	CGFloat pad = 6.0;
	CGFloat w = sz.width + pad * 2.0;
	if (w < h) {
		w = h;
	}

	NSRect badge = NSMakeRect(cellFrame.origin.x + 3.0,
		cellFrame.origin.y + (cellFrame.size.height - h) / 2.0, w, h);

	[[NSColor redColor] set];
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:badge
		xRadius:h / 2.0 yRadius:h / 2.0];
	[path fill];

	NSPoint p = NSMakePoint(badge.origin.x + (w - sz.width) / 2.0,
		badge.origin.y + (h - sz.height) / 2.0);
	[label drawAtPoint:p withAttributes:attrs];

	// Draw the title to the right of the badge.
	NSRect title = cellFrame;
	title.origin.x += w + 7.0;
	title.size.width -= (w + 7.0);
	if (title.size.width < 0) {
		title.size.width = 0;
	}
	[super drawInteriorWithFrame:title inView:controlView];
}

@end
