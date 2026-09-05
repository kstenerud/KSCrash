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
/// Public in name only: the corpse monitor's typed event payload must be visible wherever the
/// monitor class is, but everything inside stays internal; the extension's capture path is the
/// only producer and consumer.
public struct CorpseSnapshot: Codable, Sendable, Equatable {
    /// The original Mach exception type from `CrashReason.exception` (reliable, unlike its `codes`).
    public var exception: MachExceptionType?

    /// Decoded from the corpse's kcdata crash-info blob (the authoritative crash record).
    public var crashInfo: CrashInfo?

    /// TASK_CRASHINFO_RUSAGE_INFO: the kernel's final resource accounting for the process.
    public var rusage: Rusage?

    /// The TASK_CRASHINFO_LEDGER_* family: per-ledger memory figures, in bytes.
    public var ledgers: Ledgers?

    /// TASK_CRASHINFO_KERNEL_TRIAGE_INFO_V1: the kernel's own notes on why the process died.
    public var kernelTriage: [String]?

    /// Code-signing identity and status of the crashed process.
    public var codeSigning: CodeSigning?

    /// BSD process facts (identity, flags, times) decoded from kcdata.
    public var process: ProcessInfo?

    /// TASK_CRASHINFO_WORKQUEUEINFO: workqueue thread counts at death.
    public var workqueue: Workqueue?

    /// task_info(TASK_VM_INFO): memory figures kcdata does not carry.
    public var vmInfo: VMInfo?
    /// task_info(TASK_BASIC_INFO_64): suspend count and policy.
    public var basicInfo: BasicInfo?
    /// task_info(TASK_EVENTS_INFO): faults, syscalls, context switches.
    public var events: Events?
    /// task_info(TASK_POWER_INFO): the timer-wakeup bins kcdata does not carry.
    public var power: Power?
    /// task_policy_get(TASK_CATEGORY_POLICY): the Mach task role (e.g. `.foregroundApplication`).
    public var taskRole: TaskRole?

    /// The crashed process's binary images, as handed to us in the CrashedProcess struct.
    public var images: [Image]

    /// Crash facts decoded from the kcdata crash-info blob. Classified pieces (signal, mach exception,
    /// resource, exit-reason namespace) are typed enums from the report model; the rest are the raw
    /// kernel values.
    public struct CrashInfo: Codable, Sendable, Equatable {
        public var exceptionCode: UInt64
        public var exceptionSubcode: UInt64
        public var signal: Signal?
        public var machException: MachExceptionType?
        public var subcode: UInt32?
        public var faultAddress: UInt64?
        public var resource: Resource?
        public var exitReason: ExitReason?
        public var exitReasonDescription: String?
        public var processName: String?
        public var pid: UInt32?
        public var processPath: String?
        public var crashedThreadID: UInt64?
        public var cpuType: Int32?
        /// TASK_CRASHINFO_EXCEPTION_TYPE: the kernel's own record of the Mach exception type,
        /// alongside the snapshot's `exception` from CrashedProcess.reason.
        public var exceptionType: Int32?
        public var memoryLimitMB: UInt64?
        public var memoryLimitIncreaseMB: UInt32?

        /// The Mach exception code to report, matching what an in-process report carries.
        ///
        /// Most exceptions pack the code word as (signal << 24) | (mach exception << 20) |
        /// code, so only the low 20 bits are the Mach code itself; `subcode` holds them.
        /// EXC_RESOURCE and EXC_GUARD instead define the whole word as a payload, so those
        /// pass through untouched.
        public func machCode(for exception: MachExceptionType) -> UInt64 {
            switch exception {
            case .EXC_RESOURCE, .EXC_GUARD: return exceptionCode
            default: return UInt64(subcode ?? 0)
            }
        }

        /// An EXC_RESOURCE bitfield: which resource was exceeded and how.
        public struct Resource: Codable, Sendable, Equatable {
            public let type: ResourceType
            public let flavor: ResourceFlavor
            public let limitMB: UInt64?

            public init(
                type: ResourceType,
                flavor: ResourceFlavor,
                limitMB: UInt64? = nil
            ) {
                self.type = type
                self.flavor = flavor
                self.limitMB = limitMB
            }
        }

