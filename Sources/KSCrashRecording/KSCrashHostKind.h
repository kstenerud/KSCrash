//
//  KSCrashHostKind.h
//
//  Created by Alexander Cohen on 2026-11-21.
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

#ifndef HDR_KSCrashHostKind_h
#define HDR_KSCrashHostKind_h

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** The kind of process KSCrash runs in. The values are stored in the lifecycle
 *  sidecar for the next run to read, so they never change. */
typedef enum {
    KSCrashHostKindApp = 0,
    KSCrashHostKindExtension,
    KSCrashHostKindXCTest,
    KSCrashHostKindOther,
} KSCrashHostKind;

/** The kind of this process, decided once per process from its executable's path.
 *
 *  Never asks NSBundle, so it is cheap at any point of startup, install included.
 *
 *  @return This process's host kind.
 */
KSCrashHostKind kshostkind_current(void);

/** The host kind an executable at a given path belongs to. Exposed for tests;
 *  `kshostkind_current` is this applied to the running executable.
 *
 *  @param path The executable's path, NUL-terminated.
 *
 *  @return The host kind of the bundle the executable is the main executable of.
 */
KSCrashHostKind kshostkind_forExecutablePath(const char *path);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashHostKind_h
