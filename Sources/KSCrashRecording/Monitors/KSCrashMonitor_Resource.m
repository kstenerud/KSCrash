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

#import <os/lock.h>
#import "KSCrashAppMemory.h"
#import "KSCrashAppMemoryTracker.h"
#import "KSCrashC.h"
#import "KSCrashCPUTracker.h"
#import "KSCrashMonitorHelper.h"
#import "KSFileUtils.h"
#import "KSSystemCapabilities.h"

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <stdatomic.h>
#import <unistd.h>

#import <sys/sysctl.h>
#import <time.h>

#import "KSDate.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#if KSCRASH_HAS_UIAPPLICATION
#import <UIKit/UIKit.h>
#endif

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static atomic_bool g_isEnabled = false;
static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };

static os_unfair_lock g_resourceLock = OS_UNFAIR_LOCK_INIT;
static KSCrash_ResourceData *g_resource = NULL;

// Observers / timers
static id g_memoryObserver = nil;
static id g_cpuObserver = nil;

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
#pragma mark - Test Overrides -
// ============================================================================

// Re-apply env-var overrides after every resourceUpdate so polled values
// don't clobber the faked ones.  getenv() returns NULL immediately in
// production (no env vars set), so the cost is negligible.
static void applyResourceTestOverrides(KSCrash_ResourceData *res)
{
    const char *val;
    if ((val = getenv("KSCRASH_TEST_MEMORY_PRESSURE")) != NULL) res->memoryPressure = (uint8_t)atoi(val);
    if ((val = getenv("KSCRASH_TEST_MEMORY_LEVEL")) != NULL) res->memoryLevel = (uint8_t)atoi(val);
    if ((val = getenv("KSCRASH_TEST_THERMAL_STATE")) != NULL) res->thermalState = (uint8_t)atoi(val);
    if ((val = getenv("KSCRASH_TEST_CPU_USER")) != NULL) res->cpuUsageUser = (uint16_t)atoi(val);
    if ((val = getenv("KSCRASH_TEST_CPU_SYSTEM")) != NULL) res->cpuUsageSystem = (uint16_t)atoi(val);
    if ((val = getenv("KSCRASH_TEST_CPU_CORES")) != NULL) res->cpuCoreCount = (uint8_t)atoi(val);
    if ((val = getenv("KSCRASH_TEST_CPU_STATE")) != NULL) res->cpuState = (uint8_t)atoi(val);
    if ((val = getenv("KSCRASH_TEST_BATTERY_LEVEL")) != NULL) res->batteryLevel = (uint8_t)atoi(val);
    if ((val = getenv("KSCRASH_TEST_BATTERY_STATE")) != NULL) res->batteryState = (uint8_t)atoi(val);
}

// ============================================================================
#pragma mark - Sidecar Access -
// ============================================================================

/** Update the mmap'd struct under lock, then re-apply any test overrides. */
static void resourceUpdate(void (^block)(KSCrash_ResourceData *res))
{
    if (!block) return;
    os_unfair_lock_lock(&g_resourceLock);
    if (g_resource) {
        block(g_resource);
        applyResourceTestOverrides(g_resource);
    }
    os_unfair_lock_unlock(&g_resourceLock);
}

/** Replace the global resource pointer, unmapping the old one. */
static void resourceSet(KSCrash_ResourceData *res)
{
    void *old = NULL;
    os_unfair_lock_lock(&g_resourceLock);
    old = g_resource;
    g_resource = res;
    os_unfair_lock_unlock(&g_resourceLock);

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
#pragma mark - CPU / Thread Observer -
// ============================================================================

static void writeCPUSnapshot(KSCrashCPU *cpu)
{
    resourceUpdate(^(KSCrash_ResourceData *res) {
        res->cpuUsageUser = cpu.usageUser;
        res->cpuUsageSystem = cpu.usageSystem;
        res->cpuAverageUsagePermil = (uint16_t)(cpu.averageUsageInWindow * 1000.0);
        res->cpuState = (uint8_t)cpu.state;
        res->threadCount = cpu.threadCount;
        res->cpuTimeInWindowNs = (uint64_t)(cpu.cpuTimeInWindow * 1e9);
        res->cpuWallTimeInWindowNs = (uint64_t)(cpu.wallTimeInWindow * 1e9);
        res->cpuUpdatedAtNs = cpu.timestampNs;
    });
}

static void startCPUObserver(void)
{
    g_cpuObserver = [KSCrashCPUTracker.sharedInstance
        addObserverWithBlock:^(KSCrashCPU *cpu, __unused KSCrashCPUTrackerChangeType changes) {
            writeCPUSnapshot(cpu);
        }];

    KSCrashCPU *current = KSCrashCPUTracker.sharedInstance.currentCPU;
    if (current != nil) {
        writeCPUSnapshot(current);
    }
}

static void stopCPUObserver(void) { g_cpuObserver = nil; }

// ============================================================================
#pragma mark - Memory Observer -
// ============================================================================

static void startMemoryObserver(void)
{
    g_memoryObserver = [KSCrashAppMemoryTracker.sharedInstance
        addObserverWithBlock:^(KSCrashAppMemory *memory, KSCrashAppMemoryTrackerChangeType changes) {
            uint64_t now = ksdate_continuousNanoseconds();
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
                res->memoryUpdatedAtNs = now;
            });
        }];

    // Seed with current values so the sidecar isn't all-zero if a crash
    // happens before the first real change/heartbeat notification.
    KSCrashAppMemory *current = KSCrashAppMemoryTracker.sharedInstance.currentAppMemory;
    if (current != nil) {
        uint64_t now = ksdate_continuousNanoseconds();
        resourceUpdate(^(KSCrash_ResourceData *res) {
            res->memoryFootprint = current.footprint;
            res->memoryRemaining = current.remaining;
            res->memoryLimit = current.limit;
            res->memoryPressure = (uint8_t)current.pressure;
            res->memoryLevel = (uint8_t)current.level;
            res->memoryUpdatedAtNs = now;
        });
    }
}

