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


// Fake structs. Implement as needed.
typedef struct method_list_t method_list_t;
typedef struct protocol_list_t protocol_list_t;
typedef struct property_list_t property_list_t;

// Remove unknown keywords & directives
#define __strong


// ======================================================================
#pragma mark - objc4-532.2/runtime/objc-private.h -
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
#pragma mark - objc4-532.2/runtime/objc-runtime-new.h -
// ======================================================================

// Values for class_ro_t->flags
// These are emitted by the compiler and are part of the ABI.
// class is a metaclass
#define RO_META               (1<<0)
// class is a root class
#define RO_ROOT               (1<<1)


typedef struct ivar_t {
    // *offset is 64-bit by accident even though other
    // fields restrict total instance size to 32-bit.
    uintptr_t *offset;
    const char *name;
    const char *type;
    // alignment is sometimes -1; use ivar_alignment() instead
    uint32_t alignment  __attribute__((deprecated));
    uint32_t size;
} ivar_t;

typedef struct ivar_list_t {
    uint32_t entsize;
    uint32_t count;
    ivar_t first;
} ivar_list_t;

typedef struct class_ro_t {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
#ifdef __LP64__
    uint32_t reserved;
#endif

    const uint8_t * ivarLayout;

    const char * name;
    const method_list_t * baseMethods;
    const protocol_list_t * baseProtocols;
    const ivar_list_t * ivars;

    const uint8_t * weakIvarLayout;
    const property_list_t *baseProperties;
} class_ro_t;

typedef struct class_rw_t {
    uint32_t flags;
    uint32_t version;

    const class_ro_t *ro;

    union {
        method_list_t **method_lists;  // RW_METHOD_ARRAY == 1
        method_list_t *method_list;    // RW_METHOD_ARRAY == 0
    };
    struct chained_property_list *properties;
    const protocol_list_t ** protocols;

    struct class_t *firstSubclass;
    struct class_t *nextSiblingClass;
} class_rw_t;

typedef struct class_t {
    struct class_t *isa;
    struct class_t *superclass;
#pragma clang diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    Cache cache;
#pragma clang diagnostic pop
    IMP *vtable;
    uintptr_t data_NEVER_USE;  // class_rw_t * plus custom rr/alloc flags
} class_t;


// ======================================================================
#pragma mark - CF-635/CFRuntime.h -
// ======================================================================

typedef struct __CFRuntimeBase {
    uintptr_t _cfisa;
    uint8_t _cfinfo[4];
#if __LP64__
    uint32_t _rc;
#endif
} CFRuntimeBase;


// ======================================================================
#pragma mark - CF-635/CFInternal.h -
// ======================================================================

#if defined(__BIG_ENDIAN__)
#define __CF_BIG_ENDIAN__ 1
#define __CF_LITTLE_ENDIAN__ 0
#endif

#if defined(__LITTLE_ENDIAN__)
#define __CF_LITTLE_ENDIAN__ 1
#define __CF_BIG_ENDIAN__ 0
#endif

#define CF_INFO_BITS (!!(__CF_BIG_ENDIAN__) * 3)
#define CF_RC_BITS (!!(__CF_LITTLE_ENDIAN__) * 3)

/* Bit manipulation macros */
/* Bits are numbered from 31 on left to 0 on right */
/* May or may not work if you use them on bitfields in types other than UInt32, bitfields the full width of a UInt32, or anything else for which they were not designed. */
/* In the following, N1 and N2 specify an inclusive range N2..N1 with N1 >= N2 */
#define __CFBitfieldMask(N1, N2)	((((UInt32)~0UL) << (31UL - (N1) + (N2))) >> (31UL - N1))
#define __CFBitfieldGetValue(V, N1, N2)	(((V) & __CFBitfieldMask(N1, N2)) >> (N2))


// ======================================================================
#pragma mark - CF-635/CFString.c -
// ======================================================================

