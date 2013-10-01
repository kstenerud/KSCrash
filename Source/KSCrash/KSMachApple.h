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


// ======================================================================
#pragma mark - Libc-763.11/pthreads/pthread_internals.h -
// ======================================================================

#define kEXTERNAL_POSIX_THREAD_KEYS_MAX 512
#define kINTERNAL_POSIX_THREAD_KEYS_MAX 256
#define MAXTHREADNAMESIZE	64

#define kTSD_KEY_COUNT (kEXTERNAL_POSIX_THREAD_KEYS_MAX + \
kINTERNAL_POSIX_THREAD_KEYS_MAX)

#define	TRACEBUF

#define	TAILQ_ENTRY(type)						\
struct {								\
    struct type *tqe_next;	/* next element */			\
    struct type **tqe_prev;	/* address of previous next element */	\
    TRACEBUF							\
}

typedef struct internal_pthread
{
    long        sig;           /* Unique signature for this structure */
    struct __darwin_pthread_handler_rec* __cleanup_stack;
    int lock;                  /* Used for internal mutex on structure (actually pthread_lock_t) */
    uint32_t    detached:8,
                inherit:8,
                policy:8,
                freeStackOnExit:1,
                newstyle:1,
                kernalloc:1,
                schedset:1,
                wqthread:1,
                wqkillset:1,
                pad:2;
    size_t      guardsize;     /* size in bytes to guard stack overflow */
#if  !defined(__LP64__)
    int         pad0;          /* for backwards compatibility */
#endif
    struct sched_param param;
    uint32_t    cancel_error;
#if defined(__LP64__)
    uint32_t    cancel_pad;    /* pad value for alignment */
#endif
    struct _pthread* joiner;
#if !defined(__LP64__)
    int         pad1;          /* for backwards compatibility */
#endif
    void*       exit_value;
    semaphore_t death;         /* pthread_join() uses this to wait for death's call */
    mach_port_t kernel_thread; /* kernel thread this thread is bound to */
    void*       (*fun)(void*); /* Thread start routine */
    void*       arg;           /* Argment for thread start routine */
    int         cancel_state;  /* Whether thread can be cancelled */
    int         err_no;        /* thread-local errno */
    void*       tsd[kTSD_KEY_COUNT]; /* Thread specific data */
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
	TAILQ_ENTRY(internal_pthread) plist;
	void *	freeaddr;
	size_t	freesize;
	mach_port_t	joiner_notify;
	char	pthread_name[MAXTHREADNAMESIZE];		/* including nulll the name */
    int	max_tsd_key;
	void *	cur_workq;
	void * cur_workitem;
	uint64_t thread_id;
}* internal_pthread_t;


// ======================================================================
#pragma mark - Libc-763.11/pthreads/pthread_machdep.h -
// ======================================================================
#define __PTK_LIBDISPATCH_KEY0		20


// ======================================================================
#pragma mark - libdispatch-187.5/src/shims/tsd.h -
// ======================================================================
static const unsigned long dispatch_queue_key		= __PTK_LIBDISPATCH_KEY0;


// ======================================================================
#pragma mark - libdispatch-187.5/src/queue_internal.h -
// ======================================================================
#define kDISPATCH_QUEUE_MIN_LABEL_SIZE 64

typedef struct internal_dispatch_queue_s
{
    // DISPATCH_STRUCT_HEADER (object_internal.h)
    const struct dispatch_queue_vtable_s* do_vtable;
    struct dispatch_queue_s* volatile do_next;
    int do_ref_cnt;     // Was unsigned int in queue_internal.h
    int do_xref_cnt;    // Was unsigned int in queue_internal.h
    int do_suspend_cnt; // Was unsigned int in queue_internal.h
    struct dispatch_queue_s* do_targetq;
    void* do_ctxt;
    void* do_finalizer;
    
    // DISPATCH_QUEUE_HEADER
    uint32_t volatile dq_running;
    uint32_t dq_width;
    struct dispatch_queue_s* volatile dq_items_tail;
    struct dispatch_queue_s* volatile dq_items_head;
    unsigned long dq_serialnum;
    dispatch_queue_t dq_specific_q;
    
    char dq_label[kDISPATCH_QUEUE_MIN_LABEL_SIZE]; // must be last
    // char _dq_pad[DISPATCH_QUEUE_CACHELINE_PAD];
}* internal_dispatch_queue_t;

typedef struct internal_dispatch_queue_vtable_s
{
	unsigned long const do_type;
	const char *const do_kind;
	size_t (*const do_debug)(struct dispatch_queue_vtable_s *, char *, size_t);
	struct dispatch_queue_s *(*const do_invoke)(struct dispatch_queue_vtable_s *);
	bool (*const do_probe)(struct dispatch_queue_vtable_s *);
	void (*const do_dispose)(struct dispatch_queue_vtable_s *);
}* internal_dispatch_queue_vtable_t;


#ifdef __cplusplus
}
#endif

#endif // HDR_KSMachApple_h
