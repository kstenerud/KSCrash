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

#include "KSCrashReportC.h"

#include "KSBinaryImageCache.h"
#include "KSCPU.h"
#include "KSCrashExceptionHandlingPlan+Private.h"
#include "KSCrashMonitorHelper.h"
#include "KSCrashMonitor_AppState.h"
#include "KSCrashMonitor_CPPException.h"
#include "KSCrashMonitor_Deadlock.h"
#include "KSCrashMonitor_MachException.h"
#include "KSCrashMonitor_Memory.h"
#include "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor_Signal.h"
#include "KSCrashMonitor_System.h"
#include "KSCrashMonitor_User.h"
#include "KSCrashMonitor_Watchdog.h"
#include "KSCrashMonitor_Zombie.h"
#include "KSCrashReportFields.h"
#include "KSCrashReportMemoryIntrospection.h"
#include "KSCrashReportVersion.h"
#include "KSCrashReportWriter.h"
#include "KSCrashReportWriterCallbacks.h"
#include "KSDate.h"
#include "KSDynamicLinker.h"
#include "KSFileUtils.h"
#include "KSJSONCodec.h"
#include "KSMach.h"
#include "KSMemory.h"
#include "KSObjC.h"
#include "KSSignalInfo.h"
#include "KSSpinLock.h"
#include "KSStackCursor_Backtrace.h"
#include "KSStackCursor_MachineContext.h"
#include "KSString.h"
#include "KSSystemCapabilities.h"
#include "KSThread.h"
#include "KSThreadCache.h"

// #define KSLogger_LocalLevel TRACE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>

#include "KSLogger.h"

// ============================================================================
#pragma mark - Constants -
// ============================================================================

/** How far to search the stack (in pointer sized jumps) for notable data. */
#define kStackNotableSearchBackDistance 20
#define kStackNotableSearchForwardDistance 10

/** How much of the stack to dump (in pointer sized jumps). */
#define kStackContentsPushedDistance 20
#define kStackContentsPoppedDistance 10
#define kStackContentsTotalDistance (kStackContentsPushedDistance + kStackContentsPoppedDistance)

// ============================================================================
#pragma mark - JSON Encoding -
// ============================================================================

#define getJsonContext(REPORT_WRITER) ((KSJSONEncodeContext *)((REPORT_WRITER)->context))

/** Used for writing hex string values. */
static const char g_hexNybbles[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };

// ============================================================================
#pragma mark - Runtime Config -
// ============================================================================

/** User-provided JSON data to include in crash reports */
static char *g_userInfoJSON = NULL;

/** Spin lock protecting g_userInfoJSON */
static KSSpinLock g_userInfoLock = KSSPINLOCK_INIT;

static KSCrashIsWritingReportCallback g_userSectionWriteCallback = NULL;

#pragma mark Callbacks

static void addBooleanElement(const KSCrashReportWriter *const writer, const char *const key, const bool value)
{
    ksjson_addBooleanElement(getJsonContext(writer), key, value);
}

static void addFloatingPointElement(const KSCrashReportWriter *const writer, const char *const key, const double value)
{
    ksjson_addFloatingPointElement(getJsonContext(writer), key, value);
}

static void addIntegerElement(const KSCrashReportWriter *const writer, const char *const key, const int64_t value)
{
    ksjson_addIntegerElement(getJsonContext(writer), key, value);
}

static void addUIntegerElement(const KSCrashReportWriter *const writer, const char *const key, const uint64_t value)
{
    ksjson_addUIntegerElement(getJsonContext(writer), key, value);
}

static void addStringElement(const KSCrashReportWriter *const writer, const char *const key, const char *const value)
{
    ksjson_addStringElement(getJsonContext(writer), key, value, KSJSON_SIZE_AUTOMATIC);
}

static void addTextFileElement(const KSCrashReportWriter *const writer, const char *const key,
                               const char *const filePath)
{
    const int fd = open(filePath, O_RDONLY);
    if (fd < 0) {
        KSLOG_ERROR("Could not open file %s: %s", filePath, strerror(errno));
        return;
    }

    if (ksjson_beginStringElement(getJsonContext(writer), key) != KSJSON_OK) {
        KSLOG_ERROR("Could not start string element");
        goto done;
    }

    char buffer[512];
    int bytesRead;
    for (bytesRead = (int)read(fd, buffer, sizeof(buffer)); bytesRead > 0;
         bytesRead = (int)read(fd, buffer, sizeof(buffer))) {
        if (ksjson_appendStringElement(getJsonContext(writer), buffer, bytesRead) != KSJSON_OK) {
            KSLOG_ERROR("Could not append string element");
            goto done;
        }
    }

done:
    ksjson_endStringElement(getJsonContext(writer));
    close(fd);
}

static void addDataElement(const KSCrashReportWriter *const writer, const char *const key, const char *const value,
                           const int length)
{
    ksjson_addDataElement(getJsonContext(writer), key, value, length);
}

static void beginDataElement(const KSCrashReportWriter *const writer, const char *const key)
{
    ksjson_beginDataElement(getJsonContext(writer), key);
}

static void appendDataElement(const KSCrashReportWriter *const writer, const char *const value, const int length)
{
    ksjson_appendDataElement(getJsonContext(writer), value, length);
}

static void endDataElement(const KSCrashReportWriter *const writer) { ksjson_endDataElement(getJsonContext(writer)); }

