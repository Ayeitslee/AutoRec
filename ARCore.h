#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Appends to /var/mobile/Library/AutoRec/log.txt (capped). Used for on-device diagnostics.
void ARLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);

typedef NS_ENUM(NSInteger, ARState) { ARStateIdle, ARStateCountdown, ARStateRecording, ARStatePlaying };

@interface ARRecording : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSArray *frames;   // [[tMs, [[idx,id,x,y,mask,range,touch],...]], ...]
@property (nonatomic) double duration;           // seconds
@end

@interface ARStore : NSObject
+ (NSArray<NSString *> *)names;                  // newest first
+ (ARRecording *)load:(NSString *)name;
+ (BOOL)save:(ARRecording *)rec;
+ (void)deleteNamed:(NSString *)name;
+ (NSDictionary *)backupPayload;
+ (BOOL)restoreFromBackupPayload:(NSDictionary *)payload error:(NSError **)error;
@end

@interface ARController : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) ARState state;
@property (nonatomic, readonly) NSInteger currentLoop;
@property (nonatomic, readonly) NSInteger countdownRemaining;
@property (nonatomic, readonly, copy) NSString *lastError;
@property (nonatomic, strong, readonly) ARRecording *current;

// Persisted settings
@property (nonatomic) double speed;        // 0.25 ... 4
@property (nonatomic) NSInteger loops;     // 0 = infinite when loopEnabled is YES
@property (nonatomic) double loopDelay;    // seconds between loops
@property (nonatomic) double startDelay;   // seconds before record/play begins

// When disabled, playback always runs exactly once.
@property (nonatomic, readonly) BOOL loopEnabled;

// Return YES to keep a touch (given in normalized portrait coords) out of the recording.
@property (nonatomic, copy) BOOL (^excludeTouch)(CGPoint normalizedPoint);
@property (nonatomic, copy) void (^onChange)(void);

- (void)selectName:(NSString *)name;
- (void)startRecording;
- (void)stopRecording;
- (void)play;
- (void)stop;                              // stops countdown, recording or playback
- (NSString *)statusText;
@end
