//
//  CorpseSnapshot.swift
//
//  Created by Alexander Cohen on 2026-06-28.
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

import Foundation
import KSCrashReportModel

/// Everything the extension monitor gathers from a crashed process: the crash facts and process
/// record decoded from the corpse kcdata, plus the few task figures kcdata does not carry, read
/// off the corpse port. The image list is handed to us by CrashedProcess.
///
/// kcdata is the preferred source; the corpse port is only consulted for data kcdata lacks, and
/// no field is stored from two sources. Classified crash facts (signal, mach exception, resource,
/// exit reason) are typed via the report model; everything else is the raw kernel value. It is
/// intentionally Codable so it can be dumped to JSON for inspection during bring-up.
/// Fields are `var` with nil defaults purely for the synthesized memberwise init (17 hand-written
/// assignments invite silent transposition); a snapshot is never mutated after gathering.
struct CorpseSnapshot: Codable {
    /// The original Mach exception type from `CrashReason.exception` (reliable, unlike its `codes`).
    var exception: MachExceptionType?

    /// Decoded from the corpse's kcdata crash-info blob (the authoritative crash record).
    var crashInfo: CrashInfo?

    /// TASK_CRASHINFO_RUSAGE_INFO: the kernel's final resource accounting for the process.
    var rusage: Rusage?

    /// The TASK_CRASHINFO_LEDGER_* family: per-ledger memory figures, in bytes.
    var ledgers: Ledgers?

    /// TASK_CRASHINFO_KERNEL_TRIAGE_INFO_V1: the kernel's own notes on why the process died.
    var kernelTriage: [String]?

    /// Code-signing identity and status of the crashed process.
    var codeSigning: CodeSigning?

    /// BSD process facts (identity, flags, times) decoded from kcdata.
    var process: ProcessInfo?

    /// TASK_CRASHINFO_WORKQUEUEINFO: workqueue thread counts at death.
    var workqueue: Workqueue?

    /// task_info(TASK_VM_INFO): memory figures kcdata does not carry.
    var vmInfo: VMInfo?
    /// task_info(TASK_BASIC_INFO_64): suspend count and policy.
    var basicInfo: BasicInfo?
    /// task_info(TASK_EVENTS_INFO): faults, syscalls, context switches.
    var events: Events?
    /// task_info(TASK_POWER_INFO): the timer-wakeup bins kcdata does not carry.
    var power: Power?
    /// task_policy_get(TASK_CATEGORY_POLICY): the Mach task role (e.g. `.foregroundApplication`).
    var taskRole: TaskRole?

    /// The crashed process's binary images, as handed to us in the CrashedProcess struct.
    var images: [Image]

    /// Crash facts decoded from the kcdata crash-info blob. Classified pieces (signal, mach exception,
    /// resource, exit-reason namespace) are typed enums from the report model; the rest are the raw
    /// kernel values.
    struct CrashInfo: Codable {
        var exceptionCode: UInt64
        var exceptionSubcode: UInt64
        var signal: Signal?
        var machException: MachExceptionType?
        var subcode: UInt32?
        var faultAddress: UInt64?
        var resource: Resource?
        var exitReason: ExitReason?
        var exitReasonDescription: String?
        var processName: String?
        var pid: UInt32?
        var processPath: String?
        var crashedThreadID: UInt64?
        var cpuType: Int32?
        /// TASK_CRASHINFO_EXCEPTION_TYPE: the kernel's own record of the Mach exception type,
        /// alongside the snapshot's `exception` from CrashedProcess.reason.
        var exceptionType: Int32?
        var memoryLimitMB: UInt64?
        var memoryLimitIncreaseMB: UInt32?

        /// An EXC_RESOURCE bitfield: which resource was exceeded and how.
        struct Resource: Codable {
            let type: ResourceType
            let flavor: ResourceFlavor
            let limitMB: UInt64?
        }

        /// An `os_reason` exit reason (jetsam, watchdog/SpringBoard, ...) and its companion items.
        struct ExitReason: Codable {
            var namespace: ExitReasonNamespace
            var code: ExitReasonCode
            var flags: UInt64?
            var workloopID: UInt64?
            var dispatchQueueNo: UInt64?
            var userPayload: Data?
            var codeSigningInfo: CodeSigningInfo?

