//
//  KSCrashHostKind.c
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

#include "KSCrashHostKind.h"

#include <dispatch/dispatch.h>
#include <mach-o/dyld.h>
#include <stdbool.h>
#include <string.h>
#include <strings.h>
#include <sys/syslimits.h>

static bool hasSuffix(const char *string, size_t length, const char *suffix)
{
    size_t suffixLength = strnlen(suffix, PATH_MAX);
    return length >= suffixLength && strncmp(string + length - suffixLength, suffix, suffixLength) == 0;
}

static bool hasExtension(const char *string, size_t length, const char *extension)
{
    size_t extensionLength = strnlen(extension, PATH_MAX);
    return length >= extensionLength && strncasecmp(string + length - extensionLength, extension, extensionLength) == 0;
}

KSCrashHostKind kshostkind_forExecutablePath(const char *path)
{
    // The same answer NSBundle's main bundle gives, from the path alone: the executable is the
    // bundle's main executable when it sits at <bundle>/<name> (iOS, tvOS, watchOS, visionOS) or
    // <bundle>/Contents/MacOS/<name> (macOS, Mac Catalyst). Anything else, such as a helper tool
    // elsewhere inside an app or a test runner, is not a bundle's main executable.
    const char *lastSlash = strrchr(path, '/');
    if (lastSlash == NULL) {
        return KSCrashHostKindOther;
    }
    size_t bundleLength = (size_t)(lastSlash - path);
    if (hasSuffix(path, bundleLength, "/Contents/MacOS")) {
        bundleLength -= strnlen("/Contents/MacOS", PATH_MAX);
    }
    if (hasExtension(path, bundleLength, ".appex")) {
        return KSCrashHostKindExtension;
    }
    if (hasExtension(path, bundleLength, ".app")) {
        return KSCrashHostKindApp;
    }
    if (hasExtension(path, bundleLength, ".xctest")) {
        return KSCrashHostKindXCTest;
    }
    return KSCrashHostKindOther;
}

// The executable cannot change during a run, so the path is read once. Never from NSBundle: the
// first caller runs in install, where asking NSBundle can be the process's first touch of the main
// bundle and costs milliseconds of launch.
KSCrashHostKind kshostkind_current(void)
{
    static KSCrashHostKind sKind = KSCrashHostKindOther;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char path[PATH_MAX];
        uint32_t size = sizeof(path);
        if (_NSGetExecutablePath(path, &size) == 0) {
            sKind = kshostkind_forExecutablePath(path);
        }
    });
    return sKind;
}
