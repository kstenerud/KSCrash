//
//  KSCxaThrowBenchmarkSymbols.c
//
//  Created by Alexander Cohen on 2026-11-25.
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

// 20,000 empty global functions that give the benchmark bundle a symbol table the
// size of a large app framework. The throw benchmarks throw from this bundle, so a
// per-throw lookup in the swapped __cxa_throw that scales with the throwing image's
// symbol count (dladdr's nearest-symbol scan did) shows up as a gap between
// ThrowWithSwap and ThrowWithoutSwap.
//
// `used` keeps Release dead-stripping from removing them. The names must not contain
// "test": BrowserStack discovers tests by grepping the bundle's global symbols for it.

// clang-format off
#define KSBENCH_FILLER_1(n) __attribute__((used)) void ksbench_cxa_filler_##n(void) {}
#define KSBENCH_FILLER_10(n) \
    KSBENCH_FILLER_1(n##0) KSBENCH_FILLER_1(n##1) KSBENCH_FILLER_1(n##2) KSBENCH_FILLER_1(n##3) \
    KSBENCH_FILLER_1(n##4) KSBENCH_FILLER_1(n##5) KSBENCH_FILLER_1(n##6) KSBENCH_FILLER_1(n##7) \
    KSBENCH_FILLER_1(n##8) KSBENCH_FILLER_1(n##9)
#define KSBENCH_FILLER_100(n) \
    KSBENCH_FILLER_10(n##0) KSBENCH_FILLER_10(n##1) KSBENCH_FILLER_10(n##2) KSBENCH_FILLER_10(n##3) \
    KSBENCH_FILLER_10(n##4) KSBENCH_FILLER_10(n##5) KSBENCH_FILLER_10(n##6) KSBENCH_FILLER_10(n##7) \
    KSBENCH_FILLER_10(n##8) KSBENCH_FILLER_10(n##9)
#define KSBENCH_FILLER_1000(n) \
    KSBENCH_FILLER_100(n##0) KSBENCH_FILLER_100(n##1) KSBENCH_FILLER_100(n##2) KSBENCH_FILLER_100(n##3) \
    KSBENCH_FILLER_100(n##4) KSBENCH_FILLER_100(n##5) KSBENCH_FILLER_100(n##6) KSBENCH_FILLER_100(n##7) \
    KSBENCH_FILLER_100(n##8) KSBENCH_FILLER_100(n##9)
#define KSBENCH_FILLER_10000(n) \
    KSBENCH_FILLER_1000(n##0) KSBENCH_FILLER_1000(n##1) KSBENCH_FILLER_1000(n##2) KSBENCH_FILLER_1000(n##3) \
    KSBENCH_FILLER_1000(n##4) KSBENCH_FILLER_1000(n##5) KSBENCH_FILLER_1000(n##6) KSBENCH_FILLER_1000(n##7) \
    KSBENCH_FILLER_1000(n##8) KSBENCH_FILLER_1000(n##9)

KSBENCH_FILLER_10000(0)
KSBENCH_FILLER_10000(1)
// clang-format on
