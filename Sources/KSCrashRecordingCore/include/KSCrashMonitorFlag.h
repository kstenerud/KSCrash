//
//  KSCrashMonitorProperty.h
//
//  Created by Gleb Linnik on 29.05.2024.
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

#ifndef KSCrashMonitorProperty_h
#define KSCrashMonitorProperty_h

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    /** Indicates that no flags are set. */
    KSCrashMonitorFlagNone = 0,

    /** Indicates that the program cannot continue execution if a monitor with this flag is triggered. */
    KSCrashMonitorFlagFatal = 1 << 0,

    /** Indicates that the monitor with this flag will not be enabled if a debugger is attached. */
    KSCrashMonitorFlagDebuggerUnsafe = 1 << 1,

    /** Indicates that the monitor is safe to be used in an asynchronous environment.
     * Monitors without this flag are considered unsafe for asynchronous operations by default. */
    KSCrashMonitorFlagAsyncSafe = 1 << 2,

} KSCrashMonitorFlag;

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitorProperty_h */
