//
//  KSCrashMonitor_System.m
//
//  Created by Karl Stenerud on 2012-02-05.
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

#import "KSCrashMonitor_System.h"

#import "KSBinaryImageCache.h"
#import "KSCPU.h"
#import "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#import "KSDate.h"
#import "KSFileUtils.h"
#import "KSJailbreak.h"
#import "KSSpinLock.h"
#import "KSSysCtl.h"
#import "KSSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#if KSCRASH_HAS_UIKIT
#import <UIKit/UIKit.h>
#endif
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdatomic.h>

static KSCrash_SystemData *g_systemData = NULL;
static KSSpinLock g_systemDataLock = KSSPINLOCK_INIT;
static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };

static atomic_bool g_isEnabled = false;

// ============================================================================
#pragma mark - Utility -
// ============================================================================

static void safeStrlcpy(char *dst, const char *src, size_t dstSize)
{
    if (src != NULL) {
        strlcpy(dst, src, dstSize);
    } else {
        dst[0] = '\0';
    }
}

static void safeNSStringCopy(char *dst, NSString *src, size_t dstSize)
{
    if (src != NULL) {
        strlcpy(dst, src.UTF8String, dstSize);
    } else {
        dst[0] = '\0';
    }
}

static NSString *nsstringSysctl(NSString *name)
{
    NSString *str = nil;
    int size = (int)kssysctl_stringForName(name.UTF8String, NULL, 0);

    if (size <= 0) {
        return @"";
    }

    NSMutableData *value = [NSMutableData dataWithLength:(unsigned)size];

    if (kssysctl_stringForName(name.UTF8String, value.mutableBytes, size) != 0) {
        str = [NSString stringWithCString:value.mutableBytes encoding:NSUTF8StringEncoding];
    }

    return str;
}

static void stringSysctlInto(const char *name, char *dst, size_t dstSize)
{
    int size = (int)kssysctl_stringForName(name, NULL, 0);
    if (size <= 0) {
        dst[0] = '\0';
        return;
    }

    char *value = malloc((size_t)size);
    if (kssysctl_stringForName(name, value, size) <= 0) {
        free(value);
        dst[0] = '\0';
        return;
    }

    strlcpy(dst, value, dstSize);
    free(value);
}

/** Get the current VM stats. */
static bool VMStats(vm_statistics_data_t *const vmStats, vm_size_t *const pageSize)
{
    kern_return_t kr;
    const mach_port_t hostPort = mach_host_self();

    if ((kr = host_page_size(hostPort, pageSize)) != KERN_SUCCESS) {
        KSLOG_ERROR(@"host_page_size: %s", mach_error_string(kr));
        return false;
    }

    mach_msg_type_number_t hostSize = sizeof(*vmStats) / sizeof(natural_t);
    kr = host_statistics(hostPort, HOST_VM_INFO, (host_info_t)vmStats, &hostSize);
    if (kr != KERN_SUCCESS) {
        KSLOG_ERROR(@"host_statistics: %s", mach_error_string(kr));
        return false;
    }

    return true;
}

static uint64_t getFreeMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if (VMStats(&vmStats, &pageSize)) {
        return ((uint64_t)pageSize) * vmStats.free_count;
    }
    return 0;
}

static uint64_t getUsableMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if (VMStats(&vmStats, &pageSize)) {
        return ((uint64_t)pageSize) *
               (vmStats.active_count + vmStats.inactive_count + vmStats.wire_count + vmStats.free_count);
    }
    return 0;
}

/** Convert raw UUID bytes to a human-readable string into dst. */
static void uuidBytesToStringInto(const uint8_t *uuidBytes, char *dst, size_t dstSize)
{
    CFUUIDRef uuidRef = CFUUIDCreateFromUUIDBytes(NULL, *((CFUUIDBytes *)uuidBytes));
    NSString *str = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    safeNSStringCopy(dst, str, dstSize);
}

static NSString *getExecutablePath(void)
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDict = [mainBundle infoDictionary];
    NSString *bundlePath = [mainBundle bundlePath];
    NSString *executableName = infoDict[@"CFBundleExecutable"];
    return [bundlePath stringByAppendingPathComponent:executableName];
}

static void getAppUUIDInto(char *dst, size_t dstSize)
{
    const uint8_t *uuid = ksbic_getUUIDForHeader(ksbic_getAppHeader());
    if (uuid != NULL) {
        uuidBytesToStringInto(uuid, dst, dstSize);
    } else {
        dst[0] = '\0';
    }
}

