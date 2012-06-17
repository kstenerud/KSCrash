//
//  KSCrashReportWriter.m
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


#include "KSCrashReportWriter.h"

#include "KSBacktrace_private.h"
#include "KSFileUtils.h"
#include "KSJSONCodec.h"
#include "KSLogger.h"
#include "KSMach.h"
#include "KSReportWriter.h"
#include "KSSignalInfo.h"

#include <mach-o/dyld.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>


/** Version number written to the report. */
#define kReportVersionMajor 1
#define kReportVersionMinor 0

/** Maximum depth allowed for a backtrace. */
#define kMaxBacktraceDepth 50

/** Length at which we consider a backtrace to represent a stack overflow.
 * If it reaches this point, we start cutting off from the top of the stack
 * rather than the bottom.
 */
#define kOverflowThreshold 200


#if defined(__LP64__)
    #define TRACE_FMT         "%-4d%-31s 0x%016llx %s + %llu\n"
    #define POINTER_FMT       "0x%016llx"
    #define POINTER_SHORT_FMT "0x%llx"
#else
    #define TRACE_FMT         "%-4d%-31s 0x%08lx %s + %lu\n"
    #define POINTER_FMT       "0x%08lx"
    #define POINTER_SHORT_FMT "0x%lx"
#endif


// Avoiding static functions due to linker issues.

/** Print a stack trace entry in the standard format.
 *
 * @param entryNum The stack entry number.
 *
 * @param pc The program counter value (instruction address).
 *
 * @param dlInfo Information about the nearest symbols to the pc.
 */
#if KSLOG_PRINTS_AT_LEVEL(KSLogger_Level_Info)
void kscrw_i_printStackTraceEntry(const int entryNum,
                                  const uintptr_t pc,
                                  Dl_info* const dlInfo);
#endif

/** Write a backtrace.
 *
 * @param writer The writer to write the backtrace to.
 *
 * @param backtrace The backtrace to write.
 *
 * @param backtraceLength Length of the backtrace.
 *
 * @param printToStdout If true, also print a trace to stdout.
 */
void kscrw_i_writeBacktrace(const KSReportWriter* const writer,
                            const uintptr_t* const backtrace,
                            const int backtraceLength,
                            const bool printToStdout);

/** Write out the contents of all regular registers.
 *
 * @param writer The writer.
 *
 * @param machineContext The context to retrieve the registers from.
 */
void kscrw_i_writeRegisters(const KSReportWriter* const writer,
                            const _STRUCT_MCONTEXT* const machineContext);

/** Write out the contents of all exception registers.
 *
 * @param writer The writer.
 *
 * @param machineContext The context to retrieve the registers from.
 */
void kscrw_i_writeExceptionRegisters(const KSReportWriter* const writer,
                                     const _STRUCT_MCONTEXT* const machineContext);

/** Get all parts of the machine state required for a dump.
 * This includes basic thread state, and exception registers.
 *
 * @param thread The thread to get state for.
 *
 * @param machineContext The machine context to fill out.
 */
bool kscrw_i_fetchMachineState(const thread_t thread,
                               _STRUCT_MCONTEXT* const machineContext);

/** Write out information about all threads.
 *
 * @param writer The writer.
 *
 * @param crashContext Information about the crash.
 */
void kscrw_i_writeAllThreads(const KSReportWriter* const writer,
                             KSCrashContext* const crashContext);

/** Write out a list of all loaded binary images.
 *
 * @param writer The writer.
 */
void kscrw_i_writeBinaryImages(const KSReportWriter* const writer);

/** Write out some information about the machine.
 *
 * @param writer The writer.
 */
void kscrw_i_writeMachineStats(const KSReportWriter* const writer);

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
                                  const int maxLength);

/** Get the name of a mach exception code.
 *
 * It will fill the buffer with the code name, or a number in the format
 * 0x00000000 if it couldn't identify the exception code.
 *
 * @param machCode The mach exception code.
 *
 * @param buffer Buffer to hold the name.
 *
 * @param maxLength The length of the buffer.
 */