            /// EXIT_REASON_CODESIGNING_INFO: where and why code signing killed the process.
            struct CodeSigningInfo: Codable {
                let virtualAddress: UInt64
                let fileOffset: UInt64
                let pathname: String?
                let filename: String?
                let codesigModtimeSecs: UInt64
                let codesigModtimeNsecs: UInt64
                let pageModtimeSecs: UInt64
                let pageModtimeNsecs: UInt64
                let pathTruncated: Bool
                let objectCodesigned: Bool
                let pageCodesigValidated: Bool
                let pageCodesigTainted: Bool
                let pageCodesigNx: Bool
                let pageWpmapped: Bool
                let pageSlid: Bool
                let pageDirty: Bool
                let pageShadowDepth: UInt32
            }
        }
    }

    /// `struct rusage_info` decoded as a versioned prefix: fields fill in declaration order while
    /// item bytes remain, so older kernels (shorter versions) leave the tail nil and newer ones
    /// (unknown appended fields) lose nothing that our layout knows. Raw kernel units throughout:
    /// times are mach ticks, sizes bytes, energy nanojoules.
    struct Rusage: Codable {
        var uuid: String?
        var userTime: UInt64?
        var systemTime: UInt64?
        var pkgIdleWakeups: UInt64?
        var interruptWakeups: UInt64?
        var pageins: UInt64?
        var wiredSize: UInt64?
        var residentSize: UInt64?
        var physFootprint: UInt64?
        var procStartAbstime: UInt64?
        var procExitAbstime: UInt64?
        var childUserTime: UInt64?
        var childSystemTime: UInt64?
        var childPkgIdleWakeups: UInt64?
        var childInterruptWakeups: UInt64?
        var childPageins: UInt64?
        var childElapsedAbstime: UInt64?
        var diskioBytesRead: UInt64?
        var diskioBytesWritten: UInt64?
        var cpuTimeQosDefault: UInt64?
        var cpuTimeQosMaintenance: UInt64?
        var cpuTimeQosBackground: UInt64?
        var cpuTimeQosUtility: UInt64?
        var cpuTimeQosLegacy: UInt64?
        var cpuTimeQosUserInitiated: UInt64?
        var cpuTimeQosUserInteractive: UInt64?
        var billedSystemTime: UInt64?
        var servicedSystemTime: UInt64?
        var logicalWrites: UInt64?
        var lifetimeMaxPhysFootprint: UInt64?
        var instructions: UInt64?
        var cycles: UInt64?
        var billedEnergy: UInt64?
        var servicedEnergy: UInt64?
        var intervalMaxPhysFootprint: UInt64?
        var runnableTime: UInt64?
        var flags: UInt64?
        var userPtime: UInt64?
        var systemPtime: UInt64?
        var pInstructions: UInt64?
        var pCycles: UInt64?
        var energyNJ: UInt64?
        var pEnergyNJ: UInt64?
        var secureTimeInSystem: UInt64?
        var securePtimeInSystem: UInt64?
        var neuralFootprint: UInt64?
        var lifetimeMaxNeuralFootprint: UInt64?
        var intervalMaxNeuralFootprint: UInt64?
        var conclaveFootprint: UInt64?
        var pageWaitTimeMach: UInt64?
        var pageCacheHits: UInt64?
    }

    /// The TASK_CRASHINFO_LEDGER_* items, one field per ledger, in bytes.
    struct Ledgers: Codable {
        var internalMemory: UInt64?
        var internalMemoryCompressed: UInt64?
        var iokitMapped: UInt64?
        var alternateAccounting: UInt64?
        var alternateAccountingCompressed: UInt64?
        var purgeableNonvolatile: UInt64?
        var purgeableNonvolatileCompressed: UInt64?
        var pageTable: UInt64?
        var physFootprint: UInt64?
        var physFootprintLifetimeMax: UInt64?
        var networkNonvolatile: UInt64?
        var networkNonvolatileCompressed: UInt64?
        var wiredMemory: UInt64?
        var taggedFootprint: UInt64?
        var taggedFootprintCompressed: UInt64?
        var mediaFootprint: UInt64?
        var mediaFootprintCompressed: UInt64?
        var graphicsFootprint: UInt64?
        var graphicsFootprintCompressed: UInt64?
        var neuralFootprint: UInt64?
        var neuralFootprintCompressed: UInt64?
    }

