//
//  KSSessionStore.c
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

#include "KSSessionStore.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "KSDate.h"
#include "KSFileUtils.h"
#include "KSID.h"
#include "KSLogger.h"

// ============================================================================
#pragma mark - On-disk format -
// ============================================================================
//
// Header, then one append-only entry per session open. Sessions are contiguous,
// so a session ends exactly where the next one begins; there is no separate
// close event. The reader sets each session's end to the next session's start,
// and leaves the final session (no successor: the run exited or crashed with it
// open) for the send path to close from the run summary. A torn trailing write
// is caught by the per-entry frame magic (and a short read at EOF) and stops the
// read, so everything before it still decodes.
//
// Timestamps are stored as CLOCK_MONOTONIC_RAW nanoseconds (continuous across
// sleep). The header captures a one-time (wall, monotonic) reference pair; the
// reader converts each start to epoch ms as wall + (entryMono - refMono). Only
// deltas of the writer's own clock are used, so conversion is valid even after
// a reboot (the reader never samples the clock itself).

#define KSSESSION_FILE_MAGIC ((uint32_t)'kssf')
#define KSSESSION_ENTRY_MAGIC ((uint32_t)'ksse')
#define KSSESSION_FILE_VERSION ((uint8_t)1)

// This file is only ever read on the device that wrote it (same build, same
// ABI); it is never a transport format, so packing and alignment don't matter.
// Fields are in natural order (magic first). memset zeroes whatever padding the
// compiler adds before the struct is written, and the size asserts flag a layout
// change so KSSESSION_FILE_VERSION gets bumped.
typedef struct {
    uint32_t magic;      // KSSESSION_FILE_MAGIC
    uint8_t version;     // KSSESSION_FILE_VERSION
    uint64_t wallRefNs;  // unix epoch ns at file creation
    uint64_t monoRefNs;  // CLOCK_MONOTONIC_RAW ns at file creation
} KSSessionFileHeader;

_Static_assert(sizeof(KSSessionFileHeader) == 24, "KSSessionFileHeader layout changed, bump KSSESSION_FILE_VERSION");

typedef struct {
    uint32_t magic;                        // KSSESSION_ENTRY_MAGIC
    uint8_t perceptible;                   //
    uuid_string_t guid;                    // uppercase UUID string (36 chars + NUL)
    uint64_t startMonoNs;                  // CLOCK_MONOTONIC_RAW ns at session open
    char user[KSSESSION_MAX_USER_LENGTH];  // empty == anonymous
} KSSessionEntry;

_Static_assert(sizeof(KSSessionEntry) == 184, "KSSessionEntry layout changed, bump KSSESSION_FILE_VERSION");

/** Cap on how much of a `.sessions` file the reader will ingest (~90k entries).
 *  A single run realistically produces orders of magnitude fewer; the cap only
 *  bounds a pathological or corrupt file. Past the cap the tail goes unread, so
 *  the last decoded entry is reported as still-open and its end reads long; only
 *  a corrupt file grows this large, so that is left as-is. */
#define KSSESSION_MAX_READ_BYTES (16 * 1024 * 1024)

// ============================================================================
#pragma mark - Writer -
// ============================================================================
//
// Not internally synchronized: the owner serializes access (see the header).

struct KSSessionWriter {
    int fd;       // append fd, opened lazily on the first write (-1 until then)
    bool broken;  // a write failed; the file's tail is unreliable, so stop writing
    char filePath[KSFU_MAX_PATH_LENGTH];
    uint64_t wallRefNs;  // reference pair written into the file header
    uint64_t monoRefNs;
    bool hasOpenSession;   // a session was durably written; openID names it
    bool pendingWrite;     // the intended (openPerceptible, openUser) is not yet durable (last write failed)
    uuid_string_t openID;  // last durable session id; kssw_current's borrowed return
    uint64_t openMonoNs;
    bool openPerceptible;                      // current *intended* perceptibility (advances even on a failed write)
    char openUser[KSSESSION_MAX_USER_LENGTH];  // current *intended* user (advances even on a failed write)
};

/** Append one session entry, opening the file (and writing its header) on first
 *  use. Returns false if anything fails to write; once that happens the writer
 *  is marked broken and refuses further writes, because a torn or headerless
 *  tail would make the rest of the file unreadable anyway. */
