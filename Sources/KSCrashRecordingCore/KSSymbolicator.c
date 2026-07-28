//
//  KSSymbolicator.c
//
//  Copyright (c) 2016 Karl Stenerud. All rights reserved.
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

#include "KSSymbolicator.h"

#include "KSDynamicLinker.h"

/** Step backwards by one instruction.
 * The backtrace of an objective-C program is expected to contain return
 * addresses not call instructions, as that is what can easily be read from
 * the stack. This is not a problem except for a few cases where the return
 * address is inside a different symbol than the call address.
 *
 * On armv7 the least significant bit of the pointer distinguishes between thumb
 * mode (2-byte instructions) and normal mode (4-byte instructions), so it is a
 * tag and has to be cleared before stepping back.
 *
 * Everywhere else every bit of the address is significant. On arm64 in particular
 * instructions are 4-byte aligned, so a real instruction address never has its low
 * bits set, and backtrace_async() uses that spare encoding deliberately: Swift async
 * continuation addresses are reported biased by +1 so that this same step back by one
 * lands on the continuation funclet's first instruction. Masking those bits off first
 * would consume the bias and then step back a second time, resolving one byte below
 * the funclet, i.e. to whatever symbol happens to precede it.
 *
 * Pointer tags and PAC bits are stripped a layer up, by kscpu_normaliseInstructionPointer().
 */
uintptr_t kssymbolicator_callInstructionAddress(const uintptr_t returnAddress)
{
#if defined(__arm__)
    return (returnAddress & ~(1UL)) - 1;
#else
    return returnAddress - 1;
#endif
}

bool kssymbolicator_symbolicate(KSStackCursor *cursor)
{
    Dl_info symbolsBuffer;
    if (ksdl_dladdr(kssymbolicator_callInstructionAddress(cursor->stackEntry.address), &symbolsBuffer)) {
        cursor->stackEntry.imageAddress = (uintptr_t)symbolsBuffer.dli_fbase;
        cursor->stackEntry.imageName = symbolsBuffer.dli_fname;
        cursor->stackEntry.symbolAddress = (uintptr_t)symbolsBuffer.dli_saddr;
        cursor->stackEntry.symbolName = symbolsBuffer.dli_sname;
        return true;
    }

    cursor->stackEntry.imageAddress = 0;
    cursor->stackEntry.imageName = 0;
    cursor->stackEntry.symbolAddress = 0;
    cursor->stackEntry.symbolName = 0;
    return false;
}
