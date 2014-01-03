//
//  MainVC.m
//  Advanced-Example
//

#import "MainVC.h"


/**
 * Some sensitive info that should not be printed out at any time.
 *
 * If you have Objective-C introspection turned on, it would normally
 * introspect this class, unless you add it to the list of
 * "do not introspect classes" in KSCrash. We do precisely this in 
 * -[AppDelegate configureAdvancedSettings]
 */
@interface SensitiveInfo: NSObject

@property(nonatomic, readwrite, strong) NSString* password;

@end

@implementation SensitiveInfo

@end



@interface MainVC ()

@property(nonatomic, readwrite, strong) SensitiveInfo* info;

@end

@implementation MainVC

- (id) initWithCoder:(NSCoder *)aDecoder
{
    if((self = [super initWithCoder:aDecoder]))
    {
        // This info could be leaked during introspection unless you tell KSCrash to ignore it.
        // See -[AppDelegate configureAdvancedSettings] for more info.
        self.info = [SensitiveInfo new];
        self.info.password = @"it's a secret!";
    }
    return self;
}

- (IBAction) onCrash:(__unused id) sender
{
    char* invalid = (char*)-1;
    *invalid = 1;
}

@end
