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

#include <objc/objc.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MAKE_LIST_T(TYPE) \
typedef struct TYPE##_list_t { \
    uint32_t entsizeAndFlags; \
    uint32_t count; \
    TYPE##_t first; \
} TYPE##_list_t; \
typedef TYPE##_list_t TYPE##_array_t

#define OBJC_OBJECT(NAME) \
NAME { \
    Class isa  OBJC_ISA_AVAILABILITY;


// ======================================================================
#pragma mark - objc4-680/runtime/objc-msg-x86_64.s -
// and objc4-680/runtime/objc-msg-arm64.s
// ======================================================================

// Use ISA_MASK_OLD before iOS 9, in and after iOS 9, use ISA_MASK
#if __x86_64__
#   define ISA_TAG_MASK 1UL
#   define ISA_MASK     0x00007ffffffffff8UL
#elif defined(__arm64__)
#   define ISA_TAG_MASK 1UL
#   define ISA_MASK_OLD 0x00000001fffffff8UL
#   define ISA_MASK     0x0000000ffffffff8UL
#else
#   define ISA_TAG_MASK 0UL
#   define ISA_MASK     ~1UL
#endif

// ======================================================================
#pragma mark - objc4-912.3/runtime/objc-config.h -
// ======================================================================

#if __ARM_ARCH_7K__ >= 2  ||  (__arm64__ && !__LP64__)
#   define SUPPORT_INDEXED_ISA 1
#else
#   define SUPPORT_INDEXED_ISA 0
#endif

// ======================================================================
#pragma mark - objc4-912.3/runtime/objc-internal.h -
// With removed nullability to suppress warning
// ======================================================================

#if __LP64__
#define OBJC_HAVE_TAGGED_POINTERS 1
#endif

// Tagged pointer layout and usage is subject to change on different OS versions.

// Tag indexes 0..<7 have a 60-bit payload.
// Tag index 7 is reserved.
// Tag indexes 8..<264 have a 52-bit payload.
// Tag index 264 is reserved.

#if __has_feature(objc_fixed_enum)  ||  __cplusplus >= 201103L
enum objc_tag_index_t : uint16_t
#else
typedef uint16_t objc_tag_index_t;
enum
#endif
{
    // 60-bit payloads
    OBJC_TAG_NSAtom            = 0,
    OBJC_TAG_1                 = 1,
    OBJC_TAG_NSString          = 2,
    OBJC_TAG_NSNumber          = 3,
    OBJC_TAG_NSIndexPath       = 4,
    OBJC_TAG_NSManagedObjectID = 5,
    OBJC_TAG_NSDate            = 6,

    // 60-bit reserved
    OBJC_TAG_RESERVED_7        = 7,

    // 52-bit payloads
    OBJC_TAG_Photos_1          = 8,
    OBJC_TAG_Photos_2          = 9,
    OBJC_TAG_Photos_3          = 10,
    OBJC_TAG_Photos_4          = 11,
    OBJC_TAG_XPC_1             = 12,
    OBJC_TAG_XPC_2             = 13,
    OBJC_TAG_XPC_3             = 14,
    OBJC_TAG_XPC_4             = 15,
    OBJC_TAG_NSColor           = 16,
    OBJC_TAG_UIColor           = 17,
    OBJC_TAG_CGColor           = 18,
    OBJC_TAG_NSIndexSet        = 19,
    OBJC_TAG_NSMethodSignature = 20,
    OBJC_TAG_UTTypeRecord      = 21,
    OBJC_TAG_Foundation_1      = 22,
    OBJC_TAG_Foundation_2      = 23,
    OBJC_TAG_Foundation_3      = 24,
    OBJC_TAG_Foundation_4      = 25,
    OBJC_TAG_CGRegion          = 26,

    // When using the split tagged pointer representation
    // (OBJC_SPLIT_TAGGED_POINTERS), this is the first tag where
    // the tag and payload are unobfuscated. All tags from here to
    // OBJC_TAG_Last52BitPayload are unobfuscated. The shared cache
    // builder is able to construct these as long as the low bit is
    // not set (i.e. even-numbered tags).
    OBJC_TAG_FirstUnobfuscatedSplitTag = 136, // 128 + 8, first ext tag with high bit set

    OBJC_TAG_Constant_CFString = 136,

    OBJC_TAG_First60BitPayload = 0,
    OBJC_TAG_Last60BitPayload  = 6,
    OBJC_TAG_First52BitPayload = 8,
    OBJC_TAG_Last52BitPayload  = 263,

    OBJC_TAG_RESERVED_264      = 264
};
#if __has_feature(objc_fixed_enum)  &&  !defined(__cplusplus)
typedef enum objc_tag_index_t objc_tag_index_t;
#endif

#if OBJC_HAVE_TAGGED_POINTERS // (KSCrash) This line is moved here to make `objc_tag_index_t` enum visible for i386.

// Returns true if tagged pointers are enabled.
// The other functions below must not be called if tagged pointers are disabled.
static inline bool
_objc_taggedPointersEnabled(void);

// Create a tagged pointer object with the given tag and payload.
// Assumes the tag is valid.
// Assumes tagged pointers are enabled.
// The payload will be silently truncated to fit.
static inline void *
_objc_makeTaggedPointer(objc_tag_index_t tag, uintptr_t payload);

// Return true if ptr is a tagged pointer object.
// Does not check the validity of ptr's class.
static inline bool
_objc_isTaggedPointer(const void *ptr);

// Extract the tag value from the given tagged pointer object.
// Assumes ptr is a valid tagged pointer object.
// Does not check the validity of ptr's tag.
static inline objc_tag_index_t
_objc_getTaggedPointerTag(const void *ptr);

// Extract the payload from the given tagged pointer object.
// Assumes ptr is a valid tagged pointer object.
// The payload value is zero-extended.
static inline uintptr_t
_objc_getTaggedPointerValue(const void *ptr);

// Extract the payload from the given tagged pointer object.
// Assumes ptr is a valid tagged pointer object.
// The payload value is sign-extended.
static inline intptr_t
_objc_getTaggedPointerSignedValue(const void *ptr);

// (KSCrash) Added to handle runtime checks for Split Tagged Pointers,
// which were introduced in objc4-818.2, corresponding to iOS/tvOS 14, macOS 11.0.1, and watchOS 7.
// This function provides compatibility with earlier OS versions that we still support.
static inline bool
ksc_objc_splitTaggedPointersEnabled(void);

// Don't use the values below. Use the declarations above.

#if __arm64__
// ARM64 uses a new tagged pointer scheme where normal tags are in
// the low bits, extended tags are in the high bits, and half of the
// extended tag space is reserved for unobfuscated payloads.
#   define OBJC_SPLIT_TAGGED_POINTERS 1
#else
#   define OBJC_SPLIT_TAGGED_POINTERS 0
#endif

#if (TARGET_OS_OSX || TARGET_OS_MACCATALYST) && __x86_64__
// 64-bit Mac - tag bit is LSB
#   define OBJC_MSB_TAGGED_POINTERS 0
#else
// Everything else - tag bit is MSB
#   define OBJC_MSB_TAGGED_POINTERS 1
#endif

#define _OBJC_TAG_INDEX_MASK 0x7UL

#define _OBJC_TAG_EXT_INDEX_MASK 0xff
// array slot has no extra bits
#define _OBJC_TAG_EXT_SLOT_COUNT 256
#define _OBJC_TAG_EXT_SLOT_MASK 0xff

static inline int
_OBJC_TAG_SLOT_COUNT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 8 : 16;
}

