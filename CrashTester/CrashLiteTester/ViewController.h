//
//  ViewController.h
//  CrashLiteTester
//
//  Created by Karl Stenerud on 12-05-08.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property(retain,nonatomic,readwrite) IBOutlet UITextView* crashTextView;

- (IBAction)onException:(id)sender;

- (IBAction)onBadPointer:(id)sender;

@end
