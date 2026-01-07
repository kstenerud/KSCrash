//
//  KSCrashMonitor_System.h
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

#ifndef KSCrashMonitor_System_h
#define KSCrashMonitor_System_h

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"
#include "KSCrashReportFields.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Access the Monitor API.
 */
KSCrashMonitorAPI *kscm_system_getAPI(void);

#pragma mark - Report Field Keys -

extern KSCrashReportFieldName KSCrashField_System;
extern KSCrashReportFieldName KSCrashField_SystemName;
extern KSCrashReportFieldName KSCrashField_SystemVersion;
extern KSCrashReportFieldName KSCrashField_Machine;
extern KSCrashReportFieldName KSCrashField_Model;
extern KSCrashReportFieldName KSCrashField_KernelVersion;
extern KSCrashReportFieldName KSCrashField_OSVersion;
extern KSCrashReportFieldName KSCrashField_Jailbroken;
extern KSCrashReportFieldName KSCrashField_ProcTranslated;
extern KSCrashReportFieldName KSCrashField_BootTime;
extern KSCrashReportFieldName KSCrashField_AppStartTime;
extern KSCrashReportFieldName KSCrashField_ExecutablePath;
extern KSCrashReportFieldName KSCrashField_Executable;
extern KSCrashReportFieldName KSCrashField_BundleID;
extern KSCrashReportFieldName KSCrashField_BundleName;
extern KSCrashReportFieldName KSCrashField_BundleVersion;
extern KSCrashReportFieldName KSCrashField_BundleShortVersion;
extern KSCrashReportFieldName KSCrashField_AppUUID;
extern KSCrashReportFieldName KSCrashField_CPUArch;
extern KSCrashReportFieldName KSCrashField_BinaryArch;
extern KSCrashReportFieldName KSCrashField_CPUType;
extern KSCrashReportFieldName KSCrashField_ClangVersion;
extern KSCrashReportFieldName KSCrashField_CPUSubType;
extern KSCrashReportFieldName KSCrashField_BinaryCPUType;
extern KSCrashReportFieldName KSCrashField_BinaryCPUSubType;
extern KSCrashReportFieldName KSCrashField_TimeZone;
extern KSCrashReportFieldName KSCrashField_ProcessName;
extern KSCrashReportFieldName KSCrashField_ProcessID;
extern KSCrashReportFieldName KSCrashField_ParentProcessID;
extern KSCrashReportFieldName KSCrashField_DeviceAppHash;
extern KSCrashReportFieldName KSCrashField_BuildType;
extern KSCrashReportFieldName KSCrashField_Storage;
extern KSCrashReportFieldName KSCrashField_FreeStorage;
extern KSCrashReportFieldName KSCrashField_Memory;
extern KSCrashReportFieldName KSCrashField_Size;
extern KSCrashReportFieldName KSCrashField_Usable;
extern KSCrashReportFieldName KSCrashField_Free;

#ifdef __cplusplus
}
#endif

#endif
