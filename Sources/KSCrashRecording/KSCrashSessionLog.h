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

/* Per-run session log stored as JSON on disk.
 *
 * The Lifecycle monitor's mmap'd sidecar carries the session *counts* but not
 * one record per session. This companion file holds the itemized view: an
 * ordered array of session objects, each with its own start/end time and the
 * user(s) active during it. The on-disk shape matches the `sessions` array in
 * the persisted RunSummary JSON, so the next launch's install path can splice
 * these bytes straight into the `.run` file with no parse-and-re-encode.
 *
 * Durability: every mutating call rewrites the whole file via an atomic
 * temp+rename, so the file on disk is always either the last committed state
 * or the previous one, never torn. Crash safety is inherited from that
 * atomicity — no commit markers, no header.
 *
 * One writer instance owns the run's log; it keeps its own in-memory session
 * list and lock, so there is no shared module state. Reading is a class
 * method that decodes the JSON into KSCrashRunSummarySession objects.
 */

#import <Foundation/Foundation.h>

#import "KSCrashNamespace.h"

@class KSCrashRunSummarySession;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(SessionLog)
__attribute__((objc_subclassing_restricted))
@interface KSCrashSessionLog : NSObject

/// Open (creating and truncating) a session log for writing at @c path. One
/// instance per run. Returns nil if @c path is empty or the file can't be
/// created.
- (nullable instancetype)initForWritingAtPath:(NSString *)path;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Close the currently-open session (if any) at @c atMs, then open a new one
/// with @c userID (if non-empty) already attached. @c atMs is unix epoch
/// milliseconds; the caller has the anchor (lifecycle sidecar's
/// @c wallClockAtStartNs / @c monotonicAtStartNs) and converts.
- (BOOL)recordSessionBeginWithID:(NSString *)sessionID
                     perceptible:(BOOL)perceptible
                            atMs:(int64_t)atMs
                          userID:(nullable NSString *)userID;

/// Attach a user-id change to the currently-open session. No-op (returns NO)
/// if no session is open — user changes observed before the first session
/// begin are dropped, and the first session's user is carried in via
/// @c recordSessionBeginWithID:perceptible:atMs:userID: instead.
- (BOOL)recordUserID:(NSString *)userID atMs:(int64_t)atMs;

/// Flush any pending state and stop accepting writes. Also called from
/// @c dealloc.
- (void)close;

/// Decode the JSON session log at @c path into KSCrashRunSummarySession
/// objects. Returns an empty array for a missing or malformed file (so a v1
/// binary Sessions.ksscr from an older SDK degrades to no per-session detail
/// rather than a crash).
+ (NSArray<KSCrashRunSummarySession *> *)sessionsAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
