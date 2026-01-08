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
#import "KSDynamicLinker.h"
#import "KSJailbreak.h"
#import "KSSysCtl.h"
#import "KSSystemCapabilities.h"

#import "KSCrashReportWriter.h"

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

// Field keys for report writing (definitions for extern declarations in header)
KSCrashReportFieldName KSCrashField_System = "system";
KSCrashReportFieldName KSCrashField_SystemName = "system_name";
KSCrashReportFieldName KSCrashField_SystemVersion = "system_version";
KSCrashReportFieldName KSCrashField_Machine = "machine";
KSCrashReportFieldName KSCrashField_Model = "model";
KSCrashReportFieldName KSCrashField_KernelVersion = "kernel_version";
KSCrashReportFieldName KSCrashField_OSVersion = "os_version";
KSCrashReportFieldName KSCrashField_Jailbroken = "jailbroken";
KSCrashReportFieldName KSCrashField_ProcTranslated = "proc_translated";
KSCrashReportFieldName KSCrashField_BootTime = "boot_time";
KSCrashReportFieldName KSCrashField_AppStartTime = "app_start_time";
KSCrashReportFieldName KSCrashField_ExecutablePath = "CFBundleExecutablePath";
KSCrashReportFieldName KSCrashField_Executable = "CFBundleExecutable";
KSCrashReportFieldName KSCrashField_BundleID = "CFBundleIdentifier";
KSCrashReportFieldName KSCrashField_BundleName = "CFBundleName";
KSCrashReportFieldName KSCrashField_BundleVersion = "CFBundleVersion";
KSCrashReportFieldName KSCrashField_BundleShortVersion = "CFBundleShortVersionString";
KSCrashReportFieldName KSCrashField_AppUUID = "app_uuid";
KSCrashReportFieldName KSCrashField_CPUArch = "cpu_arch";
KSCrashReportFieldName KSCrashField_BinaryArch = "binary_arch";
KSCrashReportFieldName KSCrashField_CPUType = "cpu_type";
KSCrashReportFieldName KSCrashField_ClangVersion = "clang_version";
KSCrashReportFieldName KSCrashField_CPUSubType = "cpu_subtype";
KSCrashReportFieldName KSCrashField_BinaryCPUType = "binary_cpu_type";
KSCrashReportFieldName KSCrashField_BinaryCPUSubType = "binary_cpu_subtype";
KSCrashReportFieldName KSCrashField_TimeZone = "time_zone";
KSCrashReportFieldName KSCrashField_ProcessName = "process_name";
KSCrashReportFieldName KSCrashField_ProcessID = "process_id";
KSCrashReportFieldName KSCrashField_ParentProcessID = "parent_process_id";
KSCrashReportFieldName KSCrashField_DeviceAppHash = "device_app_hash";
KSCrashReportFieldName KSCrashField_BuildType = "build_type";
KSCrashReportFieldName KSCrashField_Storage = "storage";
KSCrashReportFieldName KSCrashField_FreeStorage = "freeStorage";
KSCrashReportFieldName KSCrashField_Memory = "memory";
KSCrashReportFieldName KSCrashField_Size = "size";
KSCrashReportFieldName KSCrashField_Usable = "usable";
KSCrashReportFieldName KSCrashField_Free = "free";

typedef struct {
    const char *systemName;
    const char *systemVersion;
    const char *machine;
    const char *model;
    const char *kernelVersion;
    const char *osVersion;
    bool isJailbroken;
    bool procTranslated;
    const char *bootTime;
    const char *appStartTime;
    const char *executablePath;
    const char *executableName;
    const char *bundleID;
    const char *bundleName;
    const char *bundleVersion;
    const char *bundleShortVersion;
    const char *appID;
    const char *cpuArchitecture;
    const char *binaryArchitecture;
    const char *clangVersion;
    int cpuType;
    int cpuSubType;
    int binaryCPUType;
    int binaryCPUSubType;
    const char *timezone;
    const char *processName;
    int processID;
    int parentProcessID;
    const char *deviceAppHash;
    const char *buildType;
    uint64_t memorySize;
    uint64_t storageSize;
    uint64_t freeStorageSize;
} SystemData;

static SystemData g_systemData;

