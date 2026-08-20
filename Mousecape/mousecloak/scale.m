//
//  scale.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "scale.h"
#import "MCPrefs.h"
#import "MCDefs.h"
#import "CGSCursor.h"
#import <math.h>
#import <Foundation/Foundation.h>

float cursorScale(void) {
    float value;
    CGSGetCursorScale(CGSMainConnectionID(), &value);
    return value;
}

float defaultCursorScale(void) {
    float scale = [MCDefault(MCPreferencesCursorScaleKey) floatValue];
    // Ensure scale is at least 1.0 (system only supports magnification, not shrinking)
    if (scale < 1.0 || scale > 16)
        scale = 1;
    return scale;
}

BOOL setCursorScale(float dbl) {
    if (!isfinite(dbl) || dbl <= 0 || dbl > 16) {
        MMLog(BOLD RED "Invalid cursor scale (must be 0 < scale <= 16)" RESET);
        return NO;
    }

    BOOL cgsSuccess = NO;
    BOOL prefSuccess = NO;

    // Method 1: Use CGS API (immediate effect)
    CGError err = CGSSetCursorScale(CGSMainConnectionID(), dbl);
    if (err == noErr) {
        MMLog(GREEN "CGSSetCursorScale succeeded (%.1fx)" RESET, dbl);
        cgsSuccess = YES;
    } else {
        MMLog(YELLOW "CGSSetCursorScale failed (error %d)" RESET, err);
    }

    // Method 2: Update system preference (for persistence and system settings UI sync)
    // System settings only support scale >= 1.0 (magnification only, no shrinking)
    if (dbl >= 1.0) {
        CFPreferencesSetAppValue(CFSTR("mouseDriverCursorSize"),
                                 (__bridge CFNumberRef)@(dbl),
                                 CFSTR("com.apple.universalaccess"));

        if (CFPreferencesAppSynchronize(CFSTR("com.apple.universalaccess"))) {
            MMLog("System preference updated to %.1fx", dbl);
            prefSuccess = YES;

            // Notify system of preference change
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDistributedCenter(),
                CFSTR("com.apple.accessibility.cache.cursor.size"),
                NULL, NULL, true);
        } else {
            MMLog(YELLOW "Failed to sync accessibility preferences" RESET);
        }
    } else {
        MMLog("System preference not updated (scale < 1.0, shrinking not supported)");
    }

    // Success if either method worked
    if (cgsSuccess || prefSuccess) {
        MMLog(GREEN "Cursor scale set to %.1fx" RESET, dbl);
        return YES;
    } else {
        MMLog(RED "Failed to set cursor scale!" RESET);
        return NO;
    }
}
