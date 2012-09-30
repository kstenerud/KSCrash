//
//  KSCrashReport.m
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


#include "KSCrashReport.h"

#include "KSBacktrace_Private.h"
#include "KSCrashReportWriter.h"
#include "KSFileUtils.h"
#include "KSJSONCodec.h"
#include "KSMach.h"
#include "KSObjC.h"
#include "KSSignalInfo.h"
#include "KSZombie.h"
#include "KSString.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <mach-o/dyld.h>
#include <malloc/malloc.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>


// Note: Avoiding static functions due to linker issues.


// ============================================================================
#pragma mark - Constants -
// ============================================================================

/** Version number written to the report. */
#define kReportVersionMajor 1
#define kReportVersionMinor 0

/** Maximum depth allowed for a backtrace. */
#define kMaxBacktraceDepth 50

/** Length at which we consider a backtrace to represent a stack overflow.
 * If it reaches this point, we start cutting off from the top of the stack
 * rather than the bottom.
 */
#define kStackOverflowThreshold 200

/** How far to search the stack (in pointer sized jumps) for notable data. */
#define kStackNotableSearchBackDistance 20
#define kStackNotableSearchForwardDistance 10

/** How much of the stack to dump (in pointer sized jumps). */
#define kStackContentsPushedDistance 20
#define kStackContentsPoppedDistance 10
#define kStackContentsTotalDistance (kStackContentsPushedDistance + kStackContentsPoppedDistance)

/** The minimum length for a valid string. */
#define kMinStringLength 4


// ============================================================================
#pragma mark - Formatting -
// ============================================================================

#if defined(__LP64__)
    #define TRACE_FMT         "%-4d%-31s 0x%016llx %s + %llu"
    #define POINTER_FMT       "0x%016llx"
    #define POINTER_SHORT_FMT "0x%llx"
#else
    #define TRACE_FMT         "%-4d%-31s 0x%08lx %s + %lu"
    #define POINTER_FMT       "0x%08lx"
    #define POINTER_SHORT_FMT "0x%lx"
#endif


// ============================================================================
#pragma mark - JSON Encoding -
// ============================================================================

#define getJsonContext(REPORT_WRITER) ((KSJSONEncodeContext*)((REPORT_WRITER)->context))

/** Used for writing hex string values. */
static const char g_hexNybbles[] =
{
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
};

#pragma mark Callbacks

void kscrw_i_addBooleanElement(const KSCrashReportWriter* const writer,
                               const char* const key,
                               const bool value)
{
    ksjson_addBooleanElement(getJsonContext(writer), key, value);
}

void kscrw_i_addFloatingPointElement(const KSCrashReportWriter* const writer,
                                     const char* const key,
                                     const double value)
{
    ksjson_addFloatingPointElement(getJsonContext(writer), key, value);
}

void kscrw_i_addIntegerElement(const KSCrashReportWriter* const writer,
                               const char* const key,
                               const long long value)
{
    ksjson_addIntegerElement(getJsonContext(writer), key, value);
}

void kscrw_i_addUIntegerElement(const KSCrashReportWriter* const writer,
                                const char* const key,
                                const unsigned long long value)
{
    ksjson_addIntegerElement(getJsonContext(writer), key, (long long)value);
}

void kscrw_i_addStringElement(const KSCrashReportWriter* const writer,
                              const char* const key,
                              const char* const value)
{
    if(key == NULL)
    {
        ksjson_addNullElement(getJsonContext(writer), key);
    }
    else
    {
        ksjson_addStringElement(getJsonContext(writer), key, value, strlen(value));
    }
}

void kscrw_i_addTextFileElement(const KSCrashReportWriter* const writer,
                                const char* const key,
                                const char* const filePath)
{
    const int fd = open(filePath, O_RDONLY);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open file %s: %s", filePath, strerror(errno));
        return;
    }

    if(ksjson_beginStringElement(getJsonContext(writer), key) != KSJSON_OK)
    {
        KSLOG_ERROR("Could not start string element");
        goto done;
    }

    char buffer[512];
    ssize_t bytesRead;
    for(bytesRead = read(fd, buffer, sizeof(buffer));
        bytesRead > 0;
        bytesRead = read(fd, buffer, sizeof(buffer)))
    {
        if(ksjson_appendStringElement(getJsonContext(writer),
                                      buffer,
                                      (size_t)bytesRead) != KSJSON_OK)
        {
            KSLOG_ERROR("Could not append string element");
            goto done;
        }
    }

done:
    ksjson_endStringElement(getJsonContext(writer));
    close(fd);
}

void kscrw_i_addDataElement(const KSCrashReportWriter* const writer,
                            const char* const key,
                            const char* const value,
                            const size_t length)
{
    ksjson_addDataElement(getJsonContext(writer), key, value, length);
}

void kscrw_i_beginDataElement(const KSCrashReportWriter* const writer,
                              const char* const key)
{
    ksjson_beginDataElement(getJsonContext(writer), key);
}

void kscrw_i_appendDataElement(const KSCrashReportWriter* const writer,
                               const char* const value,
                               const size_t length)
{
    ksjson_appendDataElement(getJsonContext(writer), value, length);
}

void kscrw_i_endDataElement(const KSCrashReportWriter* const writer)
{
    ksjson_endDataElement(getJsonContext(writer));
}

