//
//  KSHang.h
//
//  Created by Alexander Cohen on 2025-12-08.
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

#import <mach/task_policy.h>

#import "KSCrashNamespace.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Internal model representing a hang event.
 *
 * This class captures the state of a detected hang, including timestamps
 * and task roles at the start and end of the hang period.
 */
@interface KSHang : NSObject <NSCopying>

/** Monotonic timestamp (in nanoseconds) when the hang started. */
@property(nonatomic) uint64_t timestamp;

/** Task role when the hang started. */
@property(nonatomic) task_role_t role;

/** Monotonic timestamp (in nanoseconds) of the current/end state. */
@property(nonatomic) uint64_t endTimestamp;

/** Task role at the current/end state. */
@property(nonatomic) task_role_t endRole;

/** The report ID assigned to this hang. */
@property(nonatomic) int64_t reportId;

/** Path to the crash report file on disk. */
@property(nonatomic, copy, nullable) NSString *path;

/** Decoded crash report dictionary for in-memory updates. */
@property(nonatomic, strong, nullable) NSMutableDictionary *decodedReport;

/**
 * Initializes a new hang with the given start timestamp and role.
 *
 * @param timestamp The monotonic timestamp when the hang was detected.
 * @param role The task role at the time of detection.
 * @return A new KSHang instance.
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp role:(task_role_t)role;

/**
 * Returns the duration of the hang in seconds.
 *
 * @return The interval between endTimestamp and timestamp in seconds.
 */
- (NSTimeInterval)interval;

@end

NS_ASSUME_NONNULL_END