static inline uintptr_t
_OBJC_TAG_SLOT_MASK_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 0x7UL : 0xfUL;
}

static inline uintptr_t
_OBJC_TAG_MASK_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? (1UL<<63) :
        OBJC_MSB_TAGGED_POINTERS ? (1UL<<63) : 1UL;
}

static inline int
_OBJC_TAG_INDEX_SHIFT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 0 :
        OBJC_MSB_TAGGED_POINTERS ? 60 : 1;
}

static inline int
_OBJC_TAG_SLOT_SHIFT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 0 :
        OBJC_MSB_TAGGED_POINTERS ? 60 : 0;
}

static inline int
_OBJC_TAG_PAYLOAD_LSHIFT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 1 :
        OBJC_MSB_TAGGED_POINTERS ? 4 : 0;
}

static inline int
_OBJC_TAG_PAYLOAD_RSHIFT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 4 :
        OBJC_MSB_TAGGED_POINTERS ? 4 : 4;
}

static inline uintptr_t
_OBJC_TAG_EXT_MASK_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? (_OBJC_TAG_MASK_func() | 0x7UL) :
        OBJC_MSB_TAGGED_POINTERS ? (0xfUL<<60) : 0xfUL;
}

static inline uintptr_t
_OBJC_TAG_NO_OBFUSCATION_MASK_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? ((1UL<<62) | _OBJC_TAG_EXT_MASK_func()) : 0;
}