void kscrw_i_addUUIDElement(const KSCrashReportWriter* const writer,
                            const char* const key,
                            const unsigned char* const value)
{
    if(value == NULL)
    {
        ksjson_addNullElement(getJsonContext(writer), key);
    }
    else
    {
        char uuidBuffer[37];
        const unsigned char* src = value;
        char* dst = uuidBuffer;
        for(int i = 0; i < 4; i++)
        {
            *dst++ = g_hexNybbles[(*src>>4)&15];
            *dst++ = g_hexNybbles[(*src++)&15];
        }
        *dst++ = '-';
        for(int i = 0; i < 2; i++)
        {
            *dst++ = g_hexNybbles[(*src>>4)&15];
            *dst++ = g_hexNybbles[(*src++)&15];
        }
        *dst++ = '-';
        for(int i = 0; i < 2; i++)
        {
            *dst++ = g_hexNybbles[(*src>>4)&15];
            *dst++ = g_hexNybbles[(*src++)&15];
        }
        *dst++ = '-';
        for(int i = 0; i < 2; i++)
        {
            *dst++ = g_hexNybbles[(*src>>4)&15];
            *dst++ = g_hexNybbles[(*src++)&15];
        }
        *dst++ = '-';
        for(int i = 0; i < 6; i++)
        {
            *dst++ = g_hexNybbles[(*src>>4)&15];
            *dst++ = g_hexNybbles[(*src++)&15];
        }

        ksjson_addStringElement(getJsonContext(writer),
                                key,
                                uuidBuffer,
                                (size_t)(dst - uuidBuffer));
    }
}

void kscrw_i_addJSONElement(const KSCrashReportWriter* const writer,
                            const char* const key,
                            const char* const jsonElement)
{
    int jsonResult = ksjson_addJSONElement(getJsonContext(writer),
                                           key,
                                           jsonElement,
                                           strlen(jsonElement));
    if(jsonResult != KSJSON_OK)
    {
        char errorBuff[100];
        snprintf(errorBuff,
                 sizeof(errorBuff),
                 "Invalid JSON data: %s",
                 ksjson_stringForError(jsonResult));
        ksjson_beginObject(getJsonContext(writer), key);
        ksjson_addStringElement(getJsonContext(writer),
                                "error",
                                errorBuff,
                                strlen(errorBuff));
        ksjson_addStringElement(getJsonContext(writer),
                                "json_data",
                                jsonElement,
                                strlen(jsonElement));
        ksjson_endContainer(getJsonContext(writer));
    }
}

void kscrw_i_beginObject(const KSCrashReportWriter* const writer,
                         const char* const key)
{
    ksjson_beginObject(getJsonContext(writer), key);
}

void kscrw_i_beginArray(const KSCrashReportWriter* const writer,
                        const char* const key)
{
    ksjson_beginArray(getJsonContext(writer), key);
}

void kscrw_i_endContainer(const KSCrashReportWriter* const writer)
{
    ksjson_endContainer(getJsonContext(writer));
}

int kscrw_i_addJSONData(const char* const data,
                        const size_t length,
                        void* const userData)
{
    const int fd = *((int*)userData);
    const bool success = ksfu_writeBytesToFD(fd, data, (ssize_t)length);
    return success ? KSJSON_OK : KSJSON_ERROR_CANNOT_ADD_DATA;
}


// ============================================================================
#pragma mark - Utility -
// ============================================================================

/** Check if a memory address points to a valid null terminated UTF-8 string.
 *
 * @param address The address to check.
 *
 * @return true if the address points to a string.
 */
bool kscrw_i_isValidString(const void* const address)
{
    if((void*)address == NULL)
    {
        return false;
    }

    char buffer[500];
    if((uintptr_t)address+sizeof(buffer) < (uintptr_t)address)
    {
        // Wrapped around the address range.
        return false;
    }
    if(ksmach_copyMem(address, buffer, sizeof(buffer)) != KERN_SUCCESS)
    {
        return false;
    }
    return kstring_isNullTerminatedUTF8String(buffer,
                                              kMinStringLength,
                                              sizeof(buffer));
}

/** Get the name of a mach exception.
 *
 * It will fill the buffer with the exception name, or a number in the format
 * 0x00000000 if it couldn't identify the exception.
 *
 * @param machException The exception.
 *
 * @param buffer Buffer to hold the name.
 *
 * @param maxLength The length of the buffer.
 */
void kscrw_i_getMachExceptionName(const int machException,
                                  char* const buffer,
                                  const int maxLength)
{
    const char*const name = ksmach_exceptionName(machException);
    if(name == NULL)
    {
        snprintf(buffer, maxLength, POINTER_FMT, (unsigned long)machException);
    }
    else
    {
        strncpy(buffer, name, maxLength);
    }
}

/** Get the name of a mach exception code.
 *
 * It will fill the buffer with the code name, or a number in standard hex
 * format if it couldn't identify the exception code.
 *
 * @param machCode The mach exception code.
 *
 * @param buffer Buffer to hold the name.
 *
 * @param maxLength The length of the buffer.
 */
void kscrw_i_getMachCodeName(const int machCode,
                             char* const buffer,
                             const int maxLength)
{
    const char* name = ksmach_kernelReturnCodeName(machCode);
    if(machCode == 0 || name == NULL)
    {
        snprintf(buffer, maxLength, POINTER_FMT, (unsigned long)machCode);
    }
    else
    {
        strncpy(buffer, name, maxLength);
    }
}

/** Get all parts of the machine state required for a dump.
 * This includes basic thread state, and exception registers.
 *
 * @param thread The thread to get state for.
 *
 * @param machineContextBuffer The machine context to fill out.
 */
bool kscrw_i_fetchMachineState(const thread_t thread,
                               _STRUCT_MCONTEXT* const machineContextBuffer)
{
    if(!ksmach_threadState(thread, machineContextBuffer))
    {
        return false;
    }

    if(!ksmach_exceptionState(thread, machineContextBuffer))
    {
        return false;
    }

    return true;
}

/** Get the machine context for the specified thread.
 *
 * This function will choose how to fetch the machine context based on what kind
 * of thread it is (current, crashed, other), and what kind of crash occured.
 * It may store the context in machineContextBuffer unless it can be fetched
 * directly from memory. Do not count on machineContextBuffer containing
 * anything. Always use the return value.
 *
 * @param crash The crash handler context.
 *
 * @param thread The thread to get a machine context for.
 *
 * @param machineContextBuffer A place to store the context, if needed.
 *
 * @return A pointer to the crash context, or NULL if not found.
 */