        /// An `os_reason` exit reason (jetsam, watchdog/SpringBoard, ...) and its companion items.
        public struct ExitReason: Codable, Sendable, Equatable {
            public var namespace: ExitReasonNamespace
            public var code: ExitReasonCode
            public var flags: UInt64?
            public var workloopID: UInt64?
            public var dispatchQueueNo: UInt64?
            public var userPayload: Data?
            public var codeSigningInfo: CodeSigningInfo?

            /// EXIT_REASON_CODESIGNING_INFO: where and why code signing killed the process.
            public struct CodeSigningInfo: Codable, Sendable, Equatable {
                public let virtualAddress: UInt64
                public let fileOffset: UInt64
                public let pathname: String?
                public let filename: String?
                public let codesigModtimeSecs: UInt64
                public let codesigModtimeNsecs: UInt64
                public let pageModtimeSecs: UInt64
                public let pageModtimeNsecs: UInt64
                public let pathTruncated: Bool
                public let objectCodesigned: Bool
                public let pageCodesigValidated: Bool
                public let pageCodesigTainted: Bool
                public let pageCodesigNx: Bool
                public let pageWpmapped: Bool
                public let pageSlid: Bool
                public let pageDirty: Bool
                public let pageShadowDepth: UInt32

                public init(
                    virtualAddress: UInt64,
                    fileOffset: UInt64,
                    pathname: String? = nil,
                    filename: String? = nil,
                    codesigModtimeSecs: UInt64,
                    codesigModtimeNsecs: UInt64,
                    pageModtimeSecs: UInt64,
                    pageModtimeNsecs: UInt64,
                    pathTruncated: Bool,
                    objectCodesigned: Bool,
                    pageCodesigValidated: Bool,
                    pageCodesigTainted: Bool,
                    pageCodesigNx: Bool,
                    pageWpmapped: Bool,
                    pageSlid: Bool,
                    pageDirty: Bool,
                    pageShadowDepth: UInt32
                ) {
                    self.virtualAddress = virtualAddress
                    self.fileOffset = fileOffset
                    self.pathname = pathname
                    self.filename = filename
                    self.codesigModtimeSecs = codesigModtimeSecs
                    self.codesigModtimeNsecs = codesigModtimeNsecs
                    self.pageModtimeSecs = pageModtimeSecs
                    self.pageModtimeNsecs = pageModtimeNsecs
                    self.pathTruncated = pathTruncated
                    self.objectCodesigned = objectCodesigned
                    self.pageCodesigValidated = pageCodesigValidated
                    self.pageCodesigTainted = pageCodesigTainted
                    self.pageCodesigNx = pageCodesigNx
                    self.pageWpmapped = pageWpmapped
                    self.pageSlid = pageSlid
                    self.pageDirty = pageDirty
                    self.pageShadowDepth = pageShadowDepth
                }
            }

            public init(
                namespace: ExitReasonNamespace,
                code: ExitReasonCode,
                flags: UInt64? = nil,
                workloopID: UInt64? = nil,
                dispatchQueueNo: UInt64? = nil,
                userPayload: Data? = nil,
                codeSigningInfo: CodeSigningInfo? = nil
            ) {
                self.namespace = namespace
                self.code = code
                self.flags = flags
                self.workloopID = workloopID
                self.dispatchQueueNo = dispatchQueueNo
                self.userPayload = userPayload
                self.codeSigningInfo = codeSigningInfo
            }
        }

