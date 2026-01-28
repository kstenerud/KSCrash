//
//  KSCrash+Hang.h
//
//  Created by Alexander Cohen on 2026-01-28.
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

#import "KSCrash.h"
#import "KSCrashHang.h"

NS_ASSUME_NONNULL_BEGIN

@interface KSCrash (Hang)

/** Registers an observer to be notified of hang state changes.
 *
 * The observer block will be called when:
 * - A hang is first detected (KSHangChangeTypeStarted)
 * - An ongoing hang's duration is updated (KSHangChangeTypeUpdated)
 * - A hang ends and the main thread becomes responsive (KSHangChangeTypeEnded)
 *
 * @note This method requires `KSCrashMonitorTypeWatchdog` to be enabled in your
 *       KSCrash configuration. If the watchdog monitor is not enabled, this method
 *       returns `nil` and no observations will occur.
 *
 * @param observer The block to call when hang state changes occur.
 * @return An opaque token object that keeps the observer registered, or `nil` if the
 *         watchdog monitor is not enabled. The observer remains registered as long as
 *         this token is retained. Release it to unregister the observer.
 */
- (id _Nullable)addHangObserver:(KSHangObserverBlock)observer;

@end

NS_ASSUME_NONNULL_END
