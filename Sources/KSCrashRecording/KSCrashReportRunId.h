//
//  KSCrashReportRunId.h
//
//  Created by Alexander Cohen on 2026-03-22.
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

#ifndef KSCrashReportRunId_h
#define KSCrashReportRunId_h

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Extract the run_id from a report file.
 *
 * Reads the file and parses its JSON with a streaming C decoder,
 * stopping as soon as report["report"]["run_id"] is found or the
 * report section ends. Falls back to a full ObjC decode if the
 * streaming path fails on oversized keys/strings. The run_id must
 * be a valid UUID.
 *
 * @param reportPath Path to the report JSON file.
 * @param runIdOut Buffer to receive the UUID string.
 * @param runIdOutLen Size of the buffer (must be > 36).
 *
 * @return true if a valid UUID run_id was extracted, false otherwise.
 */
bool kscrs_extractRunIdFromReportFile(const char *reportPath, char *runIdOut, size_t runIdOutLen);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashReportRunId_h
