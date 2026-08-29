//
//  KSSessionStore.h
//
//  Created by Alexander Cohen on 2026-07-25.
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

/* Session storage.
 *
 * A *session* is a span over which (perceptible, user) is constant. A new
 * session is cut whenever perceptibility flips or the userID changes. Sessions
 * are persisted to an append-only file at a caller-supplied path.
 *
 * The store knows nothing about runs, directories, or naming; it just reads and
 * writes sessions at the path it is handed. Two disjoint objects front the file.
 * A live run's file can be decoded while its writer is active (delivery
 * stitches do this), so the store internally excludes appends and decodes from
 * each other; everything else is the caller's synchronization:
 *
 *   - KSSessionWriter records sessions and exposes the open one (its id feeds the
 *     crash report).
 *   - KSSessionReader decodes a file for the send path.
 *
 * Neither is internally synchronized. The owner serializes access (the Lifecycle
 * monitor already serializes its state). None of it runs at crash time.
 */

#ifndef HDR_KSSessionStore_h
#define HDR_KSSessionStore_h

#include <stdbool.h>
#include <stdint.h>
#include <uuid/uuid.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Max stored userID length (including NUL). Longer ids are truncated. */
#define KSSESSION_MAX_USER_LENGTH 128

typedef struct KSSessionWriter KSSessionWriter;
typedef struct KSSessionReader KSSessionReader;

/** One session, timestamps in epoch milliseconds. An all-zero record (empty
 *  `guid`) means "no session" (e.g. kssw_current with nothing open).
 */
typedef struct {
    uuid_string_t guid;                    // lowercase UUID string (36 chars + NUL)
    char user[KSSESSION_MAX_USER_LENGTH];  // empty string == anonymous
    int64_t startedAtMs;                   // unix epoch milliseconds
    int64_t endedAtMs;                     // unix epoch milliseconds; 0 while endInferred
    bool perceptible;
    bool endInferred;  // true for the still-open final session (no successor to
                       // bound its end); the send path fills endedAtMs
} KSSessionRecord;

// ============================================================================
#pragma mark - Writer -
// ============================================================================

/** Open a writer that appends sessions to `path` (created lazily on the first
 *  write; its directory must already exist). Returns NULL on a NULL/empty path
 *  or allocation failure.
 */
KSSessionWriter *kssw_open(const char *path);

/** Reconcile the writer to the current (perceptible, userID): if either differs
 *  from the open session (or none is open), close the open one and open a new
 *  one with a fresh id. `userID` NULL or "" means anonymous.
 *
 *  Returns the new session's id when a new one was cut, or NULL on a no-op. The
 *  returned pointer is borrowed from the writer and valid only until the next
 *  kssw_update / kssw_close on it; copy it to keep it. (Use kssw_current for the
 *  full record.)
 */
const char *kssw_update(KSSessionWriter *writer, bool perceptible, const char *userID);

/** Cut a new session for a userID change, keeping the open session's
 *  perceptibility. Use this when only the user changed so the caller never has
 *  to supply (or fetch) a perceptibility value. No-op if the user is unchanged.
 *  Same return contract as kssw_update.
 */
const char *kssw_updateUser(KSSessionWriter *writer, const char *userID);

/** Cut a new session for a perceptibility change, keeping the open session's
 *  user. Use this when only perceptibility changed (the caller already has the
 *  new value). No-op if perceptibility is unchanged. Same return contract as
 *  kssw_update.
 */
const char *kssw_updatePerceptible(KSSessionWriter *writer, bool perceptible);

/** The currently-open session's id, or NULL if none is open. Borrowed from the
 *  writer and valid only until the next kssw_update / kssw_close on it; copy it
 *  to keep it.
 */
const char *kssw_current(const KSSessionWriter *writer);

/** Close the writer, flushing and releasing its file. NULL-safe. */
void kssw_close(KSSessionWriter *writer);

// ============================================================================
#pragma mark - Reader -
// ============================================================================

/** Open a reader over the session file at `path`.
 *
 *  Decodes it immediately. The file holds one entry per session OPEN (there
 *  are no close events): each session's end is inferred from its successor's
 *  start, and the final session comes back still open (`endInferred`).
 *  Decoding stops at any torn trailing record. A missing or empty file yields
 *  a reader with zero sessions; an unreadable one also yields zero sessions
 *  but sets kssr_fileWasUnreadable. Returns NULL only on allocation failure.
 */
KSSessionReader *kssr_open(const char *path);

/** Number of sessions the reader decoded. */
int kssr_count(const KSSessionReader *reader);

/** The errno from the failed open or read when the file existed but could not
 *  be read; 0 when reading succeeded or the file was absent. Nonzero means the
 *  sessions are unknown rather than absent: a zero count must not be treated
 *  as "recorded none". */
int kssr_lastError(const KSSessionReader *reader);

/** Copy the session at `index` (0 ..< kssr_count) into `out`. Returns false when
 *  `index` is out of range.
 *
 *  A session the run died with still open comes back with `endInferred == true`
 *  and `endedAtMs == 0`; the send path fills its end from the run summary.
 */
bool kssr_sessionAt(const KSSessionReader *reader, int index, KSSessionRecord *out);

/** Close the reader, releasing its decoded sessions. NULL-safe. */
void kssr_close(KSSessionReader *reader);

// ============================================================================
#pragma mark - Test hooks -
// ============================================================================

/** Test-only: append a raw entry (bypassing validation) to an already-headered
 *  session file, so corruption/edge cases can be exercised. `userWithoutNul`
 *  fills the user field with non-NUL bytes to test the unterminated-string path.
 */
void kssession_testcode_appendRawEntry(const char *path, uint64_t startMonoNs, bool perceptible, const char *guid,
                                       const char *user, bool userWithoutNul);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSSessionStore_h
