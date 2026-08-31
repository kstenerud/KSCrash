//
//  KSKeyValueStore.c
//
//  Created by Alexander Cohen on 2026-03-01.
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

#include "KSKeyValueStore.h"

// #define KSLogger_LocalLevel TRACE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "KSFileUtils.h"
#include "KSLogger.h"

// ============================================================================
#pragma mark - Internal Format -
// ============================================================================

/** Record type tags for the append-only log. Readers skip types they do
 *  not know (see dispatchRecord), so new types can be added without a
 *  version break and older readers keep working.
 */
typedef enum {
    KSKVSTypeRemoved = 0,
    KSKVSTypeString = 1,
    KSKVSTypeInt64 = 2,
    KSKVSTypeUInt64 = 3,
    KSKVSTypeDouble = 4,
    KSKVSTypeBool = 5,
    KSKVSTypeDate = 6,
    KSKVSTypeJSON = 7,
} KSKVSType;

/** Magic number: "kskv" in little-endian. */
#define KSKVS_MAGIC 0x6B736B76u

#define KSKVS_VERSION_1_0 1
#define KSKVS_CURRENT_VERSION KSKVS_VERSION_1_0

#define KSKVS_HEADER_SIZE 12
#define KSKVS_RECORD_HEADER_SIZE 5

#pragma pack(push, 1)
/** File header: magic (4) + version (4) + write cursor (4) = 12 bytes. */
typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t offset;
} KSKVSHeader;
#pragma pack(pop)

_Static_assert(sizeof(KSKVSHeader) == KSKVS_HEADER_SIZE, "KSKVSHeader must be 12 bytes");

#pragma pack(push, 1)
/** Record header: key_len (2) + type (1) + value_len (2) = 5 bytes. */
typedef struct {
    uint16_t keyLen;
    uint8_t type;
    uint16_t valueLen;
} KSKVSRecordHeader;
#pragma pack(pop)

_Static_assert(sizeof(KSKVSRecordHeader) == KSKVS_RECORD_HEADER_SIZE, "KSKVSRecordHeader must be 5 bytes");

// The codec refuses the container that would reach its limit, so the depth a
// stored value may carry is one less than what is left below the containers
// already open where it lands.
_Static_assert(KSKVS_MAX_VALUE_DEPTH == KSJSON_MAX_CONTAINER_DEPTH - KSKVS_VALUE_ENCODE_DEPTH - 1,
               "KSKVS_MAX_VALUE_DEPTH must track the JSON codec's container limit");

// ============================================================================
#pragma mark - Store Structure -
// ============================================================================

struct KSKeyValueStore {
    uint8_t *storage;
    uint32_t capacity;
    int fd;  // < 0 means read-only heap (KSKVSModeRead), >= 0 means mmap mode
    // Serializes this store's own writes. Appends need nothing wider: they
    // write past hdr->offset and publish by bumping it last, so a reader that
    // sees the new cursor sees a whole record. The one write below the cursor
    // is markLastRecordRemoved's stamp, a single type byte over a record whose
    // span does not change, which no reader can catch half applied.
    pthread_rwlock_t lock;
    // Set when a compaction that ran reclaimed nothing, cleared by an append,
    // which may have superseded an older record. Only consulted at the
    // capacity ceiling, where compacting again would cost a capacity-sized
    // calloc and the O(n^2) scan for a write that fails regardless.
    bool compactionIsFutile;
    // Value bytes an in-place removal stamped over since the last compaction.
    // Once a compaction has found nothing, these are the only bytes the next
    // one can free, so they are what decides whether it is worth running.
    uint32_t reclaimableBytes;
};

// Held while a store's image is restructured or loaded whole: compaction,
// the remap that grows it, creation's truncate-and-init, and the read-mode
// file load. Those are the operations that rewrite or resize bytes a reader
// may be part way through, and a reader shares no object with the writer (it
// opens the file by path), so the exclusion has to be process-wide. A report
// finalized during its own run reads the sidecar its own process is still
// writing, so this is a live case, not a theoretical one.
//
// Deliberately NOT taken by ordinary appends: doing so meant that reading one
// run's sidecar at send time, a multi-megabyte read, blocked every metadata
// write in the app, including writes to an unrelated store.
//
// Lock order: a store's own lock first, then this one. Nothing takes them the
// other way round.
//
// Deliberately not a file lock, which iOS punishes with 0xdead10cc when held
// across suspension.
static pthread_rwlock_t g_fileImageLock = PTHREAD_RWLOCK_INITIALIZER;

