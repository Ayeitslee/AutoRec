#import <Foundation/Foundation.h>

@interface ARPreferences : NSObject
+ (NSUserDefaults *)defaults;
+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)enabled;
+ (BOOL)loopEnabled;
+ (void)setLoopEnabled:(BOOL)enabled;
+ (double)speed;
+ (void)setSpeed:(double)value;
+ (NSInteger)loops;
+ (void)setLoops:(NSInteger)value;
+ (double)loopDelay;
+ (void)setLoopDelay:(double)value;
+ (double)startDelay;
+ (void)setStartDelay:(double)value;
+ (BOOL)safeMode;
+ (void)setSafeMode:(BOOL)enabled;
+ (BOOL)lastLaunchClean;
+ (void)setLastLaunchClean:(BOOL)clean;
@end
