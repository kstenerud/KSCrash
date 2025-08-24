# GitHub Copilot Code Review Instructions for KSCrash

When performing code reviews on this repository, follow these instructions to identify API breaking changes in the KSCrash crash reporting library.

## Scope of Review

Only review changes to public API surfaces. The public modules are: KSCrashRecording, KSCrashFilters, KSCrashSinks, KSCrashInstallations, KSCrashDiscSpaceMonitor, KSCrashBootTimeMonitor, and KSCrashDemangleFilter. Only examine files in `Sources/[ModuleName]/include/*.h` directories as these contain the public headers.

## Critical Breaking Changes - Always Flag

### Method Parameter Changes
Flag ANY parameter addition, removal, or type changes to existing Objective-C methods. Objective-C has no default parameters, so even adding a nullable parameter breaks all existing call sites.

Examples of breaking changes:
```objc
// BREAKING: Adding parameter
- (void)method:(NSString *)existing;                                     // Old
- (void)method:(NSString *)existing newParam:(nullable NSString *)param; // New - BREAKING

// BREAKING: Parameter removal  
- (void)method:(NSString *)param1 param2:(NSString *)param2;    // Old
- (void)method:(NSString *)param1;                              // New - BREAKING

// BREAKING: Parameter type changes
- (void)method:(NSString *)param;    // Old
- (void)method:(NSArray *)param;     // New - BREAKING

// BREAKING: Parameter reordering
- (void)method:(NSString *)first second:(NSString *)second;    // Old
- (void)method:(NSString *)second first:(NSString *)first;     // New - BREAKING
```

### Callback Signature Changes
Flag any changes to callback or function pointer signatures including parameter addition, removal, reordering, or return type changes.

Examples of breaking changes:
```c
// BREAKING: Parameter addition
typedef void (*SomeCallback)(Writer *writer);                   // Old
typedef void (*SomeCallback)(Policy policy, Writer *writer);    // New - BREAKING

// BREAKING: Return type changes
typedef void (*SomeCallback)(Context *ctx);      // Old
typedef Policy (*SomeCallback)(Context *ctx);    // New - BREAKING
```

### Property Changes
Flag any property type changes or nullability changes in either direction.

Examples of breaking changes:
```objc
// BREAKING: Property type changes
@property (nonatomic, strong) NSString *prop;    // Old
@property (nonatomic, strong) NSArray *prop;     // New - BREAKING

// BREAKING: Nullability changes (both directions)
@property (nullable) NSString *prop;    // Old
@property (nonnull) NSString *prop;     // New - BREAKING (breaks code passing nil)

@property (nonnull) NSString *prop;     // Old
@property (nullable) NSString *prop;    // New - BREAKING (Swift API: String → String?)

// BREAKING: Property attribute changes
@property (atomic) id prop;       // Old
@property (nonatomic) id prop;    // New - BREAKING (ABI change)
```

### Swift API Changes via NS_SWIFT_NAME
Flag any addition, modification, or removal of NS_SWIFT_NAME attributes on existing types or methods.

Examples of breaking changes:
```objc
// BREAKING: Adding NS_SWIFT_NAME to existing type
@interface ExistingClass : NSObject                              // Old
@interface ExistingClass : NSObject NS_SWIFT_NAME(SwiftName)     // New - BREAKING

// BREAKING: Changing existing NS_SWIFT_NAME
NS_SWIFT_NAME(OldName) @interface MyClass : NSObject     // Old
NS_SWIFT_NAME(NewName) @interface MyClass : NSObject     // New - BREAKING

// BREAKING: Removing NS_SWIFT_NAME
NS_SWIFT_NAME(SwiftName) @interface MyClass : NSObject    // Old
@interface MyClass : NSObject                             // New - BREAKING

// BREAKING: Changing Swift parameter names
- (void)method:(NSString *)param NS_SWIFT_NAME(method(value:));    // Old
- (void)method:(NSString *)param NS_SWIFT_NAME(method(input:));    // New - BREAKING
```

