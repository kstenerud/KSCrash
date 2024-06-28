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
typedef NSString *KSCrashReportField;
#define KSCRF_CONVERT_STRING(str) @str
#else /* __OBJC__ */
typedef const char *KSCrashReportField;
#define KSCRF_CONVERT_STRING(str) str
#endif /* __OBJC__ */

#ifndef NS_TYPED_ENUM
#define NS_TYPED_ENUM
#endif

#ifndef NS_SWIFT_NAME
#define NS_SWIFT_NAME(_name)
#endif

#define KSCRF_DEFINE_CONSTANT(type, name, swift_name, string) \
    static type const type##_##name NS_SWIFT_NAME(swift_name) = KSCRF_CONVERT_STRING(string);

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - Report Types -

typedef KSCrashReportField KSCrashReportType NS_TYPED_ENUM NS_SWIFT_NAME(ReportType);

KSCRF_DEFINE_CONSTANT(KSCrashReportType, Minimal, minimal, "minimal")
KSCRF_DEFINE_CONSTANT(KSCrashReportType, Standard, standard, "standard")
KSCRF_DEFINE_CONSTANT(KSCrashReportType, Custom, custom, "custom")

#pragma mark - Memory Types -

typedef KSCrashReportField KSCrashMemType NS_TYPED_ENUM NS_SWIFT_NAME(MemoryType);

KSCRF_DEFINE_CONSTANT(KSCrashMemType, Block, block, "objc_block")
KSCRF_DEFINE_CONSTANT(KSCrashMemType, Class, class, "objc_class")
KSCRF_DEFINE_CONSTANT(KSCrashMemType, NullPointer, nullPointer, "null_pointer")
KSCRF_DEFINE_CONSTANT(KSCrashMemType, Object, object, "objc_object")
KSCRF_DEFINE_CONSTANT(KSCrashMemType, String, string, "string")
KSCRF_DEFINE_CONSTANT(KSCrashMemType, Unknown, unknown, "unknown")

#pragma mark - Exception Types -

typedef KSCrashReportField KSCrashExcType NS_TYPED_ENUM NS_SWIFT_NAME(ExceptionType);

KSCRF_DEFINE_CONSTANT(KSCrashExcType, CPPException, cppException, "cpp_exception")
KSCRF_DEFINE_CONSTANT(KSCrashExcType, Deadlock, deadlock, "deadlock")
KSCRF_DEFINE_CONSTANT(KSCrashExcType, Mach, mach, "mach")
KSCRF_DEFINE_CONSTANT(KSCrashExcType, NSException, nsException, "nsexception")
KSCRF_DEFINE_CONSTANT(KSCrashExcType, Signal, signal, "signal")
KSCRF_DEFINE_CONSTANT(KSCrashExcType, User, user, "user")
KSCRF_DEFINE_CONSTANT(KSCrashExcType, MemoryTermination, memoryTermination, "memory_termination")

#pragma mark - Common -

typedef KSCrashReportField KSCrashField NS_TYPED_ENUM NS_SWIFT_NAME(CrashField);

KSCRF_DEFINE_CONSTANT(KSCrashField, Address, address, "address")
KSCRF_DEFINE_CONSTANT(KSCrashField, Contents, contents, "contents")
KSCRF_DEFINE_CONSTANT(KSCrashField, Exception, exception, "exception")
KSCRF_DEFINE_CONSTANT(KSCrashField, FirstObject, firstObject, "first_object")
KSCRF_DEFINE_CONSTANT(KSCrashField, Index, index, "index")
KSCRF_DEFINE_CONSTANT(KSCrashField, Ivars, ivars, "ivars")
KSCRF_DEFINE_CONSTANT(KSCrashField, Language, language, "language")
KSCRF_DEFINE_CONSTANT(KSCrashField, Name, name, "name")
KSCRF_DEFINE_CONSTANT(KSCrashField, UserInfo, userInfo, "userInfo")
KSCRF_DEFINE_CONSTANT(KSCrashField, ReferencedObject, referencedObject, "referenced_object")
KSCRF_DEFINE_CONSTANT(KSCrashField, Type, type, "type")
KSCRF_DEFINE_CONSTANT(KSCrashField, UUID, uuid, "uuid")
KSCRF_DEFINE_CONSTANT(KSCrashField, Value, value, "value")
KSCRF_DEFINE_CONSTANT(KSCrashField, MemoryLimit, memoryLimit, "memory_limit")
KSCRF_DEFINE_CONSTANT(KSCrashField, Error, error, "error")
KSCRF_DEFINE_CONSTANT(KSCrashField, JSONData, jsonData, "json_data")

