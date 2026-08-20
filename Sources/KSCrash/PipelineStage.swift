//
//  PipelineStage.swift
//
//  Created by Alexander Cohen on 2026-08-08.
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

/// A value that can travel through a send pipeline: encodable, and safe to hand across concurrency domains.
public typealias PipelineValue = Codable & Sendable

/// One stage of a send pipeline.
///
/// Return the payload, possibly modified, to pass it to the next stage; return nil
/// to discard it; or throw to leave it for a later send.
public protocol PipelineStage<Payload>: Sendable {
    associatedtype Payload: PipelineValue
    func process(_ payload: Payload) async throws -> Payload?
}

/// One payload through the stages, to the outcome the driver records for it
/// (and maps onto disk state: delete on delivered or discarded, keep on
/// kept). Per-item failures are deliberately turned into `.kept` so one
/// failing item cannot end a send.
func runPipeline<Payload: SendPayload>(
    _ payload: Payload, through stages: [AnyPipelineStage<Payload>]
) async -> SendResult<Payload>.Outcome {
    var payload = payload
    for stage in stages {
        do {
            guard let processed = try await stage.process(payload) else {
                return .discarded
            }
            payload = processed
        } catch {
            return .kept(error)
        }
    }
    return .delivered
}
