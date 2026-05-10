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

#define SPUSB_DEBUG 0   // set to 1 to enable raw HID logging

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

static void hidReportCallback(void *context, IOReturn result, void *sender,
                               IOHIDReportType type, uint32_t reportID,
                               uint8_t *report, CFIndex reportLength)
{
    [(SPUSBObject *)context processReportID:reportID data:report length:reportLength];
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

    NSDictionary *matching = @{
        @(kIOHIDVendorIDKey):  @(kSpaceMouse3DxVendorID),
        @(kIOHIDProductIDKey): @(kSpaceMouseCompactPID),
    };
    IOHIDManagerSetDeviceMatching(hidManager,
                                  (__bridge CFDictionaryRef)matching);

    IOHIDManagerRegisterDeviceMatchingCallback(hidManager, hidDeviceMatchedCallback, self);
    IOHIDManagerRegisterDeviceRemovalCallback(hidManager,  hidDeviceRemovedCallback, self);
    IOHIDManagerRegisterInputReportCallback(hidManager, hidReportCallback, self);
    IOHIDManagerRegisterInputValueCallback(hidManager, hidValueCallback, self);

    IOHIDManagerScheduleWithRunLoop(hidManager,
                                    CFRunLoopGetMain(),
                                    kCFRunLoopDefaultMode);

    // Seize the device so the SpaceMouse does not move the system cursor.
    // Requires prior Wired Accessories approval (System Settings → Privacy & Security
    // → Wired Accessories) on macOS 26+.
    IOReturn ret = IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeSeizeDevice);
    if (ret != kIOReturnSuccess)
    {
        NSLog(@"[SPUSB] IOHIDManagerOpen failed: 0x%08X", ret);
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
    if (hidManager)
    {
        IOHIDManagerUnscheduleFromRunLoop(hidManager,
                                         CFRunLoopGetMain(),
                                         kCFRunLoopDefaultMode);
        IOHIDManagerClose(hidManager, kIOHIDOptionsTypeNone);
        CFRelease(hidManager);
        hidManager = NULL;
    }
    hidDevice = NULL;
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
    // Called on main runLoop.
    hidDevice = device;

    // Log device identity to confirm we matched the right device.
    int32_t vid = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device,
                    CFSTR(kIOHIDVendorIDKey)) intValue];
    int32_t pid = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device,
                    CFSTR(kIOHIDProductIDKey)) intValue];
    NSString *name = (__bridge NSString *)IOHIDDeviceGetProperty(device,
                    CFSTR(kIOHIDProductKey));
    NSLog(@"[SPUSB] device connected  VID=0x%04X PID=0x%04X name=%@", vid, pid, name);

    NSLog(@"[SPUSB] device callbacks ready");

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:SPUSBDeviceConnectedNotification object:self];
    });
}

- (void)deviceRemoved:(IOHIDDeviceRef)device
{
    if (hidDevice == device)
    {
        hidDevice = NULL;
        NSLog(@"[SPUSB] device removed");
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:SPUSBDeviceDisconnectedNotification object:self];
        });
    }
}

// ---------------------------------------------------------------------------
// HID report parsing
//
// Translation (report 1) and rotation (report 2) arrive in separate packets.
// Each is delivered as a partial move; the other 3 axes are sent as zero so
// that Quesa's delta-move accumulation is not corrupted by stale values.
// ---------------------------------------------------------------------------

- (void)processReportID:(uint32_t)reportID data:(const uint8_t *)data length:(CFIndex)length
{
    // data[0] is the report ID byte (included by the IOHIDManager report callback).
    // Axis and button payload begins at data[1].
    if (reportID == 1 && length >= 7)
    {
        int16_t tx = (int16_t)(data[1] | ((uint16_t)data[2] << 8));
        int16_t ty = (int16_t)(data[3] | ((uint16_t)data[4] << 8));
        int16_t tz = (int16_t)(data[5] | ((uint16_t)data[6] << 8));
#if SPUSB_DEBUG
        NSLog(@"[SPUSB] T  x=%d y=%d z=%d", (int)tx, (int)ty, (int)tz);
#endif
        [QuesaConnection deliverTranslation:transMult*tx :transMult*ty :transMult*tz];
    }
    else if (reportID == 2 && length >= 7)
    {
        int16_t rx = (int16_t)(data[1] | ((uint16_t)data[2] << 8));
        int16_t ry = (int16_t)(data[3] | ((uint16_t)data[4] << 8));
        int16_t rz = (int16_t)(data[5] | ((uint16_t)data[6] << 8));
#if SPUSB_DEBUG
        NSLog(@"[SPUSB] R  x=%d y=%d z=%d", (int)rx, (int)ry, (int)rz);
#endif
        [QuesaConnection deliverRotation:rotMult*rx :rotMult*ry :rotMult*rz];
    }
    else if (reportID == 3)
    {
        if (length >= 2)
        {
            uint8_t buttons = data[1];
            if (buttons != lastButtonState)
            {
#if SPUSB_DEBUG
                NSLog(@"[SPUSB] btn 0x%02X (was 0x%02X)", buttons, lastButtonState);
#endif
                lastButtonState = buttons;
                [QuesaConnection deliverKeyPress:buttons];
            }
        }
    }
    else
    {
#if SPUSB_DEBUG
        NSLog(@"[SPUSB] unknown report ID=%u len=%ld", (unsigned)reportID, (long)length);
#endif
    }
}

- (void)processValue:(IOHIDValueRef)value
{
#if SPUSB_DEBUG
    IOHIDElementRef element = IOHIDValueGetElement(value);
    NSLog(@"[SPUSB] VALUE page=0x%02X usage=0x%02X val=%ld",
          IOHIDElementGetUsagePage(element),
          IOHIDElementGetUsage(element),
          (long)IOHIDValueGetIntegerValue(value));
#else
    (void)value;
#endif
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
