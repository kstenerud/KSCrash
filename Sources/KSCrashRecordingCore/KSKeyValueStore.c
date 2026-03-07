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
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

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
    uint16_t maxKeyLength;
    uint16_t maxStringLength;
};

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

/** Discard superseded entries and tombstones in-place.
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
    uint8_t *temp = (uint8_t *)malloc(store->capacity);
    if (temp == NULL) {
        KSLOG_ERROR("Failed to allocate temp buffer for compaction");
        return;
    }
    memset(temp, 0, store->capacity);

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
    munmap(store->storage, store->capacity);
    store->storage = (uint8_t *)newMap;
    store->capacity = newCapacity;

    return true;
}

/** Append a record to the log. NOT thread-safe. */
static void appendRecord(KSKeyValueStore *store, const char *key, uint8_t type, const void *value, uint16_t valueLen)
{
    if (store == NULL || store->storage == NULL) {
        KSLOG_DEBUG("KVS appendRecord called with NULL store (not yet installed?)");
        return;
    }
    if (key == NULL) {
        return;
    }

    uint16_t keyLen = (uint16_t)strlen(key);
    if (keyLen == 0) {
        return;
    }
    if (keyLen > store->maxKeyLength) {
        KSLOG_ERROR("KVS key too long (%u > %u), truncating", keyLen, store->maxKeyLength);
        keyLen = store->maxKeyLength;
    }

    uint32_t recordSize = KSKVS_RECORD_HEADER_SIZE + keyLen + valueLen;

    KSKVSHeader *hdr = storeHeader(store);

    if (hdr->offset + recordSize > store->capacity) {
        compact(store);
        hdr = storeHeader(store);

        if (hdr->offset + recordSize > store->capacity) {
            if (!growStorage(store, hdr->offset + recordSize)) {
                return;
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
}

// ============================================================================
#pragma mark - Lifecycle -
// ============================================================================

KSKeyValueStore *kskvs_create(const char *path, KSKVSMode mode, const KSKVSConfig *config)
{
    if (path == NULL) {
        return NULL;
    }

    if (mode == KSKVSModeRead) {
        // Read existing file into heap buffer.
        int fd = open(path, O_RDONLY);
        if (fd < 0) {
            KSLOG_ERROR("Failed to open KVS file for reading %s: %s", path, strerror(errno));
            return NULL;
        }

        off_t fileSize = lseek(fd, 0, SEEK_END);
        if (fileSize < (off_t)KSKVS_HEADER_SIZE) {
            close(fd);
            return NULL;
        }
        lseek(fd, 0, SEEK_SET);

        uint8_t *buf = (uint8_t *)malloc((size_t)fileSize);
        if (buf == NULL) {
            close(fd);
            return NULL;
        }

        ssize_t bytesRead = read(fd, buf, (size_t)fileSize);
        close(fd);

        if (bytesRead != fileSize) {
            free(buf);
            return NULL;
        }

        // Validate header
        KSKVSHeader *hdr = (KSKVSHeader *)buf;
        if (hdr->magic != KSKVS_MAGIC) {
            KSLOG_ERROR("Invalid KVS magic 0x%x", hdr->magic);
            free(buf);
            return NULL;
        }
        if (hdr->version == 0 || hdr->version > KSKVS_CURRENT_VERSION) {
            KSLOG_ERROR("Unsupported KVS version %u", hdr->version);
            free(buf);
            return NULL;
        }

        KSKeyValueStore *store = (KSKeyValueStore *)calloc(1, sizeof(KSKeyValueStore));
        if (store == NULL) {
            free(buf);
            return NULL;
        }

        store->storage = buf;
        store->capacity = (uint32_t)fileSize;
        store->fd = -1;
        store->maxKeyLength = (config != NULL && config->maxKeyLength > 0) ? config->maxKeyLength : 256;
        store->maxStringLength = (config != NULL && config->maxStringLength > 0) ? config->maxStringLength : 0;

        return store;
    }

    if (mode == KSKVSModeReadWriteCreate) {
        if (config == NULL || config->initialCapacity < KSKVS_HEADER_SIZE) {
            KSLOG_ERROR("Invalid KVS config for ReadWriteCreate mode");
            return NULL;
        }

        int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) {
            KSLOG_ERROR("Failed to create KVS file %s: %s", path, strerror(errno));
            return NULL;
        }

        uint32_t capacity = config->initialCapacity;

        if (ftruncate(fd, (off_t)capacity) != 0) {
            KSLOG_ERROR("Failed to size KVS file: %s", strerror(errno));
            close(fd);
            return NULL;
        }

        void *mapped = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (mapped == MAP_FAILED) {
            KSLOG_ERROR("Failed to mmap KVS file: %s", strerror(errno));
            close(fd);
            return NULL;
        }

        KSKeyValueStore *store = (KSKeyValueStore *)calloc(1, sizeof(KSKeyValueStore));
        if (store == NULL) {
            munmap(mapped, capacity);
            close(fd);
            return NULL;
        }

        store->storage = (uint8_t *)mapped;
        store->capacity = capacity;
        store->fd = fd;
        store->maxKeyLength = config->maxKeyLength > 0 ? config->maxKeyLength : 256;
        store->maxStringLength = config->maxStringLength;
        initHeader(store->storage);

        return store;
    }

    return NULL;
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

void kskvs_setString(KSKeyValueStore *store, const char *key, const char *value)
{
    if (store == NULL) {
        KSLOG_DEBUG("KVS setString called with NULL store (not yet installed?)");
        return;
    }
    if (value == NULL) {
        kskvs_removeValue(store, key);
        return;
    }
    uint16_t len = (uint16_t)strlen(value);
    if (store->maxStringLength > 0 && len > store->maxStringLength) {
        KSLOG_ERROR("KVS string value too long (%u > %u), truncating", len, store->maxStringLength);
        len = store->maxStringLength;
    }
    appendRecord(store, key, KSKVSTypeString, value, len);
}

void kskvs_setInt64(KSKeyValueStore *store, const char *key, int64_t value)
{
    appendRecord(store, key, KSKVSTypeInt64, &value, sizeof(value));
}

void kskvs_setUInt64(KSKeyValueStore *store, const char *key, uint64_t value)
{
    appendRecord(store, key, KSKVSTypeUInt64, &value, sizeof(value));
}

void kskvs_setDouble(KSKeyValueStore *store, const char *key, double value)
{
    appendRecord(store, key, KSKVSTypeDouble, &value, sizeof(value));
}

void kskvs_setBool(KSKeyValueStore *store, const char *key, bool value)
{
    uint8_t byte = value ? 1 : 0;
    appendRecord(store, key, KSKVSTypeBool, &byte, sizeof(byte));
}

void kskvs_setDate(KSKeyValueStore *store, const char *key, uint64_t nanosecondsSince1970)
{
    appendRecord(store, key, KSKVSTypeDate, &nanosecondsSince1970, sizeof(nanosecondsSince1970));
}

void kskvs_removeValue(KSKeyValueStore *store, const char *key) { appendRecord(store, key, KSKVSTypeRemoved, NULL, 0); }

// ============================================================================
#pragma mark - Iteration -
// ============================================================================

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
            if (rec->type == KSKVSTypeRemoved) {
                if (callbacks->onRemoved) {
                    callbacks->onRemoved(key, keyLen, context);
                }
            } else {
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
                        if (callbacks->onDate && rec->valueLen == sizeof(uint64_t)) {
                            uint64_t val;
                            memcpy(&val, valueBytes, sizeof(val));
                            callbacks->onDate(key, keyLen, val, context);
                        }
                        break;
                    default:
                        break;
                }
            }
        }

        pos += recordSize;
    }
}

