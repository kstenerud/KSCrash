//
//  KSCrashMonitor_Watchdog.c
//
//  Created by Alexander Cohen on 2025-11-04.
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

#include "KSCrashMonitor_Watchdog.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach/task_policy.h>
#include <os/lock.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSCrashReportFields.h"
#include "KSDebug.h"
#include "KSFileUtils.h"
#include "KSHang.h"
#include "KSID.h"
#include "KSStackCursor_MachineContext.h"
#include "KSThread.h"
#include "Unwind/KSStackCursor_Unwind.h"

// #define KSLogger_LocalLevel TRACE
#include "KSCrashMonitor_WatchdogSidecar.h"
#include "KSLogger.h"

// ============================================================================
#pragma mark - Observer -
// ============================================================================

#define KSHANG_MAX_OBSERVERS 8

typedef struct {
    KSHangObserverCallback func;
    void *context;
    bool active;
} HangObserver;

// ============================================================================
#pragma mark - Hang Monitor -
// ============================================================================

typedef struct KSHangMonitor {
    CFRunLoopRef runLoop;
    double threshold;
    CFRunLoopObserverRef observer;
    CFRunLoopRef watchdogRunLoop;
    CFRunLoopTimerRef watchdogTimer;
    dispatch_semaphore_t threadExitSemaphore;

    bool reportsHangs;
    os_unfair_lock lock;
    KSHangState hang;

    /** mmap'd sidecar for the current hang, or NULL. */
    KSHangSidecar *sidecar;
    char sidecarPath[PATH_MAX];

    HangObserver observers[KSHANG_MAX_OBSERVERS];
    int observerCount;
} KSHangMonitor;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static atomic_bool g_isEnabled = false;
static KSHangMonitor *g_watchdog = NULL;
static KSThread g_mainQueueThread = 0;
static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };

// ============================================================================
#pragma mark - Utilities -
// ============================================================================

