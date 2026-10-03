#import "AMAppDelegate.h"
#import "AMViewController.h"

@implementation AMAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[AMViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