void kscrw_i_getMachCodeName(const int machCode,
                             char* const buffer,
                             const int maxLength);

/** Write information about the error.
 *
 * @param writer The writer.
 *
 * @param crashContext Information about the crash.
 */
void kscrw_i_writeErrorInfo(const KSReportWriter* const writer,
                            const KSCrashContext* const crashContext);

/** Prepare a report writer for use.
 *
 * @oaram writer The writer to prepare.
 *
 * @param context JSON writer contextual information.
 */
void kscrw_i_prepareReportWriter(KSReportWriter* const writer,
                                 KSJSONEncodeContext* const context);

void kscrw_i_addJSONElement(KSReportWriter* writer,
                            const char* name,
                            const char* jsonElement);


/* Various callbacks.
 */
void kscrw_i_addBooleanElement(const KSReportWriter* const writer,
                               const char* const name,
                               const bool value);

void kscrw_i_addFloatingPointElement(const KSReportWriter* const writer,
                                     const char* const name,
                                     const double value);

void kscrw_i_addIntegerElement(const KSReportWriter* const writer,
                               const char* const name,
                               const long long value);

void kscrw_i_addUIntegerElement(const KSReportWriter* const writer,
                                const char* const name,
                                const unsigned long long value);

void kscrw_i_addStringElement(const KSReportWriter* const writer,
                              const char* const name,
                              const char* const value);

void kscrw_i_addTextFileElement(const KSReportWriter* const writer,
                                const char* const name,
                                const char* const filePath);

void kscrw_i_addUUIDElement(const KSReportWriter* const writer,
                            const char* const name,
                            const unsigned char* const value);

void kscrw_i_beginObject(const KSReportWriter* const writer,
                         const char* const name);

void kscrw_i_beginArray(const KSReportWriter* const writer,
                        const char* const name);

void kscrw_i_endContainer(const KSReportWriter* const writer);

int kscrw_i_addJSONData(const char* const data,
                        const size_t length,
                        void* const userData);


#if KSLOG_PRINTS_AT_LEVEL(KSLogger_Level_Info)
void kscrw_i_printStackTraceEntry(const int entryNum,
                                  const uintptr_t pc,
                                  Dl_info* const dlInfo)
{
    char faddrBuff[20];
    char saddrBuff[20];
    
    const char* fname = ksfu_lastPathEntry(dlInfo->dli_fname);
    if(fname == NULL)
    {
        sprintf(faddrBuff, POINTER_FMT, (uintptr_t)dlInfo->dli_fbase);
        fname = faddrBuff;
    }
    
    uintptr_t offset = pc - (uintptr_t)dlInfo->dli_saddr;
    const char* sname = dlInfo->dli_sname;
    if(sname == NULL)
    {
        sprintf(saddrBuff, POINTER_SHORT_FMT, (uintptr_t)dlInfo->dli_fbase);
        sname = saddrBuff;
        offset = pc - (uintptr_t)dlInfo->dli_fbase;
    }
    
    KSLOGBASIC_INFO(TRACE_FMT,
                    entryNum,
                    fname,
                    pc,
                    sname,
                    offset);
}
#else
    #define printStackTraceEntry(A,B,C)
#endif

void kscrw_i_writeBacktrace(const KSReportWriter* const writer,
                            const uintptr_t* const backtrace,
                            const int backtraceLength,
                            const bool printToStdout)
{
    if(backtraceLength > 0)
    {
        Dl_info symbolicated[backtraceLength];
        ksbt_symbolicate(backtrace, symbolicated, backtraceLength);
        
        writer->beginArray(writer, "backtrace");
        for(int i = 0; i < backtraceLength; i++)
        {
            writer->beginObject(writer, NULL);
            const uintptr_t instructionAddr = backtrace[i];
            if(symbolicated[i].dli_fname != NULL)
            {
                writer->addStringElement(writer, "object_name", ksfu_lastPathEntry(symbolicated[i].dli_fname));
            }
            writer->addUIntegerElement(writer, "object_addr", (uintptr_t)symbolicated[i].dli_fbase);
            if(symbolicated[i].dli_sname != NULL)
            {
                writer->addStringElement(writer, "symbol_name", symbolicated[i].dli_sname);
            }
            writer->addUIntegerElement(writer, "symbol_addr", (uintptr_t)symbolicated[i].dli_saddr);
            writer->addUIntegerElement(writer, "instruction_addr", (uintptr_t)instructionAddr);
            writer->endContainer(writer);
            if(printToStdout)
            {
                kscrw_i_printStackTraceEntry(i, instructionAddr, &symbolicated[i]);
            }
        }
        writer->endContainer(writer);
    }
}