_STRUCT_MCONTEXT* kscrw_i_getMachineContext(const KSCrash_SentryContext* const crash,
                                            const thread_t thread,
                                            _STRUCT_MCONTEXT* const machineContextBuffer)
{
    if(thread == crash->crashedThread)
    {
        if(crash->crashType == KSCrashTypeSignal)
        {
            return crash->signal.userContext->uc_mcontext;
        }
    }

    if(thread == mach_thread_self())
    {
        return NULL;
    }

    if(!kscrw_i_fetchMachineState(thread, machineContextBuffer))
    {
        KSLOG_ERROR("Failed to fetch machine state for thread %d", thread);
        return NULL;
    }

    return machineContextBuffer;
}

/** Get the backtrace for the specified thread.
 *
 * This function will choose how to fetch the backtrace based on machine context
 * availability andwhat kind of crash occurred. It may store the backtrace in
 * backtraceBuffer unless it can be fetched directly from memory. Do not count
 * on backtraceBuffer containing anything. Always use the return value.
 *
 * @param crash The crash handler context.
 *
 * @param thread The thread to get a machine context for.
 *
 * @param machineContext The machine context (can be NULL).
 *
 * @param backtraceBuffer A place to store the backtrace, if needed.
 *
 * @param backtraceLength In: The length of backtraceBuffer.
 *                        Out: The length of the backtrace.
 *
 * @param skippedEntries: Out: The number of entries that were skipped due to
 *                             stack overflow.
 *
 * @return The backtrace, or NULL if not found.
 */
uintptr_t* kscrw_i_getBacktrace(const KSCrash_SentryContext* const crash,
                                const thread_t thread,
                                const _STRUCT_MCONTEXT* const machineContext,
                                uintptr_t* const backtraceBuffer,
                                int* const backtraceLength,
                                int* const skippedEntries)
{
    if(thread == crash->crashedThread)
    {
        if(crash->crashType == KSCrashTypeNSException)
        {
            *backtraceLength = crash->NSException.stackTraceLength;
            return crash->NSException.stackTrace;
        }
    }

    if(machineContext == NULL)
    {
        return NULL;
    }

    int actualSkippedEntries = 0;
    int actualLength = ksbt_backtraceLength(machineContext);
    if(actualLength >= kStackOverflowThreshold)
    {
        actualSkippedEntries = actualLength - *backtraceLength;
    }

    *backtraceLength = ksbt_backtraceThreadState(machineContext,
                                                 backtraceBuffer,
                                                 actualSkippedEntries,
                                                 *backtraceLength);
    if(skippedEntries != NULL)
    {
        *skippedEntries = actualSkippedEntries;
    }
    return backtraceBuffer;
}

/** Check if the stack for the specified thread has overflowed.
 *
 * @param crash The crash handler context.
 *
 * @param thread The thread to check.
 *
 * @return true if the thread's stack has overflowed.
 */
bool kscrw_i_isStackOverflow(const KSCrash_SentryContext* const crash,
                             const thread_t thread)
{
    _STRUCT_MCONTEXT concreteMachineContext;
    _STRUCT_MCONTEXT* machineContext = kscrw_i_getMachineContext(crash,
                                                                 thread,
                                                                 &concreteMachineContext);
    if(machineContext == NULL)
    {
        return false;
    }

    return ksbt_isBacktraceTooLong(machineContext, kStackOverflowThreshold);
}


// ============================================================================
#pragma mark - Console Printing -
// ============================================================================

/** Print a backtrace entry in the standard format.
 *
 * @param entryNum The backtrace entry number.
 *
 * @param address The program counter value (instruction address).
 *
 * @param dlInfo Information about the nearest symbols to the address.
 */
void kscrw_i_printBacktraceEntry(const int entryNum,
                                 const uintptr_t address,
                                 const Dl_info* const dlInfo)
{
    char faddrBuff[20];
    char saddrBuff[20];

    const char* fname = ksfu_lastPathEntry(dlInfo->dli_fname);
    if(fname == NULL)
    {
        sprintf(faddrBuff, POINTER_FMT, (uintptr_t)dlInfo->dli_fbase);
        fname = faddrBuff;
    }

    uintptr_t offset = address - (uintptr_t)dlInfo->dli_saddr;
    const char* sname = dlInfo->dli_sname;
    if(sname == NULL)
    {
        sprintf(saddrBuff, POINTER_SHORT_FMT, (uintptr_t)dlInfo->dli_fbase);
        sname = saddrBuff;
        offset = address - (uintptr_t)dlInfo->dli_fbase;
    }

    KSLOGBASIC_ALWAYS(TRACE_FMT, entryNum, fname, address, sname, offset);
}

/** Print a backtrace using the logger.
 *
 * @param backtrace The backtrace to print.
 *
 * @param backtraceLength The length of the backtrace.
 */
void kscrw_i_printBacktrace(const uintptr_t* const backtrace,
                            const int backtraceLength)
{
    if(backtraceLength > 0)
    {
        Dl_info symbolicated[backtraceLength];
        ksbt_symbolicate(backtrace, symbolicated, backtraceLength);

        for(int i = 0; i < backtraceLength; i++)
        {
            kscrw_i_printBacktraceEntry(i, backtrace[i], &symbolicated[i]);
        }
    }
}

/** Print the backtrace for the crashed thread.
 *
 * @param crash The crash handler context.
 */
void kscrw_i_printCrashThreadBacktrace(const KSCrash_SentryContext* const crash)
{
    thread_t thread = crash->crashedThread;
    _STRUCT_MCONTEXT concreteMachineContext;
    uintptr_t concreteBacktrace[kMaxBacktraceDepth];
    int backtraceLength = sizeof(concreteBacktrace);

    _STRUCT_MCONTEXT* machineContext = kscrw_i_getMachineContext(crash,
                                                                 thread,
                                                                 &concreteMachineContext);

    uintptr_t* backtrace = kscrw_i_getBacktrace(crash,
                                                thread,
                                                machineContext,
                                                concreteBacktrace,
                                                &backtraceLength,
                                                NULL);

    if(backtrace != NULL)
    {
        kscrw_i_printBacktrace(backtrace, backtraceLength);
    }
}


