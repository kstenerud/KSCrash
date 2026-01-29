//
//  KSCrashMonitor_Memory.m
//
//  Created by Alexander Cohen on 2024-05-20.
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
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
#import "KSCrashMonitor_Memory.h"
#include "KSCrashExceptionHandlingRequirements.h"

#import "KSCrash.h"
#import "KSCrashAppMemory.h"
#import "KSCrashAppMemoryTracker.h"
#import "KSCrashAppStateTracker.h"
#import "KSCrashC.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitorHelper.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportStoreC.h"
#import "KSDate.h"
#import "KSFileUtils.h"
#import "KSID.h"
#import "KSSpinLock.h"
#import "KSStackCursor.h"
#import "KSStackCursor_MachineContext.h"
#import "KSStackCursor_SelfThread.h"
#import "KSSystemCapabilities.h"
#import "Unwind/KSStackCursor_Unwind.h"

#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import <time.h>

#import "KSLogger.h"

#if KSCRASH_HAS_UIAPPLICATION
#import <UIKit/UIKit.h>
#endif

static const int32_t KSCrash_Memory_Magic = 'kscm';

const uint8_t KSCrash_Memory_Version_1_0 = 1;
const uint8_t KSCrash_Memory_CurrentVersion = KSCrash_Memory_Version_1_0;

const uint8_t KSCrash_Memory_NonFatalReportLevelNone = KSCrashAppMemoryStateTerminal + 1;

// ============================================================================
#pragma mark - Forward declarations -
// ============================================================================

static void _ks_memory_update(void (^block)(KSCrash_Memory *mem));
static void _ks_memory_update_from_app_memory(KSCrashAppMemory *const memory);
static void _ks_memory_set(KSCrash_Memory *mem);
static void ksmemory_write_possible_oom(void);
static void setEnabled(bool isEnabled);
static bool isEnabled(void);
static NSURL *kscm_memory_oom_breadcrumb_URL(void);
static void addContextualInfoToEvent(KSCrash_MonitorContext *eventContext);
static NSDictionary<NSString *, id> *kscm_memory_serialize(KSCrash_Memory *const memory);
static void kscm_memory_check_for_oom_in_previous_session(void);
static void notifyPostSystemEnable(void);
static void ksmemory_read(const char *path);
static void ksmemory_map(const char *path);
static void ksmemory_unmap(void);
static void ksmemory_applyNoFileProtection(NSString *path);

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static atomic_bool g_isEnabled = false;
static atomic_bool g_hasPostEnable = false;

// What we're reporting
static _Atomic(uint8_t) g_MinimumNonFatalReportingLevel = KSCrash_Memory_NonFatalReportLevelNone;
static _Atomic(bool) g_FatalReportsEnabled = true;
// Rate-limiting for proactive OOM breadcrumb writes.
// Avoids excessive disk I/O when memory state changes rapidly.
static _Atomic(uint64_t) g_lastReportWrittenTimestamp = 0;
#define KS_CRASH_MIN_DURATION_BETWEEN_REPORT_WRITES (5ULL * 1000000000ULL)  // 5 seconds in nanoseconds

// Install path for the crash system
static NSURL *g_dataURL = nil;
static NSURL *g_memoryURL = nil;

// The memory tracker
@class KSCrashMonitor_MemoryTracker;
static KSCrashMonitor_MemoryTracker *g_memoryTracker = nil;

// Observer token for app state transitions.
static id<KSCrashAppStateTrackerObserving> g_appStateObserver = nil;

static KSCrash_ExceptionHandlerCallbacks g_callbacks;

// file mapped memory.
// Never touch `g_memory` directly,
// always call `_ks_memory_update`.
// ex:
// _ks_memory_update(^(KSCrash_Memory *mem){
//      mem->x = ...
//  });
static KSSpinLock g_memoryLock = KSSPINLOCK_INIT;
static KSCrash_Memory *g_memory = NULL;

