//
//  KSCrashInstallationConsole.h
//  KSCrash-iOS
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

#import "KSCrashInstallation.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Prints all reports to the console.
 * This class is intended for testing purposes.
 */
NS_SWIFT_NAME(CrashInstallationConsole)
@interface KSCrashInstallationConsole : KSCrashInstallation

@property(nonatomic, readwrite) BOOL printAppleFormat;

@property(class, readonly) KSCrashInstallationConsole *sharedInstance NS_SWIFT_NAME(shared);

@end

NS_ASSUME_NONNULL_END