static const char *getCPUArchForCPUType(cpu_type_t cpuType, cpu_subtype_t subType)
{
    switch (cpuType) {
        case CPU_TYPE_ARM: {
            switch (subType) {
                case CPU_SUBTYPE_ARM_V6:
                    return "armv6";
                case CPU_SUBTYPE_ARM_V7:
                    return "armv7";
                case CPU_SUBTYPE_ARM_V7F:
                    return "armv7f";
                case CPU_SUBTYPE_ARM_V7K:
                    return "armv7k";
#ifdef CPU_SUBTYPE_ARM_V7S
                case CPU_SUBTYPE_ARM_V7S:
                    return "armv7s";
#endif
                default:
                    return "arm";
            }
        }
        case CPU_TYPE_ARM64: {
            switch (subType) {
                case CPU_SUBTYPE_ARM64E:
                    return "arm64e";
                default:
                    return "arm64";
            }
        }
        case CPU_TYPE_X86:
            return "x86";
        case CPU_TYPE_X86_64:
            return "x86_64";
        default:
            return NULL;
    }
}

static const char *getCurrentCPUArch(void)
{
    const char *result =
        getCPUArchForCPUType(kssysctl_int32ForName("hw.cputype"), kssysctl_int32ForName("hw.cpusubtype"));

    if (result == NULL) {
        result = kscpu_currentArch();
    }
    return result;
}

static inline bool isJailbroken(void)
{
    static bool is_jailbroken;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        get_jailbreak_status(&is_jailbroken);
    });
    return is_jailbroken;
}

static bool procTranslated(void)
{
#if KSCRASH_HOST_MAC
    int proc_translated = 0;
    size_t size = sizeof(proc_translated);
    if (!sysctlbyname("sysctl.proc_translated", &proc_translated, &size, NULL, 0) && proc_translated) {
        return true;
    }
#endif
    return false;
}

static bool isDebugBuild(void)
{
#ifdef DEBUG
    return YES;
#else
    return NO;
#endif
}

static bool isSimulatorBuild(void)
{
#if TARGET_OS_SIMULATOR
    return YES;
#else
    return NO;
#endif
}

static NSString *getReceiptUrlPath(void)
{
    NSString *path = nil;
#if KSCRASH_HOST_IOS
    path = [NSBundle mainBundle].appStoreReceiptURL.path;
#endif
    return path;
}

/** Generate a 20 byte SHA1 hash that remains unique across a single device and
 * application. This is slightly different from the Apple crash report key,
 * which is unique to the device, regardless of the application.
 */
