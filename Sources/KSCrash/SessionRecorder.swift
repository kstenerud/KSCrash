//
//  SessionRecorder.swift
//
//  Created by Alexander Cohen on 2025-12-14.
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
import KSCrashRecording
import KSCrashRecordingCore
import KSCrashSwiftCore

/// Owns the run's live `.sessions` writer: a session is one contiguous
/// segment of the run at a single (perceptible, user) setting, and the
/// recorder cuts a new one whenever either changes. Cuts land in the
/// crash-safe append-only file immediately; the send path and the stitches
/// read the file, never this object.
final class SessionRecorder: @unchecked Sendable {
    private struct State {
        var writer: OpaquePointer?
        var observer: AnyObject?
    }

    private let state = UnfairLock(State())

    /// Opens the writer at `path` (the file itself opens on the first cut),
    /// records the launch session at the tracker's current perceptibility,
    /// and follows transitions from then on. Called once by install.
    func attach(path: String) {
        state.withLock { state in
            guard state.writer == nil, let writer = kssw_open(path) else { return }
            state.writer = writer
            kssw_updatePerceptible(
                writer,
                ksapp_transitionStateIsUserPerceptible(AppStateTracker.shared.transitionState))
            state.observer =
                AppStateTracker.shared.addObserver { [weak self] transitionState in
                    self?.observeTransition(transitionState)
                } as AnyObject
        }
    }

    /// A perceptibility change cuts a session, keeping the open session's
    /// user; the writer no-ops when nothing changed.
    func observeTransition(_ transitionState: KSCrashAppTransitionState) {
        state.withLock { state in
            guard let writer = state.writer else { return }
            kssw_updatePerceptible(writer, ksapp_transitionStateIsUserPerceptible(transitionState))
        }
    }

    /// A user change cuts a session, keeping the open session's
    /// perceptibility; nil means anonymous, and logout is still a cut.
    func observeUser(_ userID: String?) {
        state.withLock { state in
            guard let writer = state.writer else { return }
            kssw_updateUser(writer, userID)
        }
    }

    /// The open session's id; nil before install or before the first cut.
    var currentSessionID: String? {
        state.withLock { state in
            guard let writer = state.writer, let id = kssw_current(writer) else { return nil }
            return String(cString: id)
        }
    }

    /// Closes the writer and stops following transitions. Test support; a
    /// process's recorder otherwise lives as long as the process.
    func detach() {
        state.withLock { state in
            state.observer = nil
            if let writer = state.writer {
                kssw_close(writer)
                state.writer = nil
            }
        }
    }
}
