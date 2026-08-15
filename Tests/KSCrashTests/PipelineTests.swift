//
//  PipelineTests.swift
//
//  Created by Alexander Cohen on 2026-08-09.
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

import KSCrash
import XCTest

final class PipelineTests: XCTestCase {
    private struct Payload: Codable, Sendable, Equatable {
        var id: String
    }

    private struct Pass: PipelineStage {
        func process(_ payload: Payload) async throws -> Payload? { payload }
    }
    private struct Rename: PipelineStage {
        let to: String
        func process(_ payload: Payload) async throws -> Payload? {
            var payload = payload
            payload.id = to
            return payload
        }
    }
    private struct Drop: PipelineStage {
        func process(_ payload: Payload) async throws -> Payload? { nil }
    }

    func test_eraser_forwardsContinue() async throws {
        let stage = AnyPipelineStage(Rename(to: "changed"))
        let out = try await stage.process(Payload(id: "orig"))
        XCTAssertEqual(out, Payload(id: "changed"))
    }

    func test_eraser_forwardsDrop() async throws {
        let stage = AnyPipelineStage(Drop())
        let out = try await stage.process(Payload(id: "orig"))
        XCTAssertNil(out)
    }

    // Compile + wiring check: a RunSummary pipeline holds erased stages.
    private struct DropSummary: PipelineStage {
        func process(_ payload: RunSummary) async throws -> RunSummary? { nil }
    }

    func test_configuration_holdsRunSummaryPipeline() {
        let config = SendConfiguration(runSummaryPipeline: [AnyPipelineStage(DropSummary())])
        XCTAssertEqual(config.runSummaryPipeline.count, 1)
    }
}
