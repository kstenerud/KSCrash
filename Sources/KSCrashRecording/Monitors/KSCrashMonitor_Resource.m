//
//  KSCrashMonitor_Resource.m
//
//  Created by Alexander Cohen on 2026-03-03.
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

#import "KSCrashMonitor_Resource.h"

#import "KSCrashAppMemory.h"
#import "KSCrashAppMemoryTracker.h"
#import "KSCrashC.h"
#import "KSCrashMonitorHelper.h"
#import "KSFileUtils.h"
#import "KSSpinLock.h"
#import "KSSystemCapabilities.h"

#import <Foundation/Foundation.h>
#import <stdatomic.h>

// proc_pidinfo is available on all Apple platforms but libproc.h
// is only in the macOS SDK.  Forward-declare what we need.
#if __has_include(<libproc.h>)
#import <libproc.h>
#else
#define PROC_PIDTASKINFO 4
struct proc_taskinfo {
    uint64_t pti_virtual_size;
    uint64_t pti_resident_size;
    uint64_t pti_total_user;
    uint64_t pti_total_system;
    uint64_t pti_threads_user;
    uint64_t pti_threads_system;
    int32_t pti_policy;
    int32_t pti_faults;
    int32_t pti_pageins;
    int32_t pti_cow_faults;
    int32_t pti_messages_sent;
    int32_t pti_messages_received;
    int32_t pti_syscalls_mach;
    int32_t pti_syscalls_unix;
    int32_t pti_csw;
    int32_t pti_threadnum;
    int32_t pti_numrunning;
    int32_t pti_priority;
};
int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
#endif
#import <sys/sysctl.h>
#import <time.h>

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#if KSCRASH_HAS_UIAPPLICATION
#import <UIKit/UIKit.h>
#endif

// ============================================================================
#pragma mark - Constants -
// ============================================================================

static const NSTimeInterval kCPUPollingInterval = 5.0;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static atomic_bool g_isEnabled = false;
static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };

static KSSpinLock g_resourceLock = KSSPINLOCK_INIT;
static KSCrash_ResourceData *g_resource = NULL;

// Observers / timers
static id g_memoryObserver = nil;
static dispatch_source_t g_cpuTimer = NULL;

static id g_powerStateObserver = nil;

#if KSCRASH_HOST_IOS
static id g_batteryLevelObserver = nil;
static id g_batteryStateObserver = nil;
#endif

#if KSCRASH_HAS_UIAPPLICATION
static id g_thermalStateObserver = nil;
static id g_protectedDataAvailableObserver = nil;
static id g_protectedDataUnavailableObserver = nil;
#endif

// ============================================================================
#pragma mark - Sidecar Access -
// ============================================================================

/** Update the mmap'd struct under spinlock (normal context). */
static void resourceUpdate(void (^block)(KSCrash_ResourceData *res))
{
    if (!block) return;
    ks_spinlock_lock(&g_resourceLock);
    if (g_resource) {
        block(g_resource);
    }
    ks_spinlock_unlock(&g_resourceLock);
}

/** Replace the global resource pointer, unmapping the old one. */
static void resourceSet(KSCrash_ResourceData *res)
{
    void *old = NULL;
    ks_spinlock_lock(&g_resourceLock);
    old = g_resource;
    g_resource = res;
    ks_spinlock_unlock(&g_resourceLock);

    if (old) {
        ksfu_munmap(old, sizeof(KSCrash_ResourceData));
    }
}

// ============================================================================
#pragma mark - Validation -
// ============================================================================

static bool validateResourceData(const KSCrash_ResourceData *data)
{
    if (data->magic != KSRESOURCE_MAGIC) return false;
    if (data->version == 0 || data->version > KSCrash_Resource_CurrentVersion) return false;
    return true;
}

// ============================================================================
#pragma mark - CPU / Thread Polling -
// ============================================================================

static uint8_t getActiveCPUCount(void)
{
    int count = 0;
    size_t size = sizeof(count);
    if (sysctlbyname("hw.activecpu", &count, &size, NULL, 0) != 0) {
        count = 1;
    }
    return (uint8_t)(count > 255 ? 255 : count);
}

