//
//  KSCrashReportMemoryIntrospection.c
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

#include "KSCrashReportMemoryIntrospection.h"

#include <stdlib.h>
#include <string.h>

#include "KSCrashMonitor_Zombie.h"
#include "KSCrashReportFields.h"
#include "KSLogger.h"
#include "KSMemory.h"
#include "KSObjC.h"
#include "KSString.h"
#include "KSSystemCapabilities.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

typedef struct {
    /** If YES, introspect memory contents during a crash. */
    bool enabled;

    /** List of classes that should never be introspected. */
    const char **restrictedClasses;
    int restrictedClassesCount;
} KSCrash_IntrospectionRules;

static KSCrash_IntrospectionRules g_introspectionRules = { 0 };

// ============================================================================
#pragma mark - Configuration -
// ============================================================================

void kscrmi_setIntrospectMemory(bool shouldIntrospectMemory) { g_introspectionRules.enabled = shouldIntrospectMemory; }

bool kscrmi_isIntrospectionEnabled(void) { return g_introspectionRules.enabled; }

void kscrmi_setDoNotIntrospectClasses(const char **doNotIntrospectClasses, int length)
{
    const char **oldClasses = g_introspectionRules.restrictedClasses;
    int oldClassesLength = g_introspectionRules.restrictedClassesCount;
    const char **newClasses = NULL;
    int newClassesLength = 0;

    if (doNotIntrospectClasses != NULL && length > 0) {
        newClassesLength = length;
        newClasses = malloc(sizeof(*newClasses) * (unsigned)newClassesLength);
        if (newClasses == NULL) {
            KSLOG_ERROR("Could not allocate memory");
            return;
        }

        for (int i = 0; i < newClassesLength; i++) {
            newClasses[i] = strdup(doNotIntrospectClasses[i]);
        }
    }

    g_introspectionRules.restrictedClasses = newClasses;
    g_introspectionRules.restrictedClassesCount = newClassesLength;

    if (oldClasses != NULL) {
        for (int i = 0; i < oldClassesLength; i++) {
            free((void *)oldClasses[i]);
        }
        free(oldClasses);
    }
}

// ============================================================================
#pragma mark - Utility -
// ============================================================================

bool kscrmi_isValidString(const void *address)
{
    if ((void *)address == NULL) {
        return false;
    }

    char buffer[500];
    if ((uintptr_t)address + sizeof(buffer) < (uintptr_t)address) {
        // Wrapped around the address range.
        return false;
    }
    if (!ksmem_copySafely(address, buffer, sizeof(buffer))) {
        return false;
    }
    return ksstring_isNullTerminatedUTF8String(buffer, kMinStringLength, sizeof(buffer));
}

bool kscrmi_isValidPointer(uintptr_t address)
{
    if (address == (uintptr_t)NULL) {
        return false;
    }

#if KSCRASH_HAS_OBJC
    if (ksobjc_isTaggedPointer((const void *)address)) {
        if (!ksobjc_isValidTaggedPointer((const void *)address)) {
            return false;
        }
    }
#endif

    return true;
}

bool kscrmi_isNotableAddress(uintptr_t address)
{
    if (!kscrmi_isValidPointer(address)) {
        return false;
    }

    const void *object = (const void *)address;

#if KSCRASH_HAS_OBJC
    if (kszombie_className(object) != NULL) {
        return true;
    }

    if (ksobjc_objectType(object) != KSObjCTypeUnknown) {
        return true;
    }
#endif

    if (kscrmi_isValidString(object)) {
        return true;
    }

    return false;
}

// ============================================================================
#pragma mark - ObjC Content Writers -
// ============================================================================

/** Write a string to the report. */
static void writeNSStringContents(const KSCrashReportWriter *writer, const char *key, uintptr_t objectAddress,
                                  __unused int *limit)
{
    const void *object = (const void *)objectAddress;
    char buffer[200];
    if (ksobjc_copyStringContents(object, buffer, sizeof(buffer))) {
        writer->addStringElement(writer, key, buffer);
    }
}

/** Write a URL to the report. */
static void writeURLContents(const KSCrashReportWriter *writer, const char *key, uintptr_t objectAddress,
                             __unused int *limit)
{
    const void *object = (const void *)objectAddress;
    char buffer[200];
    if (ksobjc_copyStringContents(object, buffer, sizeof(buffer))) {
        writer->addStringElement(writer, key, buffer);
    }
}

/** Write a date to the report. */
static void writeDateContents(const KSCrashReportWriter *writer, const char *key, uintptr_t objectAddress,
                              __unused int *limit)
{
    const void *object = (const void *)objectAddress;
    writer->addFloatingPointElement(writer, key, ksobjc_dateContents(object));
}

