//
//  KSCrashLifecycleHandler.mm
//
//  Created by Alexander Cohen on 2024-05-20.
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
#import "KSSystemCapabilities.h"

/**
 * If we can, we try and swizzle App and Scene delegates.
 *
 * Lifecycle delegate and notifications happen at different times,
 * here's what it looks like:
 *
 * run loop cycle 1: Application -> Delegate
 * run loop cycle 2: Application -> Notification
 *
 * Due to this, it's very hard for a system to receive lifecycle
 * events before the app it is being installed in. This can lead
 * to mismatched user perception (foreground when the app is actually
 * background). That mismatch leads to wrongly categorizing
 * issues reported by the system.
 *
 * To fix this, we need to swizzle app an scene delegates. This allows
 * us to receive delegate callbacks before anyone else and correctly
 * record the state of the app before the app has a chance to run any
 * code in those transitions and possibly cause a reliability event.
 *
 *
 */
// We need to have UIApplication to do any of this.
#if KSCRASH_HAS_UIAPPLICATION

#import "KSCrashAppStateTracker+Private.h"

#import <objc/runtime.h>
#import <map>
#import <string>

#import <UIKit/UIKit.h>

@interface __KS_CALLING_DELEGATE_TEMPLATE__ : NSObject <UIApplicationDelegate>
@end

#define UISCENE_AVAILABLE API_AVAILABLE(ios(13.0))

UISCENE_AVAILABLE
@interface UIScene (__KS_CALLING_DELEGATE_TEMPLATE__)
- (void)__ks_proxyDelegate;
@end

@interface UIApplication (__KS_CALLING_DELEGATE_TEMPLATE__)
- (void)__ks_setDelegate:(id<UIApplicationDelegate>)delegate;
@end

UISCENE_AVAILABLE
@interface __KS_CALLING_DELEGATE_TEMPLATE__ () <UISceneDelegate>
@end

@implementation __KS_CALLING_DELEGATE_TEMPLATE__

static BOOL SwizzleInstanceMethod(Class klass, SEL originalSelector, SEL swizzledSelector)
{
    Method original = class_getInstanceMethod(klass, originalSelector);
    Method swizzled = class_getInstanceMethod(klass, swizzledSelector);
    
    if (!original || !swizzled) {
        return NO;
    }
    
    method_exchangeImplementations(original, swizzled);
    return YES;
}

typedef BOOL (*ApplicationDelegate_TwoArgs)(id, SEL, id, id);
typedef void (*ApplicationDelegate_OneArg)(id, SEL, id);

static std::map<std::string, Method> gMappings = {};

static void __KS_CALLING_DELEGATE__(id self, SEL cmd, id arg)
{
    std::string name(sel_getName(cmd));
    NSLog(@"[MAP] %s", name.c_str());
    const auto it = gMappings.find(name);
    if (it != gMappings.end()) {
        NSLog(@"[MAP:implemented] %s", name.c_str());
        ApplicationDelegate_OneArg imp = (ApplicationDelegate_OneArg)method_getImplementation(it->second);
        imp(self, cmd, arg);
    }
}

static BOOL __KS_CALLING_DELEGATE__(id self, SEL cmd, id arg1, id arg2)
{
    std::string name(sel_getName(cmd));
    NSLog(@"[MAP] %s", name.c_str());
    const auto it = gMappings.find(name);
    if (it != gMappings.end()) {
        NSLog(@"[MAP:implemented] %s", name.c_str());
        ApplicationDelegate_TwoArgs imp = (ApplicationDelegate_TwoArgs)method_getImplementation(it->second);
        return imp(self, cmd, arg1, arg2);
    }
    return YES;
}

+ (void)load
{
    static BOOL sDontSwizzle = [NSProcessInfo.processInfo.environment[@"KSCRASH_APP_SCENE_DELEGATE_SWIZZLE_DISABLED"] boolValue];
    if (sDontSwizzle) {
        return;
    }
#if KSCRASH_HAS_UIAPPLICATION
    SwizzleInstanceMethod(UIApplication.class, @selector(setDelegate:), @selector(__ks_setDelegate:));
    
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UISceneWillConnectNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification * _Nonnull notification) {
            UIScene *scene = notification.object;
            [scene __ks_proxyDelegate];
        }];
    }
#endif
}

