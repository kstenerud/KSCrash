//
//  AppDelegate.h
//
//  Created by Karl Stenerud on 12-03-04.
//

#import <UIKit/UIKit.h>
#import <MessageUI/MessageUI.h>
#import "ARCSafe_MemMgmt.h"


@class ViewController;

@interface AppDelegate : UIResponder <UIApplicationDelegate, MFMailComposeViewControllerDelegate>

@property (nonatomic,as_strongprop) UIWindow* window;

@property (nonatomic,as_strongprop) ViewController* viewController;

@end
