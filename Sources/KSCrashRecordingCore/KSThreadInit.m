//
//  KSThreadInit.m
//
//  Created by Alexander Cohen on 2026-02-02.
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
#import <pthread.h>

extern void ksthread_storeMainThread(void);

// Captures the main thread's mach port as early as possible so that
// ksthread_main() can return it later from any context (including
// signal handlers).  A library constructor is used instead of +load
// because it doesn't depend on the ObjC runtime's class registration
// order.  Constructors normally run on the main thread, but if the
// library is loaded dynamically (e.g. via dlopen on a background
// thread) we fall back to dispatch_async to ensure the store always
// happens on the main thread.
__attribute__((constructor(101), used, visibility("default"))) static void ksthread_init(void)
{
    if (pthread_main_np()) {
        ksthread_storeMainThread();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            ksthread_storeMainThread();
        });
    }
}