        public init(
            exceptionCode: UInt64,
            exceptionSubcode: UInt64,
            signal: Signal? = nil,
            machException: MachExceptionType? = nil,
            subcode: UInt32? = nil,
            faultAddress: UInt64? = nil,
            resource: Resource? = nil,
            exitReason: ExitReason? = nil,
            exitReasonDescription: String? = nil,
            processName: String? = nil,
            pid: UInt32? = nil,
            processPath: String? = nil,
            crashedThreadID: UInt64? = nil,
            cpuType: Int32? = nil,
            exceptionType: Int32? = nil,
            memoryLimitMB: UInt64? = nil,
            memoryLimitIncreaseMB: UInt32? = nil
        ) {
            self.exceptionCode = exceptionCode
            self.exceptionSubcode = exceptionSubcode
            self.signal = signal
            self.machException = machException
            self.subcode = subcode
            self.faultAddress = faultAddress
            self.resource = resource
            self.exitReason = exitReason
            self.exitReasonDescription = exitReasonDescription
            self.processName = processName
            self.pid = pid
            self.processPath = processPath
            self.crashedThreadID = crashedThreadID
            self.cpuType = cpuType
            self.exceptionType = exceptionType
            self.memoryLimitMB = memoryLimitMB
            self.memoryLimitIncreaseMB = memoryLimitIncreaseMB
        }
    }

    /// `struct rusage_info` decoded as a versioned prefix: fields fill in declaration order while
    /// item bytes remain, so older kernels (shorter versions) leave the tail nil and newer ones
    /// (unknown appended fields) lose nothing that our layout knows. Raw kernel units throughout:
    /// times are mach ticks, sizes bytes, energy nanojoules.
    public struct Rusage: Codable, Sendable, Equatable {
        public var uuid: String?
        public var userTime: UInt64?
        public var systemTime: UInt64?
        public var pkgIdleWakeups: UInt64?
        public var interruptWakeups: UInt64?
        public var pageins: UInt64?
        public var wiredSize: UInt64?
        public var residentSize: UInt64?
        public var physFootprint: UInt64?
        public var procStartAbstime: UInt64?
        public var procExitAbstime: UInt64?
        public var childUserTime: UInt64?
        public var childSystemTime: UInt64?
        public var childPkgIdleWakeups: UInt64?
        public var childInterruptWakeups: UInt64?
        public var childPageins: UInt64?
        public var childElapsedAbstime: UInt64?
        public var diskioBytesRead: UInt64?
        public var diskioBytesWritten: UInt64?
        public var cpuTimeQosDefault: UInt64?
        public var cpuTimeQosMaintenance: UInt64?
        public var cpuTimeQosBackground: UInt64?
        public var cpuTimeQosUtility: UInt64?
        public var cpuTimeQosLegacy: UInt64?
        public var cpuTimeQosUserInitiated: UInt64?
        public var cpuTimeQosUserInteractive: UInt64?
        public var billedSystemTime: UInt64?
        public var servicedSystemTime: UInt64?
        public var logicalWrites: UInt64?
        public var lifetimeMaxPhysFootprint: UInt64?
        public var instructions: UInt64?
        public var cycles: UInt64?
        public var billedEnergy: UInt64?
        public var servicedEnergy: UInt64?
        public var intervalMaxPhysFootprint: UInt64?
        public var runnableTime: UInt64?
        public var flags: UInt64?
        public var userPtime: UInt64?
        public var systemPtime: UInt64?
        public var pInstructions: UInt64?
        public var pCycles: UInt64?
        public var energyNJ: UInt64?
        public var pEnergyNJ: UInt64?
        public var secureTimeInSystem: UInt64?
        public var securePtimeInSystem: UInt64?
        public var neuralFootprint: UInt64?
        public var lifetimeMaxNeuralFootprint: UInt64?
        public var intervalMaxNeuralFootprint: UInt64?
        public var conclaveFootprint: UInt64?
        public var pageWaitTimeMach: UInt64?
        public var pageCacheHits: UInt64?

