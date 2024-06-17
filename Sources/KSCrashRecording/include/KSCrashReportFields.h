//
//  KSCrashReportFields.h
//
//  Created by Karl Stenerud on 2012-10-07.
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


#ifndef HDR_KSCrashReportFields_h
#define HDR_KSCrashReportFields_h

#ifdef __OBJC__
#include <Foundation/Foundation.h>
typedef NSString* KSCrashReportField;
#else
typedef const char* KSCrashReportField;
#endif

#ifndef NS_TYPED_ENUM
#define NS_TYPED_ENUM
#endif

#ifndef NS_SWIFT_NAME
#define NS_SWIFT_NAME(_name)
#endif

#ifdef __OBJC__
#define CONVERT_STRING(str) @str
#else
#define CONVERT_STRING(str) str
#endif

#pragma mark - Report Types -

typedef KSCrashReportField KSCrashReportType NS_TYPED_ENUM;
static KSCrashReportType const KSCrashReportType_Minimal NS_SWIFT_NAME(minimal) = CONVERT_STRING("minimal");
static KSCrashReportType const KSCrashReportType_Standard NS_SWIFT_NAME(standard) = CONVERT_STRING("standard");
static KSCrashReportType const KSCrashReportType_Custom NS_SWIFT_NAME(custom) = CONVERT_STRING("custom");

#pragma mark - Memory Types -

typedef KSCrashReportField KSCrashMemType NS_TYPED_ENUM;
static KSCrashMemType const KSCrashMemType_Block NS_SWIFT_NAME(block) = CONVERT_STRING("objc_block");
static KSCrashMemType const KSCrashMemType_Class NS_SWIFT_NAME(class) = CONVERT_STRING("objc_class");
static KSCrashMemType const KSCrashMemType_NullPointer NS_SWIFT_NAME(nullPointer) = CONVERT_STRING("null_pointer");
static KSCrashMemType const KSCrashMemType_Object NS_SWIFT_NAME(object) = CONVERT_STRING("objc_object");
static KSCrashMemType const KSCrashMemType_String NS_SWIFT_NAME(string) = CONVERT_STRING("string");
static KSCrashMemType const KSCrashMemType_Unknown NS_SWIFT_NAME(unknown) = CONVERT_STRING("unknown");


#pragma mark - Exception Types -

typedef KSCrashReportField KSCrashExcType NS_TYPED_ENUM;
static KSCrashExcType const KSCrashExcType_CPPException NS_SWIFT_NAME(cppException) = CONVERT_STRING("cpp_exception");
static KSCrashExcType const KSCrashExcType_Deadlock NS_SWIFT_NAME(deadlock) = CONVERT_STRING("deadlock");
static KSCrashExcType const KSCrashExcType_Mach NS_SWIFT_NAME(mach) = CONVERT_STRING("mach");
static KSCrashExcType const KSCrashExcType_NSException NS_SWIFT_NAME(nsException) = CONVERT_STRING("nsexception");
static KSCrashExcType const KSCrashExcType_Signal NS_SWIFT_NAME(signal) = CONVERT_STRING("signal");
static KSCrashExcType const KSCrashExcType_User NS_SWIFT_NAME(user) = CONVERT_STRING("user");
static KSCrashExcType const KSCrashExcType_MemoryTermination NS_SWIFT_NAME(memoryTermination) = CONVERT_STRING("memory_termination");

#pragma mark - Common -