void kscrw_i_writeRegisters(const KSReportWriter* const writer,
                            const _STRUCT_MCONTEXT* const machineContext)
{
    char registerNameBuff[30];
    const char* registerName;
    writer->beginObject(writer, "registers");
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
    writer->endContainer(writer);
}

void kscrw_i_writeExceptionRegisters(const KSReportWriter* const writer,
                                     const _STRUCT_MCONTEXT* const machineContext)
{
    char registerNameBuff[30];
    const char* registerName;
    writer->beginObject(writer, "exception_registers");
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
    writer->endContainer(writer);
}

bool kscrw_i_fetchMachineState(const thread_t thread,
                               _STRUCT_MCONTEXT* const machineContext)
{
    if(!ksmach_threadState(thread, machineContext))
    {
        return false;
    }
    
    if(!ksmach_exceptionState(thread, machineContext))
    {
        return false;
    }
    
    return true;
}

void kscrw_i_writeAllThreads(const KSReportWriter* const writer,
                             KSCrashContext* const crashContext)
{
    kern_return_t kr;
    
    // Task & thread info
    const task_t thisTask = mach_task_self();
    const thread_t thisThread = mach_thread_self();
    thread_act_array_t threads;
    mach_msg_type_number_t numThreads;
    
    // Used for register and stack trace retrieval
    // Context may be a local copy or a pointer to somewhere else.
    _STRUCT_MCONTEXT concreteMachineContext;
    _STRUCT_MCONTEXT* machineContext;
    
    // Holds the actual backtrace.
    // Backtrace may be a local copy or a pointer to somewhere else.
    uintptr_t concreteBacktrace[kMaxBacktraceDepth];
    uintptr_t* backtrace;
    int backtraceLength;
    int skipEntries;
    
    // Holds the name of the thread
    char threadName[100] = {0};
    
    // Flags
    bool mustFetchBacktrace;
    bool registersAreValid;
    bool isCrashedThread;
    
    
    // Get a list of all threads.
    if((kr = task_threads(thisTask, &threads, &numThreads)) != KERN_SUCCESS)
    {
        KSLOG_ERROR("task_threads: %s", mach_error_string(kr));
        return;
    }
    
    // Fetch info for all threads.
    writer->beginArray(writer, "threads");
    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
    {
        thread_t thread = threads[i];
        pthread_t pthread = pthread_from_mach_thread_np(thread);
        
        if(thread == thisThread)
        {
            // We're looking at the current thread. Decide what to do based
            // on the crash type.
            switch(crashContext->crashType)
            {
                case KSCrashTypeSignal:
                    // Signals provide a machine context that we can get the
                    // stack trace from.
                    isCrashedThread = true;
                    registersAreValid = true;
                    machineContext = crashContext->signalUserContext->uc_mcontext;
                    mustFetchBacktrace = true;
                    break;
                case KSCrashTypeNSException:
                    // NSException conveniently provides a stack trace for us.
                    // No registers, unfortunately.
                    isCrashedThread = true;
                    registersAreValid = false;
                    machineContext = NULL;
                    backtrace = crashContext->NSExceptionStackTrace;
                    backtraceLength = crashContext->NSExceptionStackTraceLength;
                    mustFetchBacktrace = false;
                    break;
                case KSCrashTypeMachException:
                    // Mach exceptions are reported by the mach exception
                    // handler thread. We can't reliably get the stack trace
                    // of a running thread (and it wouldn't be useful for
                    // debugging anyway), so just ignore it.
                    continue;
            }
        }
        else
        {
            // This is not the current thread, and we paused all threads
            // already, so we can reliably fetch the machine state.
            isCrashedThread = thread == crashContext->machCrashedThread;
            registersAreValid = true;
            machineContext = &concreteMachineContext;
            if(!kscrw_i_fetchMachineState(thread, machineContext))
            {
                KSLOG_ERROR("Failed to fetch machine state for thread %d",
                            thread);
                continue;
            }
            mustFetchBacktrace = true;
        }
        
        // Fetch the backtrace if necessary.
        skipEntries = 0;
        if(mustFetchBacktrace)
        {
            backtrace = concreteBacktrace;
            backtraceLength = ksbt_backtraceLength(machineContext);
            if(backtraceLength > kOverflowThreshold)
            {
                crashContext->isStackOverflow = true;
                skipEntries = backtraceLength - kMaxBacktraceDepth;
            }
            
            backtraceLength = ksbt_backtraceThreadState(machineContext,
                                                        backtrace,
                                                        skipEntries,
                                                        kMaxBacktraceDepth);
        }
        
        // All information fetched. Print it out.
        writer->beginObject(writer, NULL);
        kscrw_i_writeBacktrace(writer,
                               backtrace,
                               backtraceLength,
                               crashContext->printTraceToStdout);
        writer->addIntegerElement(writer, "backtrace_skipped", skipEntries);
        if(registersAreValid)
        {
            kscrw_i_writeRegisters(writer, machineContext);
            if(isCrashedThread)
            {
                kscrw_i_writeExceptionRegisters(writer, machineContext);
            }
        }
        if(pthread_getname_np(pthread, threadName, sizeof(threadName)) == 0 &&
           threadName[0] != 0)
        {
            writer->addStringElement(writer, "name", threadName);
        }
        
        if(ksmach_getThreadQueueName(thread, threadName, sizeof(threadName)))
        {
            writer->addStringElement(writer, "dispatch_queue", threadName);
        }
        writer->addBooleanElement(writer, "crashed", isCrashedThread);
        writer->endContainer(writer);
    }
    writer->endContainer(writer);
    
    // Clean up.
    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
    {
        mach_port_deallocate(thisTask, threads[i]);
    }
    vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * numThreads);
}