        public init(
            uuid: String? = nil,
            userTime: UInt64? = nil,
            systemTime: UInt64? = nil,
            pkgIdleWakeups: UInt64? = nil,
            interruptWakeups: UInt64? = nil,
            pageins: UInt64? = nil,
            wiredSize: UInt64? = nil,
            residentSize: UInt64? = nil,
            physFootprint: UInt64? = nil,
            procStartAbstime: UInt64? = nil,
            procExitAbstime: UInt64? = nil,
            childUserTime: UInt64? = nil,
            childSystemTime: UInt64? = nil,
            childPkgIdleWakeups: UInt64? = nil,
            childInterruptWakeups: UInt64? = nil,
            childPageins: UInt64? = nil,
            childElapsedAbstime: UInt64? = nil,
            diskioBytesRead: UInt64? = nil,
            diskioBytesWritten: UInt64? = nil,
            cpuTimeQosDefault: UInt64? = nil,
            cpuTimeQosMaintenance: UInt64? = nil,
            cpuTimeQosBackground: UInt64? = nil,
            cpuTimeQosUtility: UInt64? = nil,
            cpuTimeQosLegacy: UInt64? = nil,
            cpuTimeQosUserInitiated: UInt64? = nil,
            cpuTimeQosUserInteractive: UInt64? = nil,
            billedSystemTime: UInt64? = nil,
            servicedSystemTime: UInt64? = nil,
            logicalWrites: UInt64? = nil,
            lifetimeMaxPhysFootprint: UInt64? = nil,
            instructions: UInt64? = nil,
            cycles: UInt64? = nil,
            billedEnergy: UInt64? = nil,
            servicedEnergy: UInt64? = nil,
            intervalMaxPhysFootprint: UInt64? = nil,
            runnableTime: UInt64? = nil,
            flags: UInt64? = nil,
            userPtime: UInt64? = nil,
            systemPtime: UInt64? = nil,
            pInstructions: UInt64? = nil,
            pCycles: UInt64? = nil,
            energyNJ: UInt64? = nil,
            pEnergyNJ: UInt64? = nil,
            secureTimeInSystem: UInt64? = nil,
            securePtimeInSystem: UInt64? = nil,
            neuralFootprint: UInt64? = nil,
            lifetimeMaxNeuralFootprint: UInt64? = nil,
            intervalMaxNeuralFootprint: UInt64? = nil,
            conclaveFootprint: UInt64? = nil,
            pageWaitTimeMach: UInt64? = nil,
            pageCacheHits: UInt64? = nil
        ) {
            self.uuid = uuid
            self.userTime = userTime
            self.systemTime = systemTime
            self.pkgIdleWakeups = pkgIdleWakeups
            self.interruptWakeups = interruptWakeups
            self.pageins = pageins
            self.wiredSize = wiredSize
            self.residentSize = residentSize
            self.physFootprint = physFootprint
            self.procStartAbstime = procStartAbstime
            self.procExitAbstime = procExitAbstime
            self.childUserTime = childUserTime
            self.childSystemTime = childSystemTime
            self.childPkgIdleWakeups = childPkgIdleWakeups
            self.childInterruptWakeups = childInterruptWakeups
            self.childPageins = childPageins
            self.childElapsedAbstime = childElapsedAbstime
            self.diskioBytesRead = diskioBytesRead
            self.diskioBytesWritten = diskioBytesWritten
            self.cpuTimeQosDefault = cpuTimeQosDefault
            self.cpuTimeQosMaintenance = cpuTimeQosMaintenance
            self.cpuTimeQosBackground = cpuTimeQosBackground
            self.cpuTimeQosUtility = cpuTimeQosUtility
            self.cpuTimeQosLegacy = cpuTimeQosLegacy
            self.cpuTimeQosUserInitiated = cpuTimeQosUserInitiated
            self.cpuTimeQosUserInteractive = cpuTimeQosUserInteractive
            self.billedSystemTime = billedSystemTime
            self.servicedSystemTime = servicedSystemTime
            self.logicalWrites = logicalWrites
            self.lifetimeMaxPhysFootprint = lifetimeMaxPhysFootprint
            self.instructions = instructions
            self.cycles = cycles
            self.billedEnergy = billedEnergy
            self.servicedEnergy = servicedEnergy
            self.intervalMaxPhysFootprint = intervalMaxPhysFootprint
            self.runnableTime = runnableTime
            self.flags = flags
            self.userPtime = userPtime
            self.systemPtime = systemPtime
            self.pInstructions = pInstructions
            self.pCycles = pCycles
            self.energyNJ = energyNJ
            self.pEnergyNJ = pEnergyNJ
            self.secureTimeInSystem = secureTimeInSystem
            self.securePtimeInSystem = securePtimeInSystem
            self.neuralFootprint = neuralFootprint
            self.lifetimeMaxNeuralFootprint = lifetimeMaxNeuralFootprint
            self.intervalMaxNeuralFootprint = intervalMaxNeuralFootprint
            self.conclaveFootprint = conclaveFootprint
            self.pageWaitTimeMach = pageWaitTimeMach
            self.pageCacheHits = pageCacheHits
        }
    }