// ============================================================================
#pragma mark - Internal Helpers -
// ============================================================================

static KSKVSHeader *storeHeader(KSKeyValueStore *store) { return (KSKVSHeader *)store->storage; }

static const KSKVSHeader *storeHeaderConst(const KSKeyValueStore *store) { return (const KSKVSHeader *)store->storage; }

static void initHeader(uint8_t *buf)
{
    KSKVSHeader *hdr = (KSKVSHeader *)buf;
    hdr->magic = KSKVS_MAGIC;
    hdr->version = KSKVS_CURRENT_VERSION;
    hdr->offset = KSKVS_HEADER_SIZE;
}

/** The offset of the last record for `key`, or UINT32_MAX when the store
 *  never saw it. Last write wins, so the walk keeps the latest match rather
 *  than stopping at the first. Bounds are checked here: a trailing record the
 *  cursor does not cover ends the walk.
 */
static uint32_t findLastRecordOffset(const KSKeyValueStore *store, const char *key, uint16_t keyLen, uint32_t endPos)
{
    uint32_t found = UINT32_MAX;
    uint32_t pos = KSKVS_HEADER_SIZE;
    while (pos + KSKVS_RECORD_HEADER_SIZE <= endPos) {
        const KSKVSRecordHeader *rec = (const KSKVSRecordHeader *)(store->storage + pos);
        uint32_t recordSize = KSKVS_RECORD_HEADER_SIZE + rec->keyLen + rec->valueLen;
        if (pos + recordSize > endPos) {
            break;
        }
        if (rec->keyLen == keyLen && memcmp(store->storage + pos + KSKVS_RECORD_HEADER_SIZE, key, keyLen) == 0) {
            found = pos;
        }
        pos += recordSize;
    }
    return found;
}

/** Discard superseded entries in-place. Final tombstones are preserved
 *  so removal semantics survive compaction.
 *  Returns whether it ran: a caller reads futility from the offset not
 *  moving, and a compaction that never started has not measured anything.
 *  NOT thread-safe — caller must synchronize.
 */
static bool compact(KSKeyValueStore *store)
{
    if (store->storage == NULL) {
        return false;
    }

    KSKVSHeader *hdr = storeHeader(store);
    uint32_t endPos = hdr->offset;

    // Runs under caller's lock but NOT in a crash handler, so malloc is safe.
    uint8_t *temp = (uint8_t *)calloc(1, store->capacity);
    if (temp == NULL) {
        KSLOG_ERROR("Failed to allocate temp buffer for compaction");
        return false;
    }

    pthread_rwlock_wrlock(&g_fileImageLock);

    KSKVSHeader *tempHdr = (KSKVSHeader *)temp;
    tempHdr->magic = KSKVS_MAGIC;
    tempHdr->version = KSKVS_CURRENT_VERSION;
    uint32_t tempWritePos = KSKVS_HEADER_SIZE;

    // O(n^2) scan: for each record, check if a later record with the
    // same key exists. Small record counts make this acceptable.
    uint32_t readPos = KSKVS_HEADER_SIZE;
    while (readPos + KSKVS_RECORD_HEADER_SIZE <= endPos) {
        KSKVSRecordHeader *rec = (KSKVSRecordHeader *)(store->storage + readPos);
        uint32_t recordSize = KSKVS_RECORD_HEADER_SIZE + rec->keyLen + rec->valueLen;

        if (readPos + recordSize > endPos) {
            break;
        }

        const uint8_t *key = store->storage + readPos + KSKVS_RECORD_HEADER_SIZE;
        uint16_t keyLen = rec->keyLen;

        // Scan forward for a later record with the same key.
        bool superseded = false;
        uint32_t scanPos = readPos + recordSize;
        while (scanPos + KSKVS_RECORD_HEADER_SIZE <= endPos) {
            KSKVSRecordHeader *scanRec = (KSKVSRecordHeader *)(store->storage + scanPos);
            uint32_t scanSize = KSKVS_RECORD_HEADER_SIZE + scanRec->keyLen + scanRec->valueLen;
            if (scanPos + scanSize > endPos) {
                break;
            }
            if (scanRec->keyLen == keyLen &&
                memcmp(store->storage + scanPos + KSKVS_RECORD_HEADER_SIZE, key, keyLen) == 0) {
                superseded = true;
                break;
            }
            scanPos += scanSize;
        }

        if (!superseded) {
            if (rec->type == KSKVSTypeRemoved && rec->valueLen > 0) {
                // A tombstone stamped in place over a live record still spans
                // that record's value bytes, because the span is how
                // iteration finds the next record. Compaction is where those
                // bytes go back.
                uint32_t headerAndKey = KSKVS_RECORD_HEADER_SIZE + keyLen;
                memcpy(temp + tempWritePos, store->storage + readPos, headerAndKey);
                ((KSKVSRecordHeader *)(temp + tempWritePos))->valueLen = 0;
                tempWritePos += headerAndKey;
            } else {
                memcpy(temp + tempWritePos, store->storage + readPos, recordSize);
                tempWritePos += recordSize;
            }
        }

        readPos += recordSize;
    }

    tempHdr->offset = tempWritePos;

    memcpy(store->storage, temp, tempWritePos);
    hdr = storeHeader(store);
    hdr->offset = tempWritePos;
    if (tempWritePos < store->capacity) {
        memset(store->storage + tempWritePos, 0, store->capacity - tempWritePos);
    }

    // Every stamped record is now the width of its key alone, so there is
    // nothing left for a later write to count on.
    store->reclaimableBytes = 0;

    pthread_rwlock_unlock(&g_fileImageLock);
    free(temp);
    return true;
}

