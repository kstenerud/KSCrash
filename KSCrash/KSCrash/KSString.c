//
//  KSString.m
//
//  Created by Karl Stenerud on 2012-09-15.
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


#include "KSString.h"


// Compiler hints for "if" statements
#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))

static const int g_printableControlChars[0x20] =
{
    // Only tab, CR, and LF are considered printable
    // 1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

static const int g_continuationByteCount[0x40] =
{
    /*
     --0xxxxx = 1 (00-1f)
     --10xxxx = 2 (20-2f)
     --110xxx = 3 (30-37)
     --1110xx = 4 (38-3b)
     --11110x = 5 (3c-3d)
     */
    // 1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 0, 0,
};

bool kstring_isNullTerminatedUTF8String(const void* memory,
                                        int minLength,
                                        int maxLength)
{
    const unsigned char* ptr = memory;
    const unsigned char* const end = ptr + maxLength;

    for(; ptr < end; ptr++)
    {
        unsigned char ch = *ptr;
        unlikely_if(ch == 0)
        {
            return (ptr - (const unsigned char*)memory) >= minLength;
        }
        unlikely_if(ch & 0x80)
        {
            unlikely_if((ch & 0xc0) != 0xc0)
            {
                return false;
            }
            int continuationBytes = g_continuationByteCount[ch & 0x3f];
            unlikely_if(continuationBytes == 0 || ptr + continuationBytes >= end)
            {
                return false;
            }
            for(int i = 0; i < continuationBytes; i++)
            {
                ptr++;
                unlikely_if((*ptr & 0xc0) != 0x80)
                {
                    return false;
                }
            }
        }
        else unlikely_if(ch < 0x20 && !g_printableControlChars[ch])
        {
            return false;
        }
    }
    return false;
}