// ============================================================================
#pragma mark - Report Writing -
// ============================================================================

/** Write the contents of a memory location only if it contains notable data.
 * Also writes meta information about the data.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param address The memory address.
 */
void kscrw_i_writeMemoryContentsIfNotable(const KSCrashReportWriter* const writer,
                                          const char* const key,
                                          const uintptr_t address)
{
    if((void*)address == NULL)
    {
        return;
    }

    ssize_t mallocSize = (ssize_t)malloc_size((void*)address);
    const char* zombieClassName = kszombie_className((void*)address);
    ObjCObjectType objType = ksobjc_objectType((void*)address);
    const char* className = NULL;
    if(objType != kObjCObjectTypeNone)
    {
        className = ksobjc_className((void*)address);
        if(className == NULL)
        {
            objType = kObjCObjectTypeNone;
        }
    }
    const char* bareString = NULL;
    if(objType == kObjCObjectTypeNone && kscrw_i_isValidString((void*)address))
    {
        bareString = (const char*)address;
    }

    if(objType == kObjCObjectTypeNone &&
       zombieClassName == NULL &&
       bareString == NULL &&
       mallocSize == 0)
    {
        // Nothing notable about this memory location.
        return;
    }

    writer->beginObject(writer, key);
    {
        writer->addUIntegerElement(writer, "address", address);
        writer->addUIntegerElement(writer, "malloc_size", (size_t)mallocSize);
        if(objType != kObjCObjectTypeNone)
        {
            const char* contents = objType == kObjCObjectTypeClass ? "objc_class" : "objc_object";
            writer->addStringElement(writer, "contents", contents);
            writer->addStringElement(writer, "class", className);
        }
        else if(bareString != NULL)
        {
            writer->addStringElement(writer, "contents", "string");
            writer->addStringElement(writer, "value", bareString);
        }
        else
        {
            writer->addStringElement(writer, "contents", "unknown");
        }
        if(zombieClassName != NULL)
        {
            writer->addStringElement(writer, "last_deallocated_obj", zombieClassName);
        }
    }
    writer->endContainer(writer);
}


#pragma mark Backtrace

/** Write a backtrace entry to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param address The memory address.
 *
 * @param dlInfo Information about the nearest symbols to the address.
 */
void kscrw_i_writeBacktraceEntry(const KSCrashReportWriter* const writer,
                                 const char* const key,
                                 const uintptr_t address,
                                 const Dl_info* const info)
{
    writer->beginObject(writer, key);
    {
        if(info->dli_fname != NULL)
        {
            writer->addStringElement(writer, "object_name", ksfu_lastPathEntry(info->dli_fname));
        }
        writer->addUIntegerElement(writer, "object_addr", (uintptr_t)info->dli_fbase);
        if(info->dli_sname != NULL)
        {
            writer->addStringElement(writer, "symbol_name", info->dli_sname);
        }
        writer->addUIntegerElement(writer, "symbol_addr", (uintptr_t)info->dli_saddr);
        writer->addUIntegerElement(writer, "instruction_addr", address);
    }
    writer->endContainer(writer);
}

/** Write a backtrace to the report.
 *
 * @param writer The writer to write the backtrace to.
 *
 * @param key The object key, if needed.
 *
 * @param backtrace The backtrace to write.
 *
 * @param backtraceLength Length of the backtrace.
 */
void kscrw_i_writeBacktrace(const KSCrashReportWriter* const writer,
                            const char* const key,
                            const uintptr_t* const backtrace,
                            const int backtraceLength)
{
    if(backtraceLength > 0)
    {
        Dl_info symbolicated[backtraceLength];
        ksbt_symbolicate(backtrace, symbolicated, backtraceLength);

        writer->beginArray(writer, key);
        {
            for(int i = 0; i < backtraceLength; i++)
            {
                kscrw_i_writeBacktraceEntry(writer,
                                            NULL,
                                            backtrace[i],
                                            &symbolicated[i]);
            }
        }
        writer->endContainer(writer);
    }
}

#pragma mark Stack

/** Write a dump of the stack contents to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param machineContext The context to retrieve the stack from.
 *
 * @param isStackOverflow If true, the stack has overflowed.
 */
void kscrw_i_writeStackContents(const KSCrashReportWriter* const writer,
                                const char* const key,
                                const _STRUCT_MCONTEXT* const machineContext,
                                const bool isStackOverflow)
{
    uintptr_t sp = ksmach_stackPointer(machineContext);
    if((void*)sp == NULL)
    {
        return;
    }

    uintptr_t lowAddress = sp + (uintptr_t)(kStackContentsPushedDistance * (int)sizeof(sp) * ksmach_stackGrowDirection() * -1);
    uintptr_t highAddress = sp + (uintptr_t)(kStackContentsPoppedDistance * (int)sizeof(sp) * ksmach_stackGrowDirection());
    if(highAddress < lowAddress)
    {
        uintptr_t tmp = lowAddress;
        lowAddress = highAddress;
        highAddress = tmp;
    }
    writer->beginObject(writer, key);
    {
        writer->addStringElement(writer, "grow_direction", ksmach_stackGrowDirection() > 0 ? "+" : "-");
        writer->addUIntegerElement(writer, "dump_start", lowAddress);
        writer->addUIntegerElement(writer, "dump_end", highAddress);
        writer->addUIntegerElement(writer, "stack_pointer", sp);
        writer->addBooleanElement(writer, "overflow", isStackOverflow);
        uint8_t stackBuffer[kStackContentsTotalDistance * sizeof(sp)];
        size_t copyLength = highAddress - lowAddress;
        if(ksmach_copyMem((void*)lowAddress, stackBuffer, copyLength) == KERN_SUCCESS)
        {
            writer->addDataElement(writer, "contents", (void*)stackBuffer, copyLength);
        }
        else
        {
            writer->addStringElement(writer, "error", "Stack contents not accessible");
        }
    }
    writer->endContainer(writer);
}

