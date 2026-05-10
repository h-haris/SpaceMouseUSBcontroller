/*  NAME:
        SPUSBObject.h

    DESCRIPTION:
        Objective-C interface for an object communicating with a USB SpaceMouse
        (3Dconnexion SpaceMouse Compact, VID 0x256F / PID 0xC635) under macOS.
        Uses IOHIDManager; replaces the RS-232 SPCMObject.

        HID report layout (SpaceMouse Compact):
            Report 1 — translation:  6 bytes, 3 × int16 LE  (tx, ty, tz)
            Report 2 — rotation:     6 bytes, 3 × int16 LE  (rx, ry, rz)
            Report 3 — buttons:      1 byte bitmask         (bit0=btn1, bit1=btn2)

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

#import <Foundation/Foundation.h>
#include <IOKit/hid/IOHIDManager.h>

@class SPUSBdeliverQuesa;

@interface SPUSBObject : NSObject
{
    id              frontend;

    float           rotMult;
    float           transMult;

    IOHIDManagerRef  hidManager;
    IOHIDDeviceRef   hidDevice;
    uint8_t          reportBuffer[64];
    uint8_t          lastButtonState;

    SPUSBdeliverQuesa *QuesaConnection;

    NSUserDefaults  *prefs;
    BOOL            hasPrefsFile;

    float   rotScale;
    float   transScale;
}

- init;
- (void)dealloc;

- PrefsFromDisk;
- PrefsToDisk;
- (BOOL)hasPrefsFile;

- setFrontend:(id)anObject;

- (BOOL)connectToDevice;
- disconnectFromDevice;
- (BOOL)isConnected;

- setRotScale:(float)aFloat;
- (float)rotScale;
- setTransScale:(float)aFloat;
- (float)transScale;

// Called from C HID callbacks — do not call directly.
- (void)deviceMatched:(IOHIDDeviceRef)device;
- (void)deviceRemoved:(IOHIDDeviceRef)device;
- (void)processReportID:(uint32_t)reportID data:(const uint8_t *)data length:(CFIndex)length;
- (void)processValue:(IOHIDValueRef)value;

@end

// Notification names posted on the default centre when the device connects/disconnects.
extern NSString * const SPUSBDeviceConnectedNotification;
extern NSString * const SPUSBDeviceDisconnectedNotification;
