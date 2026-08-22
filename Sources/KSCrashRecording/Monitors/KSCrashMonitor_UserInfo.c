//
//  KSCrashMonitor_UserInfo.c
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

#include "KSCrashMonitor_UserInfo.h"

#include "KSCrashMonitor.h"
#include "KSCrashReportStoreC.h"
#include "KSFileUtils.h"
#include "KSKeyValueStore.h"

// #define KSLogger_LocalLevel TRACE
#include <os/lock.h>
#include <string.h>

#include "KSLogger.h"

#define KSUSERINFO_INITIAL_CAPACITY 4096
#define KSUSERINFO_MAX_KEY_LENGTH KSCRASH_USERINFO_MAX_KEY_LENGTH
#define KSUSERINFO_MAX_STRING_LENGTH KSCRASH_USERINFO_MAX_STRING_LENGTH
#define KSUSERINFO_MONITOR_ID KSCRS_MONITOR_ID_USERINFO

// ============================================================================
#pragma mark - State -
// ============================================================================

static KSKeyValueStore *g_store = NULL;
static os_unfair_lock g_lock = OS_UNFAIR_LOCK_INIT;
static KSCrash_ExceptionHandlerCallbacks *g_callbacks = NULL;
static bool g_isEnabled = false;

static const KSKVSConfig g_config = {
    .initialCapacity = KSUSERINFO_INITIAL_CAPACITY,
    .maxKeyLength = KSUSERINFO_MAX_KEY_LENGTH,
    .maxStringLength = KSUSERINFO_MAX_STRING_LENGTH,
};

// ============================================================================
#pragma mark - Public Setters -
// ============================================================================

// Setters are no-ops before install (g_store is NULL).

void kscm_userinfo_setString(const char *key, const char *value)
{
    os_unfair_lock_lock(&g_lock);
    kskvs_setString(g_store, key, value);
    os_unfair_lock_unlock(&g_lock);
}

void kscm_userinfo_setInt64(const char *key, int64_t value)
{
    os_unfair_lock_lock(&g_lock);
    kskvs_setInt64(g_store, key, value);
    os_unfair_lock_unlock(&g_lock);
}

void kscm_userinfo_setUInt64(const char *key, uint64_t value)
{
    os_unfair_lock_lock(&g_lock);
    kskvs_setUInt64(g_store, key, value);
    os_unfair_lock_unlock(&g_lock);
}

void kscm_userinfo_setDouble(const char *key, double value)
{
    os_unfair_lock_lock(&g_lock);
    kskvs_setDouble(g_store, key, value);
    os_unfair_lock_unlock(&g_lock);
}

void kscm_userinfo_setBool(const char *key, bool value)
{
    os_unfair_lock_lock(&g_lock);
    kskvs_setBool(g_store, key, value);
    os_unfair_lock_unlock(&g_lock);
}

void kscm_userinfo_setDate(const char *key, uint64_t nanosecondsSince1970)
{
    os_unfair_lock_lock(&g_lock);
    kskvs_setDate(g_store, key, nanosecondsSince1970);
    os_unfair_lock_unlock(&g_lock);
}

void kscm_userinfo_removeValue(const char *key)
{
    os_unfair_lock_lock(&g_lock);
    kskvs_removeValue(g_store, key);
    os_unfair_lock_unlock(&g_lock);
}

// ============================================================================
#pragma mark - Reading -
// ============================================================================

// The store is an append-only log, so a replay in order makes the last
// record for a key the current one; a tombstone clears it. Both readers run
// under g_lock, like the setters.

typedef struct {
    const char *key;
    size_t keyLength;
    KSCrashUserInfoValue *out;
    bool found;
} LookupContext;

static bool lookupMatches(const LookupContext *ctx, const char *key, uint16_t keyLen)
{
    return keyLen == ctx->keyLength && memcmp(key, ctx->key, keyLen) == 0;
}

static void lookupString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *context)
{
    LookupContext *ctx = context;
    if (!lookupMatches(ctx, key, keyLen)) {
        return;
    }
    size_t length = valueLen < KSUSERINFO_MAX_STRING_LENGTH ? valueLen : KSUSERINFO_MAX_STRING_LENGTH;
    memcpy(ctx->out->string, value, length);
    ctx->out->string[length] = '\0';
    ctx->out->type = KSCrashUserInfoValueTypeString;
    ctx->found = true;
}

static void lookupInt64(const char *key, uint16_t keyLen, int64_t value, void *context)
{
    LookupContext *ctx = context;
    if (lookupMatches(ctx, key, keyLen)) {
        ctx->out->type = KSCrashUserInfoValueTypeInt64;
        ctx->out->value.int64Value = value;
        ctx->found = true;
    }
}