static inline int
_OBJC_TAG_EXT_SLOT_SHIFT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 55 :
        OBJC_MSB_TAGGED_POINTERS ? 52 : 4;
}

static inline uintptr_t
_OBJC_TAG_CONSTANT_POINTER_MASK_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ?
        ~(_OBJC_TAG_EXT_MASK_func() | ((uintptr_t)_OBJC_TAG_EXT_SLOT_MASK << _OBJC_TAG_EXT_SLOT_SHIFT_func())) : 0;
}

static inline int
_OBJC_TAG_EXT_INDEX_SHIFT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 55 :
        OBJC_MSB_TAGGED_POINTERS ? 52 : 4;
}

static inline int
_OBJC_TAG_EXT_PAYLOAD_LSHIFT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 9 :
        OBJC_MSB_TAGGED_POINTERS ? 12 : 0;
}

static inline int
_OBJC_TAG_EXT_PAYLOAD_RSHIFT_func(void)
{
    return ksc_objc_splitTaggedPointersEnabled() ? 12 :
        OBJC_MSB_TAGGED_POINTERS ? 12 : 12;
}

// (KSCrash) Macros were rewritten to include runtime checks for split tagged pointers, based on objc4-912.3.
#define _OBJC_TAG_SLOT_COUNT             _OBJC_TAG_SLOT_COUNT_func()
#define _OBJC_TAG_SLOT_MASK              _OBJC_TAG_SLOT_MASK_func()
#define _OBJC_TAG_MASK                   _OBJC_TAG_MASK_func()
#define _OBJC_TAG_INDEX_SHIFT            _OBJC_TAG_INDEX_SHIFT_func()
#define _OBJC_TAG_SLOT_SHIFT             _OBJC_TAG_SLOT_SHIFT_func()
#define _OBJC_TAG_PAYLOAD_LSHIFT         _OBJC_TAG_PAYLOAD_LSHIFT_func()
#define _OBJC_TAG_PAYLOAD_RSHIFT         _OBJC_TAG_PAYLOAD_RSHIFT_func()
#define _OBJC_TAG_EXT_MASK               _OBJC_TAG_EXT_MASK_func()
#define _OBJC_TAG_NO_OBFUSCATION_MASK    _OBJC_TAG_NO_OBFUSCATION_MASK_func()
#define _OBJC_TAG_CONSTANT_POINTER_MASK  _OBJC_TAG_CONSTANT_POINTER_MASK_func()
#define _OBJC_TAG_EXT_INDEX_SHIFT        _OBJC_TAG_EXT_INDEX_SHIFT_func()
#define _OBJC_TAG_EXT_SLOT_SHIFT         _OBJC_TAG_EXT_SLOT_SHIFT_func()
#define _OBJC_TAG_EXT_PAYLOAD_LSHIFT     _OBJC_TAG_EXT_PAYLOAD_LSHIFT_func()
#define _OBJC_TAG_EXT_PAYLOAD_RSHIFT     _OBJC_TAG_EXT_PAYLOAD_RSHIFT_func()

// Map of tags to obfuscated tags.
extern uintptr_t objc_debug_taggedpointer_obfuscator;

#if OBJC_SPLIT_TAGGED_POINTERS
// (KSCrash) Weakly linked to support *OS versions prior to objc4-818.2, where this symbol may not be available.
extern __attribute__((weak)) uint8_t objc_debug_tag60_permutations[8];

static inline uintptr_t _objc_basicTagToObfuscatedTag(uintptr_t tag) {
    if (objc_debug_tag60_permutations != NULL && tag < 8) {
        return objc_debug_tag60_permutations[tag];
    }
    // (KSCrash) Fallback: return the original tag if permutations are unavailable or tag is out of range.
    // Runtime handles the availability of split tagged pointers, so fallback is typically unnecessary,
    // but it's included as a safeguard.
    return tag;
}

