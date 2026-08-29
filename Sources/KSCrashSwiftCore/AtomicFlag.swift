//
//  AtomicFlag.swift
//
//  Created by Alexander Cohen on 2026-07-19.
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

import KSCrashCore

/// A boolean readable and writable without a lock, backed by the C11 atomic cell in
/// `KSAtomicFlag.h`. Reads use relaxed ordering, so the flag guards nothing but itself.
///
/// The cell is heap-allocated because the atomic needs a stable address; Swift makes no such
/// promise for a stored property.
public final class AtomicFlag {
    private let cell = UnsafeMutablePointer<KSAtomicFlag>.allocate(capacity: 1)

    public init(_ value: Bool = false) {
        cell.initialize(to: KSAtomicFlag())
        ksatomicflag_set(cell, value)
    }

    deinit {
        cell.deinitialize(count: 1)
        cell.deallocate()
    }

    public var value: Bool {
        get { ksatomicflag_get(cell) }
        set { ksatomicflag_set(cell, newValue) }
    }
}
