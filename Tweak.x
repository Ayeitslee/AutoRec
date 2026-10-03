#import <UIKit/UIKit.h>
#import <notify.h>
#import "AROverlay.h"
#import "ARCore.h"
#import "ARPrefs.h"

static void ARInstallOnce(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static BOOL startupChecked;
        if (!startupChecked) {
            startupChecked = YES;
            if ([ARPreferences safeMode] && ![ARPreferences lastLaunchClean]) {
                [ARPreferences setEnabled:NO];
                ARLog(@"safe mode: previous SpringBoard launch was not clean; dock disabled");
            }
            [ARPreferences setLastLaunchClean:NO];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [ARPreferences setLastLaunchClean:YES];
            });
        }
        [ARController shared];
        [AROverlay install];
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    ARInstallOnce();
}
%end

%ctor {
    ARLog(@"AutoRec loaded");
    int dockToken = 0;
    notify_register_dispatch("com.local.autorec.toggleDock", &dockToken, dispatch_get_main_queue(), ^(int token) {
        if ([ARPreferences enabled]) [AROverlay install]; else [AROverlay uninstall];
    });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) { ARInstallOnce(); }];
}