static uint64_t MonotonicUptime(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

static int TaskRole(void)
{
#if TARGET_OS_TV || TARGET_OS_WATCH
    return TASK_UNSPECIFIED;
#else
    task_category_policy_data_t policy;
    mach_msg_type_number_t count = TASK_CATEGORY_POLICY_COUNT;
    boolean_t getDefault = false;

    kern_return_t kr =
        task_policy_get(mach_task_self(), TASK_CATEGORY_POLICY, (task_policy_t)&policy, &count, &getDefault);

    return kr == KERN_SUCCESS ? policy.role : TASK_UNSPECIFIED;
#endif
}

// ============================================================================
#pragma mark - Sidecar lifecycle -
// ============================================================================

static KSHangSidecar *sidecar_open(KSHangMonitor *monitor, int64_t reportID)
{
    if (!g_callbacks.getSidecarPath) {
        return NULL;
    }

    if (!g_callbacks.getSidecarPath("Watchdog", reportID, monitor->sidecarPath, sizeof(monitor->sidecarPath))) {
        monitor->sidecarPath[0] = '\0';
        return NULL;
    }

    KSHangSidecar *sc = (KSHangSidecar *)ksfu_mmap(monitor->sidecarPath, sizeof(KSHangSidecar));
    if (!sc) {
        KSLOG_ERROR("Failed to mmap sidecar at %s", monitor->sidecarPath);
        monitor->sidecarPath[0] = '\0';
        return NULL;
    }

    sc->magic = KSHANG_SIDECAR_MAGIC;
    sc->version = KSHANG_SIDECAR_CURRENT_VERSION;
    sc->recovered = false;
    return sc;
}

static void sidecar_update(KSHangSidecar *sc, uint64_t endTimestamp, task_role_t endRole)
{
    if (!sc) {
        return;
    }
    sc->endTimestamp = endTimestamp;
    sc->endRole = endRole;
}

static void sidecar_finalize(KSHangMonitor *monitor, bool recovered)
{
    if (monitor->sidecar) {
        monitor->sidecar->recovered = recovered;
        ksfu_munmap(monitor->sidecar, sizeof(KSHangSidecar));
        monitor->sidecar = NULL;
    }
}

static void sidecar_delete(KSHangMonitor *monitor)
{
    sidecar_finalize(monitor, false);
    if (monitor->sidecarPath[0] != '\0') {
        unlink(monitor->sidecarPath);
        monitor->sidecarPath[0] = '\0';
    }
}

// ============================================================================
#pragma mark - Observer notification -
// ============================================================================

static void notifyObservers(KSHangMonitor *monitor, KSHangChangeType type, uint64_t start, uint64_t now)
{
    HangObserver snapshot[KSHANG_MAX_OBSERVERS];
    int count = 0;

    os_unfair_lock_lock(&monitor->lock);
    count = monitor->observerCount;
    memcpy(snapshot, monitor->observers, sizeof(snapshot));
    os_unfair_lock_unlock(&monitor->lock);

    for (int i = 0; i < count; i++) {
        if (snapshot[i].active && snapshot[i].func) {
            snapshot[i].func(type, start, now, snapshot[i].context);
        }
    }
}

// ============================================================================
#pragma mark - Report writing -
// ============================================================================

static void populateReportForCurrentHang(KSHangMonitor *monitor)
{
    os_unfair_lock_lock(&monitor->lock);
    KSHangState hang = monitor->hang;
    os_unfair_lock_unlock(&monitor->lock);

    if (!hang.active) {
        KSLOG_DEBUG("hang ended before report could be populated");
        return;
    }

    if (!g_callbacks.handleWithResult || !g_callbacks.notify) {
        return;
    }

    KSCrash_MonitorContext *crashContext = g_callbacks.notify(
        (thread_t)g_mainQueueThread,
        (KSCrash_ExceptionHandlingRequirements) {
            .asyncSafety = false, .isFatal = false, .shouldRecordAllThreads = true, .shouldWriteReport = true });

    KSMachineContext machineContext = { 0 };
    ksmc_getContextForThreadCheckingStackOverflow(g_mainQueueThread, &machineContext, true, false);
    KSStackCursor stackCursor;
    kssc_initWithUnwind(&stackCursor, KSSC_MAX_STACK_DEPTH, &machineContext);

    kscm_fillMonitorContext(crashContext, kscm_watchdog_getAPI());
    crashContext->registersAreValid = true;
    crashContext->offendingMachineContext = &machineContext;
    crashContext->stackCursor = &stackCursor;

    crashContext->signal.signum = SIGKILL;
    crashContext->signal.sigcode = 0;

    crashContext->mach.type = EXC_CRASH;
    crashContext->mach.code = SIGKILL;
    crashContext->mach.subcode = KERN_TERMINATED;

    crashContext->exitReason.code = 0x8badf00d;

    crashContext->Hang.inProgress = true;
    crashContext->Hang.timestamp = hang.timestamp;
    crashContext->Hang.role = hang.role;
    crashContext->Hang.endTimestamp = hang.endTimestamp;
    crashContext->Hang.endRole = hang.endRole;

    KSCrash_ReportResult result = { 0 };
    g_callbacks.handleWithResult(crashContext, &result);

    os_unfair_lock_lock(&monitor->lock);
    if (monitor->hang.active && monitor->hang.timestamp == hang.timestamp) {
        monitor->hang.reportId = result.reportId;
        strncpy(monitor->hang.path, result.path, PATH_MAX - 1);
        monitor->hang.path[PATH_MAX - 1] = '\0';

        monitor->sidecar = sidecar_open(monitor, result.reportId);
        sidecar_update(monitor->sidecar, monitor->hang.endTimestamp, monitor->hang.endRole);
    } else {
        KSLOG_DEBUG("hang changed during report population - discarding");
    }
    os_unfair_lock_unlock(&monitor->lock);

    notifyObservers(monitor, KSHangChangeTypeStarted, hang.timestamp, hang.endTimestamp);
}

static void writeUpdatedReport(KSHangMonitor *monitor)
{
    uint64_t timestampStart = 0;
    uint64_t timestampEnd = 0;

    os_unfair_lock_lock(&monitor->lock);
    if (!monitor->hang.active) {
        os_unfair_lock_unlock(&monitor->lock);
        return;
    }
    timestampStart = monitor->hang.timestamp;
    timestampEnd = monitor->hang.endTimestamp;
    sidecar_update(monitor->sidecar, timestampEnd, monitor->hang.endRole);
    os_unfair_lock_unlock(&monitor->lock);

    notifyObservers(monitor, KSHangChangeTypeUpdated, timestampStart, timestampEnd);
}

static void endOwnedHang(KSHangMonitor *monitor, KSHangState hang)
{
    if (hang.path[0] != '\0') {
        if (monitor->reportsHangs) {
            sidecar_finalize(monitor, true);
        } else {
            sidecar_delete(monitor);
            if (unlink(hang.path) != 0) {
                KSLOG_ERROR("Failed to delete hang report at %s: %s", hang.path, strerror(errno));
            }
        }
    } else {
        sidecar_delete(monitor);
    }

    notifyObservers(monitor, KSHangChangeTypeEnded, hang.timestamp, hang.endTimestamp);
}

// ============================================================================
#pragma mark - Ping / Activity handlers -
// ============================================================================

typedef struct {
    KSHangMonitor *monitor;
    uint64_t enterTime;
} PingTimerContext;

static void handlePing(CFRunLoopTimerRef timer, void *info)
{
    (void)timer;
    PingTimerContext *ctx = (PingTimerContext *)info;
    KSHangMonitor *monitor = ctx->monitor;

    const uint64_t thresholdInNs = (uint64_t)(monitor->threshold * 1000000000);
    uint64_t now = MonotonicUptime();
    uint64_t hangTime = now - ctx->enterTime;

    if (hangTime < thresholdInNs) {
        return;
    }

    task_role_t currentRole = TaskRole();

    bool shouldStartNewHang = false;
    bool shouldUpdateHang = false;

    os_unfair_lock_lock(&monitor->lock);
    if (!monitor->hang.active) {
        kshangstate_init(&monitor->hang, ctx->enterTime, currentRole);
        monitor->hang.endTimestamp = now;
        monitor->hang.endRole = currentRole;
        shouldStartNewHang = true;
    } else {
        monitor->hang.endTimestamp = now;
        monitor->hang.endRole = currentRole;
        shouldUpdateHang = true;
    }
    os_unfair_lock_unlock(&monitor->lock);

    if (shouldStartNewHang) {
        populateReportForCurrentHang(monitor);
    } else if (shouldUpdateHang) {
        writeUpdatedReport(monitor);
    }
}

static void pingTimerRelease(const void *info)
{
    PingTimerContext *ctx = (PingTimerContext *)info;
    free(ctx);
}

static void schedulePings(KSHangMonitor *monitor)
{
    PingTimerContext *ctx = (PingTimerContext *)calloc(1, sizeof(PingTimerContext));
    ctx->monitor = monitor;
    ctx->enterTime = MonotonicUptime();

    CFRunLoopTimerContext timerCtx = {
        .version = 0, .info = ctx, .retain = NULL, .release = pingTimerRelease, .copyDescription = NULL
    };
    monitor->watchdogTimer =
        CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent(), monitor->threshold, 0, 0, handlePing, &timerCtx);
    CFRunLoopAddTimer(monitor->watchdogRunLoop, monitor->watchdogTimer, kCFRunLoopCommonModes);
}

