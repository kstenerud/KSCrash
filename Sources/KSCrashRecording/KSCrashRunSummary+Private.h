//
//  KSCrashRunSummary+Private.h
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//

#import "KSCrashRunSummary.h"

#import <sys/uio.h>

NS_ASSUME_NONNULL_BEGIN

typedef ssize_t (^KSCrashRunSummaryWritevBlock)(int, const struct iovec *, int);

@interface KSCrashRunSummary ()

- (BOOL)writeJSONToFileDescriptor:(int)fileDescriptor;

/// Test seam for exercising the production vector advancement loop without
/// relying on kernel-specific partial-write behavior.
+ (BOOL)testcode_writeAllVectors:(const struct iovec *)vectors
                           count:(int)count
                  fileDescriptor:(int)fileDescriptor
                     writevBlock:(KSCrashRunSummaryWritevBlock)writevBlock;

@end

NS_ASSUME_NONNULL_END