/** Updates the memory-mapped structure under the spinlock.
 *
 *  When @c needsAsyncSignalSafety is YES (crash handler context), uses a bounded
 *  lock attempt so we don't spin forever if the lock holder was suspended mid-crash.
 *  Returns false if the lock could not be acquired or g_memory is NULL.
 */
static bool _ks_memory_update_with_bounded(BOOL needsAsyncSignalSafety, void (^block)(KSCrash_Memory *mem))
{
    if (!block) {
        return false;
    }
    bool updated = false;

    if (needsAsyncSignalSafety) {
        if (ks_spinlock_lock_bounded(&g_memoryLock)) {
            if (g_memory) {
                block(g_memory);
                updated = true;
            }
            ks_spinlock_unlock(&g_memoryLock);
        }
    } else {
        ks_spinlock_lock(&g_memoryLock);
        if (g_memory) {
            block(g_memory);
            updated = true;
        }
        ks_spinlock_unlock(&g_memoryLock);
    }
    return updated;
}

static void _ks_memory_update(void (^block)(KSCrash_Memory *mem)) { _ks_memory_update_with_bounded(NO, block); }

/** Replaces the global memory pointer and unmaps the old one.
 *  Not async-signal-safe (calls ksfu_munmap).
 */
static void _ks_memory_set(KSCrash_Memory *mem)
{
    void *old = NULL;
    ks_spinlock_lock(&g_memoryLock);
    old = g_memory;
    g_memory = mem;
    ks_spinlock_unlock(&g_memoryLock);

    if (old) {
        ksfu_munmap(old, sizeof(KSCrash_Memory));
    }
}

/** Copies current app memory state into the memory-mapped structure.
 *  Not async-signal-safe (uses Objective-C property access).
 */
static void _ks_memory_update_from_app_memory(KSCrashAppMemory *const memory)
{
    if (!memory) {
        return;
    }

    _ks_memory_update(^(KSCrash_Memory *mem) {
        *mem = (KSCrash_Memory) {
            .magic = KSCrash_Memory_Magic,
            .version = KSCrash_Memory_CurrentVersion,
            .footprint = memory.footprint,
            .remaining = memory.remaining,
            .limit = memory.limit,
            .pressure = (uint8_t)memory.pressure,
            .level = (uint8_t)memory.level,
            .timestamp = ksdate_microseconds(),
            .state = KSCrashAppStateTracker.sharedInstance.transitionState,
        };
    });
}

// last memory write from the previous session
static KSCrash_Memory g_previousSessionMemory;

// ============================================================================
#pragma mark - Tracking -
// ============================================================================

@interface KSCrashMonitor_MemoryTracker : NSObject {
    id _observer;
}
@end

@implementation KSCrashMonitor_MemoryTracker

- (instancetype)init
{
    if ((self = [super init])) {
        __weak typeof(self) weakMe = self;
        _observer = [KSCrashAppMemoryTracker.sharedInstance
            addObserverWithBlock:^(KSCrashAppMemory *_Nonnull memory, KSCrashAppMemoryTrackerChangeType changes) {
                typeof(self) me = weakMe;
                if (!me) {
                    return;
                }
                [me _memory:memory changed:changes];
            }];
    }
    return self;
}

- (void)dealloc
{
    _observer = nil;
}

- (KSCrashAppMemory *)memory
{
    return KSCrashAppMemoryTracker.sharedInstance.currentAppMemory;
}

- (void)_updateMappedMemoryFrom:(KSCrashAppMemory *)memory
{
    _ks_memory_update_from_app_memory(memory);
}

