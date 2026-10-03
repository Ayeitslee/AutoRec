#import "ARPrefs.h"
#import <math.h>

static NSString *const kSuite = @"com.local.autorec";
static NSString *const kEnabled = @"AutoRec.enabled";
static NSString *const kLoopEnabled = @"AutoRec.loopEnabled";
static NSString *const kSpeed = @"AutoRec.speed";
static NSString *const kLoops = @"AutoRec.loops";
static NSString *const kLoopDelay = @"AutoRec.loopDelay";
static NSString *const kStartDelay = @"AutoRec.startDelay";
static NSString *const kSafeMode = @"AutoRec.safeMode";
static NSString *const kLastLaunchClean = @"AutoRec.lastLaunchClean";

@implementation ARPreferences
+ (NSUserDefaults *)defaults {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:kSuite]; });
    return defaults;
}
+ (BOOL)enabled {
    NSUserDefaults *d = [self defaults];
    return [d objectForKey:kEnabled] ? [d boolForKey:kEnabled] : YES;
}
+ (void)setEnabled:(BOOL)value { [[self defaults] setBool:value forKey:kEnabled]; [[self defaults] synchronize]; }
+ (BOOL)loopEnabled { return [[self defaults] boolForKey:kLoopEnabled]; }
+ (void)setLoopEnabled:(BOOL)value { [[self defaults] setBool:value forKey:kLoopEnabled]; [[self defaults] synchronize]; }
+ (double)speed { double value = [[self defaults] doubleForKey:kSpeed]; return isfinite(value) && value >= 0.25 && value <= 4.0 ? value : 1.0; }
+ (void)setSpeed:(double)value { [[self defaults] setDouble:isfinite(value) ? MIN(MAX(value, 0.25), 4.0) : 1.0 forKey:kSpeed]; [[self defaults] synchronize]; }
+ (NSInteger)loops { NSUserDefaults *d = [self defaults]; return [d objectForKey:kLoops] ? MIN(MAX([d integerForKey:kLoops], 0), 9999) : 1; }
+ (void)setLoops:(NSInteger)value { [[self defaults] setInteger:MIN(MAX(value, 0), 9999) forKey:kLoops]; [[self defaults] synchronize]; }
+ (double)loopDelay { double value = [[self defaults] doubleForKey:kLoopDelay]; return isfinite(value) ? MIN(MAX(value, 0), 120) : 0; }
+ (void)setLoopDelay:(double)value { [[self defaults] setDouble:isfinite(value) ? MIN(MAX(value, 0), 120) : 0 forKey:kLoopDelay]; [[self defaults] synchronize]; }
+ (double)startDelay { NSUserDefaults *d = [self defaults]; double value = [d objectForKey:kStartDelay] ? [d doubleForKey:kStartDelay] : 3.0; return isfinite(value) ? MIN(MAX(value, 0), 15) : 3.0; }
+ (void)setStartDelay:(double)value { [[self defaults] setDouble:isfinite(value) ? MIN(MAX(value, 0), 15) : 3.0 forKey:kStartDelay]; [[self defaults] synchronize]; }
+ (BOOL)safeMode { return YES; }
+ (void)setSafeMode:(BOOL)value {
    [[self defaults] setBool:YES forKey:kSafeMode];
    [[self defaults] synchronize];
}
+ (BOOL)lastLaunchClean {
    NSUserDefaults *d = [self defaults];
    return [d objectForKey:kLastLaunchClean] ? [d boolForKey:kLastLaunchClean] : YES;
}
+ (void)setLastLaunchClean:(BOOL)value { [[self defaults] setBool:value forKey:kLastLaunchClean]; [[self defaults] synchronize]; }
@end