/** Reads CPU time and thread count via proc_pidinfo.
 *  CPU usage is computed as the delta since the last poll,
 *  split into user-space and kernel-space components.
 */
static void pollCPUAndThreads(void)
{
    struct proc_taskinfo taskInfo = { 0 };
    int size = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &taskInfo, sizeof(taskInfo));
    if (size != (int)sizeof(taskInfo)) {
        return;
    }

    static uint64_t s_prevUserNs = 0;
    static uint64_t s_prevSystemNs = 0;
    static uint64_t s_prevWallNs = 0;

    uint64_t nowNs = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);

    uint16_t userUsage = 0;
    uint16_t systemUsage = 0;
    if (s_prevWallNs > 0 && nowNs > s_prevWallNs) {
        uint64_t wallDelta = nowNs - s_prevWallNs;
        uint64_t userDelta = taskInfo.pti_total_user - s_prevUserNs;
        uint64_t systemDelta = taskInfo.pti_total_system - s_prevSystemNs;
        userUsage = (uint16_t)((userDelta * 1000) / wallDelta);
        systemUsage = (uint16_t)((systemDelta * 1000) / wallDelta);
    }

    s_prevUserNs = taskInfo.pti_total_user;
    s_prevSystemNs = taskInfo.pti_total_system;
    s_prevWallNs = nowNs;

    uint16_t threadCount = (uint16_t)(taskInfo.pti_threadnum > UINT16_MAX ? UINT16_MAX : taskInfo.pti_threadnum);

    resourceUpdate(^(KSCrash_ResourceData *res) {
        res->cpuUsageUser = userUsage;
        res->cpuUsageSystem = systemUsage;
        res->threadCount = threadCount;
    });
}

static void startCPUTimer(void)
{
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    g_cpuTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(g_cpuTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(kCPUPollingInterval * NSEC_PER_SEC), NSEC_PER_SEC);
    dispatch_source_set_event_handler(g_cpuTimer, ^{
        if (!atomic_load(&g_isEnabled)) return;
        pollCPUAndThreads();
    });
    dispatch_resume(g_cpuTimer);
}

static void stopCPUTimer(void)
{
    if (g_cpuTimer) {
        dispatch_source_cancel(g_cpuTimer);
        g_cpuTimer = NULL;
    }
}

// ============================================================================
#pragma mark - Memory Observer -
// ============================================================================

static void startMemoryObserver(void)
{
    g_memoryObserver = [KSCrashAppMemoryTracker.sharedInstance
        addObserverWithBlock:^(KSCrashAppMemory *memory, KSCrashAppMemoryTrackerChangeType changes) {
            resourceUpdate(^(KSCrash_ResourceData *res) {
                if (changes & KSCrashAppMemoryTrackerChangeTypeFootprint) {
                    res->memoryFootprint = memory.footprint;
                    res->memoryRemaining = memory.remaining;
                    res->memoryLimit = memory.limit;
                }
                if (changes & KSCrashAppMemoryTrackerChangeTypePressure) {
                    res->memoryPressure = (uint8_t)memory.pressure;
                }
                if (changes & KSCrashAppMemoryTrackerChangeTypeLevel) {
                    res->memoryLevel = (uint8_t)memory.level;
                }
            });
        }];
}

static void stopMemoryObserver(void) { g_memoryObserver = nil; }

// ============================================================================
#pragma mark - Battery (iOS only) -
// ============================================================================

#if KSCRASH_HOST_IOS

static void updateBattery(KSCrash_ResourceData *res)
{
    UIDevice *device = UIDevice.currentDevice;
    float level = device.batteryLevel;
    res->batteryLevel = (level < 0) ? 255 : (uint8_t)(level * 100.0f);

    switch (device.batteryState) {
        case UIDeviceBatteryStateUnplugged:
            res->batteryState = 1;
            break;
        case UIDeviceBatteryStateCharging:
            res->batteryState = 2;
            break;
        case UIDeviceBatteryStateFull:
            res->batteryState = 3;
            break;
        default:
            res->batteryState = 0;
            break;
    }
}

