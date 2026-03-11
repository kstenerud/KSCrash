//
//  KSKeyValueStore.h
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

/**
 * @file KSKeyValueStore.h
 * @brief Append-only key-value store backed by an mmap'd file.
 *
 * Instance-based, lock-free storage engine. The caller is responsible
 * for synchronization. Supports typed setters, last-write-wins
 * iteration, compaction, and automatic growth.
 */

#ifndef HDR_KSKeyValueStore_h
#define HDR_KSKeyValueStore_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KSKeyValueStore KSKeyValueStore;

typedef enum {
    /** Read existing file into heap buffer (for stitch / read-only use). */
    KSKVSModeRead,
    /** Create/truncate file and mmap MAP_SHARED (for live writing). */
    KSKVSModeReadWriteCreate,
} KSKVSMode;

/** Configuration for store creation. */
typedef struct {
    uint32_t initialCapacity; /**< Starting buffer size (e.g. 4096). */
    uint16_t maxKeyLength;    /**< Keys longer than this are truncated (e.g. 256). */
    uint16_t maxStringLength; /**< String values longer than this are truncated (e.g. 1024). */
} KSKVSConfig;

// ============================================================================
#pragma mark - Lifecycle -
// ============================================================================

/** Create a store instance backed by a file.
 *
 *  KSKVSModeRead:            reads existing file into heap. config may be NULL.
 *  KSKVSModeReadWriteCreate: creates file, mmap MAP_SHARED. config is required.
 *
 *  @return A new store, or NULL on failure. Caller must call kskvs_destroy().
 */
KSKeyValueStore *kskvs_create(const char *path, KSKVSMode mode, const KSKVSConfig *config);

/** Destroy a store and release all resources (munmap/free + close fd). */
void kskvs_destroy(KSKeyValueStore *store);

// ============================================================================
#pragma mark - Typed Setters (NOT thread-safe) -
// ============================================================================

void kskvs_setString(KSKeyValueStore *store, const char *key, const char *value);
void kskvs_setInt64(KSKeyValueStore *store, const char *key, int64_t value);
void kskvs_setUInt64(KSKeyValueStore *store, const char *key, uint64_t value);
void kskvs_setDouble(KSKeyValueStore *store, const char *key, double value);
void kskvs_setBool(KSKeyValueStore *store, const char *key, bool value);
void kskvs_setDate(KSKeyValueStore *store, const char *key, uint64_t nanosecondsSince1970);
void kskvs_removeValue(KSKeyValueStore *store, const char *key);

// ============================================================================
#pragma mark - Reading -
// ============================================================================

/** Callbacks for typed iteration over resolved records. */
typedef struct {
    void (*onString)(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx);
    void (*onInt64)(const char *key, uint16_t keyLen, int64_t value, void *ctx);
    void (*onUInt64)(const char *key, uint16_t keyLen, uint64_t value, void *ctx);
    void (*onDouble)(const char *key, uint16_t keyLen, double value, void *ctx);
    void (*onBool)(const char *key, uint16_t keyLen, bool value, void *ctx);
    void (*onDate)(const char *key, uint16_t keyLen, uint64_t nanosecondsSince1970, void *ctx);
    /** Called for keys whose final resolved state is a tombstone (removal).
     *  Allows callers to actively delete keys from a pre-existing dictionary. */
    void (*onRemoved)(const char *key, uint16_t keyLen, void *ctx);
} KSKVSCallbacks;

/** Iterate resolved (last-write-wins) records and tombstones.
 *  Works on any store (file-backed writable or read-only).
 */
void kskvs_iterate(const KSKeyValueStore *store, const KSKVSCallbacks *callbacks, void *context);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSKeyValueStore_h