static inline uintptr_t _objc_obfuscatedTagToBasicTag(uintptr_t tag) {
    if (objc_debug_tag60_permutations != NULL) {
        for (unsigned i = 0; i < 7; i++) {
            if (objc_debug_tag60_permutations[i] == tag) {
                return i;
            }
        }
    }
    // (KSCrash) Fallback: return the original tag if within range, otherwise return 7.
    // Runtime handles the availability of split tagged pointers, so fallback is typically unnecessary,
    // but it's included as a safeguard.
    return (tag < 8) ? tag : 7;
}
#endif

static inline void *
_objc_encodeTaggedPointer_withObfuscator(uintptr_t ptr, uintptr_t obfuscator)
{
    uintptr_t value = (obfuscator ^ ptr);
#if OBJC_SPLIT_TAGGED_POINTERS
    if (ksc_objc_splitTaggedPointersEnabled()) {
        if ((value & _OBJC_TAG_NO_OBFUSCATION_MASK) == _OBJC_TAG_NO_OBFUSCATION_MASK)
            return (void *)ptr;
        uintptr_t basicTag = (value >> _OBJC_TAG_INDEX_SHIFT) & _OBJC_TAG_INDEX_MASK;
        uintptr_t permutedTag = _objc_basicTagToObfuscatedTag(basicTag);
        value &= ~(_OBJC_TAG_INDEX_MASK << _OBJC_TAG_INDEX_SHIFT);
        value |= permutedTag << _OBJC_TAG_INDEX_SHIFT;
    }
#endif
    return (void *)value;
}

static inline uintptr_t
_objc_decodeTaggedPointer_noPermute_withObfuscator(const void *ptr,
                                                   uintptr_t obfuscator)
{
    uintptr_t value = (uintptr_t)ptr;
#if OBJC_SPLIT_TAGGED_POINTERS
    if (ksc_objc_splitTaggedPointersEnabled()) {
        if ((value & _OBJC_TAG_NO_OBFUSCATION_MASK) == _OBJC_TAG_NO_OBFUSCATION_MASK)
            return value;
    }
#endif
    return value ^ obfuscator;
}

static inline uintptr_t
_objc_decodeTaggedPointer_withObfuscator(const void *ptr,
                                         uintptr_t obfuscator)
{
    uintptr_t value
    = _objc_decodeTaggedPointer_noPermute_withObfuscator(ptr, obfuscator);
#if OBJC_SPLIT_TAGGED_POINTERS
    if (ksc_objc_splitTaggedPointersEnabled()) {
        uintptr_t basicTag = (value >> _OBJC_TAG_INDEX_SHIFT) & _OBJC_TAG_INDEX_MASK;

        value &= ~(_OBJC_TAG_INDEX_MASK << _OBJC_TAG_INDEX_SHIFT);
        value |= _objc_obfuscatedTagToBasicTag(basicTag) << _OBJC_TAG_INDEX_SHIFT;
    }
#endif
    return value;
}

static inline void *
_objc_encodeTaggedPointer(uintptr_t ptr)
{
    return _objc_encodeTaggedPointer_withObfuscator(ptr, objc_debug_taggedpointer_obfuscator);
}

static inline uintptr_t
_objc_decodeTaggedPointer_noPermute(const void *ptr)
{
    return _objc_decodeTaggedPointer_noPermute_withObfuscator(ptr, objc_debug_taggedpointer_obfuscator);
}

static inline uintptr_t
_objc_decodeTaggedPointer(const void *ptr)
{
    return _objc_decodeTaggedPointer_withObfuscator(ptr, objc_debug_taggedpointer_obfuscator);
}

static inline bool
_objc_taggedPointersEnabled(void)
{
    extern uintptr_t objc_debug_taggedpointer_mask;
    return (objc_debug_taggedpointer_mask != 0);
}

