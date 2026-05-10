/*  NAME:
        SPUSBObject.m

    DESCRIPTION:
        Objective-C implementation of an object communicating with a USB SpaceMouse
        (3Dconnexion SpaceMouse Compact) under macOS using IOHIDManager.

        USB HID protocol reference:
            https://spacemice.org/index.php?title=SpaceMouse_Compact

 COPYRIGHT:
     Copyright (c) 2005-2025, Quesa Developers. All rights reserved.

     For the current release of Quesa, please see:

         <https://github.com/jwwalker/Quesa>

     For the current release of Quesa including 3D device support,
     please see: <https://github.com/h-haris/Quesa>

     Redistribution and use in source and binary forms, with or without
     modification, are permitted provided that the following conditions
     are met:

         o Redistributions of source code must retain the above copyright
           notice, this list of conditions and the following disclaimer.

         o Redistributions in binary form must reproduce the above
           copyright notice, this list of conditions and the following
           disclaimer in the documentation and/or other materials provided
           with the distribution.

         o Neither the name of Quesa nor the names of its contributors
           may be used to endorse or promote products derived from this
           software without specific prior written permission.

     THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
     "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
     LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
     A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
     OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
     SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
     TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
     PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
     LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
     NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
     SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 ___________________________________________________________________________
*/

#include <math.h>
#include <IOKit/hid/IOHIDManager.h>

#import "SPUSBObject.h"
#import "SPUSBdeliverQuesa.h"

#define SPUSB_DEBUG 1   // set to 0 to silence raw HID logging

// 3Dconnexion USB identifiers for SpaceMouse Compact
#define kSpaceMouse3DxVendorID  0x256F
#define kSpaceMouseCompactPID   0xC635

/*  USB SpaceMouse raw axis counts at full deflection ≈ ±350.
    The RS-232 Magellan used base 4000 for a physical max of ~400 counts (10:1 ratio).
    Applying the same ratio to USB: 350 × 10 = 3500.
    rotScaleBase = 3500 → at rotScale=10, max per-report deflection ≈ 1° (≈ 60°/s at 60 Hz).
    transScaleBase = 3500 → keeps translation in the same ballpark as RS-232.           */
#define rotScaleBase   (3500.0f)
#define transScaleBase (3500.0f)

NSString * const SPUSBDeviceConnectedNotification    = @"SPUSBDeviceConnected";
NSString * const SPUSBDeviceDisconnectedNotification = @"SPUSBDeviceDisconnected";

// ---------------------------------------------------------------------------
// C callbacks — bridge to ObjC methods
// ---------------------------------------------------------------------------

static void hidDeviceMatchedCallback(void *context, IOReturn result,
                                     void *sender, IOHIDDeviceRef device)
{
    [(SPUSBObject *)context deviceMatched:device];
}

static void hidDeviceRemovedCallback(void *context, IOReturn result,
                                     void *sender, IOHIDDeviceRef device)
{
    [(SPUSBObject *)context deviceRemoved:device];
}

static void hidValueCallback(void *context, IOReturn result, void *sender,
                              IOHIDValueRef value)
{
    [(SPUSBObject *)context processValue:value];
}

// ---------------------------------------------------------------------------

@implementation SPUSBObject

- init
{
    self = [super init];
    if (!self) return self;

    QuesaConnection = [[SPUSBdeliverQuesa alloc] init];
    [self PrefsFromDisk];

    return self;
}

- (void)dealloc
{
    [self disconnectFromDevice];
    [self PrefsToDisk];
    [prefs release];
    [QuesaConnection release];
    [super dealloc];
}

- PrefsFromDisk
{
    prefs = [[NSUserDefaults standardUserDefaults] retain];

    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    [defaults setObject:[NSNumber numberWithBool:NO]    forKey:@"usbHasPrefsFile"];
    [defaults setObject:[NSNumber numberWithFloat:10.0] forKey:@"usbRotScale"];
    [defaults setObject:[NSNumber numberWithFloat:3.0]  forKey:@"usbTransScale"];
    [prefs registerDefaults:defaults];

    hasPrefsFile = [prefs boolForKey:@"usbHasPrefsFile"];
    [self setRotScale:[prefs floatForKey:@"usbRotScale"]];
    [self setTransScale:[prefs floatForKey:@"usbTransScale"]];

    return self;
}

