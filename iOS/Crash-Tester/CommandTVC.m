//
//  CommandTVC.m
//
//  Created by Karl Stenerud on 2012-03-04.
//

#import "CommandTVC.h"


@implementation CommandEntry

@synthesize name = _name;
@synthesize block = _block;
@synthesize accessoryType = _accessoryType;

+ (CommandEntry*) commandWithName:(NSString*) name
                    accessoryType:(UITableViewCellAccessoryType) accessoryType
                            block:(void (^)(UIViewController* controller)) block
{
    return [[self alloc] initWithName:name
                        accessoryType:accessoryType
                                block:block];
}

- (id) initWithName:(NSString*) name
      accessoryType:(UITableViewCellAccessoryType) accessoryType
              block:(void (^)(UIViewController* controller)) block
{
    if((self = [super init]))
    {
        self.name = name;
        self.accessoryType = accessoryType;
        self.block = block;
    }
    return self;
}

- (void) executeWithViewController:(UIViewController*) controller
{
    self.block(controller);
}

@end


@interface CommandTVC ()

@property(nonatomic,readwrite,retain) NSMutableArray* commands;

@end

@implementation CommandTVC

@synthesize commands = _commands;
@synthesize getTitleBlock = _getTitleBlock;

- (id)initWithStyle:(UITableViewStyle) style
{
    if((self = [super initWithStyle:style]))
    {
        self.commands = [NSMutableArray array];
    }
    return self;
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadTitle];
}

- (void) reloadTitle
{
    if(self.getTitleBlock != nil)
    {
        self.title = self.getTitleBlock(self);
    }
}

#pragma mark - Table view data source

- (NSInteger) numberOfSectionsInTableView:(__unused UITableView*) tableView
{
    return 1;
}

- (NSInteger) tableView:(__unused UITableView*) tableView numberOfRowsInSection:(__unused NSInteger) section
{
    return (NSInteger)[self.commands count];
}

- (UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    static NSString* CellIdentifier = @"Cell";
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if(cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:CellIdentifier];
    }
    CommandEntry* command = [self.commands objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = command.name;
    cell.accessoryType = command.accessoryType;
    
    return cell;
}

#pragma mark - Table view delegate

- (void) tableView:(UITableView*) tableView didSelectRowAtIndexPath:(NSIndexPath*) indexPath
{
    [[self.commands objectAtIndex:(NSUInteger)indexPath.row] executeWithViewController:self];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