__attribute__((no_sanitize("unsigned-shift-base")))
static inline void *
_objc_makeTaggedPointer_withObfuscator(objc_tag_index_t tag, uintptr_t value,
                                       uintptr_t obfuscator)
{
    // PAYLOAD_LSHIFT and PAYLOAD_RSHIFT are the payload extraction shifts.
    // They are reversed here for payload insertion.

    // ASSERT(_objc_taggedPointersEnabled());
    if (tag <= OBJC_TAG_Last60BitPayload) {
        // ASSERT(((value << _OBJC_TAG_PAYLOAD_RSHIFT) >> _OBJC_TAG_PAYLOAD_LSHIFT) == value);
        uintptr_t result =
        (_OBJC_TAG_MASK |
         ((uintptr_t)tag << _OBJC_TAG_INDEX_SHIFT) |
         ((value << _OBJC_TAG_PAYLOAD_RSHIFT) >> _OBJC_TAG_PAYLOAD_LSHIFT));
        return _objc_encodeTaggedPointer_withObfuscator(result, obfuscator);
    } else {
        // ASSERT(tag >= OBJC_TAG_First52BitPayload);
        // ASSERT(tag <= OBJC_TAG_Last52BitPayload);
        // ASSERT(((value << _OBJC_TAG_EXT_PAYLOAD_RSHIFT) >> _OBJC_TAG_EXT_PAYLOAD_LSHIFT) == value);
        uintptr_t result =
        (_OBJC_TAG_EXT_MASK |
         ((uintptr_t)(tag - OBJC_TAG_First52BitPayload) << _OBJC_TAG_EXT_INDEX_SHIFT) |
         ((value << _OBJC_TAG_EXT_PAYLOAD_RSHIFT) >> _OBJC_TAG_EXT_PAYLOAD_LSHIFT));
        return _objc_encodeTaggedPointer_withObfuscator(result, obfuscator);
    }
}

static inline void *
_objc_makeTaggedPointer(objc_tag_index_t tag, uintptr_t value)
{
    return _objc_makeTaggedPointer_withObfuscator(tag, value, objc_debug_taggedpointer_obfuscator);
}

static inline bool
_objc_isTaggedPointer(const void *ptr)
{
    return ((uintptr_t)ptr & _OBJC_TAG_MASK) == _OBJC_TAG_MASK;
}

static inline bool
_objc_isTaggedPointerOrNil(const void *ptr)
{
    // this function is here so that clang can turn this into
    // a comparison with NULL when this is appropriate
    // it turns out it's not able to in many cases without this
    return !ptr || ((uintptr_t)ptr & _OBJC_TAG_MASK) == _OBJC_TAG_MASK;
}

static inline objc_tag_index_t
_objc_getTaggedPointerTag_withObfuscator(const void *ptr,
                                         uintptr_t obfuscator)
{
    // ASSERT(_objc_isTaggedPointer(ptr));
    uintptr_t value = _objc_decodeTaggedPointer_withObfuscator(ptr, obfuscator);
    uintptr_t basicTag = (value >> _OBJC_TAG_INDEX_SHIFT) & _OBJC_TAG_INDEX_MASK;
    uintptr_t extTag =   (value >> _OBJC_TAG_EXT_INDEX_SHIFT) & _OBJC_TAG_EXT_INDEX_MASK;
    if (basicTag == _OBJC_TAG_INDEX_MASK) {
        return (objc_tag_index_t)(extTag + OBJC_TAG_First52BitPayload);
    } else {
        return (objc_tag_index_t)basicTag;
    }
}

__attribute__((no_sanitize("unsigned-shift-base")))
static inline uintptr_t
_objc_getTaggedPointerValue_withObfuscator(const void *ptr,
                                           uintptr_t obfuscator)
{
    // ASSERT(_objc_isTaggedPointer(ptr));
    uintptr_t value = _objc_decodeTaggedPointer_noPermute_withObfuscator(ptr, obfuscator);
    uintptr_t basicTag = (value >> _OBJC_TAG_INDEX_SHIFT) & _OBJC_TAG_INDEX_MASK;
    if (basicTag == _OBJC_TAG_INDEX_MASK) {
        return (value << _OBJC_TAG_EXT_PAYLOAD_LSHIFT) >> _OBJC_TAG_EXT_PAYLOAD_RSHIFT;
    } else {
        return (value << _OBJC_TAG_PAYLOAD_LSHIFT) >> _OBJC_TAG_PAYLOAD_RSHIFT;
    }
}

