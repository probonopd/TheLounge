/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "TLApplicationDelegate.h"

static void uncaughtHandler(NSException *exception)
{
	fprintf(stderr, "UNCAUGHT EXCEPTION: %s - %s\n",
		[[exception name] UTF8String], [[exception reason] UTF8String]);
	NSArray *symbols = [exception callStackSymbols];
	for (NSString *s in symbols) {
		fprintf(stderr, "  %s\n", [s UTF8String]);
	}
}

int main(int argc, char **argv)
{
	NSSetUncaughtExceptionHandler(&uncaughtHandler);

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	// No nib is used, so the delegate must be installed explicitly for
	// applicationDidFinishLaunching to run and present the login window.
	NSApplication *app = [NSApplication sharedApplication];
	TLApplicationDelegate *delegate = [[TLApplicationDelegate alloc] init];
	[app setDelegate:delegate];
	[app run];

	[delegate release];
	[pool drain];
	return 0;
}