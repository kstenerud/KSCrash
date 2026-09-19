//
//  PublicSurfaceTests.swift
//
//  Created by Alexander Cohen on 2026-07-14.
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

import KSCrashMonitorPlugins
import XCTest

// Compiles against only the public surface: what a third-party monitor sees.
final class PublicSurfaceTests: XCTestCase {
    final class ThirdPartyMonitor: CrashMonitor {
        static let id = "ThirdParty"
        struct Configuration { var flag = false }
        let host: MonitorHost<Void>
        let configuration: Configuration
        init(host: MonitorHost<Void>, configuration: Configuration) {
            self.host = host
            self.configuration = configuration
        }
    }

    func testPluginRegistrationShapeCompilesAndInstantiates() {
        let bridge = ThirdPartyMonitor.plugin(.init(flag: true))
        XCTAssertTrue(bridge.monitor.configuration.flag)
        XCTAssertFalse(bridge.isInstalled)
        XCTAssertFalse(bridge.monitor.host.isEnabled)
    }
}