    /// The TASK_CRASHINFO_LEDGER_* items, one field per ledger, in bytes.
    public struct Ledgers: Codable, Sendable, Equatable {
        public var internalMemory: UInt64?
        public var internalMemoryCompressed: UInt64?
        public var iokitMapped: UInt64?
        public var alternateAccounting: UInt64?
        public var alternateAccountingCompressed: UInt64?
        public var purgeableNonvolatile: UInt64?
        public var purgeableNonvolatileCompressed: UInt64?
        public var pageTable: UInt64?
        public var physFootprint: UInt64?
        public var physFootprintLifetimeMax: UInt64?
        public var networkNonvolatile: UInt64?
        public var networkNonvolatileCompressed: UInt64?
        public var wiredMemory: UInt64?
        public var taggedFootprint: UInt64?
        public var taggedFootprintCompressed: UInt64?
        public var mediaFootprint: UInt64?
        public var mediaFootprintCompressed: UInt64?
        public var graphicsFootprint: UInt64?
        public var graphicsFootprintCompressed: UInt64?
        public var neuralFootprint: UInt64?
        public var neuralFootprintCompressed: UInt64?

        public init(
            internalMemory: UInt64? = nil,
            internalMemoryCompressed: UInt64? = nil,
            iokitMapped: UInt64? = nil,
            alternateAccounting: UInt64? = nil,
            alternateAccountingCompressed: UInt64? = nil,
            purgeableNonvolatile: UInt64? = nil,
            purgeableNonvolatileCompressed: UInt64? = nil,
            pageTable: UInt64? = nil,
            physFootprint: UInt64? = nil,
            physFootprintLifetimeMax: UInt64? = nil,
            networkNonvolatile: UInt64? = nil,
            networkNonvolatileCompressed: UInt64? = nil,
            wiredMemory: UInt64? = nil,
            taggedFootprint: UInt64? = nil,
            taggedFootprintCompressed: UInt64? = nil,
            mediaFootprint: UInt64? = nil,
            mediaFootprintCompressed: UInt64? = nil,
            graphicsFootprint: UInt64? = nil,
            graphicsFootprintCompressed: UInt64? = nil,
            neuralFootprint: UInt64? = nil,
            neuralFootprintCompressed: UInt64? = nil
        ) {
            self.internalMemory = internalMemory
            self.internalMemoryCompressed = internalMemoryCompressed
            self.iokitMapped = iokitMapped
            self.alternateAccounting = alternateAccounting
            self.alternateAccountingCompressed = alternateAccountingCompressed
            self.purgeableNonvolatile = purgeableNonvolatile
            self.purgeableNonvolatileCompressed = purgeableNonvolatileCompressed
            self.pageTable = pageTable
            self.physFootprint = physFootprint
            self.physFootprintLifetimeMax = physFootprintLifetimeMax
            self.networkNonvolatile = networkNonvolatile
            self.networkNonvolatileCompressed = networkNonvolatileCompressed
            self.wiredMemory = wiredMemory
            self.taggedFootprint = taggedFootprint
            self.taggedFootprintCompressed = taggedFootprintCompressed
            self.mediaFootprint = mediaFootprint
            self.mediaFootprintCompressed = mediaFootprintCompressed
            self.graphicsFootprint = graphicsFootprint
            self.graphicsFootprintCompressed = graphicsFootprintCompressed
            self.neuralFootprint = neuralFootprint
            self.neuralFootprintCompressed = neuralFootprintCompressed
        }
    }

    /// Code-signing identity and status of the crashed process.
    public struct CodeSigning: Codable, Sendable, Equatable {
        public var csFlags: UInt32?
        public var signingID: String?
        public var teamID: String?
        public var validationCategory: UInt32?
        /// Raw kernel value; 0xFFFFFFFF means "invalid/unset" (KCDATA_INVALID_CS_TRUST_LEVEL).
        public var trustLevel: UInt32?
        public var auxiliaryInfo: UInt64?
        public var securityConfig: UInt32?

