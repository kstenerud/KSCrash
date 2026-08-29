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
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "KSFileUtils.h"
#include "KSLogger.h"

// ============================================================================
#pragma mark - Internal Format -
// ============================================================================

/** Record type tags for the append-only log. */
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

// ============================================================================
#pragma mark - Store Structure -
// ============================================================================

struct KSKeyValueStore {
    uint8_t *storage;
    uint32_t capacity;
    int fd;  // < 0 means read-only heap (KSKVSModeRead), >= 0 means mmap mode
};

// Spans mutation (write side) and the read-mode file load (read side), so a
// reader's snapshot is never torn by a concurrent compact or append. Global
// because a reader opens the file by path and shares no object with the
// writer. This is NOT a thread-safety promise: concurrent writers to one
// store remain the caller's responsibility. Deliberately not a file lock,
// which iOS punishes with 0xdead10cc when held across suspension.
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

/** Discard superseded entries in-place. Final tombstones are preserved
 *  so removal semantics survive compaction.
 *  NOT thread-safe — caller must synchronize.
 */
static void compact(KSKeyValueStore *store)
{
    if (store->storage == NULL) {
        return;
    }

    KSKVSHeader *hdr = storeHeader(store);
    uint32_t endPos = hdr->offset;

    // Runs under caller's lock but NOT in a crash handler, so malloc is safe.
    uint8_t *temp = (uint8_t *)calloc(1, store->capacity);
    if (temp == NULL) {
        KSLOG_ERROR("Failed to allocate temp buffer for compaction");
        return;
    }

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
            memcpy(temp + tempWritePos, store->storage + readPos, recordSize);
            tempWritePos += recordSize;
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

    free(temp);
}

/** Double storage capacity until at least minCapacity. NOT thread-safe. */
static bool growStorage(KSKeyValueStore *store, uint32_t minCapacity)
{
    if (store->fd < 0) {
        // Read-only store cannot grow.
        KSLOG_ERROR("Cannot grow read-only KVS store");
        return false;
    }

    uint32_t newCapacity = store->capacity;
    while (newCapacity < minCapacity) {
        newCapacity *= 2;
    }

    if (ftruncate(store->fd, (off_t)newCapacity) != 0) {
        KSLOG_ERROR("Failed to grow KVS file: %s", strerror(errno));
        return false;
    }
    void *newMap = mmap(NULL, newCapacity, PROT_READ | PROT_WRITE, MAP_SHARED, store->fd, 0);
    if (newMap == MAP_FAILED) {
        KSLOG_ERROR("Failed to remap KVS file: %s", strerror(errno));
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

    pthread_rwlock_wrlock(&g_fileImageLock);

    KSKVSHeader *hdr = storeHeader(store);

    if (hdr->offset + recordSize > store->capacity) {
        compact(store);
        hdr = storeHeader(store);

        if (hdr->offset + recordSize > store->capacity) {
            if (!growStorage(store, hdr->offset + recordSize)) {
                pthread_rwlock_unlock(&g_fileImageLock);
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

    hdr->offset += recordSize;
    pthread_rwlock_unlock(&g_fileImageLock);
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

        // The size probe and the read form one snapshot: both under the read
        // lock so a concurrent compact or append cannot tear the image.
        pthread_rwlock_rdlock(&g_fileImageLock);
        off_t fileSize = lseek(fd, 0, SEEK_END);
        if (fileSize < 0) {
            pthread_rwlock_unlock(&g_fileImageLock);
            goto read_fail;  // seek failure is environmental, not a verdict on the file
        }
        if (fileSize < (off_t)KSKVS_HEADER_SIZE) {
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

        // The truncate-and-init below is visible to a concurrent read-mode
        // load of the same path. The write lock keeps such a reader from
        // observing the zeroed image between O_TRUNC and initHeader.
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

bool kskvs_removeValue(KSKeyValueStore *store, const char *key)
{
    return appendRecord(store, key, KSKVSTypeRemoved, NULL, 0);
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
    switch (rec->type) {
        case KSKVSTypeString:
            if (callbacks->onString) {
                callbacks->onString(key, keyLen, (const char *)valueBytes, rec->valueLen, context);
            }
            break;
        case KSKVSTypeInt64:
            if (callbacks->onInt64 && rec->valueLen == sizeof(int64_t)) {
                int64_t val;
                memcpy(&val, valueBytes, sizeof(val));
                callbacks->onInt64(key, keyLen, val, context);
            }
            break;
        case KSKVSTypeUInt64:
            if (callbacks->onUInt64 && rec->valueLen == sizeof(uint64_t)) {
                uint64_t val;
                memcpy(&val, valueBytes, sizeof(val));
                callbacks->onUInt64(key, keyLen, val, context);
            }
            break;
        case KSKVSTypeDouble:
            if (callbacks->onDouble && rec->valueLen == sizeof(double)) {
                double val;
                memcpy(&val, valueBytes, sizeof(val));
                callbacks->onDouble(key, keyLen, val, context);
            }
            break;
        case KSKVSTypeBool:
            if (callbacks->onBool && rec->valueLen == sizeof(uint8_t)) {
                callbacks->onBool(key, keyLen, valueBytes[0] != 0, context);
            }
            break;
        case KSKVSTypeDate:
            if (callbacks->onDate && rec->valueLen == sizeof(int64_t)) {
                int64_t val;
                memcpy(&val, valueBytes, sizeof(val));
                callbacks->onDate(key, keyLen, val, context);
            }
            break;
        case KSKVSTypeJSON:
            if (callbacks->onJSON && rec->valueLen > 0) {
                callbacks->onJSON(key, keyLen, (const char *)valueBytes, rec->valueLen, context);
            }
            break;
        default:
            // Unknown types are skipped, so a future record type never
            // corrupts an older reader's view.
            break;
    }
}

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

    size_t keyLen = strlen(key);

    // One forward pass remembering the latest record for the key; whatever is
    // held at the end is the last write, so exactly one callback fires.
    uint32_t foundPos = UINT32_MAX;
    uint32_t pos = KSKVS_HEADER_SIZE;
    while (pos + KSKVS_RECORD_HEADER_SIZE <= endPos) {
        const KSKVSRecordHeader *rec = (const KSKVSRecordHeader *)(store->storage + pos);
        uint32_t recordSize = KSKVS_RECORD_HEADER_SIZE + rec->keyLen + rec->valueLen;
        if (pos + recordSize > endPos) {
            break;
        }
        if (rec->keyLen == keyLen && memcmp(store->storage + pos + KSKVS_RECORD_HEADER_SIZE, key, keyLen) == 0) {
            foundPos = pos;
        }
        pos += recordSize;
    }

    if (foundPos != UINT32_MAX) {
        dispatchRecord(store, foundPos, callbacks, context);
    }
}

