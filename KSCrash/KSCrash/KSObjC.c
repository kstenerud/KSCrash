//
//  KSObjC.c
//
//  Created by Karl Stenerud on 2012-08-30.
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


#include "KSObjC.h"
#include "KSObjCApple.h"

#include "KSMach.h"
#include "KSString.h"


#define kMaxNameLength 128

//======================================================================
#pragma mark - Macros -
//======================================================================

// Compiler hints for "if" statements
#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))


//======================================================================
#pragma mark - Types -
//======================================================================

typedef enum
{
    ClassSubtypeNone = 0,
    ClassSubtypeCFArray,
    ClassSubtypeNSArrayMutable,
    ClassSubtypeNSArrayImmutable,
    ClassSubtypeCFString,
} ClassSubtype;

typedef struct
{
    const char* name;
    KSObjCClassType type;
    ClassSubtype subtype;
    bool isMutable;
    bool (*isValidObject)(const void* object);
    size_t (*description)(const void* object,
                          char* buffer,
                          size_t bufferLength);
    const void* class;
} ClassData;


//======================================================================
#pragma mark - Globals -
//======================================================================

// Forward references
static bool objectIsValid(const void* object);
static bool stringIsValid(const void* object);
static bool urlIsValid(const void* object);
static bool arrayIsValid(const void* object);
static bool dateIsValid(const void* object);

static size_t objectDescription(const void* object, char* buffer, size_t bufferLength);
static size_t stringDescription(const void* object, char* buffer, size_t bufferLength);
static size_t urlDescription(const void* object, char* buffer, size_t bufferLength);
static size_t arrayDescription(const void* object, char* buffer, size_t bufferLength);
static size_t dateDescription(const void* object, char* buffer, size_t bufferLength);


static ClassData g_classData[] =
{
    {"__NSCFString",         KSObjCClassTypeString,  ClassSubtypeNone,             true,  stringIsValid, stringDescription},
    {"NSCFString",           KSObjCClassTypeString,  ClassSubtypeNone,             true,  stringIsValid, stringDescription},
    {"__NSCFConstantString", KSObjCClassTypeString,  ClassSubtypeNone,             true,  stringIsValid, stringDescription},
    {"NSCFConstantString",   KSObjCClassTypeString,  ClassSubtypeNone,             true,  stringIsValid, stringDescription},
    {"__NSArrayI",           KSObjCClassTypeArray,   ClassSubtypeNSArrayImmutable, false, arrayIsValid,  arrayDescription},
    {"__NSArrayM",           KSObjCClassTypeArray,   ClassSubtypeNSArrayMutable,   true,  arrayIsValid,  arrayDescription},
    {"__NSCFArray",          KSObjCClassTypeArray,   ClassSubtypeCFArray,          false, arrayIsValid,  arrayDescription},
    {"NSCFArray",            KSObjCClassTypeArray,   ClassSubtypeCFArray,          false, arrayIsValid,  arrayDescription},
    {"__NSDate",             KSObjCClassTypeDate,    ClassSubtypeNone,             false, dateIsValid,   dateDescription},
    {"NSDate",               KSObjCClassTypeDate,    ClassSubtypeNone,             false, dateIsValid,   dateDescription},
    {"NSURL",                KSObjCClassTypeURL,     ClassSubtypeNone,             false, urlIsValid,    urlDescription},
    {NULL,                   KSObjCClassTypeUnknown, ClassSubtypeNone,             false, objectIsValid, objectDescription},
};

static const char* g_blockBaseClassName = "NSBlock";


//======================================================================
#pragma mark - Utility -
//======================================================================

/** Get any special class metadata we have about the specified class.
 * It will return a generic metadata object if the type is not recognized.
 *
 * Note: The Objective-C runtime is free to change a class address,
 * so I can't just blindly store class pointers at application start
 * and then compare against them later. However, comparing strings is
 * slow, so I've reached a compromise. Since I'm omly using this at
 * crash time, I can assume that the Objective-C environment is frozen.
 * As such, I can keep a cache of discovered classes. If, however, this
 * library is used outside of a frozen environment, caching will be
 * unreliable.
 *
 * @param class The class to examine.
 *
 * @return The associated class data.
 */
static ClassData* getClassData(const void* class)
{
    const char* className = ksobjc_className(class);
    for(ClassData* data = g_classData;; data++)
    {
        unlikely_if(data->name == NULL)
        {
            return data;
        }
        unlikely_if(class == data->class)
        {
            return data;
        }
        unlikely_if(data->class == NULL && strcmp(className, data->name) == 0)
        {
            data->class = class;
            return data;
        }
    }
}

static inline ClassData* getClassDataFromObject(const void* object)
{
    const struct class_t* obj = object;
    return getClassData(obj->isa);
}

