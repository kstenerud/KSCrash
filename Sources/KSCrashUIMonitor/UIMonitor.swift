//
//  UIMonitor.swift
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

#if os(iOS) || os(tvOS) || os(visionOS)
    import UIKit
#endif

/// The UI monitor: records the battery's level and state, and whether
/// protected data is available, on reports. Register `UIMonitor.plugin()` in
/// `InstallConfiguration.plugins`.
///
/// Linking this module also starts the app-state tracker when the process
/// loads, so an app's reports see every transition from launch on.
///
/// For apps only: it reads the application object, which an app extension
/// does not have.
@available(iOSApplicationExtension, unavailable)
@available(tvOSApplicationExtension, unavailable)
@available(visionOSApplicationExtension, unavailable)
@available(macCatalystApplicationExtension, unavailable)
public final class UIMonitor: CrashMonitor, @unchecked Sendable {
    public static let id = "UI"

    private let host: MonitorHost<Void>

    /// Only touched on the main thread, where UIKit has to be read.
    @MainActor private var observers: [NSObjectProtocol]?

    /// Set while protected data waits for the launch to make the application object.
    @MainActor private var launchObserver: NSObjectProtocol?

    public init(host: MonitorHost<Void>, configuration: Void) {
        self.host = host
    }

    // Install runs on any thread, and UIKit is read on the main thread. On the main thread the
    // values are recorded before enabling returns; from another thread they land on the main
    // queue's next turn, and a report written before then goes without them.
    // Each pass applies whatever the flag says when it runs, so passes that land out of order
    // still leave the observers matching the last change.
    public func enabledDidChange(_ isEnabled: Bool) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { applyEnabledState() }
        } else {
            // Weak: the host reaches the bridge unowned, and a pass that outlives the bridge has
            // nothing left to apply.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.applyEnabledState() }
            }
        }
    }

    @MainActor private func applyEnabledState() {
        if host.isEnabled {
            guard observers == nil else { return }
            observers = Self.start()
            #if os(iOS) || os(tvOS) || os(visionOS)
                if !Self.recordProtectedData() {
                    waitForLaunch()
                }
            #endif
        } else {
            guard let started = observers else { return }
            Self.stop(started)
            observers = nil
            stopWaitingForLaunch()
        }
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
        /// Whether there was an application object to read.
        @MainActor private static func recordProtectedData() -> Bool {
            // `shared` is declared non-optional but is nil before UIApplicationMain.
            guard let application = unsafeBitCast(UIApplication.shared, to: UIApplication?.self) else {
                return false
            }
            // Only the starting value is needed; later changes are recorded without another call.
            kscm_resource_setProtectedDataAvailable(application.isProtectedDataAvailable)
            return true
        }

        // An install can run before UIApplicationMain has made the application object (a SwiftUI
        // app's initializer), where a read would message nil and record false. UIKit posts the launch
        // notification on the main thread once the object exists, so the read waits for it. No
        // queue, so the read lands before the launch goes on to draw anything.
        @MainActor private func waitForLaunch() {
            guard launchObserver == nil else { return }
            launchObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stopWaitingForLaunch()
                    _ = Self.recordProtectedData()
                }
            }
        }
    #endif

    @MainActor private func stopWaitingForLaunch() {
        guard let observer = launchObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        launchObserver = nil
    }

    @MainActor private static func start() -> [NSObjectProtocol] {
        #if os(iOS)
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            recordBattery(device)
            return [
                UIDevice.batteryLevelDidChangeNotification,
                UIDevice.batteryStateDidChangeNotification,
            ].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { recordBattery(UIDevice.current) }
                }
            }
        #else
            return []
        #endif
    }

    @MainActor private static func stop(_ observers: [NSObjectProtocol]) {
        observers.forEach(NotificationCenter.default.removeObserver)
        #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
    }

    #if os(iOS)
        @MainActor private static func recordBattery(_ device: UIDevice) {
            let level = device.batteryLevel
            let state: KSCrashBatteryState =
                switch device.batteryState {
                case .unplugged: KSCrashBatteryStateUnplugged
                case .charging: KSCrashBatteryStateCharging
                case .full: KSCrashBatteryStateFull
                default: KSCrashBatteryStateUnknown
                }
            kscm_resource_setBattery(level < 0 ? 255 : UInt8(level * 100), state)
        }
    #endif
}
