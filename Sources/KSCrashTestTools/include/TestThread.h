//
//  TestThread.h
//
//  Created by Karl Stenerud on 2012-03-03.
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

#import <Foundation/Foundation.h>
#import <mach/mach_types.h>

@interface TestThread : NSThread

/** The mach thread, valid only once the thread is actually running. */
@property(atomic, readwrite, assign) thread_t thread;

/** Block until the thread is scheduled and `thread` is set.
 *
 * `thread` is assigned by the thread itself, so it stays MACH_PORT_NULL until
 * the OS gets round to running it. Sleeping a fixed interval instead is what
 * makes these tests fail on a loaded machine.
 *
 * @return YES if the thread came up before the timeout.
 */
- (BOOL)waitUntilRunningWithTimeout:(NSTimeInterval)timeout;

@end
