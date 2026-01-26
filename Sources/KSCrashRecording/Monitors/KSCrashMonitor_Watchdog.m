//
//  KSCrashMonitor_Watchdog.m
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

#import "KSCrashMonitor_Watchdog.h"

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitorHelper.h"
#import "KSCrashReportFields.h"
#import "KSDebug.h"
#import "KSHang.h"
#import "KSID.h"
#import "KSJSONCodecObjC.h"
#import "KSStackCursor_MachineContext.h"
#import "KSThread.h"
#import "KSUnfairLock.h"
#import "Unwind/KSStackCursor_Unwind.h"

#import <Foundation/Foundation.h>
#import <os/lock.h>
#import <pthread.h>
#import <stdatomic.h>

#import <mach/mach.h>
#import <mach/task_policy.h>

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#import <limits.h>
#import <string.h>

@class KSHangMonitor;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static atomic_bool g_isEnabled = false;

/** The active hang monitor instance, or nil if disabled. */
static KSHangMonitor *g_watchdog = nil;

/** The main thread, captured at load time. */
static KSThread g_mainQueueThread = 0;

static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };

// ============================================================================
#pragma mark - Watchdog and utilities -
// ============================================================================

static void *watchdog_thread_main(void *arg)
{
    dispatch_block_t block = (__bridge_transfer dispatch_block_t)arg;
    block();
    return NULL;
}

/**
 * Monitors a run loop for hangs (periods where the loop is unresponsive).
 *
 * KSHangMonitor uses a high-priority watchdog thread to periodically check
 * if the monitored run loop is responsive. When the run loop is blocked
 * longer than the configured threshold, a hang is detected and reported.
 */
@interface KSHangMonitor : NSObject {
    /** The run loop being monitored (typically the main run loop). */
    CFRunLoopRef _runLoop;
    /** Time in seconds before a blocked run loop is considered a hang. */
    NSTimeInterval _threshold;
    /** Observes run loop activity to detect when it goes idle or wakes. */
    CFRunLoopObserverRef _observer;
    /** Run loop for the watchdog thread. */
    CFRunLoopRef _watchdogRunLoop;
    /** Timer that fires periodically to check hang duration. */
    CFRunLoopTimerRef _watchdogTimer;
    /** Semaphore signaled when the watchdog thread exits. */
    dispatch_semaphore_t _threadExitSemaphore;

    /** Whether to report recovered hangs (non-fatal). */
    BOOL _reportsHangs;
    /** Protects access to _hang and _observers. */
    KSUnfairLock *_lock;
    /** Current hang being tracked, or nil if no hang in progress. */
    KSHang *_hang;
    /** Weak references to registered observer blocks. */
    NSPointerArray *_observers;
}

@end

@implementation KSHangMonitor

// Returns monotonic time in nanoseconds (pauses when device sleeps).
static uint64_t MonotonicUptime(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

// Loads and decodes a JSON crash report from disk.
static NSMutableDictionary<NSString *, id> *DecodeReport(NSString *path)
{
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    return data ? [[KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil] mutableCopy] : nil;
}

// Returns the current task role (foreground, background, etc).
static int TaskRole(void)
{
#if TARGET_OS_TV || TARGET_OS_WATCH
    // task_policy_get is not available on tvOS or watchOS
    return TASK_UNSPECIFIED;
#else
    task_category_policy_data_t policy;
    mach_msg_type_number_t count = TASK_CATEGORY_POLICY_COUNT;
    boolean_t getDefault = NO;

    kern_return_t kr =
        task_policy_get(mach_task_self(), TASK_CATEGORY_POLICY, (task_policy_t)&policy, &count, &getDefault);

    return kr == KERN_SUCCESS ? policy.role : TASK_UNSPECIFIED;
#endif
}

- (instancetype)initWithRunLoop:(CFRunLoopRef)runLoop threshold:(NSTimeInterval)threshold
{
    if ((self = [super init])) {
        // For now, this isn't configurable, but we may allow it in the future.
        _reportsHangs = NO;

        _lock = [[KSUnfairLock alloc] init];
        _runLoop = runLoop;
        _threshold = threshold;
        _observers = [NSPointerArray weakObjectsPointerArray];
        _threadExitSemaphore = dispatch_semaphore_create(0);
        [self scheduleThread];
        [self scheduleObserver];
    }
    return self;
}

- (void)dealloc
{
    if (_observer) {
        CFRunLoopObserverInvalidate(_observer);
        CFRelease(_observer);
    }

    if (_watchdogTimer) {
        CFRunLoopTimerInvalidate(_watchdogTimer);
        CFRelease(_watchdogTimer);
    }

    // Atomically read and clear _watchdogRunLoop to prevent race with scheduleThread
    __block CFRunLoopRef runLoop = NULL;
    [_lock withLock:^{
        runLoop = self->_watchdogRunLoop;
        self->_watchdogRunLoop = NULL;
    }];

    if (runLoop) {
        // This will stop the runloop and effectively
        // exit the watchdog thread.
        CFRunLoopStop(runLoop);
    }

    // Wait for the thread to exit
    if (_threadExitSemaphore) {
        dispatch_semaphore_wait(_threadExitSemaphore, DISPATCH_TIME_FOREVER);
    }
}

// Adds a hang observer. Returns a token that must be retained to keep the observer active.
- (id)addObserver:(KSHangObserverBlock)observer
{
    id copy = [observer copy];
    [_lock withLock:^{
        [self->_observers addPointer:(__bridge void *_Nullable)(copy)];
    }];
    return copy;
}

// Notifies all registered observers of a hang state change.
- (void)_sendObserversForType:(KSHangChangeType)type timeStamp:(uint64_t)start now:(uint64_t)now
{
    __block NSArray *observers = nil;
    [_lock withLock:^{
        [self->_observers compact];
        observers = self->_observers.allObjects;
    }];
    for (KSHangObserverBlock block in observers) {
        if (block) {
            block(type, start, now);
        }
    }
}

- (void)_schedulePings
{
    __weak typeof(self) weakSelf = self;
    uint64_t startTime = MonotonicUptime();
    _watchdogTimer = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent(), _threshold, 0, 0,
                                                     ^(__unused CFRunLoopTimerRef timer) {
                                                         [weakSelf _handlePingWithStartTime:startTime];
                                                     });
    CFRunLoopAddTimer(_watchdogRunLoop, _watchdogTimer, kCFRunLoopCommonModes);
}