static atomic_bool g_isEnabled = false;

// ============================================================================
#pragma mark - Utility -
// ============================================================================

static const char *cString(NSString *str) { return str == NULL ? NULL : strdup(str.UTF8String); }

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

/** Get a sysctl value as a null terminated string.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
static const char *stringSysctl(const char *name)
{
    int size = (int)kssysctl_stringForName(name, NULL, 0);
    if (size <= 0) {
        return NULL;
    }

    char *value = malloc((size_t)size);
    if (kssysctl_stringForName(name, value, size) <= 0) {
        free(value);
        return NULL;
    }

    return value;
}

static const char *dateString(time_t date)
{
    char *buffer = malloc(KSDATE_BUFFERSIZE);
    ksdate_utcStringFromTimestamp(date, buffer, KSDATE_BUFFERSIZE);
    return buffer;
}

/** Get the current VM stats.
 *
 * @param vmStats Gets filled with the VM stats.
 *
 * @param pageSize gets filled with the page size.
 *
 * @return true if the operation was successful.
 */
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

static uint64_t freeMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if (VMStats(&vmStats, &pageSize)) {
        return ((uint64_t)pageSize) * vmStats.free_count;
    }
    return 0;
}

static uint64_t usableMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if (VMStats(&vmStats, &pageSize)) {
        return ((uint64_t)pageSize) *
               (vmStats.active_count + vmStats.inactive_count + vmStats.wire_count + vmStats.free_count);
    }
    return 0;
}

/** Convert raw UUID bytes to a human-readable string.
 *
 * @param uuidBytes The UUID bytes (must be 16 bytes long).
 *
 * @return The human readable form of the UUID.
 */
static const char *uuidBytesToString(const uint8_t *uuidBytes)
{
    CFUUIDRef uuidRef = CFUUIDCreateFromUUIDBytes(NULL, *((CFUUIDBytes *)uuidBytes));
    NSString *str = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);

    return cString(str);
}

/** Get this application's executable path.
 *
 * @return Executable path.
 */
static NSString *getExecutablePath(void)
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDict = [mainBundle infoDictionary];
    NSString *bundlePath = [mainBundle bundlePath];
    NSString *executableName = infoDict[@"CFBundleExecutable"];
    return [bundlePath stringByAppendingPathComponent:executableName];
}

/** Get this application's UUID.
 *
 * @return The UUID.
 */
static const char *getAppUUID(void)
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    if (!images || count == 0) {
        return NULL;
    }
    const struct mach_header *header = images[0].imageLoadAddress;

    KSBinaryImage binary = { 0 };
    if (ksdl_binaryImageForHeader(header, NULL, &binary)) {
        if (binary.uuid) {
            return uuidBytesToString(binary.uuid);
        }
    }
    return NULL;
}

/** Get the current CPU's architecture.
 *
 * @return The current CPU archutecture.
 */
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

/** Check if the current device is jailbroken.
 *
 * @return YES if the device is jailbroken.
 */
static inline bool isJailbroken(void)
{
    static bool is_jailbroken;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        get_jailbreak_status(&is_jailbroken);
    });
    return is_jailbroken;
}

/** Check if the app is started using Rosetta translation environment
 *
 * @return true if app is translated using Rosetta
 */
static bool procTranslated(void)
{
#if KSCRASH_HOST_MAC
    // https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment
    int proc_translated = 0;
    size_t size = sizeof(proc_translated);
    if (!sysctlbyname("sysctl.proc_translated", &proc_translated, &size, NULL, 0) && proc_translated) {
        return true;
    }
#endif

    return false;
}

/** Check if the current build is a debug build.
 *
 * @return YES if the app was built in debug mode.
 */
static bool isDebugBuild(void)
{
#ifdef DEBUG
    return YES;
#else
    return NO;
#endif
}

/** Check if this code is built for the simulator.
 *
 * @return YES if this is a simulator build.
 */
static bool isSimulatorBuild(void)
{
#if TARGET_OS_SIMULATOR
    return YES;
#else
    return NO;
#endif
}

/** The file path for the bundle’s App Store receipt.
 *
 * @return App Store receipt for iOS 7+, nil otherwise.
 */
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
 *
 * @return The stringified hex representation of the hash for this device + app.
 */
