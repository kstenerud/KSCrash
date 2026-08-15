//
//  CorpseGatherer.swift
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

import Darwin
import Foundation
import KSCrashRecordingCore
import KSCrashReportModel

/// Gathers everything obtainable from a crashed process into a `CorpseSnapshot`: the kcdata crash
/// facts plus the resource/task figures read off the corpse port. Each read is independent and
/// missing pieces are simply nil, so a partial corpse still yields what it can. Threads and
/// backtraces are out of scope here, they are unwound separately.
enum CorpseGatherer {

    /// Read everything from `corpse`. `exception` is `CrashReason.exception`; `images` is the
    /// `CrashedProcess.binaryImages` list mapped to our `Image` shape. `saveKCData` receives the
    /// raw crash-info blob (untrimmed, before any parsing) for debug dumps.
    static func gather(
        corpse: mach_port_t, exception: Int32, images: [CorpseSnapshot.Image],
        saveKCData: ((Data, CorpseSnapshot.CrashInfo?) -> Void)? = nil
    ) -> CorpseSnapshot {
        let kcdata = mapCorpseInfo(corpse)
        let decoded = kcdata.flatMap { KCDataParser.parse($0, exception: exception) }
        if let kcdata, let saveKCData {
            saveKCData(kcdata, decoded?.crashInfo)
        }

        return CorpseSnapshot(
            // Absent rather than EXC_*(0) when the corpse carried no exception (a jetsam or
            // RunningBoard kill delivered without one). MachExceptionType's init is
            // non-failable, so wrapping unconditionally would make the field always present and
            // silently strand the kcdata-decoded exception behind an unreachable `??`.
            exception: exception != 0 ? MachExceptionType(rawValue: exception) : nil,
            crashInfo: decoded?.crashInfo,
            rusage: decoded?.rusage,
            ledgers: decoded?.ledgers,
            kernelTriage: decoded?.kernelTriage,
            codeSigning: decoded?.codeSigning,
            process: decoded?.process,
            workqueue: decoded?.workqueue,
            vmInfo: readVMInfo(corpse),
            basicInfo: readBasicInfo(corpse),
            events: readEvents(corpse),
            power: readPower(corpse),
            taskRole: readTaskRole(corpse),
            images: images)
    }

    // MARK: - kcdata

    /// Map the corpse's kcdata crash-info blob into our address space, copy it out, free the mapping.
    private static func mapCorpseInfo(_ task: mach_port_t) -> Data? {
        var address: mach_vm_address_t = 0
        var size: mach_vm_size_t = 0
        let result = task_map_corpse_info_64(mach_task_self_, task, &address, &size)
        guard result == KERN_SUCCESS, address != 0, size != 0 else { return nil }
        let data = UnsafeRawPointer(bitPattern: UInt(address)).map { Data(bytes: $0, count: Int(size)) }
        vm_deallocate(mach_task_self_, vm_address_t(address), vm_size_t(size))
        return data
    }

    // MARK: - task_info

    /// Read a fixed-size task_info flavor. The element count is computed with `.stride` (== C sizeof,
    /// including trailing padding); `.size` would come up short and the call would fail.
    private static func readTaskInfo<T>(_ task: mach_port_t, _ flavor: Int32, _ zero: T) -> T? {
        var info = zero
        var count = mach_msg_type_number_t(MemoryLayout<T>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(task, task_flavor_t(flavor), intPointer, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    // physFootprint deliberately omitted: the kcdata ledgers and rusage carry it.
    private static func readVMInfo(_ task: mach_port_t) -> CorpseSnapshot.VMInfo? {
        guard let i = readTaskInfo(task, TASK_VM_INFO, task_vm_info_data_t()) else { return nil }
        return CorpseSnapshot.VMInfo(
            virtualSize: i.virtual_size, residentSize: i.resident_size, residentSizePeak: i.resident_size_peak,
            reusable: i.reusable, compressed: i.compressed, compressedPeak: i.compressed_peak,
            compressedLifetime: i.compressed_lifetime,
            // limit_bytes_remaining imports as UInt64 but is semantically signed (-1 = unknown).
            limitBytesRemaining: Int64(bitPattern: i.limit_bytes_remaining), regionCount: i.region_count)
    }

    private static func readBasicInfo(_ task: mach_port_t) -> CorpseSnapshot.BasicInfo? {
        guard let i = readTaskInfo(task, TASK_BASIC_INFO_64, task_basic_info_64_data_t()) else { return nil }
        return CorpseSnapshot.BasicInfo(suspendCount: i.suspend_count, policy: i.policy)
    }

    // pageins deliberately omitted: rusage carries it (no field is stored from two sources).
    private static func readEvents(_ task: mach_port_t) -> CorpseSnapshot.Events? {
        guard let i = readTaskInfo(task, TASK_EVENTS_INFO, task_events_info_data_t()) else { return nil }
        return CorpseSnapshot.Events(
            faults: i.faults, cowFaults: i.cow_faults,
            messagesSent: i.messages_sent, messagesReceived: i.messages_received,
            syscallsMach: i.syscalls_mach, syscallsUnix: i.syscalls_unix, contextSwitches: i.csw)
    }

    // Only the timer bins: the other task_power_info fields duplicate rusage.
    private static func readPower(_ task: mach_port_t) -> CorpseSnapshot.Power? {
        guard let i = readTaskInfo(task, TASK_POWER_INFO, task_power_info_data_t()) else { return nil }
        return CorpseSnapshot.Power(
            timerWakeupsBin1: i.task_timer_wakeups_bin_1, timerWakeupsBin2: i.task_timer_wakeups_bin_2)
    }

    // MARK: - task role

    /// The role and its name both come from the C KSTaskRole helpers so the mapping lives in
    /// one place; `TaskRole(rawValue:)` turns the canonical name into a case. A failed kernel
    /// query is nil, distinct from a real `.unspecified` role.
    private static func readTaskRole(_ task: mach_port_t) -> TaskRole? {
        var role: Int32 = 0
        guard kstaskrole_forTask(task, &role) else { return nil }
        return TaskRole(rawValue: String(cString: kstaskrole_toString(role)))
    }

}