typedef KSCrashReportField KSCrashField NS_TYPED_ENUM;
static KSCrashField const KSCrashField_Address NS_SWIFT_NAME(address) = CONVERT_STRING("address");
static KSCrashField const KSCrashField_Contents NS_SWIFT_NAME(contents) = CONVERT_STRING("contents");
static KSCrashField const KSCrashField_Exception NS_SWIFT_NAME(exception) = CONVERT_STRING("exception");
static KSCrashField const KSCrashField_FirstObject NS_SWIFT_NAME(firstObject) = CONVERT_STRING("first_object");
static KSCrashField const KSCrashField_Index NS_SWIFT_NAME(index) = CONVERT_STRING("index");
static KSCrashField const KSCrashField_Ivars NS_SWIFT_NAME(ivars) = CONVERT_STRING("ivars");
static KSCrashField const KSCrashField_Language NS_SWIFT_NAME(language) = CONVERT_STRING("language");
static KSCrashField const KSCrashField_Name NS_SWIFT_NAME(name) = CONVERT_STRING("name");
static KSCrashField const KSCrashField_UserInfo NS_SWIFT_NAME(userInfo) = CONVERT_STRING("userInfo");
static KSCrashField const KSCrashField_ReferencedObject NS_SWIFT_NAME(referencedObject) = CONVERT_STRING("referenced_object");
static KSCrashField const KSCrashField_Type NS_SWIFT_NAME(type) = CONVERT_STRING("type");
static KSCrashField const KSCrashField_UUID NS_SWIFT_NAME(uuid) = CONVERT_STRING("uuid");
static KSCrashField const KSCrashField_Value NS_SWIFT_NAME(value) = CONVERT_STRING("value");
static KSCrashField const KSCrashField_MemoryLimit NS_SWIFT_NAME(memoryLimit) = CONVERT_STRING("memory_limit");
static KSCrashField const KSCrashField_Error NS_SWIFT_NAME(error) = CONVERT_STRING("error");
static KSCrashField const KSCrashField_JSONData NS_SWIFT_NAME(jsonData) = CONVERT_STRING("json_data");

#pragma mark - Notable Address -

static KSCrashField const KSCrashField_Class NS_SWIFT_NAME(class) = CONVERT_STRING("class");
static KSCrashField const KSCrashField_LastDeallocObject NS_SWIFT_NAME(lastDeallocObject) = CONVERT_STRING("last_deallocated_obj");

#pragma mark - Backtrace -

static KSCrashField const KSCrashField_InstructionAddr NS_SWIFT_NAME(instructionAddr) = CONVERT_STRING("instruction_addr");
static KSCrashField const KSCrashField_LineOfCode NS_SWIFT_NAME(lineOfCode) = CONVERT_STRING("line_of_code");
static KSCrashField const KSCrashField_ObjectAddr NS_SWIFT_NAME(objectAddr) = CONVERT_STRING("object_addr");
static KSCrashField const KSCrashField_ObjectName NS_SWIFT_NAME(objectName) = CONVERT_STRING("object_name");
static KSCrashField const KSCrashField_SymbolAddr NS_SWIFT_NAME(symbolAddr) = CONVERT_STRING("symbol_addr");
static KSCrashField const KSCrashField_SymbolName NS_SWIFT_NAME(symbolName) = CONVERT_STRING("symbol_name");

#pragma mark - Stack Dump -

static KSCrashField const KSCrashField_DumpEnd NS_SWIFT_NAME(dumpEnd) = CONVERT_STRING("dump_end");
static KSCrashField const KSCrashField_DumpStart NS_SWIFT_NAME(dumpStart) = CONVERT_STRING("dump_start");
static KSCrashField const KSCrashField_GrowDirection NS_SWIFT_NAME(growDirection) = CONVERT_STRING("grow_direction");
static KSCrashField const KSCrashField_Overflow NS_SWIFT_NAME(overflow) = CONVERT_STRING("overflow");
static KSCrashField const KSCrashField_StackPtr NS_SWIFT_NAME(stackPtr) = CONVERT_STRING("stack_pointer");

#pragma mark - Thread Dump -

static KSCrashField const KSCrashField_Backtrace NS_SWIFT_NAME(backtrace) = CONVERT_STRING("backtrace");
static KSCrashField const KSCrashField_Basic NS_SWIFT_NAME(basic) = CONVERT_STRING("basic");
static KSCrashField const KSCrashField_Crashed NS_SWIFT_NAME(crashed) = CONVERT_STRING("crashed");
static KSCrashField const KSCrashField_CurrentThread NS_SWIFT_NAME(currentThread) = CONVERT_STRING("current_thread");
static KSCrashField const KSCrashField_DispatchQueue NS_SWIFT_NAME(dispatchQueue) = CONVERT_STRING("dispatch_queue");
static KSCrashField const KSCrashField_NotableAddresses NS_SWIFT_NAME(notableAddresses) = CONVERT_STRING("notable_addresses");
static KSCrashField const KSCrashField_Registers NS_SWIFT_NAME(registers) = CONVERT_STRING("registers");
static KSCrashField const KSCrashField_Skipped NS_SWIFT_NAME(skipped) = CONVERT_STRING("skipped");
static KSCrashField const KSCrashField_Stack NS_SWIFT_NAME(stack) = CONVERT_STRING("stack");

