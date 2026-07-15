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

/* Per-run session log stored as append-only JSON on disk.
 *
 * Records session begins and user-id changes for the run. Every event
 * survives process termination — no batching, no debouncing, no caps.
 * The log is metrics data: every event matters and the count is
 * unbounded. Note that "survives process termination" is not the same
 * as "survives power loss"; we don't `F_FULLFSYNC` on each write, so a
 * kernel crash or sudden power off can still lose events the OS hadn't
 * flushed to storage yet.
 *
 * ## Three invariants drive this shape
 *
 *   1. **Every event lands on disk before the writer returns.** No
 *      buffering in memory; a crash between the observation and the next
 *      event cannot lose the observation itself.
 *   2. **Reading at startup runs at memcpy speed.** KSCrash runs on the
 *      app's startup path and must not spend the app's ~400ms launch
 *      budget on parsing. In particular, the RunSummary raw-splice path
 *      does no JSON parse — it copies bytes and appends a closing
 *      suffix.
 *   3. **The log is unbounded.** Sessions and user changes are metrics;
 *      nothing may be dropped or capped.
 *
 * ## On-disk shape
 *
 * The file is intentionally not a complete JSON document. Every write
 * ends with a `\n` commit-delimiter; between the outer `[` and the last
 * `\n` the file is a sequence of session bodies whose tail session is
 * still open — its `users` array is unclosed, and the session object
 * itself is missing its `ended_at_ms` field and closing `}`. Each write
 * is a single delta (one `write()` per event, ~50-300 bytes) that ends
 * with the delimiter.
 *
 * The reader (and the RunSummary raw-splice path) mmaps the file, cuts
 * off any bytes past the last `\n` (that tail belongs to a partial
 * write), and appends a fixed closing suffix — `],"ended_at_ms":<N>}]`
 * — that closes the tail session's users array, stamps its
 * `ended_at_ms`, and closes the outer array. The whole read-side
 * operation is memcpy + a ~30-byte append; no NSJSONSerialization on
 * the splice path.
 *
 * Total write cost across a run with N events is O(N). Total read cost
 * is O(file_size) with a memcpy constant.
 *
 * ## Ruled-out alternatives
 *
 * The following were considered and rejected. If a future change is
 * tempted to move back to one of these, one of the three invariants
 * above is being violated:
 *
 *   - **Rewrite the whole file on every event** (the previous shape).
 *     Simple, but O(N²) total bytes written across a run — real cost
 *     for apps with heavy session or user-change churn.
 *   - **JSONL append-only.** O(N) writes, but the reader has to parse
 *     each line to reconstruct sessions. Parse cost for thousands of
 *     records is milliseconds — non-trivial against the launch budget.
 *   - **Two-file split** (canonical JSON array + append-only user
 *     delta). Preserves memcpy startup only when the delta is empty. In
 *     the common case (any user change since the last session begin)
 *     it requires parsing the delta and reshaping the tail, costing
 *     1-3ms.
 *   - **Append without a commit delimiter.** Recovery would need to
 *     parse to find valid boundaries — which drops us back into parsing
 *     on the hot read path.
 *   - **Session or user-change caps.** Bounds file size but violates
 *     the "metrics, no bounds" invariant.
 *   - **Debounce or batch flushes.** Reduces write frequency but
 *     forfeits durability — events since the last flush are lost on
 *     crash.
 *   - **Move disk writes off the main thread.** Would return stale
 *     state to readers between the observation and the flush; the
 *     caller expects the log to reflect state immediately.
 *
 * ## Recovery
 *
 * If the process dies mid-`write()`, the file's tail past the last
 * `\n` may be a partial record. The reader truncates to the last `\n`
 * boundary and appends the closing suffix. `\n` cannot appear literally
 * inside a JSON string (Foundation encodes it as `\n`), so a `\n` in
 * the on-disk bytes is unambiguously a commit boundary — no chance of
 * mistaking the last byte of an in-flight write for a good stopping
 * point.
 *
 * ## Concurrency
 *
 * One writer instance owns the run's log; it keeps its own state and
 * lock, so there is no shared module state. Reading is a class method.
 */

#import <Foundation/Foundation.h>

#import "KSCrashNamespace.h"

@class KSCrashRunSummarySession;

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    NSRange committedRange;
    int64_t maxObservedTimestampMs;
    BOOL isValid;
    BOOL hasSessions;
} KSCrashSessionLogInspection;

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

/// Break the adjacent-user dedup so the next @c recordUserID: cannot be
/// suppressed by matching against the previously recorded id. Called by
/// the lifecycle monitor when the current user signs out: a subsequent
/// alice → nil → alice sequence must record alice's second activation
/// (the "at_ms when this user became active" contract), even though
/// alice is technically adjacent to alice in the id stream.
- (void)forgetLastUserID;

/// Stop accepting writes and release the underlying file descriptor. Also
/// called from @c dealloc.
- (void)close;

/// Decode the on-disk session log at @c path into KSCrashRunSummarySession
/// objects. Handles the append-only format's implicit closing suffix, and
/// returns an empty array for a missing or malformed file (so a leftover
/// binary Sessions.ksscr from an older SDK degrades to no per-session
/// detail rather than a crash).
+ (NSArray<KSCrashRunSummarySession *> *)sessionsAtPath:(NSString *)path;

/// Decode already-loaded on-disk bytes. Same behavior and recovery as
/// @c sessionsAtPath:. This lets @c KSCrashRunSummary retain a mapped
/// view whose lifetime is independent of sidecar cleanup.
+ (NSArray<KSCrashRunSummarySession *> *)sessionsFromData:(NSData *)data;

/// Inspect the last newline-committed range without allocating storage that
/// scales with @c data. Invalid committed bytes produce an invalid inspection.
+ (KSCrashSessionLogInspection)inspectionForData:(NSData *)data;

/// Splice a previously inspected log without scanning it again.
+ (void)appendSessionsJSONFromData:(NSData *)data
                        inspection:(KSCrashSessionLogInspection)inspection
                      runEndedAtMs:(int64_t)runEndedAtMs
                          toOutput:(NSMutableData *)output;

/// Return either the suffix that closes a valid non-empty inspection or the
/// complete empty array encoding for an invalid or empty inspection.
+ (NSData *)closingDataForInspection:(KSCrashSessionLogInspection)inspection runEndedAtMs:(int64_t)runEndedAtMs;

/// Splice on-disk session-log bytes into a wire-format `sessions` JSON
/// array in @c output. Trims to the last committed newline, appends
/// the closing suffix that finalizes the tail against @c runEndedAtMs
/// (floored against any observation still recorded in the log so a
/// user event cannot land past its session's end), and closes the
/// outer array. No JSON parse on this path; used by the RunSummary
/// raw-splice fast path. Appends @c "[]" on garbage or a file with no
/// committed events.
+ (void)appendSessionsJSONFromData:(NSData *)data runEndedAtMs:(int64_t)runEndedAtMs toOutput:(NSMutableData *)output;

/// Highest observed timestamp in @c data — max of every
/// `"started_at_ms":` and `"at_ms":` in the committed portion.
/// Zero if the log has no committed events. Callers use this to bump
/// the RunSummary's ended_at_ms when a user observation is more recent
/// than any monitor-observed transition (e.g. OOM shortly after a
/// user change with the resource monitor disabled).
+ (int64_t)maxObservedTimestampInData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