static inline struct class_rw_t* classRW(const struct class_t* const class)
{
    uintptr_t ptr = class->data_NEVER_USE & (~WORD_MASK);
    return (struct class_rw_t*)ptr;
}

static inline const struct class_ro_t* classRO(const struct class_t* const class)
{
    return classRW(class)->ro;
}

static size_t stringPrintf(char* buffer,
                           size_t bufferLength,
                           const char* fmt,
                           ...)
{
    unlikely_if(bufferLength == 0)
    {
        return 0;
    }
    
    va_list args;
    va_start(args,fmt);
    int printLength = vsnprintf(buffer, bufferLength, fmt, args);
    va_end(args);
    
    unlikely_if(printLength < 0)
    {
        *buffer = 0;
        return 0;
    }
    unlikely_if((size_t)printLength > bufferLength)
    {
        return bufferLength-1;
    }
    return (size_t)printLength;
}


//======================================================================
#pragma mark - Validation -
//======================================================================

// Lookup table for validating class/ivar names and objc @encode types.
#define INV 0
#define N_C 5
#define N_S 7
#define T_C 4

static const unsigned int g_nameChars[] =
{
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, T_C, T_C, T_C, T_C, T_C, T_C, T_C, T_C, T_C, T_C, T_C, T_C, T_C, T_C, T_C,
    N_C, N_C, N_C, N_C, N_C, N_C, N_C, N_C, N_C, N_C, T_C, T_C, T_C, T_C, T_C, T_C,
    T_C, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S,
    N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, T_C, T_C, T_C, T_C, N_S,
    T_C, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S,
    N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, N_S, T_C, T_C, T_C, T_C, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
};

#define VALID_NAME_CHAR(A) ((g_nameChars[(uint8_t)(A)] & 1) != 0)
#define VALID_NAME_START_CHAR(A) ((g_nameChars[(uint8_t)(A)] & 2) != 0)
#define VALID_TYPE_CHAR(A) ((g_nameChars[(uint8_t)(A)] & 7) != 0)

static bool isValidName(const char* const name, const size_t maxLength)
{
    if((uintptr_t)name + maxLength < (uintptr_t)name)
    {
        // Wrapped around address space.
        return false;
    }

    char buffer[maxLength];
    size_t length = ksmach_copyMaxPossibleMem(name, buffer, maxLength);
    if(length == 0 || !VALID_NAME_START_CHAR(name[0]))
    {
        return false;
    }
    for(size_t i = 1; i < length; i++)
    {
        unlikely_if(!VALID_NAME_CHAR(name[i]))
        {
            if(name[i] == 0)
            {
                return true;
            }
            return false;
        }
    }
    return false;
}

static bool isValidIvarType(const char* const type)
{
    char buffer[100];
    const size_t maxLength = sizeof(buffer);

    if((uintptr_t)type + maxLength < (uintptr_t)type)
    {
        // Wrapped around address space.
        return false;
    }

    size_t length = ksmach_copyMaxPossibleMem(type, buffer, maxLength);
    if(length == 0 || !VALID_TYPE_CHAR(type[0]))
    {
        return false;
    }
    for(size_t i = 0; i < length; i++)
    {
        unlikely_if(!VALID_TYPE_CHAR(type[i]))
        {
            if(type[i] == 0)
            {
                return true;
            }
        }
    }
    return false;
}

static bool containsValidROData(const void* const classPtr)
{
    struct class_t class;
    struct class_rw_t rw;
    struct class_ro_t ro;
    if(ksmach_copyMem(classPtr, &class, sizeof(class)) != KERN_SUCCESS)
    {
        return false;
    }
    if(ksmach_copyMem(classRW(&class), &rw, sizeof(rw)) != KERN_SUCCESS)
    {
        return false;
    }
    if(ksmach_copyMem(rw.ro, &ro, sizeof(ro)) != KERN_SUCCESS)
    {
        return false;
    }
    return true;
}

static bool containsValidIvarData(const void* const classPtr)
{
    const struct class_ro_t* ro = classRO(classPtr);
    const struct ivar_list_t* ivars = ro->ivars;
    if(ivars == NULL)
    {
        return true;
    }
    
    struct ivar_list_t ivarsBuffer;
    if(ksmach_copyMem(ivars, &ivarsBuffer, sizeof(ivarsBuffer)) != KERN_SUCCESS)
    {
        return false;
    }

    if(ivars->count > 0)
    {
        struct ivar_t ivar;
        uint8_t* ivarPtr = (uint8_t*)(&ivars->first) + ivars->entsize;
        for(uint32_t i = 1; i < ivarsBuffer.count; i++)
        {
            if(ksmach_copyMem(ivarPtr, &ivar, sizeof(ivar)) != KERN_SUCCESS)
            {
                return false;
            }
            uintptr_t offset;
            if(ksmach_copyMem(ivar.offset, &offset, sizeof(offset)) != KERN_SUCCESS)
            {
                return false;
            }
            if(!isValidName(ivar.name, kMaxNameLength))
            {
                return false;
            }
            if(!isValidIvarType(ivar.type))
            {
                return false;
            }
            ivarPtr += ivars->entsize;
        }
    }
    return true;
}