void kscrw_i_writeBinaryImages(const KSReportWriter* const writer)
{
    const uint32_t imageCount = _dyld_image_count();
    
    writer->beginArray(writer, "binary_images");
    
    // Dump all images.
    for(uint32_t iImg = 0; iImg < imageCount; iImg++)
    {
        writer->beginObject(writer, NULL);
        const struct mach_header* header = _dyld_get_image_header(iImg);
        if(header != NULL)
        {
            // Look for the TEXT segment to get the image size.
            // Also look for a UUID command.
            uint64_t imageSize = 0;
            uint8_t* uuid = NULL;
            uintptr_t cmdPtr = ksmach_firstCmdAfterHeader(header);
            if(cmdPtr == 0)
            {
                continue;
            }
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
            writer->addUIntegerElement(writer, "image_addr", (uintptr_t)header);
            writer->addUIntegerElement(writer, "image_size", imageSize);
            writer->addStringElement(writer, "name", _dyld_get_image_name(iImg));
            writer->addUUIDElement(writer, "uuid", uuid);
            writer->addIntegerElement(writer, "cpu_type", header->cputype);
            writer->addIntegerElement(writer, "cpu_subtype", header->cpusubtype);
        }
        writer->endContainer(writer);
    }
    
    writer->endContainer(writer);
}

void kscrw_i_writeMachineStats(const KSReportWriter* const writer)
{
    writer->addUIntegerElement(writer, "usable_memory", ksmach_usableMemory());
    writer->addUIntegerElement(writer, "free_memory", ksmach_freeMemory());
}

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