__attribute__((no_sanitize("unsigned-shift-base")))
static inline intptr_t
_objc_getTaggedPointerSignedValue_withObfuscator(const void *ptr,
                                                 uintptr_t obfuscator)
{
    // ASSERT(_objc_isTaggedPointer(ptr));
    uintptr_t value = _objc_decodeTaggedPointer_noPermute_withObfuscator(ptr, obfuscator);
    uintptr_t basicTag = (value >> _OBJC_TAG_INDEX_SHIFT) & _OBJC_TAG_INDEX_MASK;
    if (basicTag == _OBJC_TAG_INDEX_MASK) {
        return ((intptr_t)value << _OBJC_TAG_EXT_PAYLOAD_LSHIFT) >> _OBJC_TAG_EXT_PAYLOAD_RSHIFT;
    } else {
        return ((intptr_t)value << _OBJC_TAG_PAYLOAD_LSHIFT) >> _OBJC_TAG_PAYLOAD_RSHIFT;
    }
}

static inline objc_tag_index_t
_objc_getTaggedPointerTag(const void *ptr)
{
    return _objc_getTaggedPointerTag_withObfuscator(ptr, objc_debug_taggedpointer_obfuscator);
}

static inline uintptr_t
_objc_getTaggedPointerValue(const void *ptr)
{
    return _objc_getTaggedPointerValue_withObfuscator(ptr, objc_debug_taggedpointer_obfuscator);
}

static inline intptr_t
_objc_getTaggedPointerSignedValue(const void *ptr)
{
    return _objc_getTaggedPointerSignedValue_withObfuscator(ptr, objc_debug_taggedpointer_obfuscator);
}

static inline bool 
ksc_objc_splitTaggedPointersEnabled(void)
{
#if OBJC_SPLIT_TAGGED_POINTERS
    return objc_debug_tag60_permutations != NULL;
#else
    return false;
#endif
}

#   if OBJC_SPLIT_TAGGED_POINTERS
static inline void *
_objc_getTaggedPointerRawPointerValue(const void *ptr) {
    return (void *)((uintptr_t)ptr & _OBJC_TAG_CONSTANT_POINTER_MASK);
}
#   endif

#else

// Just check for nil when we don't support tagged pointers.
static inline bool
_objc_isTaggedPointerOrNil(const void *ptr)
{
    return !ptr;
}

// OBJC_HAVE_TAGGED_POINTERS
#endif

// ======================================================================
#pragma mark - objc4-680/runtime/objc-os.h -
// ======================================================================

#ifdef __LP64__
#   define WORD_SHIFT 3UL
#   define WORD_MASK 7UL
#   define WORD_BITS 64
#   define FAST_DATA_MASK          0x00007ffffffffff8UL
#else
#   define WORD_SHIFT 2UL
#   define WORD_MASK 3UL
#   define WORD_BITS 32
#   define FAST_DATA_MASK        0xfffffffcUL
#endif



// ======================================================================
#pragma mark - objc4-680/runtime/runtime.h -
// ======================================================================
    
typedef struct objc_cache *Cache;


// ======================================================================
#pragma mark - objc4-680/runtime/objc-runtime-new.h -
// ======================================================================

typedef struct method_t {
    SEL name;
    const char *types;
    IMP imp;
} method_t;

MAKE_LIST_T(method);

typedef struct ivar_t {
#if __x86_64__
    // *offset was originally 64-bit on some x86_64 platforms.
    // We read and write only 32 bits of it.
    // Some metadata provides all 64 bits. This is harmless for unsigned
    // little-endian values.
    // Some code uses all 64 bits. class_addIvar() over-allocates the
    // offset for their benefit.
#endif
    int32_t *offset;
    const char *name;
    const char *type;
    // alignment is sometimes -1; use alignment() instead
    uint32_t alignment_raw;
    uint32_t size;
} ivar_t;

MAKE_LIST_T(ivar);

typedef struct property_t {
    const char *name;
    const char *attributes;
} property_t;

MAKE_LIST_T(property);