/** Write a number to the report. */
static void writeNumberContents(const KSCrashReportWriter *writer, const char *key, uintptr_t objectAddress,
                                __unused int *limit)
{
    const void *object = (const void *)objectAddress;
    writer->addFloatingPointElement(writer, key, ksobjc_numberAsFloat(object));
}

/** Write an array to the report. This will only print the first child of the array. */
static void writeArrayContents(const KSCrashReportWriter *writer, const char *key, uintptr_t objectAddress, int *limit)
{
    const void *object = (const void *)objectAddress;
    uintptr_t firstObject;
    if (ksobjc_arrayContents(object, &firstObject, 1) == 1) {
        kscrmi_writeMemoryContents(writer, key, firstObject, limit);
    }
}

/** Write out ivar information about an unknown object. */
static void writeUnknownObjectContents(const KSCrashReportWriter *writer, const char *key, uintptr_t objectAddress,
                                       int *limit)
{
    (*limit)--;
    const void *object = (const void *)objectAddress;
    KSObjCIvar ivars[10];
    int8_t s8;
    int16_t s16;
    int sInt;
    int32_t s32;
    int64_t s64;
    uint8_t u8;
    uint16_t u16;
    unsigned int uInt;
    uint32_t u32;
    uint64_t u64;
    float f32;
    double f64;
    bool b;
    void *pointer;

    writer->beginObject(writer, key);
    {
        if (ksobjc_isTaggedPointer(object)) {
            writer->addIntegerElement(writer, "tagged_payload", (int64_t)ksobjc_taggedPointerPayload(object));
        } else {
            const void *class = ksobjc_isaPointer(object);
            int ivarCount = ksobjc_ivarList(class, ivars, sizeof(ivars) / sizeof(*ivars));
            *limit -= ivarCount;
            for (int i = 0; i < ivarCount; i++) {
                KSObjCIvar *ivar = &ivars[i];
                switch (ivar->type[0]) {
                    case 'c':
                        ksobjc_ivarValue(object, ivar->index, &s8);
                        writer->addIntegerElement(writer, ivar->name, s8);
                        break;
                    case 'i':
                        ksobjc_ivarValue(object, ivar->index, &sInt);
                        writer->addIntegerElement(writer, ivar->name, sInt);
                        break;
                    case 's':
                        ksobjc_ivarValue(object, ivar->index, &s16);
                        writer->addIntegerElement(writer, ivar->name, s16);
                        break;
                    case 'l':
                        ksobjc_ivarValue(object, ivar->index, &s32);
                        writer->addIntegerElement(writer, ivar->name, s32);
                        break;
                    case 'q':
                        ksobjc_ivarValue(object, ivar->index, &s64);
                        writer->addIntegerElement(writer, ivar->name, s64);
                        break;
                    case 'C':
                        ksobjc_ivarValue(object, ivar->index, &u8);
                        writer->addUIntegerElement(writer, ivar->name, u8);
                        break;
                    case 'I':
                        ksobjc_ivarValue(object, ivar->index, &uInt);
                        writer->addUIntegerElement(writer, ivar->name, uInt);
                        break;
                    case 'S':
                        ksobjc_ivarValue(object, ivar->index, &u16);
                        writer->addUIntegerElement(writer, ivar->name, u16);
                        break;
                    case 'L':
                        ksobjc_ivarValue(object, ivar->index, &u32);
                        writer->addUIntegerElement(writer, ivar->name, u32);
                        break;
                    case 'Q':
                        ksobjc_ivarValue(object, ivar->index, &u64);
                        writer->addUIntegerElement(writer, ivar->name, u64);
                        break;
                    case 'f':
                        ksobjc_ivarValue(object, ivar->index, &f32);
                        writer->addFloatingPointElement(writer, ivar->name, f32);
                        break;
                    case 'd':
                        ksobjc_ivarValue(object, ivar->index, &f64);
                        writer->addFloatingPointElement(writer, ivar->name, f64);
                        break;
                    case 'B':
                        ksobjc_ivarValue(object, ivar->index, &b);
                        writer->addBooleanElement(writer, ivar->name, b);
                        break;
                    case '*':
                    case '@':
                    case '#':
                    case ':':
                        ksobjc_ivarValue(object, ivar->index, &pointer);
                        kscrmi_writeMemoryContents(writer, ivar->name, (uintptr_t)pointer, limit);
                        break;
                    default:
                        KSLOG_DEBUG("%s: Unknown ivar type [%s]", ivar->name, ivar->type);
                }
            }
        }
    }
    writer->endContainer(writer);
}