void kscrw_i_writeErrorInfo(const KSReportWriter* const writer,
                            const KSCrashContext* const crashContext)
{
    int machExceptionType;
    kern_return_t machCode;
    kern_return_t machSubCode;
    int sigNum;
    int sigCode;
    
    writer->beginObject(writer, "error");
    
    // Gather common info.
    switch(crashContext->crashType)
    {
        case KSCrashTypeMachException:
            machExceptionType = crashContext->machExceptionType;
            machCode = (kern_return_t)crashContext->machExceptionCode;
            if(machCode == KERN_PROTECTION_FAILURE && crashContext->isStackOverflow)
            {
                // A stack overflow should return KERN_INVALID_ADDRESS, but
                // when a stack blasts through the guard pages at the top of the stack,
                // it generates KERN_PROTECTION_FAILURE. Correct for this.
                machCode = KERN_INVALID_ADDRESS;
            }
            machSubCode = (kern_return_t)crashContext->machExceptionSubcode;
            
            sigNum = kssignal_signalForMachException(crashContext->machExceptionType,
                                                     machCode);
            sigCode = 0;
            break;
            
        case KSCrashTypeNSException:
            machExceptionType = EXC_CRASH;
            machCode = 0;
            machSubCode = 0;
            sigNum = SIGABRT;
            sigCode = 0;
            break;
            
        case KSCrashTypeSignal:
            sigNum = crashContext->signalInfo->si_signo;
            sigCode = crashContext->signalInfo->si_code;
            machExceptionType = kssignal_machExceptionForSignal(sigNum);
            machCode = 0;
            machSubCode = 0;
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
    
    writer->addStringElement(writer, "mach_exception", machExceptionName);
    writer->addUIntegerElement(writer, "mach_code", (unsigned)machCode);
    writer->addStringElement(writer, "mach_code_name", machCodeName);
    writer->addUIntegerElement(writer, "mach_subcode", (unsigned)machSubCode);
    writer->addUIntegerElement(writer, "signal", (unsigned)sigNum);
    writer->addStringElement(writer, "signal_name", sigName);
    writer->addUIntegerElement(writer, "signal_code", (unsigned)sigCode);
    writer->addStringElement(writer, "signal_code_name", sigCodeName);
    writer->addUIntegerElement(writer, "address", crashContext->faultAddress);
    
    // Gather specific info.
    switch(crashContext->crashType)
    {
        case KSCrashTypeMachException:
            writer->addStringElement(writer, "type", "mach");
            
            KSLOGBASIC_INFO("App crashed due to mach exception %s: %s",
                            machExceptionName, machCodeName);
            break;
            
        case KSCrashTypeNSException:
            if(crashContext->NSExceptionName != NULL)
            {
                writer->addStringElement(writer, "nsexception_name", crashContext->NSExceptionName);
            }
            if(crashContext->NSExceptionReason != NULL)
            {
                writer->addStringElement(writer, "nsexception_reason", crashContext->NSExceptionReason);
            }
            writer->addStringElement(writer, "type", "nsexception");
            
            KSLOGBASIC_INFO("App crashed due to exception %s: %s",
                            crashContext->NSExceptionName,
                            crashContext->NSExceptionReason);
            break;
            
        case KSCrashTypeSignal:
            writer->addStringElement(writer, "type", "signal");
            
            KSLOGBASIC_INFO("App crashed due to signal [%s, %s] at %08x",
                            sigName, sigCodeName, crashContext->faultAddress);
    }
    
    if(crashContext->crashType == KSCrashTypeNSException)
    {
        writer->beginObject(writer, "nsexception");
        
        if(crashContext->NSExceptionName != NULL)
        {
            writer->addStringElement(writer, "name", crashContext->NSExceptionName);
        }
        if(crashContext->NSExceptionReason != NULL)
        {
            writer->addStringElement(writer, "reason", crashContext->NSExceptionReason);
        }
        
        if(crashContext->printTraceToStdout)
        {
            KSLOGBASIC_INFO("\nNSException Backtrace:\n");
        }
        kscrw_i_writeBacktrace(writer,
                               crashContext->NSExceptionStackTrace,
                               crashContext->NSExceptionStackTraceLength,
                               crashContext->printTraceToStdout);
        
        
        writer->endContainer(writer);
    }
    
    writer->endContainer(writer);
}

#define getJsonContext(REPORT_WRITER) ((KSJSONEncodeContext*)((REPORT_WRITER)->context))

/** Used for writing hex string values. */
static char g_hexNybbles[] =
{
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
};

void kscrw_i_addBooleanElement(const KSReportWriter* const writer,
                               const char* const name,
                               const bool value)
{
    ksjson_addBooleanElement(getJsonContext(writer), name, value);
}

void kscrw_i_addFloatingPointElement(const KSReportWriter* const writer,
                                     const char* const name,
                                     const double value)
{
    ksjson_addFloatingPointElement(getJsonContext(writer), name, value);
}

void kscrw_i_addIntegerElement(const KSReportWriter* const writer,
                               const char* const name,
                               const long long value)
{
    ksjson_addIntegerElement(getJsonContext(writer), name, value);
}

void kscrw_i_addUIntegerElement(const KSReportWriter* const writer,
                                const char* const name,
                                const unsigned long long value)
{
    ksjson_addIntegerElement(getJsonContext(writer), name, (long long)value);
}

void kscrw_i_addStringElement(const KSReportWriter* const writer,
                              const char* const name,
                              const char* const value)
{
    if(name == NULL)
    {
        ksjson_addNullElement(getJsonContext(writer), name);
    }
    else
    {
        ksjson_addStringElement(getJsonContext(writer), name, value, strlen(value));
    }
}

void kscrw_i_addTextFileElement(const KSReportWriter* const writer,
                                const char* const name,
                                const char* const filePath)
{
    const int fd = open(filePath, O_RDONLY);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open file %s: %s", filePath, strerror(errno));
        return;
    }
    
    if(!ksjson_beginStringElement(getJsonContext(writer), name))
    {
        goto done;
    }
    
    char buffer[512];
    ssize_t bytesRead;
    for(bytesRead = read(fd, buffer, sizeof(buffer));
        bytesRead > 0;
        bytesRead = read(fd, buffer, sizeof(buffer)))
    {
        if(!ksjson_appendStringElement(getJsonContext(writer),
                                       buffer,
                                       (size_t)bytesRead))
        {
            goto done;
        }
    }
    
done:
    ksjson_endStringElement(getJsonContext(writer));
    close(fd);
}

