//
//  KCDataParser.swift
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

/// Reader for the kernel's kcdata crash-info buffer (the blob from `task_map_corpse_info_64`).
///
/// The buffer is a stream of 16-byte-aligned TLV items: a 16-byte header (type: u32, size: u32,
/// flags: u64) followed by `size` bytes, beginning with KCDATA_BUFFER_BEGIN_CRASHINFO and ending
/// with KCDATA_TYPE_BUFFER_END. Every TASK_CRASHINFO/EXIT_REASON item with a published layout is
/// decoded; layouts come from the macOS 27 SDK's `kern/kcdata.h` (newer than open-source xnu) and
/// were confirmed against real device samples. Classified fields (signal, mach exception,
/// resource, exit-reason namespace/code) are decoded into the report model's typed values; the
/// rest are the raw kernel values.
enum KCDataParser {

    /// Everything decoded out of one crash-info buffer, grouped the way the snapshot stores it.
    struct Decoded {
        let crashInfo: CorpseSnapshot.CrashInfo
        let rusage: CorpseSnapshot.Rusage?
        let ledgers: CorpseSnapshot.Ledgers?
        let kernelTriage: [String]?
        let codeSigning: CorpseSnapshot.CodeSigning?
        let process: CorpseSnapshot.ProcessInfo?
        let workqueue: CorpseSnapshot.Workqueue?
    }

    private static let bufferBeginCrashInfo: UInt32 = 0xDEAD_F157
    private static let bufferEnd: UInt32 = 0xF191_58ED

    // TASK_CRASHINFO_* item types (kern/kcdata.h, macOS 27 SDK).
    private static let extModInfo: UInt32 = 0x801
    private static let bsdInfoWithUniqID: UInt32 = 0x802
    private static let taskDyldInfo: UInt32 = 0x803
    private static let taskUUID: UInt32 = 0x804
    private static let pid: UInt32 = 0x805
    private static let ppid: UInt32 = 0x806
    private static let rusageInfo: UInt32 = 0x808
    private static let procName: UInt32 = 0x809
    private static let procStartTime: UInt32 = 0x80B
    private static let userStack: UInt32 = 0x80C
    private static let argsLen: UInt32 = 0x80D
    private static let exceptionCodes: UInt32 = 0x80E
    private static let procPath: UInt32 = 0x80F
    private static let procCSFlags: UInt32 = 0x810
    private static let procStatus: UInt32 = 0x811
    private static let uid: UInt32 = 0x812
    private static let gid: UInt32 = 0x813
    private static let procArgc: UInt32 = 0x814
    private static let procFlags: UInt32 = 0x815
    private static let cpuType: UInt32 = 0x816
    private static let workQueueInfo: UInt32 = 0x817
    private static let responsiblePid: UInt32 = 0x818
    private static let dirtyFlags: UInt32 = 0x819
    private static let crashedThreadID: UInt32 = 0x81A
    private static let coalitionID: UInt32 = 0x81B
    private static let udataPtrs: UInt32 = 0x81C
    private static let memoryLimit: UInt32 = 0x81D
    private static let ledgerRange: ClosedRange<UInt32> = 0x81E...0x834
    private static let memoryLimitIncrease: UInt32 = 0x82C
    private static let personaID: UInt32 = 0x82B
    private static let memorystatusEffectivePriority: UInt32 = 0x835
    private static let kernelTriageV1: UInt32 = 0x836
    private static let taskIsCorpseFork: UInt32 = 0x837
    private static let exceptionType: UInt32 = 0x838
    private static let crashCount: UInt32 = 0x839
    private static let throttleTimeout: UInt32 = 0x83A
    private static let csSigningID: UInt32 = 0x83B
    private static let csTeamID: UInt32 = 0x83C
    private static let csValidationCategory: UInt32 = 0x83D
    private static let csTrustLevel: UInt32 = 0x83E
    private static let procCPUType: UInt32 = 0x83F
    private static let jitAddressRange: UInt32 = 0x840
    private static let csAuxiliaryInfo: UInt32 = 0x842
    private static let rlimCore: UInt32 = 0x843
    private static let coreAllowed: UInt32 = 0x844
    private static let taskSecurityConfig: UInt32 = 0x845
    private static let voucherInfo: UInt32 = 0x846
    private static let sandboxProfile: UInt32 = 0x847
    private static let procPSAFlags: UInt32 = 0x848
    /// TASK_CRASHINFO_LEDGER_* item id → Ledgers field. 0x82B/0x82C sit inside this id range
    /// but are not ledgers; their cases match before the range case does.
    private static let ledgerFields: [UInt32: WritableKeyPath<CorpseSnapshot.Ledgers, UInt64?>] = [
        0x81E: \.internalMemory, 0x81F: \.internalMemoryCompressed, 0x820: \.iokitMapped,
        0x821: \.alternateAccounting, 0x822: \.alternateAccountingCompressed,
        0x823: \.purgeableNonvolatile, 0x824: \.purgeableNonvolatileCompressed,
        0x825: \.pageTable, 0x826: \.physFootprint, 0x827: \.physFootprintLifetimeMax,
        0x828: \.networkNonvolatile, 0x829: \.networkNonvolatileCompressed, 0x82A: \.wiredMemory,
        0x82D: \.taggedFootprint, 0x82E: \.taggedFootprintCompressed,
        0x82F: \.mediaFootprint, 0x830: \.mediaFootprintCompressed,
        0x831: \.graphicsFootprint, 0x832: \.graphicsFootprintCompressed,
        0x833: \.neuralFootprint, 0x834: \.neuralFootprintCompressed,
    ]