#pragma mark - Binary Image -

static KSCrashField const KSCrashField_CPUSubType NS_SWIFT_NAME(cpuSubType) = CONVERT_STRING("cpu_subtype");
static KSCrashField const KSCrashField_CPUType NS_SWIFT_NAME(cpuType) = CONVERT_STRING("cpu_type");
static KSCrashField const KSCrashField_ImageAddress NS_SWIFT_NAME(imageAddress) = CONVERT_STRING("image_addr");
static KSCrashField const KSCrashField_ImageVmAddress NS_SWIFT_NAME(imageVmAddress) = CONVERT_STRING("image_vmaddr");
static KSCrashField const KSCrashField_ImageSize NS_SWIFT_NAME(imageSize) = CONVERT_STRING("image_size");
static KSCrashField const KSCrashField_ImageMajorVersion NS_SWIFT_NAME(imageMajorVersion) = CONVERT_STRING("major_version");
static KSCrashField const KSCrashField_ImageMinorVersion NS_SWIFT_NAME(imageMinorVersion) = CONVERT_STRING("minor_version");
static KSCrashField const KSCrashField_ImageRevisionVersion NS_SWIFT_NAME(imageRevisionVersion) = CONVERT_STRING("revision_version");
static KSCrashField const KSCrashField_ImageCrashInfoMessage NS_SWIFT_NAME(imageCrashInfoMessage) = CONVERT_STRING("crash_info_message");
static KSCrashField const KSCrashField_ImageCrashInfoMessage2 NS_SWIFT_NAME(imageCrashInfoMessage2) = CONVERT_STRING("crash_info_message2");
static KSCrashField const KSCrashField_ImageCrashInfoBacktrace NS_SWIFT_NAME(imageCrashInfoBacktrace) = CONVERT_STRING("crash_info_backtrace");
static KSCrashField const KSCrashField_ImageCrashInfoSignature NS_SWIFT_NAME(imageCrashInfoSignature) = CONVERT_STRING("crash_info_signature");

#pragma mark - Memory -

static KSCrashField const KSCrashField_Free NS_SWIFT_NAME(free) = CONVERT_STRING("free");
static KSCrashField const KSCrashField_Usable NS_SWIFT_NAME(usable) = CONVERT_STRING("usable");

#pragma mark - Error -

static KSCrashField const KSCrashField_Code NS_SWIFT_NAME(code) = CONVERT_STRING("code");
static KSCrashField const KSCrashField_CodeName NS_SWIFT_NAME(codeName) = CONVERT_STRING("code_name");
static KSCrashField const KSCrashField_CPPException NS_SWIFT_NAME(cppException) = CONVERT_STRING("cpp_exception");
static KSCrashField const KSCrashField_ExceptionName NS_SWIFT_NAME(exceptionName) = CONVERT_STRING("exception_name");
static KSCrashField const KSCrashField_Mach NS_SWIFT_NAME(mach) = CONVERT_STRING("mach");
static KSCrashField const KSCrashField_NSException NS_SWIFT_NAME(nsException) = CONVERT_STRING("nsexception");
static KSCrashField const KSCrashField_Reason NS_SWIFT_NAME(reason) = CONVERT_STRING("reason");
static KSCrashField const KSCrashField_Signal NS_SWIFT_NAME(signal) = CONVERT_STRING("signal");
static KSCrashField const KSCrashField_Subcode NS_SWIFT_NAME(subcode) = CONVERT_STRING("subcode");
static KSCrashField const KSCrashField_UserReported NS_SWIFT_NAME(userReported) = CONVERT_STRING("user_reported");

#pragma mark - Process State -

static KSCrashField const KSCrashField_LastDeallocedNSException NS_SWIFT_NAME(lastDeallocedNSException) = CONVERT_STRING("last_dealloced_nsexception");
static KSCrashField const KSCrashField_ProcessState NS_SWIFT_NAME(processState) = CONVERT_STRING("process");

#pragma mark - App Stats -

