//
//  CrashReport.swift
//
//  Created by KSCrash on 2024.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

// MARK: - Top Level Report

/// The root structure representing a complete KSCrash report.
public final class CrashReport: Codable, Sendable {
    /// List of binary images loaded in the process at crash time.
    public let binaryImages: [BinaryImage]?

    /// Information about the crash itself.
    public let crash: Crash

    /// Debug information (console logs, etc.).
    public let debug: DebugInfo?

    /// Process-specific information (zombie exceptions, etc.).
    public let process: ProcessState?

    /// Metadata about this report.
    public let report: ReportInfo

    /// If a crash occurred while writing the crash report, the original report is embedded here.
    public let recrashReport: CrashReport?

    /// System information at the time of crash.
    public let system: SystemInfo

    /// User-defined custom data attached to the crash report.
    public let user: [String: AnyCodable]?

    /// Whether this report is incomplete (crash during crash handling).
    public let incomplete: Bool?

    enum CodingKeys: String, CodingKey {
        case binaryImages = "binary_images"
        case crash
        case debug
        case process
        case report
        case recrashReport = "recrash_report"
        case system
        case user
        case incomplete
    }
}

// MARK: - Binary Image

/// Information about a loaded binary image (executable, framework, or dylib).
public struct BinaryImage: Codable, Sendable {
    /// CPU subtype of the binary.
    public let cpuSubtype: Int

    /// CPU type of the binary.
    public let cpuType: Int

    /// Load address of the image in memory.
    public let imageAddr: UInt64

    /// Virtual memory address of the image.
    public let imageVmAddr: UInt64?

    /// Size of the image in bytes.
    public let imageSize: UInt64

    /// Path to the binary image.
    public let name: String

    /// UUID of the binary image for symbolication.
    public let uuid: String?

    /// Major version of the image.
    public let majorVersion: UInt64?

    /// Minor version of the image.
    public let minorVersion: UInt64?

    /// Revision version of the image.
    public let revisionVersion: UInt64?

    /// Crash info message from __crash_info section.
    public let crashInfoMessage: String?

    /// Secondary crash info message.
    public let crashInfoMessage2: String?

    /// Crash info backtrace.
    public let crashInfoBacktrace: String?

    /// Crash info signature.
    public let crashInfoSignature: String?

    enum CodingKeys: String, CodingKey {
        case cpuSubtype = "cpu_subtype"
        case cpuType = "cpu_type"
        case imageAddr = "image_addr"
        case imageVmAddr = "image_vmaddr"
        case imageSize = "image_size"
        case name
        case uuid
        case majorVersion = "major_version"
        case minorVersion = "minor_version"
        case revisionVersion = "revision_version"
        case crashInfoMessage = "crash_info_message"
        case crashInfoMessage2 = "crash_info_message2"
        case crashInfoBacktrace = "crash_info_backtrace"
        case crashInfoSignature = "crash_info_signature"
    }
}

// MARK: - Crash Information

/// Information about the crash event.
public struct Crash: Codable, Sendable {
    /// Human-readable diagnosis of the crash.
    public let diagnosis: String?

    /// Details about the error that caused the crash.
    public let error: CrashError

    /// All threads at the time of crash.
    public let threads: [Thread]?

    /// The crashed thread (in minimal reports).
    public let crashedThread: Thread?

    enum CodingKeys: String, CodingKey {
        case diagnosis
        case error
        case threads
        case crashedThread = "crashed_thread"
    }
}

/// The error that caused the crash.
public struct CrashError: Codable, Sendable {
    /// Memory address involved in the crash (if applicable).
    public let address: UInt64?

    /// Mach exception information.
    public let mach: MachError?

    /// NSException information (for Objective-C/Swift exceptions).
    public let nsexception: NSExceptionInfo?

    /// Unix signal information.
    public let signal: SignalError?

    /// The type of error (e.g., "mach", "signal", "nsexception", "cpp_exception", "deadlock", "user", "memory_termination").
    public let type: String

    /// C++ exception information.
    public let cppException: CppExceptionInfo?

    /// User-reported crash information.
    public let userReported: UserReportedInfo?