- (void)scheduleThread
{
    assert(CFRunLoopGetCurrent() == _runLoop);

    dispatch_semaphore_t setupSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_t exitSemaphore = _threadExitSemaphore;

    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = ^{
        pthread_setname_np("com.kscrash.hang.watchdog.thread");

        // We want a block where self is strongly retained
        // to make sure we can't go out of scope and get deallocated
        {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();

                // Synchronize access to _watchdogRunLoop to prevent race with dealloc
                [strongSelf->_lock withLock:^{
                    strongSelf->_watchdogRunLoop = currentRunLoop;
                }];

                // Any run loop requires a port of some sort in order to run.
                CFRunLoopSourceContext cntxt = { .version = 0, .info = NULL };
                CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &cntxt);
                CFRunLoopAddSource(currentRunLoop, source, kCFRunLoopCommonModes);
                CFRelease(source);

                // Signal that setup is complete, but only once the run loop has started running.
                CFRunLoopPerformBlock(currentRunLoop, kCFRunLoopCommonModes, ^{
                    dispatch_semaphore_signal(setupSemaphore);
                });
            }
        }

        // Now that self is weak again, we can be deallocated
        // which will stop the runloop, exit the thread and cleanup.

        // Run the loop. On dealloc, we'll stop this to exit the thread.
        CFRunLoopRun();

        // Signal that the thread is exiting so dealloc can complete
        dispatch_semaphore_signal(exitSemaphore);
    };

    // Set up thread attributes with maximum priority and detached state.
    // We use PTHREAD_CREATE_DETACHED instead of pthread_join because TSan
    // reports thread leaks with joinable threads in this pattern. The thread
    // signals _threadExitSemaphore before exiting, and dealloc waits on it.
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    // Copy the block to the heap and transfer ownership to pthread
    pthread_t thread;
    pthread_create(&thread, &attr, watchdog_thread_main, (__bridge_retained void *)block);
    pthread_attr_destroy(&attr);

    // Wait for thread setup to complete
    dispatch_semaphore_wait(setupSemaphore, DISPATCH_TIME_FOREVER);

    // Start out by scheduling pings to make sure we catch
    // anything that happens before any run loops are running (startup).
    [self _schedulePings];
}

- (void)scheduleObserver
{
    assert(_runLoop == CFRunLoopGetCurrent());

    __weak typeof(self) weakSelf = self;
    _observer =
        CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting, true, 0,
                                           ^(__unused CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
                                               [weakSelf _handleActivity:activity];
                                           });
    CFRunLoopAddObserver(_runLoop, _observer, kCFRunLoopCommonModes);
}

