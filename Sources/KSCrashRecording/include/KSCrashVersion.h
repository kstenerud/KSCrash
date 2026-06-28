//
//  KSCrashVersion.h
//
//  Created by Alexander Cohen on 2026-08-22.
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

#ifndef KSCrashVersion_h
#define KSCrashVersion_h

#ifdef __cplusplus
extern "C" {
#endif

/** The framework version as a number (major.minor) and as its string, e.g. 3.0 and "3.0.0". */
extern const double KSCrashFrameworkVersionNumber;
extern const unsigned char KSCrashFrameworkVersionString[];

/** Tests only: overwrite the run id, or clear it when @c runID is NULL.
 *
 * Install generates the run id once per process and `kscrash_clearRunID` is otherwise
 * irreversible, so a test that exercises clear-then-failed-load would strand every later test
 * in the process with an empty id. Declared here rather than in KSCrashC.h to keep it out of
 * the public surface.
 */
void kscrash_testcode_setRunID(const char *_Nullable runID);

#ifdef __cplusplus
}
#endif

#endif /* KSCrashVersion_h */