    /// Memory termination information (OOM kills).
    public let memoryTermination: MemoryTerminationInfo?

    /// Reason for the crash (often from abort message or exception reason).
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case address
        case mach
        case nsexception
        case signal
        case type
        case cppException = "cpp_exception"
        case userReported = "user_reported"
        case memoryTermination = "memory_termination"
        case reason
    }
}

/// Mach exception details.
public struct MachError: Codable, Sendable {
    /// Mach exception code.
    public let code: UInt64

    /// Human-readable name for the code.
    public let codeName: String?

    /// Mach exception type.
    public let exception: UInt64

    /// Human-readable name for the exception.
    public let exceptionName: String?

    /// Mach exception subcode.
    public let subcode: UInt64?

    enum CodingKeys: String, CodingKey {
        case code
        case codeName = "code_name"
        case exception
        case exceptionName = "exception_name"
        case subcode
    }
}

/// Unix signal details.
public struct SignalError: Codable, Sendable {
    /// Signal code providing additional context.
    public let code: UInt64

    /// Human-readable name for the signal code.
    public let codeName: String?

    /// Signal name (e.g., "SIGSEGV", "SIGABRT").
    public let name: String?

    /// Signal number.
    public let signal: UInt64

    enum CodingKeys: String, CodingKey {
        case code
        case codeName = "code_name"
        case name
        case signal
    }
}

/// NSException details (Objective-C/Swift exceptions).
public struct NSExceptionInfo: Codable, Sendable {
    /// Exception name (e.g., "NSInvalidArgumentException").
    public let name: String

    /// Exception reason string (note: reason is often at the error level, not here).
    public let reason: String?

    /// User info dictionary from the exception.
    public let userInfo: String?

    /// Referenced object that was involved in the exception.
    public let referencedObject: ReferencedObject?

    enum CodingKeys: String, CodingKey {
        case name
        case reason
        case userInfo
        case referencedObject = "referenced_object"
    }
}

/// Object referenced in an exception.
public final class ReferencedObject: Codable, Sendable {
    /// Memory address of the object.
    public let address: UInt64?

    /// Class name of the object.
    public let `class`: String?

    /// Type description of the object.
    public let type: String?

    /// String value if the object is a string.
    public let value: String?

    /// First object in a collection (for arrays/sets).
    public let firstObject: ReferencedObject?

    /// Class name of the last deallocated object at this address (for zombie detection).
    public let lastDeallocatedObj: String?

    /// Instance variables of the object.
    public let ivars: [String: ReferencedObject]?

    enum CodingKeys: String, CodingKey {
        case address
        case `class`
        case type
        case value
        case firstObject = "first_object"
        case lastDeallocatedObj = "last_deallocated_obj"
        case ivars
    }
}

/// C++ exception details.
public struct CppExceptionInfo: Codable, Sendable {
    /// The C++ exception name (type).
    public let name: String?
}

/// User-reported crash details.
public struct UserReportedInfo: Codable, Sendable {
    /// Name/title of the user-reported crash.
    public let name: String?

    /// Programming language of the exception.
    public let language: String?

    /// Line of code where the crash was reported.
    public let lineOfCode: String?

    /// Custom backtrace provided by the user.
    public let backtrace: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case name
        case language
        case lineOfCode = "line_of_code"
        case backtrace
    }
}

/// Memory termination details (OOM kills).
public struct MemoryTerminationInfo: Codable, Sendable {
    /// Memory pressure level at termination.
    public let memoryPressure: String?

    /// App memory level at termination.
    public let memoryLevel: String?

    enum CodingKeys: String, CodingKey {
        case memoryPressure = "memory_pressure"
        case memoryLevel = "memory_level"
    }
}

// MARK: - Thread Information

/// Information about a thread at the time of crash.
public struct Thread: Codable, Sendable {
    /// Stack backtrace for this thread.
    public let backtrace: Backtrace?

    /// Whether this thread crashed.
    public let crashed: Bool

    /// Whether this is the current thread being executed.
    public let currentThread: Bool

    /// Dispatch queue this thread was executing on (if any).
    public let dispatchQueue: String?

    /// Thread index.
    public let index: Int

    /// Thread name (if set).
    public let name: String?