#pragma mark - Notable Address -

KSCRF_DEFINE_CONSTANT(KSCrashField, Class, class, "class")
KSCRF_DEFINE_CONSTANT(KSCrashField, LastDeallocObject, lastDeallocObject, "last_deallocated_obj")

#pragma mark - Backtrace -

KSCRF_DEFINE_CONSTANT(KSCrashField, InstructionAddr, instructionAddr, "instruction_addr")
KSCRF_DEFINE_CONSTANT(KSCrashField, LineOfCode, lineOfCode, "line_of_code")
KSCRF_DEFINE_CONSTANT(KSCrashField, ObjectAddr, objectAddr, "object_addr")
KSCRF_DEFINE_CONSTANT(KSCrashField, ObjectName, objectName, "object_name")
KSCRF_DEFINE_CONSTANT(KSCrashField, SymbolAddr, symbolAddr, "symbol_addr")
KSCRF_DEFINE_CONSTANT(KSCrashField, SymbolName, symbolName, "symbol_name")

#pragma mark - Stack Dump -

KSCRF_DEFINE_CONSTANT(KSCrashField, DumpEnd, dumpEnd, "dump_end")
KSCRF_DEFINE_CONSTANT(KSCrashField, DumpStart, dumpStart, "dump_start")
KSCRF_DEFINE_CONSTANT(KSCrashField, GrowDirection, growDirection, "grow_direction")
KSCRF_DEFINE_CONSTANT(KSCrashField, Overflow, overflow, "overflow")
KSCRF_DEFINE_CONSTANT(KSCrashField, StackPtr, stackPtr, "stack_pointer")

#pragma mark - Thread Dump -

KSCRF_DEFINE_CONSTANT(KSCrashField, Backtrace, backtrace, "backtrace")
KSCRF_DEFINE_CONSTANT(KSCrashField, Basic, basic, "basic")
KSCRF_DEFINE_CONSTANT(KSCrashField, Crashed, crashed, "crashed")
KSCRF_DEFINE_CONSTANT(KSCrashField, CurrentThread, currentThread, "current_thread")
KSCRF_DEFINE_CONSTANT(KSCrashField, DispatchQueue, dispatchQueue, "dispatch_queue")
KSCRF_DEFINE_CONSTANT(KSCrashField, NotableAddresses, notableAddresses, "notable_addresses")
KSCRF_DEFINE_CONSTANT(KSCrashField, Registers, registers, "registers")
KSCRF_DEFINE_CONSTANT(KSCrashField, Skipped, skipped, "skipped")
KSCRF_DEFINE_CONSTANT(KSCrashField, Stack, stack, "stack")

#pragma mark - Binary Image -

KSCRF_DEFINE_CONSTANT(KSCrashField, CPUSubType, cpuSubType, "cpu_subtype")
KSCRF_DEFINE_CONSTANT(KSCrashField, CPUType, cpuType, "cpu_type")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageAddress, imageAddress, "image_addr")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageVmAddress, imageVmAddress, "image_vmaddr")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageSize, imageSize, "image_size")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageMajorVersion, imageMajorVersion, "major_version")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageMinorVersion, imageMinorVersion, "minor_version")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageRevisionVersion, imageRevisionVersion, "revision_version")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageCrashInfoMessage, imageCrashInfoMessage, "crash_info_message")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageCrashInfoMessage2, imageCrashInfoMessage2, "crash_info_message2")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageCrashInfoBacktrace, imageCrashInfoBacktrace, "crash_info_backtrace")
KSCRF_DEFINE_CONSTANT(KSCrashField, ImageCrashInfoSignature, imageCrashInfoSignature, "crash_info_signature")

#pragma mark - Memory -

KSCRF_DEFINE_CONSTANT(KSCrashField, Free, free, "free")
KSCRF_DEFINE_CONSTANT(KSCrashField, Usable, usable, "usable")

