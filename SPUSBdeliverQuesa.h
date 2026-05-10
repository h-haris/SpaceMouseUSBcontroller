/*  NAME:
        SPUSBdeliverQuesa.h

    DESCRIPTION:
        Objective-C interface for an object communicating with Quesa and
        delivering translation, rotation and button state for a USB SpaceMouse
        (3Dconnexion SpaceMouse Compact) under macOS.

 COPYRIGHT:
     Copyright (c) 2003-2025, Quesa Developers. All rights reserved.

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

#include <CoreFoundation/CoreFoundation.h>

#ifndef QUESA_OS_MACINTOSH
#define QUESA_OS_MACINTOSH 1
#endif

#ifndef Q3_DEBUG
#define Q3_DEBUG 1
#endif

#include <Quesa/Quesa.h>
#include <Quesa/QuesaMath.h>
#include <Quesa/QuesaController.h>

#import <Foundation/Foundation.h>

@interface SPUSBdeliverQuesa : NSObject {
    TQ3ControllerRef    fControllerRef;
    TQ3ControllerData   fControllerData;
}

- init;
- (void)dealloc;
- (BOOL)deliverTranslation:(float)x :(float)y :(float)z;
- (BOOL)deliverRotation:(float)a :(float)b :(float)c;
- (BOOL)deliverKeyPress:(int)keys;

@end