/** Write any notable addresses near the stack pointer (above and below).
 *
 * @param writer The writer.
 *
 * @param machineContext The context to retrieve the stack from.
 *
 * @param backDistance The distance towards the beginning of the stack to check.
 *
 * @param forwardDistance The distance past the end of the stack to check.
 */
void kscrw_i_writeNotableStackContents(const KSCrashReportWriter* const writer,
                                       const _STRUCT_MCONTEXT* const machineContext,
                                       const int backDistance,
                                       const int forwardDistance)
{
    uintptr_t sp = ksmach_stackPointer(machineContext);
    if((void*)sp == NULL)
    {
        return;
    }

    uintptr_t lowAddress = sp + (uintptr_t)(backDistance * (int)sizeof(sp) * ksmach_stackGrowDirection() * -1);
    uintptr_t highAddress = sp + (uintptr_t)(forwardDistance * (int)sizeof(sp) * ksmach_stackGrowDirection());
    if(highAddress < lowAddress)
    {
        uintptr_t tmp = lowAddress;
        lowAddress = highAddress;
        highAddress = tmp;
    }
    uintptr_t contentsAsPointer;
    char nameBuffer[40];
    for(uintptr_t address = lowAddress; address < highAddress; address += sizeof(address))
    {
        if(ksmach_copyMem((void*)address, &contentsAsPointer, sizeof(contentsAsPointer)) == KERN_SUCCESS)
        {
            sprintf(nameBuffer, "stack@%p", (void*)address);
            kscrw_i_writeMemoryContentsIfNotable(writer, nameBuffer, contentsAsPointer);
        }
    }
}


#pragma mark Registers

/** Write the contents of all regular registers to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param machineContext The context to retrieve the registers from.
 */
void kscrw_i_writeRegisters(const KSCrashReportWriter* const writer,
                            const char* const key,
                            const _STRUCT_MCONTEXT* const machineContext)
{
    char registerNameBuff[30];
    const char* registerName;
    writer->beginObject(writer, key);
    {
        const int numRegisters = ksmach_numRegisters();
        for(int reg = 0; reg < numRegisters; reg++)
        {
            registerName = ksmach_registerName(reg);
            if(registerName == NULL)
            {
                snprintf(registerNameBuff, sizeof(registerNameBuff), "r%d", reg);
                registerName = registerNameBuff;
            }
            writer->addUIntegerElement(writer, registerName,
                                       ksmach_registerValue(machineContext, reg));
        }
    }
    writer->endContainer(writer);
}

/** Write the contents of all exception registers to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param machineContext The context to retrieve the registers from.
 */
void kscrw_i_writeExceptionRegisters(const KSCrashReportWriter* const writer,
                                     const char* const key,
                                     const _STRUCT_MCONTEXT* const machineContext)
{
    char registerNameBuff[30];
    const char* registerName;
    writer->beginObject(writer, key);
    {
        const int numRegisters = ksmach_numExceptionRegisters();
        for(int reg = 0; reg < numRegisters; reg++)
        {
            registerName = ksmach_exceptionRegisterName(reg);
            if(registerName == NULL)
            {
                snprintf(registerNameBuff, sizeof(registerNameBuff), "r%d", reg);
                registerName = registerNameBuff;
            }
            writer->addUIntegerElement(writer,registerName,
                                       ksmach_exceptionRegisterValue(machineContext, reg));
        }
    }
    writer->endContainer(writer);
}

/** Write any notable addresses contained in the CPU registers.
 *
 * @param writer The writer.
 *
 * @param machineContext The context to retrieve the registers from.
 */
void kscrw_i_writeNotableRegisters(const KSCrashReportWriter* const writer,
                                   const _STRUCT_MCONTEXT* const machineContext)
{
    char registerNameBuff[30];
    const char* registerName;
    const int numRegisters = ksmach_numRegisters();
    for(int reg = 0; reg < numRegisters; reg++)
    {
        registerName = ksmach_registerName(reg);
        if(registerName == NULL)
        {
            snprintf(registerNameBuff, sizeof(registerNameBuff), "r%d", reg);
            registerName = registerNameBuff;
        }
        kscrw_i_writeMemoryContentsIfNotable(writer,
                                             registerName,
                                             (uintptr_t)ksmach_registerValue(machineContext, reg));
    }
}


#pragma mark Thread-specific

/** Write any notable addresses in the stack or registers to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param machineContext The context to retrieve the registers from.
 */
void kscrw_i_writeNotableAddresses(const KSCrashReportWriter* const writer,
                                   const char* const key,
                                   const _STRUCT_MCONTEXT* const machineContext)
{
    writer->beginObject(writer, key);
    {
        kscrw_i_writeNotableRegisters(writer, machineContext);
        kscrw_i_writeNotableStackContents(writer,
                                          machineContext,
                                          kStackNotableSearchBackDistance,
                                          kStackNotableSearchForwardDistance);
    }
    writer->endContainer(writer);
}

/** Write information about a thread to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param crash The crash handler context.
 *
 * @param thread The thread to write about.
 */
