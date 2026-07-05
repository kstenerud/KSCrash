//
//  CrashReportExtensionMonitor+Implementation.swift
//
//  Created by Alexander Cohen on 2026-07-04.
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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashRecordingCore

extension CrashReportExtensionMonitor {

    struct CaptureFailure: Error {}

    /// Writes a standard crash report for `corpse` through the normal report pipeline, into the
    /// installed store. Returns the new report's ID.
    ///
    /// `crashedThreadID` is the kernel thread id the corpse's crash info reports; `images` is the
    /// CrashedProcess.binaryImages list in our shape. `signal` is the kcdata-decoded signal when
    /// the corpse's crash record carries one (EXC_CRASH packs the true signal in its code, which
    /// the mach-exception mapping alone cannot recover); `processName` names the corpse's process
    /// in the report header; `snapshot` is what writeReportSection embeds in the report's error
    /// section. The report is stamped with this process's current run ID, so load the crashed
    /// run's ID first (`kscrash_loadRunIDFromCorpse`).
    func writeReport(
        corpse: mach_port_t, crashedThreadID: UInt64, images: [CorpseSnapshot.Image],
        exception: Int32, code: UInt64, subcode: UInt64,
        signal: Int32? = nil, processName: String? = nil, snapshot: CorpseSnapshot? = nil
    ) throws -> Int64 {
        // The corpse's unwind tables, read out of the corpse by way of the provided image list.
        let ownedPaths = images.map { strdup($0.path) }
        let ownedProcessName = processName.flatMap { strdup($0) }
        // A corpse capture is a mach exception at heart; overriding the error type makes the
        // report read like one the in-process Mach monitor wrote instead of a custom type.
        let ownedErrorType = strdup(ExceptionType.mach.rawValue)
        defer {
            for path in ownedPaths { free(path) }
            free(ownedProcessName)
            free(ownedErrorType)
        }
        var descriptors = zip(images, ownedPaths).map { image, path in
            KSBinaryImageDescriptor(loadAddress: UInt(image.baseAddress), name: UnsafePointer(path))
        }
        guard let imageSet = ksbic_createSetFromTaskImages(corpse, &descriptors, UInt32(descriptors.count)) else {
            throw CaptureFailure()
        }
        defer { ksbic_destroySet(imageSet) }

        // The machine context over the corpse: thread list, crashed thread resolved by kernel
        // thread id, registers. One task_threads pass inside; port rights follow the machinery's
        // convention (kept for a remote task, dropped in-process).
        var machineContext = KSMachineContext()
        guard ksmc_getContextForTaskThread(corpse, imageSet, crashedThreadID, &machineContext) else {
            throw CaptureFailure()
        }

        // The report's binary images section must list the corpse's images, not this
        // process's; symbolication resolves the corpse's frames against it.
        let ownedUUIDs: [UnsafeMutablePointer<UInt8>?] = images.map { image in
            guard let uuidString = image.uuid, let uuid = UUID(uuidString: uuidString) else { return nil }
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 16)
            withUnsafeBytes(of: uuid.uuid) { raw in
                bytes.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: 16)
            }
            return bytes
        }
        defer {
            for uuid in ownedUUIDs { uuid?.deallocate() }
        }
        let providedImages = zip(images, zip(ownedPaths, ownedUUIDs)).map { image, owned in
            var provided = KSBinaryImage()
            // The extension hands us a load address, a size and a uuid and nothing else, and the
            // size is untrustworthy for shared-cache images (it is computed to the end of the
            // cache, gigabytes past the image, which wrecks server-side frame attribution). The
            // corpse's own header knows the real size, and is the only source for the vmaddr and
            // the version triple. vmAddress especially must not be left at zero: symbolication
            // derives the slide as address - vmAddress, so a zero there misplaces every frame.
            if !ksbic_fillTaskImage(corpse, UInt(image.baseAddress), &provided) {
                // No readable header: fall back to what we were handed.
                provided.address = image.baseAddress
                provided.size = image.size
            }
            provided.name = UnsafePointer(owned.0)
            provided.uuid = UnsafePointer(owned.1)
            provided.cpuType = image.cpuType
            provided.cpuSubType = image.cpuSubType
            return provided
        }

        return try withUnsafeMutablePointer(to: &machineContext) { machineContextPointer in
            try providedImages.withUnsafeBufferPointer { imageBuffer in
                // A nil snapshot writes the report without the monitor's snapshot section.
                try host.handle(payload: snapshot, requirements: .fatalRemoteSubject) { context in
                    context.pointee.offendingMachineContext = machineContextPointer
                    context.pointee.registersAreValid = true
                    context.pointee.mach.type = exception
                    context.pointee.mach.code = Int64(bitPattern: code)
                    context.pointee.mach.subcode = Int64(bitPattern: subcode)
                    // Only the kcdata-decoded signal is set here (EXC_CRASH packs the true
                    // signal in its code); left 0, the report writer derives it from
                    // mach.type/code.
                    context.pointee.signal.signum = signal ?? 0
                    // Same rule as the Mach monitor's handler (KSCrashMonitor_MachException.c):
                    // EXC_BAD_ACCESS reports the fault register, everything else the
                    // instruction pointer.
                    context.pointee.faultAddress =
                        exception == EXC_BAD_ACCESS
                        ? kscpu_faultAddress(machineContextPointer) : kscpu_instructionAddress(machineContextPointer)
                    context.pointee.providedBinaryImages = imageBuffer.baseAddress
                    context.pointee.providedBinaryImageCount = Int32(imageBuffer.count)
                    context.pointee.processName = UnsafePointer(ownedProcessName)
                    context.pointee.errorTypeOverride = UnsafePointer(ownedErrorType)
                }.id
            }
        }
    }
}
