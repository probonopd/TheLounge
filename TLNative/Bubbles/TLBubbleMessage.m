/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLBubbleMessage.h"

@implementation TLBubbleMessage

+ (instancetype)messageWithText:(NSString *)text
                     senderName:(NSString *)senderName
                       outgoing:(BOOL)outgoing
{
	TLBubbleMessage *m = [[TLBubbleMessage alloc] init];
	m.text = text;
	m.senderName = senderName;
	m.outgoing = outgoing;
	return [m autorelease];
}

- (void)dealloc
{
	[_senderName release];
	[_text release];
	[_attributedText release];
	[_avatar release];
	[super dealloc];
}

@end