static void handleActivity(CFRunLoopObserverRef obs, CFRunLoopActivity activity, void *info)
{
    (void)obs;
    KSHangMonitor *monitor = (KSHangMonitor *)info;

    if (monitor->watchdogTimer) {
        CFRunLoopTimerInvalidate(monitor->watchdogTimer);
        CFRelease(monitor->watchdogTimer);
        monitor->watchdogTimer = NULL;
    }

    if (activity == kCFRunLoopBeforeWaiting) {
        KSHangState hang = { 0 };
        bool hadHang = false;

        os_unfair_lock_lock(&monitor->lock);
        if (monitor->hang.active) {
            hang = monitor->hang;
            kshangstate_clear(&monitor->hang);
            hadHang = true;
        }
        os_unfair_lock_unlock(&monitor->lock);

        if (!hadHang) {
            return;
        }

        hang.endTimestamp = MonotonicUptime();
        hang.endRole = TaskRole();
        endOwnedHang(monitor, hang);

    } else if (activity == kCFRunLoopAfterWaiting) {
        schedulePings(monitor);
    }
}

// ============================================================================
#pragma mark - Thread lifecycle -
// ============================================================================

typedef struct {
    KSHangMonitor *monitor;
    dispatch_semaphore_t setupSemaphore;
} WatchdogThreadArg;