#pragma mark - Error -

KSCRF_DEFINE_CONSTANT(KSCrashField, Code, code, "code")
KSCRF_DEFINE_CONSTANT(KSCrashField, CodeName, codeName, "code_name")
KSCRF_DEFINE_CONSTANT(KSCrashField, CPPException, cppException, "cpp_exception")
KSCRF_DEFINE_CONSTANT(KSCrashField, ExceptionName, exceptionName, "exception_name")
KSCRF_DEFINE_CONSTANT(KSCrashField, Mach, mach, "mach")
KSCRF_DEFINE_CONSTANT(KSCrashField, NSException, nsException, "nsexception")
KSCRF_DEFINE_CONSTANT(KSCrashField, Reason, reason, "reason")
KSCRF_DEFINE_CONSTANT(KSCrashField, Signal, signal, "signal")
KSCRF_DEFINE_CONSTANT(KSCrashField, Subcode, subcode, "subcode")
KSCRF_DEFINE_CONSTANT(KSCrashField, UserReported, userReported, "user_reported")

#pragma mark - Process State -

KSCRF_DEFINE_CONSTANT(KSCrashField, LastDeallocedNSException, lastDeallocedNSException, "last_dealloced_nsexception")
KSCRF_DEFINE_CONSTANT(KSCrashField, ProcessState, processState, "process")

#pragma mark - App Stats -

KSCRF_DEFINE_CONSTANT(KSCrashField, ActiveTimeSinceCrash, activeTimeSinceCrash, "active_time_since_last_crash")
KSCRF_DEFINE_CONSTANT(KSCrashField, ActiveTimeSinceLaunch, activeTimeSinceLaunch, "active_time_since_launch")
KSCRF_DEFINE_CONSTANT(KSCrashField, AppActive, appActive, "application_active")
KSCRF_DEFINE_CONSTANT(KSCrashField, AppInFG, appInFG, "application_in_foreground")
KSCRF_DEFINE_CONSTANT(KSCrashField, BGTimeSinceCrash, bgTimeSinceCrash, "background_time_since_last_crash")
KSCRF_DEFINE_CONSTANT(KSCrashField, BGTimeSinceLaunch, bgTimeSinceLaunch, "background_time_since_launch")
KSCRF_DEFINE_CONSTANT(KSCrashField, LaunchesSinceCrash, launchesSinceCrash, "launches_since_last_crash")
KSCRF_DEFINE_CONSTANT(KSCrashField, SessionsSinceCrash, sessionsSinceCrash, "sessions_since_last_crash")
KSCRF_DEFINE_CONSTANT(KSCrashField, SessionsSinceLaunch, sessionsSinceLaunch, "sessions_since_launch")

#pragma mark - Report -

KSCRF_DEFINE_CONSTANT(KSCrashField, Crash, crash, "crash")
KSCRF_DEFINE_CONSTANT(KSCrashField, Debug, debug, "debug")
KSCRF_DEFINE_CONSTANT(KSCrashField, Diagnosis, diagnosis, "diagnosis")
KSCRF_DEFINE_CONSTANT(KSCrashField, ID, id, "id")
KSCRF_DEFINE_CONSTANT(KSCrashField, ProcessName, processName, "process_name")
KSCRF_DEFINE_CONSTANT(KSCrashField, Report, report, "report")
KSCRF_DEFINE_CONSTANT(KSCrashField, Timestamp, timestamp, "timestamp")
KSCRF_DEFINE_CONSTANT(KSCrashField, Version, version, "version")
KSCRF_DEFINE_CONSTANT(KSCrashField, AppMemory, appMemory, "app_memory")
KSCRF_DEFINE_CONSTANT(KSCrashField, MemoryTermination, memoryTermination, "memory_termination")

