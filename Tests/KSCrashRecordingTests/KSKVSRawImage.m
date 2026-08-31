//
//  KSKVSRawImage.m
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

#import "KSKVSRawImage.h"

// The record format, from KSKeyValueStore.c: magic "kskv" little-endian, a
// 12-byte file header of magic, version and write cursor, then records of
// key length (2), type (1), value length (2), key bytes, value bytes.
static const uint32_t kMagic = 0x6B736B76u;
static const uint32_t kVersion = 1;
static const uint32_t kHeaderSize = 12;

void kskvstest_appendRecord(NSMutableData *records, NSString *key, uint8_t type, NSData *value)
{
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    uint16_t keyLen = (uint16_t)keyData.length;
    uint16_t valueLen = (uint16_t)value.length;
    [records appendBytes:&keyLen length:sizeof(keyLen)];
    [records appendBytes:&type length:sizeof(type)];
    [records appendBytes:&valueLen length:sizeof(valueLen)];
    [records appendData:keyData];
    [records appendData:value];
}

NSData *kskvstest_storeImage(void (^records)(NSMutableData *records))
{
    NSMutableData *body = [NSMutableData data];
    if (records) {
        records(body);
    }

    NSMutableData *image = [NSMutableData data];
    uint32_t magic = kMagic;
    uint32_t version = kVersion;
    uint32_t offset = (uint32_t)(kHeaderSize + body.length);
    [image appendBytes:&magic length:sizeof(magic)];
    [image appendBytes:&version length:sizeof(version)];
    [image appendBytes:&offset length:sizeof(offset)];
    [image appendData:body];
    return image;
}
