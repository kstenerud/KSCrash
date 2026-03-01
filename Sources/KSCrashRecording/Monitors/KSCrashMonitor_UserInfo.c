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
#include "KSFileUtils.h"
#include "KSKeyValueStore.h"

// #define KSLogger_LocalLevel TRACE
#include <os/lock.h>
#include <string.h>

#include "KSLogger.h"

#define KSUSERINFO_INITIAL_CAPACITY 4096
#define KSUSERINFO_MAX_KEY_LENGTH 256
#define KSUSERINFO_MAX_STRING_LENGTH 1024
#define KSUSERINFO_MONITOR_ID "UserInfo"

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

    g_store = kskvs_create(sidecarPath, KSKVSModeReadWriteCreate, &g_config);
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
        api.stitchReport = kscm_userinfo_stitchReport;
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
    g_store = kskvs_create(path, KSKVSModeReadWriteCreate, &g_config);
    os_unfair_lock_unlock(&g_lock);
    return g_store != NULL;
}