/** Double storage capacity until at least minCapacity. NOT thread-safe. */
static bool growStorage(KSKeyValueStore *store, uint32_t minCapacity)
{
    if (store->fd < 0) {
        // Read-only store cannot grow.
        KSLOG_ERROR("Cannot grow read-only KVS store");
        return false;
    }

    if (minCapacity > KSKVS_MAX_CAPACITY) {
        KSLOG_ERROR("KVS store needs %u bytes, past the %u byte ceiling; rejecting the write", minCapacity,
                    (uint32_t)KSKVS_MAX_CAPACITY);
        return false;
    }

    // The ceiling is what terminates this, not the comparison: capacity is a
    // uint32_t, so doubling past 2^31 wraps to 0 and would spin forever here
    // while holding the file-image lock.
    uint32_t newCapacity = store->capacity;
    while (newCapacity < minCapacity) {
        if (newCapacity > KSKVS_MAX_CAPACITY / 2) {
            newCapacity = KSKVS_MAX_CAPACITY;
            break;
        }
        newCapacity *= 2;
    }

    // The resize and the remap change what a reader loading this file whole
    // would see, so they wait for one to finish and it waits for them.
    pthread_rwlock_wrlock(&g_fileImageLock);

    if (ftruncate(store->fd, (off_t)newCapacity) != 0) {
        KSLOG_ERROR("Failed to grow KVS file: %s", strerror(errno));
        pthread_rwlock_unlock(&g_fileImageLock);
        return false;
    }
    void *newMap = mmap(NULL, newCapacity, PROT_READ | PROT_WRITE, MAP_SHARED, store->fd, 0);
    if (newMap == MAP_FAILED) {
        KSLOG_ERROR("Failed to remap KVS file: %s", strerror(errno));
        pthread_rwlock_unlock(&g_fileImageLock);
        return false;
    }

    // Zero the extended region so TSan shadow state from a prior virtual
    // address doesn't cause false positives.  The existing file content
    // (0..oldCapacity) is already valid from the MAP_SHARED mapping.
    if (newCapacity > store->capacity) {
        memset((uint8_t *)newMap + store->capacity, 0, newCapacity - store->capacity);
    }

    munmap(store->storage, store->capacity);
    store->storage = (uint8_t *)newMap;
    store->capacity = newCapacity;

    pthread_rwlock_unlock(&g_fileImageLock);
    return true;
}