- (void)_memory:(KSCrashAppMemory *)memory changed:(KSCrashAppMemoryTrackerChangeType)changes
{
    if (changes & KSCrashAppMemoryTrackerChangeTypeFootprint || changes & KSCrashAppMemoryTrackerChangeTypePressure) {
        [self _updateMappedMemoryFrom:memory];
    }

    // Proactively write the OOM breadcrumb when memory is urgent so the
    // data is already on disk if the OS kills us. Rate-limited via atomic CAS
    // to avoid excessive writes during rapid state changes.
    // Guard on g_hasPostEnable to ensure the monitor system is fully initialized
    // (callbacks are set) before attempting to write a report.
    if (atomic_load(&g_hasPostEnable) &&
        (memory.level >= KSCrashAppMemoryStateUrgent || memory.pressure >= KSCrashAppMemoryStateUrgent)) {
        uint64_t now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
        uint64_t last = atomic_load(&g_lastReportWrittenTimestamp);
        if (now - last > KS_CRASH_MIN_DURATION_BETWEEN_REPORT_WRITES) {
            if (atomic_compare_exchange_strong(&g_lastReportWrittenTimestamp, &last, now)) {
                ksmemory_write_possible_oom();
            }
        }
    }

    if ((changes & KSCrashAppMemoryTrackerChangeTypeLevel) && memory.level >= ksmemory_get_nonfatal_report_level()) {
        NSString *level = @(KSCrashAppMemoryStateToString(memory.level)).uppercaseString;
        NSString *reason = [NSString stringWithFormat:@"Memory Level Is %@", level];

        [[KSCrash sharedInstance] reportUserException:@"Memory Level"
                                               reason:reason
                                             language:@""
                                           lineOfCode:@"0"
                                           stackTrace:@[ @"__MEMORY_LEVEL__NON_FATAL__" ]
                                        logAllThreads:NO
                                     terminateProgram:NO];
    }

    if ((changes & KSCrashAppMemoryTrackerChangeTypePressure) &&
        memory.pressure >= ksmemory_get_nonfatal_report_level()) {
        NSString *pressure = @(KSCrashAppMemoryStateToString(memory.pressure)).uppercaseString;
        NSString *reason = [NSString stringWithFormat:@"Memory Pressure Is %@", pressure];

        [[KSCrash sharedInstance] reportUserException:@"Memory Pressure"
                                               reason:reason
                                             language:@""
                                           lineOfCode:@"0"
                                           stackTrace:@[ @"__MEMORY_PRESSURE__NON_FATAL__" ]
                                        logAllThreads:NO
                                     terminateProgram:NO];
    }
}

@end

// ============================================================================
#pragma mark - API -
// ============================================================================

static const char *monitorId(void) { return "MemoryTermination"; }

static void setEnabled(bool isEnabled)
{
    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        // We were already in the expected state
        return;
    }

    if (isEnabled) {
        g_memoryTracker = [[KSCrashMonitor_MemoryTracker alloc] init];

        ksmemory_map(g_memoryURL.path.UTF8String);

        g_appStateObserver =
            [KSCrashAppStateTracker.sharedInstance addObserverWithBlock:^(KSCrashAppTransitionState transitionState) {
                _ks_memory_update(^(KSCrash_Memory *mem) {
                    mem->state = transitionState;
                });
            }];

    } else {
        [KSCrashAppStateTracker.sharedInstance removeObserver:g_appStateObserver];
        g_appStateObserver = nil;
        g_memoryTracker = nil;
        ksmemory_unmap();
    }
}

static bool isEnabled(void) { return atomic_load(&g_isEnabled); }

static NSURL *kscm_memory_oom_breadcrumb_URL(void)
{
    return [g_dataURL URLByAppendingPathComponent:@"oom_breadcrumb_report.json"];
}