static KSCrashField const KSCrashField_ActiveTimeSinceCrash NS_SWIFT_NAME(activeTimeSinceCrash) = CONVERT_STRING("active_time_since_last_crash");
static KSCrashField const KSCrashField_ActiveTimeSinceLaunch NS_SWIFT_NAME(activeTimeSinceLaunch) = CONVERT_STRING("active_time_since_launch");
static KSCrashField const KSCrashField_AppActive NS_SWIFT_NAME(appActive) = CONVERT_STRING("application_active");
static KSCrashField const KSCrashField_AppInFG NS_SWIFT_NAME(appInFG) = CONVERT_STRING("application_in_foreground");
static KSCrashField const KSCrashField_BGTimeSinceCrash NS_SWIFT_NAME(bgTimeSinceCrash) = CONVERT_STRING("background_time_since_last_crash");
static KSCrashField const KSCrashField_BGTimeSinceLaunch NS_SWIFT_NAME(bgTimeSinceLaunch) = CONVERT_STRING("background_time_since_launch");
static KSCrashField const KSCrashField_LaunchesSinceCrash NS_SWIFT_NAME(launchesSinceCrash) = CONVERT_STRING("launches_since_last_crash");
static KSCrashField const KSCrashField_SessionsSinceCrash NS_SWIFT_NAME(sessionsSinceCrash) = CONVERT_STRING("sessions_since_last_crash");
static KSCrashField const KSCrashField_SessionsSinceLaunch NS_SWIFT_NAME(sessionsSinceLaunch) = CONVERT_STRING("sessions_since_launch");

#pragma mark - Report -

static KSCrashField const KSCrashField_Crash NS_SWIFT_NAME(crash) = CONVERT_STRING("crash");
static KSCrashField const KSCrashField_Debug NS_SWIFT_NAME(debug) = CONVERT_STRING("debug");
static KSCrashField const KSCrashField_Diagnosis NS_SWIFT_NAME(diagnosis) = CONVERT_STRING("diagnosis");
static KSCrashField const KSCrashField_ID NS_SWIFT_NAME(id) = CONVERT_STRING("id");
static KSCrashField const KSCrashField_ProcessName NS_SWIFT_NAME(processName) = CONVERT_STRING("process_name");
static KSCrashField const KSCrashField_Report NS_SWIFT_NAME(report) = CONVERT_STRING("report");
static KSCrashField const KSCrashField_Timestamp NS_SWIFT_NAME(timestamp) = CONVERT_STRING("timestamp");
static KSCrashField const KSCrashField_Version NS_SWIFT_NAME(version) = CONVERT_STRING("version");
static KSCrashField const KSCrashField_AppMemory NS_SWIFT_NAME(appMemory) = CONVERT_STRING("app_memory");
static KSCrashField const KSCrashField_MemoryTermination NS_SWIFT_NAME(memoryTermination) = CONVERT_STRING("memory_termination");

static KSCrashField const KSCrashField_CrashedThread NS_SWIFT_NAME(crashedThread) = CONVERT_STRING("crashed_thread");
static KSCrashField const KSCrashField_AppStats NS_SWIFT_NAME(appStats) = CONVERT_STRING("application_stats");
static KSCrashField const KSCrashField_BinaryImages NS_SWIFT_NAME(binaryImages) = CONVERT_STRING("binary_images");
static KSCrashField const KSCrashField_System NS_SWIFT_NAME(system) = CONVERT_STRING("system");
static KSCrashField const KSCrashField_Memory NS_SWIFT_NAME(memory) = CONVERT_STRING("memory");
static KSCrashField const KSCrashField_Threads NS_SWIFT_NAME(threads) = CONVERT_STRING("threads");
static KSCrashField const KSCrashField_User NS_SWIFT_NAME(user) = CONVERT_STRING("user");
static KSCrashField const KSCrashField_ConsoleLog NS_SWIFT_NAME(consoleLog) = CONVERT_STRING("console_log");
static KSCrashField const KSCrashField_Incomplete NS_SWIFT_NAME(incomplete) = CONVERT_STRING("incomplete");
static KSCrashField const KSCrashField_RecrashReport NS_SWIFT_NAME(recrashReport) = CONVERT_STRING("recrash_report");

