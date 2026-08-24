/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

// Multi-line composer input. Enter sends; Shift-Enter inserts a real
// newline so one message can span several lines.
@interface TLInputTextView : NSTextView
{
@private
	id _sendTarget;
	SEL _sendAction;
}

- (void)setSendTarget:(id)target action:(SEL)action;

@end