/** Append a record to the log; false when rejected or not persisted. NOT thread-safe. */
static bool appendRecord(KSKeyValueStore *store, const char *key, uint8_t type, const void *value, uint16_t valueLen)
{
    if (store == NULL || store->storage == NULL) {
        KSLOG_DEBUG("KVS appendRecord called with NULL store (not yet installed?)");
        return false;
    }
    // A read-mode store is a private heap snapshot; accepting the write would
    // report persistence for bytes that die with the store.
    if (store->fd < 0) {
        KSLOG_ERROR("KVS write rejected: the store is read-only");
        return false;
    }
    if (key == NULL) {
        return false;
    }

    // Reject records with a payload length but no payload pointer —
    // writing the header alone would leave garbage in the value region.
    if (valueLen > 0 && value == NULL) {
        KSLOG_DEBUG("KVS appendRecord called with NULL value but valueLen %u", valueLen);
        return false;
    }

    // Compare before narrowing: a length past the record format's 64KB
    // bound must reject, not wrap.
    size_t rawKeyLen = strlen(key);
    if (rawKeyLen == 0) {
        return false;
    }
    if (rawKeyLen > UINT16_MAX) {
        KSLOG_ERROR("KVS key too long (%zu), rejecting the write", rawKeyLen);
        return false;
    }
    uint16_t keyLen = (uint16_t)rawKeyLen;

    uint32_t recordSize = KSKVS_RECORD_HEADER_SIZE + keyLen + valueLen;

    pthread_rwlock_wrlock(&store->lock);

    KSKVSHeader *hdr = storeHeader(store);

    if (hdr->offset + recordSize > store->capacity) {
        // Refuse cheaply at the ceiling. Compacting first cost a
        // capacity-sized calloc and the O(n^2) scan on the host app's thread
        // before growStorage refused the write anyway, and the caller's
        // fallback removal then paid it a second time.
        //
        // A removal stamped in place since then is the one thing that can
        // change the answer, so the bytes it freed decide when to try again:
        // without that, every refused write at the ceiling paid for a
        // compaction the write after it paid for all over again.
        if (store->capacity >= KSKVS_MAX_CAPACITY && store->compactionIsFutile &&
            hdr->offset + recordSize > store->capacity + store->reclaimableBytes) {
            pthread_rwlock_unlock(&store->lock);
            return false;
        }

        uint32_t offsetBeforeCompact = hdr->offset;
        // Only a compaction that ran has measured anything: one that could not
        // allocate its buffer left the offset where it was, and reading that
        // as futility would wedge the store for the rest of the run over a
        // transient allocation failure.
        if (compact(store)) {
            hdr = storeHeader(store);
            store->compactionIsFutile = hdr->offset >= offsetBeforeCompact;
        }

        if (hdr->offset + recordSize > store->capacity) {
            if (!growStorage(store, hdr->offset + recordSize)) {
                pthread_rwlock_unlock(&store->lock);
                return false;
            }
            hdr = storeHeader(store);
        }
    }

    uint8_t *dest = store->storage + hdr->offset;
    KSKVSRecordHeader *rec = (KSKVSRecordHeader *)dest;
    rec->keyLen = keyLen;
    rec->type = type;
    rec->valueLen = valueLen;
    memcpy(dest + KSKVS_RECORD_HEADER_SIZE, key, keyLen);
    if (valueLen > 0 && value != NULL) {
        memcpy(dest + KSKVS_RECORD_HEADER_SIZE + keyLen, value, valueLen);
    }

    // Publish the record by bumping the cursor last, after a release so a
    // reader that sees the new cursor sees the bytes below it. A read-mode
    // load of this file shares no lock with this append (it takes
    // g_fileImageLock, which ordinary appends deliberately do not), so this
    // ordering is all that stands between a live run's own report and a
    // record header whose bytes have not landed.
    atomic_thread_fence(memory_order_release);
    hdr->offset += recordSize;
    // This record may supersede an earlier one for the same key, so the next
    // compaction has something to reclaim again.
    store->compactionIsFutile = false;
    pthread_rwlock_unlock(&store->lock);
    return true;
}

// ============================================================================
#pragma mark - Lifecycle -
// ============================================================================

