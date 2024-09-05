//
//  KSTestModuleConfig.h
//
//
//  Created by Alexander Cohen on 5/9/24.
//

#ifndef KSTestModuleConfig_h
#define KSTestModuleConfig_h

#import <XCTest/XCTest.h>

#if !defined(KS_TEST_MODULE_BUNDLE)
#ifdef SWIFTPM_MODULE_BUNDLE
#define KS_TEST_MODULE_BUNDLE SWIFTPM_MODULE_BUNDLE
#else
#define KS_TEST_MODULE_BUNDLE ([NSBundle bundleForClass:[self class]])
#endif
#endif

#endif  // KSTestModuleConfig_h
