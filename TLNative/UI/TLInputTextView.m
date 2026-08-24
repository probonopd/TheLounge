/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLInputTextView.h"

@implementation TLInputTextView

- (void)setSendTarget:(id)target action:(SEL)action
{
	_sendTarget = target;
	_sendAction = action;
}

- (void)insertNewline:(id)sender
{
	NSEvent *event = [NSApp currentEvent];
	if (event && ([event modifierFlags] & NSShiftKeyMask)) {
		[super insertNewline:sender];
		// The composer height follows the typed lines; the notification
		// the text system would post for programmatic edits is skipped,
		// so nudge the delegate here.
		if ([_delegate respondsToSelector:@selector(textDidChange:)]) {
			[(id)_delegate textDidChange:
			    [NSNotification notificationWithName:NSTextDidChangeNotification
			                                object:self]];
		}
		return;
	}
	if (_sendTarget && _sendAction) {
		[NSApp sendAction:_sendAction to:_sendTarget from:self];
	}
}

@end