void kscrw_i_writeThread(const KSCrashReportWriter* const writer,
                         const char* const key,
                         const KSCrash_SentryContext* const crash,
                         const thread_t thread)
{
    bool isCrashedThread = thread == crash->crashedThread;
    char nameBuffer[128];
    _STRUCT_MCONTEXT machineContextBuffer;
    uintptr_t backtraceBuffer[kMaxBacktraceDepth];
    int backtraceLength = sizeof(backtraceBuffer);
    int skippedEntries = 0;

    _STRUCT_MCONTEXT* machineContext = kscrw_i_getMachineContext(crash,
                                                                 thread,
                                                                 &machineContextBuffer);

    uintptr_t* backtrace = kscrw_i_getBacktrace(crash,
                                                thread,
                                                machineContext,
                                                backtraceBuffer,
                                                &backtraceLength,
                                                &skippedEntries);

    writer->beginObject(writer, key);
    {
        if(backtrace != NULL)
        {
            kscrw_i_writeBacktrace(writer, "backtrace", backtrace, backtraceLength);
            writer->addIntegerElement(writer, "backtrace_skipped", skippedEntries);
        }
        if(machineContext != NULL)
        {
            kscrw_i_writeRegisters(writer, "registers", machineContext);
            if(isCrashedThread)
            {
                kscrw_i_writeExceptionRegisters(writer, "exception_registers", machineContext);
            }
        }
        if(pthread_getname_np(pthread_from_mach_thread_np(thread),
                              nameBuffer,
                              sizeof(nameBuffer)) == 0 &&
           nameBuffer[0] != 0)
        {
            writer->addStringElement(writer, "name", nameBuffer);
        }

        if(ksmach_getThreadQueueName(thread, nameBuffer, sizeof(nameBuffer)))
        {
            writer->addStringElement(writer, "dispatch_queue", nameBuffer);
        }
        writer->addBooleanElement(writer, "crashed", isCrashedThread);
        writer->addBooleanElement(writer, "current_thread", thread == mach_thread_self());
        if(isCrashedThread && machineContext != NULL)
        {
            kscrw_i_writeStackContents(writer,
                                       "stack",
                                       machineContext,
                                       skippedEntries > 0);
            kscrw_i_writeNotableAddresses(writer, "notable_addresses", machineContext);
        }
    }
    writer->endContainer(writer);
}

/** Write information about all threads to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param crash The crash handler context.
 */
void kscrw_i_writeAllThreads(const KSCrashReportWriter* const writer,
                             const char* const key,
                             const KSCrash_SentryContext* const crash)
{
    const task_t thisTask = mach_task_self();
    thread_act_array_t threads;
    mach_msg_type_number_t numThreads;
    kern_return_t kr;

    if((kr = task_threads(thisTask, &threads, &numThreads)) != KERN_SUCCESS)
    {
        KSLOG_ERROR("task_threads: %s", mach_error_string(kr));
        return;
    }

    // Fetch info for all threads.
    writer->beginArray(writer, key);
    {
        for(mach_msg_type_number_t i = 0; i < numThreads; i++)
        {
            kscrw_i_writeThread(writer, NULL, crash, threads[i]);
        }
    }
    writer->endContainer(writer);

    // Clean up.
    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
    {
        mach_port_deallocate(thisTask, threads[i]);
    }
    vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * numThreads);
}


#pragma mark Global Report Data

/** Write information about a binary image to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param index Which image to write about.
 */