static void writeZombieIfPresent(const KSCrashReportWriter *writer, const char *key, uintptr_t address)
{
#if KSCRASH_HAS_OBJC
    const void *object = (const void *)address;
    const char *zombieClassName = kszombie_className(object);
    if (zombieClassName != NULL) {
        writer->addStringElement(writer, key, zombieClassName);
    }
#endif
}

static bool isRestrictedClass(const char *name)
{
    if (g_introspectionRules.restrictedClasses != NULL) {
        for (int i = 0; i < g_introspectionRules.restrictedClassesCount; i++) {
            if (ksstring_safeStrcmp(name, g_introspectionRules.restrictedClasses[i]) == 0) {
                return true;
            }
        }
    }
    return false;
}

static bool writeObjCObject(const KSCrashReportWriter *writer, uintptr_t address, int *limit)
{
#if KSCRASH_HAS_OBJC
    const void *object = (const void *)address;
    switch (ksobjc_objectType(object)) {
        case KSObjCTypeClass:
            writer->addStringElement(writer, KSCrashField_Type, KSCrashMemType_Class);
            writer->addStringElement(writer, KSCrashField_Class, ksobjc_className(object));
            return true;
        case KSObjCTypeObject: {
            writer->addStringElement(writer, KSCrashField_Type, KSCrashMemType_Object);
            const char *className = ksobjc_objectClassName(object);
            writer->addStringElement(writer, KSCrashField_Class, className);
            if (!isRestrictedClass(className)) {
                switch (ksobjc_objectClassType(object)) {
                    case KSObjCClassTypeString:
                        writeNSStringContents(writer, KSCrashField_Value, address, limit);
                        return true;
                    case KSObjCClassTypeURL:
                        writeURLContents(writer, KSCrashField_Value, address, limit);
                        return true;
                    case KSObjCClassTypeDate:
                        writeDateContents(writer, KSCrashField_Value, address, limit);
                        return true;
                    case KSObjCClassTypeArray:
                        if (*limit > 0) {
                            writeArrayContents(writer, KSCrashField_FirstObject, address, limit);
                        }
                        return true;
                    case KSObjCClassTypeNumber:
                        writeNumberContents(writer, KSCrashField_Value, address, limit);
                        return true;
                    case KSObjCClassTypeDictionary:
                    case KSObjCClassTypeException:
                        // TODO: Implement these.
                        if (*limit > 0) {
                            writeUnknownObjectContents(writer, KSCrashField_Ivars, address, limit);
                        }
                        return true;
                    case KSObjCClassTypeUnknown:
                        if (*limit > 0) {
                            writeUnknownObjectContents(writer, KSCrashField_Ivars, address, limit);
                        }
                        return true;
                    default:
                        break;
                }
            }
            break;
        }
        case KSObjCTypeBlock:
            writer->addStringElement(writer, KSCrashField_Type, KSCrashMemType_Block);
            const char *className = ksobjc_objectClassName(object);
            writer->addStringElement(writer, KSCrashField_Class, className);
            return true;
        case KSObjCTypeUnknown:
            break;
        default:
            return false;
    }
#endif

    return false;
}

// ============================================================================
#pragma mark - Public API -
// ============================================================================

void kscrmi_writeMemoryContents(const KSCrashReportWriter *writer, const char *key, uintptr_t address, int *limit)
{
    (*limit)--;
    const void *object = (const void *)address;
    writer->beginObject(writer, key);
    {
        writer->addUIntegerElement(writer, KSCrashField_Address, address);
        writeZombieIfPresent(writer, KSCrashField_LastDeallocObject, address);
        if (!writeObjCObject(writer, address, limit)) {
            if (object == NULL) {
                writer->addStringElement(writer, KSCrashField_Type, KSCrashMemType_NullPointer);
            } else if (kscrmi_isValidString(object)) {
                writer->addStringElement(writer, KSCrashField_Type, KSCrashMemType_String);
                writer->addStringElement(writer, KSCrashField_Value, (const char *)object);
            } else {
                writer->addStringElement(writer, KSCrashField_Type, KSCrashMemType_Unknown);
            }
        }
    }
    writer->endContainer(writer);
}

void kscrmi_writeMemoryContentsIfNotable(const KSCrashReportWriter *writer, const char *key, uintptr_t address)
{
    if (kscrmi_isNotableAddress(address)) {
        int limit = kDefaultMemorySearchDepth;
        kscrmi_writeMemoryContents(writer, key, address, &limit);
    }
}

void kscrmi_writeAddressReferencedByString(const KSCrashReportWriter *writer, const char *key, const char *string)
{
    uint64_t address = 0;
    if (string == NULL || !ksstring_extractHexValue(string, (int)strlen(string), &address)) {
        return;
    }

    int limit = kDefaultMemorySearchDepth;
    kscrmi_writeMemoryContents(writer, key, (uintptr_t)address, &limit);
}