- PrefsToDisk
{
    [prefs setBool:YES     forKey:@"usbHasPrefsFile"];
    [prefs setFloat:rotScale   forKey:@"usbRotScale"];
    [prefs setFloat:transScale forKey:@"usbTransScale"];
    [prefs synchronize];

    return self;
}

- (BOOL)hasPrefsFile
{
    return hasPrefsFile;
}

- setFrontend:(id)anObject
{
    frontend = anObject;
    return self;
}

// ---------------------------------------------------------------------------
// Connect / disconnect
// ---------------------------------------------------------------------------

- (BOOL)connectToDevice
{
    if (hidManager) return [self isConnected];   // already open

    hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!hidManager) return NO;

    NSDictionary *matching = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:kSpaceMouse3DxVendorID], @kIOHIDVendorIDKey,
        [NSNumber numberWithInt:kSpaceMouseCompactPID],  @kIOHIDProductIDKey,
        nil];
    IOHIDManagerSetDeviceMatching(hidManager, (CFDictionaryRef)matching);

    IOHIDManagerRegisterDeviceMatchingCallback(hidManager, hidDeviceMatchedCallback, self);
    IOHIDManagerRegisterDeviceRemovalCallback(hidManager,  hidDeviceRemovedCallback, self);
    IOHIDManagerRegisterInputValueCallback(hidManager, hidValueCallback, self);

    IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), kCFRunLoopCommonModes);

    IOReturn ret = IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess)
    {
        NSLog(@"[SPUSB] IOHIDManagerOpen failed: 0x%08X", ret);
        IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFRelease(hidManager);
        hidManager = NULL;
        return NO;
    }

    NSLog(@"[SPUSB] HID manager opened — waiting for device (VID 0x%04X PID 0x%04X)...",
          kSpaceMouse3DxVendorID, kSpaceMouseCompactPID);
    // isConnected becomes YES when the device-matched callback fires.
    return YES;
}

- disconnectFromDevice
{
    if (hidDevice)
    {
        IOHIDDeviceUnscheduleFromRunLoop(hidDevice, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        hidDevice = NULL;
    }
    if (hidManager)
    {
        IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        IOHIDManagerClose(hidManager, kIOHIDOptionsTypeNone);
        CFRelease(hidManager);
        hidManager = NULL;
    }
    NSLog(@"[SPUSB] disconnected");
    return self;
}

- (BOOL)isConnected
{
    return (hidDevice != NULL);
}

// ---------------------------------------------------------------------------
// HID device callbacks
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Vendor feature report logger
//
// Polls every report ID from the known output/config and vendor-status tables
// via GET_REPORT (kIOHIDReportTypeFeature) and logs the raw bytes.
// Reports that the device does not expose as feature reports will return an
// IOReturn error instead of data — both outcomes are useful for protocol RE.
// ---------------------------------------------------------------------------

- (void)logVendorFeatureReports
{
    // Report IDs to probe: output/config + vendor-status input (from protocol table)
    const uint8_t reportIDs[] = { 1, 5, 6, 7, 8, 9, 10, 11,
                                   19, 25, 26, 144, 154, 224 };
    const size_t  count = sizeof(reportIDs) / sizeof(reportIDs[0]);

    NSLog(@"[SPUSB] --- vendor feature report dump ---");
    for (size_t i = 0; i < count; i++)
    {
        uint8_t  buf[64] = {0};
        CFIndex  len = (CFIndex)sizeof(buf);
        IOReturn ret = IOHIDDeviceGetReport(hidDevice,
                                            kIOHIDReportTypeFeature,
                                            reportIDs[i],
                                            buf, &len);
        if (ret == kIOReturnSuccess && len > 0)
        {
            NSMutableString *hex = [NSMutableString stringWithCapacity:(NSUInteger)(len * 3)];
            for (CFIndex b = 0; b < len; b++)
                [hex appendFormat:@" %02X", buf[b]];
            NSLog(@"[SPUSB] report %3u (%2ld bytes):%@", reportIDs[i], (long)len, hex);
        }
        else
        {
            NSLog(@"[SPUSB] report %3u — no feature report (IOReturn 0x%08X)",
                  reportIDs[i], ret);
        }
    }
    NSLog(@"[SPUSB] --- end vendor feature report dump ---");
}

- (void)deviceMatched:(IOHIDDeviceRef)device
{
    hidDevice = device;
    NSLog(@"[SPUSB] device connected");

    // Run the feature-report probe on a background thread.  IOHIDDeviceGetReport
    // blocks for ~5 s per absent report; calling it here would freeze the main
    // run loop and prevent input-report callbacks from firing.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self logVendorFeatureReports];
    });

    [[NSNotificationCenter defaultCenter]
        postNotificationName:SPUSBDeviceConnectedNotification object:self];
}