#pragma - app delegate

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(nullable NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateLaunching];
    return __KS_CALLING_DELEGATE__(self, _cmd, application, launchOptions);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(nullable NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateLaunched];
    return __KS_CALLING_DELEGATE__(self, _cmd, application, launchOptions);
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateActive];
    __KS_CALLING_DELEGATE__(self, _cmd, application);
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateDeactivating];
    __KS_CALLING_DELEGATE__(self, _cmd, application);
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateBackground];
    __KS_CALLING_DELEGATE__(self, _cmd, application);
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateForegrounding];
    __KS_CALLING_DELEGATE__(self, _cmd, application);
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateTerminating];
    __KS_CALLING_DELEGATE__(self, _cmd, application);
}

#pragma - scene delegate

- (void)sceneWillEnterForeground:(UIScene *)scene UISCENE_AVAILABLE
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateForegrounding];
    __KS_CALLING_DELEGATE__(self, _cmd, scene);
}

- (void)sceneDidBecomeActive:(UIScene *)scene UISCENE_AVAILABLE
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateActive];
    __KS_CALLING_DELEGATE__(self, _cmd, scene);
}

- (void)sceneWillResignActive:(UIScene *)scene UISCENE_AVAILABLE
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateDeactivating];
    __KS_CALLING_DELEGATE__(self, _cmd, scene);
}

- (void)sceneDidEnterBackground:(UIScene *)scene UISCENE_AVAILABLE
{
    [KSCrashAppStateTracker.shared _setTransitionState:KSCrashAppTransitionStateBackground];
    __KS_CALLING_DELEGATE__(self, _cmd, scene);
}

@end

@interface Proxier : NSObject
@end

@implementation Proxier

+ (void)copyMethodsFromClass:(Class)fromClass toClass:(Class)toClass baseClass:(Class)baseClass
{
    unsigned int count = 0;
    Method *methods = class_copyMethodList(fromClass, &count);
    for (unsigned int i = 0; i < count; i++) {
        
        SEL name = method_getName(methods[i]);
        IMP imp = method_getImplementation(methods[i]);
        const char *type = method_getTypeEncoding(methods[i]);
        
        NSLog(@"Adding %s", sel_getName(name));
        
        Method originalMethod = class_getInstanceMethod(baseClass, name);
        if (originalMethod) {
            gMappings[sel_getName(name)] = originalMethod;
            NSLog(@"-> original exists");
        } else {
            NSLog(@"-> no original");
        }
        
        if (!class_addMethod(toClass, name, imp, type)) {
            NSLog(@"-> Failed to add %s", sel_getName(name));
        }
    }
    free(methods);
}

+ (Class)subclassClass:(Class)klass copyMethodsFromClass:(Class)methodSourceClass
{
    NSString *subclassName = [[[@"__KSCrash__"
                                stringByAppendingString:NSStringFromClass(klass)]
                               stringByAppendingString:@"_"]
                              stringByAppendingString:[NSUUID UUID].UUIDString];
    Class subclass = objc_allocateClassPair(klass, subclassName.UTF8String, 0);
    if (!subclass) {
        return nil;
    }
    
    [Proxier copyMethodsFromClass:methodSourceClass
                          toClass:subclass
                        baseClass:klass];
    
    objc_registerClassPair(subclass);
    
    return subclass;
}

+ (void)proxyObject:(NSObject *)object withMethodsFromClass:(Class)methodSourceClass
{
    Class subclass = [self subclassClass:object.class copyMethodsFromClass:methodSourceClass];
    Class originalClass = object_setClass(object, subclass);
    if (originalClass) {
        NSLog(@"[AC] Swizzled '%@' with '%@'", NSStringFromClass(originalClass), NSStringFromClass(subclass));
    } else {
        NSLog(@"[AC] Swizzled failed");
    }
}

@end

@implementation UIApplication (__KS_CALLING_DELEGATE_TEMPLATE__)

- (void)__ks_setDelegate:(id<UIApplicationDelegate>)delegate
{
    if (delegate) {
        [Proxier proxyObject:delegate withMethodsFromClass:__KS_CALLING_DELEGATE_TEMPLATE__.class];
        KSCrashAppStateTracker.shared.proxied = YES;
    }
    [self __ks_setDelegate:delegate];
}

@end

UISCENE_AVAILABLE
@implementation UIScene (__KS_CALLING_DELEGATE_TEMPLATE__)

- (void)__ks_proxyDelegate
{
    if (self.delegate) {
        [Proxier proxyObject:self.delegate withMethodsFromClass:__KS_CALLING_DELEGATE_TEMPLATE__.class];
        KSCrashAppStateTracker.shared.proxied = YES;
    }
}

@end

#endif