        public init(
            csFlags: UInt32? = nil,
            signingID: String? = nil,
            teamID: String? = nil,
            validationCategory: UInt32? = nil,
            trustLevel: UInt32? = nil,
            auxiliaryInfo: UInt64? = nil,
            securityConfig: UInt32? = nil
        ) {
            self.csFlags = csFlags
            self.signingID = signingID
            self.teamID = teamID
            self.validationCategory = validationCategory
            self.trustLevel = trustLevel
            self.auxiliaryInfo = auxiliaryInfo
            self.securityConfig = securityConfig
        }
    }

    /// BSD process facts from kcdata. Raw kernel values; times are seconds/microseconds pairs.
    public struct ProcessInfo: Codable, Sendable, Equatable {
        public var ppid: UInt32?
        public var responsiblePid: UInt32?
        public var uid: UInt32?
        public var gid: UInt32?
        public var procFlags: UInt32?
        public var procStatus: UInt8?
        public var psaFlags: UInt16?
        public var startTimeSec: UInt64?
        public var startTimeUSec: UInt64?
        public var userStackAddress: UInt64?
        public var argsLen: UInt32?
        public var argc: UInt32?
        public var dirtyFlags: UInt32?
        /// UUID of the main executable (from BSDINFOWITHUNIQID).
        public var executableUUID: String?
        public var uniqueID: UInt64?
        public var parentUniqueID: UInt64?
        public var procCPUType: Int32?
        public var coalitionID: UInt64?
        public var personaID: UInt32?
        public var isCorpseFork: Bool?
        public var crashCount: Int32?
        public var throttleTimeout: Int32?
        public var memorystatusEffectivePriority: Int32?
        public var rlimCore: UInt64?
        public var coreAllowed: Bool?
        public var sandboxProfile: String?
        public var taskUUID: String?
        public var udataPtrs: [UInt64]?
        public var voucher: Voucher?
        public var externalModifications: ExternalModifications?
        public var dyldInfo: DyldInfo?
        public var jitAddressRange: JITAddressRange?

        /// TASK_CRASHINFO_VOUCHER_INFO: the voucher origin of the crashed work.
        public struct Voucher: Codable, Sendable, Equatable {
            public let threadID: UInt64
            public let originatorPid: UInt32
            public let proximatePid: UInt32

            public init(
                threadID: UInt64,
                originatorPid: UInt32,
                proximatePid: UInt32
            ) {
                self.threadID = threadID
                self.originatorPid = originatorPid
                self.proximatePid = proximatePid
            }
        }

        /// TASK_CRASHINFO_EXTMODINFO (vm_extmod_statistics): who reached into this task.
        public struct ExternalModifications: Codable, Sendable, Equatable {
            public let taskForPidCount: Int64
            public let taskForPidCallerCount: Int64
            public let threadCreationCount: Int64
            public let threadCreationCallerCount: Int64
            public let threadSetStateCount: Int64
            public let threadSetStateCallerCount: Int64

            public init(
                taskForPidCount: Int64,
                taskForPidCallerCount: Int64,
                threadCreationCount: Int64,
                threadCreationCallerCount: Int64,
                threadSetStateCount: Int64,
                threadSetStateCallerCount: Int64
            ) {
                self.taskForPidCount = taskForPidCount
                self.taskForPidCallerCount = taskForPidCallerCount
                self.threadCreationCount = threadCreationCount
                self.threadCreationCallerCount = threadCreationCallerCount
                self.threadSetStateCount = threadSetStateCount
                self.threadSetStateCallerCount = threadSetStateCallerCount
            }
        }

        /// TASK_CRASHINFO_TASKDYLD_INFO (task_dyld_info).
        public struct DyldInfo: Codable, Sendable, Equatable {
            public let allImageInfoAddr: UInt64
            public let allImageInfoSize: UInt64
            public let allImageInfoFormat: Int32

            public init(
                allImageInfoAddr: UInt64,
                allImageInfoSize: UInt64,
                allImageInfoFormat: Int32
            ) {
                self.allImageInfoAddr = allImageInfoAddr
                self.allImageInfoSize = allImageInfoSize
                self.allImageInfoFormat = allImageInfoFormat
            }
        }