static void *watchdog_thread_main(void *arg)
{
    WatchdogThreadArg *threadArg = (WatchdogThreadArg *)arg;
    KSHangMonitor *monitor = threadArg->monitor;
    dispatch_semaphore_t setupSemaphore = threadArg->setupSemaphore;
    free(threadArg);

    pthread_setname_np("com.kscrash.hang.watchdog.thread");

    CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();

    os_unfair_lock_lock(&monitor->lock);
    monitor->watchdogRunLoop = currentRunLoop;
    os_unfair_lock_unlock(&monitor->lock);

    CFRunLoopSourceContext srcCtx = { .version = 0, .info = NULL };
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &srcCtx);
    CFRunLoopAddSource(currentRunLoop, source, kCFRunLoopCommonModes);
    CFRelease(source);

    CFRunLoopPerformBlock(currentRunLoop, kCFRunLoopCommonModes, ^{
        dispatch_semaphore_signal(setupSemaphore);
    });

    CFRunLoopRun();

    dispatch_semaphore_signal(monitor->threadExitSemaphore);
    return NULL;
}

// ============================================================================
#pragma mark - Monitor create / destroy -
// ============================================================================

static KSHangMonitor *watchdog_create(CFRunLoopRef runLoop, double threshold)
{
    KSHangMonitor *monitor = (KSHangMonitor *)calloc(1, sizeof(KSHangMonitor));
    if (!monitor) {
        return NULL;
    }

    monitor->reportsHangs = false;
    monitor->lock = OS_UNFAIR_LOCK_INIT;
    monitor->runLoop = runLoop;
    monitor->threshold = threshold;
    monitor->threadExitSemaphore = dispatch_semaphore_create(0);

    dispatch_semaphore_t setupSemaphore = dispatch_semaphore_create(0);

    WatchdogThreadArg *threadArg = (WatchdogThreadArg *)calloc(1, sizeof(WatchdogThreadArg));
    threadArg->monitor = monitor;
    threadArg->setupSemaphore = setupSemaphore;

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    pthread_t thread;
    pthread_create(&thread, &attr, watchdog_thread_main, threadArg);
    pthread_attr_destroy(&attr);

    dispatch_semaphore_wait(setupSemaphore, DISPATCH_TIME_FOREVER);

    schedulePings(monitor);

    CFRunLoopObserverContext obsCtx = { .version = 0, .info = monitor };
    monitor->observer = CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting, true, 0,
                                                handleActivity, &obsCtx);
    CFRunLoopAddObserver(runLoop, monitor->observer, kCFRunLoopCommonModes);

    return monitor;
}

static void watchdog_destroy(KSHangMonitor *monitor)
{
    if (!monitor) {
        return;
    }

    if (monitor->observer) {
        CFRunLoopObserverInvalidate(monitor->observer);
        CFRelease(monitor->observer);
    }

    if (monitor->watchdogTimer) {
        CFRunLoopTimerInvalidate(monitor->watchdogTimer);
        CFRelease(monitor->watchdogTimer);
    }

    CFRunLoopRef rl = NULL;
    os_unfair_lock_lock(&monitor->lock);
    rl = monitor->watchdogRunLoop;
    monitor->watchdogRunLoop = NULL;
    os_unfair_lock_unlock(&monitor->lock);

    if (rl) {
        CFRunLoopStop(rl);
    }

    if (monitor->threadExitSemaphore) {
        dispatch_semaphore_wait(monitor->threadExitSemaphore, DISPATCH_TIME_FOREVER);
    }

    sidecar_delete(monitor);

    free(monitor);
}

// ============================================================================
#pragma mark - Observer API -
// ============================================================================

const KSHangObserverToken KSHangObserverTokenNotFound = -1;