static void addContextualInfoToEvent(KSCrash_MonitorContext *eventContext)
{
    // Mark whether this crash is fatal so the next launch can determine
    // if an OOM is still possible, and attach memory info to the event.
    bool asyncSafetyNeeded = kscexc_requiresAsyncSafety(eventContext->requirements);
    bool updated = _ks_memory_update_with_bounded(asyncSafetyNeeded, ^(KSCrash_Memory *mem) {
        mem->fatal = eventContext->requirements.isFatal;

        if (atomic_load(&g_isEnabled)) {
            eventContext->AppMemory.footprint = mem->footprint;
            eventContext->AppMemory.pressure = KSCrashAppMemoryStateToString((KSCrashAppMemoryState)mem->pressure);
            eventContext->AppMemory.remaining = mem->remaining;
            eventContext->AppMemory.limit = mem->limit;
            eventContext->AppMemory.level = KSCrashAppMemoryStateToString((KSCrashAppMemoryState)mem->level);
            eventContext->AppMemory.timestamp = mem->timestamp;
            eventContext->AppMemory.state = ksapp_transitionStateToString(mem->state);
        }
    });

    // Bounded lock failed — threads are suspended so direct access is safe.
    // We still need to record fatality for next-launch OOM detection.
    if (!updated && g_memory && eventContext->requirements.asyncSafetyBecauseThreadsSuspended) {
        g_memory->fatal = eventContext->requirements.isFatal;
    }
}

static NSDictionary<NSString *, id> *kscm_memory_serialize(KSCrash_Memory *const memory)
{
    return @{
        KSCrashField_MemoryFootprint : @(memory->footprint),
        KSCrashField_MemoryRemaining : @(memory->remaining),
        KSCrashField_MemoryLimit : @(memory->limit),
        KSCrashField_MemoryPressure : @(KSCrashAppMemoryStateToString((KSCrashAppMemoryState)memory->pressure)),
        KSCrashField_MemoryLevel : @(KSCrashAppMemoryStateToString((KSCrashAppMemoryState)memory->level)),
        KSCrashField_Timestamp : @(memory->timestamp),
        KSCrashField_AppTransitionState : @(ksapp_transitionStateToString(memory->state)),
    };
}

/**
 Check to see if the previous run was an OOM
 if it was, we load up the report created in the previous
 session and modify it, save it out to the reports location,
 and let the system run its course.
 */
static void kscm_memory_check_for_oom_in_previous_session(void)
{
    // An OOM should be the last thng we check for. For example,
    // If memory is critical but before being jetisoned we encounter
    // a programming error and receiving a Mach event or signal that
    // indicates a crash, we should process that on startup and ignore
    // and indication of an OOM.
    bool userPerceivedOOM = false;
    if (ksmemory_get_fatal_reports_enabled() &&
        ksmemory_previous_session_was_terminated_due_to_memory(&userPerceivedOOM)) {
        // We only report an OOM that the user might have seen.
        // Ignore this check if we want to report all OOM, foreground and background.
        if (userPerceivedOOM) {
            NSURL *url = kscm_memory_oom_breadcrumb_URL();
            const char *reportContents = kscrs_readReportAtPath(url.path.UTF8String);
            if (reportContents) {
                NSData *data = [NSData dataWithBytes:reportContents length:strlen(reportContents)];
                NSMutableDictionary *json =
                    [[NSJSONSerialization JSONObjectWithData:data
                                                     options:NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves
                                                       error:nil] mutableCopy];

                if (json) {
                    json[KSCrashField_System][KSCrashField_AppMemory] = kscm_memory_serialize(&g_previousSessionMemory);
                    json[KSCrashField_Report][KSCrashField_Timestamp] = @(g_previousSessionMemory.timestamp);
                    json[KSCrashField_Crash][KSCrashField_Error][KSCrashExcType_MemoryTermination] =
                        kscm_memory_serialize(&g_previousSessionMemory);
                    json[KSCrashField_Crash][KSCrashField_Error][KSCrashExcType_Mach] = nil;
                    json[KSCrashField_Crash][KSCrashField_Error][KSCrashExcType_Signal] = @{
                        KSCrashField_Signal : @(SIGKILL),
                        KSCrashField_Name : @"SIGKILL",
                    };

                    data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
                    kscrash_addUserReport((const char *)data.bytes, (int)data.length);
                }
                free((void *)reportContents);
            }
        }
    }

    // remove the old breadcrumb oom file
    unlink(kscm_memory_oom_breadcrumb_URL().path.UTF8String);
}

/**
 This is called after all monitors are enabled.
 */