static void startBatteryObservers(void)
{
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;

    resourceUpdate(^(KSCrash_ResourceData *res) {
        updateBattery(res);
    });

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

    g_batteryLevelObserver = [nc addObserverForName:UIDeviceBatteryLevelDidChangeNotification
                                             object:nil
                                              queue:nil
                                         usingBlock:^(__unused NSNotification *note) {
                                             resourceUpdate(^(KSCrash_ResourceData *res) {
                                                 updateBattery(res);
                                             });
                                         }];

    g_batteryStateObserver = [nc addObserverForName:UIDeviceBatteryStateDidChangeNotification
                                             object:nil
                                              queue:nil
                                         usingBlock:^(__unused NSNotification *note) {
                                             resourceUpdate(^(KSCrash_ResourceData *res) {
                                                 updateBattery(res);
                                             });
                                         }];
}

static void stopBatteryObservers(void)
{
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    if (g_batteryLevelObserver) {
        [nc removeObserver:g_batteryLevelObserver];
        g_batteryLevelObserver = nil;
    }
    if (g_batteryStateObserver) {
        [nc removeObserver:g_batteryStateObserver];
        g_batteryStateObserver = nil;
    }
    UIDevice.currentDevice.batteryMonitoringEnabled = NO;
}

#endif  // KSCRASH_HOST_IOS

// ============================================================================
#pragma mark - Thermal / Data Protection (UIApplication) -
// ============================================================================

#if KSCRASH_HAS_UIAPPLICATION

static uint8_t thermalStateToUInt8(NSProcessInfoThermalState state)
{
    switch (state) {
        case NSProcessInfoThermalStateNominal:
            return 0;
        case NSProcessInfoThermalStateFair:
            return 1;
        case NSProcessInfoThermalStateSerious:
            return 2;
        case NSProcessInfoThermalStateCritical:
            return 3;
        default:
            return 0;
    }
}

static void startThermalObserver(void)
{
    resourceUpdate(^(KSCrash_ResourceData *res) {
        res->thermalState = thermalStateToUInt8(NSProcessInfo.processInfo.thermalState);
    });

    g_thermalStateObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(__unused NSNotification *note) {
                    resourceUpdate(^(KSCrash_ResourceData *res) {
                        res->thermalState = thermalStateToUInt8(NSProcessInfo.processInfo.thermalState);
                    });
                }];
}

static void stopThermalObserver(void)
{
    if (g_thermalStateObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:g_thermalStateObserver];
        g_thermalStateObserver = nil;
    }
}

static void startDataProtectionObservers(void)
{
    resourceUpdate(^(KSCrash_ResourceData *res) {
        res->dataProtectionActive = UIApplication.sharedApplication.isProtectedDataAvailable ? 1 : 0;
    });

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

    g_protectedDataAvailableObserver = [nc addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
                                                       object:nil
                                                        queue:nil
                                                   usingBlock:^(__unused NSNotification *note) {
                                                       resourceUpdate(^(KSCrash_ResourceData *res) {
                                                           res->dataProtectionActive = 1;
                                                       });
                                                   }];

    g_protectedDataUnavailableObserver = [nc addObserverForName:UIApplicationProtectedDataWillBecomeUnavailable
                                                         object:nil
                                                          queue:nil
                                                     usingBlock:^(__unused NSNotification *note) {
                                                         resourceUpdate(^(KSCrash_ResourceData *res) {
                                                             res->dataProtectionActive = 0;
                                                         });
                                                     }];
}

static void stopDataProtectionObservers(void)
{
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    if (g_protectedDataAvailableObserver) {
        [nc removeObserver:g_protectedDataAvailableObserver];
        g_protectedDataAvailableObserver = nil;
    }
    if (g_protectedDataUnavailableObserver) {
        [nc removeObserver:g_protectedDataUnavailableObserver];
        g_protectedDataUnavailableObserver = nil;
    }
}

#endif  // KSCRASH_HAS_UIAPPLICATION

// Cross-platform: low power mode
static void startPowerObserver(void)
{
    if (@available(macOS 12.0, iOS 9.0, tvOS 9.0, watchOS 2.0, *)) {
        resourceUpdate(^(KSCrash_ResourceData *res) {
            res->lowPowerMode = NSProcessInfo.processInfo.lowPowerModeEnabled ? 1 : 0;
        });

        g_powerStateObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *note) {
                        resourceUpdate(^(KSCrash_ResourceData *res) {
                            res->lowPowerMode = NSProcessInfo.processInfo.lowPowerModeEnabled ? 1 : 0;
                        });
                    }];
    }
}

