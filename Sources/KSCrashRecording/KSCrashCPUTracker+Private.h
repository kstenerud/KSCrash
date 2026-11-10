//
//  KSCrashCPUTracker+Private.h
//
//  Created by Alexander Cohen on 2026-11-08.
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

#import "KSCrashCPUTracker.h"

NS_ASSUME_NONNULL_BEGIN

@interface KSCrashCPUTracker ()

/** For tests. Runs one tick on the tracker's queue, the same poll and observer notification the
 *  timer runs. The timer fires every few seconds at utility QoS, so a test that waits for it waits
 *  on the scheduler as well.
 *
 *  @param wait YES to return only after the observers have been called, NO to queue the tick and
 *              return at once. Waiting is safe from an observer, which already runs on the queue.
 */
- (void)tickWaitingUntilDone:(BOOL)wait;

@end

NS_ASSUME_NONNULL_END
