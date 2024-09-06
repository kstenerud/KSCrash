//
//  KSCrashReportFilterAppleFmt.h
//
//  Created by Karl Stenerud on 2012-02-24.
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

#import "KSCrashReportFilter.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Affects how an Apple-style crash report is generated.
 *
 * KSCrashReporter reports contain symbolication data which can be used in place
 * of normal offsets when generating an Apple-style report. The report style you
 * should choose depends on what symbols will be present in the application,
 * and what information will be available for offline symbolication (e.g. with
 * Apple's symbolication tools).
 *
 * There are three levels of symbolication:
 *
 * - Unsymbolicated: Contains a base address and an offset.
 *                   e.g. 0x0000347a 0x1000 + 9338
 *
 * - Basic: Contains base address, method name, and an offset into the method.
 *          e.g. 0x372bd97e -[UIControl sendAction:to:forEvent:] + 38
 *
 * - Full: Similar to basic, but the offset is converted to a line number.
 *         e.g. 0x0000347a +[MyObject someMethod] (MyObject.m:21)
 *
 * Full symbolication can only be done (and is only useful) for your own code.
 * Full symbolication information is only available from the dSYM file that
 * matches your app, so it can only be retrieved by offline symbolication.
 * For dynamic libraries (such as libc, UIKit, Foundation, etc), only basic
 * symbolication is available (online or offline).
 *
 * All iOS devices have basic symbol information on-board for dynamic libraries
 * (such as libc, UIKit, Foundation, etc). It's recommended to symbolicate these
 * on the device as it's not guaranteed that the machine you're offline
 * symbolicating from will have the same version available (for example, having
 * symbols available for iOS 4.2 - 5.01, but not for iOS 4.0).
 *
 * App symbols are present only if you have set "Strip Style" in your build
 * settings to "Debugging Symbols" (which strips all debugging symbols, but
 * leaves basic symbol information intact). This increases your app's code
 * footprint by about 10%, but allows basic symbolication on the device.
 *
 * Choosing KSAppleReportStylePartiallySymbolicated symbolicates everything
 * except main executable entries so that you can use an offline symbolicator.
 * You will need a dsym file to symbolicate those entries.
 *
 * KSAppleReportStyleSymbolicatedSideBySide generates a best-of-both-worlds
 * report where everything is symbolicated, but any offsets in the main
 * executable will retain both their "unsymbolicated" and "symbolicated"
 * versions side-by-side so that an offline symbolicator can still parse the
 * line and determine the line numbers (provided you have a matching dsym file).
 *
 * In short, if you're not worried about line numbers, or you don't want to
 * do offline symbolication, go with KSAppleReportStyleSymbolicated.
 * If you DO care about line numbers, have the dsym file handy, and will be
 * symbolicating offline, use KSAppleReportStyleSymbolicatedSideBySide.
 */
typedef NS_ENUM(NSInteger, KSAppleReportStyle) {
    /** Leave all stack trace entries unsymbolicated. */
    KSAppleReportStyleUnsymbolicated,

    /** Symbolicate all stack trace entries except for those in the main
     * executable.
     */
    KSAppleReportStylePartiallySymbolicated,

    /** Symbolicate all stack trace entries, but for any in the main executable,
     * put both an unsymbolicated and a symbolicated entry side-by-side.
     */
    KSAppleReportStyleSymbolicatedSideBySide,

    /** Symbolicate everything. */
    KSAppleReportStyleSymbolicated
} NS_SWIFT_NAME(AppleReportStyle);

/** Converts to Apple format.
 *
 * Input: NSDictionary
 * Output: NSString
 */
NS_SWIFT_NAME(CrashReportFilterAppleFmt)
@interface KSCrashReportFilterAppleFmt : NSObject <KSCrashReportFilter>

/** Initialize with a specific Apple report style.
 * @param reportStyle The Apple report style to use for symbolication.
 * @return The initialized instance.
 * @see KSAppleReportStyle for detailed information on symbolication options.
 */
- (instancetype)initWithReportStyle:(KSAppleReportStyle)reportStyle;

/** Default initializer.
 * @return The initialized instance with KSAppleReportStyleSymbolicated.
 * @note This style symbolicates all stack trace entries.
 */
- (instancetype)init;

/** Generate a header string for the Apple-style crash report.
 * @param system Dictionary containing system information (e.g., device, OS, app details).
 * @param reportID Unique identifier for the crash report.
 * @param crashTime Timestamp of when the crash occurred.
 * @return Formatted header string including incident identifier, hardware model, process info, OS version, etc.
 */
- (NSString *)headerStringForSystemInfo:(NSDictionary<NSString *, id> *)system
                               reportID:(nullable NSString *)reportID
                              crashTime:(nullable NSDate *)crashTime;

@end

NS_ASSUME_NONNULL_END