typedef struct OBJC_OBJECT(protocol_t)
    const char *mangledName;
    struct protocol_list_t *protocols;
    method_list_t *instanceMethods;
    method_list_t *classMethods;
    method_list_t *optionalInstanceMethods;
    method_list_t *optionalClassMethods;
    property_list_t *instanceProperties;
    uint32_t size;   // sizeof(protocol_t)
    uint32_t flags;
    // Fields below this point are not always present on disk.
    const char **extendedMethodTypes;
    const char *_demangledName;
} protocol_t;

MAKE_LIST_T(protocol);

// Values for class_ro_t->flags
// These are emitted by the compiler and are part of the ABI.
// class is a metaclass
#define RO_META               (1<<0)
// class is a root class
#define RO_ROOT               (1<<1)

typedef struct class_ro_t {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
#ifdef __LP64__
    uint32_t reserved;
#endif
    
    const uint8_t * ivarLayout;
    
    const char * name;
    method_list_t * baseMethodList;
    protocol_list_t * baseProtocols;
    const ivar_list_t * ivars;
    
    const uint8_t * weakIvarLayout;
    property_list_t *baseProperties;
} class_ro_t;

struct class_rw_ext_t {
    const class_ro_t *ro;
    method_array_t methods;
    property_array_t properties;
    protocol_array_t protocols;
    char *demangledName;
    uint32_t version;
};

