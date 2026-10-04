//
//  KSCrashMonitor_SystemStitch.m
//
//  Created by Alexander Cohen on 2026-02-20.
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

#import "KSCrashReportFields.h"
#import "KSCrashStitch.h"
#import "KSDate.h"

#import <Foundation/Foundation.h>

/** Sets `key` to the string in a fixed-size field of `capacity` bytes, reading
 *  no further than the field even when another writer left it without a NUL.
 *  An empty field leaves the key as it is; bytes that are not UTF-8 clear the
 *  key, as an unreadable value always has. */
static void setStringIfNonEmpty(NSMutableDictionary *dict, NSString *key, const char *value, size_t capacity)
{
    size_t length = value != NULL ? strnlen(value, capacity) : 0;
    if (length > 0) {
        dict[key] = [[NSString alloc] initWithBytes:value length:length encoding:NSUTF8StringEncoding];
    }
}

/** setStringIfNonEmpty with the field's own size as the bound. The field must be
 *  an array: a pointer's size would cap the read at the pointer's width. */
#define SET_STRING(dict, key, field)                                                              \
    do {                                                                                          \
        _Static_assert(!__builtin_types_compatible_p(__typeof__(field), __typeof__(&(field)[0])), \
                       "SET_STRING needs a char array, not a pointer");                           \
        setStringIfNonEmpty(dict, key, field, sizeof(field));                                     \
    } while (0)

static void setTimestamp(NSMutableDictionary *dict, NSString *key, int64_t timestamp)
{
    if (timestamp != 0) {
        char buf[KSDATE_BUFFERSIZE];
        ksdate_utcStringFromTimestamp((time_t)timestamp, buf, sizeof(buf));
        SET_STRING(dict, key, buf);
    }
}

CFDictionaryRef kscm_system_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                 KSCrashSidecarScope scope, __unused void *context)
{
    __block KSCrash_SystemData sc = {};
    NSDictionary *stitched = ksstitch_stitchedReport(
        (__bridge NSDictionary *)reportDict, sidecarPath, scope, KSCrashSidecarScopeRun,
        ^(const char *path) {
            return kssidecar_readSystem(path, &sc);
        },
        ^(NSMutableDictionary *report) {
            NSMutableDictionary *system = ksstitch_object(report, KSCrashField_System);
            SET_STRING(system, KSCrashField_SystemName, sc.systemName);
            SET_STRING(system, KSCrashField_SystemVersion, sc.systemVersion);
            SET_STRING(system, KSCrashField_Machine, sc.machine);
            SET_STRING(system, KSCrashField_Model, sc.model);
            SET_STRING(system, KSCrashField_KernelVersion, sc.kernelVersion);
            SET_STRING(system, KSCrashField_OSVersion, sc.osVersion);
            system[KSCrashField_Jailbroken] = sc.isJailbroken ? @YES : @NO;
            system[KSCrashField_ProcTranslated] = sc.procTranslated ? @YES : @NO;
            // Only emit for sidecars that actually recorded it (version >= 2). For an
            // older sidecar the field is zero-filled, and emitting `false` would read as
            // "definitely not debugged" rather than "unknown".
            if (sc.header.version >= 2) {
                system[KSCrashField_IsBeingDebugged] = sc.isBeingDebugged ? @YES : @NO;
            }
            setTimestamp(system, KSCrashField_AppStartTime, sc.appStartTimestamp);
            system[KSCrashField_ProcessStartWallClockNs] = @(sc.processStartWallClockNs);
            system[KSCrashField_ProcessStartMonotonicNs] = @(sc.processStartMonotonicNs);
            SET_STRING(system, KSCrashField_ExecutablePath, sc.executablePath);
            SET_STRING(system, KSCrashField_Executable, sc.executableName);
            SET_STRING(system, KSCrashField_BundleID, sc.bundleID);
            SET_STRING(system, KSCrashField_BundleName, sc.bundleName);
            SET_STRING(system, KSCrashField_BundleVersion, sc.bundleVersion);
            SET_STRING(system, KSCrashField_BundleShortVersion, sc.bundleShortVersion);
            SET_STRING(system, KSCrashField_AppUUID, sc.appID);
            SET_STRING(system, KSCrashField_CPUArch, sc.cpuArchitecture);
            SET_STRING(system, KSCrashField_BinaryArch, sc.binaryArchitecture);
            SET_STRING(system, KSCrashField_ClangVersion, sc.clangVersion);
            system[KSCrashField_CPUType] = @(sc.cpuType);
            system[KSCrashField_CPUSubType] = @(sc.cpuSubType);
            system[KSCrashField_BinaryCPUType] = @(sc.binaryCPUType);
            system[KSCrashField_BinaryCPUSubType] = @(sc.binaryCPUSubType);
            SET_STRING(system, KSCrashField_TimeZone, sc.timezone);
            SET_STRING(system, KSCrashField_ProcessName, sc.processName);
            system[KSCrashField_ProcessID] = @(sc.processID);
            system[KSCrashField_ParentProcessID] = @(sc.parentProcessID);
            SET_STRING(system, KSCrashField_DeviceAppHash, sc.deviceAppHash);
            SET_STRING(system, KSCrashField_BuildType, sc.buildType);
            setTimestamp(system, KSCrashField_BootTime, sc.bootTimestamp);
            if (sc.storageSize > 0) {
                system[KSCrashField_Storage] = @(sc.storageSize);
            }
            if (sc.freeStorageSize > 0) {
                system[KSCrashField_FreeStorage] = @(sc.freeStorageSize);
            }

            NSMutableDictionary *memory = ksstitch_object(system, KSCrashField_Memory);
            memory[KSCrashField_Size] = @(sc.memorySize);
            memory[KSCrashField_Free] = @(sc.freeMemory);
            memory[KSCrashField_Usable] = @(sc.usableMemory);

            // The process name also goes into an existing report section.
            if ([report[KSCrashField_Report] isKindOfClass:[NSDictionary class]]) {
                SET_STRING(ksstitch_object(report, KSCrashField_Report), KSCrashField_ProcessName, sc.processName);
            }
        });
    return (__bridge_retained CFDictionaryRef)stitched;
}