static void addUUIDElement(const KSCrashReportWriter *const writer, const char *const key,
                           const unsigned char *const value)
{
    if (value == NULL) {
        ksjson_addNullElement(getJsonContext(writer), key);
    } else {
        char uuidBuffer[37];
        const unsigned char *src = value;
        char *dst = uuidBuffer;
        for (int i = 0; i < 4; i++) {
            *dst++ = g_hexNybbles[(*src >> 4) & 15];
            *dst++ = g_hexNybbles[(*src++) & 15];
        }
        *dst++ = '-';
        for (int i = 0; i < 2; i++) {
            *dst++ = g_hexNybbles[(*src >> 4) & 15];
            *dst++ = g_hexNybbles[(*src++) & 15];
        }
        *dst++ = '-';
        for (int i = 0; i < 2; i++) {
            *dst++ = g_hexNybbles[(*src >> 4) & 15];
            *dst++ = g_hexNybbles[(*src++) & 15];
        }
        *dst++ = '-';
        for (int i = 0; i < 2; i++) {
            *dst++ = g_hexNybbles[(*src >> 4) & 15];
            *dst++ = g_hexNybbles[(*src++) & 15];
        }
        *dst++ = '-';
        for (int i = 0; i < 6; i++) {
            *dst++ = g_hexNybbles[(*src >> 4) & 15];
            *dst++ = g_hexNybbles[(*src++) & 15];
        }

        ksjson_addStringElement(getJsonContext(writer), key, uuidBuffer, (int)(dst - uuidBuffer));
    }
}

static void addJSONElement(const KSCrashReportWriter *const writer, const char *const key,
                           const char *const jsonElement, bool closeLastContainer)
{
    int jsonResult =
        ksjson_addJSONElement(getJsonContext(writer), key, jsonElement, (int)strlen(jsonElement), closeLastContainer);
    if (jsonResult != KSJSON_OK) {
        char errorBuff[100];
        snprintf(errorBuff, sizeof(errorBuff), "Invalid JSON data: %s", ksjson_stringForError(jsonResult));
        ksjson_beginObject(getJsonContext(writer), key);
        ksjson_addStringElement(getJsonContext(writer), KSCrashField_Error, errorBuff, KSJSON_SIZE_AUTOMATIC);
        ksjson_addStringElement(getJsonContext(writer), KSCrashField_JSONData, jsonElement, KSJSON_SIZE_AUTOMATIC);
        ksjson_endContainer(getJsonContext(writer));
    }
}

static void addJSONElementFromFile(const KSCrashReportWriter *const writer, const char *const key,
                                   const char *const filePath, bool closeLastContainer)
{
    ksjson_addJSONFromFile(getJsonContext(writer), key, filePath, closeLastContainer);
}

static void beginObject(const KSCrashReportWriter *const writer, const char *const key)
{
    ksjson_beginObject(getJsonContext(writer), key);
}

static void beginArray(const KSCrashReportWriter *const writer, const char *const key)
{
    ksjson_beginArray(getJsonContext(writer), key);
}

static void endContainer(const KSCrashReportWriter *const writer) { ksjson_endContainer(getJsonContext(writer)); }

static void addTextLinesFromFile(const KSCrashReportWriter *const writer, const char *const key,
                                 const char *const filePath)
{
    char readBuffer[1024];
    KSBufferedReader reader;
    if (!ksfu_openBufferedReader(&reader, filePath, readBuffer, sizeof(readBuffer))) {
        return;
    }
    char buffer[1024];
    beginArray(writer, key);
    {
        for (;;) {
            int length = sizeof(buffer);
            ksfu_readBufferedReaderUntilChar(&reader, '\n', buffer, &length);
            if (length <= 0) {
                break;
            }
            buffer[length - 1] = '\0';
            ksjson_addStringElement(getJsonContext(writer), NULL, buffer, KSJSON_SIZE_AUTOMATIC);
        }
    }
    endContainer(writer);
    ksfu_closeBufferedReader(&reader);
}

static int addJSONData(const char *restrict const data, const int length, void *restrict userData)
{
    KSBufferedWriter *writer = (KSBufferedWriter *)userData;
    const bool success = ksfu_writeBufferedWriter(writer, data, length);
    return success ? KSJSON_OK : KSJSON_ERROR_CANNOT_ADD_DATA;
}

// ============================================================================
#pragma mark - Utility -
// ============================================================================

/** Get the backtrace for the specified machine context.
 *
 * This function will choose how to fetch the backtrace based on the crash and
 * machine context. It may store the backtrace in backtraceBuffer unless it can
 * be fetched directly from memory. Do not count on backtraceBuffer containing
 * anything. Always use the return value.
 *
 * @param crash The crash handler context.
 *
 * @param machineContext The machine context.
 *
 * @param cursor The stack cursor to fill.
 *
 * @return True if the cursor was filled.
 */
static bool getStackCursor(const KSCrash_MonitorContext *const crash,
                           const struct KSMachineContext *const machineContext, KSStackCursor *cursor)
{
    if (ksmc_getThreadFromContext(machineContext) == ksmc_getThreadFromContext(crash->offendingMachineContext) &&
        crash->stackCursor != NULL) {
        *cursor = *((KSStackCursor *)crash->stackCursor);
        return true;
    }

    kssc_initWithMachineContext(cursor, KSSC_STACK_OVERFLOW_THRESHOLD, machineContext);
    return true;
}

// ============================================================================
#pragma mark - Report Writing -
// ============================================================================

#pragma mark Backtrace

/** Write a backtrace to the report.
 *
 * @param writer The writer to write the backtrace to.
 *
 * @param key The object key, if needed.
 *
 * @param stackCursor The stack cursor to read from.
 */