void kscrw_i_writeBinaryImage(const KSCrashReportWriter* const writer,
                              const char* const key,
                              const uint32_t index)
{
    const struct mach_header* header = _dyld_get_image_header(index);
    if(header == NULL)
    {
        return;
    }

    uintptr_t cmdPtr = ksmach_firstCmdAfterHeader(header);
    if(cmdPtr == 0)
    {
        return;
    }

    // Look for the TEXT segment to get the image size.
    // Also look for a UUID command.
    uint64_t imageSize = 0;
    uint8_t* uuid = NULL;

    for(uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++)
    {
        struct load_command* loadCmd = (struct load_command*)cmdPtr;
        switch(loadCmd->cmd)
        {
            case LC_SEGMENT:
            {
                struct segment_command* segCmd = (struct segment_command*)cmdPtr;
                if(strcmp(segCmd->segname, SEG_TEXT) == 0)
                {
                    imageSize = segCmd->vmsize;
                }
                break;
            }
            case LC_SEGMENT_64:
            {
                struct segment_command_64* segCmd = (struct segment_command_64*)cmdPtr;
                if(strcmp(segCmd->segname, SEG_TEXT) == 0)
                {
                    imageSize = segCmd->vmsize;
                }
                break;
            }
            case LC_UUID:
            {
                struct uuid_command* uuidCmd = (struct uuid_command*)cmdPtr;
                uuid = uuidCmd->uuid;
                break;
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }

    writer->beginObject(writer, key);
    {
        writer->addUIntegerElement(writer, "image_addr", (uintptr_t)header);
        writer->addUIntegerElement(writer, "image_size", imageSize);
        writer->addStringElement(writer, "name", _dyld_get_image_name(index));
        writer->addUUIDElement(writer, "uuid", uuid);
        writer->addIntegerElement(writer, "cpu_type", header->cputype);
        writer->addIntegerElement(writer, "cpu_subtype", header->cpusubtype);
    }
    writer->endContainer(writer);
}

/** Write information about all images to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 */
void kscrw_i_writeBinaryImages(const KSCrashReportWriter* const writer,
                               const char* const key)
{
    const uint32_t imageCount = _dyld_image_count();

    writer->beginArray(writer, key);
    {
        for(uint32_t iImg = 0; iImg < imageCount; iImg++)
        {
            kscrw_i_writeBinaryImage(writer, NULL, iImg);
        }
    }
    writer->endContainer(writer);
}

/** Write information about system memory to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 */
void kscrw_i_writeMemoryInfo(const KSCrashReportWriter* const writer,
                             const char* const key)
{
    writer->beginObject(writer, key);
    {
        writer->addUIntegerElement(writer, "usable_memory", ksmach_usableMemory());
        writer->addUIntegerElement(writer, "free_memory", ksmach_freeMemory());
    }
    writer->endContainer(writer);
}

/** Write information about an NSException to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param name The exception name.
 *
 * @param reason The exception reason.
 *
 * @param backtrace The exception's backtrace.
 *
 * @param backtraceLength The length of the backtrace.
 */
void kscrw_i_writeNSException(const KSCrashReportWriter* const writer,
                              const char* const key,
                              const char* const name,
                              const char* const reason,
                              const uintptr_t* const backtrace,
                              const int backtraceLength)
{
    writer->beginObject(writer, key);
    {
        writer->addStringElement(writer, "name", name);
        writer->addStringElement(writer, "reason", reason);
        kscrw_i_writeBacktrace(writer, "backtrace", backtrace, backtraceLength);
    }
    writer->endContainer(writer);
}

/** Write information about the error leading to the crash to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param crash The crash handler context.
 */
void kscrw_i_writeError(const KSCrashReportWriter* const writer,
                        const char* const key,
                        const KSCrash_SentryContext* const crash)
{
    int machExceptionType = 0;
    kern_return_t machCode = 0;
    kern_return_t machSubCode = 0;
    int sigNum = 0;
    int sigCode = 0;
    const char* NSExceptionName = "(null)";
    const char* NSExceptionReason = "(null)";

    // Gather common info.
    switch(crash->crashType)
    {
        case KSCrashTypeMachException:
            machExceptionType = crash->mach.type;
            machCode = (kern_return_t)crash->mach.code;
            if(machCode == KERN_PROTECTION_FAILURE && crash->isStackOverflow)
            {
                // A stack overflow should return KERN_INVALID_ADDRESS, but
                // when a stack blasts through the guard pages at the top of the stack,
                // it generates KERN_PROTECTION_FAILURE. Correct for this.
                machCode = KERN_INVALID_ADDRESS;
            }
            machSubCode = (kern_return_t)crash->mach.subcode;

            sigNum = kssignal_signalForMachException(machExceptionType,
                                                     machCode);
            break;

        case KSCrashTypeNSException:
            machExceptionType = EXC_CRASH;
            sigNum = SIGABRT;
            if(crash->NSException.name != NULL)
            {
                NSExceptionName = crash->NSException.name;
            }
            if(crash->NSException.reason != NULL)
            {
                NSExceptionReason = crash->NSException.reason;
            }
            break;
        case KSCrashTypeSignal:
            sigNum = crash->signal.signalInfo->si_signo;
            sigCode = crash->signal.signalInfo->si_code;
            machExceptionType = kssignal_machExceptionForSignal(sigNum);
            break;
    }

    char machExceptionName[30];
    char machCodeName[30];
    kscrw_i_getMachExceptionName(machExceptionType, machExceptionName, sizeof(machExceptionName));
    kscrw_i_getMachCodeName(machCode, machCodeName, sizeof(machCodeName));
    char sigNameBuff[30];
    char sigCodeNameBuff[30];
    const char* sigName = kssignal_signalName(sigNum);
    const char* sigCodeName = kssignal_signalCodeName(sigNum, sigCode);
    if(sigName == NULL)
    {
        snprintf(sigNameBuff, sizeof(sigNameBuff), "%d", sigNum);
        sigName = sigNameBuff;
    }
    if(sigCodeName == NULL)
    {
        snprintf(sigCodeNameBuff, sizeof(sigCodeNameBuff), "%d", sigCode);
        sigCodeName = sigCodeNameBuff;
    }

    writer->beginObject(writer, key);
    {
        writer->addStringElement(writer, "mach_exception", machExceptionName);
        writer->addUIntegerElement(writer, "mach_code", (unsigned)machCode);
        writer->addStringElement(writer, "mach_code_name", machCodeName);
        writer->addUIntegerElement(writer, "mach_subcode", (unsigned)machSubCode);
        writer->addUIntegerElement(writer, "signal", (unsigned)sigNum);
        writer->addStringElement(writer, "signal_name", sigName);
        writer->addUIntegerElement(writer, "signal_code", (unsigned)sigCode);
        writer->addStringElement(writer, "signal_code_name", sigCodeName);
        writer->addUIntegerElement(writer, "address", crash->faultAddress);

        // Gather specific info.
        switch(crash->crashType)
        {
            case KSCrashTypeMachException:
                writer->addStringElement(writer, "type", "mach");

                KSLOGBASIC_INFO("App crashed due to mach exception %s: %s",
                                machExceptionName, machCodeName);
                break;

            case KSCrashTypeNSException:
                writer->addStringElement(writer, "nsexception_name", NSExceptionName);
                writer->addStringElement(writer, "nsexception_reason", NSExceptionReason);
                writer->addStringElement(writer, "type", "nsexception");

                KSLOGBASIC_INFO("App crashed due to exception %s: %s",
                                NSExceptionName,
                                NSExceptionReason);
                break;

            case KSCrashTypeSignal:
                writer->addStringElement(writer, "type", "signal");

                KSLOGBASIC_INFO("App crashed due to signal [%s, %s] at %08x",
                                sigName, sigCodeName, crash->faultAddress);
        }

        if(crash->crashType == KSCrashTypeNSException)
        {
            kscrw_i_writeNSException(writer,
                                     "nsexception",
                                     NSExceptionName,
                                     NSExceptionReason,
                                     crash->NSException.stackTrace,
                                     crash->NSException.stackTraceLength);
        }
    }
    writer->endContainer(writer);
}

/** Write information about app runtime, etc to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param state The persistent crash handler state.
 */
void kscrw_i_writeAppStats(const KSCrashReportWriter* const writer,
                           const char* const key,
                           KSCrash_State* state)
{
    writer->beginObject(writer, key);
    {
        writer->addBooleanElement(writer, "application_active",
                                  state->applicationIsActive);
        writer->addBooleanElement(writer, "application_in_foreground",
                                  state->applicationIsInForeground);

        writer->addIntegerElement(writer, "launches_since_last_crash",
                                  state->launchesSinceLastCrash);
        writer->addIntegerElement(writer, "sessions_since_last_crash",
                                  state->sessionsSinceLastCrash);
        writer->addFloatingPointElement(writer,
                                        "active_time_since_last_crash",
                                        state->activeDurationSinceLastCrash);
        writer->addFloatingPointElement(writer,
                                        "background_time_since_last_crash",
                                        state->backgroundDurationSinceLastCrash);

        writer->addIntegerElement(writer, "sessions_since_launch",
                                  state->sessionsSinceLaunch);
        writer->addFloatingPointElement(writer,
                                        "active_time_since_launch",
                                        state->activeDurationSinceLaunch);
        writer->addFloatingPointElement(writer,
                                        "background_time_since_launch",
                                        state->backgroundDurationSinceLaunch);
    }
    writer->endContainer(writer);
}


#pragma mark Setup

/** Prepare a report writer for use.
 *
 * @oaram writer The writer to prepare.
 *
 * @param context JSON writer contextual information.
 */
void kscrw_i_prepareReportWriter(KSCrashReportWriter* const writer,
                                 KSJSONEncodeContext* const context)
{
    writer->addBooleanElement = kscrw_i_addBooleanElement;
    writer->addFloatingPointElement = kscrw_i_addFloatingPointElement;
    writer->addIntegerElement = kscrw_i_addIntegerElement;
    writer->addUIntegerElement = kscrw_i_addUIntegerElement;
    writer->addStringElement = kscrw_i_addStringElement;
    writer->addTextFileElement = kscrw_i_addTextFileElement;
    writer->addDataElement = kscrw_i_addDataElement;
    writer->beginDataElement = kscrw_i_beginDataElement;
    writer->appendDataElement = kscrw_i_appendDataElement;
    writer->endDataElement = kscrw_i_endDataElement;
    writer->addUUIDElement = kscrw_i_addUUIDElement;
    writer->addJSONElement = kscrw_i_addJSONElement;
    writer->beginObject = kscrw_i_beginObject;
    writer->beginArray = kscrw_i_beginArray;
    writer->endContainer = kscrw_i_endContainer;
    writer->context = context;
}

/** Open the crash report file.
 *
 * @param path The path to the file.
 *
 * @return The file descriptor, or -1 if an error occurred.
 */
int kscrw_i_openCrashReportFile(const char* const path)
{
    int fd = open(path, O_RDWR | O_CREAT | O_EXCL, 0644);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open crash report file %s: %s",
                    path,
                    strerror(errno));
    }
    return fd;
}