KSKeyValueStore *kskvs_create(const char *path, KSKVSMode mode, const KSKVSConfig *config, KSKVSOpenStatus *outStatus)
{
    // Every exit funnels through done so the status write cannot be missed.
    KSKVSOpenStatus status = KSKVSOpenFailure;
    KSKeyValueStore *result = NULL;

    if (path == NULL) {
        goto done;
    }

    if (mode == KSKVSModeRead) {
        // Read existing file into heap buffer.
        uint8_t *buf = NULL;
        int fd = open(path, O_RDONLY);
        if (fd < 0) {
            if (errno == ENOENT) {
                status = KSKVSOpenAbsent;
            } else {
                KSLOG_ERROR("Failed to open KVS file for reading %s: %s", path, strerror(errno));
            }
            goto done;
        }

        // The size probe and the read form one snapshot, taken while no
        // store is restructuring an image: a live run's own report is
        // finalized against the sidecar this process is still writing, so a
        // compaction or a remap part way through this read would tear it.
        // Appends do not take this lock and do not need to: they only write
        // past the offset this snapshot records.
        pthread_rwlock_rdlock(&g_fileImageLock);
        off_t fileSize = lseek(fd, 0, SEEK_END);
        if (fileSize < 0) {
            pthread_rwlock_unlock(&g_fileImageLock);
            goto read_fail;  // seek failure is environmental, not a verdict on the file
        }
        if (fileSize < (off_t)KSKVS_HEADER_SIZE || fileSize > (off_t)KSKVS_MAX_CAPACITY) {
            pthread_rwlock_unlock(&g_fileImageLock);
            status = KSKVSOpenCorrupt;
            goto read_fail;
        }
        lseek(fd, 0, SEEK_SET);

        buf = (uint8_t *)malloc((size_t)fileSize);
        if (buf == NULL) {
            pthread_rwlock_unlock(&g_fileImageLock);
            goto read_fail;
        }

        ssize_t bytesRead = read(fd, buf, (size_t)fileSize);
        pthread_rwlock_unlock(&g_fileImageLock);
        close(fd);
        fd = -1;

        if (bytesRead != fileSize) {
            goto read_fail;
        }

        // Validate header
        KSKVSHeader *hdr = (KSKVSHeader *)buf;
        if (hdr->magic != KSKVS_MAGIC) {
            KSLOG_ERROR("Invalid KVS magic 0x%x", hdr->magic);
            status = KSKVSOpenCorrupt;
            goto read_fail;
        }
        if (hdr->version == 0 || hdr->version > KSKVS_CURRENT_VERSION) {
            KSLOG_ERROR("Unsupported KVS version %u", hdr->version);
            status = KSKVSOpenCorrupt;
            goto read_fail;
        }

        KSKeyValueStore *store = (KSKeyValueStore *)calloc(1, sizeof(KSKeyValueStore));
        if (store == NULL) {
            goto read_fail;
        }
        pthread_rwlock_init(&store->lock, NULL);

        store->storage = buf;
        store->capacity = (uint32_t)fileSize;
        store->fd = -1;

        result = store;
        status = KSKVSOpenSuccess;
        goto done;

    read_fail:
        free(buf);
        if (fd >= 0) {
            close(fd);
        }
        goto done;
    }

    if (mode == KSKVSModeReadWriteCreate) {
        if (config == NULL || config->initialCapacity < KSKVS_HEADER_SIZE) {
            KSLOG_ERROR("Invalid KVS config for ReadWriteCreate mode");
            goto done;
        }
        // Bounded by the same ceiling the read mode enforces, so this mode
        // cannot produce a file every later read-mode open calls corrupt.
        if (config->initialCapacity > KSKVS_MAX_CAPACITY) {
            KSLOG_ERROR("KVS initial capacity %u is past the %u byte ceiling", config->initialCapacity,
                        (uint32_t)KSKVS_MAX_CAPACITY);
            goto done;
        }

        // The truncate-and-init below is visible to a concurrent read-mode
        // load of the same path, which must not observe the zeroed image
        // between O_TRUNC and initHeader.
        pthread_rwlock_wrlock(&g_fileImageLock);
        int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) {
            if (errno == ENOENT) {
                status = KSKVSOpenAbsent;
            } else {
                KSLOG_ERROR("Failed to create KVS file %s: %s", path, strerror(errno));
            }
            pthread_rwlock_unlock(&g_fileImageLock);
            goto done;
        }

        void *mapped = MAP_FAILED;
        uint32_t capacity = config->initialCapacity;

        if (ftruncate(fd, (off_t)capacity) != 0) {
            KSLOG_ERROR("Failed to size KVS file: %s", strerror(errno));
            goto rw_fail;
        }

        mapped = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (mapped == MAP_FAILED) {
            KSLOG_ERROR("Failed to mmap KVS file: %s", strerror(errno));
            goto rw_fail;
        }

        // Zero-init so TSan shadow state from a prior virtual address doesn't
        // cause false positives (same rationale as ksfu_mmap).
        memset(mapped, 0, capacity);

        // Ensure the file is readable before first unlock (iOS data protection).
        ksfu_applyNoFileProtection(path);

        KSKeyValueStore *store = (KSKeyValueStore *)calloc(1, sizeof(KSKeyValueStore));
        if (store == NULL) {
            goto rw_fail;
        }
        pthread_rwlock_init(&store->lock, NULL);

        store->storage = (uint8_t *)mapped;
        store->capacity = capacity;
        store->fd = fd;
        initHeader(store->storage);

        result = store;
        status = KSKVSOpenSuccess;
        pthread_rwlock_unlock(&g_fileImageLock);
        goto done;

    rw_fail:
        if (mapped != MAP_FAILED) {
            munmap(mapped, capacity);
        }
        close(fd);
        pthread_rwlock_unlock(&g_fileImageLock);
        goto done;
    }