static bool containsValidClassName(const void* const classPtr)
{
    const struct class_ro_t* ro = classRO(classPtr);
    return isValidName(ro->name, kMaxNameLength);
}


//======================================================================
#pragma mark - Basic Objective-C Queries -
//======================================================================

const void* ksobjc_isaPointer(const void* const objectOrClassPtr)
{
    const struct class_t* ptr = objectOrClassPtr;
    return ptr->isa;
}

const void* ksobjc_superClass(const void* const classPtr)
{
    const struct class_t* class = classPtr;
    return class->superclass;
}

bool ksobjc_isMetaClass(const void* const classPtr)
{
    return (classRO(classPtr)->flags & RO_META) != 0;
}

bool ksobjc_isRootClass(const void* const classPtr)
{
    return (classRO(classPtr)->flags & RO_ROOT) != 0;
}

const char* ksobjc_className(const void* classPtr)
{
    const struct class_ro_t* ro = classRO(classPtr);
    return ro->name;
}

bool ksobjc_isClassNamed(const void* const classPtr, const char* const className)
{
    const char* name = ksobjc_className(classPtr);
    if(name == NULL || className == NULL)
    {
        return false;
    }
    return strcmp(name, className) == 0;
}

bool ksobjc_isKindOfClass(const void* const classPtr, const char* const className)
{
    if(className == NULL)
    {
        return false;
    }
    
    const struct class_t* class = (const struct class_t*)classPtr;
    
    for(;;)
    {
        const char* name = ksobjc_className(class);
        if(name == NULL)
        {
            return false;
        }
        if(strcmp(className, name) == 0)
        {
            return true;
        }
        class = class->superclass;
        if(!containsValidROData(class))
        {
            return false;
        }
    }
}

const void* ksobjc_baseClass(const void* const classPtr)
{
    const struct class_t* superClass = classPtr;
    const struct class_t* subClass = classPtr;
    
    for(;;)
    {
        if(ksobjc_isRootClass(superClass))
        {
            return subClass;
        }
        subClass = superClass;
        superClass = superClass->superclass;
        if(!containsValidROData(superClass))
        {
            return NULL;
        }
    }
}

size_t ksobjc_ivarCount(const void* const classPtr)
{
    const struct ivar_list_t* ivars = classRO(classPtr)->ivars;
    if(ivars == NULL)
    {
        return 0;
    }
    return ivars->count;
}

size_t ksobjc_ivarList(const void* const classPtr, KSObjCIvar* dstIvars, size_t ivarsCount)
{
    if(dstIvars == NULL)
    {
        return 0;
    }
    
    size_t count = ksobjc_ivarCount(classPtr);
    if(count == 0)
    {
        return 0;
    }

    if(ivarsCount < count)
    {
        count = ivarsCount;
    }
    const struct ivar_list_t* srcIvars = classRO(classPtr)->ivars;
    uintptr_t srcPtr = (uintptr_t)&srcIvars->first;
    const struct ivar_t* src = (void*)srcPtr;
    for(size_t i = 0; i < count; i++)
    {
        KSObjCIvar* dst = &dstIvars[i];
        dst->name = src->name;
        dst->type = src->type;
        dst->index = i;
        srcPtr += srcIvars->entsize;
        src = (void*)srcPtr;
    }
    return count;
}

bool ksobjc_ivarNamed(const void* const classPtr, const char* name, KSObjCIvar* dst)
{
    if(name == NULL)
    {
        return false;
    }
    const struct ivar_list_t* ivars = classRO(classPtr)->ivars;
    uintptr_t ivarPtr = (uintptr_t)&ivars->first;
    const struct ivar_t* ivar = (void*)ivarPtr;
    for(size_t i = 0; i < ivars->count; i++)
    {
        if(ivar->name != NULL && strcmp(name, ivar->name) == 0)
        {
            dst->name = ivar->name;
            dst->type = ivar->type;
            dst->index = i;
            return true;
        }
        ivarPtr += ivars->entsize;
        ivar = (void*)ivarPtr;
    }
    return false;
}