- (void)_handlePingWithStartTime:(uint64_t)enterTime
{
    // This method should only be called from the watchdog thread

    const uint64_t thresholdInNs = (uint64_t)(_threshold * 1000000000);
    uint64_t now = MonotonicUptime();
    uint64_t hangTime = now - enterTime;

    // No hang detected, bail early.
    if (hangTime < thresholdInNs) {
        return;
    }

    task_role_t currentRole = TaskRole();

    __block BOOL shouldStartNewHang = NO;
    __block BOOL shouldUpdateHang = NO;

    [_lock withLock:^{
        if (self->_hang == nil) {
            // Atomically claim the hang slot before doing heavy work.
            // This ensures _handleActivity will see the hang even if
            // the report population is still in progress.
            self->_hang = [[KSHang alloc] initWithTimestamp:enterTime role:currentRole];
            self->_hang.endTimestamp = now;
            self->_hang.endRole = currentRole;
            shouldStartNewHang = YES;
        } else {
            // Update existing hang timestamps
            self->_hang.endTimestamp = now;
            self->_hang.endRole = currentRole;
            shouldUpdateHang = YES;
        }
    }];

    // Heavy work outside the lock
    if (shouldStartNewHang) {
        [self _populateReportForCurrentHang];
    } else if (shouldUpdateHang) {
        [self _writeUpdatedReport];
    }
}

- (void)_handleActivity:(CFRunLoopActivity)activity
{
    if (_watchdogTimer) {
        CFRunLoopTimerInvalidate(_watchdogTimer);
        CFRelease(_watchdogTimer);
        _watchdogTimer = nil;
    }

    if (activity == kCFRunLoopBeforeWaiting) {
        __block KSHang *hang = nil;
        [_lock withLock:^{
            // Move ownership - no need to copy
            hang = self->_hang;
            self->_hang = nil;
        }];

        if (hang == nil) {
            return;
        }

        // Hang has ended - finalize it
        hang.endTimestamp = MonotonicUptime();
        hang.endRole = TaskRole();
        [self _endOwnedHang:hang];

    }

    // Run loop woke up - start monitoring again
    else if (activity == kCFRunLoopAfterWaiting) {
        [self _schedulePings];
    }
}

- (void)_writeUpdatedReport
{
    __block NSDictionary<NSString *, id> *decodedReport = nil;
    __block NSString *path = nil;
    __block uint64_t timestampStart = 0;
    __block uint64_t timestampEnd = 0;

    [_lock withLock:^{
        if (self->_hang == nil || self->_hang.decodedReport == nil) {
            // Hang was ended or not yet populated
            return;
        }

        timestampStart = self->_hang.timestamp;
        timestampEnd = self->_hang.endTimestamp;

        self->_hang
            .decodedReport[KSCrashField_Crash][KSCrashField_Error][KSCrashField_Hang][KSCrashField_HangEndNanoseconds] =
            @(self->_hang.endTimestamp);
        self->_hang.decodedReport[KSCrashField_Crash][KSCrashField_Error][KSCrashField_Hang][KSCrashField_HangEndRole] =
            @(kscm_stringFromRole(self->_hang.endRole));
        decodedReport = [self->_hang.decodedReport copy];
        path = [self->_hang.path copy];
    }];

    if (decodedReport && path) {
        // Write report back to disk (outside lock)
        NSError *error = nil;
        NSData *newData = [KSJSONCodec encode:decodedReport options:KSJSONEncodeOptionNone error:&error];
        if (newData) {
            if (![newData writeToFile:path options:0 error:&error]) {
                KSLOG_ERROR(@"[HANG] Failed to write updated report to %@: %@", path, error);
            }
        } else {
            KSLOG_ERROR(@"[HANG] Failed to encode updated report: %@", error);
        }
    } else {
        KSLOG_DEBUG(@"[HANG] Skipping update;");
    }

    [self _sendObserversForType:KSHangChangeTypeUpdated timeStamp:timestampStart now:timestampEnd];
}