    /// struct rusage_info's u64 fields after the uuid, in on-wire order: position in this array
    /// IS the wire offset (index 36 = byte 16 + 36*8), so append-only, never reorder. New
    /// kernel versions extend the tail; decode stops at the item's actual size.
    private static let rusageFields: [WritableKeyPath<CorpseSnapshot.Rusage, UInt64?>] = [
        \.userTime, \.systemTime, \.pkgIdleWakeups, \.interruptWakeups, \.pageins,
        \.wiredSize, \.residentSize, \.physFootprint, \.procStartAbstime, \.procExitAbstime,
        \.childUserTime, \.childSystemTime, \.childPkgIdleWakeups, \.childInterruptWakeups,
        \.childPageins, \.childElapsedAbstime, \.diskioBytesRead, \.diskioBytesWritten,
        \.cpuTimeQosDefault, \.cpuTimeQosMaintenance, \.cpuTimeQosBackground, \.cpuTimeQosUtility,
        \.cpuTimeQosLegacy, \.cpuTimeQosUserInitiated, \.cpuTimeQosUserInteractive,
        \.billedSystemTime, \.servicedSystemTime, \.logicalWrites, \.lifetimeMaxPhysFootprint,
        \.instructions, \.cycles, \.billedEnergy, \.servicedEnergy, \.intervalMaxPhysFootprint,
        \.runnableTime, \.flags, \.userPtime, \.systemPtime, \.pInstructions, \.pCycles,
        \.energyNJ, \.pEnergyNJ, \.secureTimeInSystem, \.securePtimeInSystem, \.neuralFootprint,
        \.lifetimeMaxNeuralFootprint, \.intervalMaxNeuralFootprint, \.conclaveFootprint,
        \.pageWaitTimeMach, \.pageCacheHits,
    ]

    private static let exitReasonSnapshot: UInt32 = 0x1001
    private static let exitReasonUserDesc: UInt32 = 0x1002
    private static let exitReasonUserPayload: UInt32 = 0x1003
    private static let exitReasonCodesigningInfo: UInt32 = 0x1004
    private static let exitReasonWorkloopID: UInt32 = 0x1005
    private static let exitReasonDispatchQueueNo: UInt32 = 0x1006