static void lookupUInt64(const char *key, uint16_t keyLen, uint64_t value, void *context)
{
    LookupContext *ctx = context;
    if (lookupMatches(ctx, key, keyLen)) {
        ctx->out->type = KSCrashUserInfoValueTypeUInt64;
        ctx->out->value.uint64Value = value;
        ctx->found = true;
    }
}

static void lookupDouble(const char *key, uint16_t keyLen, double value, void *context)
{
    LookupContext *ctx = context;
    if (lookupMatches(ctx, key, keyLen)) {
        ctx->out->type = KSCrashUserInfoValueTypeDouble;
        ctx->out->value.doubleValue = value;
        ctx->found = true;
    }
}

static void lookupBool(const char *key, uint16_t keyLen, bool value, void *context)
{
    LookupContext *ctx = context;
    if (lookupMatches(ctx, key, keyLen)) {
        ctx->out->type = KSCrashUserInfoValueTypeBool;
        ctx->out->value.boolValue = value;
        ctx->found = true;
    }
}

static void lookupDate(const char *key, uint16_t keyLen, uint64_t nanosecondsSince1970, void *context)
{
    LookupContext *ctx = context;
    if (lookupMatches(ctx, key, keyLen)) {
        ctx->out->type = KSCrashUserInfoValueTypeDate;
        ctx->out->value.dateNanoseconds = nanosecondsSince1970;
        ctx->found = true;
    }
}

static void lookupRemoved(const char *key, uint16_t keyLen, void *context)
{
    LookupContext *ctx = context;
    if (lookupMatches(ctx, key, keyLen)) {
        ctx->out->type = KSCrashUserInfoValueTypeNone;
        ctx->found = false;
    }
}

bool kscm_userinfo_copyValue(const char *key, KSCrashUserInfoValue *valueOut)
{
    if (key == NULL || valueOut == NULL) {
        return false;
    }
    memset(valueOut, 0, sizeof(*valueOut));
    LookupContext ctx = { .key = key, .keyLength = strlen(key), .out = valueOut, .found = false };
    KSKVSCallbacks callbacks = {
        .onString = lookupString,
        .onInt64 = lookupInt64,
        .onUInt64 = lookupUInt64,
        .onDouble = lookupDouble,
        .onBool = lookupBool,
        .onDate = lookupDate,
        .onRemoved = lookupRemoved,
    };
    os_unfair_lock_lock(&g_lock);
    if (g_store != NULL) {
        kskvs_iterate(g_store, &callbacks, &ctx);
    }
    os_unfair_lock_unlock(&g_lock);
    return ctx.found;
}

// The live keys are collected under the lock, then handed to the callback
// after it is released, so the callback may use the store.
typedef struct {
    char (*keys)[KSUSERINFO_MAX_KEY_LENGTH + 1];
    int count;
    int capacity;
    bool failed;
} KeysContext;

static int keysIndexOf(const KeysContext *ctx, const char *key, uint16_t keyLen)
{
    for (int i = 0; i < ctx->count; i++) {
        if (strlen(ctx->keys[i]) == keyLen && memcmp(ctx->keys[i], key, keyLen) == 0) {
            return i;
        }
    }
    return -1;
}

static void keysRecord(const char *key, uint16_t keyLen, KeysContext *ctx)
{
    if (ctx->failed || keyLen > KSUSERINFO_MAX_KEY_LENGTH || keysIndexOf(ctx, key, keyLen) >= 0) {
        return;
    }
    if (ctx->count == ctx->capacity) {
        int grown = ctx->capacity == 0 ? 16 : ctx->capacity * 2;
        void *keys = realloc(ctx->keys, sizeof(ctx->keys[0]) * (size_t)grown);
        if (keys == NULL) {
            ctx->failed = true;
            return;
        }
        ctx->keys = keys;
        ctx->capacity = grown;
    }
    memcpy(ctx->keys[ctx->count], key, keyLen);
    ctx->keys[ctx->count][keyLen] = '\0';
    ctx->count++;
}

static void keysOnString(const char *key, uint16_t keyLen, __unused const char *v, __unused uint16_t l, void *ctx)
{
    keysRecord(key, keyLen, ctx);
}
static void keysOnInt64(const char *key, uint16_t keyLen, __unused int64_t v, void *ctx)
{
    keysRecord(key, keyLen, ctx);
}
static void keysOnUInt64(const char *key, uint16_t keyLen, __unused uint64_t v, void *ctx)
{
    keysRecord(key, keyLen, ctx);
}
static void keysOnDouble(const char *key, uint16_t keyLen, __unused double v, void *ctx)
{
    keysRecord(key, keyLen, ctx);
}
static void keysOnBool(const char *key, uint16_t keyLen, __unused bool v, void *ctx) { keysRecord(key, keyLen, ctx); }
static void keysOnDate(const char *key, uint16_t keyLen, __unused uint64_t v, void *ctx)
{
    keysRecord(key, keyLen, ctx);
}