static bool appendSession(KSSessionWriter *writer, const char *guid, uint64_t startMonoNs, bool perceptible,
                          const char *user)
{
    if (writer->broken) {
        return false;
    }
    if (writer->fd < 0) {
        writer->fd = open(writer->filePath, O_WRONLY | O_APPEND | O_CREAT, 0644);
        if (writer->fd < 0) {
            KSLOG_ERROR("Failed to open session file %s", writer->filePath);
            return false;  // may be transient (missing dir, perms); retried next time
        }
        // Keep the file writable while the device is locked (iOS data protection);
        // otherwise a locked-device append would fail and permanently break the writer.
        ksfu_applyNoFileProtection(writer->filePath);
        // Write the header only into a freshly created (empty) file; a unique
        // per-run id means this is normally always the case.
        struct stat st;
        if (fstat(writer->fd, &st) != 0) {
            // Unknown file state: an entry appended to a possibly headerless
            // file makes the whole file unreadable, so stop writing instead.
            KSLOG_ERROR("Failed to stat session file %s", writer->filePath);
            goto failed_broken;
        }
        if (st.st_size == 0) {
            KSSessionFileHeader header;
            memset(&header, 0, sizeof(header));
            header.magic = KSSESSION_FILE_MAGIC;
            header.version = KSSESSION_FILE_VERSION;
            header.wallRefNs = writer->wallRefNs;
            header.monoRefNs = writer->monoRefNs;
            if (!ksfu_writeBytesToFD(writer->fd, (const char *)&header, (int)sizeof(header))) {
                // No header means the reader rejects the whole file; do not write
                // an entry onto it, and stop writing.
                KSLOG_ERROR("Failed to write session file header %s", writer->filePath);
                goto failed_broken;
            }
        }
    }

    KSSessionEntry entry;
    memset(&entry, 0, sizeof(entry));
    entry.magic = KSSESSION_ENTRY_MAGIC;
    entry.perceptible = perceptible ? 1 : 0;
    strlcpy(entry.guid, guid, sizeof(entry.guid));
    entry.startMonoNs = startMonoNs;
    if (user != NULL) {
        strlcpy(entry.user, user, sizeof(entry.user));
    }
    if (!ksfu_writeBytesToFD(writer->fd, (const char *)&entry, (int)sizeof(entry))) {
        KSLOG_ERROR("Failed to append session entry to %s", writer->filePath);
        goto failed_broken;
    }
    return true;

failed_broken:
    writer->broken = true;
    return false;
}

KSSessionWriter *kssw_open(const char *path)
{
    if (path == NULL || path[0] == '\0') {
        return NULL;  // a writer needs somewhere to write
    }
    KSSessionWriter *writer = (KSSessionWriter *)calloc(1, sizeof(KSSessionWriter));
    if (writer == NULL) {
        return NULL;
    }
    writer->fd = -1;
    writer->monoRefNs = ksdate_continuousNanoseconds();
    writer->wallRefNs = ksdate_wallClockNanoseconds();
    strlcpy(writer->filePath, path, sizeof(writer->filePath));
    return writer;
}

/** Copy `src` into `dst` (size `dstSize`), truncating on a UTF-8 code-point
 *  boundary so a multibyte character is never split. Assumes valid UTF-8 input;
 *  a character straddling the limit (e.g. an emoji) is dropped whole, so the
 *  reader never hands the JSON send path malformed UTF-8. */
