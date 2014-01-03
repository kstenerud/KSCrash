//
//  AppDelegate.h
//  Crash-Tester
//
//  Created by Karl Stenerud on 9/27/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, assign) IBOutlet NSWindow* window;

@property (nonatomic, weak) IBOutlet NSTextFieldCell* reportCountLabel;

@end
