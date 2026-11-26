//
//  KSCrashNotificationNames.h
//
//  Created by Alexander Cohen on 2026-11-22.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#ifndef HDR_KSCrashNotificationNames_h
#define HDR_KSCrashNotificationNames_h

#import <Foundation/Foundation.h>

#include "KSCrashNamespace.h"

// The UIKit and Foundation notifications the core observes by name, so the core imports neither
// UIKit nor any other UI framework. Each name is the string its UIKit or Foundation symbol holds;
// KSCrashAppMemory_Tests compares them where the symbols exist.

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const KSApplicationDidFinishLaunchingNotification;
FOUNDATION_EXPORT NSNotificationName const KSApplicationWillEnterForegroundNotification;
FOUNDATION_EXPORT NSNotificationName const KSApplicationDidBecomeActiveNotification;
FOUNDATION_EXPORT NSNotificationName const KSApplicationWillResignActiveNotification;
FOUNDATION_EXPORT NSNotificationName const KSApplicationDidEnterBackgroundNotification;
FOUNDATION_EXPORT NSNotificationName const KSApplicationWillTerminateNotification;
FOUNDATION_EXPORT NSNotificationName const KSApplicationProtectedDataDidBecomeAvailableNotification;
FOUNDATION_EXPORT NSNotificationName const KSApplicationProtectedDataWillBecomeUnavailableNotification;
FOUNDATION_EXPORT NSNotificationName const KSExtensionHostDidBecomeActiveNotification;
FOUNDATION_EXPORT NSNotificationName const KSExtensionHostWillResignActiveNotification;
FOUNDATION_EXPORT NSNotificationName const KSExtensionHostDidEnterBackgroundNotification;
FOUNDATION_EXPORT NSNotificationName const KSExtensionHostWillEnterForegroundNotification;

NS_ASSUME_NONNULL_END

#endif  // HDR_KSCrashNotificationNames_h