static void notifyPostSystemEnable(void)
{
    bool expectPostEnable = false;
    if (!atomic_compare_exchange_strong(&g_hasPostEnable, &expectPostEnable, true)) {
        // We were already in the expected state
        return;
    }

    // Usually we'd do something like this `setEnabled`,
    // but in this case not all monitors are ready in `seEnabled`
    // so we simply do it after everything is enabled.

    kscm_memory_check_for_oom_in_previous_session();
}

static void init(KSCrash_ExceptionHandlerCallbacks *callbacks) { g_callbacks = *callbacks; }

KSCrashMonitorAPI *kscm_memory_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = init;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
        api.addContextualInfoToEvent = addContextualInfoToEvent;
        api.notifyPostSystemEnable = notifyPostSystemEnable;
    }
    return &api;
}

/**
 Read the previous sessions memory data,
 and unlinks the file to remove any trace of it.
 */
static void ksmemory_read(const char *path)
{
    int fd = open(path, O_RDONLY);
    if (fd == -1) {
        unlink(path);
        return;
    }

    size_t size = sizeof(KSCrash_Memory);
    KSCrash_Memory memory = {};

    // This will fail is we don't receive exactly _size_.
    // In the future, we need to read and allow getting back something
    // that is not exactly _size_, then check the version to see
    // what we can or cannot use in the structure.
    if (!ksfu_readBytesFromFD(fd, (char *)&memory, (int)size)) {
        close(fd);
        unlink(path);
        return;
    }

    // get rid of the file, we don't want it anymore.
    close(fd);
    unlink(path);

    // validate some of the data before doing anything with it.

    // check magic
    if (memory.magic != KSCrash_Memory_Magic) {
        return;
    }

    // check version
    if (memory.version == 0 || memory.version > KSCrash_Memory_CurrentVersion) {
        return;
    }

    // ---
    // START KSCrash_Memory_Version_1_0
    // ---

    // check the timestamp, let's say it's valid for the last week
    // do we really want crash reports older than a week anyway??
    const uint64_t kUS_in_day = 86400000000ULL;  // 24 * 60 * 60 * 1000000
    const uint64_t kUS_in_week = kUS_in_day * 7;
    uint64_t now = ksdate_microseconds();
    if (memory.timestamp == 0 || memory.timestamp > now || memory.timestamp < now - kUS_in_week) {
        return;
    }

    // check pressure and level are in ranges
    if (memory.level > KSCrashAppMemoryStateTerminal) {
        return;
    }
    if (memory.pressure > KSCrashAppMemoryStateTerminal) {
        return;
    }

    // check app transition state
    if (memory.state > KSCrashAppTransitionStateExiting) {
        return;
    }

    // if we're at max, we likely overflowed or set a negative value,
    // in any case, we're counting this as a possible error and bailing.
    if (memory.footprint == UINT64_MAX) {
        return;
    }
    if (memory.remaining == UINT64_MAX) {
        return;
    }
    if (memory.limit == UINT64_MAX) {
        return;
    }

    // Footprint and remaining should always = limit
    if (memory.footprint + memory.remaining != memory.limit) {
        return;
    }

    // ---
    // END KSCrash_Memory_Version_1_0
    // ---

    g_previousSessionMemory = memory;
}

/** Maps the memory structure to a file on disk so the kernel keeps it
 *  persistently written. This makes the data crash-resistant.
 *  Not async-signal-safe.
 */
static void ksmemory_map(const char *path)
{
    void *ptr = ksfu_mmap(path, sizeof(KSCrash_Memory));
    if (!ptr) {
        return;
    }

    _ks_memory_set(ptr);

    KSCrashAppMemory *currentMemory = g_memoryTracker.memory;
    if (currentMemory) {
        _ks_memory_update_from_app_memory(currentMemory);
    }
}

/**
 Unmaps the memory-mapped file and clears the global pointer.
 */
static void ksmemory_unmap(void) { _ks_memory_set(NULL); }