    /// Notable memory addresses and their contents.
    public let notableAddresses: [String: NotableAddress]?

    /// CPU register values.
    public let registers: Registers?

    /// Stack memory dump.
    public let stack: StackDump?

    /// Thread state (e.g., "TH_STATE_RUNNING", "TH_STATE_WAITING").
    public let state: String?

    enum CodingKeys: String, CodingKey {
        case backtrace
        case crashed
        case currentThread = "current_thread"
        case dispatchQueue = "dispatch_queue"
        case index
        case name
        case notableAddresses = "notable_addresses"
        case registers
        case stack
        case state
    }
}

/// Stack backtrace information.
public struct Backtrace: Codable, Sendable {
    /// Stack frames in the backtrace.
    public let contents: [StackFrame]

    /// Number of frames that were skipped.
    public let skipped: Int
}

/// A single frame in a stack trace.
public struct StackFrame: Codable, Sendable {
    /// Instruction pointer address.
    public let instructionAddr: UInt64

    /// Base address of the containing binary image.
    public let objectAddr: UInt64?

    /// Name of the containing binary image.
    public let objectName: String?

    /// Address of the symbol.
    public let symbolAddr: UInt64?

    /// Name of the symbol (function/method name).
    public let symbolName: String?

    enum CodingKeys: String, CodingKey {
        case instructionAddr = "instruction_addr"
        case objectAddr = "object_addr"
        case objectName = "object_name"
        case symbolAddr = "symbol_addr"
        case symbolName = "symbol_name"
    }
}

/// CPU register values.
public struct Registers: Codable, Sendable {
    /// Basic CPU registers (general purpose, etc.).
    public let basic: [String: UInt64]?

    /// Exception-related registers.
    public let exception: ExceptionRegisters?
}

/// Exception-related register values.
public struct ExceptionRegisters: Codable, Sendable {
    /// Exception type.
    public let exception: UInt64?

    /// Fault address register.
    public let far: UInt64?

    /// Fault status register.
    public let fsr: UInt64?
}

/// Notable address information (for debugging object references).
public final class NotableAddress: Codable, Sendable {
    /// Memory address.
    public let address: UInt64?

    /// Class name of the object at this address.
    public let `class`: String?

    /// Type of the value (e.g., "objc_object", "objc_class", "objc_block", "string", "null_pointer", "unknown").
    public let type: String?

    /// String value if this is a string.
    public let value: String?

    /// Instance variables of the object.
    public let ivars: [String: NotableAddress]?

    /// First object in a collection.
    public let firstObject: NotableAddress?

    /// Class name of the last deallocated object at this address.
    public let lastDeallocatedObj: String?

    /// Tagged pointer payload (for tagged pointers).
    public let taggedPayload: Int64?

    enum CodingKeys: String, CodingKey {
        case address
        case `class`
        case type
        case value
        case ivars
        case firstObject = "first_object"
        case lastDeallocatedObj = "last_deallocated_obj"
        case taggedPayload = "tagged_payload"
    }
}

/// Raw stack memory dump.
public struct StackDump: Codable, Sendable {
    /// Hexadecimal string of stack contents.
    public let contents: String?

    /// End address of the dump.
    public let dumpEnd: UInt64?

    /// Start address of the dump.
    public let dumpStart: UInt64?

    /// Stack growth direction ("-" for downward, "+" for upward).
    public let growDirection: String?

    /// Whether stack overflow was detected.
    public let overflow: Bool?

    /// Current stack pointer value.
    public let stackPointer: UInt64?

    /// Error message if stack contents couldn't be read.
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case contents
        case dumpEnd = "dump_end"
        case dumpStart = "dump_start"
        case growDirection = "grow_direction"
        case overflow
        case stackPointer = "stack_pointer"
        case error
    }
}

// MARK: - Process State

/// Process state information including zombie exception data.
public struct ProcessState: Codable, Sendable {
    /// Information about the last deallocated NSException (for zombie detection).
    public let lastDeallocedNSException: LastDeallocedNSException?

    enum CodingKeys: String, CodingKey {
        case lastDeallocedNSException = "last_dealloced_nsexception"
    }
}