bool ksobjc_ivarValue(const void* const objectPtr, size_t ivarIndex, void* dst)
{
    const void* const classPtr = ksobjc_isaPointer(objectPtr);
    const struct ivar_list_t* ivars = classRO(classPtr)->ivars;
    if(ivarIndex >= ivars->count)
    {
        return false;
    }
    uintptr_t ivarPtr = (uintptr_t)&ivars->first;
    const struct ivar_t* ivar = (void*)(ivarPtr + ivars->entsize * ivarIndex);
    
    uintptr_t valuePtr = (uintptr_t)objectPtr + *ivar->offset;
    if(ksmach_copyMem((void*)valuePtr, dst, ivar->size) != KERN_SUCCESS)
    {
        return false;
    }
    return true;
}

static inline bool isBlockClass(const void* class)
{
    const void* baseClass = ksobjc_baseClass(class);
    if(baseClass == NULL)
    {
        return false;
    }
    const char* name = ksobjc_className(baseClass);
    if(name == NULL)
    {
        return false;
    }
    return strcmp(name, g_blockBaseClassName) == 0;
}

KSObjCType ksobjc_objectType(const void* objectOrClassPtr)
{
    if(objectOrClassPtr == NULL)
    {
        return KSObjCTypeUnknown;
    }
    
    const struct class_t* isa;
    if(ksmach_copyMem(objectOrClassPtr, &isa, sizeof(isa)) != KERN_SUCCESS)
    {
        return KSObjCTypeUnknown;
    }
    if(!containsValidROData(isa))
    {
        return KSObjCTypeUnknown;
    }
    if(!containsValidClassName(isa))
    {
        return KSObjCTypeUnknown;
    }
    
    if(isBlockClass(isa))
    {
        return KSObjCTypeBlock;
    }
    if(!ksobjc_isMetaClass(isa))
    {
        return KSObjCTypeObject;
    }
    
    isa = (struct class_t*)objectOrClassPtr;
    if(!containsValidROData(isa))
    {
        return KSObjCTypeUnknown;
    }
    
    if(!containsValidIvarData(isa))
    {
        return KSObjCTypeUnknown;
    }
    if(!containsValidClassName(isa))
    {
        return KSObjCTypeUnknown;
    }
    
    return KSObjCTypeClass;
}


//======================================================================
#pragma mark - Unknown Object -
//======================================================================

static bool objectIsValid(__unused const void* object)
{
    // If it passed ksobjc_objectType, it's been validated as much as
    // possible.
    return true;
}

static size_t objectDescription(const void* object,
                             char* buffer,
                             size_t bufferLength)
{
    const void* class = ksobjc_isaPointer(object);
    const char* name = ksobjc_className(class);
    uintptr_t objPointer = (uintptr_t)object;
    const char* fmt = sizeof(uintptr_t) == sizeof(uint32_t) ? "<%s: 0x%08x>" : "<%s: 0x%016x>";
    return stringPrintf(buffer, bufferLength, fmt, name, objPointer);
}


//======================================================================
#pragma mark - NSString -
//======================================================================

static inline const char* stringStart(const struct CFString* str)
{
    return (const char*)CF_StrContents(str) + (CF_StrHasLengthByte(str) ? 1 : 0);
}

static bool stringIsValid(const void* const stringPtr)
{
    const struct CFString* string = stringPtr;
    struct CFString temp;
    uint8_t oneByte;
    CFIndex length = -1;
    if(ksmach_copyMem(string, &temp, sizeof(string->base)) != KERN_SUCCESS)
    {
        return false;
    }
    
    if(CF_StrIsInline(string))
    {
        if(ksmach_copyMem(&string->variants.inline1, &temp, sizeof(string->variants.inline1)) != KERN_SUCCESS)
        {
            return false;
        }
        length = string->variants.inline1.length;
    }
    else if(CF_StrIsMutable(string))
    {
        if(ksmach_copyMem(&string->variants.notInlineMutable, &temp, sizeof(string->variants.notInlineMutable)) != KERN_SUCCESS)
        {
            return false;
        }
        length = string->variants.notInlineMutable.length;
    }
    else if(!CF_StrHasLengthByte(string))
    {
        if(ksmach_copyMem(&string->variants.notInlineImmutable1, &temp, sizeof(string->variants.notInlineImmutable1)) != KERN_SUCCESS)
        {
            return false;
        }
        length = string->variants.notInlineImmutable1.length;
    }
    else
    {
        if(ksmach_copyMem(&string->variants.notInlineImmutable2, &temp, sizeof(string->variants.notInlineImmutable2)) != KERN_SUCCESS)
        {
            return false;
        }
        if(ksmach_copyMem(CF_StrContents(string), &oneByte, sizeof(oneByte)) != KERN_SUCCESS)
        {
            return false;
        }
        length = oneByte;
    }
    
    if(length < 0)
    {
        return false;
    }
    else if(length > 0)
    {
        if(ksmach_copyMem(stringStart(string), &oneByte, sizeof(oneByte)) != KERN_SUCCESS)
        {
            return false;
        }
    }
    return true;
}