// This is separate for C++
struct __notInlineMutable {
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
struct __CFString {
    CFRuntimeBase base;
    union {	// In many cases the allocated structs are smaller than these
        struct __inline1 {
            CFIndex length;
        } inline1;                                      // Bytes follow the length
        struct __inline2 {
            uint8_t length;
        } inline2;                                      // Not part of official CF, but this type exists.
        struct __notInlineImmutable1 {
            void *buffer;                               // Note that the buffer is in the same place for all non-inline variants of CFString
            CFIndex length;
            CFAllocatorRef contentsDeallocator;		// Optional; just the dealloc func is used
        } notInlineImmutable1;                          // This is the usual not-inline immutable CFString
        struct __notInlineImmutable2 {
            void *buffer;
            CFAllocatorRef contentsDeallocator;		// Optional; just the dealloc func is used
        } notInlineImmutable2;                          // This is the not-inline immutable CFString when length is stored with the contents (first byte)
        struct __notInlineMutable notInlineMutable;
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
    __kCFFreeContentsWhenDoneMask = 0x020,
    __kCFFreeContentsWhenDone = 0x020,
    __kCFContentsMask = 0x060,
	__kCFHasInlineContents = 0x000,
	__kCFNotInlineContentsNoFree = 0x040,		// Don't free
	__kCFNotInlineContentsDefaultFree = 0x020,	// Use allocator's free function
	__kCFNotInlineContentsCustomFree = 0x060,		// Use a specially provided free function
    __kCFHasContentsAllocatorMask = 0x060,
    __kCFHasContentsAllocator = 0x060,		// (For mutable strings) use a specially provided allocator
    __kCFHasContentsDeallocatorMask = 0x060,
    __kCFHasContentsDeallocator = 0x060,
    __kCFIsMutableMask = 0x01,
	__kCFIsMutable = 0x01,
    __kCFIsUnicodeMask = 0x10,
	__kCFIsUnicode = 0x10,
    __kCFHasNullByteMask = 0x08,
	__kCFHasNullByte = 0x08,
    __kCFHasLengthByteMask = 0x04,
	__kCFHasLengthByte = 0x04,
    // !!! Bit 0x02 has been freed up
};


// !!! Assumptions:
// Mutable strings are not inline
// Compile-time constant strings are not inline
// Mutable strings always have explicit length (but they might also have length byte and null byte)
// If there is an explicit length, always use that instead of the length byte (length byte is useful for quickly returning pascal strings)
// Never look at the length byte for the length; use __CFStrLength or __CFStrLength2

/* The following set of functions and macros need to be updated on change to the bit configuration
 */
CF_INLINE Boolean __CFStrIsMutable(CFStringRef str)                 {return (str->base._cfinfo[CF_INFO_BITS] & __kCFIsMutableMask) == __kCFIsMutable;}
CF_INLINE Boolean __CFStrIsInline(CFStringRef str)                  {return (str->base._cfinfo[CF_INFO_BITS] & __kCFContentsMask) == __kCFHasInlineContents;}
CF_INLINE Boolean __CFStrIsUnicode(CFStringRef str)                 {return (str->base._cfinfo[CF_INFO_BITS] & __kCFIsUnicodeMask) == __kCFIsUnicode;}
CF_INLINE Boolean __CFStrHasLengthByte(CFStringRef str)             {return (str->base._cfinfo[CF_INFO_BITS] & __kCFHasLengthByteMask) == __kCFHasLengthByte;}
CF_INLINE Boolean __CFStrHasExplicitLength(CFStringRef str)         {return (str->base._cfinfo[CF_INFO_BITS] & (__kCFIsMutableMask | __kCFHasLengthByteMask)) != __kCFHasLengthByte;}	// Has explicit length if (1) mutable or (2) not mutable and no length byte

/* Returns ptr to the buffer (which might include the length byte)
 */
CF_INLINE const void *__CFStrContents(CFStringRef str) {
    if (__CFStrIsInline(str)) {
        return (const void *)(((uintptr_t)&(str->variants)) + (__CFStrHasExplicitLength(str) ? sizeof(CFIndex) : 0));
    } else {	// Not inline; pointer is always word 2
        return str->variants.notInlineImmutable1.buffer;
    }
}


// ======================================================================
#pragma mark - CF-635/CFURL.c -
// ======================================================================

struct __CFURL {
    CFRuntimeBase _cfBase;
    UInt32 _flags;
    CFStringEncoding _encoding; // The encoding to use when asked to remove percent escapes; this is never consulted if IS_OLD_UTF8_STYLE is set.
    CFStringRef _string; // Never NULL; the meaning of _string depends on URL_PATH_TYPE(myURL) (see above)
    CFURLRef _base;
    CFRange *ranges;
    struct _CFURLAdditionalData* extra;
    void *_resourceInfo;    // For use by CarbonCore to cache property values. Retained and released by CFURL.
};


// ======================================================================
#pragma mark - CF-635/CFDate.c -
// ======================================================================

struct __CFDate {
    // According to CFDate.c the structure is a CFRuntimeBase followed
    // by the time. In fact, it's only an isa pointer followed by the time.
    //struct CFRuntimeBase _base;
    uintptr_t _cfisa;
    CFAbsoluteTime _time;       /* immutable */
};


// ======================================================================
#pragma mark - CF-635/CFNumber.c -
// ======================================================================

struct __CFNumber {
    CFRuntimeBase _base;
    uint64_t _pad; // need this space here for the constant objects
    /* 0 or 8 more bytes allocated here */
};


// ======================================================================
#pragma mark - CF-635/CFArray.c -
// ======================================================================

struct __CFArrayBucket {
    const void *_item;
};

struct __CFArrayDeque {
    uintptr_t _leftIdx;
    uintptr_t _capacity;
    /* struct __CFArrayBucket buckets follow here */
};

struct __CFArray {
    CFRuntimeBase _base;
    CFIndex _count;		/* number of objects */
    CFIndex _mutations;
    int32_t _mutInProgress;
    __strong void *_store;           /* can be NULL when MutableDeque */
};

/* Flag bits */
enum {		/* Bits 0-1 */
    __kCFArrayImmutable = 0,
    __kCFArrayDeque = 2,
};

enum {		/* Bits 2-3 */
    __kCFArrayHasNullCallBacks = 0,
    __kCFArrayHasCFTypeCallBacks = 1,
    __kCFArrayHasCustomCallBacks = 3	/* callbacks are at end of header */
};

CF_INLINE CFIndex __CFArrayGetType(CFArrayRef array) {
    return __CFBitfieldGetValue(((const CFRuntimeBase *)array)->_cfinfo[CF_INFO_BITS], 1, 0);
}

CF_INLINE CFIndex __CFArrayGetSizeOfType(CFIndex t) {
    CFIndex size = 0;
    size += sizeof(struct __CFArray);
    if (__CFBitfieldGetValue((unsigned)t, 3, 2) == __kCFArrayHasCustomCallBacks) {
        size += sizeof(CFArrayCallBacks);
    }
    return size;
}

/* Only applies to immutable and mutable-deque-using arrays;
 * Returns the bucket holding the left-most real value in the latter case. */
CF_INLINE struct __CFArrayBucket *__CFArrayGetBucketsPtr(CFArrayRef array) {
    switch (__CFArrayGetType(array)) {
        case __kCFArrayImmutable:
            return (struct __CFArrayBucket *)((uint8_t *)array + __CFArrayGetSizeOfType(((CFRuntimeBase *)array)->_cfinfo[CF_INFO_BITS]));
        case __kCFArrayDeque: {
            struct __CFArrayDeque *deque = (struct __CFArrayDeque *)array->_store;
            return (struct __CFArrayBucket *)((uint8_t *)deque + sizeof(struct __CFArrayDeque) + deque->_leftIdx * sizeof(struct __CFArrayBucket));
        }
    }
    return NULL;
}


// ======================================================================
#pragma mark - CF-635/CFBasicHash.h -
// ======================================================================

typedef struct __CFBasicHash *CFBasicHashRef;
typedef const struct __CFBasicHash *CFConstBasicHashRef;

typedef struct __CFBasicHashCallbacks CFBasicHashCallbacks;

struct __CFBasicHashCallbacks {
    CFBasicHashCallbacks *(*copyCallbacks)(CFConstBasicHashRef ht, CFAllocatorRef allocator, CFBasicHashCallbacks *cb);	// Return new value
    void (*freeCallbacks)(CFConstBasicHashRef ht, CFAllocatorRef allocator, CFBasicHashCallbacks *cb);
    uintptr_t (*retainValue)(CFConstBasicHashRef ht, uintptr_t stack_value);	// Return 2nd arg or new value
    uintptr_t (*retainKey)(CFConstBasicHashRef ht, uintptr_t stack_key);	// Return 2nd arg or new key
    void (*releaseValue)(CFConstBasicHashRef ht, uintptr_t stack_value);
    void (*releaseKey)(CFConstBasicHashRef ht, uintptr_t stack_key);
    Boolean (*equateValues)(CFConstBasicHashRef ht, uintptr_t coll_value1, uintptr_t stack_value2); // 2nd arg is in-collection value, 3rd arg is probe parameter OR in-collection value for a second collection
    Boolean (*equateKeys)(CFConstBasicHashRef ht, uintptr_t coll_key1, uintptr_t stack_key2); // 2nd arg is in-collection key, 3rd arg is probe parameter
    uintptr_t (*hashKey)(CFConstBasicHashRef ht, uintptr_t stack_key);
    uintptr_t (*getIndirectKey)(CFConstBasicHashRef ht, uintptr_t coll_value);	// Return key; 2nd arg is in-collection value
    CFStringRef (*copyValueDescription)(CFConstBasicHashRef ht, uintptr_t stack_value);
    CFStringRef (*copyKeyDescription)(CFConstBasicHashRef ht, uintptr_t stack_key);
    uintptr_t context[0]; // variable size; any pointers in here must remain valid as long as the CFBasicHash
};


// ======================================================================
#pragma mark - CF-635/CFBasicHash.m -
// ======================================================================

typedef union {
    uintptr_t neutral;
    uintptr_t strong;
    uintptr_t weak;
} CFBasicHashValue;

struct __CFBasicHash {
    CFRuntimeBase base;
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
    __strong CFBasicHashCallbacks *callbacks;
    void *pointers[1];
};

CF_INLINE CFBasicHashValue *__CFBasicHashGetValues(CFConstBasicHashRef ht) {
    return (CFBasicHashValue *)ht->pointers[0];
}

CF_INLINE CFBasicHashValue *__CFBasicHashGetKeys(CFConstBasicHashRef ht) {
    return (CFBasicHashValue *)ht->pointers[ht->bits.keys_offset];
}

CF_INLINE void *__CFBasicHashGetCounts(CFConstBasicHashRef ht) {
    return (void *)ht->pointers[ht->bits.counts_offset];
}


// Prime numbers. Values above 100 have been adjusted up so that the
// malloced block size will be just below a multiple of 512; values
// above 1200 have been adjusted up to just below a multiple of 4096.
static const uintptr_t __CFBasicHashTableSizes[64] = {
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

CF_INLINE uintptr_t __CFBasicHashGetSlotCount(CFConstBasicHashRef ht, CFIndex idx) {
    void *counts = __CFBasicHashGetCounts(ht);
    switch (ht->bits.counts_width) {
        case 0: return ((uint8_t *)counts)[idx];
        case 1: return ((uint16_t *)counts)[idx];
        case 2: return ((uint32_t *)counts)[idx];
        case 3: return (uintptr_t)((uint64_t *)counts)[idx];
    }
    return 0;
}


//__private_extern__ CFIndex CFBasicHashGetCount(CFConstBasicHashRef ht) {
CF_INLINE CFIndex __CFBasicHashGetCount(CFConstBasicHashRef ht) {
    if (ht->bits.counts_offset) {
        CFIndex total = 0L;
        CFIndex cnt = (CFIndex)__CFBasicHashTableSizes[ht->bits.num_buckets_idx];
        for (CFIndex idx = 0; idx < cnt; idx++) {
            total += __CFBasicHashGetSlotCount(ht, idx);
        }
        return total;
    }
    return (CFIndex)ht->bits.used_buckets;
}


#ifdef __cplusplus
}
#endif

#endif // HDR_KSObjCApple_h