static void getDeviceAndAppHashInto(char *dst, size_t dstSize)
{
    NSMutableData *data = nil;

#if KSCRASH_HAS_UIDEVICE
    if ([[UIDevice currentDevice] respondsToSelector:@selector(identifierForVendor)]) {
        data = [NSMutableData dataWithLength:16];
        [[UIDevice currentDevice].identifierForVendor getUUIDBytes:data.mutableBytes];
    } else
#endif
    {
        data = [NSMutableData dataWithLength:6];
        kssysctl_getMacAddress("en0", [data mutableBytes]);
    }

    [data appendData:(NSData *_Nonnull)[nsstringSysctl(@"hw.machine") dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:(NSData *_Nonnull)[nsstringSysctl(@"hw.model") dataUsingEncoding:NSUTF8StringEncoding]];
    const char *cpuArch = getCurrentCPUArch();
    [data appendBytes:cpuArch length:strlen(cpuArch)];

    NSData *bundleID = [[[NSBundle mainBundle] bundleIdentifier] dataUsingEncoding:NSUTF8StringEncoding];
    if (bundleID != nil) {
        [data appendData:bundleID];
    }

    uint8_t sha[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([data bytes], (CC_LONG)[data length], sha);

    NSMutableString *hash = [NSMutableString string];
    for (unsigned i = 0; i < sizeof(sha); i++) {
        [hash appendFormat:@"%02x", sha[i]];
    }

    safeNSStringCopy(dst, hash, dstSize);
}

static bool isTestBuild(void) { return [getReceiptUrlPath().lastPathComponent isEqualToString:@"sandboxReceipt"]; }

static bool hasAppStoreReceipt(void)
{
    NSString *receiptPath = getReceiptUrlPath();
    if (receiptPath == nil) {
        return NO;
    }
    bool isAppStoreReceipt = [receiptPath.lastPathComponent isEqualToString:@"receipt"];
    bool receiptExists = [[NSFileManager defaultManager] fileExistsAtPath:receiptPath];

    return isAppStoreReceipt && receiptExists;
}

static const char *getBuildType(void)
{
    if (isSimulatorBuild()) {
        return "simulator";
    }
    if (isDebugBuild()) {
        return "debug";
    }
    if (isTestBuild()) {
        return "test";
    }
    if (hasAppStoreReceipt()) {
        return "app store";
    }
    return "unknown";
}

// ============================================================================
#pragma mark - API -
// ============================================================================

static void initialize(void)
{
    if (g_systemData != NULL) {
        return;
    }

    // Get run sidecar path and mmap the struct
    char sidecarPath[KSSYS_MAX_PATH];
    if (!g_callbacks.getRunSidecarPath || !g_callbacks.getRunSidecarPath("System", sidecarPath, sizeof(sidecarPath))) {
        KSLOG_ERROR(@"Failed to get run sidecar path for System monitor");
        return;
    }

    void *ptr = ksfu_mmap(sidecarPath, sizeof(KSCrash_SystemData));
    if (!ptr) {
        KSLOG_ERROR(@"Failed to mmap system data at %s", sidecarPath);
        return;
    }
    g_systemData = (KSCrash_SystemData *)ptr;

    // Populate all static fields
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDict = [mainBundle infoDictionary];
    const struct mach_header *header = _dyld_get_image_header(0);

#if KSCRASH_HAS_UIDEVICE
    safeNSStringCopy(g_systemData->systemName, [UIDevice currentDevice].systemName, sizeof(g_systemData->systemName));
    safeNSStringCopy(g_systemData->systemVersion, [UIDevice currentDevice].systemVersion,
                     sizeof(g_systemData->systemVersion));
#else
#if KSCRASH_HOST_MAC
    safeStrlcpy(g_systemData->systemName, "macOS", sizeof(g_systemData->systemName));
#endif
#if KSCRASH_HOST_WATCH
    safeStrlcpy(g_systemData->systemName, "watchOS", sizeof(g_systemData->systemName));
#endif
    NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
    NSString *systemVersion;
    if (version.patchVersion == 0) {
        systemVersion = [NSString stringWithFormat:@"%d.%d", (int)version.majorVersion, (int)version.minorVersion];
    } else {
        systemVersion = [NSString stringWithFormat:@"%d.%d.%d", (int)version.majorVersion, (int)version.minorVersion,
                                                   (int)version.patchVersion];
    }
    safeNSStringCopy(g_systemData->systemVersion, systemVersion, sizeof(g_systemData->systemVersion));
#endif
    stringSysctlInto("kern.version", g_systemData->kernelVersion, sizeof(g_systemData->kernelVersion));

    if (isSimulatorBuild()) {
        safeNSStringCopy(g_systemData->machine, [NSProcessInfo processInfo].environment[@"SIMULATOR_MODEL_IDENTIFIER"],
                         sizeof(g_systemData->machine));
        safeStrlcpy(g_systemData->model, "simulator", sizeof(g_systemData->model));
        safeNSStringCopy(g_systemData->systemVersion,
                         [NSProcessInfo processInfo].environment[@"SIMULATOR_RUNTIME_VERSION"],
                         sizeof(g_systemData->systemVersion));
        safeNSStringCopy(g_systemData->osVersion,
                         [NSProcessInfo processInfo].environment[@"SIMULATOR_RUNTIME_BUILD_VERSION"],
                         sizeof(g_systemData->osVersion));
    } else {
#if KSCRASH_HOST_MAC
        stringSysctlInto("hw.model", g_systemData->machine, sizeof(g_systemData->machine));
#else
        stringSysctlInto("hw.machine", g_systemData->machine, sizeof(g_systemData->machine));
        stringSysctlInto("hw.model", g_systemData->model, sizeof(g_systemData->model));
#endif
        stringSysctlInto("kern.osversion", g_systemData->osVersion, sizeof(g_systemData->osVersion));
    }
    g_systemData->isJailbroken = isJailbroken();
    g_systemData->procTranslated = procTranslated();

    char timeBuf[KSDATE_BUFFERSIZE];
    ksdate_utcStringFromTimestamp(time(NULL), timeBuf, sizeof(timeBuf));
    safeStrlcpy(g_systemData->appStartTime, timeBuf, sizeof(g_systemData->appStartTime));

    safeNSStringCopy(g_systemData->executablePath, getExecutablePath(), sizeof(g_systemData->executablePath));
    safeNSStringCopy(g_systemData->executableName, infoDict[@"CFBundleExecutable"],
                     sizeof(g_systemData->executableName));
    safeNSStringCopy(g_systemData->bundleID, infoDict[@"CFBundleIdentifier"], sizeof(g_systemData->bundleID));
    safeNSStringCopy(g_systemData->bundleName, infoDict[@"CFBundleName"], sizeof(g_systemData->bundleName));
    safeNSStringCopy(g_systemData->bundleVersion, infoDict[@"CFBundleVersion"], sizeof(g_systemData->bundleVersion));
    safeNSStringCopy(g_systemData->bundleShortVersion, infoDict[@"CFBundleShortVersionString"],
                     sizeof(g_systemData->bundleShortVersion));
    getAppUUIDInto(g_systemData->appID, sizeof(g_systemData->appID));
    safeStrlcpy(g_systemData->cpuArchitecture, getCurrentCPUArch(), sizeof(g_systemData->cpuArchitecture));
    g_systemData->cpuType = kssysctl_int32ForName("hw.cputype");
    g_systemData->cpuSubType = kssysctl_int32ForName("hw.cpusubtype");
    g_systemData->binaryCPUType = header->cputype;
    g_systemData->binaryCPUSubType = header->cpusubtype;
    safeNSStringCopy(g_systemData->timezone, [NSTimeZone localTimeZone].abbreviation, sizeof(g_systemData->timezone));
    safeNSStringCopy(g_systemData->processName, [NSProcessInfo processInfo].processName,
                     sizeof(g_systemData->processName));
    g_systemData->processID = [NSProcessInfo processInfo].processIdentifier;
    g_systemData->parentProcessID = getppid();
    getDeviceAndAppHashInto(g_systemData->deviceAppHash, sizeof(g_systemData->deviceAppHash));
    safeStrlcpy(g_systemData->buildType, getBuildType(), sizeof(g_systemData->buildType));
    g_systemData->memorySize = kssysctl_uint64ForName("hw.memsize");

    const char *binaryArch = getCPUArchForCPUType(header->cputype, header->cpusubtype);
    safeStrlcpy(g_systemData->binaryArchitecture, binaryArch != NULL ? binaryArch : "",
                sizeof(g_systemData->binaryArchitecture));

#ifdef __clang_version__
    safeStrlcpy(g_systemData->clangVersion, __clang_version__, sizeof(g_systemData->clangVersion));
#endif

    g_systemData->magic = KSSYS_MAGIC;
    g_systemData->version = KSCrash_System_CurrentVersion;
}

static const char *monitorId(__unused void *context) { return "System"; }

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    g_callbacks = *callbacks;
}

static void setEnabled(bool isEnabled, __unused void *context)
{
    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        return;
    }

    if (isEnabled) {
        initialize();
    } else {
        ks_spinlock_lock(&g_systemDataLock);
        KSCrash_SystemData *old = g_systemData;
        g_systemData = NULL;
        ks_spinlock_unlock(&g_systemDataLock);
        if (old) {
            ksfu_munmap(old, sizeof(KSCrash_SystemData));
        }
    }
}

