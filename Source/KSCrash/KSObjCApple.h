//
//  KSObjCApple.h
//
//  Created by Karl Stenerud on 2012-08-30.
//
// Copyright (c) 2011 Apple Inc. All rights reserved.
//
// This file contains Original Code and/or Modifications of Original Code
// as defined in and that are subject to the Apple Public Source License
// Version 2.0 (the 'License'). You may not use this file except in
// compliance with the License. Please obtain a copy of the License at
// http://www.opensource.apple.com/apsl/ and read it before using this
// file.
//

// This file contains structures and constants copied from Apple header
// files, arranged for use in KSObjC.

#ifndef HDR_KSObjCApple_h
#define HDR_KSObjCApple_h

#ifdef __cplusplus
extern "C" {
#endif


#include <objc/objc.h>
#include <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>


// ======================================================================
#pragma mark - objc4-493.9/runtime/objc-private.h -
// ======================================================================

#ifdef __LP64__
#   define WORD_SHIFT 3UL
#   define WORD_MASK 7UL
#else
#   define WORD_SHIFT 2UL
#   define WORD_MASK 3UL
#endif

typedef struct objc_cache *Cache;


// ======================================================================
#pragma mark - objc4-493.9/runtime/objc-runtime-new.h -
// ======================================================================

// Values for class_ro_t->flags
// These are emitted by the compiler and are part of the ABI.
// class is a metaclass
#define RO_META               (1<<0)
// class is a root class
#define RO_ROOT               (1<<1)


struct class_t { // P*5
    struct class_t *isa;
    struct class_t *superclass;
    Cache cache;
    IMP *vtable;
    uintptr_t data_NEVER_USE;  // class_rw_t * plus flags
    // Last 2 bits of data are flags.
    // Real type is class_rw_t*
};


struct ivar_t {
    // *offset is 64-bit by accident even though other
    // fields restrict total instance size to 32-bit.
    uintptr_t *offset;
    const char *name;
    const char *type;
    // alignment is sometimes -1; use ivar_alignment() instead
    uint32_t alignment  __attribute__((deprecated));
    uint32_t size;
};

struct ivar_list_t {
    uint32_t entsize;
    uint32_t count;
    struct ivar_t first;
};

struct class_ro_t { // P*7, U32*4
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
#ifdef __LP64__
    uint32_t reserved;
#endif
    
    const uint8_t * ivarLayout;
    
    const char * name;
    const struct method_list_t * baseMethods;
    const struct protocol_list_t * baseProtocols;
    const struct ivar_list_t * ivars;
    
    const uint8_t * weakIvarLayout;
    const struct property_list_t *baseProperties;
};

struct class_rw_t { // P*6, U32*2
    uint32_t flags;
    uint32_t version;
    
    const struct class_ro_t *ro;
    
    struct method_list_t **methods;
    struct chained_property_list *properties;
    const struct protocol_list_t ** protocols;
    
    struct class_t *firstSubclass;
    struct class_t *nextSiblingClass;
};

struct ivar_alignment_t {
    uintptr_t *offset;
    const char *name;
    const char *type;
    uint32_t alignment;
};

//static inline uint32_t ivar_alignment(const struct ivar_t *ivar)
//{
//    uint32_t alignment = ((struct ivar_alignment_t *)ivar)->alignment;
//    if (alignment == (uint32_t)-1) alignment = (uint32_t)WORD_SHIFT;
//    return 1<<alignment;
//}


// ======================================================================
#pragma mark - CF-635/CFRuntime.h -
// ======================================================================

struct CFRuntimeBase {
    uintptr_t _cfisa;
    uint8_t _cfinfo[4];
#if __LP64__
    uint32_t _rc;
#endif
};


// ======================================================================
#pragma mark - CF-635/CFInternal.h -
// ======================================================================

#if defined(__BIG_ENDIAN__)
#define CF_BIG_ENDIAN 1
#define CF_LITTLE_ENDIAN 0
#endif

#if defined(__LITTLE_ENDIAN__)
#define CF_LITTLE_ENDIAN 1
#define CF_BIG_ENDIAN 0
#endif

/* Bit manipulation macros */
/* Bits are numbered from 31 on left to 0 on right */
/* May or may not work if you use them on bitfields in types other than UInt32, bitfields the full width of a UInt32, or anything else for which they were not designed. */
/* In the following, N1 and N2 specify an inclusive range N2..N1 with N1 >= N2 */
#define CF_BitfieldMask(N1, N2)	((((UInt32)~0UL) << (31UL - (N1) + (N2))) >> (31UL - N1))
#define CF_BitfieldGetValue(V, N1, N2)	(((V) & CF_BitfieldMask(N1, N2)) >> (N2))

#define CF_INFO_BITS (!!(CF_BIG_ENDIAN) * 3)
#define CF_RC_BITS (!!(CF_LITTLE_ENDIAN) * 3)


// ======================================================================
#pragma mark - CF-635/CFString.h -
// ======================================================================

typedef UInt32 CFStringEncoding;


// ======================================================================
#pragma mark - CF-635/CFString.c -
// ======================================================================

// This is separate for C++
struct notInlineMutable {
    void *buffer;
    CFIndex length;
    CFIndex capacity;                           // Capacity in bytes
    unsigned int hasGap:1;                      // Currently unused
    unsigned int isFixedCapacity:1;
    unsigned int isExternalMutable:1;
    unsigned int capacityProvidedExternally:1;
#if __LP64__
    unsigned long desiredCapacity:60;
#else
    unsigned long desiredCapacity:28;
#endif
    CFAllocatorRef contentsAllocator;           // Optional
};                             // The only mutable variant for CFString

/* !!! Never do sizeof(CFString); the union is here just to make it easier to access some fields.
 */
struct CFString {
    struct CFRuntimeBase base;
    union {	// In many cases the allocated structs are smaller than these
        struct inline1 {
            CFIndex length;
        } inline1;                                      // Bytes follow the length
        struct inline2 {
            uint8_t length;
        } inline2;                                      // Bytes follow the length
        struct notInlineImmutable1 {
            void *buffer;                               // Note that the buffer is in the same place for all non-inline variants of CFString
            CFIndex length;
            CFAllocatorRef contentsDeallocator;		// Optional; just the dealloc func is used
        } notInlineImmutable1;                          // This is the usual not-inline immutable CFString
        struct notInlineImmutable2 {
            void *buffer;
            CFAllocatorRef contentsDeallocator;		// Optional; just the dealloc func is used
        } notInlineImmutable2;                          // This is the not-inline immutable CFString when length is stored with the contents (first byte)
        struct notInlineMutable notInlineMutable;
    } variants;
};

/*
 I = is immutable
 E = not inline contents
 U = is Unicode
 N = has NULL byte
 L = has length byte
 D = explicit deallocator for contents (for mutable objects, allocator)
 C = length field is CFIndex (rather than UInt32); only meaningful for 64-bit, really
 if needed this bit (valuable real-estate) can be given up for another bit elsewhere, since this info is needed just for 64-bit
 
 Also need (only for mutable)
 F = is fixed
 G = has gap
 Cap, DesCap = capacity
 
 B7 B6 B5 B4 B3 B2 B1 B0
 U  N  L  C  I
 
 B6 B5
 0  0   inline contents
 0  1   E (freed with default allocator)
 1  0   E (not freed)
 1  1   E D
 
 !!! Note: Constant CFStrings use the bit patterns:
 C8 (11001000 = default allocator, not inline, not freed contents; 8-bit; has NULL byte; doesn't have length; is immutable)
 D0 (11010000 = default allocator, not inline, not freed contents; Unicode; is immutable)
 The bit usages should not be modified in a way that would effect these bit patterns.
 */

enum {
    kCFFreeContentsWhenDoneMask = 0x020,
    kCFFreeContentsWhenDone = 0x020,
    kCFContentsMask = 0x060,
	kCFHasInlineContents = 0x000,
	kCFNotInlineContentsNoFree = 0x040,		// Don't free
	kCFNotInlineContentsDefaultFree = 0x020,	// Use allocator's free function
	kCFNotInlineContentsCustomFree = 0x060,		// Use a specially provided free function
    kCFHasContentsAllocatorMask = 0x060,
    kCFHasContentsAllocator = 0x060,		// (For mutable strings) use a specially provided allocator
    kCFHasContentsDeallocatorMask = 0x060,
    kCFHasContentsDeallocator = 0x060,
    kCFIsMutableMask = 0x01,
	kCFIsMutable = 0x01,
    kCFIsUnicodeMask = 0x10,
	kCFIsUnicode = 0x10,
    kCFHasNullByteMask = 0x08,
	kCFHasNullByte = 0x08,
    kCFHasLengthByteMask = 0x04,
	kCFHasLengthByte = 0x04,
    // !!! Bit 0x02 has been freed up
};


// !!! Assumptions:
// Mutable strings are not inline
// Compile-time constant strings are not inline
// Mutable strings always have explicit length (but they might also have length byte and null byte)
// If there is an explicit length, always use that instead of the length byte (length byte is useful for quickly returning pascal strings)
// Never look at the length byte for the length; use CFStrLength or CFStrLength2

/* The following set of functions and macros need to be updated on change to the bit configuration
 */
CF_INLINE Boolean CF_StrIsMutable(const struct CFString* str)         {return (str->base._cfinfo[CF_INFO_BITS] & kCFIsMutableMask) == kCFIsMutable;}
CF_INLINE Boolean CF_StrIsInline(const struct CFString* str)          {return (str->base._cfinfo[CF_INFO_BITS] & kCFContentsMask) == kCFHasInlineContents;}
CF_INLINE Boolean CF_StrIsUnicode(const struct CFString* str)         {return (str->base._cfinfo[CF_INFO_BITS] & kCFIsUnicodeMask) == kCFIsUnicode;}
CF_INLINE Boolean CF_StrHasLengthByte(const struct CFString* str)     {return (str->base._cfinfo[CF_INFO_BITS] & kCFHasLengthByteMask) == kCFHasLengthByte;}
CF_INLINE Boolean CF_StrHasExplicitLength(const struct CFString* str) {return (str->base._cfinfo[CF_INFO_BITS] & (kCFIsMutableMask | kCFHasLengthByteMask)) != kCFHasLengthByte;}	// Has explicit length if (1) mutable or (2) not mutable and no length byte

/* Returns ptr to the buffer (which might include the length byte)
 */
CF_INLINE const void *CF_StrContents(const struct CFString* str) {
    if (CF_StrIsInline(str)) {
        return (const void *)(((uintptr_t)&(str->variants)) + (CF_StrHasExplicitLength(str) ? sizeof(CFIndex) : 0));
    } else {	// Not inline; pointer is always word 2
        return str->variants.notInlineImmutable1.buffer;
    }
}

/* Returns length; use __CFStrLength2 if contents buffer pointer has already been computed.
 */
// See below for custom safe version of this method.
//CF_INLINE CFIndex CF_StrLength(const struct CFString* str) {
//    if (CF_StrHasExplicitLength(str)) {
//        if (CF_StrIsInline(str)) {
//            return str->variants.inline1.length;
//        } else {
//            return str->variants.notInlineImmutable1.length;
//        }
//    } else {
//        return (CFIndex)(*((uint8_t *)CF_StrContents(str)));
//    }
//}


// ======================================================================
#pragma mark - CF-635/CFURL.c -
// ======================================================================

struct CFURL {
    struct CFRuntimeBase _cfBase;
    UInt32 _flags;
    CFStringEncoding _encoding; // The encoding to use when asked to remove percent escapes; this is never consulted if IS_OLD_UTF8_STYLE is set.
    struct CFString* _string; // Never NULL; the meaning of _string depends on URL_PATH_TYPE(myURL) (see above)
    const struct CFURL* _base;
    CFRange *ranges;
    struct _CFURLAdditionalData* extra;
    void *_resourceInfo;    // For use by CarbonCore to cache property values. Retained and released by CFURL.
};


// ======================================================================
#pragma mark - CF-635/CFDate.c -
// ======================================================================

struct CFDate {
    // According to CFDate.c the structure is a CFRuntimeBase followed
    // by the time. In fact, it's only an isa pointer followed by the time.
    //struct CFRuntimeBase _base;
    uintptr_t _cfisa;
    CFAbsoluteTime _time;       /* immutable */
};


// ======================================================================
#pragma mark - CF-635/CFArray.c -
// ======================================================================

struct CFArrayBucket {
    const void *_item;
};

struct CFArrayDeque {
    uintptr_t _leftIdx;
    uintptr_t _capacity;
    /* struct __CFArrayBucket buckets follow here */
};

struct CFArray {
    struct CFRuntimeBase _base;
    CFIndex _count;		/* number of objects */
    CFIndex _mutations;
    int32_t _mutInProgress;
    __strong void *_store;           /* can be NULL when MutableDeque */
};

/* Flag bits */
enum {		/* Bits 0-1 */
    kCFArrayImmutable = 0,
    kCFArrayDeque = 2,
};

enum {		/* Bits 2-3 */
    kCFArrayHasNullCallBacks = 0,
    kCFArrayHasCFTypeCallBacks = 1,
    kCFArrayHasCustomCallBacks = 3	/* callbacks are at end of header */
};

CF_INLINE CFIndex CF_ArrayGetType(const struct CFArray* array) {
    return CF_BitfieldGetValue(((const struct CFRuntimeBase *)array)->_cfinfo[CF_INFO_BITS], 1, 0);
}

CF_INLINE CFIndex CF_ArrayGetSizeOfType(const CFIndex t) {
    CFIndex size = 0;
    size += sizeof(struct CFArray);
    if (CF_BitfieldGetValue((unsigned long)t, 3, 2) == kCFArrayHasCustomCallBacks) {
        size += sizeof(CFArrayCallBacks);
    }
    return size;
}

// See below for custom safe version of this method.
CF_INLINE struct CFArrayBucket *CF_ArrayGetBucketsPtr(const struct CFArray* array) {
    switch (CF_ArrayGetType(array)) {
        case kCFArrayImmutable:
            return (struct CFArrayBucket *)((uint8_t *)array + CF_ArrayGetSizeOfType(((struct CFRuntimeBase *)array)->_cfinfo[CF_INFO_BITS]));
        case kCFArrayDeque: {
            struct CFArrayDeque *deque = (struct CFArrayDeque *)array->_store;
            return (struct CFArrayBucket *)((uint8_t *)deque + sizeof(struct CFArrayDeque) + deque->_leftIdx * sizeof(struct CFArrayBucket));
        }
    }
    return NULL;
}


// ======================================================================
#pragma mark - CF-635/CFBasicHash.m -
// ======================================================================

struct CFBasicHash {
    struct CFRuntimeBase base;
    struct { // 128 bits
        uint8_t hash_style:2;
        uint8_t fast_grow:1;
        uint8_t keys_offset:1;
        uint8_t counts_offset:2;
        uint8_t counts_width:2;
        uint8_t hashes_offset:2;
        uint8_t strong_values:1;
        uint8_t strong_keys:1;
        uint8_t weak_values:1;
        uint8_t weak_keys:1;
        uint8_t int_values:1;
        uint8_t int_keys:1;
        uint8_t indirect_keys:1;
        uint8_t compactable_keys:1;
        uint8_t compactable_values:1;
        uint8_t finalized:1;
        uint8_t __2:4;
        uint8_t num_buckets_idx;  /* index to number of buckets */
        uint32_t used_buckets;    /* number of used buckets */
        uint8_t __8:8;
        uint8_t __9:8;
        uint16_t special_bits;
        uint16_t deleted;
        uint16_t mutations;
    } bits;
    struct CFBasicHashCallbacks *callbacks;
    void *pointers[1];
};

CF_INLINE intptr_t *CF_BasicHashGetValues(const struct CFBasicHash* ht) {
    return ht->pointers[0];
}

CF_INLINE intptr_t *CF_BasicHashGetKeys(const struct CFBasicHash* ht) {
    return ht->pointers[ht->bits.keys_offset];
}

CF_INLINE void *CF_BasicHashGetCounts(const struct CFBasicHash* ht) {
    return (void *)ht->pointers[ht->bits.counts_offset];
}


// Prime numbers. Values above 100 have been adjusted up so that the
// malloced block size will be just below a multiple of 512; values
// above 1200 have been adjusted up to just below a multiple of 4096.
static const uintptr_t CFBasicHashTableSizes[64] = {
    0, 3, 7, 13, 23, 41, 71, 127, 191, 251, 383, 631, 1087, 1723,
    2803, 4523, 7351, 11959, 19447, 31231, 50683, 81919, 132607,
    214519, 346607, 561109, 907759, 1468927, 2376191, 3845119,
    6221311, 10066421, 16287743, 26354171, 42641881, 68996069,
    111638519, 180634607, 292272623, 472907251,
#if __LP64__
    765180413UL, 1238087663UL, 2003267557UL, 3241355263UL, 5244622819UL,
#if 0
    8485977589UL, 13730600407UL, 22216578047UL, 35947178479UL,
    58163756537UL, 94110934997UL, 152274691561UL, 246385626107UL,
    398660317687UL, 645045943807UL, 1043706260983UL, 1688752204787UL,
    2732458465769UL, 4421210670577UL, 7153669136377UL,
    11574879807461UL, 18728548943849UL, 30303428750843UL
#endif
#endif
};

CF_INLINE uint64_t CF_BasicHashGetSlotCount(const struct CFBasicHash* ht, CFIndex idx) {
    void *counts = CF_BasicHashGetCounts(ht);
    switch (ht->bits.counts_width) {
        case 0: return ((uint8_t *)counts)[idx];
        case 1: return ((uint16_t *)counts)[idx];
        case 2: return ((uint32_t *)counts)[idx];
        case 3: return ((uint64_t *)counts)[idx];
    }
    return 0;
}


CF_INLINE CFIndex CF_BasicHashGetCount(struct CFBasicHash* ht) {
    if (ht->bits.counts_offset) {
        CFIndex total = 0L;
        CFIndex cnt = (CFIndex)CFBasicHashTableSizes[ht->bits.num_buckets_idx];
        for (CFIndex idx = 0; idx < cnt; idx++) {
            total += CF_BasicHashGetSlotCount(ht, idx);
        }
        return total;
    }
    return (CFIndex)ht->bits.used_buckets;
}


#ifdef __cplusplus
}
#endif

#endif // HDR_KSObjCApple_h
