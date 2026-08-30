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
 *
 * Keys and values are variable-size, up to 64KB each.
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

/** Ceiling on a store file, for both growth and reading an existing one.
 *  Records are bounded individually (64KB each) but their number is not, and
 *  the file only ever grows within a run, so without this a live store is
 *  unbounded on the user's disk and stays mapped for the process lifetime.
 *  A write that would cross it is refused, which callers surface as the key
 *  becoming absent.
 */
#define KSKVS_MAX_CAPACITY (16u * 1024u * 1024u)

/** Configuration for store creation. */
typedef struct {
    uint32_t initialCapacity; /**< Starting buffer size (e.g. 4096), at most KSKVS_MAX_CAPACITY. */
} KSKVSConfig;

/** Outcome of kskvs_create. */
typedef enum {
    KSKVSOpenSuccess = 0,
    /** Nothing exists at the path. */
    KSKVSOpenAbsent,
    /** The file exists but is not a valid store; no retry can succeed. */
    KSKVSOpenCorrupt,
    /** An environmental failure (I/O, allocation) that may not recur. */
    KSKVSOpenFailure,
} KSKVSOpenStatus;

// ============================================================================
#pragma mark - Lifecycle -
// ============================================================================

/** Create a store instance backed by a file.
 *
 *  KSKVSModeRead:            reads existing file into heap. config may be NULL.
 *  KSKVSModeReadWriteCreate: creates file, mmap MAP_SHARED. config is required.
 *
 *  Read mode may target a file this process is also writing, which is what a
 *  report finalized during its own run does: the load takes a whole snapshot,
 *  never one a concurrent compaction or growth is part way through.
 *
 *  @param outStatus Optional; receives why the call returned NULL
 *                   (KSKVSOpenSuccess when it didn't).
 *  @return A new store, or NULL on failure. Caller must call kskvs_destroy().
 */
KSKeyValueStore *kskvs_create(const char *path, KSKVSMode mode, const KSKVSConfig *config, KSKVSOpenStatus *outStatus);

/** Destroy a store and release all resources (munmap/free + close fd). */
void kskvs_destroy(KSKeyValueStore *store);

// ============================================================================
#pragma mark - Typed Setters (NOT thread-safe) -
// ============================================================================

/** Each setter returns false when the write is rejected (empty key, or a key
 *  or value past the 64KB bound) or cannot be persisted; the
 *  store is unchanged. Nothing is ever truncated.
 *
 *  A write is also rejected once the store has reached its capacity ceiling
 *  and compaction cannot free room for the record.
 *
 *  NOT thread-safe: concurrent writers to a store are the caller's
 *  responsibility. The store's only internal guarantee is that a read-mode
 *  open never observes a partially applied write.
 */
bool kskvs_setString(KSKeyValueStore *store, const char *key, const char *value);
bool kskvs_setInt64(KSKeyValueStore *store, const char *key, int64_t value);
bool kskvs_setUInt64(KSKeyValueStore *store, const char *key, uint64_t value);
bool kskvs_setDouble(KSKeyValueStore *store, const char *key, double value);
bool kskvs_setBool(KSKeyValueStore *store, const char *key, bool value);
bool kskvs_setDate(KSKeyValueStore *store, const char *key, int64_t nanosecondsSince1970);

/** Stores `length` bytes of UTF-8 JSON text as the key's value. Only a JSON
 *  container is a value: bytes that do not open an array or an object are
 *  rejected. The store does not parse further; consumers interpret the bytes
 *  at read time and treat anything but a container as absence.
 */
bool kskvs_setJSON(KSKeyValueStore *store, const char *key, const char *json, size_t length);

/** Makes the key absent. Unlike the setters this does not fail for want of
 *  room: a store too full to hold a removal record marks the key's existing
 *  record removed in place, so a caller can always retract a value.
 */
bool kskvs_removeValue(KSKeyValueStore *store, const char *key);

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
    void (*onDate)(const char *key, uint16_t keyLen, int64_t nanosecondsSince1970, void *ctx);
    /** One JSON container (array or object) as UTF-8 text, not
     *  NUL-terminated and not validated by the store; a consumer that cannot
     *  parse it to a container treats the key as absent. */
    void (*onJSON)(const char *key, uint16_t keyLen, const char *json, uint16_t jsonLen, void *ctx);
    /** Called for keys whose final resolved state is a tombstone (removal).
     *  Allows callers to actively delete keys from a pre-existing dictionary. */
    void (*onRemoved)(const char *key, uint16_t keyLen, void *ctx);
} KSKVSCallbacks;

/** Iterate resolved (last-write-wins) records and tombstones.
 *  Works on any store (file-backed writable or read-only).
 */
void kskvs_iterate(const KSKeyValueStore *store, const KSKVSCallbacks *callbacks, void *context);

/** Look up one key's resolved (last-write-wins) state: exactly one callback
 *  fires with the latest value, onRemoved fires when the last record is a
 *  tombstone, and nothing fires for a key the store never saw.
 *  Works on any store (file-backed writable or read-only).
 */
void kskvs_lookup(const KSKeyValueStore *store, const char *key, const KSKVSCallbacks *callbacks, void *context);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSKeyValueStore_h