typedef struct class_rw_t {
    uint32_t flags;
    uint16_t witness;
#if SUPPORT_INDEXED_ISA
    uint16_t index;
#endif
    
    uintptr_t ro_or_rw_ext;
    Class firstSubclass;
    Class nextSiblingClass;

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
#pragma mark - CF-1153.18/CFRuntime.h -
// ======================================================================

typedef struct __CFRuntimeBase {
    uintptr_t _cfisa;
    uint8_t _cfinfo[4];
#if __LP64__
    uint32_t _rc;
#endif
} CFRuntimeBase;


// ======================================================================
#pragma mark - CF-1153.18/CFInternal.h -
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
#pragma mark - CF-1153.18/CFString.c -
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
CF_INLINE Boolean __CFStrFreeContentsWhenDone(CFStringRef str)      {return (str->base._cfinfo[CF_INFO_BITS] & __kCFFreeContentsWhenDoneMask) == __kCFFreeContentsWhenDone;}
CF_INLINE Boolean __CFStrHasContentsDeallocator(CFStringRef str)    {return (str->base._cfinfo[CF_INFO_BITS] & __kCFHasContentsDeallocatorMask) == __kCFHasContentsDeallocator;}
CF_INLINE Boolean __CFStrIsUnicode(CFStringRef str)                 {return (str->base._cfinfo[CF_INFO_BITS] & __kCFIsUnicodeMask) == __kCFIsUnicode;}
CF_INLINE Boolean __CFStrIsEightBit(CFStringRef str)                {return (str->base._cfinfo[CF_INFO_BITS] & __kCFIsUnicodeMask) != __kCFIsUnicode;}
CF_INLINE Boolean __CFStrHasNullByte(CFStringRef str)               {return (str->base._cfinfo[CF_INFO_BITS] & __kCFHasNullByteMask) == __kCFHasNullByte;}
CF_INLINE Boolean __CFStrHasLengthByte(CFStringRef str)             {return (str->base._cfinfo[CF_INFO_BITS] & __kCFHasLengthByteMask) == __kCFHasLengthByte;}
CF_INLINE Boolean __CFStrHasExplicitLength(CFStringRef str)         {return (str->base._cfinfo[CF_INFO_BITS] & (__kCFIsMutableMask | __kCFHasLengthByteMask)) != __kCFHasLengthByte;}	// Has explicit length if (1) mutable or (2) not mutable and no length byte
CF_INLINE Boolean __CFStrIsConstant(CFStringRef str) {
#if __LP64__
    return str->base._rc == 0;
#else
    return (str->base._cfinfo[CF_RC_BITS]) == 0;
#endif
}

/* Returns ptr to the buffer (which might include the length byte).
 */
CF_INLINE const void *__CFStrContents(CFStringRef str) {
    if (__CFStrIsInline(str)) {
        return (const void *)(((uintptr_t)&(str->variants)) + (__CFStrHasExplicitLength(str) ? sizeof(CFIndex) : 0));
    } else {	// Not inline; pointer is always word 2
        return str->variants.notInlineImmutable1.buffer;
    }
}


// ======================================================================
#pragma mark - CF-1153.18/CFURL.c -
// ======================================================================

struct __CFURL {
    CFRuntimeBase _cfBase;
    UInt32 _flags;
    CFStringEncoding _encoding; // The encoding to use when asked to remove percent escapes
    CFStringRef _string; // Never NULL
    CFURLRef _base;
    struct _CFURLAdditionalData* _extra;
    void *_resourceInfo;    // For use by CoreServicesInternal to cache property values. Retained and released by CFURL.
    CFRange _ranges[1]; // variable length (1 to 9) array of ranges
};


// ======================================================================
#pragma mark - CF-1153.18/CFDate.c -
// ======================================================================

struct __CFDate {
    // According to CFDate.c the structure is a CFRuntimeBase followed
    // by the time. In fact, it's only an isa pointer followed by the time.
    //struct CFRuntimeBase _base;
    uintptr_t _cfisa;
    CFAbsoluteTime _time;       /* immutable */
};


// ======================================================================
#pragma mark - CF-1153.18/CFNumber.c -
// ======================================================================

struct __CFNumber {
    CFRuntimeBase _base;
    uint64_t _pad; // need this space here for the constant objects
    /* 0 or 8 more bytes allocated here */
};


// ======================================================================
#pragma mark - CF-1153.18/CFArray.c -
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
    /* __strong */ void *_store;           /* can be NULL when MutableDeque */
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
    if (__CFBitfieldGetValue((unsigned long)t, 3, 2) == __kCFArrayHasCustomCallBacks) {
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
#pragma mark - CF-1153.18/CFBasicHash.h -
// ======================================================================

typedef struct __CFBasicHash *CFBasicHashRef;
typedef const struct __CFBasicHash *CFConstBasicHashRef;

typedef struct __CFBasicHashCallbacks CFBasicHashCallbacks;

struct __CFBasicHashCallbacks {
    uintptr_t (*retainValue)(CFAllocatorRef alloc, uintptr_t stack_value);	// Return 2nd arg or new value
    uintptr_t (*retainKey)(CFAllocatorRef alloc, uintptr_t stack_key);	// Return 2nd arg or new key
    void (*releaseValue)(CFAllocatorRef alloc, uintptr_t stack_value);
    void (*releaseKey)(CFAllocatorRef alloc, uintptr_t stack_key);
    Boolean (*equateValues)(uintptr_t coll_value1, uintptr_t stack_value2); // 1st arg is in-collection value, 2nd arg is probe parameter OR in-collection value for a second collection
    Boolean (*equateKeys)(uintptr_t coll_key1, uintptr_t stack_key2); // 1st arg is in-collection key, 2nd arg is probe parameter
    CFHashCode (*hashKey)(uintptr_t stack_key);
    uintptr_t (*getIndirectKey)(uintptr_t coll_value);	// Return key; 1st arg is in-collection value
    CFStringRef (*copyValueDescription)(uintptr_t stack_value);
    CFStringRef (*copyKeyDescription)(uintptr_t stack_key);
};


// ======================================================================
#pragma mark - CF-1153.18/CFBasicHash.c -
// ======================================================================

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

typedef union {
    uintptr_t neutral;
    void* Xstrong; // Changed from type 'id'
    void* Xweak; // Changed from type 'id'
} CFBasicHashValue;

struct __CFBasicHash {
    CFRuntimeBase base;
    struct { // 192 bits
        uint16_t mutations;
        uint8_t hash_style:2;
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
        uint32_t used_buckets;      /* number of used buckets */
        uint64_t deleted:16;
        uint64_t num_buckets_idx:8; /* index to number of buckets */
        uint64_t __kret:10;
        uint64_t __vret:10;
        uint64_t __krel:10;
        uint64_t __vrel:10;
        uint64_t __:1;
        uint64_t null_rc:1;
        uint64_t fast_grow:1;
        uint64_t finalized:1;
        uint64_t __kdes:10;
        uint64_t __vdes:10;
        uint64_t __kequ:10;
        uint64_t __vequ:10;
        uint64_t __khas:10;
        uint64_t __kget:10;
    } bits;
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


#ifdef __cplusplus
}
#endif

#endif // HDR_KSObjCApple_h
