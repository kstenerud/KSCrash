//
//  AppDelegate.h
//
//  Created by Karl Stenerud on 2012-03-04.
//

#import <UIKit/UIKit.h>
#import "Crasher.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (retain, nonatomic) UIWindow* window;

@property (retain, nonatomic) UIViewController* viewController;

@property(nonatomic, readwrite, assign) BOOL crashInHandler;

@property (nonatomic, readwrite, retain) Crasher* crasher;

@end
