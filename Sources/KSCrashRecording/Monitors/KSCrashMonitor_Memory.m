//
//  KSCrashMonitor_Memory.h
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

#import "KSCrash.h"
#import "KSCrashAppMemory.h"
#import "KSCrashAppMemoryTracker.h"
#import "KSCrashAppStateTracker.h"
#import "KSCrashC.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitorContextHelper.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportStoreC.h"
#import "KSDate.h"
#import "KSFileUtils.h"
#import "KSID.h"
#import "KSStackCursor.h"
#import "KSStackCursor_MachineContext.h"
#import "KSStackCursor_SelfThread.h"
#import "KSSystemCapabilities.h"

#import <Foundation/Foundation.h>
#import <os/lock.h>

#import "KSLogger.h"

#if KSCRASH_HAS_UIAPPLICATION
#import <UIKit/UIKit.h>
#endif

const int32_t KSCrash_Memory_Magic = 'kscm';

const uint8_t KSCrash_Memory_Version_1 = 1;
const uint8_t KSCrash_Memory_CurrentVersion = KSCrash_Memory_Version_1;

const uint8_t KSCrash_Memory_NonFatalReportLevelNone = KSCrashAppMemoryStateTerminal + 1;

// ============================================================================
#pragma mark - Forward declarations -
// ============================================================================

static KSCrash_Memory _ks_memory_copy(void);
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

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static volatile bool g_isEnabled = 0;
static volatile bool g_hasPostEnable = 0;

// What we're reporting
static uint8_t g_MinimumNonFatalReportingLevel = KSCrash_Memory_NonFatalReportLevelNone;
static bool g_FatalReportsEnabled = true;

// Install path for the crash system
static NSURL *g_dataURL = nil;
static NSURL *g_memoryURL = nil;

// The memory tracker
@class _KSCrashMonitor_MemoryTracker;
static _KSCrashMonitor_MemoryTracker *g_memoryTracker = nil;

// Observer token for app state transitions.
static id<KSCrashAppStateTrackerObserving> g_appStateObserver = nil;

// file mapped memory.
// Never touch `g_memory` directly,
// always call `_ks_memory_update`.
// ex:
// _ks_memory_update(^(KSCrash_Memory *mem){
//      mem->x = ...
//  });
static os_unfair_lock g_memoryLock = OS_UNFAIR_LOCK_INIT;
static KSCrash_Memory *g_memory = NULL;

static KSCrash_Memory _ks_memory_copy(void)
{
    KSCrash_Memory copy = { 0 };
    {
        os_unfair_lock_lock(&g_memoryLock);
        if (g_memory) {
            copy = *g_memory;
        }
        os_unfair_lock_unlock(&g_memoryLock);
    }
    return copy;
}

static void _ks_memory_update(void (^block)(KSCrash_Memory *mem))
{
    if (!block) {
        return;
    }
    os_unfair_lock_lock(&g_memoryLock);
    if (g_memory) {
        block(g_memory);
    }
    os_unfair_lock_unlock(&g_memoryLock);
}

static void _ks_memory_set(KSCrash_Memory *mem)
{
    os_unfair_lock_lock(&g_memoryLock);
    g_memory = mem;
    os_unfair_lock_unlock(&g_memoryLock);
}