    /// Decode a kcdata crash-info blob.
    ///
    /// - Parameters:
    ///   - data: The blob mapped from the corpse via `task_map_corpse_info_64`.
    ///   - exception: The original Mach exception type from `CrashReason.exception`. It selects how
    ///     the raw exception code is interpreted (resource bitfield vs signal/fault packing).
    /// - Returns: The decoded facts, or `nil` if the blob is not a crash-info buffer.
    static func parse(_ data: Data, exception: Int32) -> Decoded? {
        let b = [UInt8](data)
        let n = b.count
        guard n >= 16 else { return nil }

        func u16(_ o: Int) -> UInt16 {
            guard o >= 0, o + 2 <= n else { return 0 }
            return UInt16(b[o]) | UInt16(b[o + 1]) << 8
        }
        func u32(_ o: Int) -> UInt32 {
            guard o >= 0, o + 4 <= n else { return 0 }
            return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
        }
        func u64(_ o: Int) -> UInt64 {
            guard o >= 0, o + 8 <= n else { return 0 }
            return (0..<8).reduce(UInt64(0)) { $0 | (UInt64(b[o + $1]) << (8 * $1)) }
        }
        func i32(_ o: Int) -> Int32 { Int32(bitPattern: u32(o)) }
        func i64(_ o: Int) -> Int64 { Int64(bitPattern: u64(o)) }
        func string(_ o: Int, _ maxLen: Int) -> String? {
            guard o >= 0, o < n else { return nil }
            var end = o
            let limit = min(o + maxLen, n)
            while end < limit && b[end] != 0 { end += 1 }
            let slice = b[o..<end]
            // Any valid UTF-8 is fine (CJK executable names are legitimate). Tab/newline stay:
            // dyld and RunningBoard exit-reason descriptions are multi-line ("Library not
            // loaded: ...\n  Referenced from: ..."). Other control characters mean corruption.
            guard !slice.isEmpty, let s = String(bytes: slice, encoding: .utf8),
                !s.unicodeScalars.contains(where: {
                    ($0.value < 32 && $0 != "\t" && $0 != "\n" && $0 != "\r") || $0.value == 127
                })
            else { return nil }
            return s
        }
        func uuidString(_ o: Int) -> String? {
            guard o >= 0, o + 16 <= n else { return nil }
            let u = UUID(
                uuid: (
                    b[o], b[o + 1], b[o + 2], b[o + 3], b[o + 4], b[o + 5], b[o + 6], b[o + 7],
                    b[o + 8], b[o + 9], b[o + 10], b[o + 11], b[o + 12], b[o + 13], b[o + 14], b[o + 15]
                ))
            // All zeros means the kernel had nothing; don't report a fake nil UUID.
            return u.uuid.0 == 0 && b[(o + 1)...(o + 15)].allSatisfy({ $0 == 0 }) ? nil : u.uuidString
        }

        guard u32(0) == bufferBeginCrashInfo else { return nil }

        // Crash facts.
        var excCode: UInt64 = 0
        var excSub: UInt64 = 0
        var haveExc = false
        var erNamespace: UInt32 = 0
        var erCode: UInt64 = 0
        var erFlags: UInt64?
        var haveER = false
        var erDesc: String?
        var erPayload: Data?
        var erCodeSigning: CorpseSnapshot.CrashInfo.ExitReason.CodeSigningInfo?
        var erWorkloopID: UInt64?
        var erDispatchQueueNo: UInt64?
        var processName: String?
        var processPath: String?
        var procPID: UInt32?
        var threadID: UInt64?
        var cpu: Int32?
        var kernelExceptionType: Int32?
        var memLimit: UInt64?
        var memLimitIncrease: UInt32?

        // Grouped sections, built field by field as their items stream past.
        var rusage: CorpseSnapshot.Rusage?
        var ledgers = CorpseSnapshot.Ledgers()
        var haveLedgers = false
        var triage: [String]?
        var codeSigning = CorpseSnapshot.CodeSigning()
        var haveCodeSigning = false
        var process = CorpseSnapshot.ProcessInfo()
        var haveProcess = false
        var workqueue: CorpseSnapshot.Workqueue?

        var off = 0
        while off + 16 <= n {
            let type = u32(off)
            let rawSize = u32(off + 4)
            let d = off + 16
            if type == bufferEnd { break }
            // A truncated or corrupt blob can end mid-item or carry a garbage size; stop
            // rather than let the out-of-range u32/u64 helpers fabricate zero-valued crash
            // facts. The bound is checked before UInt32 -> Int so a hostile size cannot trap
            // the conversion or the offset addition on a 32-bit Int platform.
            if UInt64(rawSize) > UInt64(n - d) { break }
            let size = Int(rawSize)

            switch type {
            case exceptionCodes where size >= 16:
                excCode = u64(d)
                excSub = u64(d + 8)
                haveExc = true
            case pid where size >= 4:
                procPID = u32(d)
            case procName:
                processName = string(d, min(size, 64))
            case procPath:
                processPath = string(d, size)
            case crashedThreadID where size >= 8:
                threadID = u64(d)
            case cpuType where size >= 4:
                cpu = i32(d)
            case exceptionType where size >= 4:
                kernelExceptionType = i32(d)
            case memoryLimit where size >= 8:
                memLimit = u64(d)
            // These two sit inside the ledger id range, so they must match before it.
            case memoryLimitIncrease where size >= 4:
                memLimitIncrease = u32(d)
            case personaID where size >= 4:
                process.personaID = u32(d)
                haveProcess = true

            case exitReasonSnapshot where size >= 12:
                erNamespace = u32(d)
                erCode = u64(d + 4)
                if size >= 20 { erFlags = u64(d + 12) }
                haveER = true
            case exitReasonUserDesc:
                erDesc = string(d, size)
            case exitReasonUserPayload where size > 0:
                erPayload = Data(b[d..<(d + size)])
            case exitReasonWorkloopID where size >= 8:
                erWorkloopID = u64(d)
            case exitReasonDispatchQueueNo where size >= 8:
                erDispatchQueueNo = u64(d)
            case exitReasonCodesigningInfo where size >= 2108:
                // struct codesigning_exit_reason_info (packed): two u64s, two 1024-byte paths,
                // four u64 modtimes, eight u8 flags, one u32.
                erCodeSigning = .init(
                    virtualAddress: u64(d), fileOffset: u64(d + 8),
                    pathname: string(d + 16, 1024), filename: string(d + 1040, 1024),
                    codesigModtimeSecs: u64(d + 2064), codesigModtimeNsecs: u64(d + 2072),
                    pageModtimeSecs: u64(d + 2080), pageModtimeNsecs: u64(d + 2088),
                    pathTruncated: b[d + 2096] != 0, objectCodesigned: b[d + 2097] != 0,
                    pageCodesigValidated: b[d + 2098] != 0, pageCodesigTainted: b[d + 2099] != 0,
                    pageCodesigNx: b[d + 2100] != 0, pageWpmapped: b[d + 2101] != 0,
                    pageSlid: b[d + 2102] != 0, pageDirty: b[d + 2103] != 0,
                    pageShadowDepth: u32(d + 2104))

            case rusageInfo where size >= 16:
                // struct rusage_info: a 16-byte uuid then u64 fields appended version over
                // version, so decode as a prefix: fill fields in order while bytes remain.
                var v = CorpseSnapshot.Rusage()
                v.uuid = uuidString(d)
                var o = d + 16
                for field in Self.rusageFields {
                    guard o + 8 <= d + size else { break }
                    v[keyPath: field] = u64(o)
                    o += 8
                }
                rusage = v

            case ledgerRange where size >= 8:
                if let field = Self.ledgerFields[type] {
                    ledgers[keyPath: field] = u64(d)
                    haveLedgers = true
                }

            case kernelTriageV1 where size >= 640:
                // struct kernel_triage_info_v1: five 128-char strings; keep the non-empty ones.
                let strings = (0..<5).compactMap { string(d + $0 * 128, 128) }
                if !strings.isEmpty { triage = strings }

            case procCSFlags where size >= 4:
                codeSigning.csFlags = u32(d)
                haveCodeSigning = true
            case csSigningID:
                codeSigning.signingID = string(d, min(size, 64))
                haveCodeSigning = true
            case csTeamID:
                codeSigning.teamID = string(d, min(size, 32))
                haveCodeSigning = true
            case csValidationCategory where size >= 4:
                codeSigning.validationCategory = u32(d)
                haveCodeSigning = true
            case csTrustLevel where size >= 4:
                codeSigning.trustLevel = u32(d)
                haveCodeSigning = true
            case csAuxiliaryInfo where size >= 8:
                codeSigning.auxiliaryInfo = u64(d)
                haveCodeSigning = true
            case taskSecurityConfig where size >= 4:
                codeSigning.securityConfig = u32(d)
                haveCodeSigning = true

            case ppid where size >= 4:
                process.ppid = u32(d)
                haveProcess = true
            case responsiblePid where size >= 4:
                process.responsiblePid = u32(d)
                haveProcess = true
            case uid where size >= 4:
                process.uid = u32(d)
                haveProcess = true
            case gid where size >= 4:
                process.gid = u32(d)
                haveProcess = true
            case procFlags where size >= 4:
                process.procFlags = u32(d)
                haveProcess = true
            case procStatus where size >= 1:
                process.procStatus = b[d]
                haveProcess = true
            case procPSAFlags where size >= 2:
                process.psaFlags = u16(d)
                haveProcess = true
            case procStartTime where size >= 16:
                // struct timeval64.
                process.startTimeSec = u64(d)
                process.startTimeUSec = u64(d + 8)
                haveProcess = true
            case userStack where size >= 8:
                process.userStackAddress = u64(d)
                haveProcess = true
            case argsLen where size >= 4:
                process.argsLen = u32(d)
                haveProcess = true
            case procArgc where size >= 4:
                process.argc = u32(d)
                haveProcess = true
            case dirtyFlags where size >= 4:
                process.dirtyFlags = u32(d)
                haveProcess = true
            case bsdInfoWithUniqID where size >= 32:
                // struct crashinfo_proc_uniqidentifierinfo (packed): uuid[16], u64 unique,
                // u64 parent-unique, then reserved.
                process.executableUUID = uuidString(d)
                process.uniqueID = u64(d + 16)
                process.parentUniqueID = u64(d + 24)
                haveProcess = true
            case procCPUType where size >= 4:
                process.procCPUType = i32(d)
                haveProcess = true
            case taskIsCorpseFork where size >= 4:
                process.isCorpseFork = u32(d) != 0
                haveProcess = true
            case crashCount where size >= 4:
                process.crashCount = i32(d)
                haveProcess = true
            case throttleTimeout where size >= 4:
                process.throttleTimeout = i32(d)
                haveProcess = true
            case memorystatusEffectivePriority where size >= 4:
                process.memorystatusEffectivePriority = i32(d)
                haveProcess = true
            case rlimCore where size >= 8:
                process.rlimCore = u64(d)
                haveProcess = true
            case coreAllowed where size >= 1:
                process.coreAllowed = b[d] != 0
                haveProcess = true
            case sandboxProfile:
                process.sandboxProfile = string(d, min(size, 32))
                haveProcess = true
            case taskUUID where size >= 16:
                process.taskUUID = uuidString(d)
                haveProcess = true
            case coalitionID where size >= 8:
                process.coalitionID = u64(d)
                haveProcess = true
            case udataPtrs where size >= 8:
                process.udataPtrs = stride(from: d, to: d + (size / 8) * 8, by: 8).map { u64($0) }
                haveProcess = true
            case voucherInfo where size >= 16:
                // struct crashinfo_voucher (packed): u64 thread id, u32 originator, u32 proximate.
                process.voucher = .init(threadID: u64(d), originatorPid: u32(d + 8), proximatePid: u32(d + 12))
                haveProcess = true
            case extModInfo where size >= 48:
                // struct vm_extmod_statistics: six i64 counters.
                process.externalModifications = .init(
                    taskForPidCount: i64(d), taskForPidCallerCount: i64(d + 8),
                    threadCreationCount: i64(d + 16), threadCreationCallerCount: i64(d + 24),
                    threadSetStateCount: i64(d + 32), threadSetStateCallerCount: i64(d + 40))
                haveProcess = true
            case taskDyldInfo where size >= 20:
                // struct task_dyld_info: u64 addr, u64 size, i32 format.
                process.dyldInfo = .init(
                    allImageInfoAddr: u64(d), allImageInfoSize: u64(d + 8), allImageInfoFormat: i32(d + 16))
                haveProcess = true
            case jitAddressRange where size >= 16:
                process.jitAddressRange = .init(startAddress: u64(d), endAddress: u64(d + 8))
                haveProcess = true

            case workQueueInfo where size >= 16:
                // struct proc_workqueueinfo: four u32s.
                workqueue = .init(
                    totalThreads: u32(d), runningThreads: u32(d + 4),
                    blockedThreads: u32(d + 8), state: u32(d + 12))

            default:
                break
            }

            let next = (off + 16 + size + 15) & ~15
            if next <= off { break }
            off = next
        }

        // Decode the raw exception code. EXC_RESOURCE packs a resource bitfield; every other
        // (signal/fault) crash packs (signal << 24) | (mach exception << 20) | subcode, with the
        // fault address in the subcode word.
        var signal: Signal?
        var machExc: MachExceptionType?
        var sub: UInt32?
        var fault: UInt64?
        var resource: CorpseSnapshot.CrashInfo.Resource?

        if haveExc {
            if exception == EXC_RESOURCE {
                let rtype = UInt32((excCode >> 61) & 0x7)
                let flavor = UInt32((excCode >> 58) & 0x7)
                resource = .init(
                    type: ResourceType(rawValue: rtype),
                    flavor: ResourceFlavor(type: rtype, flavor: flavor),
                    // EXC_RESOURCE_HWM_LIMIT_MASK: bits [15:0] (kern/exc_resource.h); bit 16
                    // is the Active flag, not part of the limit.
                    limitMB: rtype == 3 ? (excCode & 0xFFFF) : nil)
            } else {
                signal = Signal(rawValue: Int32((excCode >> 24) & 0xFF))
                let me = UInt32((excCode >> 20) & 0xF)
                if me != 0 {
                    machExc = MachExceptionType(rawValue: Int32(me))
                    sub = UInt32(excCode & 0xF_FFFF)
                }
                if exception == EXC_BAD_ACCESS {
                    fault = excSub
                }
            }
        }

        var exitReason: CorpseSnapshot.CrashInfo.ExitReason?
        if haveER {
            exitReason = .init(
                namespace: ExitReasonNamespace(rawValue: erNamespace),
                code: ExitReasonCode(rawValue: erCode),
                flags: erFlags,
                workloopID: erWorkloopID,
                dispatchQueueNo: erDispatchQueueNo,
                userPayload: erPayload,
                codeSigningInfo: erCodeSigning)
        }

        let crashInfo = CorpseSnapshot.CrashInfo(
            exceptionCode: excCode, exceptionSubcode: excSub,
            signal: signal, machException: machExc, subcode: sub, faultAddress: fault,
            resource: resource,
            exitReason: exitReason, exitReasonDescription: erDesc,
            processName: processName, pid: procPID, processPath: processPath,
            crashedThreadID: threadID, cpuType: cpu, exceptionType: kernelExceptionType,
            memoryLimitMB: memLimit, memoryLimitIncreaseMB: memLimitIncrease)

        return Decoded(
            crashInfo: crashInfo,
            rusage: rusage,
            ledgers: haveLedgers ? ledgers : nil,
            kernelTriage: triage,
            codeSigning: haveCodeSigning ? codeSigning : nil,
            process: haveProcess ? process : nil,
            workqueue: workqueue)
    }
}
