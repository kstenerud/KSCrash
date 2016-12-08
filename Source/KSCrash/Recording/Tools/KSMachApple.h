//
//  KSMachApple.h
//
//  Created by Karl Stenerud on 2013-01-08.
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
// files, arranged for use in KSMach.

#ifndef HDR_KSMachApple_h
#define HDR_KSMachApple_h

#ifdef __cplusplus
extern "C" {
#endif


#include <sched.h>
#include <sys/queue.h>


// Avoid name clashes when copying structs from private headers
#define dispatch_queue_s internal_dispatch_queue_s


// ======================================================================
#pragma mark - Libc-825.26/pthreads/pthread_machdep.h -
// ======================================================================

typedef int pthread_lock_t;

#define __PTK_LIBDISPATCH_KEY0		20


// ======================================================================
#pragma mark - libdispatch-228.33/src/shims/tsd.h -
// ======================================================================
static const unsigned long dispatch_queue_key		= __PTK_LIBDISPATCH_KEY0;


// ======================================================================
#pragma mark - libdispatch-228.33/src/object_private.h -
// ======================================================================

#define _OS_OBJECT_HEADER(isa, ref_cnt, xref_cnt) \
        isa; /* must be pointer-sized */ \
        int volatile ref_cnt; \
        int volatile xref_cnt


// ======================================================================
#pragma mark - libdispatch-228.33/src/object_internal.h -
// ======================================================================

#define DISPATCH_STRUCT_HEADER(x) \
    _OS_OBJECT_HEADER( \
    const struct dispatch_##x##_vtable_s *do_vtable, \
    do_ref_cnt, \
    do_xref_cnt); \
    struct dispatch_##x##_s *volatile do_next; \
    struct dispatch_queue_s *do_targetq; \
    void *do_ctxt; \
    void *do_finalizer; \
    unsigned int do_suspend_cnt;


// ======================================================================
#pragma mark - libdispatch-228.33/src/queue_internal.h -
// ======================================================================

#define DISPATCH_QUEUE_MIN_LABEL_SIZE 64

#ifdef __LP64__
#define DISPATCH_QUEUE_CACHELINE_PAD (4*sizeof(void*))
#else
#define DISPATCH_QUEUE_CACHELINE_PAD (2*sizeof(void*))
#endif

#define DISPATCH_QUEUE_HEADER \
    uint32_t volatile dq_running; \
    uint32_t dq_width; \
    struct dispatch_object_s *volatile dq_items_tail; \
    struct dispatch_object_s *volatile dq_items_head; \
    unsigned long dq_serialnum; \
    uintptr_t dq_specific_q;


struct dispatch_queue_s {
	DISPATCH_STRUCT_HEADER(queue);
	DISPATCH_QUEUE_HEADER;
	char dq_label[DISPATCH_QUEUE_MIN_LABEL_SIZE]; // must be last
	char _dq_pad[DISPATCH_QUEUE_CACHELINE_PAD]; // for static queues only
};


#undef dispatch_queue_s


#ifdef __cplusplus
}
#endif

#endif // HDR_KSMachApple_h
