//
//  KSReportWriter.h
//
//  Created by Karl Stenerud on 12-01-28.
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


#ifndef HDR_KSReportWriter_h
#define HDR_KSReportWriter_h

#ifdef __cplusplus
extern "C" {
#endif


#include <stdbool.h>


/**
 * Encapsulates report writing functionality.
 */
typedef struct KSReportWriter
{
    /** Add a boolean element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*addBooleanElement)(const struct KSReportWriter* writer,
                              const char* name,
                              bool value);
    
    /** Add a floating point element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*addFloatingPointElement)(const struct KSReportWriter* writer,
                                    const char* name,
                                    double value);
    
    /** Add an integer element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*addIntegerElement)(const struct KSReportWriter* writer,
                              const char* name,
                              long long value);
    
    /** Add an unsigned integer element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*addUIntegerElement)(const struct KSReportWriter* writer,
                               const char* name,
                               unsigned long long value);
    
    /** Add a string element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value The value to add.
     */
    void (*addStringElement)(const struct KSReportWriter* writer,
                             const char* name,
                             const char* value);
    
    /** Add a string element from a text file to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param filePath The path to the file containing the value to add.
     */
    void (*addTextFileElement)(const struct KSReportWriter* writer,
                               const char* name,
                               const char* filePath);
    
    /** Add a UUID element to the report.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     *
     * @param value A pointer to the binary UUID data.
     */
    void (*addUUIDElement)(const struct KSReportWriter* writer,
                           const char* name,
                           const unsigned char* value);
    
    /** Begin a new object container.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     */
    void (*beginObject)(const struct KSReportWriter* writer,
                        const char* name);
    
    /** Begin a new array container.
     *
     * @param writer This writer.
     *
     * @param name The name to give this element.
     */
    void (*beginArray)(const struct KSReportWriter* writer,
                       const char* name);
    
    /** Leave the current container, returning to the next higher level
     *  container.
     *
     * @param writer This writer.
     */
    void (*endContainer)(const struct KSReportWriter* writer);
    
    /** Internal contextual data for the writer */
    void* context;
    
} KSReportWriter;

typedef void (*KSReportWriteCallback)(const KSReportWriter* writer);

#ifdef __cplusplus
}
#endif

#endif // HDR_KSReportWriter_h

