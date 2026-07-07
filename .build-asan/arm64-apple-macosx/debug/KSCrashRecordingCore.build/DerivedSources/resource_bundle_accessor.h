#if __OBJC__
#import <Foundation/Foundation.h>

#if __cplusplus
extern "C" {
#endif

NSBundle* KSCrashRecordingCore_SWIFTPM_MODULE_BUNDLE(void);

#define SWIFTPM_MODULE_BUNDLE KSCrashRecordingCore_SWIFTPM_MODULE_BUNDLE()

#if __cplusplus
}
#endif
#endif