size_t ksobjc_stringLength(const void* const stringPtr)
{
    const struct CFString* string = stringPtr;
    if(CF_StrIsInline(string))
    {
        if(CF_StrHasLengthByte(string))
        {
            return string->variants.inline2.length;
        }
        return (size_t)string->variants.inline1.length;
    }
    else if(CF_StrIsMutable(string))
    {
        return (size_t)string->variants.notInlineMutable.length;
    }
    else if(!CF_StrHasLengthByte(string))
    {
        return (size_t)string->variants.notInlineImmutable1.length;
    }
    else
    {
        return (uint8_t)*((uint8_t*)CF_StrContents(string));
    }
}

#define kUTF16_LeadSurrogateStart       0xd800u
#define kUTF16_LeadSurrogateEnd         0xdbffu
#define kUTF16_TailSurrogateStart       0xdc00u
#define kUTF16_TailSurrogateEnd         0xdfffu
#define kUTF16_FirstSupplementaryPlane  0x10000u

size_t ksobjc_i_copyAndConvertUTF16StringToUTF8(const void* const src,
                                                void* const dst,
                                                size_t charCount,
                                                size_t maxByteCount)
{
    const uint16_t* pSrc = src;
    uint8_t* pDst = dst;
    const uint8_t* const pDstEnd = pDst + maxByteCount - 1; // Leave room for null termination.
    for(size_t charsRemaining = charCount; charsRemaining > 0 && pDst < pDstEnd; charsRemaining--)
    {
        // Decode UTF-16
        uint32_t character = 0;
        uint16_t leadSurrogate = *pSrc++;
        likely_if(leadSurrogate < kUTF16_LeadSurrogateStart || leadSurrogate > kUTF16_TailSurrogateEnd)
        {
            character = leadSurrogate;
        }
        else if(leadSurrogate > kUTF16_LeadSurrogateEnd)
        {
            // Inverted surrogate
            *((uint8_t*)dst) = 0;
            return 0;
        }
        else
        {
            uint16_t tailSurrogate = *pSrc++;
            if(tailSurrogate < kUTF16_TailSurrogateStart || tailSurrogate > kUTF16_TailSurrogateEnd)
            {
                // Invalid tail surrogate
                *((uint8_t*)dst) = 0;
                return 0;
            }
            character = ((leadSurrogate - kUTF16_LeadSurrogateStart) << 10) + (tailSurrogate - kUTF16_TailSurrogateStart);
            character += kUTF16_FirstSupplementaryPlane;
            charsRemaining--;
        }
        
        // Encode UTF-8
        likely_if(character <= 0x7f)
        {
            *pDst++ = (uint8_t)character;
        }
        else if(character <= 0x7ff)
        {
            if(pDstEnd - pDst >= 2)
            {
                *pDst++ = (uint8_t)(0xc0 | (character >> 6));
                *pDst++ = (uint8_t)(0x80 | (character & 0x3f));
            }
            else
            {
                break;
            }
        }
        else if(character <= 0xffff)
        {
            if(pDstEnd - pDst >= 3)
            {
                *pDst++ = (uint8_t)(0xe0 | (character >> 12));
                *pDst++ = (uint8_t)(0x80 | ((character >> 6) & 0x3f));
                *pDst++ = (uint8_t)(0x80 | (character & 0x3f));
            }
            else
            {
                break;
            }
        }
        // RFC3629 restricts UTF-8 to end at 0x10ffff.
        else if(character <= 0x10ffff)
        {
            if(pDstEnd - pDst >= 4)
            {
                *pDst++ = (uint8_t)(0xf0 | (character >> 18));
                *pDst++ = (uint8_t)(0x80 | ((character >> 12) & 0x3f));
                *pDst++ = (uint8_t)(0x80 | ((character >> 6) & 0x3f));
                *pDst++ = (uint8_t)(0x80 | (character & 0x3f));
            }
            else
            {
                break;
            }
        }
        else
        {
            // Invalid unicode.
            *((uint8_t*)dst) = 0;
            return 0;
        }
    }
    
    // Null terminate and return.
    *pDst = 0;
    return (size_t)(pDst - (uint8_t*)dst);
}

