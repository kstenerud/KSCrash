//
//  KSObjC.h
//  KSCrash
//
//  Created by Karl Stenerud on 8/30/12.
//
//

#ifndef HDR_KSObjC_h
#define HDR_KSObjC_h

#ifdef __cplusplus
extern "C" {
#endif

    
#include <stdbool.h>

typedef enum
{
    kObjCObjectTypeNone,
    kObjCObjectTypeClass,
    kObjCObjectTypeObject,
} ObjCObjectType;

/** Interpret a pointer as an object or class and attempt to get its class name.
 *
 * @param potentialObject The pointer that may be an object.
 *
 * @return The class name or NULL if not found.
 */
const char* ksobjc_className(void* potentialObject);

/** Get the type of object at the specified pointer.
 *
 * Note: This only checks that the pointers for isa and superclass check out.
 *       You should also call ksobjc_className() to be sure it really is valid.
 *       This method doesn't call it automatically because ksobjc_className()
 *       is potentially expensive.
 *
 * @param potentialClass The pointer to test.
 *
 * @return The kind of object, or kObjCObjectTypeNone if it couldn't be determined.
 */
ObjCObjectType ksobjc_objectType(void* address);

#ifdef __cplusplus
}
#endif

#endif // HDR_KSObjC_h