/// Information about a deallocated NSException (zombie).
public struct LastDeallocedNSException: Codable, Sendable {
    /// Memory address of the exception.
    public let address: UInt64?

    /// Exception name.
    public let name: String?

    /// Exception reason.
    public let reason: String?

    /// Object referenced in the exception reason.
    public let referencedObject: ReferencedObject?

    enum CodingKeys: String, CodingKey {
        case address
        case name
        case reason
        case referencedObject = "referenced_object"
    }
}

// MARK: - Debug Information

/// Debug information included in crash reports.
public struct DebugInfo: Codable, Sendable {
    /// Console log lines captured before the crash.
    public let consoleLog: [String]?

    enum CodingKeys: String, CodingKey {
        case consoleLog = "console_log"
    }
}

// MARK: - Report Metadata

/// Metadata about the crash report itself.
public struct ReportInfo: Codable, Sendable {
    /// Unique identifier for this report.
    public let id: String

    /// Name of the process that crashed.
    public let processName: String?

    /// Timestamp when the crash occurred.
    /// Can be either a string (ISO 8601) or an integer (microseconds since epoch).
    public let timestamp: AnyCodable?

    /// Type of report (e.g., "standard", "minimal", "custom").
    public let type: String?

    /// Report format version.
    public let version: ReportVersion?

    enum CodingKeys: String, CodingKey {
        case id
        case processName = "process_name"
        case timestamp
        case type
        case version
    }
}

/// Report format version information.
public struct ReportVersion: Codable, Sendable {
    /// Major version number.
    public let major: Int

    /// Minor version number.
    public let minor: Int
}

// MARK: - System Information

/// System information at the time of crash.
public struct SystemInfo: Codable, Sendable {
    /// Bundle executable name.
    public let cfBundleExecutable: String?

    /// Full path to the bundle executable.
    public let cfBundleExecutablePath: String?

    /// Bundle identifier.
    public let cfBundleIdentifier: String?

    /// Bundle display name.
    public let cfBundleName: String?

    /// Short version string (marketing version).
    public let cfBundleShortVersionString: String?

    /// Bundle version (build number).
    public let cfBundleVersion: String?

    /// Timestamp when the app was started.
    public let appStartTime: String?

    /// UUID of the app binary.
    public let appUUID: String?

    /// Application usage statistics.
    public let applicationStats: ApplicationStats?

    /// System boot time.
    public let bootTime: String?

    /// CPU architecture string (e.g., "arm64", "x86_64").
    public let cpuArch: String?

    /// CPU type code.
    public let cpuType: Int?

    /// CPU subtype code.
    public let cpuSubtype: Int?

    /// Binary CPU architecture (may differ from runtime on Rosetta).
    public let binaryArch: String?

    /// Binary CPU type.
    public let binaryCPUType: Int?

    /// Binary CPU subtype.
    public let binaryCPUSubtype: Int?

    /// Hash identifying the device and app combination.
    public let deviceAppHash: String?

    /// Whether the device is jailbroken.
    public let jailbroken: Bool?

    /// Whether the process is running under Rosetta translation.
    public let procTranslated: Bool?

    /// Darwin kernel version string.
    public let kernelVersion: String?

    /// Machine identifier (e.g., "iPhone14,2").
    public let machine: String?

    /// Memory information.
    public let memory: MemoryInfo?

    /// Model identifier.
    public let model: String?

    /// OS build version.
    public let osVersion: String?

    /// Parent process ID.
    public let parentProcessID: Int?

    /// Parent process name.
    public let parentProcessName: String?

    /// Process ID.
    public let processID: Int?

    /// Process name.
    public let processName: String?

    /// System name (e.g., "iOS", "macOS").
    public let systemName: String?

    /// System version (e.g., "17.0").
    public let systemVersion: String?

    /// Timezone identifier.
    public let timeZone: String?

    /// Total storage in bytes.
    public let storage: Int64?

    /// Free storage in bytes.
    public let freeStorage: Int64?

    /// Build type (e.g., "debug", "release").
    public let buildType: String?

    /// Clang version used to compile the app.
    public let clangVersion: String?