static void copyUtf8Truncated(char *dst, const char *src, size_t dstSize)
{
    if (dstSize == 0) {
        return;
    }
    size_t n = strnlen(src, dstSize);
    size_t max = dstSize - 1;
    if (n > max) {
        n = max;
        // If the first dropped byte is a continuation byte (10xxxxxx) we cut
        // mid-character; back up to that character's lead byte and drop it.
        if (((unsigned char)src[n] & 0xC0) == 0x80) {
            while (n > 0 && ((unsigned char)src[n] & 0xC0) == 0x80) {
                n--;
            }
        }
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

/** Cut a new session for `(perceptible, user)` if it differs from the open one.
 *  `user` is already normalized (NULL-free, UTF-8-safe truncated). Returns the
 *  new id, or NULL on a no-op or a failed write. */
static const char *reconcileSession(KSSessionWriter *writer, bool perceptible, const char *user)
{
    // openPerceptible/openUser are the current *intended* (perceptible, user):
    // they advance even when a write fails, so a later update of the OTHER
    // dimension still carries the intended value (a failed setUserID isn't lost).
    // pendingWrite marks that intended tuple as not-yet-durable, which also forces
    // the next call to retry the write. openID/hasOpenSession name the last
    // session that IS in the file (what kssw_current returns) and never advance on
    // a failed write.
    if (writer->hasOpenSession && !writer->pendingWrite && writer->openPerceptible == perceptible &&
        strncmp(writer->openUser, user, sizeof(writer->openUser)) == 0) {
        return NULL;  // already the durable open session
    }

    // Advance the intended tuple before writing so a failure still carries it.
    writer->openPerceptible = perceptible;
    strlcpy(writer->openUser, user, sizeof(writer->openUser));

    uuid_string_t newID;
    ksid_generate(newID);
    uint64_t now = ksdate_continuousNanoseconds();
    if (!appendSession(writer, newID, now, perceptible, user)) {
        // Not durable: keep the previous session as kssw_current's answer (the
        // report never names a session not in the file) and retry next time.
        writer->pendingWrite = true;
        return NULL;
    }

    strlcpy(writer->openID, newID, sizeof(writer->openID));
    writer->openMonoNs = now;
    writer->hasOpenSession = true;
    writer->pendingWrite = false;
    return writer->openID;
}

const char *kssw_update(KSSessionWriter *writer, bool perceptible, const char *userID)
{
    if (writer == NULL) {
        return NULL;
    }
    // Normalize (NULL -> "", UTF-8-safe truncate) up front so the change check
    // compares the stored, already-truncated user against an identically-
    // truncated value; a userID longer than the buffer must not re-cut a session
    // on every update.
    char user[KSSESSION_MAX_USER_LENGTH];
    copyUtf8Truncated(user, (userID != NULL) ? userID : "", sizeof(user));
    return reconcileSession(writer, perceptible, user);
}

const char *kssw_updateUser(KSSessionWriter *writer, const char *userID)
{
    if (writer == NULL) {
        return NULL;
    }
    // Only the user is changing: keep the open session's perceptibility. This is
    // why the caller never has to fetch perceptibility (and so can't read a stale
    // value that races a concurrent perceptibility change).
    char user[KSSESSION_MAX_USER_LENGTH];
    copyUtf8Truncated(user, (userID != NULL) ? userID : "", sizeof(user));
    return reconcileSession(writer, writer->openPerceptible, user);
}

const char *kssw_updatePerceptible(KSSessionWriter *writer, bool perceptible)
{
    if (writer == NULL) {
        return NULL;
    }
    // Only perceptibility is changing: keep the open session's user (already
    // normalized when stored). Copy it to a local first — reconcileSession
    // strlcpy's `user` back into writer->openUser, and strlcpy with overlapping
    // src/dst is undefined.
    char user[KSSESSION_MAX_USER_LENGTH];
    strlcpy(user, writer->openUser, sizeof(user));
    return reconcileSession(writer, perceptible, user);
}

const char *kssw_current(const KSSessionWriter *writer)
{
    if (writer == NULL || !writer->hasOpenSession) {
        return NULL;
    }
    return writer->openID;
}

void kssw_close(KSSessionWriter *writer)
{
    if (writer == NULL) {
        return;
    }
    if (writer->fd >= 0) {
        close(writer->fd);
        writer->fd = -1;
    }
    free(writer);
}

// ============================================================================
#pragma mark - Reader -
// ============================================================================

struct KSSessionReader {
    KSSessionRecord *records;  // owned; freed on close
    int recordCount;
    int lastError;  // errno when the file existed but could not be read; else 0
};

/** readFileHead outcome: data read, nothing to read, unreadable, or OOM. */
typedef enum {
    KSSESSION_READ_OK = 0,     // buffer allocated and filled
    KSSESSION_READ_NONE = 1,   // absent / empty: zero sessions, not a failure
    KSSESSION_READ_ERROR = 2,  // file exists but could not be read: errno in *outError
    KSSESSION_READ_OOM = -1,   // allocation failed: propagate as a reader-open failure
} KSSessionReadResult;

/** Read up to `maxBytes` from the START of `path` into a malloc'd buffer (caller
 *  frees on OK). ksfu_readEntireFile's cap reads the file's TAIL, which for an
 *  oversized session file would begin mid-entry and lose the header; reading the
 *  head keeps the header and the oldest entries. Logs when it truncates. */
static KSSessionReadResult readFileHead(const char *path, char **outData, int *outLength, int maxBytes, int *outError)
{
    *outData = NULL;
    *outLength = 0;
    *outError = 0;
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        // Only a missing file means "no sessions"; any other failure (perms,
        // descriptor pressure, I/O) means the sessions are unknown, which the
        // caller must not confuse with absent.
        if (errno == ENOENT) {
            return KSSESSION_READ_NONE;
        }
        *outError = errno != 0 ? errno : EIO;
        return KSSESSION_READ_ERROR;
    }
    struct stat st;
    if (fstat(fd, &st) != 0) {
        *outError = errno != 0 ? errno : EIO;
        close(fd);
        return KSSESSION_READ_ERROR;
    }
    if (st.st_size <= 0) {
        close(fd);
        return KSSESSION_READ_NONE;
    }
    int toRead = st.st_size > (off_t)maxBytes ? maxBytes : (int)st.st_size;
    if (st.st_size > (off_t)maxBytes) {
        KSLOG_ERROR("Session file %s is %lld bytes; decoding only the first %d", path, (long long)st.st_size, maxBytes);
    }
    char *mem = (char *)malloc((size_t)toRead);
    if (mem == NULL) {
        close(fd);
        return KSSESSION_READ_OOM;
    }
    bool ok = ksfu_readBytesFromFD(fd, mem, toRead);
    if (!ok) {
        *outError = errno != 0 ? errno : EIO;
        close(fd);
        free(mem);
        return KSSESSION_READ_ERROR;
    }
    close(fd);
    *outData = mem;
    *outLength = toRead;
    return KSSESSION_READ_OK;
}

/** Decode `path` into reader->records / reader->recordCount, stopping at the
 *  first torn or content-corrupt entry (bad magic, empty id, an unconvertible
 *  start, or a non-monotonic start) and keeping the valid prefix. Returns false
 *  ONLY on an allocation failure (so kssr_open can honor its NULL-on-OOM
 *  contract); a missing/short/invalid-header file is a success with zero
 *  sessions. */
static bool decodeFile(KSSessionReader *reader, const char *path)
{
    char *data = NULL;
    int length = 0;
    int readError = 0;
    KSSessionReadResult rr = readFileHead(path, &data, &length, KSSESSION_MAX_READ_BYTES, &readError);
    if (rr == KSSESSION_READ_OOM) {
        return false;
    }
    if (rr == KSSESSION_READ_ERROR) {
        reader->lastError = readError;
        return true;  // zero sessions, but flagged unknown rather than absent
    }
    if (rr != KSSESSION_READ_OK) {
        return true;  // nothing to read: zero sessions
    }
    if (length < (int)sizeof(KSSessionFileHeader)) {
        goto free_and_success;
    }

    KSSessionFileHeader header;
    memcpy(&header, data, sizeof(header));
    if (header.magic != KSSESSION_FILE_MAGIC || header.version != KSSESSION_FILE_VERSION || header.wallRefNs == 0 ||
        header.monoRefNs == 0) {
        goto free_and_success;
    }

    // Count the leading run of valid entries; stop at the first torn or
    // content-corrupt one (see the function contract). A start is "unconvertible"
    // when ksdate returns 0 (before the reference, or the conversion overflows).
    int entryCount = 0;
    uint64_t prevStart = 0;
    int off = (int)sizeof(KSSessionFileHeader);
    while (off + (int)sizeof(KSSessionEntry) <= length) {
        KSSessionEntry entry;
        memcpy(&entry, data + off, sizeof(entry));
        if (entry.magic != KSSESSION_ENTRY_MAGIC || entry.guid[0] == '\0' ||
            ksdate_monotonicToWallClockNanoseconds(entry.startMonoNs, header.wallRefNs, header.monoRefNs) == 0 ||
            (entryCount > 0 && entry.startMonoNs < prevStart)) {
            break;
        }
        prevStart = entry.startMonoNs;
        entryCount++;
        off += (int)sizeof(KSSessionEntry);
    }

    if (entryCount == 0) {
        goto free_and_success;
    }

    KSSessionRecord *records = (KSSessionRecord *)calloc((size_t)entryCount, sizeof(KSSessionRecord));
    if (records == NULL) {
        goto free_and_failure;  // allocation failure
    }

    off = (int)sizeof(KSSessionFileHeader);
    for (int i = 0; i < entryCount; i++) {
        KSSessionEntry entry;
        memcpy(&entry, data + off, sizeof(entry));
        off += (int)sizeof(KSSessionEntry);

        KSSessionRecord *rec = &records[i];
        // Bounded copies: a corrupt on-disk guid/user need not be NUL-terminated.
        memcpy(rec->guid, entry.guid, sizeof(rec->guid));
        rec->guid[sizeof(rec->guid) - 1] = '\0';
        memcpy(rec->user, entry.user, sizeof(rec->user));
        rec->user[sizeof(rec->user) - 1] = '\0';
        rec->startedAtMs =
            (int64_t)(ksdate_monotonicToWallClockNanoseconds(entry.startMonoNs, header.wallRefNs, header.monoRefNs) /
                      1000000ULL);
        rec->perceptible = entry.perceptible != 0;
    }
    free(data);

    // Each session ends where the next begins; the final one has no successor,
    // so its end is left for the send path to fill from the run summary.
    for (int i = 0; i < entryCount - 1; i++) {
        records[i].endedAtMs = records[i + 1].startedAtMs;
        records[i].endInferred = false;
    }
    records[entryCount - 1].endedAtMs = 0;
    records[entryCount - 1].endInferred = true;

    reader->records = records;
    reader->recordCount = entryCount;
    return true;

free_and_success:
    free(data);
    return true;

free_and_failure:
    free(data);
    return false;
}

KSSessionReader *kssr_open(const char *path)
{
    KSSessionReader *reader = (KSSessionReader *)calloc(1, sizeof(KSSessionReader));
    if (reader == NULL) {
        return NULL;
    }
    if (path != NULL && path[0] != '\0' && !decodeFile(reader, path)) {
        kssr_close(reader);  // allocation failure: honor the NULL-on-OOM contract
        return NULL;
    }
    return reader;
}

int kssr_count(const KSSessionReader *reader) { return reader != NULL ? reader->recordCount : 0; }

int kssr_lastError(const KSSessionReader *reader) { return reader != NULL ? reader->lastError : 0; }

bool kssr_sessionAt(const KSSessionReader *reader, int index, KSSessionRecord *out)
{
    if (reader == NULL || out == NULL || index < 0 || index >= reader->recordCount) {
        return false;
    }
    *out = reader->records[index];
    return true;
}

void kssr_close(KSSessionReader *reader)
{
    if (reader == NULL) {
        return;
    }
    free(reader->records);
    free(reader);
}

// ============================================================================
#pragma mark - Test hooks -
// ============================================================================

void kssession_testcode_appendRawEntry(const char *path, uint64_t startMonoNs, bool perceptible, const char *guid,
                                       const char *user, bool userWithoutNul)
{
    int fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (fd < 0) {
        return;
    }
    KSSessionEntry entry;
    memset(&entry, 0, sizeof(entry));
    entry.magic = KSSESSION_ENTRY_MAGIC;
    entry.perceptible = perceptible ? 1 : 0;
    entry.startMonoNs = startMonoNs;
    if (guid != NULL) {
        strlcpy(entry.guid, guid, sizeof(entry.guid));
    }
    if (userWithoutNul) {
        memset(entry.user, 'A', sizeof(entry.user));  // 128 non-NUL bytes, no terminator
    } else if (user != NULL) {
        strlcpy(entry.user, user, sizeof(entry.user));
    }
    ksfu_writeBytesToFD(fd, (const char *)&entry, (int)sizeof(entry));
    close(fd);
}