done:
    if (outStatus != NULL) {
        *outStatus = status;
    }
    return result;
}

void kskvs_destroy(KSKeyValueStore *store)
{
    if (store == NULL) {
        return;
    }

    if (store->storage != NULL) {
        if (store->fd >= 0) {
            munmap(store->storage, store->capacity);
            close(store->fd);
        } else {
            free(store->storage);
        }
    }
    store->storage = NULL;
    store->capacity = 0;
    store->fd = -1;
    pthread_rwlock_destroy(&store->lock);

    free(store);
}

// ============================================================================
#pragma mark - Typed Setters -
// ============================================================================

bool kskvs_setString(KSKeyValueStore *store, const char *key, const char *value)
{
    if (store == NULL) {
        KSLOG_DEBUG("KVS setString called with NULL store (not yet installed?)");
        return false;
    }
    if (value == NULL) {
        return kskvs_removeValue(store, key);
    }
    // Compare before narrowing: a length past UINT16_MAX must reject, not wrap.
    size_t rawLen = strlen(value);
    if (rawLen > UINT16_MAX) {
        KSLOG_ERROR("KVS string value too long (%zu), rejecting the write", rawLen);
        return false;
    }
    return appendRecord(store, key, KSKVSTypeString, value, (uint16_t)rawLen);
}

bool kskvs_setInt64(KSKeyValueStore *store, const char *key, int64_t value)
{
    return appendRecord(store, key, KSKVSTypeInt64, &value, sizeof(value));
}

bool kskvs_setUInt64(KSKeyValueStore *store, const char *key, uint64_t value)
{
    return appendRecord(store, key, KSKVSTypeUInt64, &value, sizeof(value));
}

bool kskvs_setDouble(KSKeyValueStore *store, const char *key, double value)
{
    return appendRecord(store, key, KSKVSTypeDouble, &value, sizeof(value));
}

bool kskvs_setBool(KSKeyValueStore *store, const char *key, bool value)
{
    uint8_t byte = value ? 1 : 0;
    return appendRecord(store, key, KSKVSTypeBool, &byte, sizeof(byte));
}

bool kskvs_setDate(KSKeyValueStore *store, const char *key, int64_t nanosecondsSince1970)
{
    return appendRecord(store, key, KSKVSTypeDate, &nanosecondsSince1970, sizeof(nanosecondsSince1970));
}

bool kskvs_setJSON(KSKeyValueStore *store, const char *key, const char *json, size_t length)
{
    if (json == NULL || length == 0) {
        return false;
    }
    // Compare before narrowing: a length past UINT16_MAX must reject, not wrap.
    if (length > UINT16_MAX) {
        KSLOG_ERROR("KVS JSON value too long (%zu), rejecting the write", length);
        return false;
    }
    // Only a container is a value: scalars have native record types, so JSON
    // bytes must open an array or an object. Checked without parsing, the
    // same way readers will refuse whatever slips past it.
    size_t first = 0;
    while (first < length &&
           (json[first] == ' ' || json[first] == '\t' || json[first] == '\n' || json[first] == '\r')) {
        first++;
    }
    if (first >= length || (json[first] != '[' && json[first] != '{')) {
        KSLOG_ERROR("KVS JSON value is not a container, rejecting the write");
        return false;
    }
    return appendRecord(store, key, KSKVSTypeJSON, json, (uint16_t)length);
}

/** Stamp the key's last record as removed without appending anything.
 *  The reader resolves a key to its last record, so this makes the key absent
 *  in a store that has no room left for a tombstone. Returns whether the key
 *  ends up absent, which includes never having been there.
 */