        /// TASK_CRASHINFO_JIT_ADDRESS_RANGE.
        public struct JITAddressRange: Codable, Sendable, Equatable {
            public let startAddress: UInt64
            public let endAddress: UInt64

            public init(
                startAddress: UInt64,
                endAddress: UInt64
            ) {
                self.startAddress = startAddress
                self.endAddress = endAddress
            }
        }

        public init(
            ppid: UInt32? = nil,
            responsiblePid: UInt32? = nil,
            uid: UInt32? = nil,
            gid: UInt32? = nil,
            procFlags: UInt32? = nil,
            procStatus: UInt8? = nil,
            psaFlags: UInt16? = nil,
            startTimeSec: UInt64? = nil,
            startTimeUSec: UInt64? = nil,
            userStackAddress: UInt64? = nil,
            argsLen: UInt32? = nil,
            argc: UInt32? = nil,
            dirtyFlags: UInt32? = nil,
            executableUUID: String? = nil,
            uniqueID: UInt64? = nil,
            parentUniqueID: UInt64? = nil,
            procCPUType: Int32? = nil,
            coalitionID: UInt64? = nil,
            personaID: UInt32? = nil,
            isCorpseFork: Bool? = nil,
            crashCount: Int32? = nil,
            throttleTimeout: Int32? = nil,
            memorystatusEffectivePriority: Int32? = nil,
            rlimCore: UInt64? = nil,
            coreAllowed: Bool? = nil,
            sandboxProfile: String? = nil,
            taskUUID: String? = nil,
            udataPtrs: [UInt64]? = nil,
            voucher: Voucher? = nil,
            externalModifications: ExternalModifications? = nil,
            dyldInfo: DyldInfo? = nil,
            jitAddressRange: JITAddressRange? = nil
        ) {
            self.ppid = ppid
            self.responsiblePid = responsiblePid
            self.uid = uid
            self.gid = gid
            self.procFlags = procFlags
            self.procStatus = procStatus
            self.psaFlags = psaFlags
            self.startTimeSec = startTimeSec
            self.startTimeUSec = startTimeUSec
            self.userStackAddress = userStackAddress
            self.argsLen = argsLen
            self.argc = argc
            self.dirtyFlags = dirtyFlags
            self.executableUUID = executableUUID
            self.uniqueID = uniqueID
            self.parentUniqueID = parentUniqueID
            self.procCPUType = procCPUType
            self.coalitionID = coalitionID
            self.personaID = personaID
            self.isCorpseFork = isCorpseFork
            self.crashCount = crashCount
            self.throttleTimeout = throttleTimeout
            self.memorystatusEffectivePriority = memorystatusEffectivePriority
            self.rlimCore = rlimCore
            self.coreAllowed = coreAllowed
            self.sandboxProfile = sandboxProfile
            self.taskUUID = taskUUID
            self.udataPtrs = udataPtrs
            self.voucher = voucher
            self.externalModifications = externalModifications
            self.dyldInfo = dyldInfo
            self.jitAddressRange = jitAddressRange
        }
    }

    /// TASK_CRASHINFO_WORKQUEUEINFO (proc_workqueueinfo).
    public struct Workqueue: Codable, Sendable, Equatable {
        public let totalThreads: UInt32
        public let runningThreads: UInt32
        public let blockedThreads: UInt32
        public let state: UInt32

        public init(
            totalThreads: UInt32,
            runningThreads: UInt32,
            blockedThreads: UInt32,
            state: UInt32
        ) {
            self.totalThreads = totalThreads
            self.runningThreads = runningThreads
            self.blockedThreads = blockedThreads
            self.state = state
        }
    }

    public struct VMInfo: Codable, Sendable, Equatable {
        public let virtualSize: UInt64
        public let residentSize: UInt64
        public let residentSizePeak: UInt64
        public let reusable: UInt64
        public let compressed: UInt64
        public let compressedPeak: UInt64
        public let compressedLifetime: UInt64
        /// Bytes left before the process hits its memory limit (-1 when unknown).
        public let limitBytesRemaining: Int64
        public let regionCount: Int32