static void writeBacktrace(const KSCrashReportWriter *const writer, const char *const key, KSStackCursor *stackCursor)
{
    writer->beginObject(writer, key);
    {
        writer->beginArray(writer, KSCrashField_Contents);
        {
            while (stackCursor->advanceCursor(stackCursor)) {
                writer->beginObject(writer, NULL);
                {
                    if (stackCursor->symbolicate(stackCursor)) {
                        if (stackCursor->stackEntry.imageName != NULL) {
                            writer->addStringElement(writer, KSCrashField_ObjectName,
                                                     ksfu_lastPathEntry(stackCursor->stackEntry.imageName));
                        }
                        writer->addUIntegerElement(writer, KSCrashField_ObjectAddr,
                                                   stackCursor->stackEntry.imageAddress);
                        if (stackCursor->stackEntry.symbolName != NULL) {
                            writer->addStringElement(writer, KSCrashField_SymbolName,
                                                     stackCursor->stackEntry.symbolName);
                        }
                        writer->addUIntegerElement(writer, KSCrashField_SymbolAddr,
                                                   stackCursor->stackEntry.symbolAddress);
                    }
                    writer->addUIntegerElement(writer, KSCrashField_InstructionAddr, stackCursor->stackEntry.address);
                }
                writer->endContainer(writer);
            }
        }
        writer->endContainer(writer);
        writer->addIntegerElement(writer, KSCrashField_Skipped, 0);
    }
    writer->endContainer(writer);
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
static void writeStackContents(const KSCrashReportWriter *const writer, const char *const key,
                               const struct KSMachineContext *const machineContext, const bool isStackOverflow)
{
    uintptr_t sp = kscpu_stackPointer(machineContext);
    if ((void *)sp == NULL) {
        return;
    }

    uintptr_t lowAddress =
        sp + (uintptr_t)(kStackContentsPushedDistance * (int)sizeof(sp) * kscpu_stackGrowDirection() * -1);
    uintptr_t highAddress =
        sp + (uintptr_t)(kStackContentsPoppedDistance * (int)sizeof(sp) * kscpu_stackGrowDirection());
    if (highAddress < lowAddress) {
        uintptr_t tmp = lowAddress;
        lowAddress = highAddress;
        highAddress = tmp;
    }
    writer->beginObject(writer, key);
    {
        writer->addStringElement(writer, KSCrashField_GrowDirection, kscpu_stackGrowDirection() > 0 ? "+" : "-");
        writer->addUIntegerElement(writer, KSCrashField_DumpStart, lowAddress);
        writer->addUIntegerElement(writer, KSCrashField_DumpEnd, highAddress);
        writer->addUIntegerElement(writer, KSCrashField_StackPtr, sp);
        writer->addBooleanElement(writer, KSCrashField_Overflow, isStackOverflow);
        uint8_t stackBuffer[kStackContentsTotalDistance * sizeof(sp)];
        int copyLength = (int)(highAddress - lowAddress);
        if (ksmem_copySafely((void *)lowAddress, stackBuffer, copyLength)) {
            writer->addDataElement(writer, KSCrashField_Contents, (void *)stackBuffer, copyLength);
        } else {
            writer->addStringElement(writer, KSCrashField_Error, "Stack contents not accessible");
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
static void writeNotableStackContents(const KSCrashReportWriter *const writer,
                                      const struct KSMachineContext *const machineContext, const int backDistance,
                                      const int forwardDistance)
{
    uintptr_t sp = kscpu_stackPointer(machineContext);
    if ((void *)sp == NULL) {
        return;
    }

    uintptr_t lowAddress = sp + (uintptr_t)(backDistance * (int)sizeof(sp) * kscpu_stackGrowDirection() * -1);
    uintptr_t highAddress = sp + (uintptr_t)(forwardDistance * (int)sizeof(sp) * kscpu_stackGrowDirection());
    if (highAddress < lowAddress) {
        uintptr_t tmp = lowAddress;
        lowAddress = highAddress;
        highAddress = tmp;
    }
    uintptr_t contentsAsPointer;
    char nameBuffer[40];
    for (uintptr_t address = lowAddress; address < highAddress; address += sizeof(address)) {
        if (ksmem_copySafely((void *)address, &contentsAsPointer, sizeof(contentsAsPointer))) {
            snprintf(nameBuffer, sizeof(nameBuffer), "stack@%p", (void *)address);
            kscrmi_writeMemoryContentsIfNotable(writer, nameBuffer, contentsAsPointer);
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
static void writeBasicRegisters(const KSCrashReportWriter *const writer, const char *const key,
                                const struct KSMachineContext *const machineContext)
{
    char registerNameBuff[30];
    const char *registerName;
    writer->beginObject(writer, key);
    {
        const int numRegisters = kscpu_numRegisters();
        for (int reg = 0; reg < numRegisters; reg++) {
            registerName = kscpu_registerName(reg);
            if (registerName == NULL) {
                snprintf(registerNameBuff, sizeof(registerNameBuff), "r%d", reg);
                registerName = registerNameBuff;
            }
            writer->addUIntegerElement(writer, registerName, kscpu_registerValue(machineContext, reg));
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
static void writeExceptionRegisters(const KSCrashReportWriter *const writer, const char *const key,
                                    const struct KSMachineContext *const machineContext)
{
    char registerNameBuff[30];
    const char *registerName;
    writer->beginObject(writer, key);
    {
        const int numRegisters = kscpu_numExceptionRegisters();
        for (int reg = 0; reg < numRegisters; reg++) {
            registerName = kscpu_exceptionRegisterName(reg);
            if (registerName == NULL) {
                snprintf(registerNameBuff, sizeof(registerNameBuff), "r%d", reg);
                registerName = registerNameBuff;
            }
            writer->addUIntegerElement(writer, registerName, kscpu_exceptionRegisterValue(machineContext, reg));
        }
    }
    writer->endContainer(writer);
}

/** Write all applicable registers.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param machineContext The context to retrieve the registers from.
 */
static void writeRegisters(const KSCrashReportWriter *const writer, const char *const key,
                           const struct KSMachineContext *const machineContext)
{
    writer->beginObject(writer, key);
    {
        writeBasicRegisters(writer, KSCrashField_Basic, machineContext);
        if (ksmc_hasValidExceptionRegisters(machineContext)) {
            writeExceptionRegisters(writer, KSCrashField_Exception, machineContext);
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
static void writeNotableRegisters(const KSCrashReportWriter *const writer,
                                  const struct KSMachineContext *const machineContext)
{
    char registerNameBuff[30];
    const char *registerName;
    const int numRegisters = kscpu_numRegisters();
    for (int reg = 0; reg < numRegisters; reg++) {
        registerName = kscpu_registerName(reg);
        if (registerName == NULL) {
            snprintf(registerNameBuff, sizeof(registerNameBuff), "r%d", reg);
            registerName = registerNameBuff;
        }
        kscrmi_writeMemoryContentsIfNotable(writer, registerName, (uintptr_t)kscpu_registerValue(machineContext, reg));
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
static void writeNotableAddresses(const KSCrashReportWriter *const writer, const char *const key,
                                  const struct KSMachineContext *const machineContext)
{
    writer->beginObject(writer, key);
    {
        writeNotableRegisters(writer, machineContext);
        writeNotableStackContents(writer, machineContext, kStackNotableSearchBackDistance,
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
 * @param machineContext The context whose thread to write about.
 *
 * @param threadIndex The index of the thread.
 *
 * @param shouldWriteNotableAddresses If true, write any notable addresses found.
 *
 * @param threadState The state code of the thread.
 */
static void writeThread(const KSCrashReportWriter *const writer, const char *const key,
                        const KSCrash_MonitorContext *const crash, const struct KSMachineContext *const machineContext,
                        const int threadIndex, const bool shouldWriteNotableAddresses, const int threadState)
{
    bool isCrashedThread = ksmc_isCrashedContext(machineContext);
    KSThread thread = ksmc_getThreadFromContext(machineContext);
    KSLOG_DEBUG("Writing thread %x (index %d). is crashed: %d", thread, threadIndex, isCrashedThread);

    KSStackCursor stackCursor;
    bool hasBacktrace = getStackCursor(crash, machineContext, &stackCursor);
    const char *state = ksthread_state_name(threadState);

    writer->beginObject(writer, key);
    {
        if (hasBacktrace) {
            writeBacktrace(writer, KSCrashField_Backtrace, &stackCursor);
        }
        if (ksmc_canHaveCPUState(machineContext)) {
            writeRegisters(writer, KSCrashField_Registers, machineContext);
        }
        writer->addIntegerElement(writer, KSCrashField_Index, threadIndex);
        const char *name = kstc_getThreadName(thread);
        if (name != NULL) {
            writer->addStringElement(writer, KSCrashField_Name, name);
        }
        name = kstc_getQueueName(thread);
        if (name != NULL) {
            writer->addStringElement(writer, KSCrashField_DispatchQueue, name);
        }
        if (state != NULL) {
            writer->addStringElement(writer, KSCrashField_State, state);
        }
        writer->addBooleanElement(writer, KSCrashField_Crashed, isCrashedThread);
        writer->addBooleanElement(writer, KSCrashField_CurrentThread, thread == ksthread_self());
        if (isCrashedThread) {
            writeStackContents(writer, KSCrashField_Stack, machineContext, stackCursor.state.hasGivenUp);
            if (shouldWriteNotableAddresses) {
                writeNotableAddresses(writer, KSCrashField_NotableAddresses, machineContext);
            }
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
static void writeThreads(const KSCrashReportWriter *const writer, const char *const key,
                         const KSCrash_MonitorContext *const crash, bool writeNotableAddresses)
{
    const struct KSMachineContext *const context = crash->offendingMachineContext;

    // Some custom monitors may not have an offending context.
    if (!context) {
        return;
    }

    KSThread offendingThread = ksmc_getThreadFromContext(context);
    int threadCount = ksmc_getThreadCount(context);
    KSMachineContext machineContext = { 0 };
    bool shouldRecordAllThreads = crash->requirements.shouldRecordAllThreads;

    // Fetch info for all threads.
    writer->beginArray(writer, key);
    {
        KSLOG_DEBUG("Writing %d of %d threads.", shouldRecordAllThreads ? threadCount : 1, threadCount);
        for (int i = 0; i < threadCount; i++) {
            KSThread thread = ksmc_getThreadAtIndex(context, i);
            int threadRunState = ksthread_getThreadState(thread);
            if (thread == offendingThread) {
                writeThread(writer, NULL, crash, context, i, writeNotableAddresses, threadRunState);
            } else if (shouldRecordAllThreads) {
                ksmc_getContextForThread(thread, &machineContext, false);
                writeThread(writer, NULL, crash, &machineContext, i, writeNotableAddresses, threadRunState);
            }
        }
    }
    writer->endContainer(writer);
}

#pragma mark Global Report Data

/** Write information about a binary image to the report.
 *
 * @param writer The writer.
 *
 * @param image The image to write.
 */
static void writeBinaryImage(const KSCrashReportWriter *const writer, const KSBinaryImage *const image)
{
    writer->beginObject(writer, NULL);
    {
        writer->addUIntegerElement(writer, KSCrashField_ImageAddress, image->address);
        writer->addUIntegerElement(writer, KSCrashField_ImageVmAddress, image->vmAddress);
        writer->addUIntegerElement(writer, KSCrashField_ImageSize, image->size);
        writer->addStringElement(writer, KSCrashField_Name, image->name);
        writer->addUUIDElement(writer, KSCrashField_UUID, image->uuid);
        writer->addIntegerElement(writer, KSCrashField_CPUType, image->cpuType);
        writer->addIntegerElement(writer, KSCrashField_CPUSubType, image->cpuSubType);
        writer->addUIntegerElement(writer, KSCrashField_ImageMajorVersion, image->majorVersion);
        writer->addUIntegerElement(writer, KSCrashField_ImageMinorVersion, image->minorVersion);
        writer->addUIntegerElement(writer, KSCrashField_ImageRevisionVersion, image->revisionVersion);
        if (image->crashInfoMessage != NULL) {
            writer->addStringElement(writer, KSCrashField_ImageCrashInfoMessage, image->crashInfoMessage);
        }
        if (image->crashInfoMessage2 != NULL) {
            writer->addStringElement(writer, KSCrashField_ImageCrashInfoMessage2, image->crashInfoMessage2);
        }
        if (image->crashInfoBacktrace != NULL) {
            writer->addStringElement(writer, KSCrashField_ImageCrashInfoBacktrace, image->crashInfoBacktrace);
        }
        if (image->crashInfoSignature != NULL) {
            writer->addStringElement(writer, KSCrashField_ImageCrashInfoSignature, image->crashInfoSignature);
        }
    }
    writer->endContainer(writer);
}

/** Write information about all images to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 */
static void writeBinaryImages(const KSCrashReportWriter *const writer, const char *const key)
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);

    writer->beginArray(writer, key);
    {
        for (uint32_t iImg = 0; iImg < count; iImg++) {
            ks_dyld_image_info info = images[iImg];
            KSBinaryImage image = { 0 };
            if (ksdl_binaryImageForHeader(info.imageLoadAddress, info.imageFilePath, &image)) {
                writeBinaryImage(writer, &image);
            }
        }
    }
    writer->endContainer(writer);
}

static inline bool isCrashOfMonitorType(const KSCrash_MonitorContext *const crash, const KSCrashMonitorAPI *monitorAPI)
{
    return ksstring_safeStrcmp(crash->monitorId, monitorAPI->monitorId()) == 0;
}

/** Write information about the error leading to the crash to the report.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param crash The crash handler context.
 */
static void writeError(const KSCrashReportWriter *const writer, const char *const key,
                       const KSCrash_MonitorContext *const crash)
{
    writer->beginObject(writer, key);
    {
#if KSCRASH_HOST_APPLE
        writer->beginObject(writer, KSCrashField_Mach);
        {
            const char *machExceptionName = ksmach_exceptionName(crash->mach.type);
            const char *machCodeName = crash->mach.code == 0 ? NULL : ksmach_kernelReturnCodeName(crash->mach.code);
            writer->addUIntegerElement(writer, KSCrashField_Exception, (unsigned)crash->mach.type);
            if (machExceptionName != NULL) {
                writer->addStringElement(writer, KSCrashField_ExceptionName, machExceptionName);
            }
            writer->addUIntegerElement(writer, KSCrashField_Code, (unsigned)crash->mach.code);
            if (machCodeName != NULL) {
                writer->addStringElement(writer, KSCrashField_CodeName, machCodeName);
            }
            writer->addUIntegerElement(writer, KSCrashField_Subcode, (size_t)crash->mach.subcode);
        }
        writer->endContainer(writer);
#endif
        writer->beginObject(writer, KSCrashField_Signal);
        {
            const char *sigName = kssignal_signalName(crash->signal.signum);
            const char *sigCodeName = kssignal_signalCodeName(crash->signal.signum, crash->signal.sigcode);
            writer->addUIntegerElement(writer, KSCrashField_Signal, (unsigned)crash->signal.signum);
            if (sigName != NULL) {
                writer->addStringElement(writer, KSCrashField_Name, sigName);
            }
            writer->addUIntegerElement(writer, KSCrashField_Code, (unsigned)crash->signal.sigcode);
            if (sigCodeName != NULL) {
                writer->addStringElement(writer, KSCrashField_CodeName, sigCodeName);
            }
        }
        writer->endContainer(writer);

        writer->addUIntegerElement(writer, KSCrashField_Address, crash->faultAddress);
        if (crash->crashReason != NULL) {
            writer->addStringElement(writer, KSCrashField_Reason, crash->crashReason);
        }

        // Write the exit reason if it's available
        if (crash->exitReason.code != 0) {
            writer->beginObject(writer, KSCrashField_ExitReason);
            {
                writer->addUIntegerElement(writer, KSCrashField_Code, crash->exitReason.code);
            }
            writer->endContainer(writer);
        }

        // Write any current hang info if available
        if (crash->Hang.inProgress) {
            writer->beginObject(writer, KSCrashField_Hang);
            {
                writer->addUIntegerElement(writer, KSCrashField_HangStartNanoseconds, crash->Hang.timestamp);
                writer->addStringElement(writer, KSCrashField_HangStartRole, kscm_stringFromRole(crash->Hang.role));

                writer->addUIntegerElement(writer, KSCrashField_HangEndNanoseconds, crash->Hang.endTimestamp);
                writer->addStringElement(writer, KSCrashField_HangEndRole, kscm_stringFromRole(crash->Hang.endRole));
            }
            writer->endContainer(writer);
        }

        if (isCrashOfMonitorType(crash, kscm_watchdog_getAPI())) {
            // We're leaning towards a SIGKILL watchdog timeout
            if (crash->Hang.inProgress) {
                writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_Mach);
            }

            // This is going to be a non-fatal hang.
            else {
                writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_Hang);
            }

        }

        else if (isCrashOfMonitorType(crash, kscm_nsexception_getAPI())) {
            writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_NSException);
            writer->beginObject(writer, KSCrashField_NSException);
            {
                writer->addStringElement(writer, KSCrashField_Name, crash->NSException.name);
                writer->addStringElement(writer, KSCrashField_UserInfo, crash->NSException.userInfo);
                kscrmi_writeAddressReferencedByString(writer, KSCrashField_ReferencedObject, crash->crashReason);
            }
            writer->endContainer(writer);
        } else if (isCrashOfMonitorType(crash, kscm_machexception_getAPI())) {
            writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_Mach);
        } else if (isCrashOfMonitorType(crash, kscm_signal_getAPI())) {
            writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_Signal);
        } else if (isCrashOfMonitorType(crash, kscm_cppexception_getAPI())) {
            writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_CPPException);
            writer->beginObject(writer, KSCrashField_CPPException);
            {
                writer->addStringElement(writer, KSCrashField_Name, crash->CPPException.name);
            }
            writer->endContainer(writer);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        } else if (isCrashOfMonitorType(crash, kscm_deadlock_getAPI())) {
#pragma clang diagnostic pop
            writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_Deadlock);

        } else if (isCrashOfMonitorType(crash, kscm_memory_getAPI())) {
            writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_MemoryTermination);
            const KSCrashMonitorAPI *memoryAPI = kscm_memory_getAPI();
            if (memoryAPI != NULL && memoryAPI->writeInReportSection != NULL) {
                writer->beginObject(writer, KSCrashField_MemoryTermination);
                memoryAPI->writeInReportSection(crash, writer);
                writer->endContainer(writer);
            }
        } else if (isCrashOfMonitorType(crash, kscm_user_getAPI())) {
            writer->addStringElement(writer, KSCrashField_Type, KSCrashExcType_User);
            writer->beginObject(writer, KSCrashField_UserReported);
            {
                writer->addStringElement(writer, KSCrashField_Name, crash->userException.name);
                if (crash->userException.language != NULL) {
                    writer->addStringElement(writer, KSCrashField_Language, crash->userException.language);
                }
                if (crash->userException.lineOfCode != NULL) {
                    writer->addStringElement(writer, KSCrashField_LineOfCode, crash->userException.lineOfCode);
                }
                if (crash->userException.customStackTrace != NULL) {
                    writer->addJSONElement(writer, KSCrashField_Backtrace, crash->userException.customStackTrace, true);
                }
            }
            writer->endContainer(writer);
        } else if (isCrashOfMonitorType(crash, kscm_system_getAPI()) ||
                   isCrashOfMonitorType(crash, kscm_appstate_getAPI()) ||
                   isCrashOfMonitorType(crash, kscm_zombie_getAPI())) {
            KSLOG_ERROR("Crash monitor type %s shouldn't be able to cause events!", crash->monitorId);
        } else {
            // We now support custom monitors.
            writer->addStringElement(writer, KSCrashField_Type, crash->monitorId);
            const KSCrashMonitorAPI *api = kscm_getMonitor(crash->monitorId);
            if (api && api->writeInReportSection) {
                writer->beginObject(writer, crash->monitorId);
                {
                    api->writeInReportSection(crash, writer);
                }
                writer->endContainer(writer);
            }
        }
    }
    writer->endContainer(writer);
}

/** Write information about this process.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 */
static void writeProcessState(const KSCrashReportWriter *const writer, const char *const key,
                              const KSCrash_MonitorContext *const monitorContext)
{
    writer->beginObject(writer, key);
    {
        // Call Zombie monitor's writeMetadataInReportSection callback
        const KSCrashMonitorAPI *zombieAPI = kscm_zombie_getAPI();
        if (zombieAPI != NULL && zombieAPI->writeMetadataInReportSection != NULL) {
            zombieAPI->writeMetadataInReportSection(monitorContext, writer);
        }
    }
    writer->endContainer(writer);
}

/** Write basic report information.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param type The report type.
 *
 * @param reportID The report ID.
 */
static void writeReportInfo(const KSCrashReportWriter *const writer, const char *const key, const char *const type,
                            const char *const reportID, const char *const processName)
{
    writer->beginObject(writer, key);
    {
        writer->addStringElement(writer, KSCrashField_Version, KSCRASH_REPORT_VERSION);
        writer->addStringElement(writer, KSCrashField_ID, reportID);
        writer->addStringElement(writer, KSCrashField_ProcessName, processName);
        writer->addUIntegerElement(writer, KSCrashField_Timestamp, ksdate_microseconds());
        writer->addStringElement(writer, KSCrashField_Type, type);
    }
    writer->endContainer(writer);
}

static void writeRecrash(const KSCrashReportWriter *const writer, const char *const key, const char *crashReportPath)
{
    writer->addJSONFileElement(writer, key, crashReportPath, true);
}

#pragma mark Setup

/** Prepare a report writer for use.
 *
 * @param writer The writer to prepare.
 *
 * @param context JSON writer contextual information.
 */
static void prepareReportWriter(KSCrashReportWriter *const writer, KSJSONEncodeContext *const context)
{
    writer->addBooleanElement = addBooleanElement;
    writer->addFloatingPointElement = addFloatingPointElement;
    writer->addIntegerElement = addIntegerElement;
    writer->addUIntegerElement = addUIntegerElement;
    writer->addStringElement = addStringElement;
    writer->addTextFileElement = addTextFileElement;
    writer->addTextFileLinesElement = addTextLinesFromFile;
    writer->addJSONFileElement = addJSONElementFromFile;
    writer->addDataElement = addDataElement;
    writer->beginDataElement = beginDataElement;
    writer->appendDataElement = appendDataElement;
    writer->endDataElement = endDataElement;
    writer->addUUIDElement = addUUIDElement;
    writer->addJSONElement = addJSONElement;
    writer->beginObject = beginObject;
    writer->beginArray = beginArray;
    writer->endContainer = endContainer;
    writer->context = context;
}

// ============================================================================
#pragma mark - Main API -
// ============================================================================

void kscrashreport_writeRecrashReport(const KSCrash_MonitorContext *const monitorContext, const char *const path)
{
    char writeBuffer[1024];
    KSBufferedWriter bufferedWriter;
    static char tempPath[KSFU_MAX_PATH_LENGTH];
    strncpy(tempPath, path, sizeof(tempPath) - 10);
    strncpy(tempPath + strlen(tempPath) - 5, ".old", 5);
    KSLOG_INFO("Writing recrash report to %s", path);

    if (rename(path, tempPath) < 0) {
        KSLOG_ERROR("Could not rename %s to %s: %s", path, tempPath, strerror(errno));
    }
    if (!ksfu_openBufferedWriter(&bufferedWriter, path, writeBuffer, sizeof(writeBuffer))) {
        return;
    }

    kstc_freeze();

    KSJSONEncodeContext jsonContext;
    jsonContext.userData = &bufferedWriter;
    KSCrashReportWriter concreteWriter;
    KSCrashReportWriter *writer = &concreteWriter;
    prepareReportWriter(writer, &jsonContext);

    ksjson_beginEncode(getJsonContext(writer), true, addJSONData, &bufferedWriter);

    writer->beginObject(writer, KSCrashField_Report);
    {
        writeRecrash(writer, KSCrashField_RecrashReport, tempPath);
        ksfu_flushBufferedWriter(&bufferedWriter);
        if (remove(tempPath) < 0) {
            KSLOG_ERROR("Could not remove %s: %s", tempPath, strerror(errno));
        }
        writeReportInfo(writer, KSCrashField_Report, KSCrashReportType_Minimal, monitorContext->eventID,
                        kscm_system_getProcessName());
        ksfu_flushBufferedWriter(&bufferedWriter);

        writer->beginObject(writer, KSCrashField_Crash);
        {
            writeError(writer, KSCrashField_Error, monitorContext);
            ksfu_flushBufferedWriter(&bufferedWriter);
            KSThread thread = ksmc_getThreadFromContext(monitorContext->offendingMachineContext);
            int threadIndex = ksmc_indexOfThread(monitorContext->offendingMachineContext, thread);
            int threadRunState = ksthread_getThreadState(thread);
            writeThread(writer, KSCrashField_CrashedThread, monitorContext, monitorContext->offendingMachineContext,
                        threadIndex, false, threadRunState);
            ksfu_flushBufferedWriter(&bufferedWriter);
        }
        writer->endContainer(writer);

        if (g_userSectionWriteCallback != NULL) {
            writer->beginObject(writer, KSCrashField_User);
            ksfu_flushBufferedWriter(&bufferedWriter);
            KSCrash_ExceptionHandlingPlan plan = ksexc_monitorContextToPlan(monitorContext);
            g_userSectionWriteCallback(&plan, writer);
            writer->endContainer(writer);
        }
    }
    writer->endContainer(writer);

    ksjson_endEncode(getJsonContext(writer));
    ksfu_closeBufferedWriter(&bufferedWriter);
    kstc_unfreeze();
}

static void writeSystemInfo(const KSCrashReportWriter *const writer, const char *const key,
                            const KSCrash_MonitorContext *const monitorContext)
{
    writer->beginObject(writer, key);
    {
        // Call System monitor's writeMetadataInReportSection callback
        const KSCrashMonitorAPI *systemAPI = kscm_system_getAPI();
        if (systemAPI != NULL && systemAPI->writeMetadataInReportSection != NULL) {
            systemAPI->writeMetadataInReportSection(monitorContext, writer);
        }

        // Call AppState monitor's writeMetadataInReportSection callback
        const KSCrashMonitorAPI *appStateAPI = kscm_appstate_getAPI();
        if (appStateAPI != NULL && appStateAPI->writeMetadataInReportSection != NULL) {
            writer->beginObject(writer, KSCrashField_AppStats);
            appStateAPI->writeMetadataInReportSection(monitorContext, writer);
            writer->endContainer(writer);
        }

        // Call Memory monitor's writeMetadataInReportSection callback
        const KSCrashMonitorAPI *memoryAPI = kscm_memory_getAPI();
        if (memoryAPI != NULL && memoryAPI->writeMetadataInReportSection != NULL) {
            writer->beginObject(writer, KSCrashField_AppMemory);
            memoryAPI->writeMetadataInReportSection(monitorContext, writer);
            writer->endContainer(writer);
        }
    }
    writer->endContainer(writer);
}

static void writeDebugInfo(const KSCrashReportWriter *const writer, const char *const key,
                           const KSCrash_MonitorContext *const monitorContext)
{
    writer->beginObject(writer, key);
    {
        if (monitorContext->consoleLogPath != NULL) {
            addTextLinesFromFile(writer, KSCrashField_ConsoleLog, monitorContext->consoleLogPath);
        }
    }
    writer->endContainer(writer);
}

void kscrashreport_writeStandardReport(KSCrash_MonitorContext *const monitorContext, const char *const path)
{
    KSLOG_INFO("Writing crash report to %s", path);
    char writeBuffer[1024];
    KSBufferedWriter bufferedWriter;

    if (!ksfu_openBufferedWriter(&bufferedWriter, path, writeBuffer, sizeof(writeBuffer))) {
        return;
    }

    kstc_freeze();

    KSJSONEncodeContext jsonContext;
    jsonContext.userData = &bufferedWriter;
    KSCrashReportWriter concreteWriter;
    KSCrashReportWriter *writer = &concreteWriter;
    prepareReportWriter(writer, &jsonContext);

    ksjson_beginEncode(getJsonContext(writer), true, addJSONData, &bufferedWriter);

    writer->beginObject(writer, KSCrashField_Report);
    {
        writeReportInfo(writer, KSCrashField_Report, KSCrashReportType_Standard, monitorContext->eventID,
                        kscm_system_getProcessName());
        ksfu_flushBufferedWriter(&bufferedWriter);

        if (!monitorContext->omitBinaryImages) {
            writeBinaryImages(writer, KSCrashField_BinaryImages);
            ksfu_flushBufferedWriter(&bufferedWriter);
        }

        writeProcessState(writer, KSCrashField_ProcessState, monitorContext);
        ksfu_flushBufferedWriter(&bufferedWriter);

        writeSystemInfo(writer, KSCrashField_System, monitorContext);
        ksfu_flushBufferedWriter(&bufferedWriter);

        writer->beginObject(writer, KSCrashField_Crash);
        {
            writeError(writer, KSCrashField_Error, monitorContext);
            ksfu_flushBufferedWriter(&bufferedWriter);
            writeThreads(writer, KSCrashField_Threads, monitorContext, kscrmi_isIntrospectionEnabled());
            ksfu_flushBufferedWriter(&bufferedWriter);
            if (monitorContext->suspendedThreadsCount > 0) {
                // Special case: If we only needed to suspend the environment to record the threads, then we can
                // safely resume now. This gives any remaining callbacks more freedom.
                monitorContext->requirements.asyncSafetyBecauseThreadsSuspended = false;
                if (!kscexc_requiresAsyncSafety(monitorContext->requirements)) {
                    ksmc_resumeEnvironment(&monitorContext->suspendedThreads, &monitorContext->suspendedThreadsCount);
                }
            }
        }
        writer->endContainer(writer);

        // Acquire lock to read userInfo (async-signal-safe bounded spin)
        bool userInfoLocked = ks_spinlock_lock_bounded(&g_userInfoLock);

        if (userInfoLocked && g_userInfoJSON != NULL) {
            addJSONElement(writer, KSCrashField_User, g_userInfoJSON, false);
            ksfu_flushBufferedWriter(&bufferedWriter);
        } else {
            writer->beginObject(writer, KSCrashField_User);
        }

        // Release the lock
        if (userInfoLocked) {
            ks_spinlock_unlock(&g_userInfoLock);
        }

        if (g_userSectionWriteCallback != NULL) {
            ksfu_flushBufferedWriter(&bufferedWriter);
            KSCrash_ExceptionHandlingPlan plan = ksexc_monitorContextToPlan(monitorContext);
            g_userSectionWriteCallback(&plan, writer);
        }
        writer->endContainer(writer);
        ksfu_flushBufferedWriter(&bufferedWriter);

        writeDebugInfo(writer, KSCrashField_Debug, monitorContext);
    }
    writer->endContainer(writer);

    ksjson_endEncode(getJsonContext(writer));
    ksfu_closeBufferedWriter(&bufferedWriter);
    kstc_unfreeze();
}

void kscrashreport_setUserInfoJSON(const char *const userInfoJSON)
{
    KSLOG_TRACE("Setting userInfoJSON to %p", userInfoJSON);

    // Acquire lock
    ks_spinlock_lock(&g_userInfoLock);

    // Update the JSON
    free(g_userInfoJSON);
    g_userInfoJSON = (userInfoJSON != NULL) ? strdup(userInfoJSON) : NULL;

    // Release lock
    ks_spinlock_unlock(&g_userInfoLock);
}

const char *kscrashreport_getUserInfoJSON(void)
{
    // Acquire lock
    ks_spinlock_lock(&g_userInfoLock);

    // Copy the value
    const char *copy = (g_userInfoJSON != NULL) ? strdup(g_userInfoJSON) : NULL;

    // Release lock
    ks_spinlock_unlock(&g_userInfoLock);

    return copy;
}

void kscrashreport_setIntrospectMemory(bool shouldIntrospectMemory)
{
    kscrmi_setIntrospectMemory(shouldIntrospectMemory);
}

void kscrashreport_setDoNotIntrospectClasses(const char **doNotIntrospectClasses, int length)
{
    kscrmi_setDoNotIntrospectClasses(doNotIntrospectClasses, length);
}

void kscrashreport_setIsWritingReportCallback(const KSCrashIsWritingReportCallback isWritingReportCallback)
{
    KSLOG_TRACE("Set isWritingReportCallback to %p", isWritingReportCallback);
    g_userSectionWriteCallback = isWritingReportCallback;
}