KSHangObserverToken kshang_addHangObserver(KSHangObserverCallback callback, void *context)
{
    KSHangMonitor *monitor = g_watchdog;
    if (!monitor || !callback) {
        return KSHangObserverTokenNotFound;
    }

    KSHangObserverToken token = KSHangObserverTokenNotFound;
    os_unfair_lock_lock(&monitor->lock);
    if (monitor->observerCount < KSHANG_MAX_OBSERVERS) {
        token = monitor->observerCount;
        monitor->observers[token].func = callback;
        monitor->observers[token].context = context;
        monitor->observers[token].active = true;
        monitor->observerCount++;
    }
    os_unfair_lock_unlock(&monitor->lock);
    return token;
}

void kshang_removeHangObserver(KSHangObserverToken token)
{
    KSHangMonitor *monitor = g_watchdog;
    if (!monitor || token < 0 || token >= KSHANG_MAX_OBSERVERS) {
        return;
    }

    os_unfair_lock_lock(&monitor->lock);
    if (token < monitor->observerCount) {
        monitor->observers[token].active = false;
        monitor->observers[token].func = NULL;
        monitor->observers[token].context = NULL;
    }
    os_unfair_lock_unlock(&monitor->lock);
}

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static const char *monitorId(void) { return "Watchdog"; }

static KSCrashMonitorFlag monitorFlags(void) { return KSCrashMonitorFlagNone; }

static void setEnabled(bool isEnabled)
{
    const char *forceEnv = getenv("KSCRASH_FORCE_ENABLE_WATCHDOG");
    bool forceEnable = forceEnv && (strcmp(forceEnv, "1") == 0 || strcmp(forceEnv, "YES") == 0);

    if (!forceEnable && ksdebug_isBeingTraced()) {
        KSLOG_DEBUG("Cannot run watchdog monitor while attached to a debugger.");
        return;
    }

    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        return;
    }

    if (isEnabled) {
        KSLOG_DEBUG("Creating watchdog.");
        g_watchdog = watchdog_create(CFRunLoopGetMain(), 0.249);
    } else {
        KSLOG_DEBUG("Stopping watchdog.");
        KSHangMonitor *old = g_watchdog;
        g_watchdog = NULL;
        watchdog_destroy(old);
    }
}

static bool isEnabled(void) { return g_isEnabled; }

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks) { g_callbacks = *callbacks; }

const char *kscm_stringFromRole(int /*task_role_t*/ role)
{
    switch (role) {
        case TASK_RENICED:
            return "RENICED";
        case TASK_UNSPECIFIED:
            return "UNSPECIFIED";
        case TASK_FOREGROUND_APPLICATION:
            return "FOREGROUND_APPLICATION";
        case TASK_BACKGROUND_APPLICATION:
            return "BACKGROUND_APPLICATION";
        case TASK_CONTROL_APPLICATION:
            return "CONTROL_APPLICATION";
        case TASK_GRAPHICS_SERVER:
            return "GRAPHICS_SERVER";
        case TASK_THROTTLE_APPLICATION:
            return "THROTTLE_APPLICATION";
        case TASK_NONUI_APPLICATION:
            return "NONUI_APPLICATION";
        case TASK_DEFAULT_APPLICATION:
            return "DEFAULT_APPLICATION";
#if defined(TASK_DARWINBG_APPLICATION)
        case TASK_DARWINBG_APPLICATION:
            return "DARWINBG_APPLICATION";
#endif
#if defined(TASK_USER_INIT_APPLICATION)
        case TASK_USER_INIT_APPLICATION:
            return "USER_INIT_APPLICATION";
#endif
        default:
            return "UNKNOWN";
    }
}

/** Implemented in KSCrashMonitor_WatchdogStitch.m */
extern char *kscm_watchdog_stitchReport(const char *report, int64_t reportID, const char *sidecarPath);

KSCrashMonitorAPI *kscm_watchdog_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.monitorFlags = monitorFlags;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
        api.stitchReport = kscm_watchdog_stitchReport;
    }
    return &api;
}

__attribute__((constructor)) static void kscm_watchdog_constructor(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (pthread_main_np() != 0) {
            g_mainQueueThread = ksthread_self();
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                g_mainQueueThread = ksthread_self();
            });
        }
    });
}
