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


#include <dispatch/dispatch.h>
#include <sched.h>
#include <sys/queue.h>


// Avoid name clashes when copying structs from private headers
#define pthread_t internal_pthread_t
#define dispatch_queue_s internal_dispatch_queue_s


// ======================================================================
#pragma mark - Libc-825.26/pthreads/pthread_machdep.h -
// ======================================================================

typedef int pthread_lock_t;

#define __PTK_LIBDISPATCH_KEY0		20


// ======================================================================
#pragma mark - Libc-825.26/pthreads/pthread_internals.h -
// ======================================================================

#define _EXTERNAL_POSIX_THREAD_KEYS_MAX 512
#define _INTERNAL_POSIX_THREAD_KEYS_MAX 256

#define MAXTHREADNAMESIZE	64

typedef struct _pthread
{
	long	       sig;	      /* Unique signature for this structure */
	struct __darwin_pthread_handler_rec *__cleanup_stack;
	pthread_lock_t lock;	      /* Used for internal mutex on structure */
	uint32_t	detached:8,
                inherit:8,
                policy:8,
                freeStackOnExit:1,
                newstyle:1,
                kernalloc:1,
                schedset:1,
                wqthread:1,
                wqkillset:1,
                pad:2;
	size_t	       guardsize;	/* size in bytes to guard stack overflow */
#if  !defined(__LP64__)
	int	       pad0;		/* for backwards compatibility */
#endif
	struct sched_param param;
	uint32_t	cancel_error;
#if defined(__LP64__)
	uint32_t	cancel_pad;	/* pad value for alignment */
#endif
	struct _pthread *joiner;
#if !defined(__LP64__)
	int		pad1;		/* for backwards compatibility */
#endif
	void           *exit_value;
	semaphore_t    death;		/* pthread_join() uses this to wait for death's call */
	mach_port_t    kernel_thread; /* kernel thread this thread is bound to */
	void	       *(*fun)(void*);/* Thread start routine */
    void	       *arg;	      /* Argment for thread start routine */
	int	       cancel_state;  /* Whether thread can be cancelled */
	int	       err_no;		/* thread-local errno */
	void	       *tsd[_EXTERNAL_POSIX_THREAD_KEYS_MAX + _INTERNAL_POSIX_THREAD_KEYS_MAX];  /* Thread specific data */
    void           *stackaddr;     /* Base of the stack (is aligned on vm_page_size boundary */
    size_t         stacksize;      /* Size of the stack (is a multiple of vm_page_size and >= PTHREAD_STACK_MIN) */
	mach_port_t    reply_port;     /* Cached MiG reply port */
#if defined(__LP64__)
    int		pad2;		/* for natural alignment */
#endif
	void           *cthread_self;  /* cthread_self() if somebody calls cthread_set_self() */
	/* protected by list lock */
	uint32_t 	childrun:1,
                parentcheck:1,
                childexit:1,
                pad3:29;
#if defined(__LP64__)
	int		pad4;		/* for natural alignment */
#endif
	TAILQ_ENTRY(_pthread) plist;
	void *	freeaddr;
	size_t	freesize;
	mach_port_t	joiner_notify;
	char	pthread_name[MAXTHREADNAMESIZE];		/* including nulll the name */
    int	max_tsd_key;
	void *	cur_workq;
	void * cur_workitem;
	uint64_t thread_id;
} *pthread_t;


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


#undef pthread_t
#undef dispatch_queue_s


#ifdef __cplusplus
}
#endif

#endif // HDR_KSMachApple_h
