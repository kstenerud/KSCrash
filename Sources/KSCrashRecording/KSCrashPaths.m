//
//  KSCrashPaths.m
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

#import <Foundation/Foundation.h>

#import "KSCrashC.h"
#import "KSCrashNamespace.h"

// The namespaced per-process directories the C API hands out, resolved once.

static const char *kscrash_namespacedSearchPath(NSSearchPathDirectory directory)
{
    NSArray *directories = NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
    if ([directories count] == 0) {
        return NULL;
    }
    NSString *basePath = [directories objectAtIndex:0];
    if ([basePath length] == 0) {
        return NULL;
    }
    NSString *path = [basePath stringByAppendingPathComponent:KSCRASH_NS_STRING(@"KSCrash")];
    return strdup(path.UTF8String);
}

const char *kscrash_documentsPath(void)
{
    static const char *path = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = kscrash_namespacedSearchPath(NSDocumentDirectory);
    });
    return path;
}

const char *kscrash_applicationSupportPath(void)
{
    static const char *path = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = kscrash_namespacedSearchPath(NSApplicationSupportDirectory);
    });
    return path;
}

const char *kscrash_cachesPath(void)
{
    static const char *path = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = kscrash_namespacedSearchPath(NSCachesDirectory);
    });
    return path;
}