static bool markLastRecordRemoved(KSKeyValueStore *store, const char *key)
{
    if (store == NULL || store->storage == NULL || store->fd < 0) {
        return false;  // a read-mode image is a copy; there is nothing to stamp
    }
    // appendRecord rejects a NULL key before this runs, so the fallback must
    // reject it too rather than walk the store looking for it.
    if (key == NULL) {
        return false;
    }

    size_t rawKeyLen = strlen(key);
    if (rawKeyLen == 0 || rawKeyLen > UINT16_MAX) {
        return false;
    }
    uint16_t keyLen = (uint16_t)rawKeyLen;

    pthread_rwlock_wrlock(&store->lock);

    KSKVSHeader *hdr = storeHeader(store);
    uint32_t endPos = hdr->offset;
    if (endPos > store->capacity) {
        endPos = store->capacity;
    }

    uint32_t foundPos = findLastRecordOffset(store, key, keyLen, endPos);
    if (foundPos != UINT32_MAX) {
        KSKVSRecordHeader *last = (KSKVSRecordHeader *)(store->storage + foundPos);
        // valueLen is left alone: a record's span is how iteration finds the
        // next one. compact() reclaims the dead value bytes, and remembering
        // how many of them there are is what lets the next write tell whether
        // a compaction would make room for it. Clearing compactionIsFutile
        // here instead disarmed that guard on every refused write.
        if (last->type != KSKVSTypeRemoved) {
            store->reclaimableBytes += last->valueLen;
        }
        last->type = KSKVSTypeRemoved;
    }

    pthread_rwlock_unlock(&store->lock);
    return true;
}

bool kskvs_removeValue(KSKeyValueStore *store, const char *key)
{
    if (appendRecord(store, key, KSKVSTypeRemoved, NULL, 0)) {
        return true;
    }
    // A store with no room left can still stop serving the value, and must:
    // otherwise a refused write leaves the key returning what the app
    // believes it replaced.
    return markLastRecordRemoved(store, key);
}

// ============================================================================
#pragma mark - Iteration -
// ============================================================================

/** Fire the one callback matching the record at `pos`. Bounds are the
 *  caller's responsibility; iteration and lookup validate before remembering
 *  a position. */
static void dispatchRecord(const KSKeyValueStore *store, uint32_t pos, const KSKVSCallbacks *callbacks, void *context)
{
    const KSKVSRecordHeader *rec = (const KSKVSRecordHeader *)(store->storage + pos);
    const char *key = (const char *)(store->storage + pos + KSKVS_RECORD_HEADER_SIZE);
    uint16_t keyLen = rec->keyLen;
    if (rec->type == KSKVSTypeRemoved) {
        if (callbacks->onRemoved) {
            callbacks->onRemoved(key, keyLen, context);
        }
        return;
    }
    const uint8_t *valueBytes = store->storage + pos + KSKVS_RECORD_HEADER_SIZE + keyLen;

    // A record whose payload does not fit its type is not readable, and
    // silence would be the wrong answer: the key would keep whatever an
    // earlier record or the crash-time writer left under it, while every
    // other reader of this store calls it absent.
    bool unreadable = false;
    switch (rec->type) {
        case KSKVSTypeString:
            // Every length is a string, the empty one included.
            if (callbacks->onString) {
                callbacks->onString(key, keyLen, (const char *)valueBytes, rec->valueLen, context);
            }
            break;
        case KSKVSTypeInt64:
            if (rec->valueLen != sizeof(int64_t)) {
                unreadable = true;
            } else if (callbacks->onInt64) {
                int64_t val;
                memcpy(&val, valueBytes, sizeof(val));
                callbacks->onInt64(key, keyLen, val, context);
            }
            break;
        case KSKVSTypeUInt64:
            if (rec->valueLen != sizeof(uint64_t)) {
                unreadable = true;
            } else if (callbacks->onUInt64) {
                uint64_t val;
                memcpy(&val, valueBytes, sizeof(val));
                callbacks->onUInt64(key, keyLen, val, context);
            }
            break;
        case KSKVSTypeDouble:
            if (rec->valueLen != sizeof(double)) {
                unreadable = true;
            } else if (callbacks->onDouble) {
                double val;
                memcpy(&val, valueBytes, sizeof(val));
                callbacks->onDouble(key, keyLen, val, context);
            }
            break;
        case KSKVSTypeBool:
            if (rec->valueLen != sizeof(uint8_t)) {
                unreadable = true;
            } else if (callbacks->onBool) {
                callbacks->onBool(key, keyLen, valueBytes[0] != 0, context);
            }
            break;
        case KSKVSTypeDate:
            if (rec->valueLen != sizeof(int64_t)) {
                unreadable = true;
            } else if (callbacks->onDate) {
                int64_t val;
                memcpy(&val, valueBytes, sizeof(val));
                callbacks->onDate(key, keyLen, val, context);
            }
            break;
        case KSKVSTypeJSON:
            if (rec->valueLen == 0) {
                unreadable = true;
            } else if (callbacks->onJSON) {
                callbacks->onJSON(key, keyLen, (const char *)valueBytes, rec->valueLen, context);
            }
            break;
        default:
            // A record type this build does not know is not read: a newer
            // writer's value is not ours to judge. It is still reported, so a
            // reader that starts from an older value for the key can stop
            // serving what the store says was replaced.
            if (callbacks->onUnknown) {
                callbacks->onUnknown(key, keyLen, rec->type, context);
            }
            break;
    }

    if (unreadable && callbacks->onRemoved) {
        callbacks->onRemoved(key, keyLen, context);
    }
}

