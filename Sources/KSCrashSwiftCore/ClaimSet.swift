//
//  ClaimSet.swift
//
//  Created by Alexander Cohen on 2026-11-03.
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

/// Keys held by whoever claimed them first. A caller that finds a key already
/// claimed does not wait for it: the claim's holder owns that work, and the
/// caller moves on without it.
public final class ClaimSet<Key: Hashable & Sendable>: Sendable {
    private let claimed = UnfairLock(Set<Key>())

    public init() {}

    /// Claims `key`, returning false when another caller already holds it.
    public func claim(_ key: Key) -> Bool {
        claimed.withLock { $0.insert(key).inserted }
    }

    /// Releases `key` so it can be claimed again.
    public func release(_ key: Key) {
        claimed.withLock { _ = $0.remove(key) }
    }
}