void kscrw_i_addUUIDElement(const KSReportWriter* const writer,
                            const char* const name,
                            const unsigned char* const value)
{
    if(value == NULL)
    {
        ksjson_addNullElement(getJsonContext(writer), name);
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
                                name,
                                uuidBuffer,
                                (size_t)(dst - uuidBuffer));
    }
}

void kscrw_i_beginObject(const KSReportWriter* const writer,
                         const char* const name)
{
    ksjson_beginObject(getJsonContext(writer), name);
}

void kscrw_i_beginArray(const KSReportWriter* const writer,
                        const char* const name)
{
    ksjson_beginArray(getJsonContext(writer), name);
}

void kscrw_i_endContainer(const KSReportWriter* const writer)
{
    ksjson_endContainer(getJsonContext(writer));
}


void kscrw_i_prepareReportWriter(KSReportWriter* const writer,
                                 KSJSONEncodeContext* const context)
{
    writer->addBooleanElement = kscrw_i_addBooleanElement;
    writer->addFloatingPointElement = kscrw_i_addFloatingPointElement;
    writer->addIntegerElement = kscrw_i_addIntegerElement;
    writer->addUIntegerElement = kscrw_i_addUIntegerElement;
    writer->addStringElement = kscrw_i_addStringElement;
    writer->addTextFileElement = kscrw_i_addTextFileElement;
    writer->addUUIDElement = kscrw_i_addUUIDElement;
    writer->beginObject = kscrw_i_beginObject;
    writer->beginArray = kscrw_i_beginArray;
    writer->endContainer = kscrw_i_endContainer;
    writer->context = context;
}