// Takes no lock. Every caller either owns a private image (a read-mode store
// is this process's own heap copy) or holds the same serialization the writer
// does, and staying lock-free is also what would let a crash handler walk a
// live store, where pthread calls are not async-signal-safe. Iterating a live
// store from outside its writer's serialization is the one thing this does not
// support.
void kskvs_iterate(const KSKeyValueStore *store, const KSKVSCallbacks *callbacks, void *context)
{
    if (store == NULL || store->storage == NULL || callbacks == NULL) {
        return;
    }

    const KSKVSHeader *hdr = storeHeaderConst(store);
    if (hdr->magic != KSKVS_MAGIC) {
        return;
    }

    uint32_t endPos = hdr->offset;
    if (endPos > store->capacity) {
        endPos = store->capacity;
    }

    // Two-pass approach: first pass determines which records are live
    // (last-write-wins), second pass dispatches callbacks.
    // We track which records are superseded using the same forward-scan approach.

    uint32_t pos = KSKVS_HEADER_SIZE;
    while (pos + KSKVS_RECORD_HEADER_SIZE <= endPos) {
        const KSKVSRecordHeader *rec = (const KSKVSRecordHeader *)(store->storage + pos);
        uint32_t recordSize = KSKVS_RECORD_HEADER_SIZE + rec->keyLen + rec->valueLen;

        // Bounds check: keyLen and valueLen are uint16_t (max 65535 each), so
        // recordSize cannot overflow uint32_t. This also guarantees all bytes
        // passed to callbacks are within the buffer.
        if (pos + recordSize > endPos) {
            break;
        }

        const char *key = (const char *)(store->storage + pos + KSKVS_RECORD_HEADER_SIZE);
        uint16_t keyLen = rec->keyLen;

        // Check if a later record with the same key exists.
        bool superseded = false;
        uint32_t scanPos = pos + recordSize;
        while (scanPos + KSKVS_RECORD_HEADER_SIZE <= endPos) {
            const KSKVSRecordHeader *scanRec = (const KSKVSRecordHeader *)(store->storage + scanPos);
            uint32_t scanSize = KSKVS_RECORD_HEADER_SIZE + scanRec->keyLen + scanRec->valueLen;
            if (scanPos + scanSize > endPos) {
                break;
            }
            if (scanRec->keyLen == keyLen &&
                memcmp(store->storage + scanPos + KSKVS_RECORD_HEADER_SIZE, key, keyLen) == 0) {
                superseded = true;
                break;
            }
            scanPos += scanSize;
        }

        if (!superseded) {
            dispatchRecord(store, pos, callbacks, context);
        }

        pos += recordSize;
    }
}

void kskvs_lookup(const KSKeyValueStore *store, const char *key, const KSKVSCallbacks *callbacks, void *context)
{
    if (store == NULL || store->storage == NULL || key == NULL || callbacks == NULL) {
        return;
    }

    const KSKVSHeader *hdr = storeHeaderConst(store);
    if (hdr->magic != KSKVS_MAGIC) {
        return;
    }

    uint32_t endPos = hdr->offset;
    if (endPos > store->capacity) {
        endPos = store->capacity;
    }

    size_t rawKeyLen = strlen(key);
    if (rawKeyLen == 0 || rawKeyLen > UINT16_MAX) {
        return;
    }

    // The last record for the key is the last write, so exactly one callback
    // fires. Same walk the in-place removal uses to find what to stamp.
    uint32_t foundPos = findLastRecordOffset(store, key, (uint16_t)rawKeyLen, endPos);
    if (foundPos != UINT32_MAX) {
        dispatchRecord(store, foundPos, callbacks, context);
    }
}

