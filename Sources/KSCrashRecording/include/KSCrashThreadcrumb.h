//
//  KSCrashThreadcrumb.h
//
//  Created by Alexander Cohen on 2026-02-03.
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
// Inspired by:
// - Embrace EMBThreadcrumb: https://github.com/embrace-io/embrace-apple-sdk
// - Naftaly Threadcrumb: https://github.com/naftaly/Threadcrumb
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Maximum message length (characters) before truncation.
FOUNDATION_EXPORT NSInteger const KSCrashThreadcrumbMaximumMessageLength;

/**
 * Encodes a short message into a thread's call stack so it can be recovered
 * from crash reports via symbolication.
 *
 * Each allowed character (A-Z, a-z, 0-9, _) maps to a unique function symbol.
 * When `log:` is called, functions are chained to shape the stack so it mirrors
 * the message. The stack is captured, then the thread parks until the next request.
 *
 * Usage:
 * ```
 * KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
 * NSArray<NSNumber *> *addresses = [crumb log:@"ABC123"];
 * // addresses contains return addresses for each character frame
 * ```
 *
 * The stack can later be decoded by symbolication - each frame's symbol name
 * contains the encoded character (e.g., `__kscrash__A__`, `__kscrash__B__`).
 */
@interface KSCrashThreadcrumb : NSObject

/**
 * Initialize with an identifier used as the thread name.
 *
 * @param identifier A string to use as the thread name (e.g., "com.kscrash.metrickit").
 *                   If nil or empty, a default name is used.
 */
- (instancetype)initWithIdentifier:(NSString *)identifier NS_DESIGNATED_INITIALIZER;

/**
 * Log a message by encoding it into the thread's call stack.
 *
 * @param message The message to encode. Only [A-Za-z0-9_] are kept; others are stripped.
 *                Truncated to KSCrashThreadcrumbMaximumMessageLength if too long.
 *
 * @return An array of NSNumber (uint64) containing the stack frame return addresses,
 *         pruned of runtime frames. These addresses can be hashed to create a
 *         unique identifier for sidecar file lookup.
 */
- (NSArray<NSNumber *> *)log:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