- (void)_endOwnedHang:(KSHang *)hang
{
    if (hang.path && hang.decodedReport) {
        if (_reportsHangs) {
            // Hang has recovered but we report non-fatal hangs

            // We have options.
            // started in the foreground and ended in the foreground, report it.
            // started in the foreground and ended in the background, report it.
            // started in the background and ended in the background, drop it.
            // started in the background and ended in the foreground, report it.

            // Update the end data
            hang.decodedReport[KSCrashField_Crash][KSCrashField_Error][KSCrashField_Hang]
                              [KSCrashField_HangEndNanoseconds] = @(hang.endTimestamp);
            hang.decodedReport[KSCrashField_Crash][KSCrashField_Error][KSCrashField_Hang][KSCrashField_HangEndRole] =
                @(kscm_stringFromRole(hang.endRole));

            // Update the type to hang
            hang.decodedReport[KSCrashField_Crash][KSCrashField_Error][KSCrashField_Type] = KSCrashField_Hang;

            // Remove signal, mach and exit reason
            [hang.decodedReport[KSCrashField_Crash][KSCrashField_Error] removeObjectForKey:KSCrashField_Signal];
            [hang.decodedReport[KSCrashField_Crash][KSCrashField_Error] removeObjectForKey:KSCrashField_Mach];
            [hang.decodedReport[KSCrashField_Crash][KSCrashField_Error] removeObjectForKey:KSCrashField_ExitReason];

            // write report back to disk
            NSError *error = nil;
            NSData *newData = [KSJSONCodec encode:hang.decodedReport options:KSJSONEncodeOptionNone error:&error];
            if (newData) {
                if (![newData writeToFile:hang.path options:0 error:&error]) {
                    KSLOG_ERROR(@"[HANG] Failed to write final report to %@: %@", hang.path, error);
                }
            } else {
                KSLOG_ERROR(@"[HANG] Failed to encode final report: %@", error);
            }

        } else {
            // simply delete the hang since we don't report non-fatal hangs.
            if (unlink(hang.path.UTF8String) != 0) {
                KSLOG_ERROR(@"[HANG] Failed to delete hang report at %@: %s", hang.path, strerror(errno));
            }
        }
    }

    [self _sendObserversForType:KSHangChangeTypeEnded timeStamp:hang.timestamp now:hang.endTimestamp];
}

- (void)_populateReportForCurrentHang
{
    // Get a reference to the hang we just created.
    // We need to verify it's still the same hang after doing heavy work.
    __block KSHang *hang = nil;
    [_lock withLock:^{
        hang = self->_hang;
    }];

    if (hang == nil) {
        // Hang was ended before we could populate - that's fine
        KSLOG_DEBUG(@"[HANG] hang ended before report could be populated");
        return;
    }

    // On hang start, we write the report we want to be on disk
    // if the application is terminated by the timeout Watchdog.
    // As the hang progresses, we update the report with the
    // current timestamp.
    // If the hang recovers, we have two options:
    // 1- report as a non-fatal hang.
    // 2- delete the report and don't report anything.
    // if the app is terminated due to the hang, the report
    // is on disk and will be reported as a fatal watchdog timeout.

    if (g_callbacks.handle && g_callbacks.notify) {
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
        // crashContext->crashReason = "Watchdog";

        crashContext->Hang.inProgress = true;
        crashContext->Hang.timestamp = hang.timestamp;
        crashContext->Hang.role = hang.role;
        crashContext->Hang.endTimestamp = hang.endTimestamp;
        crashContext->Hang.endRole = hang.endRole;

        KSCrash_ReportResult result = { 0 };
        g_callbacks.handleWithResult(crashContext, &result);

        // Update hang with report details, but only if it's still the same hang
        [_lock withLock:^{
            if (self->_hang == hang) {
                // Still the same hang, safe to update
                hang.reportId = result.reportId;
                hang.path = @(result.path);
                hang.decodedReport = DecodeReport(hang.path);
            } else {
                // Hang was ended and possibly a new one started - discard our work
                KSLOG_DEBUG(@"[HANG] hang changed during report population - discarding");
            }
        }];
    }

    [self _sendObserversForType:KSHangChangeTypeStarted timeStamp:hang.timestamp now:hang.endTimestamp];
}

@end

// ============================================================================
#pragma mark - API -
// ============================================================================

static const char *monitorId(void) { return "Watchdog"; }

static KSCrashMonitorFlag monitorFlags(void) { return KSCrashMonitorFlagNone; }

static void setEnabled(bool isEnabled)
{
    BOOL forceEnable = NSProcessInfo.processInfo.environment[@"KSCRASH_FORCE_ENABLE_WATCHDOG"].boolValue;
    if (!forceEnable && ksdebug_isBeingTraced()) {
        KSLOG_DEBUG(@"Cannot run watchdog monitor while attached to a debugger.");
        return;
    }

    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        // We were already in the expected state
        return;
    }

    if (isEnabled) {
        KSLOG_DEBUG(@"Creating watchdog.");
        g_watchdog = [[KSHangMonitor alloc] initWithRunLoop:CFRunLoopGetMain() threshold:0.249];
    } else {
        KSLOG_DEBUG(@"Stopping watchdog.");
        g_watchdog = nil;
    }
}

static bool isEnabled(void) { return g_isEnabled; }

static void init(KSCrash_ExceptionHandlerCallbacks *callbacks) { g_callbacks = *callbacks; }

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

// See header for documentation.
id kshang_addHangObserver(KSHangObserverBlock observer)
{
    return [g_watchdog addObserver:observer];
}

KSCrashMonitorAPI *kscm_watchdog_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = init;
        api.monitorId = monitorId;
        api.monitorFlags = monitorFlags;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
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