/** Record whether the crashed thread had a stack overflow or not.
 *
 * @param crashContext the context.
 */
void kscrw_i_updateStackOverflowStatus(KSCrash_Context* const crashContext)
{
    // TODO: This feels weird. Shouldn't be mutating the context.
    if(kscrw_i_isStackOverflow(&crashContext->crash, crashContext->crash.crashedThread))
    {
        KSLOG_TRACE("Stack overflow detected.");
        crashContext->crash.isStackOverflow = true;
    }
}


// ============================================================================
#pragma mark - Main API -
// ============================================================================

void kscrashreport_writeMinimalReport(KSCrash_Context* const crashContext,
                                      const char* const path)
{
    KSLOG_INFO("Writing minimal crash report to %s", path);

    int fd = kscrw_i_openCrashReportFile(path);
    if(fd < 0)
    {
        return;
    }

    kscrw_i_updateStackOverflowStatus(crashContext);

    KSJSONEncodeContext jsonContext;
    jsonContext.userData = &fd;
    KSCrashReportWriter concreteWriter;
    KSCrashReportWriter* writer = &concreteWriter;
    kscrw_i_prepareReportWriter(writer, &jsonContext);

    ksjson_beginEncode(getJsonContext(writer),
                       true,
                       kscrw_i_addJSONData,
                       &fd);

    writer->beginObject(writer, "minimal_report");
    {
        writer->addIntegerElement(writer, "report_version_major", kReportVersionMajor);
        writer->addIntegerElement(writer, "report_version_minor", kReportVersionMinor);
        writer->addStringElement(writer, "crash_id", crashContext->config.crashID);
        writer->addIntegerElement(writer, "timestamp", time(NULL));

        writer->beginObject(writer, "crash");
        {
            kscrw_i_writeThread(writer,
                                "crashed_thread",
                                &crashContext->crash,
                                crashContext->crash.crashedThread);
            kscrw_i_writeError(writer, "error", &crashContext->crash);
        }
        writer->endContainer(writer);
    }
    writer->endContainer(writer);

    ksjson_endEncode(getJsonContext(writer));

    close(fd);
}

void kscrashreport_writeStandardReport(KSCrash_Context* const crashContext,
                                       const char* const path)
{
    KSLOG_INFO("Writing crash report to %s", path);

    int fd = kscrw_i_openCrashReportFile(path);
    if(fd < 0)
    {
        return;
    }

    kscrw_i_updateStackOverflowStatus(crashContext);

    kscrw_i_printCrashThreadBacktrace(&crashContext->crash);

    KSJSONEncodeContext jsonContext;
    jsonContext.userData = &fd;
    KSCrashReportWriter concreteWriter;
    KSCrashReportWriter* writer = &concreteWriter;
    kscrw_i_prepareReportWriter(writer, &jsonContext);

    ksjson_beginEncode(getJsonContext(writer), true, kscrw_i_addJSONData, &fd);

    writer->beginObject(writer, "report");
    {
        writer->addIntegerElement(writer, "report_version_major", kReportVersionMajor);
        writer->addIntegerElement(writer, "report_version_minor", kReportVersionMinor);
        writer->addStringElement(writer, "crash_id", crashContext->config.crashID);
        writer->addIntegerElement(writer, "timestamp", time(NULL));
        if(crashContext->config.systemInfoJSON != NULL)
        {
            kscrw_i_addJSONElement(writer, "system", crashContext->config.systemInfoJSON);
        }

        writer->beginObject(writer, "system_atcrash");
        {
            kscrw_i_writeMemoryInfo(writer, "memory");
            kscrw_i_writeAppStats(writer, "application_stats", &crashContext->state);
        }
        writer->endContainer(writer);

        kscrw_i_writeBinaryImages(writer, "binary_images");

        writer->beginObject(writer, "crash");
        {
            kscrw_i_writeAllThreads(writer, "threads", &crashContext->crash);
            kscrw_i_writeError(writer, "error", &crashContext->crash);
        }
        writer->endContainer(writer);

        if(crashContext->config.userInfoJSON != NULL)
        {
            kscrw_i_addJSONElement(writer, "user", crashContext->config.userInfoJSON);
        }

        if(crashContext->config.onCrashNotify != NULL)
        {
            writer->beginObject(writer, "user_atcrash");
            {
                crashContext->config.onCrashNotify(writer);
            }
            writer->endContainer(writer);
        }
    }
    writer->endContainer(writer);
    
    ksjson_endEncode(getJsonContext(writer));
    
    close(fd);
}