size_t ksobjc_i_copy8BitString(const void* const src, void* const dst, size_t charCount, size_t maxByteCount)
{
    unlikely_if(maxByteCount == 0)
    {
        return 0;
    }
    unlikely_if(charCount == 0)
    {
        *((uint8_t*)dst) = 0;
        return 0;
    }

    unlikely_if(charCount >= maxByteCount)
    {
        charCount = maxByteCount - 1;
    }
    unlikely_if(ksmach_copyMem(src, dst, charCount) != KERN_SUCCESS)
    {
        *((uint8_t*)dst) = 0;
        return 0;
    }
    uint8_t* charDst = dst;
    charDst[charCount] = 0;
    return charCount;
}

size_t ksobjc_copyStringContents(const void* stringPtr, char* dst, size_t maxByteCount)
{
    const struct CFString* string = stringPtr;
    size_t charCount = ksobjc_stringLength(string);
    
    const char* src = stringStart(string);
    if(CF_StrIsUnicode(string))
    {
        return ksobjc_i_copyAndConvertUTF16StringToUTF8(src, dst, charCount, maxByteCount);
    }
    
    return ksobjc_i_copy8BitString(src, dst, charCount, maxByteCount);
}

static size_t stringDescription(const void* object, char* buffer, size_t bufferLength)
{
    char* pBuffer = buffer;
    char* pEnd = buffer + bufferLength;
    
    pBuffer += objectDescription(object, pBuffer, (size_t)(pEnd - pBuffer));
    pBuffer += stringPrintf(pBuffer, (size_t)(pEnd - pBuffer), ": \"");
    pBuffer += ksobjc_copyStringContents(object, pBuffer, (size_t)(pEnd - pBuffer));
    pBuffer += stringPrintf(pBuffer, (size_t)(pEnd - pBuffer), "\"");

    return (size_t)(pBuffer - buffer);
}


//======================================================================
#pragma mark - NSURL -
//======================================================================

static bool urlIsValid(const void* const urlPtr)
{
    struct CFURL url;
    if(ksmach_copyMem(urlPtr, &url, sizeof(url)) != KERN_SUCCESS)
    {
        return false;
    }
    return stringIsValid(url._string);
}

size_t ksobjc_copyURLContents(const void* const urlPtr, char* dst, size_t maxLength)
{
    const struct CFURL* url = urlPtr;
    return ksobjc_copyStringContents(url->_string, dst, maxLength);
}

static size_t urlDescription(const void* object, char* buffer, size_t bufferLength)
{
    char* pBuffer = buffer;
    char* pEnd = buffer + bufferLength;
    
    pBuffer += objectDescription(object, pBuffer, (size_t)(pEnd - pBuffer));
    pBuffer += stringPrintf(pBuffer, (size_t)(pEnd - pBuffer), ": \"");
    pBuffer += ksobjc_copyURLContents(object, pBuffer, (size_t)(pEnd - pBuffer));
    pBuffer += stringPrintf(pBuffer, (size_t)(pEnd - pBuffer), "\"");
    
    return (size_t)(pBuffer - buffer);
}


//======================================================================
#pragma mark - NSDate -
//======================================================================

static bool dateIsValid(const void* const datePtr)
{
    struct CFDate temp;
    return ksmach_copyMem(datePtr, &temp, sizeof(temp)) == KERN_SUCCESS;
}

CFAbsoluteTime ksobjc_dateContents(const void* const datePtr)
{
    const struct CFDate* date = datePtr;
    return date->_time;
}

static size_t dateDescription(const void* object, char* buffer, size_t bufferLength)
{
    char* pBuffer = buffer;
    char* pEnd = buffer + bufferLength;
    
    CFAbsoluteTime time = ksobjc_dateContents(object);
    pBuffer += objectDescription(object, pBuffer, (size_t)(pEnd - pBuffer));
    pBuffer += stringPrintf(pBuffer, (size_t)(pEnd - pBuffer), ": %f", time);
    
    return (size_t)(pBuffer - buffer);
}


//======================================================================
#pragma mark - NSArray -
//======================================================================

struct NSArray
{
    struct
    {
        void* isa;
        CFIndex count;
    } basic;
    
    struct
    {
        unsigned long flags; // Seems to always be 0x21 or 0x11
        unsigned long dequeStartOffset; // Need to shift right by 2 since lower bits always set?
        unsigned long mutations;
        void* deque;
    } mutable;
};

static inline bool nsarrayIsMutable(const void* const arrayPtr)
{
    return getClassDataFromObject(arrayPtr)->isMutable;
}

static inline bool nsarrayIsValid(const void* const arrayPtr)
{
    struct NSArray temp;
    if(ksmach_copyMem(arrayPtr, &temp, sizeof(temp.basic)) != KERN_SUCCESS)
    {
        return false;
    }
    if(nsarrayIsMutable(arrayPtr))
    {
        if(ksmach_copyMem(arrayPtr, &temp, sizeof(temp.mutable)) != KERN_SUCCESS)
        {
            return false;
        }
    }
    return true;
}

