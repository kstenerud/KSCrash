//
//  CommandTVC.h
//
//  Created by Karl Stenerud on 2012-03-04.
//

#import <UIKit/UIKit.h>


@interface CommandEntry: NSObject

@property(nonatomic,readwrite,retain) NSString* name;
@property(nonatomic,readwrite,copy) void (^block)(UIViewController* controller);
@property(nonatomic,readwrite,assign) UITableViewCellAccessoryType accessoryType;

+ (CommandEntry*) commandWithName:(NSString*) name
                    accessoryType:(UITableViewCellAccessoryType) accessoryType
                            block:(void(^)(UIViewController* controller)) block;

- (id) initWithName:(NSString*) name
      accessoryType:(UITableViewCellAccessoryType) accessoryType
              block:(void(^)(UIViewController* controller)) block;

- (void) executeWithViewController:(UIViewController*) controller;

@end


@interface CommandTVC : UITableViewController

@property(nonatomic,readonly,retain) NSMutableArray* commands;
@property(nonatomic,readwrite,copy) NSString* (^getTitleBlock)(UIViewController* controller);

- (void) reloadTitle;

@end
