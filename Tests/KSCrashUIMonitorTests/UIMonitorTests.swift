//
//  UIMonitorTests.swift
//
//  Created by Alexander Cohen on 2026-11-22.
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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashTestTools
import KSCrashUIMonitor
import ObjectiveC
import XCTest

#if os(iOS) || os(tvOS) || os(visionOS)
    import UIKit
#endif

final class UIMonitorTests: XCTestCase {
    private var sidecarPath = ""
    private var plugin: (any MonitorPlugin)!

    override func setUp() {
        super.setUp()
        sidecarPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        resourcetest_arm(sidecarPath)
        plugin = UIMonitor.plugin()
    }

    override func tearDown() {
        setEnabled(false)
        plugin = nil
        resourcetest_disarm()
        try? FileManager.default.removeItem(atPath: sidecarPath)
        super.tearDown()
    }

    private func setEnabled(_ isEnabled: Bool) {
        plugin.api.pointee.setEnabled(isEnabled, plugin.api.pointee.context)
    }

    private var isEnabled: Bool { plugin.api.pointee.isEnabled(plugin.api.pointee.context) }

    private func readSidecar() throws -> ResourceTestSnapshot {
        var snapshot = ResourceTestSnapshot()
        XCTAssertTrue(resourcetest_read(sidecarPath, &snapshot))
        return snapshot
    }

    func testIdentity() {
        let api = plugin.api
        XCTAssertEqual(api.pointee.monitorId(api.pointee.context).map { String(cString: $0) }, "UI")
        XCTAssertEqual(api.pointee.monitorFlags(api.pointee.context), .plugin)
        XCTAssertTrue(kscma_hasRequiredCallbacks(api))
    }

    func testEnableAndDisable() {
        XCTAssertFalse(isEnabled)
        setEnabled(true)
        XCTAssertTrue(isEnabled)
        setEnabled(false)
        XCTAssertFalse(isEnabled)
    }

    /// Linking the module is what starts the tracker, so the loader's +load has to be in the binary.
    func testLoaderHasALoadMethod() throws {
        let loader: AnyClass = try XCTUnwrap(NSClassFromString("KSCrashUIMonitorLoader"))
        let metaclass: AnyClass = try XCTUnwrap(object_getClass(loader))
        var count: UInt32 = 0
        let methods = try XCTUnwrap(class_copyMethodList(metaclass, &count))
        defer { free(methods) }
        let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }
        XCTAssertTrue(names.contains("load"))
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
        /// The test runner has no application object, as an app has none before UIApplicationMain.
        /// The value stays unread rather than taking the false a message to nil returns, and a launch
        /// notification that still finds no object leaves it unread.
        func testProtectedDataIsLeftUnreadWithoutAnApplication() throws {
            guard unsafeBitCast(UIApplication.shared, to: UIApplication?.self) == nil else {
                throw XCTSkip("This runner has an application object")
            }
            setEnabled(true)
            XCTAssertEqual(try readSidecar().dataProtectionUpdatedAtNs, 0)
            NotificationCenter.default.post(name: UIApplication.didFinishLaunchingNotification, object: nil)
            XCTAssertEqual(try readSidecar().dataProtectionUpdatedAtNs, 0)
        }
    #endif

    #if os(iOS)
        private func assertBatteryMatchesTheDevice(file: StaticString = #filePath, line: UInt = #line) throws {
            let device = UIDevice.current
            let level = device.batteryLevel
            let snapshot = try readSidecar()
            XCTAssertEqual(snapshot.batteryLevel, level < 0 ? 255 : UInt8(level * 100), file: file, line: line)
            XCTAssertEqual(snapshot.batteryState, UInt8(device.batteryState.rawValue), file: file, line: line)
            XCTAssertGreaterThan(snapshot.batteryUpdatedAtNs, 0, file: file, line: line)
        }

        /// Whether a battery notification gets recorded, which is whether the observers are installed.
        private func batteryNotificationIsRecorded() throws -> Bool {
            let before = try readSidecar().batteryUpdatedAtNs
            NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification, object: nil)
            return try readSidecar().batteryUpdatedAtNs != before
        }

        /// Enables from a thread of its own while the main thread waits without turning its run loop,
        /// so nothing the enable posts to the main queue can run before this returns.
        /// (`DispatchQueue.sync` from the main thread would run the block on the main thread.)
        private func enableOnAnotherThread() {
            let condition = NSCondition()
            var done = false
            let api = plugin.api
            let thread = Thread {
                api.pointee.setEnabled(true, api.pointee.context)
                condition.lock()
                done = true
                condition.signal()
                condition.unlock()
            }
            thread.start()
            condition.lock()
            while !done { condition.wait() }
            condition.unlock()
        }

        private func turnTheMainQueue() {
            let turned = expectation(description: "main queue turned")
            DispatchQueue.main.async { turned.fulfill() }
            wait(for: [turned], timeout: 5)
        }

        func testEnablingOnTheMainThreadRecordsTheBatteryBeforeReturning() throws {
            setEnabled(true)
            try assertBatteryMatchesTheDevice()
            XCTAssertTrue(try batteryNotificationIsRecorded())
        }

        func testDisablingStopsFollowingTheBattery() throws {
            setEnabled(true)
            setEnabled(false)
            XCTAssertFalse(try batteryNotificationIsRecorded())
        }

        func testEnablingOffTheMainThreadRecordsTheBatteryOnTheMainQueue() throws {
            // The Resource monitor stamps its own default at enable.
            let seeded = try readSidecar().batteryUpdatedAtNs
            enableOnAnotherThread()
            XCTAssertEqual(try readSidecar().batteryUpdatedAtNs, seeded)

            turnTheMainQueue()
            XCTAssertNotEqual(try readSidecar().batteryUpdatedAtNs, seeded)
            try assertBatteryMatchesTheDevice()
            XCTAssertTrue(try batteryNotificationIsRecorded())
        }

        /// An enable posted from another thread runs after a disable made on the main thread, and the
        /// monitor still ends disabled.
        func testAnOffMainEnableOvertakenByADisableEndsDisabled() throws {
            let seeded = try readSidecar().batteryUpdatedAtNs
            enableOnAnotherThread()
            setEnabled(false)
            turnTheMainQueue()

            XCTAssertFalse(isEnabled)
            XCTAssertEqual(try readSidecar().batteryUpdatedAtNs, seeded)
            XCTAssertFalse(try batteryNotificationIsRecorded())
        }
    #endif
}