static bool isEnabled_func(__unused void *context) { return g_isEnabled; }

static void addContextualInfoToEvent(__unused KSCrash_MonitorContext *eventContext, __unused void *context)
{
    // Bounded: this runs at crash time, possibly from a signal handler.
    // If we can't acquire within the spin limit, just skip — stale values are acceptable.
    if (!ks_spinlock_lock_bounded(&g_systemDataLock)) {
        return;
    }
    if (g_systemData != NULL) {
        g_systemData->freeMemory = getFreeMemory();
        g_systemData->usableMemory = getUsableMemory();
    }
    ks_spinlock_unlock(&g_systemDataLock);
}

bool kscm_system_getSystemData(KSCrash_SystemData *dst)
{
    if (dst == NULL) {
        return false;
    }
    bool ok = false;
    ks_spinlock_lock(&g_systemDataLock);
    if (g_systemData != NULL) {
        *dst = *g_systemData;
        ok = true;
    }
    ks_spinlock_unlock(&g_systemDataLock);
    return ok;
}

void kscm_system_setBootTime(int64_t bootTimestamp)
{
    ks_spinlock_lock(&g_systemDataLock);
    if (g_systemData != NULL) {
        g_systemData->bootTimestamp = bootTimestamp;
    }
    ks_spinlock_unlock(&g_systemDataLock);
}

void kscm_system_setDiscSpace(uint64_t storageSize, uint64_t freeStorageSize)
{
    ks_spinlock_lock(&g_systemDataLock);
    if (g_systemData != NULL) {
        g_systemData->storageSize = storageSize;
        g_systemData->freeStorageSize = freeStorageSize;
    }
    ks_spinlock_unlock(&g_systemDataLock);
}

void kscm_system_setFreeStorageSize(uint64_t freeStorageSize)
{
    // Bounded: called from disc space monitor's addContextualInfoToEvent on the
    // crash path, where threads may be suspended holding this lock.
    if (!ks_spinlock_lock_bounded(&g_systemDataLock)) {
        return;
    }
    if (g_systemData != NULL) {
        g_systemData->freeStorageSize = freeStorageSize;
    }
    ks_spinlock_unlock(&g_systemDataLock);
}

/** Implemented in KSCrashMonitor_SystemStitch.m */
extern char *kscm_system_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                      void *context);

KSCrashMonitorAPI *kscm_system_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled_func;
        api.addContextualInfoToEvent = addContextualInfoToEvent;
        api.stitchReport = kscm_system_stitchReport;
    }
    return &api;
}
