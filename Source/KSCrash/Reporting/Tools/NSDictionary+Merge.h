//
//  NSDictionary+Merge.h
//
//  Created by Karl Stenerud on 2012-10-01.
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


/** Adds dictionary merging capabilities.
 */
@interface NSDictionary (KSMerge)

/** Recursively merge this dictionary into the destination dictionary.
 * If the same key exists in both dictionaries, the following occurs:
 * - If both entries are dictionaries, the sub-dictionaries are merged and
 *   placed into the merged dictionary.
 * - Otherwise the entry from this dictionary overrides the entry from the
 *   destination in the merged dictionary.
 *
 * Note: Neither this dictionary nor the destination will be modified by this
 *       operation.
 *
 * @param dest The dictionary to merge into. Can be nil or empty, in which case
 *             this dictionary is returned.
 *
 * @return The merged dictionary.
 */
- (NSDictionary*) mergedInto:(NSDictionary*) dest;

@end
