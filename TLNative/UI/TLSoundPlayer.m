/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Sound playback adapted from the Eau theme's EauSound (same author).
 */

#import "TLSoundPlayer.h"

#import <AppKit/AppKit.h>

/*
 * NSSound's libao sink ignores -setVolume:, and lowering the mixer for one
 * sound would duck every other sound. The sound therefore plays through an
 * attenuated copy of the file: the WAV is decoded, its PCM samples are
 * scaled down and the result is handed to NSSound via -initWithData:. Only
 * this sound plays quieter; nothing on the system is muted or restored
 * around it.
 */

/* Quiet by design: an incoming message is ambient information, not an
 * alert. Multiplied by the desktop alert volume so the system preference
 * still governs the overall level. */
static const float TLMessageSoundGain = 0.3f;

static const NSTimeInterval TLMessageSoundCooldown = 2.0;

typedef struct
{
	NSUInteger sampleOffset;   /* offset of the data chunk payload */
	NSUInteger sampleBytes;    /* size of the data chunk payload */
	uint16_t formatTag;        /* 1 = PCM, 3 = IEEE float */
	uint16_t bitsPerSample;
} TLWavInfo;

/* Minimal RIFF/WAVE walker: finds the fmt and data chunks. Handles
 * WAVE_FORMAT_EXTENSIBLE by reading the real tag from its subformat GUID. */
static BOOL TLParseWav(const uint8_t *b, NSUInteger len, TLWavInfo *out)
{
	if (len < 12 || memcmp(b, "RIFF", 4) != 0 || memcmp(b + 8, "WAVE", 4) != 0) {
		return NO;
	}

	NSUInteger off = 12;
	BOOL haveFmt = NO, haveData = NO;

	while (off + 8 <= len) {
		uint32_t size = (uint32_t)b[off + 4] | ((uint32_t)b[off + 5] << 8) |
			((uint32_t)b[off + 6] << 16) | ((uint32_t)b[off + 7] << 24);

		if (!haveFmt && memcmp(b + off, "fmt ", 4) == 0) {
			if (off + 24 > len) {
				return NO;
			}
			out->formatTag = (uint16_t)(b[off + 8] | (b[off + 9] << 8));
			out->bitsPerSample = (uint16_t)(b[off + 22] | (b[off + 23] << 8));
			if (out->formatTag == 0xFFFE && off + 48 <= len) {
				out->formatTag = (uint16_t)(b[off + 32] | (b[off + 33] << 8));
			}
			haveFmt = YES;
		} else if (!haveData && memcmp(b + off, "data", 4) == 0) {
			NSUInteger avail = len - off - 8;
			out->sampleOffset = off + 8;
			out->sampleBytes = (size <= avail) ? size : avail;
			haveData = YES;
		}

		/* Chunks are word aligned, so odd payloads carry a pad byte */
		off += 8 + size + (size & 1);
		if (haveFmt && haveData) {
			break;
		}
	}

	return haveFmt && haveData && out->sampleBytes > 0;
}

static int32_t TLClamp(double v, double lo, double hi)
{
	if (v < lo) {
		return (int32_t)lo;
	}
	if (v > hi) {
		return (int32_t)hi;
	}
	return (int32_t)v;
}

/* Returns a WAV blob identical to the input except with all samples scaled
 * by gain. Returns nil for containers or sample formats we do not
 * understand; the caller then plays the original file unscaled rather than
 * risk emitting garbage. */