static inline const void* nsarrayData(const void* const arrayPtr)
{
    const struct NSArray* array = arrayPtr;
    uintptr_t entriesPtr;
    if(nsarrayIsMutable(arrayPtr))
    {
        entriesPtr = ((uintptr_t)array->mutable.deque) + array->mutable.dequeStartOffset;
    }
    else
    {
        entriesPtr = ((uintptr_t)array) + sizeof(array->basic);
    }
    entriesPtr &= ~WORD_MASK;
    return (void*)entriesPtr;
}

static inline size_t nsarrayCount(const void* const arrayPtr)
{
    const struct NSArray* array = arrayPtr;
    return array->basic.count < 0 ? 0 : (size_t)array->basic.count;
}

static size_t nsarrayContents(const void* const arrayPtr, uintptr_t* contents, size_t count)
{
    const struct NSArray* array = arrayPtr;
    
    if(array->basic.count < (CFIndex)count)
    {
        if(array->basic.count <= 0)
        {
            return 0;
        }
        count = (size_t)array->basic.count;
    }
    
    const void* firstEntry = nsarrayData(array);
    if(ksmach_copyMem(firstEntry, contents, sizeof(*contents) * count) != KERN_SUCCESS)
    {
        return 0;
    }
    return count;
}


static inline bool cfarrayIsValid(const void* const arrayPtr)
{
    struct CFArray temp;
    if(ksmach_copyMem(arrayPtr, &temp, sizeof(temp)) != KERN_SUCCESS)
    {
        return false;
    }
    const struct CFArray* array = arrayPtr;
    if(CF_ArrayGetType(array) == kCFArrayDeque)
    {
        if(array->_store != NULL)
        {
            struct CFArrayDeque deque;
            if(ksmach_copyMem(array->_store, &deque, sizeof(deque)) != KERN_SUCCESS)
            {
                return false;
            }
        }
    }
    return true;
}

static inline const void* cfarrayData(const void* const arrayPtr)
{
    return CF_ArrayGetBucketsPtr(arrayPtr);
}

static inline size_t cfarrayCount(const void* const arrayPtr)
{
    const struct CFArray* array = arrayPtr;
    return array->_count < 0 ? 0 : (size_t)array->_count;
}

static size_t cfarrayContents(const void* const arrayPtr, uintptr_t* contents, size_t count)
{
    const struct CFArray* array = arrayPtr;
    if(array->_count < (CFIndex)count)
    {
        if(array->_count <= 0)
        {
            return 0;
        }
        count = (size_t)array->_count;
    }
    
    const void* firstEntry = cfarrayData(array);
    if(ksmach_copyMem(firstEntry, contents, sizeof(*contents) * count) != KERN_SUCCESS)
    {
        return 0;
    }
    return count;
}

static bool isCFArray(const void* const arrayPtr)
{
    ClassData* data = getClassDataFromObject(arrayPtr);
    return data->subtype == ClassSubtypeCFArray;
}



size_t ksobjc_arrayCount(const void* const arrayPtr)
{
    if(isCFArray(arrayPtr))
    {
        return cfarrayCount(arrayPtr);
    }
    return nsarrayCount(arrayPtr);
}

size_t ksobjc_arrayContents(const void* const arrayPtr, uintptr_t* contents, size_t count)
{
    if(isCFArray(arrayPtr))
    {
        return cfarrayContents(arrayPtr, contents, count);
    }
    return nsarrayContents(arrayPtr, contents, count);
}

bool arrayIsValid(const void* object)
{
    if(isCFArray(object))
    {
        return cfarrayIsValid(object);
    }
    return nsarrayIsValid(object);
}

static size_t arrayDescription(const void* object, char* buffer, size_t bufferLength)
{
    char* pBuffer = buffer;
    char* pEnd = buffer + bufferLength;
    
    pBuffer += objectDescription(object, pBuffer, (size_t)(pEnd - pBuffer));
    pBuffer += stringPrintf(pBuffer, (size_t)(pEnd - pBuffer), ": [");

    if(pBuffer < pEnd-1 && ksobjc_arrayCount(object) > 0)
    {
        uintptr_t contents = 0;
        if(ksobjc_arrayContents(object, &contents, 1) == 1)
        {
            pBuffer += ksobjc_getDescription((void*)contents, pBuffer, (size_t)(pEnd - pBuffer));
        }
    }
    pBuffer += stringPrintf(pBuffer, (size_t)(pEnd - pBuffer), "]");
    
    return (size_t)(pBuffer - buffer);
}