static KSCrashField const KSCrashField_AppStartTime NS_SWIFT_NAME(appStartTime) = CONVERT_STRING("app_start_time");
static KSCrashField const KSCrashField_AppUUID NS_SWIFT_NAME(appUUID) = CONVERT_STRING("app_uuid");
static KSCrashField const KSCrashField_BootTime NS_SWIFT_NAME(bootTime) = CONVERT_STRING("boot_time");
static KSCrashField const KSCrashField_BundleID NS_SWIFT_NAME(bundleID) = CONVERT_STRING("CFBundleIdentifier");
static KSCrashField const KSCrashField_BundleName NS_SWIFT_NAME(bundleName) = CONVERT_STRING("CFBundleName");
static KSCrashField const KSCrashField_BundleShortVersion NS_SWIFT_NAME(bundleShortVersion) = CONVERT_STRING("CFBundleShortVersionString");
static KSCrashField const KSCrashField_BundleVersion NS_SWIFT_NAME(bundleVersion) = CONVERT_STRING("CFBundleVersion");
static KSCrashField const KSCrashField_CPUArch NS_SWIFT_NAME(cpuArch) = CONVERT_STRING("cpu_arch");
static KSCrashField const KSCrashField_BinaryCPUType NS_SWIFT_NAME(binaryCPUType) = CONVERT_STRING("binary_cpu_type");
static KSCrashField const KSCrashField_BinaryCPUSubType NS_SWIFT_NAME(binaryCPUSubType) = CONVERT_STRING("binary_cpu_subtype");
static KSCrashField const KSCrashField_DeviceAppHash NS_SWIFT_NAME(deviceAppHash) = CONVERT_STRING("device_app_hash");
static KSCrashField const KSCrashField_Executable NS_SWIFT_NAME(executable) = CONVERT_STRING("CFBundleExecutable");
static KSCrashField const KSCrashField_ExecutablePath NS_SWIFT_NAME(executablePath) = CONVERT_STRING("CFBundleExecutablePath");
static KSCrashField const KSCrashField_Jailbroken NS_SWIFT_NAME(jailbroken) = CONVERT_STRING("jailbroken");
static KSCrashField const KSCrashField_KernelVersion NS_SWIFT_NAME(kernelVersion) = CONVERT_STRING("kernel_version");
static KSCrashField const KSCrashField_Machine NS_SWIFT_NAME(machine) = CONVERT_STRING("machine");
static KSCrashField const KSCrashField_Model NS_SWIFT_NAME(model) = CONVERT_STRING("model");
static KSCrashField const KSCrashField_OSVersion NS_SWIFT_NAME(osVersion) = CONVERT_STRING("os_version");
static KSCrashField const KSCrashField_ParentProcessID NS_SWIFT_NAME(parentProcessID) = CONVERT_STRING("parent_process_id");
static KSCrashField const KSCrashField_ProcessID NS_SWIFT_NAME(processID) = CONVERT_STRING("process_id");
static KSCrashField const KSCrashField_Size NS_SWIFT_NAME(size) = CONVERT_STRING("size");
static KSCrashField const KSCrashField_Storage NS_SWIFT_NAME(storage) = CONVERT_STRING("storage");
static KSCrashField const KSCrashField_SystemName NS_SWIFT_NAME(systemName) = CONVERT_STRING("system_name");
static KSCrashField const KSCrashField_SystemVersion NS_SWIFT_NAME(systemVersion) = CONVERT_STRING("system_version");
static KSCrashField const KSCrashField_TimeZone NS_SWIFT_NAME(timeZone) = CONVERT_STRING("time_zone");
static KSCrashField const KSCrashField_BuildType NS_SWIFT_NAME(buildType) = CONVERT_STRING("build_type");

static KSCrashField const KSCrashField_MemoryFootprint NS_SWIFT_NAME(memoryFootprint) = CONVERT_STRING("memory_footprint");
static KSCrashField const KSCrashField_MemoryRemaining NS_SWIFT_NAME(memoryRemaining) = CONVERT_STRING("memory_remaining");
static KSCrashField const KSCrashField_MemoryPressure NS_SWIFT_NAME(memoryPressure) = CONVERT_STRING("memory_pressure");
static KSCrashField const KSCrashField_MemoryLevel NS_SWIFT_NAME(memoryLevel) = CONVERT_STRING("memory_level");
static KSCrashField const KSCrashField_AppTransitionState NS_SWIFT_NAME(appTransitionState) = CONVERT_STRING("app_transition_state");

#endif