    /// App memory information.
    public let appMemory: AppMemoryInfo?

    enum CodingKeys: String, CodingKey {
        case cfBundleExecutable = "CFBundleExecutable"
        case cfBundleExecutablePath = "CFBundleExecutablePath"
        case cfBundleIdentifier = "CFBundleIdentifier"
        case cfBundleName = "CFBundleName"
        case cfBundleShortVersionString = "CFBundleShortVersionString"
        case cfBundleVersion = "CFBundleVersion"
        case appStartTime = "app_start_time"
        case appUUID = "app_uuid"
        case applicationStats = "application_stats"
        case bootTime = "boot_time"
        case cpuArch = "cpu_arch"
        case cpuType = "cpu_type"
        case cpuSubtype = "cpu_subtype"
        case binaryArch = "binary_arch"
        case binaryCPUType = "binary_cpu_type"
        case binaryCPUSubtype = "binary_cpu_subtype"
        case deviceAppHash = "device_app_hash"
        case jailbroken
        case procTranslated = "proc_translated"
        case kernelVersion = "kernel_version"
        case machine
        case memory
        case model
        case osVersion = "os_version"
        case parentProcessID = "parent_process_id"
        case parentProcessName = "parent_process_name"
        case processID = "process_id"
        case processName = "process_name"
        case systemName = "system_name"
        case systemVersion = "system_version"
        case timeZone = "time_zone"
        case storage
        case freeStorage
        case buildType = "build_type"
        case clangVersion = "clang_version"
        case appMemory = "app_memory"
    }
}

/// Application usage statistics.
public struct ApplicationStats: Codable, Sendable {
    /// Time the app was active since the last crash.
    public let activeTimeSinceLastCrash: Double?

    /// Time the app was active since launch.
    public let activeTimeSinceLaunch: Double?

    /// Whether the app is currently active.
    public let applicationActive: Bool?

    /// Whether the app is in the foreground.
    public let applicationInForeground: Bool?

    /// Time the app was in the background since the last crash.
    public let backgroundTimeSinceLastCrash: Double?

    /// Time the app was in the background since launch.
    public let backgroundTimeSinceLaunch: Double?

    /// Number of times the app was launched since the last crash.
    public let launchesSinceLastCrash: Int?

    /// Number of sessions since the last crash.
    public let sessionsSinceLastCrash: Int?

    /// Number of sessions since launch.
    public let sessionsSinceLaunch: Int?

    enum CodingKeys: String, CodingKey {
        case activeTimeSinceLastCrash = "active_time_since_last_crash"
        case activeTimeSinceLaunch = "active_time_since_launch"
        case applicationActive = "application_active"
        case applicationInForeground = "application_in_foreground"
        case backgroundTimeSinceLastCrash = "background_time_since_last_crash"
        case backgroundTimeSinceLaunch = "background_time_since_launch"
        case launchesSinceLastCrash = "launches_since_last_crash"
        case sessionsSinceLastCrash = "sessions_since_last_crash"
        case sessionsSinceLaunch = "sessions_since_launch"
    }
}

/// System memory information.
public struct MemoryInfo: Codable, Sendable {
    /// Free memory in bytes.
    public let free: UInt64?

    /// Total memory size in bytes.
    public let size: UInt64?

    /// Usable memory in bytes.
    public let usable: UInt64?
}

/// App memory information at crash time.
public struct AppMemoryInfo: Codable, Sendable {
    /// Memory footprint of the app in bytes.
    public let memoryFootprint: UInt64?

    /// Memory remaining before limit in bytes.
    public let memoryRemaining: UInt64?

    /// System memory pressure level.
    public let memoryPressure: String?

    /// App memory level.
    public let memoryLevel: String?

    /// Memory limit for the app in bytes.
    public let memoryLimit: UInt64?

    /// App transition state at crash time.
    public let appTransitionState: String?

    enum CodingKeys: String, CodingKey {
        case memoryFootprint = "memory_footprint"
        case memoryRemaining = "memory_remaining"
        case memoryPressure = "memory_pressure"
        case memoryLevel = "memory_level"
        case memoryLimit = "memory_limit"
        case appTransitionState = "app_transition_state"
    }
}
