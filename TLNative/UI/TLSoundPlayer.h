/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Sound playback adapted from the Eau theme's EauSound (same author).
 */

#import <Foundation/Foundation.h>

/* Plays the incoming-message alert: a short system sound at a deliberately
 * quiet level, further scaled by the desktop's configured alert volume.
 * Calls within the cooldown window are dropped so a burst of messages does
 * not machine-gun the sound. */
@interface TLSoundPlayer : NSObject

+ (void)playMessageSound;

@end