int kscrw_i_addJSONData(const char* const data,
                        const size_t length,
                        void* const userData)
{
    const int fd = *((int*)userData);
    const bool success = ksfu_writeBytesToFD(fd, data, (ssize_t)length);
    return success ? KSJSON_OK : KSJSON_ERROR_CANNOT_ADD_DATA;
}

void kscrw_i_addJSONElement(KSReportWriter* writer,
                            const char* name,
                            const char* jsonElement)
{
    int jsonResult = ksjson_addJSONElement(getJsonContext(writer),
                                           name,
                                           jsonElement,
                                           strlen(jsonElement));
    if(jsonResult != KSJSON_OK)
    {
        char errorBuff[100];
        snprintf(errorBuff,
                 sizeof(errorBuff),
                 "Invalid JSON data: %s",
                 ksjson_stringForError(jsonResult));
        ksjson_beginObject(getJsonContext(writer), name);
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

void kscrash_writeCrashReport(KSCrashContext* const crashContext,
                              const char* const path)
{
    int fd = open(path, O_RDWR | O_CREAT | O_EXCL, 0644);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open crash report file %s: %s",
                    path,
                    strerror(errno));
        return;
    }
    
    KSJSONEncodeContext jsonContext;
    jsonContext.userData = &fd;
    KSReportWriter concreteWriter;
    KSReportWriter* writer = &concreteWriter;
    kscrw_i_prepareReportWriter(writer, &jsonContext);
    
    ksjson_beginEncode(getJsonContext(writer),
                       true,
                       kscrw_i_addJSONData,
                       &fd);
    writer->beginObject(writer, NULL);
    {
        writer->addIntegerElement(writer, "report_version_major", kReportVersionMajor);
        writer->addIntegerElement(writer, "report_version_minor", kReportVersionMinor);
        writer->addStringElement(writer, "crash_id", crashContext->crashID);
        writer->addIntegerElement(writer, "timestamp", time(NULL));
        if(crashContext->systemInfoJSON != NULL)
        {
            kscrw_i_addJSONElement(writer, "system", crashContext->systemInfoJSON);
        }
        writer->beginObject(writer, "system_atcrash");
        {
            kscrw_i_writeMachineStats(writer);
            
            writer->addBooleanElement(writer, "application_active",
                                      crashContext->applicationIsActive);
            writer->addBooleanElement(writer, "application_in_foreground",
                                      crashContext->applicationIsInForeground);
            
            writer->addIntegerElement(writer, "launches_since_last_crash",
                                      crashContext->launchesSinceLastCrash);
            writer->addIntegerElement(writer, "sessions_since_last_crash",
                                      crashContext->sessionsSinceLastCrash);
            writer->addFloatingPointElement(writer,
                                            "active_time_since_last_crash",
                                            crashContext->activeDurationSinceLastCrash);
            writer->addFloatingPointElement(writer,
                                            "background_time_since_last_crash",
                                            crashContext->backgroundDurationSinceLastCrash);
            
            writer->addIntegerElement(writer, "sessions_since_launch",
                                      crashContext->sessionsSinceLaunch);
            writer->addFloatingPointElement(writer,
                                            "active_time_since_launch",
                                            crashContext->activeDurationSinceLaunch);
            writer->addFloatingPointElement(writer,
                                            "background_time_since_launch",
                                            crashContext->backgroundDurationSinceLaunch);
        }
        writer->endContainer(writer);
        
        writer->beginObject(writer, "crash");
        {
            kscrw_i_writeAllThreads(writer, crashContext);
            kscrw_i_writeErrorInfo(writer, crashContext);
            kscrw_i_writeBinaryImages(writer);
        }
        writer->endContainer(writer);
        
        if(crashContext->userInfoJSON != NULL)
        {
            kscrw_i_addJSONElement(writer, "user", crashContext->userInfoJSON);
        }
        if(crashContext->onCrashNotify != NULL)
        {
            writer->beginObject(writer, "user_atcrash");
            crashContext->onCrashNotify(writer);
            writer->endContainer(writer);
        }
    }
    writer->endContainer(writer);
    ksjson_endEncode(getJsonContext(writer));
    
    close(fd);
}
