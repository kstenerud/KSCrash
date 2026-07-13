//
//  KSCrashSessionLog.h
//
//  Created by Alexander Cohen on 2026-07-09.
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

/* Growable per-run session log.
 *
 * The Lifecycle monitor's mmap'd sidecar is a fixed-size struct — it holds the
 * session *counts* but not one record per session. This is the companion
 * variable-length store: an ordered stream of session/user events, one appended
 * as each event happens, so the previous run's summary can carry each session
 * with its own start/end time and the user(s) active during it.
 *
 * Crash-safety: every event here (a foreground/background transition, a user
 * change) happens during normal runtime, never in a crash/signal handler, so
 * the writer is plain buffered I/O. Durability against an abnormal termination
 * comes from a header commit marker: a record's bytes are written first, then
 * the header's committed size/count are published in a single small write. A
 * reader trusts only the committed region, so a record that was mid-write when
 * the process died sits past the committed size and is ignored.
 *
 * One writer instance owns the run's log; it keeps its own file handle, commit
 * offsets, and lock, so there is no shared module state. Reading is a class
 * method that replays the log straight into the per-session RunSummary list.
 */

#import <Foundation/Foundation.h>

#import "KSCrashNamespace.h"

@class KSCrashRunSummarySession;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(SessionLog)
__attribute__((objc_subclassing_restricted))
@interface KSCrashSessionLog : NSObject

/// Open (creating and truncating) a session log for writing at @c path. One
/// instance per run. Returns nil if the file can't be created.
- (nullable instancetype)initForWritingAtPath:(NSString *)path;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Append and commit a session-begin event. @c perceptible marks a foreground
/// reach (true) vs a background entry (false). @c monotonicNs is the event time
/// on the caller's monotonic clock. Thread-safe.
- (BOOL)recordSessionBeginWithID:(NSString *)sessionID perceptible:(BOOL)perceptible monotonicNs:(uint64_t)monotonicNs;

/// Append and commit a user-change event. Thread-safe.
- (BOOL)recordUserID:(NSString *)userID monotonicNs:(uint64_t)monotonicNs;

/// Close the underlying file. Also happens on dealloc.
- (void)close;

/// Replay the committed log at @c path into an ordered list of sessions, each
/// with its start/end time and the user(s) active during it. Event times are
/// converted from the log's monotonic clock to unix epoch milliseconds using
/// the run's anchor (@c wallClockAtStartNs / @c monotonicAtStartNs, captured
/// together at sidecar creation); the last open session ends at @c runEndedAtMs.
/// Tolerates a torn tail. Returns an empty array for a missing, invalid, or
/// empty log.
+ (NSArray<KSCrashRunSummarySession *> *)sessionsAtPath:(NSString *)path
                                     wallClockAtStartNs:(uint64_t)wallClockAtStartNs
                                     monotonicAtStartNs:(uint64_t)monotonicAtStartNs
                                           runEndedAtMs:(int64_t)runEndedAtMs;

@end

NS_ASSUME_NONNULL_END