    /// Code-signing identity and status of the crashed process.
    struct CodeSigning: Codable {
        var csFlags: UInt32?
        var signingID: String?
        var teamID: String?
        var validationCategory: UInt32?
        /// Raw kernel value; 0xFFFFFFFF means "invalid/unset" (KCDATA_INVALID_CS_TRUST_LEVEL).
        var trustLevel: UInt32?
        var auxiliaryInfo: UInt64?
        var securityConfig: UInt32?
    }

    /// BSD process facts from kcdata. Raw kernel values; times are seconds/microseconds pairs.
    struct ProcessInfo: Codable {
        var ppid: UInt32?
        var responsiblePid: UInt32?
        var uid: UInt32?
        var gid: UInt32?
        var procFlags: UInt32?
        var procStatus: UInt8?
        var psaFlags: UInt16?
        var startTimeSec: UInt64?
        var startTimeUSec: UInt64?
        var userStackAddress: UInt64?
        var argsLen: UInt32?
        var argc: UInt32?
        var dirtyFlags: UInt32?
        /// UUID of the main executable (from BSDINFOWITHUNIQID).
        var executableUUID: String?
        var uniqueID: UInt64?
        var parentUniqueID: UInt64?
        var procCPUType: Int32?
        var coalitionID: UInt64?
        var personaID: UInt32?
        var isCorpseFork: Bool?
        var crashCount: Int32?
        var throttleTimeout: Int32?
        var memorystatusEffectivePriority: Int32?
        var rlimCore: UInt64?
        var coreAllowed: Bool?
        var sandboxProfile: String?
        var taskUUID: String?
        var udataPtrs: [UInt64]?
        var voucher: Voucher?
        var externalModifications: ExternalModifications?
        var dyldInfo: DyldInfo?
        var jitAddressRange: JITAddressRange?

        /// TASK_CRASHINFO_VOUCHER_INFO: the voucher origin of the crashed work.
        struct Voucher: Codable {
            let threadID: UInt64
            let originatorPid: UInt32
            let proximatePid: UInt32
        }

        /// TASK_CRASHINFO_EXTMODINFO (vm_extmod_statistics): who reached into this task.
        struct ExternalModifications: Codable {
            let taskForPidCount: Int64
            let taskForPidCallerCount: Int64
            let threadCreationCount: Int64
            let threadCreationCallerCount: Int64
            let threadSetStateCount: Int64
            let threadSetStateCallerCount: Int64
        }

        /// TASK_CRASHINFO_TASKDYLD_INFO (task_dyld_info).
        struct DyldInfo: Codable {
            let allImageInfoAddr: UInt64
            let allImageInfoSize: UInt64
            let allImageInfoFormat: Int32
        }

        /// TASK_CRASHINFO_JIT_ADDRESS_RANGE.
        struct JITAddressRange: Codable {
            let startAddress: UInt64
            let endAddress: UInt64
        }
    }

    /// TASK_CRASHINFO_WORKQUEUEINFO (proc_workqueueinfo).
    struct Workqueue: Codable {
        let totalThreads: UInt32
        let runningThreads: UInt32
        let blockedThreads: UInt32
        let state: UInt32
    }

    struct VMInfo: Codable {
        let virtualSize: UInt64
        let residentSize: UInt64
        let residentSizePeak: UInt64
        let reusable: UInt64
        let compressed: UInt64
        let compressedPeak: UInt64
        let compressedLifetime: UInt64
        /// Bytes left before the process hits its memory limit (-1 when unknown).
        let limitBytesRemaining: Int64
        let regionCount: Int32
    }

    /// Only the fields unique to this flavor: sizes are in `VMInfo` and everything else the
    /// task carries is in `Rusage`, so repeating them here would leave consumers picking a winner.
    struct BasicInfo: Codable {
        let suspendCount: Int32
        let policy: Int32
    }

    struct Events: Codable {
        let faults: Int32
        let cowFaults: Int32
        let messagesSent: Int32
        let messagesReceived: Int32
        let syscallsMach: Int32
        let syscallsUnix: Int32
        let contextSwitches: Int32
    }

    /// Only the timer-wakeup bins: the other task_power_info fields duplicate `Rusage`.
    struct Power: Codable {
        let timerWakeupsBin1: UInt64
        let timerWakeupsBin2: UInt64
    }

    /// One binary image of the crashed process (from CrashedProcess.binaryImages).
    struct Image: Codable {
        let path: String
        let uuid: String?
        let baseAddress: UInt64
        let size: UInt64
        let cpuType: Int32
        let cpuSubType: Int32
    }
}
