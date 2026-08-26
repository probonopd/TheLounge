/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

// A text cell that draws a red circular badge with a white count to its left
// when the channel has unseen messages, then the channel title. Used by the
// left channel list so the user can see which channel a Dock badge belongs to.
@interface TLChannelBadgeCell : NSTextFieldCell

@property (nonatomic, assign) NSInteger unseen;

@end
