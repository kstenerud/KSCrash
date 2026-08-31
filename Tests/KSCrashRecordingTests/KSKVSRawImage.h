//
//  KSKVSRawImage.h
//
//  Created by Alexander Cohen on 2026-08-30.
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

#import <Foundation/Foundation.h>

/** Append one record to a store image: the record header (key length, type,
 *  value length) followed by the key and value bytes.
 *
 *  For records the API cannot write: an unknown type, or a payload that does
 *  not match its type. Restating the on-disk layout per test meant several
 *  copies of it that a change to KSKVSRecordHeader would have to find.
 */
void kskvstest_appendRecord(NSMutableData *records, NSString *key, uint8_t type, NSData *value);

/** A whole store image: the file header with its write cursor covering
 *  whatever `records` appended.
 */
NSData *kskvstest_storeImage(void (^records)(NSMutableData *records));
