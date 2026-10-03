//
//  KSCrashMonitor_ResourceStitch.m
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
#import "KSCrashCPUTracker.h"
#import "KSCrashReportFields.h"
#import "KSCrashStitch.h"

#import <Foundation/Foundation.h>

CFDictionaryRef kscm_resource_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   KSCrashSidecarScope scope, __unused void *context)
{
    __block KSCrash_ResourceData data = {};
    NSDictionary *stitched = ksstitch_stitchedReport(
        (__bridge NSDictionary *)reportDict, sidecarPath, scope, KSCrashSidecarScopeRun,
        ^(const char *path) {
            return kssidecar_readResource(path, &data);
        },
        ^(NSMutableDictionary *report) {
            NSMutableDictionary *system = ksstitch_object(report, KSCrashField_System);

            // app_memory: the same format as KSCrashMonitor_Memory serialization,
            // minus timestamp and transition state (those belong to Memory/Lifecycle).
            NSMutableDictionary *appMemory = ksstitch_object(system, KSCrashField_AppMemory);
            appMemory[KSCrashField_MemoryFootprint] = @(data.memoryFootprint);
            appMemory[KSCrashField_MemoryRemaining] = @(data.memoryRemaining);
            appMemory[KSCrashField_MemoryLimit] = @(data.memoryLimit);
            appMemory[KSCrashField_MemoryPressure] =
                @(KSCrashAppMemoryStateToString((KSCrashAppMemoryState)data.memoryPressure));
            appMemory[KSCrashField_MemoryLevel] =
                @(KSCrashAppMemoryStateToString((KSCrashAppMemoryState)data.memoryLevel));
            // Omitted when no system-wide data was recorded (v1 sidecar, or stats unavailable).
            if (data.systemMemoryLimit > 0) {
                appMemory[KSCrashField_MemoryHeadroom] =
                    @(KSCrashAppMemoryStateToString((KSCrashAppMemoryState)data.memoryHeadroom));
                appMemory[KSCrashField_SystemMemoryRemaining] = @(data.systemMemoryRemaining);
                appMemory[KSCrashField_SystemMemoryLimit] = @(data.systemMemoryLimit);
            }

            if (data.batteryLevel != 255) {
                system[KSCrashField_BatteryLevel] = @(data.batteryLevel);
            }
            system[KSCrashField_BatteryState] = @(data.batteryState);
            system[KSCrashField_LowPowerModeEnabled] = @((BOOL)data.lowPowerMode);
            system[KSCrashField_CPUCoreCount] = @(data.cpuCoreCount);
            system[KSCrashField_CPUUsageUser] = @(data.cpuUsageUser);
            system[KSCrashField_CPUUsageSystem] = @(data.cpuUsageSystem);
            system[KSCrashField_CPUState] = @(KSCrashCPUStateToString((KSCrashCPUState)data.cpuState));
            system[KSCrashField_CPUAverageUsagePermil] = @(data.cpuAverageUsagePermil);
            if (data.cpuWallTimeInWindowNs > 0) {
                system[KSCrashField_CPUTimeInWindow] = @((double)data.cpuTimeInWindowNs / 1e9);
                system[KSCrashField_CPUWallTimeInWindow] = @((double)data.cpuWallTimeInWindowNs / 1e9);
            }
            system[KSCrashField_ThermalState] = @(data.thermalState);
            system[KSCrashField_ThreadCount] = @(data.threadCount);
            system[KSCrashField_DataProtectionActive] = @((BOOL)data.dataProtectionActive);
        });
    return (__bridge_retained CFDictionaryRef)stitched;
}