static const char *getDeviceAndAppHash(void)
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

    // Append some device-specific data.
    [data appendData:(NSData *_Nonnull)[nsstringSysctl(@"hw.machine") dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:(NSData *_Nonnull)[nsstringSysctl(@"hw.model") dataUsingEncoding:NSUTF8StringEncoding]];
    const char *cpuArch = getCurrentCPUArch();
    [data appendBytes:cpuArch length:strlen(cpuArch)];

    // Append the bundle ID.
    NSData *bundleID = [[[NSBundle mainBundle] bundleIdentifier] dataUsingEncoding:NSUTF8StringEncoding];
    if (bundleID != nil) {
        [data appendData:bundleID];
    }

    // SHA the whole thing.
    uint8_t sha[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([data bytes], (CC_LONG)[data length], sha);

    NSMutableString *hash = [NSMutableString string];
    for (unsigned i = 0; i < sizeof(sha); i++) {
        [hash appendFormat:@"%02x", sha[i]];
    }

    return cString(hash);
}

/** Check if the current build is a "testing" build.
 * This is useful for checking if the app was released through Testflight.
 *
 * @return YES if this is a testing build.
 */
static bool isTestBuild(void) { return [getReceiptUrlPath().lastPathComponent isEqualToString:@"sandboxReceipt"]; }

/** Check if the app has an app store receipt.
 * Only apps released through the app store will have a receipt.
 *
 * @return YES if there is an app store receipt.
 */
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
    static bool isInitialized = false;
    if (!isInitialized) {
        isInitialized = true;

        NSBundle *mainBundle = [NSBundle mainBundle];
        NSDictionary *infoDict = [mainBundle infoDictionary];
        const struct mach_header *header = _dyld_get_image_header(0);

#if KSCRASH_HAS_UIDEVICE
        g_systemData.systemName = cString([UIDevice currentDevice].systemName);
        g_systemData.systemVersion = cString([UIDevice currentDevice].systemVersion);
#else
#if KSCRASH_HOST_MAC
        g_systemData.systemName = "macOS";
#endif
#if KSCRASH_HOST_WATCH
        g_systemData.systemName = "watchOS";
#endif
        NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
        ;
        NSString *systemVersion;
        if (version.patchVersion == 0) {
            systemVersion = [NSString stringWithFormat:@"%d.%d", (int)version.majorVersion, (int)version.minorVersion];
        } else {
            systemVersion = [NSString stringWithFormat:@"%d.%d.%d", (int)version.majorVersion,
                                                       (int)version.minorVersion, (int)version.patchVersion];
        }
        g_systemData.systemVersion = cString(systemVersion);
#endif
        if (isSimulatorBuild()) {
            g_systemData.machine = cString([NSProcessInfo processInfo].environment[@"SIMULATOR_MODEL_IDENTIFIER"]);
            g_systemData.model = "simulator";
            g_systemData.systemVersion = cString([NSProcessInfo processInfo].environment[@"SIMULATOR_RUNTIME_VERSION"]);
        } else {
#if KSCRASH_HOST_MAC
            // MacOS has the machine in the model field, and no model
            g_systemData.machine = stringSysctl("hw.model");
#else
            g_systemData.machine = stringSysctl("hw.machine");
            g_systemData.model = stringSysctl("hw.model");
#endif
        }

        g_systemData.kernelVersion = stringSysctl("kern.version");
        g_systemData.osVersion = stringSysctl("kern.osversion");
        g_systemData.isJailbroken = isJailbroken();
        g_systemData.procTranslated = procTranslated();
        g_systemData.appStartTime = dateString(time(NULL));
        g_systemData.executablePath = cString(getExecutablePath());
        g_systemData.executableName = cString(infoDict[@"CFBundleExecutable"]);
        g_systemData.bundleID = cString(infoDict[@"CFBundleIdentifier"]);
        g_systemData.bundleName = cString(infoDict[@"CFBundleName"]);
        g_systemData.bundleVersion = cString(infoDict[@"CFBundleVersion"]);
        g_systemData.bundleShortVersion = cString(infoDict[@"CFBundleShortVersionString"]);
        g_systemData.appID = getAppUUID();
        g_systemData.cpuArchitecture = getCurrentCPUArch();
        g_systemData.cpuType = kssysctl_int32ForName("hw.cputype");
        g_systemData.cpuSubType = kssysctl_int32ForName("hw.cpusubtype");
        g_systemData.binaryCPUType = header->cputype;
        g_systemData.binaryCPUSubType = header->cpusubtype;
        g_systemData.timezone = cString([NSTimeZone localTimeZone].abbreviation);
        g_systemData.processName = cString([NSProcessInfo processInfo].processName);
        g_systemData.processID = [NSProcessInfo processInfo].processIdentifier;
        g_systemData.parentProcessID = getppid();
        g_systemData.deviceAppHash = getDeviceAndAppHash();
        g_systemData.buildType = getBuildType();
        g_systemData.memorySize = kssysctl_uint64ForName("hw.memsize");

        const char *binaryArch = getCPUArchForCPUType(header->cputype, header->cpusubtype);
        g_systemData.binaryArchitecture = binaryArch == NULL ? "" : binaryArch;

#ifdef __clang_version__
        g_systemData.clangVersion = __clang_version__;
#endif
    }
}