static void stopPowerObserver(void)
{
    if (g_powerStateObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:g_powerStateObserver];
        g_powerStateObserver = nil;
    }
}

// ============================================================================
#pragma mark - Public Snapshot API -
// ============================================================================

bool ksresource_getSnapshot(KSCrash_ResourceData *outData)
{
    if (!outData) return false;

    bool ok = false;
    if (ks_spinlock_lock_bounded(&g_resourceLock)) {
        if (g_resource && g_resource->magic == KSRESOURCE_MAGIC) {
            *outData = *g_resource;
            ok = true;
        }
        ks_spinlock_unlock(&g_resourceLock);
    }
    return ok;
}

bool ksresource_getSnapshotForRunID(const char *runID, KSCrash_ResourceData *outData)
{
    if (!runID || !outData || runID[0] == '\0') return false;
    if (!g_callbacks.getRunSidecarPathForRunID) return false;

    char sidecarPath[KSFU_MAX_PATH_LENGTH];
    if (!g_callbacks.getRunSidecarPathForRunID("Resource", runID, sidecarPath, sizeof(sidecarPath))) {
        return false;
    }

    int fd = open(sidecarPath, O_RDONLY);
    if (fd == -1) return false;

    KSCrash_ResourceData data = { 0 };
    bool readOK = ksfu_readBytesFromFD(fd, (char *)&data, (int)sizeof(data));
    close(fd);

    if (!readOK || !validateResourceData(&data)) return false;

    *outData = data;
    return true;
}

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static const char *monitorId(__unused void *context) { return "Resource"; }

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    g_callbacks = *callbacks;
}

static void setEnabled(bool isEnabled, __unused void *context)
{
    bool expected = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expected, isEnabled)) {
        return;
    }

    if (isEnabled) {
        char sidecarPath[KSFU_MAX_PATH_LENGTH];
        if (!g_callbacks.getRunSidecarPath ||
            !g_callbacks.getRunSidecarPath("Resource", sidecarPath, sizeof(sidecarPath))) {
            KSLOG_ERROR(@"Failed to get run sidecar path for Resource monitor");
            atomic_store(&g_isEnabled, false);
            return;
        }

        void *ptr = ksfu_mmap(sidecarPath, sizeof(KSCrash_ResourceData));
        if (!ptr) {
            KSLOG_ERROR(@"Failed to mmap resource sidecar at %s", sidecarPath);
            atomic_store(&g_isEnabled, false);
            return;
        }

        resourceSet(ptr);

        resourceUpdate(^(KSCrash_ResourceData *res) {
            res->magic = KSRESOURCE_MAGIC;
            res->version = KSCrash_Resource_CurrentVersion;
            res->cpuCoreCount = getActiveCPUCount();

            // Defaults for platforms without battery / data protection
            res->batteryLevel = 255;
            res->batteryState = 0;
            res->dataProtectionActive = 1;
        });

        startMemoryObserver();
        startCPUTimer();
        startPowerObserver();
#if KSCRASH_HOST_IOS
        startBatteryObservers();
#endif
#if KSCRASH_HAS_UIAPPLICATION
        startThermalObserver();
        startDataProtectionObservers();
#endif

    } else {
        stopMemoryObserver();
        stopCPUTimer();
        stopPowerObserver();
#if KSCRASH_HOST_IOS
        stopBatteryObservers();
#endif
#if KSCRASH_HAS_UIAPPLICATION
        stopThermalObserver();
        stopDataProtectionObservers();
#endif

        resourceSet(NULL);
    }
}

static bool isEnabled_func(__unused void *context) { return atomic_load(&g_isEnabled); }

/** Implemented in KSCrashMonitor_ResourceStitch.m */
extern char *kscm_resource_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                        void *context);

KSCrashMonitorAPI *kscm_resource_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled_func;
        api.stitchReport = kscm_resource_stitchReport;
    }
    return &api;
}