static void _ks_memory_update_from_app_memory(KSCrashAppMemory *const memory)
{
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

@interface _KSCrashMonitor_MemoryTracker : NSObject <KSCrashAppMemoryTrackerDelegate> {
    KSCrashAppMemoryTracker *_tracker;
}
@end

@implementation _KSCrashMonitor_MemoryTracker

- (instancetype)init
{
    if (self = [super init]) {
        _tracker = [[KSCrashAppMemoryTracker alloc] init];
        _tracker.delegate = self;
        [_tracker start];
    }
    return self;
}

- (void)dealloc
{
    [_tracker stop];
}

- (KSCrashAppMemory *)memory
{
    return _tracker.currentAppMemory;
}

- (void)_updateMappedMemoryFrom:(KSCrashAppMemory *)memory
{
    _ks_memory_update_from_app_memory(memory);
}

- (void)appMemoryTracker:(KSCrashAppMemoryTracker *)tracker
                  memory:(KSCrashAppMemory *)memory
                 changed:(KSCrashAppMemoryTrackerChangeType)changes
{
    if (changes & KSCrashAppMemoryTrackerChangeTypeFootprint) {
        [self _updateMappedMemoryFrom:memory];
    }

    if ((changes & KSCrashAppMemoryTrackerChangeTypeLevel) && memory.level >= g_MinimumNonFatalReportingLevel) {
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

    if ((changes & KSCrashAppMemoryTrackerChangeTypePressure) && memory.pressure >= g_MinimumNonFatalReportingLevel) {
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
    if (isEnabled != g_isEnabled) {
        g_isEnabled = isEnabled;
        if (isEnabled) {
            g_memoryTracker = [[_KSCrashMonitor_MemoryTracker alloc] init];

            ksmemory_map(g_memoryURL.path.UTF8String);

            g_appStateObserver = [KSCrashAppStateTracker.sharedInstance
                addObserverWithBlock:^(KSCrashAppTransitionState transitionState) {
                    _ks_memory_update(^(KSCrash_Memory *mem) {
                        mem->state = transitionState;
                    });
                }];

        } else {
            g_memoryTracker = nil;
            [KSCrashAppStateTracker.sharedInstance removeObserver:g_appStateObserver];
            g_appStateObserver = nil;
        }
    }
}

static bool isEnabled(void) { return g_isEnabled; }

static NSURL *kscm_memory_oom_breadcrumb_URL(void)
{
    return [g_dataURL URLByAppendingPathComponent:@"oom_breadcrumb_report.json"];
}

static void addContextualInfoToEvent(KSCrash_MonitorContext *eventContext)
{
    bool asyncSafeOnly = eventContext->requiresAsyncSafety;

    // we'll use this when reading this back on the next run
    // to know if an OOM is even possible.
    if (asyncSafeOnly) {
        // since we're in a singal or something that can only
        // use async safe functions, we can't lock.
        // It's "ok" though, since no other threads should be running.
        g_memory->fatal = eventContext->handlingCrash;
    } else {
        _ks_memory_update(^(KSCrash_Memory *mem) {
            mem->fatal = eventContext->handlingCrash;
        });
    }

    if (g_isEnabled) {
        // same as above re: not locking when _asyncSafeOnly_ is set.
        KSCrash_Memory memCopy = asyncSafeOnly ? *g_memory : _ks_memory_copy();
        eventContext->AppMemory.footprint = memCopy.footprint;
        eventContext->AppMemory.pressure = KSCrashAppMemoryStateToString((KSCrashAppMemoryState)memCopy.pressure);
        eventContext->AppMemory.remaining = memCopy.remaining;
        eventContext->AppMemory.limit = memCopy.limit;
        eventContext->AppMemory.level = KSCrashAppMemoryStateToString((KSCrashAppMemoryState)memCopy.level);
        eventContext->AppMemory.timestamp = memCopy.timestamp;
        eventContext->AppMemory.state = ksapp_transitionStateToString(memCopy.state);
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
    bool userPerceivedOOM = NO;
    if (g_FatalReportsEnabled && ksmemory_previous_session_was_terminated_due_to_memory(&userPerceivedOOM)) {
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
    if (g_hasPostEnable) {
        return;
    }
    g_hasPostEnable = 1;

    // Usually we'd do something like this `setEnabled`,
    // but in this case not all monitors are ready in `seEnabled`
    // so we simply do it after everything is enabled.

    kscm_memory_check_for_oom_in_previous_session();

    if (g_isEnabled) {
        ksmemory_write_possible_oom();
    }
}

KSCrashMonitorAPI *kscm_memory_getAPI(void)
{
    static KSCrashMonitorAPI api = {
        .monitorId = monitorId,
        .setEnabled = setEnabled,
        .isEnabled = isEnabled,
        .addContextualInfoToEvent = addContextualInfoToEvent,
        .notifyPostSystemEnable = notifyPostSystemEnable,
    };
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
    const uint64_t kUS_in_day = 8.64e+10;
    const uint64_t kUS_in_week = kUS_in_day * 7;
    uint64_t now = ksdate_microseconds();
    if (memory.timestamp <= 0 || memory.timestamp == INT64_MAX || memory.timestamp < now - kUS_in_week) {
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

/**
 Mapping memory to a file on disk. This allows us to simply treat the location
 in memory as a structure and the kernel will ensure it is on disk. This is also
 crash resistant.
 */
static void ksmemory_map(const char *path)
{
    void *ptr = ksfu_mmap(path, sizeof(KSCrash_Memory));
    if (!ptr) {
        return;
    }

    _ks_memory_set(ptr);
    _ks_memory_update_from_app_memory(g_memoryTracker.memory);
}

/**
 What we're doing here is writing a file out that can be reused
 on restart if the data shows us there was a memory issue.

 If an OOM did happen, we'll modify this file
 (see `kscm_memory_check_for_oom_in_previous_session`),
 then write it back out using the normal writing procedure to write reports. This
 leads to the system seeing the report as if it had always been there and will
 then report an OOM.
 */
static void ksmemory_write_possible_oom(void)
{
    NSURL *reportURL = kscm_memory_oom_breadcrumb_URL();
    const char *reportPath = reportURL.path.UTF8String;

    KSMC_NEW_CONTEXT(machineContext);
    ksmc_getContextForThread(ksthread_self(), machineContext, false);
    KSStackCursor stackCursor;
    kssc_initWithMachineContext(&stackCursor, KSSC_MAX_STACK_DEPTH, machineContext);

    char eventID[37] = { 0 };
    ksid_generate(eventID);

    KSCrash_MonitorContext context;
    memset(&context, 0, sizeof(context));
    ksmc_fillMonitorContext(&context, kscm_memory_getAPI());
    context.eventID = eventID;
    context.registersAreValid = false;
    context.offendingMachineContext = machineContext;
    context.currentSnapshotUserReported = true;

    // we don't need all the images, we have no stack
    context.omitBinaryImages = true;

    // _reportPath_ only valid within this scope
    context.reportPath = reportPath;

    kscm_handleException(&context);
}

void ksmemory_initialize(const char *dataPath)
{
    g_hasPostEnable = 0;
    g_dataURL = [NSURL fileURLWithPath:@(dataPath)];
    g_memoryURL = [g_dataURL URLByAppendingPathComponent:@"memory.bin"];

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
        return NO;
    }

    // We might care if the user might have seen the OOM
    if (userPerceptible) {
        *userPerceptible = ksapp_transitionStateIsUserPerceptible(g_previousSessionMemory.state);
    }

    // level or pressure is critical++
    return g_previousSessionMemory.level >= KSCrashAppMemoryStateCritical ||
           g_previousSessionMemory.pressure >= KSCrashAppMemoryStateCritical;
}

void ksmemory_set_nonfatal_report_level(uint8_t level) { g_MinimumNonFatalReportingLevel = level; }

uint8_t ksmemory_get_nonfatal_report_level(void) { return g_MinimumNonFatalReportingLevel; }

void ksmemory_set_fatal_reports_enabled(bool enabled) { g_FatalReportsEnabled = enabled; }

bool ksmemory_get_fatal_reports_enabled(void) { return g_FatalReportsEnabled; }

void ksmemory_notifyUnhandledFatalSignal(void)
{
    // this is only called from a signal so we cannot lock.
    if (g_memory) {
        g_memory->fatal = true;
    }
}