static NSData *TLScaleWav(NSData *wav, float gain)
{
	const uint8_t *src = [wav bytes];
	TLWavInfo info = {0};

	if (!TLParseWav(src, [wav length], &info)) {
		return nil;
	}

	switch (info.formatTag) {
		case 1:
			if (info.bitsPerSample != 8 && info.bitsPerSample != 16 &&
				info.bitsPerSample != 24 && info.bitsPerSample != 32) {
				return nil;
			}
			break;
		case 3:
			if (info.bitsPerSample != 32 && info.bitsPerSample != 64) {
				return nil;
			}
			break;
		default:
			return nil;
	}

	NSMutableData *out = [wav mutableCopy];
	uint8_t *d = [out mutableBytes] + info.sampleOffset;
	NSUInteger n = info.sampleBytes;

	switch (info.formatTag) {
		case 1: {
			switch (info.bitsPerSample) {
				case 8: {
					/* 8 bit WAV is unsigned, centred on 128 */
					for (NSUInteger i = 0; i < n; i++) {
						int v = TLClamp((d[i] - 128) * gain, -128, 127);
						d[i] = (uint8_t)(v + 128);
					}
					break;
				}
				case 16: {
					for (NSUInteger i = 0; i + 1 < n; i += 2) {
						int16_t s = (int16_t)((uint16_t)d[i] | ((uint16_t)d[i + 1] << 8));
						s = (int16_t)TLClamp(s * gain, -32768, 32767);
						d[i] = (uint8_t)(s & 0xff);
						d[i + 1] = (uint8_t)(((uint16_t)s >> 8) & 0xff);
					}
					break;
				}
				case 24: {
					for (NSUInteger i = 0; i + 2 < n; i += 3) {
						int32_t s = (int32_t)((uint32_t)d[i] | ((uint32_t)d[i + 1] << 8) |
							((uint32_t)d[i + 2] << 16));
						if (s & 0x800000) {
							s -= 0x1000000;
						}
						s = TLClamp(s * gain, -8388608, 8388607);
						d[i] = (uint8_t)(s & 0xff);
						d[i + 1] = (uint8_t)((s >> 8) & 0xff);
						d[i + 2] = (uint8_t)((s >> 16) & 0xff);
					}
					break;
				}
				case 32: {
					for (NSUInteger i = 0; i + 3 < n; i += 4) {
						int32_t s = (int32_t)((uint32_t)d[i] | ((uint32_t)d[i + 1] << 8) |
							((uint32_t)d[i + 2] << 16) | ((uint32_t)d[i + 3] << 24));
						s = TLClamp((double)s * gain, -2147483648.0, 2147483647.0);
						d[i] = (uint8_t)(s & 0xff);
						d[i + 1] = (uint8_t)((s >> 8) & 0xff);
						d[i + 2] = (uint8_t)((s >> 16) & 0xff);
						d[i + 3] = (uint8_t)((s >> 24) & 0xff);
					}
					break;
				}
			}
			break;
		}
		case 3: {
			size_t step = (info.bitsPerSample == 32) ? 4 : 8;
			for (NSUInteger i = 0; i + step <= n; i += step) {
				if (step == 4) {
					float f;
					memcpy(&f, d + i, 4);
					f *= gain;
					memcpy(d + i, &f, 4);
				} else {
					double f;
					memcpy(&f, d + i, 8);
					f *= gain;
					memcpy(d + i, &f, 8);
				}
			}
			break;
		}
	}

	return out;
}

/* The Sound prefPane's alert volume slider is the linear gain the desktop
 * applies to system sounds; honoring it keeps the message pop consistent
 * with every other sound the user hears. */
static float TLAlertVolumeGain(void)
{
	NSString *prefsPath = [NSHomeDirectory()
		stringByAppendingPathComponent:@".config/gershwin/sound-defaults.plist"];
	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
	NSNumber *volume = [prefs objectForKey:@"alertVolume"];
	return volume ? [volume floatValue] : 1.0f;
}

@implementation TLSoundPlayer

+ (NSString *)messageSoundPath
{
	NSString *home = NSHomeDirectory();
	NSString *soundNames[] = { @"Pop", @"Ping" };
	NSArray *extensions = @[@"aiff", @"aif", @"wav", @"au", @"snd"];

	NSString *userDir = [home stringByAppendingPathComponent:@"Library/Sounds"];
	NSString *directories[] = { userDir,
		@"/System/Library/Sounds",
		@"/usr/share/sounds",
		@"/usr/local/share/sounds" };

	for (NSUInteger n = 0; n < sizeof(soundNames) / sizeof(soundNames[0]); n++) {
		for (NSUInteger d = 0; d < sizeof(directories) / sizeof(directories[0]); d++) {
			for (NSString *ext in extensions) {
				NSString *path = [[directories[d] stringByAppendingPathComponent:
					soundNames[n]]
					stringByAppendingPathExtension:ext];
				if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
					return path;
				}
			}
		}
	}
	return nil;
}

+ (void)playMessageSound
{
	static NSTimeInterval lastPlayed = 0.0;
	static NSLock *cooldownLock = nil;
	if (cooldownLock == nil) {
		cooldownLock = [[NSLock alloc] init];
	}

	[cooldownLock lock];
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	if (now - lastPlayed < TLMessageSoundCooldown) {
		[cooldownLock unlock];
		return;
	}
	lastPlayed = now;
	[cooldownLock unlock];

	NSString *path = [self messageSoundPath];
	if (path == nil) {
		return;
	}

	float gain = TLMessageSoundGain * TLAlertVolumeGain();
	NSSound *sound = nil;
	if (gain < 0.99f) {
		NSData *wav = [NSData dataWithContentsOfFile:path];
		NSData *quiet = wav ? TLScaleWav(wav, gain) : nil;
		if (quiet) {
			sound = [[NSSound alloc] initWithData:quiet];
		}
	}
	if (!sound) {
		sound = [[NSSound alloc] initWithContentsOfFile:path byReference:YES];
	}
	if (!sound) {
		return;
	}
	[sound play];
	/* NSSound must outlive playback; the cooldown bounds the number of
	 * orphans, so releasing over the playing sound is not worth the risk of
	 * cutting it off. */
}

@end