static void stopMemoryObserver(void) { g_memoryObserver = nil; }

// ============================================================================
#pragma mark - Battery (iOS only) -
// ============================================================================

#if KSCRASH_HOST_IOS

static void readBattery(uint8_t *outLevel, uint8_t *outState)
{
    UIDevice *device = UIDevice.currentDevice;
    float level = device.batteryLevel;
    *outLevel = (level < 0) ? 255 : (uint8_t)(level * 100.0f);

    switch (device.batteryState) {
        case UIDeviceBatteryStateUnplugged:
            *outState = KSCrashBatteryStateUnplugged;
            break;
        case UIDeviceBatteryStateCharging:
            *outState = KSCrashBatteryStateCharging;
            break;
        case UIDeviceBatteryStateFull:
            *outState = KSCrashBatteryStateFull;
            break;
        default:
            *outState = KSCrashBatteryStateUnknown;
            break;
    }
}

static void writeBattery(void)
{
    uint8_t level, state;
    readBattery(&level, &state);
    uint64_t now = ksdate_continuousNanoseconds();
    resourceUpdate(^(KSCrash_ResourceData *res) {
        res->batteryLevel = level;
        res->batteryState = state;
        res->batteryUpdatedAtNs = now;
    });
}

static void startBatteryObservers(void)
{
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;

    writeBattery();

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

    g_batteryLevelObserver = [nc addObserverForName:UIDeviceBatteryLevelDidChangeNotification
                                             object:nil
                                              queue:nil
                                         usingBlock:^(__unused NSNotification *note) {
                                             writeBattery();
                                         }];

    g_batteryStateObserver = [nc addObserverForName:UIDeviceBatteryStateDidChangeNotification
                                             object:nil
                                              queue:nil
                                         usingBlock:^(__unused NSNotification *note) {
                                             writeBattery();
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

static void writeThermalState(void)
{
    uint8_t state = thermalStateToUInt8(NSProcessInfo.processInfo.thermalState);
    uint64_t now = ksdate_continuousNanoseconds();
    resourceUpdate(^(KSCrash_ResourceData *res) {
        res->thermalState = state;
        res->thermalUpdatedAtNs = now;
    });
}

static void startThermalObserver(void)
{
    writeThermalState();

    g_thermalStateObserver =
        [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(__unused NSNotification *note) {
                                                        writeThermalState();
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
    uint8_t active = UIApplication.sharedApplication.isProtectedDataAvailable ? 1 : 0;
    uint64_t now = ksdate_continuousNanoseconds();
    resourceUpdate(^(KSCrash_ResourceData *res) {
        res->dataProtectionActive = active;
        res->dataProtectionUpdatedAtNs = now;
    });

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

    g_protectedDataAvailableObserver = [nc addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
                                                       object:nil
                                                        queue:nil
                                                   usingBlock:^(__unused NSNotification *note) {
                                                       uint64_t ts = ksdate_continuousNanoseconds();
                                                       resourceUpdate(^(KSCrash_ResourceData *res) {
                                                           res->dataProtectionActive = 1;
                                                           res->dataProtectionUpdatedAtNs = ts;
                                                       });
                                                   }];

    g_protectedDataUnavailableObserver = [nc addObserverForName:UIApplicationProtectedDataWillBecomeUnavailable
                                                         object:nil
                                                          queue:nil
                                                     usingBlock:^(__unused NSNotification *note) {
                                                         uint64_t ts = ksdate_continuousNanoseconds();
                                                         resourceUpdate(^(KSCrash_ResourceData *res) {
                                                             res->dataProtectionActive = 0;
                                                             res->dataProtectionUpdatedAtNs = ts;
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
static void writeLowPowerMode(void)
{
    if (@available(macOS 12.0, iOS 9.0, tvOS 9.0, watchOS 2.0, *)) {
        uint8_t mode = NSProcessInfo.processInfo.lowPowerModeEnabled ? 1 : 0;
        uint64_t now = ksdate_continuousNanoseconds();
        resourceUpdate(^(KSCrash_ResourceData *res) {
            res->lowPowerMode = mode;
            res->lowPowerUpdatedAtNs = now;
        });
    }
}

static void startPowerObserver(void)
{
    writeLowPowerMode();

    if (@available(macOS 12.0, iOS 9.0, tvOS 9.0, watchOS 2.0, *)) {
        g_powerStateObserver =
            [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                                                            object:nil
                                                             queue:nil
                                                        usingBlock:^(__unused NSNotification *note) {
                                                            writeLowPowerMode();
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
    os_unfair_lock_lock(&g_resourceLock);
    if (g_resource && validateResourceData(g_resource)) {
        *outData = *g_resource;
        ok = true;
    }
    os_unfair_lock_unlock(&g_resourceLock);
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
            res->cpuCoreCount = KSCrashCPUTracker.sharedInstance.coreCount;

            // Defaults for platforms without battery / data protection
            res->batteryLevel = 255;
            res->batteryState = KSCrashBatteryStateUnknown;
            res->dataProtectionActive = 1;
        });

        startMemoryObserver();
        startCPUObserver();
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
        stopCPUObserver();
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

KSCrashMonitorAPI *kscm_resource_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled_func;
        api.createStitchedReport = kscm_resource_createStitchedReport;
    }
    return &api;
}
