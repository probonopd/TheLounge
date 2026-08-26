/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

// Mirrors the DockService protocol published by the Gershwin workspace Dock.
// We declare it locally instead of importing the workspace headers so this
// app builds without linking gershwin-workspace; the service is reached at
// runtime over distributed objects and is simply absent when no Dock runs.
@protocol DockService <NSObject>

- (void)setBadgeCount:(int64_t)count;
- (void)setCountVisible:(BOOL)visible;
- (void)setProgressValue:(double)value;
- (void)setProgressVisible:(BOOL)visible;
- (void)setUrgent:(BOOL)urgent;
- (void)clearAll;

@end

@interface TLDockBadge : NSObject

// Push the running total of unread messages to the Dock; a zero or negative
// count hides the badge entirely.
- (void)updateWithUnreadCount:(NSInteger)count;

// Hide the badge unconditionally, e.g. when the application quits so no stale
// count lingers on the Dock icon.
- (void)clear;

@end