KSCRF_DEFINE_CONSTANT(KSCrashField, CrashedThread, crashedThread, "crashed_thread")
KSCRF_DEFINE_CONSTANT(KSCrashField, AppStats, appStats, "application_stats")
KSCRF_DEFINE_CONSTANT(KSCrashField, BinaryImages, binaryImages, "binary_images")
KSCRF_DEFINE_CONSTANT(KSCrashField, System, system, "system")
KSCRF_DEFINE_CONSTANT(KSCrashField, Memory, memory, "memory")
KSCRF_DEFINE_CONSTANT(KSCrashField, Threads, threads, "threads")
KSCRF_DEFINE_CONSTANT(KSCrashField, User, user, "user")
KSCRF_DEFINE_CONSTANT(KSCrashField, ConsoleLog, consoleLog, "console_log")
KSCRF_DEFINE_CONSTANT(KSCrashField, Incomplete, incomplete, "incomplete")
KSCRF_DEFINE_CONSTANT(KSCrashField, RecrashReport, recrashReport, "recrash_report")

KSCRF_DEFINE_CONSTANT(KSCrashField, AppStartTime, appStartTime, "app_start_time")
KSCRF_DEFINE_CONSTANT(KSCrashField, AppUUID, appUUID, "app_uuid")
KSCRF_DEFINE_CONSTANT(KSCrashField, BootTime, bootTime, "boot_time")
KSCRF_DEFINE_CONSTANT(KSCrashField, BundleID, bundleID, "CFBundleIdentifier")
KSCRF_DEFINE_CONSTANT(KSCrashField, BundleName, bundleName, "CFBundleName")
KSCRF_DEFINE_CONSTANT(KSCrashField, BundleShortVersion, bundleShortVersion, "CFBundleShortVersionString")
KSCRF_DEFINE_CONSTANT(KSCrashField, BundleVersion, bundleVersion, "CFBundleVersion")
KSCRF_DEFINE_CONSTANT(KSCrashField, CPUArch, cpuArch, "cpu_arch")
KSCRF_DEFINE_CONSTANT(KSCrashField, BinaryCPUType, binaryCPUType, "binary_cpu_type")
KSCRF_DEFINE_CONSTANT(KSCrashField, BinaryCPUSubType, binaryCPUSubType, "binary_cpu_subtype")
KSCRF_DEFINE_CONSTANT(KSCrashField, DeviceAppHash, deviceAppHash, "device_app_hash")
KSCRF_DEFINE_CONSTANT(KSCrashField, Executable, executable, "CFBundleExecutable")
KSCRF_DEFINE_CONSTANT(KSCrashField, ExecutablePath, executablePath, "CFBundleExecutablePath")
KSCRF_DEFINE_CONSTANT(KSCrashField, Jailbroken, jailbroken, "jailbroken")
KSCRF_DEFINE_CONSTANT(KSCrashField, KernelVersion, kernelVersion, "kernel_version")
KSCRF_DEFINE_CONSTANT(KSCrashField, Machine, machine, "machine")
KSCRF_DEFINE_CONSTANT(KSCrashField, Model, model, "model")
KSCRF_DEFINE_CONSTANT(KSCrashField, OSVersion, osVersion, "os_version")
KSCRF_DEFINE_CONSTANT(KSCrashField, ParentProcessID, parentProcessID, "parent_process_id")
KSCRF_DEFINE_CONSTANT(KSCrashField, ProcessID, processID, "process_id")
KSCRF_DEFINE_CONSTANT(KSCrashField, Size, size, "size")
KSCRF_DEFINE_CONSTANT(KSCrashField, Storage, storage, "storage")
KSCRF_DEFINE_CONSTANT(KSCrashField, SystemName, systemName, "system_name")
KSCRF_DEFINE_CONSTANT(KSCrashField, SystemVersion, systemVersion, "system_version")
KSCRF_DEFINE_CONSTANT(KSCrashField, TimeZone, timeZone, "time_zone")
KSCRF_DEFINE_CONSTANT(KSCrashField, BuildType, buildType, "build_type")

KSCRF_DEFINE_CONSTANT(KSCrashField, MemoryFootprint, memoryFootprint, "memory_footprint")
KSCRF_DEFINE_CONSTANT(KSCrashField, MemoryRemaining, memoryRemaining, "memory_remaining")
KSCRF_DEFINE_CONSTANT(KSCrashField, MemoryPressure, memoryPressure, "memory_pressure")
KSCRF_DEFINE_CONSTANT(KSCrashField, MemoryLevel, memoryLevel, "memory_level")
KSCRF_DEFINE_CONSTANT(KSCrashField, AppTransitionState, appTransitionState, "app_transition_state")

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashReportFields_h
