//
//  KSObjC.c
//  KSCrash
//
//  Created by Karl Stenerud on 8/30/12.
//
//


#include "KSObjC.h"

#include "KSMach.h"

#include <objc/objc.h>
#include <stdint.h>
#include <sys/types.h>


// From objc4-493.9/runtime/objc-runtime-new.h

typedef struct objc_cache *Cache;

typedef struct class_ro_t {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
#ifdef __LP64__
    uint32_t reserved;
#endif

    const uint8_t * ivarLayout;

    const char * name;
//    const void * baseMethods; // method_list_t*
//    const void * baseProtocols; // protocol_list_t*
//    const void * ivars; // ivar_list_t*
//
//    const uint8_t * weakIvarLayout;
//    const void *baseProperties; // property_list_t*
} class_ro_t;

typedef struct class_rw_t {
    uint32_t flags;
    uint32_t version;

    const class_ro_t *ro;

//    void **methods; // method_list_t**
//    struct chained_property_list *properties;
//    const void ** protocols; // protocol_list_t**
//
//    struct class_t *firstSubclass;
//    struct class_t *nextSiblingClass;
} class_rw_t;

typedef struct class_t {
    struct class_t *isa;
    struct class_t *superclass;
    Cache cache;
    void *vtable; // IMP*
    class_rw_t *data;
} class_t;

static inline bool isValidClassNameStartChar(char ch)
{
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_';
}

static inline bool isValidClassNameChar(char ch)
{
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_';
}

ObjCObjectType ksobjc_objectType(void* self)
{
    /*
     How to determine if it's a class or object.
     
     Root object/class:
     - class: self->isa->superclass == self
     - object: self->isa->superclass == nil

     Non-root object/class:
     - class: self->isa->isa->isa == self->isa->isa
     - object: self->isa->isa->isa->isa == self->isa->isa->isa
     */

    class_t* pIsa;
    class_t cls;

    if(self == NULL)
    {
        return kObjCObjectTypeNone;
    }

    // Get the object/class isa pointer
    if(ksmach_copyMem(self, &pIsa, sizeof(pIsa)) != KERN_SUCCESS)
    {
        return kObjCObjectTypeNone;
    }

    // Copy the class contents
    if(ksmach_copyMem(pIsa, &cls, sizeof(cls)) != KERN_SUCCESS)
    {
        return kObjCObjectTypeNone;
    }

    // Simple case: Root object or class.
    if(cls.superclass == NULL)
    {
        return kObjCObjectTypeObject;
    }
    if(cls.superclass == self)
    {
        return kObjCObjectTypeClass;
    }

    // One more isa before loop = class
    pIsa = cls.isa;
    if(ksmach_copyMem(pIsa, &cls, sizeof(cls)) != KERN_SUCCESS)
    {
        return kObjCObjectTypeNone;
    }
    if(cls.isa == pIsa)
    {
        return kObjCObjectTypeClass;
    }

    // Two more isa before loop = object
    pIsa = cls.isa;
    if(ksmach_copyMem(pIsa, &cls, sizeof(cls)) != KERN_SUCCESS)
    {
        return kObjCObjectTypeNone;
    }
    if(cls.isa == pIsa)
    {
        return kObjCObjectTypeObject;
    }

    // Don't know what this is
    return kObjCObjectTypeNone;
}

const char* ksobjc_className(void* address)
{
    ObjCObjectType objectType = ksobjc_objectType(address);
    class_t* pIsa = address;
    class_t cls;
    class_rw_t rw;
    class_ro_t ro;
    char name[128];

    if(objectType == kObjCObjectTypeNone)
    {
        return NULL;
    }

    if(objectType == kObjCObjectTypeObject)
    {
        // Copy the object's isa pointer
        if(ksmach_copyMem(pIsa, &pIsa, sizeof(pIsa)) != KERN_SUCCESS)
        {
            return NULL;
        }
    }

    // We're now guaranteed that pClass points to a class.

    if(ksmach_copyMem(pIsa, &cls, sizeof(cls)) != KERN_SUCCESS)
    {
        return NULL;
    }
    if(ksmach_copyMem(cls.data, &rw, sizeof(rw)) != KERN_SUCCESS)
    {
        return NULL;
    }
    if(ksmach_copyMem(rw.ro, &ro, sizeof(ro)) != KERN_SUCCESS)
    {
        return NULL;
    }
    size_t nameLength = ksmach_copyMaxPossibleMem(ro.name, name, sizeof(name));
    if(ro.name + nameLength < ro.name)
    {
        // Wrapped around address space.
        return NULL;
    }
    if(nameLength == 0 || !isValidClassNameStartChar(*name))
    {
        return NULL;
    }
    for(size_t i = 0; i < nameLength; i++)
    {
        if(!isValidClassNameChar(name[i]))
        {
            if(name[i] == 0)
            {
                return ro.name;
            }
            return NULL;
        }
    }
    return NULL;
}
