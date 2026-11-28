//
//  KSCrash+Private.h
//
//  Created by Gleb Linnik on 11.06.2024.
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

#ifndef KSCrash_Private_h
#define KSCrash_Private_h

#import "KSCrash.h"
#import "KSCrashError.h"
#import "KSCrashMonitor_NSException+Private.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

NSString *kscrash_getBundleName(void);
NSString *_Nullable kscrash_getDefaultInstallPath(void);

/** Link anchors, one per KSCrash category that lives in its own source file.
 *
 * A category defines no linker symbols, so a static linker only loads a
 * category-only object file from an archive when the consumer passes -ObjC.
 * Without it the category methods are missing at runtime and calling one
 * raises "unrecognized selector".
 *
 * KSCrash.m references these anchors, so loading the KSCrash class also loads
 * every category. A new category file must define an anchor and add it to the
 * list in KSCrash.m.
 */
void kscrash_linkBacktraceCategory(void);
void kscrash_linkHangCategory(void);
void kscrash_linkNamespaceCategory(void);
void kscrash_linkUserInfoCategory(void);

#ifdef __cplusplus
}
#endif

@interface KSCrash ()

@property(nonatomic, readwrite, assign) NSUncaughtExceptionHandler *uncaughtExceptionHandler;

@property(nonatomic, assign) KSCrashCustomNSExceptionReporter *customNSExceptionReporter;

+ (nullable NSError *)errorForInstallErrorCode:(KSCrashInstallErrorCode)errorCode;

@end

NS_ASSUME_NONNULL_END

#endif /* KSCrash_Private_h */