- (void)deviceRemoved:(IOHIDDeviceRef)device
{
    if (hidDevice == device)
    {
        hidDevice = NULL;
        NSLog(@"[SPUSB] device removed");
        [[NSNotificationCenter defaultCenter]
            postNotificationName:SPUSBDeviceDisconnectedNotification object:self];
    }
}

// ---------------------------------------------------------------------------
// HID report parsing
//
// Translation (report 1) and rotation (report 2) arrive in separate packets.
// Each is delivered as a partial move; the other 3 axes are sent as zero so
// that Quesa's delta-move accumulation is not corrupted by stale values.
// ---------------------------------------------------------------------------

- (void)processValue:(IOHIDValueRef)value
{
    IOHIDElementRef element = IOHIDValueGetElement(value);
    uint32_t usagePage = IOHIDElementGetUsagePage(element);
    uint32_t usage     = IOHIDElementGetUsage(element);
    CFIndex  intVal    = IOHIDValueGetIntegerValue(value);

#if SPUSB_DEBUG
    NSLog(@"[SPUSB] page=0x%02X usage=0x%02X val=%ld", usagePage, usage, (long)intVal);
#endif

    // Generic Desktop (0x01) axes: X=0x30 Y=0x31 Z=0x32 Rx=0x33 Ry=0x34 Rz=0x35
    if (usagePage == 0x01)
    {
        float v = (float)intVal;
        switch (usage)
        {
            case 0x30: [QuesaConnection deliverTranslation:transMult*v :0 :0]; break;
            case 0x31: [QuesaConnection deliverTranslation:0 :transMult*v :0]; break;
            case 0x32: [QuesaConnection deliverTranslation:0 :0 :transMult*v]; break;
            case 0x33: [QuesaConnection deliverRotation:rotMult*v :0 :0]; break;
            case 0x34: [QuesaConnection deliverRotation:0 :rotMult*v :0]; break;
            case 0x35: [QuesaConnection deliverRotation:0 :0 :rotMult*v]; break;
            default: break;
        }
    }
    // Button page (0x09)
    else if (usagePage == 0x09)
    {
        // Re-read all buttons via the element's parent report would be ideal,
        // but for now deliver the bitmask as reported.
        [QuesaConnection deliverKeyPress:(int)intVal];
    }
}

// ---------------------------------------------------------------------------
// Scale accessors
// ---------------------------------------------------------------------------

- setRotScale:(float)aFloat
{
    rotScale = aFloat;
    rotMult  = (rotScale / rotScaleBase) * ((float)M_PI / 180.0f);
    return self;
}

- (float)rotScale
{
    return rotScale;
}

- setTransScale:(float)aFloat
{
    transScale = aFloat;
    transMult  = transScale / transScaleBase;
    return self;
}

- (float)transScale
{
    return transScale;
}

@end
