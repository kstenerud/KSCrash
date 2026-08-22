//
//  MetadataStore.swift
//
//  Created by Alexander Cohen on 2026-08-22.
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

/// Keyed access to scalar metadata: `String`, `Bool`, `Int`, `Int64`,
/// `UInt64`, `Double`, and `Date`. Conformers are a report's `Metadata` and
/// the live store on `KSCrash`.
public protocol MetadataStore {
    /// Reads or writes the value under `key`. Assigning nil removes the key;
    /// reading a key that holds another type yields nil.
    subscript<Value: MetadataValueRepresentable>(key: String) -> Value? { get set }

    /// Removes any value under `key`.
    mutating func removeValue(forKey key: String)

    /// The keys that currently hold a value, sorted.
    var keys: [String] { get }
}