### Struct and Enum Changes
Flag any struct or enum field reordering, removal, or type changes as these break binary compatibility.

Examples of breaking changes:
```c
// BREAKING: Field reordering
typedef struct {    // Old
    int field1;
    int field2;
} PublicStruct;

typedef struct {    // New - BREAKING
    int field2;     // Reordered!
    int field1;
} PublicStruct;

// BREAKING: Field type changes
typedef struct {
    int field;      // Old
} PublicStruct;

typedef struct {
    float field;    // New - BREAKING
} PublicStruct;

// BREAKING: Enum value changes
typedef enum {      // Old
    Value1 = 0,
    Value2 = 1,
} PublicEnum;

typedef enum {      // New - BREAKING
    Value1 = 1,     // Changed value!
    Value2 = 0,
} PublicEnum;
```

### Protocol Requirement Changes
Flag changes between required and optional protocol methods.

Examples of breaking changes:
```objc
// BREAKING: Adding required methods
@protocol PublicProtocol         // Old
- (void)existingMethod;
@end

@protocol PublicProtocol         // New - BREAKING
- (void)existingMethod;
- (void)newRequiredMethod;       // Added required method
@end

// BREAKING: Making optional methods required
@protocol PublicProtocol         // Old
- (void)existingMethod;
@optional
- (void)method;
@end

@protocol PublicProtocol         // New - BREAKING
- (void)existingMethod;
- (void)method;                  // Now required!
@end
```

### Function Signature Changes
Flag any C function parameter or return type changes.

Examples of breaking changes:
```c
// BREAKING: Parameter changes
void someFunction(int param);                    // Old
void someFunction(int param, char *newParam);    // New - BREAKING

// BREAKING: Return type changes
void someFunction(void);    // Old
int someFunction(void);     // New - BREAKING
```

### Class Hierarchy Changes
Flag any superclass changes for existing classes.

Examples of breaking changes:
```objc
// BREAKING: Changing superclass
@interface MyClass : NSObject    // Old
@interface MyClass : NSView      // New - BREAKING (changes inheritance)
```

### Private Module Leaks
Flag any private module types appearing in public headers.

Examples of breaking changes:
```objc
// BREAKING: Private types in public API
#import "KSCrashRecordingCore/SomePrivateType.h"  // FLAG if used in public headers
@property (nonatomic) KSCrash_InternalStruct *detail;  // FLAG if Internal type is private
```

## Safe Changes - Don't Flag

### Deprecation
Adding deprecation attributes is safe:
```objc
// SAFE: Deprecation warnings don't break compilation
@property (deprecated("Use newProperty instead")) id oldProperty;
@property id newProperty;
```

### New APIs with New Names
Adding completely new methods, properties, or classes is safe:
```objc
// SAFE: New methods with different names
- (void)existingMethod:(NSString *)param;
- (void)brandNewMethod:(NSString *)param;  // Different selector

// SAFE: New properties and classes
@property (nonatomic) id brandNewProperty;
@interface CompletelyNewClass : NSObject
```

### NS_SWIFT_NAME on New APIs
Adding NS_SWIFT_NAME to brand new APIs is safe:
```objc
// SAFE: NS_SWIFT_NAME on new APIs only
NS_SWIFT_NAME(NewSwiftAPI) @interface BrandNewClass : NSObject
```

### Optional Protocol Methods
Adding optional methods to protocols is safe:
```objc
// SAFE: Adding optional methods
@protocol ExistingProtocol
- (void)existing;
@optional
- (void)newOptionalMethod;
@end
```

## Review Process

For each PR, examine modified public headers and flag any of the breaking change patterns above. Ask yourself: Would existing user code fail to compile after this change? If yes, it's breaking. The KSCrash library prioritizes API stability, so breaking changes need strong justification and migration guidance.

Pay special attention to callback API changes as this library has a history of major callback signature evolution for async-safety and policy awareness.