/** Writes an OOM breadcrumb report to disk so it survives an OS kill.
 *
 *  On the next launch, @c kscm_memory_check_for_oom_in_previous_session reads
 *  this file back and, if the evidence points to an OOM, promotes it into a
 *  normal crash report.
 *
 *  Not async-signal-safe (uses ObjC/NSURL). Only called from the memory
 *  tracker callback on a normal thread.
 */
static void ksmemory_write_possible_oom(void)
{
    if (!g_callbacks.notify || !g_callbacks.handle) {
        return;
    }

    NSURL *reportURL = kscm_memory_oom_breadcrumb_URL();
    const char *reportPath = reportURL.path.UTF8String;
    unlink(reportPath);

    thread_t thisThread = (thread_t)ksthread_self();
    KSCrash_MonitorContext *ctx = g_callbacks.notify(
        thisThread,
        (KSCrash_ExceptionHandlingRequirements) {
            .asyncSafety = false, .isFatal = false, .shouldRecordAllThreads = false, .shouldWriteReport = true });
    if (ctx->requirements.shouldExitImmediately) {
        return;
    }

    KSMachineContext machineContext = { 0 };
    ksmc_getContextForThreadCheckingStackOverflow(thisThread, &machineContext, false, false);
    KSStackCursor stackCursor;
    kssc_initWithUnwind(&stackCursor, KSSC_MAX_STACK_DEPTH, &machineContext);

    kscm_fillMonitorContext(ctx, kscm_memory_getAPI());
    ctx->registersAreValid = false;
    ctx->offendingMachineContext = &machineContext;
    ctx->currentSnapshotUserReported = true;

    // we don't need all the images, we have no stack
    ctx->omitBinaryImages = true;

    // _reportPath_ only valid within this scope
    ctx->reportPath = reportPath;

    g_callbacks.handle(ctx);
}

static void ksmemory_applyNoFileProtection(NSString *path)
{
    if (!path) {
        return;
    }

    NSDictionary *attrs = @ { NSFileProtectionKey : NSFileProtectionNone };
    [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:path error:nil];
}

void ksmemory_initialize(const char *dataPath)
{
    atomic_store(&g_hasPostEnable, false);
    g_dataURL = [NSURL fileURLWithPath:@(dataPath)];
    g_memoryURL = [g_dataURL URLByAppendingPathComponent:@"memory.bin"];

    // Ensure files we touch stay readable while the app is locked.
    ksmemory_applyNoFileProtection(g_dataURL.path);
    ksmemory_applyNoFileProtection(g_memoryURL.path);
    ksmemory_applyNoFileProtection(kscm_memory_oom_breadcrumb_URL().path);

    // load up the old memory data
    ksmemory_read(g_memoryURL.path.UTF8String);
}

bool ksmemory_previous_session_was_terminated_due_to_memory(bool *userPerceptible)
{
    // If we had any kind of fatal, even if the data says an OOM, it wasn't an OOM.
    // The idea is that we could have been very close to an OOM then some
    // exception/event occured that terminated/crashed the app. We don't want to report
    // that as an OOM.
    if (g_previousSessionMemory.fatal) {
        return false;
    }

    // We might care if the user might have seen the OOM
    if (userPerceptible) {
        *userPerceptible = ksapp_transitionStateIsUserPerceptible(g_previousSessionMemory.state);
    }

    // level or pressure is critical++
    return g_previousSessionMemory.level >= KSCrashAppMemoryStateCritical ||
           g_previousSessionMemory.pressure >= KSCrashAppMemoryStateCritical;
}

void ksmemory_set_nonfatal_report_level(uint8_t level) { atomic_store(&g_MinimumNonFatalReportingLevel, level); }

uint8_t ksmemory_get_nonfatal_report_level(void) { return atomic_load(&g_MinimumNonFatalReportingLevel); }

void ksmemory_set_fatal_reports_enabled(bool enabled) { atomic_store(&g_FatalReportsEnabled, enabled); }

bool ksmemory_get_fatal_reports_enabled(void) { return atomic_load(&g_FatalReportsEnabled); }
