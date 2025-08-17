//
//  KSCrashReportWriter.h
//
//  Created by Karl Stenerud on 2012-01-28.
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

/* Pointers to functions for writing to a crash report. All JSON types are
 * supported.
 */

#ifndef HDR_KSCrashReportWriter_h
#define HDR_KSCrashReportWriter_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashExceptionHandlingPolicy.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashNamespace.h"

#ifdef __OBJC__
#include <Foundation/Foundation.h>
#endif

#ifndef NS_SWIFT_NAME
#define NS_SWIFT_NAME(_name)
#endif

#ifndef NS_SWIFT_UNAVAILABLE
#define NS_SWIFT_UNAVAILABLE(_msg)
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Encapsulates report writing functionality.
 */
typedef struct KSCrashReportWriter {
    /** Add a boolean element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*_Nonnull addBooleanElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                       bool value);

    /** Add a floating point element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*_Nonnull addFloatingPointElement)(const struct KSCrashReportWriter *_Nonnull writer,
                                             const char *_Nullable name, double value);

    /** Add an integer element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*_Nonnull addIntegerElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                       int64_t value);

    /** Add an unsigned integer element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*_Nonnull addUIntegerElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                        uint64_t value);

    /** Add a string element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*_Nonnull addStringElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                      const char *_Nullable value);

    /** Add a string element from a text file to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param filePath The path to the file containing the value to add.
     */
    void (*_Nonnull addTextFileElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                        const char *_Nonnull filePath);

    /** Add an array of string elements representing lines from a text file to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param filePath The path to the file containing the value to add.
     */
    void (*_Nonnull addTextFileLinesElement)(const struct KSCrashReportWriter *_Nonnull writer,
                                             const char *_Nullable name, const char *_Nonnull filePath);

    /** Add a JSON element from a text file to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param filePath The path to the file containing the value to add.
     *
     * @param closeLastContainer If false, do not close the last container.
     */
    void (*_Nonnull addJSONFileElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                        const char *_Nonnull filePath, const bool closeLastContainer);

    /** Add a hex encoded data element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value A pointer to the binary data.
     *
     * @paramn length The length of the data.
     */
    void (*_Nonnull addDataElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                    const char *_Nonnull value, const int length);

    /** Begin writing a hex encoded data element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     */
    void (*_Nonnull beginDataElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name);

    /** Append hex encoded data to the current data element in the report.
     *
     * @param writer This writer.
     *
     * @param value A pointer to the binary data.
     *
     * @paramn length The length of the data.
     */
    void (*_Nonnull appendDataElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nonnull value,
                                       const int length);

    /** Complete writing a hex encoded data element to the report.
     *
     * @param writer This writer.
     */
    void (*_Nonnull endDataElement)(const struct KSCrashReportWriter *_Nonnull writer);

    /** Add a UUID element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value A pointer to the binary UUID data.
     */
    void (*_Nonnull addUUIDElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                    const unsigned char *_Nullable value);

    /** Add a preformatted JSON element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param jsonElement A pointer to the JSON data.
     *
     * @param closeLastContainer If false, do not close the last container.
     */
    void (*_Nonnull addJSONElement)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name,
                                    const char *_Nonnull jsonElement, bool closeLastContainer);

    /** Begin a new object container.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     */
    void (*_Nonnull beginObject)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name);

    /** Begin a new array container.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     */
    void (*_Nonnull beginArray)(const struct KSCrashReportWriter *_Nonnull writer, const char *_Nullable name);

    /** Leave the current container, returning to the next higher level
     *  container.
     *
     * @param writer This writer.
     */
    void (*_Nonnull endContainer)(const struct KSCrashReportWriter *_Nonnull writer);

    /** Internal contextual data for the writer */
    void *_Nonnull context;

} NS_SWIFT_NAME(ReportWriter) KSCrashReportWriter;

/** Callback type for when a crash report is being written (DEPRECATED).
 *
 * @deprecated Use `KSReportWriteCallbackWithPolicy` for async-safety awareness (since v2.4.0).
 * This callback does not receive policy information and may not handle crash
 * scenarios safely.
 *
 * @param writer The report writer.
 */
typedef void (*KSReportWriteCallback)(const KSCrashReportWriter *_Nonnull writer)
    __attribute__((deprecated("Use `KSReportWriteCallbackWithPolicy` for async-safety awareness (since v2.4.0).")));

/** Callback type for when a crash report is finished writing (DEPRECATED).
 *
 * @deprecated Use `KSReportWrittenCallbackWithPolicy` for async-safety awareness (since v2.4.0).
 * This callback does not receive policy information and may not handle crash
 * scenarios safely.
 *
 * @param reportID The ID of the report that was written.
 */
typedef void (*KSReportWrittenCallback)(int64_t reportID)
    __attribute__((deprecated("Use `KSReportWrittenCallbackWithPolicy` for async-safety awareness (since v2.4.0).")));

/** Callback type for when a crash report is being written.
 *
 * @param policy The policy under which the report was written.
 * @param writer The report writer.
 */
typedef void (*KSReportWriteCallbackWithPolicy)(KSCrash_ExceptionHandlingPolicy policy,
                                                const KSCrashReportWriter *_Nonnull writer);

/** Callback type for when a crash report should be written.
 *
 * @param context The monitor context of the report.
 */
typedef void (*KSCrashEventNotifyCallback)(struct KSCrash_MonitorContext *_Nonnull context);

/** Callback type for when a crash report is finished writing.
 *
 * @param policy The policy under which the report was written.
 * @param reportID The ID of the report that was written.
 */
typedef void (*KSReportWrittenCallbackWithPolicy)(KSCrash_ExceptionHandlingPolicy policy, int64_t reportID);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashReportWriter_h