static const char *monitorId(void) { return "System"; }

static void setEnabled(bool isEnabled)
{
    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        // We were already in the expected state
        return;
    }

    if (isEnabled) {
        initialize();
    }
}

static bool isEnabled(void) { return g_isEnabled; }

static void writeMetadataInReportSection(const KSCrash_MonitorContext *monitorContext,
                                         const KSCrashReportWriter *writer)
{
    (void)monitorContext;

    writer->addStringElement(writer, KSCrashField_SystemName, g_systemData.systemName);
    writer->addStringElement(writer, KSCrashField_SystemVersion, g_systemData.systemVersion);
    writer->addStringElement(writer, KSCrashField_Machine, g_systemData.machine);
    writer->addStringElement(writer, KSCrashField_Model, g_systemData.model);
    writer->addStringElement(writer, KSCrashField_KernelVersion, g_systemData.kernelVersion);
    writer->addStringElement(writer, KSCrashField_OSVersion, g_systemData.osVersion);
    writer->addBooleanElement(writer, KSCrashField_Jailbroken, g_systemData.isJailbroken);
    writer->addBooleanElement(writer, KSCrashField_ProcTranslated, g_systemData.procTranslated);
    writer->addStringElement(writer, KSCrashField_BootTime, g_systemData.bootTime);
    writer->addStringElement(writer, KSCrashField_AppStartTime, g_systemData.appStartTime);
    writer->addStringElement(writer, KSCrashField_ExecutablePath, g_systemData.executablePath);
    writer->addStringElement(writer, KSCrashField_Executable, g_systemData.executableName);
    writer->addStringElement(writer, KSCrashField_BundleID, g_systemData.bundleID);
    writer->addStringElement(writer, KSCrashField_BundleName, g_systemData.bundleName);
    writer->addStringElement(writer, KSCrashField_BundleVersion, g_systemData.bundleVersion);
    writer->addStringElement(writer, KSCrashField_BundleShortVersion, g_systemData.bundleShortVersion);
    writer->addStringElement(writer, KSCrashField_AppUUID, g_systemData.appID);
    writer->addStringElement(writer, KSCrashField_CPUArch, g_systemData.cpuArchitecture);
    writer->addStringElement(writer, KSCrashField_BinaryArch, g_systemData.binaryArchitecture);
    writer->addIntegerElement(writer, KSCrashField_CPUType, g_systemData.cpuType);
    writer->addStringElement(writer, KSCrashField_ClangVersion, g_systemData.clangVersion);
    writer->addIntegerElement(writer, KSCrashField_CPUSubType, g_systemData.cpuSubType);
    writer->addIntegerElement(writer, KSCrashField_BinaryCPUType, g_systemData.binaryCPUType);
    writer->addIntegerElement(writer, KSCrashField_BinaryCPUSubType, g_systemData.binaryCPUSubType);
    writer->addStringElement(writer, KSCrashField_TimeZone, g_systemData.timezone);
    writer->addStringElement(writer, KSCrashField_ProcessName, g_systemData.processName);
    writer->addIntegerElement(writer, KSCrashField_ProcessID, g_systemData.processID);
    writer->addIntegerElement(writer, KSCrashField_ParentProcessID, g_systemData.parentProcessID);
    writer->addStringElement(writer, KSCrashField_DeviceAppHash, g_systemData.deviceAppHash);
    writer->addStringElement(writer, KSCrashField_BuildType, g_systemData.buildType);

    writer->addIntegerElement(writer, KSCrashField_Storage, (int64_t)g_systemData.storageSize);
    writer->addIntegerElement(writer, KSCrashField_FreeStorage, (int64_t)g_systemData.freeStorageSize);

    writer->beginObject(writer, KSCrashField_Memory);
    {
        writer->addUIntegerElement(writer, KSCrashField_Size, g_systemData.memorySize);
        writer->addUIntegerElement(writer, KSCrashField_Usable, usableMemory());
        writer->addUIntegerElement(writer, KSCrashField_Free, freeMemory());
    }
    writer->endContainer(writer);
}