        public init(
            virtualSize: UInt64,
            residentSize: UInt64,
            residentSizePeak: UInt64,
            reusable: UInt64,
            compressed: UInt64,
            compressedPeak: UInt64,
            compressedLifetime: UInt64,
            limitBytesRemaining: Int64,
            regionCount: Int32
        ) {
            self.virtualSize = virtualSize
            self.residentSize = residentSize
            self.residentSizePeak = residentSizePeak
            self.reusable = reusable
            self.compressed = compressed
            self.compressedPeak = compressedPeak
            self.compressedLifetime = compressedLifetime
            self.limitBytesRemaining = limitBytesRemaining
            self.regionCount = regionCount
        }
    }

    /// Only the fields unique to this flavor: sizes are in `VMInfo` and everything else the
    /// task carries is in `Rusage`, so repeating them here would leave consumers picking a winner.
    public struct BasicInfo: Codable, Sendable, Equatable {
        public let suspendCount: Int32
        public let policy: Int32

        public init(
            suspendCount: Int32,
            policy: Int32
        ) {
            self.suspendCount = suspendCount
            self.policy = policy
        }
    }

    public struct Events: Codable, Sendable, Equatable {
        public let faults: Int32
        public let cowFaults: Int32
        public let messagesSent: Int32
        public let messagesReceived: Int32
        public let syscallsMach: Int32
        public let syscallsUnix: Int32
        public let contextSwitches: Int32

        public init(
            faults: Int32,
            cowFaults: Int32,
            messagesSent: Int32,
            messagesReceived: Int32,
            syscallsMach: Int32,
            syscallsUnix: Int32,
            contextSwitches: Int32
        ) {
            self.faults = faults
            self.cowFaults = cowFaults
            self.messagesSent = messagesSent
            self.messagesReceived = messagesReceived
            self.syscallsMach = syscallsMach
            self.syscallsUnix = syscallsUnix
            self.contextSwitches = contextSwitches
        }
    }

    /// Only the timer-wakeup bins: the other task_power_info fields duplicate `Rusage`.
    public struct Power: Codable, Sendable, Equatable {
        public let timerWakeupsBin1: UInt64
        public let timerWakeupsBin2: UInt64

        public init(
            timerWakeupsBin1: UInt64,
            timerWakeupsBin2: UInt64
        ) {
            self.timerWakeupsBin1 = timerWakeupsBin1
            self.timerWakeupsBin2 = timerWakeupsBin2
        }
    }

    /// One binary image of the crashed process (from CrashedProcess.binaryImages).
    public struct Image: Codable, Sendable, Equatable {
        public let path: String
        public let uuid: String?
        public let baseAddress: UInt64
        public let size: UInt64
        public let cpuType: Int32
        public let cpuSubType: Int32

        public init(
            path: String,
            uuid: String? = nil,
            baseAddress: UInt64,
            size: UInt64,
            cpuType: Int32,
            cpuSubType: Int32
        ) {
            self.path = path
            self.uuid = uuid
            self.baseAddress = baseAddress
            self.size = size
            self.cpuType = cpuType
            self.cpuSubType = cpuSubType
        }
    }

    public init(
        exception: MachExceptionType? = nil,
        crashInfo: CrashInfo? = nil,
        rusage: Rusage? = nil,
        ledgers: Ledgers? = nil,
        kernelTriage: [String]? = nil,
        codeSigning: CodeSigning? = nil,
        process: ProcessInfo? = nil,
        workqueue: Workqueue? = nil,
        vmInfo: VMInfo? = nil,
        basicInfo: BasicInfo? = nil,
        events: Events? = nil,
        power: Power? = nil,
        taskRole: TaskRole? = nil,
        images: [Image]
    ) {
        self.exception = exception
        self.crashInfo = crashInfo
        self.rusage = rusage
        self.ledgers = ledgers
        self.kernelTriage = kernelTriage
        self.codeSigning = codeSigning
        self.process = process
        self.workqueue = workqueue
        self.vmInfo = vmInfo
        self.basicInfo = basicInfo
        self.events = events
        self.power = power
        self.taskRole = taskRole
        self.images = images
    }
}