//======================================================================
#pragma mark - NSDictionary (BROKEN) -
//======================================================================

bool ksobjc_dictionaryFirstEntry(const void* dict, uintptr_t* key, uintptr_t* value)
{
    // TODO: This is broken.

    // Ensure memory is valid.
    struct CFBasicHash copy;
    kern_return_t kr = KERN_SUCCESS;
    if((kr = ksmach_copyMem(dict, &copy, sizeof(copy))) != KERN_SUCCESS)
    {
        return false;
    }
    
    struct CFBasicHash* ht = (struct CFBasicHash*)dict;
    uintptr_t* keys = (uintptr_t*)ht->pointers + ht->bits.keys_offset;
    uintptr_t* values = (uintptr_t*)ht->pointers;
    
    // Dereference key and value pointers.
    if((kr = ksmach_copyMem(keys, &keys, sizeof(keys))) != KERN_SUCCESS)
    {
        return false;
    }
    
    if((kr = ksmach_copyMem(values, &values, sizeof(values))) != KERN_SUCCESS)
    {
        return false;
    }
    
    // Copy to destination.
    if((kr = ksmach_copyMem(keys, key, sizeof(*key))) != KERN_SUCCESS)
    {
        return false;
    }
    if((kr = ksmach_copyMem(values, value, sizeof(*value))) != KERN_SUCCESS)
    {
        return false;
    }
    return true;
}

//kern_return_t ksobjc_dictionaryContents(const void* dict, uintptr_t* keys, uintptr_t* values, CFIndex* count)
//{
//    struct CFBasicHash copy;
//    void* pointers[100];
//
//    kern_return_t kr = KERN_SUCCESS;
//    if((kr = ksmach_copyMem(dict, &copy, sizeof(copy))) != KERN_SUCCESS)
//    {
//        return kr;
//    }
//
//    struct CFBasicHash* ht = (struct CFBasicHash*)dict;
//    size_t values_offset = 0;
//    size_t keys_offset = copy.bits.keys_offset;
//    if((kr = ksmach_copyMem(&ht->pointers, pointers, sizeof(*pointers) * keys_offset)) != KERN_SUCCESS)
//    {
//        return kr;
//    }
//
//
//
//    return kr;
//}

size_t ksobjc_dictionaryCount(const void* dict)
{
    // TODO: Implement me
#pragma unused(dict)
    return 0;
}


//======================================================================
#pragma mark - General Queries -
//======================================================================

size_t ksobjc_getDescription(void* object,
                             char* buffer,
                             size_t bufferLength)
{
    ClassData* data = getClassDataFromObject(object);
    return data->description(object, buffer, bufferLength);
}

void* ksobjc_i_objectReferencedByString(const char* string)
{
    uint64_t address = 0;
    if(ksstring_extractHexValue(string, strlen(string), &address))
    {
        return (void*)address;
    }
    return NULL;
}

bool ksobjc_isValidObject(const void* object)
{
    ClassData* data = getClassDataFromObject(object);
    return data->isValidObject(object);
}

KSObjCClassType ksobjc_objectClassType(const void* object)
{
    ClassData* data = getClassDataFromObject(object);
    return data->type;
}

//__NSArrayReversed
//__NSCFBoolean
//__NSCFDictionary
//__NSCFError
//__NSCFNumber
//__NSCFSet
//__NSCFString
//__NSDate
//__NSDictionaryI
//__NSDictionaryM
//__NSOrderedSetArrayProxy
//__NSOrderedSetI
//__NSOrderedSetM
//__NSOrderedSetReversed
//__NSOrderedSetSetProxy
//__NSPlaceholderArray
//__NSPlaceholderDate
//__NSPlaceholderDictionary
//__NSPlaceholderOrderedSet
//__NSPlaceholderSet
//__NSSetI
//__NSSetM
//NSArray
//NSCFArray
//NSCFBoolean
//NSCFDictionary
//NSCFError
//NSCFNumber
//NSCFSet
//NSCheapMutableString
//NSClassicHashTable
//NSClassicMapTable
//SConcreteHashTable
//NSConcreteMapTable
//NSConcreteValue
//NSDate
//NSDecimalNumber
//NSDecimalNumberPlaceholder
//NSDictionary
//NSError
//NSException
//NSHashTable
//NSMutableArray
//NSMutableDictionary
//NSMutableIndexSet
//NSMutableOrderedSet
//NSMutableRLEArray
//NSMutableSet
//NSMutableString
//NSMutableStringProxy
//NSNumber
//NSOrderedSet
//NSPlaceholderMutableString
//NSPlaceholderNumber
//NSPlaceholderString
//NSRLEArray
//NSSet
//NSSimpleCString
//NSString
//NSURL