void kscm_system_setStorageInfo(uint64_t storageSize, uint64_t freeStorageSize)
{
    g_systemData.storageSize = storageSize;
    g_systemData.freeStorageSize = freeStorageSize;
}

void kscm_system_setBootTime(const char *bootTime) { g_systemData.bootTime = bootTime; }

const char *kscm_system_getBootTime(void) { return g_systemData.bootTime; }

uint64_t kscm_system_getStorageSize(void) { return g_systemData.storageSize; }

const char *kscm_system_getProcessName(void) { return g_systemData.processName; }

NSDictionary *kscm_system_copySystemInfo(void)
{
    NSMutableDictionary *dict = [NSMutableDictionary new];

#define COPY_STRING(KEY, FIELD) \
    if (g_systemData.FIELD) dict[@ #KEY] = [NSString stringWithUTF8String:g_systemData.FIELD]
#define COPY_PRIMITIVE(KEY, FIELD) dict[@ #KEY] = @(g_systemData.FIELD)

    COPY_STRING(systemName, systemName);
    COPY_STRING(systemVersion, systemVersion);
    COPY_STRING(machine, machine);
    COPY_STRING(model, model);
    COPY_STRING(kernelVersion, kernelVersion);
    COPY_STRING(osVersion, osVersion);
    COPY_PRIMITIVE(isJailbroken, isJailbroken);
    COPY_PRIMITIVE(procTranslated, procTranslated);
    COPY_STRING(bootTime, bootTime);
    COPY_STRING(appStartTime, appStartTime);
    COPY_STRING(executablePath, executablePath);
    COPY_STRING(executableName, executableName);
    COPY_STRING(bundleID, bundleID);
    COPY_STRING(bundleName, bundleName);
    COPY_STRING(bundleVersion, bundleVersion);
    COPY_STRING(bundleShortVersion, bundleShortVersion);
    COPY_STRING(appID, appID);
    COPY_STRING(cpuArchitecture, cpuArchitecture);
    COPY_STRING(binaryArchitecture, binaryArchitecture);
    COPY_STRING(clangVersion, clangVersion);
    COPY_PRIMITIVE(cpuType, cpuType);
    COPY_PRIMITIVE(cpuSubType, cpuSubType);
    COPY_PRIMITIVE(binaryCPUType, binaryCPUType);
    COPY_PRIMITIVE(binaryCPUSubType, binaryCPUSubType);
    COPY_STRING(timezone, timezone);
    COPY_STRING(processName, processName);
    COPY_PRIMITIVE(processID, processID);
    COPY_PRIMITIVE(parentProcessID, parentProcessID);
    COPY_STRING(deviceAppHash, deviceAppHash);
    COPY_STRING(buildType, buildType);
    COPY_PRIMITIVE(storageSize, storageSize);
    COPY_PRIMITIVE(freeStorageSize, freeStorageSize);
    COPY_PRIMITIVE(memorySize, memorySize);
    dict[@"freeMemory"] = @(freeMemory());
    dict[@"usableMemory"] = @(usableMemory());

#undef COPY_STRING
#undef COPY_PRIMITIVE

    return [dict copy];
}

KSCrashMonitorAPI *kscm_system_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
        api.writeMetadataInReportSection = writeMetadataInReportSection;
    }
    return &api;
}