static void keysOnRemoved(const char *key, uint16_t keyLen, void *context)
{
    KeysContext *ctx = context;
    int index = keysIndexOf(ctx, key, keyLen);
    if (index < 0) {
        return;
    }
    // Drop the slot and close the gap; order is not part of the contract.
    ctx->count--;
    if (index != ctx->count) {
        memcpy(ctx->keys[index], ctx->keys[ctx->count], sizeof(ctx->keys[0]));
    }
}

void kscm_userinfo_enumerateKeys(KSCrashUserInfoKeyCallback callback, void *context)
{
    if (callback == NULL) {
        return;
    }
    KeysContext ctx = { .keys = NULL, .count = 0, .capacity = 0, .failed = false };
    KSKVSCallbacks callbacks = {
        .onString = keysOnString,
        .onInt64 = keysOnInt64,
        .onUInt64 = keysOnUInt64,
        .onDouble = keysOnDouble,
        .onBool = keysOnBool,
        .onDate = keysOnDate,
        .onRemoved = keysOnRemoved,
    };
    os_unfair_lock_lock(&g_lock);
    if (g_store != NULL) {
        kskvs_iterate(g_store, &callbacks, &ctx);
    }
    os_unfair_lock_unlock(&g_lock);
    if (!ctx.failed) {
        for (int i = 0; i < ctx.count; i++) {
            callback(ctx.keys[i], context);
        }
    }
    free(ctx.keys);
}

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    g_callbacks = callbacks;
}

static const char *monitorId(__unused void *context) { return KSUSERINFO_MONITOR_ID; }

static void setEnabled(bool isEnabled, __unused void *context)
{
    if (isEnabled == g_isEnabled) {
        return;
    }

    if (!isEnabled) {
        os_unfair_lock_lock(&g_lock);
        if (g_store != NULL) {
            kskvs_destroy(g_store);
            g_store = NULL;
        }
        g_isEnabled = false;
        os_unfair_lock_unlock(&g_lock);
        return;
    }

    if (g_callbacks == NULL || g_callbacks->getRunSidecarPath == NULL) {
        KSLOG_ERROR("UserInfo monitor enabled but no run sidecar path provider");
        return;
    }

    char sidecarPath[KSFU_MAX_PATH_LENGTH];
    if (!g_callbacks->getRunSidecarPath(KSUSERINFO_MONITOR_ID, sidecarPath, sizeof(sidecarPath))) {
        KSLOG_ERROR("Failed to get UserInfo run sidecar path");
        return;
    }

    os_unfair_lock_lock(&g_lock);

    g_store = kskvs_create(sidecarPath, KSKVSModeReadWriteCreate, &g_config, NULL);
    if (g_store == NULL) {
        KSLOG_ERROR("Failed to create UserInfo mmap store");
    }

    // Only report enabled after successful store creation.
    g_isEnabled = (g_store != NULL);

    os_unfair_lock_unlock(&g_lock);
}

static bool isEnabled(__unused void *context) { return g_isEnabled; }

KSCrashMonitorAPI *kscm_userinfo_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
        api.createStitchedReport = kscm_userinfo_createStitchedReport;
    }
    return &api;
}

// ============================================================================
#pragma mark - Testing Support -
// ============================================================================

// Declared as extern in test files. Tears down storage so tests start clean.
__attribute__((unused)) void kscm_userinfo_test_reset(void)
{
    os_unfair_lock_lock(&g_lock);
    if (g_store != NULL) {
        kskvs_destroy(g_store);
        g_store = NULL;
    }
    g_isEnabled = false;
    os_unfair_lock_unlock(&g_lock);
}

// Returns the current store for test inspection. Caller holds no lock.
__attribute__((unused)) KSKeyValueStore *kscm_userinfo_test_getStore(void) { return g_store; }

// Creates the store at the given path so setters work in tests without full install.
__attribute__((unused)) bool kscm_userinfo_test_createStore(const char *path)
{
    os_unfair_lock_lock(&g_lock);
    if (g_store != NULL) {
        kskvs_destroy(g_store);
    }
    g_store = kskvs_create(path, KSKVSModeReadWriteCreate, &g_config, NULL);
    os_unfair_lock_unlock(&g_lock);
    return g_store != NULL;
}
