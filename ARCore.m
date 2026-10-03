#import "ARCore.h"
#import "ARPrefs.h"
#import "HID.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach_time.h>
#import <notify.h>
#import <unistd.h>
#import <math.h>

static NSString *const kDir = @"/var/mobile/Library/AutoRec";
static const NSTimeInterval kMaxRecordingSeconds = 20.0 * 60.0;
static NSUserDefaults *D(void) { return [ARPreferences defaults]; }

void ARLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    static dispatch_queue_t q; static dispatch_once_t once; static NSDateFormatter *df;
    NSString *path = [kDir stringByAppendingPathComponent:@"log.txt"];
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.local.autorec.log", DISPATCH_QUEUE_SERIAL);
        df = [NSDateFormatter new]; df.dateFormat = @"MM-dd HH:mm:ss.SSS";
        [[NSFileManager defaultManager] createDirectoryAtPath:kDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        if ([a fileSize] > 200 * 1024) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    });
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], msg];
    dispatch_async(q, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    });
}

#pragma mark - Model / store

@implementation ARRecording
@end

@implementation ARStore

static BOOL ARFiniteNumber(id value) {
    return [value isKindOfClass:[NSNumber class]] && isfinite([value doubleValue]);
}

static BOOL ARValidFrames(NSArray *frames) {
    for (id frame in frames) {
        if (![frame isKindOfClass:[NSArray class]] || [frame count] != 2 || !ARFiniteNumber(frame[0]) || [frame[0] doubleValue] < 0) return NO;
        id fingers = frame[1];
        if (![fingers isKindOfClass:[NSArray class]]) return NO;
        for (id finger in fingers) {
            if (![finger isKindOfClass:[NSArray class]] || [finger count] != 7) return NO;
            for (id value in finger) if (!ARFiniteNumber(value)) return NO;
            double x = [finger[2] doubleValue], y = [finger[3] doubleValue];
            if (x < 0 || x > 1 || y < 0 || y > 1) return NO;
        }
    }
    return YES;
}

+ (NSString *)pathFor:(NSString *)name {
    NSString *safe = [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    return [kDir stringByAppendingPathComponent:[safe stringByAppendingPathExtension:@"json"]];
}
+ (NSArray<NSString *> *)names {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:kDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *f in [fm contentsOfDirectoryAtPath:kDir error:nil] ?: @[]) {
        if (![f.pathExtension isEqualToString:@"json"]) continue;
        NSDictionary *a = [fm attributesOfItemAtPath:[kDir stringByAppendingPathComponent:f] error:nil];
        [items addObject:@[f.stringByDeletingPathExtension, a[NSFileModificationDate] ?: [NSDate distantPast]]];
    }
    [items sortUsingComparator:^NSComparisonResult(NSArray *x, NSArray *y) { return [y[1] compare:x[1]]; }];
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *i in items) [out addObject:i[0]];
    return out;
}
+ (ARRecording *)load:(NSString *)name {
    NSData *d = [NSData dataWithContentsOfFile:[self pathFor:name]];
    if (!d) return nil;
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![j isKindOfClass:[NSDictionary class]] || ![j[@"frames"] isKindOfClass:[NSArray class]] || !ARValidFrames(j[@"frames"])) return nil;
    ARRecording *r = [ARRecording new];
    r.name = name;
    r.frames = j[@"frames"];
    r.duration = [j[@"duration"] doubleValue];
    return r;
}
+ (BOOL)save:(ARRecording *)rec {
    [[NSFileManager defaultManager] createDirectoryAtPath:kDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *j = @{@"version": @1, @"name": rec.name, @"duration": @(rec.duration), @"frames": rec.frames};
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
    return [d writeToFile:[self pathFor:rec.name] atomically:YES];
}
+ (void)deleteNamed:(NSString *)name {
    [[NSFileManager defaultManager] removeItemAtPath:[self pathFor:name] error:nil];
}

+ (NSDictionary *)backupPayload {
    NSMutableArray *recordings = [NSMutableArray array];
    for (NSString *name in [self names]) {
        ARRecording *recording = [self load:name];
        if (!recording || !recording.frames) continue;
        [recordings addObject:@{
            @"name": recording.name ?: @"Recording",
            @"duration": @(MAX(0, recording.duration)),
            @"frames": recording.frames
        }];
    }
    return @{
        @"format": @"com.local.autorec.backup",
        @"version": @1,
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"preferences": @{
            @"enabled": @([ARPreferences enabled]),
            @"loopEnabled": @([ARPreferences loopEnabled]),
            @"speed": @([ARPreferences speed]),
            @"loops": @([ARPreferences loops]),
            @"loopDelay": @([ARPreferences loopDelay]),
            @"startDelay": @([ARPreferences startDelay])
        },
        @"recordings": recordings
    };
}

static void ARSetRestoreError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"com.local.autorec.backup" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL ARValidRecordingName(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || name.length == 0 || name.length > 128) return NO;
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."] || [name containsString:@"/"] || [name containsString:@"\\"]) return NO;
    return YES;
}

+ (BOOL)restoreFromBackupPayload:(NSDictionary *)payload error:(NSError **)error {
    if (![payload isKindOfClass:[NSDictionary class]] || ![payload[@"format"] isEqual:@"com.local.autorec.backup"] || [payload[@"version"] integerValue] != 1) {
        ARSetRestoreError(error, @"This is not a supported AutoRec backup.");
        return NO;
    }
    NSArray *recordings = payload[@"recordings"];
    NSDictionary *preferences = payload[@"preferences"];
    if (![recordings isKindOfClass:[NSArray class]] || ![preferences isKindOfClass:[NSDictionary class]]) {
        ARSetRestoreError(error, @"The backup is missing required data.");
        return NO;
    }

    NSMutableArray *validated = [NSMutableArray arrayWithCapacity:recordings.count];
    NSMutableSet *incomingNames = [NSMutableSet set];
    for (NSDictionary *item in recordings) {
        if (![item isKindOfClass:[NSDictionary class]] || !ARValidRecordingName(item[@"name"]) || ![item[@"frames"] isKindOfClass:[NSArray class]] || !ARValidFrames(item[@"frames"])) {
            ARSetRestoreError(error, @"The backup contains an invalid recording.");
            return NO;
        }
        NSString *name = item[@"name"];
        if ([incomingNames containsObject:name]) {
            ARSetRestoreError(error, @"The backup contains duplicate recording names.");
            return NO;
        }
        [incomingNames addObject:name];
        double duration = [item[@"duration"] doubleValue];
        if (!ARFiniteNumber(item[@"duration"]) || duration < 0 || duration > 20 * 60) {
            ARSetRestoreError(error, @"The backup contains an invalid recording duration.");
            return NO;
        }
        [validated addObject:@{ @"name": name, @"duration": @(duration), @"frames": item[@"frames"] }];
    }

    NSMutableSet *existingNames = [NSMutableSet setWithArray:[self names]];
    NSMutableArray *savedNames = [NSMutableArray array];
    for (NSDictionary *item in validated) {
        NSString *base = item[@"name"];
        NSString *name = base;
        NSUInteger suffix = 2;
        while ([existingNames containsObject:name]) name = [NSString stringWithFormat:@"%@ (%lu)", base, (unsigned long)suffix++];
        ARRecording *recording = [ARRecording new];
        recording.name = name;
        recording.duration = [item[@"duration"] doubleValue];
        recording.frames = item[@"frames"];
        if (![self save:recording]) {
            for (NSString *savedName in savedNames) [self deleteNamed:savedName];
            ARSetRestoreError(error, @"AutoRec could not save the restored recordings.");
            return NO;
        }
        [savedNames addObject:name];
        [existingNames addObject:name];
    }

    if (preferences[@"enabled"] != nil) [ARPreferences setEnabled:[preferences[@"enabled"] boolValue]];
    if (preferences[@"loopEnabled"] != nil) [ARPreferences setLoopEnabled:[preferences[@"loopEnabled"] boolValue]];
    if (ARFiniteNumber(preferences[@"speed"])) [ARPreferences setSpeed:[preferences[@"speed"] doubleValue]];
    if ([preferences[@"loops"] isKindOfClass:[NSNumber class]]) [ARPreferences setLoops:[preferences[@"loops"] integerValue]];
    if (ARFiniteNumber(preferences[@"loopDelay"])) [ARPreferences setLoopDelay:[preferences[@"loopDelay"] doubleValue]];
    if (ARFiniteNumber(preferences[@"startDelay"])) [ARPreferences setStartDelay:[preferences[@"startDelay"] doubleValue]];
    return YES;
}
@end

#pragma mark - Controller

@interface ARController () {
    ARState _state;
    NSInteger _currentLoop, _remaining;
    IOHIDEventSystemClientRef _recClient;
    NSMutableArray *_frames;
    NSMutableSet *_down, *_ignored;
    CFTimeInterval _t0;
    NSUInteger _cdToken;
    NSUInteger _evSeen, _evKept, _injected;
    NSTimer *_recordTimer;
    dispatch_queue_t _q;
}
@property (atomic) NSUInteger gen;
@property (nonatomic, copy, readwrite) NSString *lastError;
@property (nonatomic, strong, readwrite) ARRecording *current;
- (void)handleHID:(IOHIDEventRef)e;
@end

static void HIDCallback(void *target, void *refcon, void *queue, IOHIDEventRef event) {
    [[ARController shared] handleHID:event];
}

@implementation ARController

+ (instancetype)shared {
    static ARController *c; static dispatch_once_t t;
    dispatch_once(&t, ^{ c = [ARController new]; });
    return c;
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = dispatch_queue_create("com.local.autorec.play", DISPATCH_QUEUE_SERIAL);
        ARLog(@"AutoRec controller init (pid %d)", getpid());
        NSArray *names = [ARStore names];
        if (names.count) _current = [ARStore load:names.firstObject];
        __weak ARController *w = self;
        int t1, t2;
        notify_register_dispatch("com.local.autorec.toggleRecord", &t1, dispatch_get_main_queue(), ^(int t) {
            ARController *s = w; if (!s) return;
            if (s.state == ARStateRecording) [s stopRecording]; else [s startRecording];
        });
        notify_register_dispatch("com.local.autorec.togglePlay", &t2, dispatch_get_main_queue(), ^(int t) {
            ARController *s = w; if (!s) return;
            if (s.state == ARStateIdle) [s play]; else [s stop];
        });
    }
    return self;
}

#pragma mark Settings
- (double)speed { return [ARPreferences speed]; }
- (void)setSpeed:(double)v { [ARPreferences setSpeed:v]; }
- (NSInteger)loops { return [ARPreferences loops]; }
- (void)setLoops:(NSInteger)v { [ARPreferences setLoops:v]; }
- (double)loopDelay { return [ARPreferences loopDelay]; }
- (void)setLoopDelay:(double)v { [ARPreferences setLoopDelay:v]; }
- (id)startDelayObj { return @([ARPreferences startDelay]); }
- (double)startDelay { return [ARPreferences startDelay]; }
- (void)setStartDelay:(double)v { [ARPreferences setStartDelay:v]; }
- (BOOL)loopEnabled { return [ARPreferences loopEnabled]; }

#pragma mark State helpers
- (ARState)state { return _state; }
- (NSInteger)currentLoop { return _currentLoop; }
- (NSInteger)countdownRemaining { return _remaining; }

- (void)changed { if (self.onChange) self.onChange(); }
- (void)setStateAndNotify:(ARState)s { _state = s; [self changed]; }

- (NSString *)statusText {
    if (self.lastError.length && _state == ARStateIdle) return self.lastError;
    switch (_state) {
        case ARStateIdle: return self.current ? [NSString stringWithFormat:@"Ready · %@", self.current.name] : @"Ready · nothing recorded";
        case ARStateCountdown: return [NSString stringWithFormat:@"Starting in %ld…", (long)_remaining];
        case ARStateRecording: return @"Recording…";
        case ARStatePlaying: {
            NSInteger n = self.loops;
            return n == 0 ? [NSString stringWithFormat:@"Playing · loop %ld", (long)_currentLoop]
                          : [NSString stringWithFormat:@"Playing · %ld/%ld", (long)_currentLoop, (long)n];
        }
    }
}

- (void)selectName:(NSString *)name {
    if (!name.length) {
        self.current = nil;
        self.lastError = nil;
        [self changed];
        return;
    }
    ARRecording *r = [ARStore load:name];
    if (r) { self.current = r; self.lastError = nil; }
    [self changed];
}

#pragma mark Countdown
- (void)runCountdownThen:(void (^)(void))then {
    NSUInteger tok = ++_cdToken;
    _remaining = (NSInteger)ceil(self.startDelay);
    if (_remaining <= 0) { then(); return; }
    [self setStateAndNotify:ARStateCountdown];
    [self tick:tok then:then];
}
- (void)tick:(NSUInteger)tok then:(void (^)(void))then {
    if (tok != _cdToken) return;
    if (_remaining <= 0) { then(); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (tok != self->_cdToken) return;
        self->_remaining--;
        [self changed];
        [self tick:tok then:then];
    });
}

#pragma mark Recording
- (void)startRecording {
    if (_state != ARStateIdle || ![ARPreferences enabled]) return;
    self.lastError = nil;
    [self runCountdownThen:^{
        self->_recClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!self->_recClient) {
            ARLog(@"record: IOHIDEventSystemClientCreate returned NULL");
            self.lastError = @"Can't open HID client (see log)";
            [self setStateAndNotify:ARStateIdle];
            return;
        }
        ARLog(@"record: HID client created");
        self->_evSeen = self->_evKept = 0;
        self->_frames = [NSMutableArray array];
        self->_down = [NSMutableSet set];
        self->_ignored = [NSMutableSet set];
        self->_t0 = 0;
        IOHIDEventSystemClientScheduleWithRunLoop(self->_recClient, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        IOHIDEventSystemClientRegisterEventCallback(self->_recClient, HIDCallback, NULL, NULL);
        [self setStateAndNotify:ARStateRecording];
        self->_recordTimer = [NSTimer scheduledTimerWithTimeInterval:kMaxRecordingSeconds
                                                              target:self
                                                            selector:@selector(recordingLimitReached)
                                                            userInfo:nil
                                                             repeats:NO];
    }];
}

- (void)recordingLimitReached {
    if (_state != ARStateRecording) return;
    [self stopRecording];
    self.lastError = @"Recording stopped at the 20-minute limit";
    [self changed];
}

- (void)handleHID:(IOHIDEventRef)e {
    if (_state != ARStateRecording) return;
    if (IOHIDEventGetType(e) != kHIDTypeDigitizer) return;
    _evSeen++;
    CFArrayRef kids = IOHIDEventGetChildren(e);
    if (!kids) return;
    NSMutableArray *fingers = [NSMutableArray array];
    for (CFIndex i = 0; i < CFArrayGetCount(kids); i++) {
        IOHIDEventRef c = (IOHIDEventRef)CFArrayGetValueAtIndex(kids, i);
        if (IOHIDEventGetType(c) != kHIDTypeDigitizer) continue;
        double x = IOHIDEventGetFloatValue(c, kFieldDigX), y = IOHIDEventGetFloatValue(c, kFieldDigY);
        NSInteger idx = IOHIDEventGetIntegerValue(c, kFieldDigIndex);
        NSInteger ident = IOHIDEventGetIntegerValue(c, kFieldDigIdentity);
        NSInteger mask = IOHIDEventGetIntegerValue(c, kFieldDigEventMask);
        NSInteger range = IOHIDEventGetIntegerValue(c, kFieldDigRange);
        NSInteger touch = IOHIDEventGetIntegerValue(c, kFieldDigTouch);
        NSNumber *key = @(ident);
        NSArray *f = @[@(idx), @(ident), @(x), @(y), @(mask), @(range), @(touch)];
        if (touch) {
            if (![_down containsObject:key] && ![_ignored containsObject:key]) {
                if (self.excludeTouch && self.excludeTouch(CGPointMake(x, y))) [_ignored addObject:key];
                else [_down addObject:key];
            }
            if ([_down containsObject:key]) [fingers addObject:f];
        } else {
            if ([_down containsObject:key]) { [fingers addObject:f]; [_down removeObject:key]; }
            [_ignored removeObject:key];
        }
    }
    if (!fingers.count) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (_t0 == 0) _t0 = now;
    _evKept++;
    [_frames addObject:@[@((NSInteger)((now - _t0) * 1000.0)), fingers]];
}

- (void)stopRecording {
    if (_state != ARStateRecording) return;
    [_recordTimer invalidate];
    _recordTimer = nil;
    if (_recClient) {
        IOHIDEventSystemClientUnregisterEventCallback(_recClient);
        IOHIDEventSystemClientUnscheduleWithRunLoop(_recClient, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFRelease(_recClient);
        _recClient = NULL;
    }
    NSArray *frames = [_frames copy];
    ARLog(@"record: stopped, digitizer events seen=%lu kept=%lu", (unsigned long)_evSeen, (unsigned long)_evKept);
    NSUInteger seen = _evSeen;
    _frames = nil; _down = nil; _ignored = nil;
    if (frames.count >= 2) {
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"MMM d HH.mm.ss";
        ARRecording *r = [ARRecording new];
        NSString *stamp = [df stringFromDate:[NSDate date]];
        r.name = [NSString stringWithFormat:@"Rec %@-%@", stamp, [[[NSUUID UUID] UUIDString] substringToIndex:8]];
        r.frames = frames;
        r.duration = [[frames.lastObject firstObject] doubleValue] / 1000.0;
        if ([ARStore save:r]) self.current = r; else self.lastError = @"Couldn't save recording";
    } else {
        self.lastError = seen == 0 ? @"No touch events received (HID monitor blocked?) - see log" : @"Nothing recorded";
    }
    [self setStateAndNotify:ARStateIdle];
}

#pragma mark Playback
- (void)play {
    if (_state != ARStateIdle || ![ARPreferences enabled]) return;
    if (!self.current.frames.count) { self.lastError = @"Nothing to play"; [self changed]; return; }
    self.lastError = nil;
    [self runCountdownThen:^{
        NSArray *frames = self.current.frames;
        double speed = self.speed, loopDelay = self.loopDelay;
        NSInteger loops = [ARPreferences loopEnabled] ? MAX(1, self.loops) : 1;
        NSUInteger gen = ++self.gen;
        self->_injected = 0;
        self->_currentLoop = 1;
        ARLog(@"play: '%@' frames=%lu speed=%g loops=%ld delay=%g", self.current.name, (unsigned long)frames.count, speed, (long)loops, loopDelay);
        [self setStateAndNotify:ARStatePlaying];
        dispatch_async(self->_q, ^{ [self runPlayback:frames speed:speed loops:loops delay:loopDelay gen:gen]; });
    }];
}

- (void)sleepFor:(double)sec gen:(NSUInteger)gen {
    CFTimeInterval end = CACurrentMediaTime() + sec;
    while (gen == self.gen) {
        double w = end - CACurrentMediaTime();
        if (w <= 0) break;
        [NSThread sleepForTimeInterval:MIN(w, 0.05)];
    }
}

- (void)runPlayback:(NSArray *)frames speed:(double)speed loops:(NSInteger)loops delay:(double)delay gen:(NSUInteger)gen {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) {
        ARLog(@"play: IOHIDEventSystemClientCreate returned NULL");
        dispatch_async(dispatch_get_main_queue(), ^{
            self.lastError = @"Can't open HID client (see log)";
            if (gen == self.gen) [self setStateAndNotify:ARStateIdle];
        });
        return;
    }
    NSMutableDictionary *down = [NSMutableDictionary dictionary];
    NSInteger n = 0;
    while (gen == self.gen && (loops == 0 || n < loops)) {
        n++;
        NSInteger loopNo = n;
        dispatch_async(dispatch_get_main_queue(), ^{ if (gen == self.gen) { self->_currentLoop = loopNo; [self changed]; } });
        CFTimeInterval t0 = CACurrentMediaTime();
        for (NSArray *frame in frames) {
            if (gen != self.gen) break;
            double target = [frame[0] doubleValue] / 1000.0 / speed;
            [self sleepFor:target - (CACurrentMediaTime() - t0) gen:gen];
            if (gen != self.gen) break;
            [self inject:frame[1] client:client down:down];
        }
        [self liftAll:client down:down];
        if (gen == self.gen && (loops == 0 || n < loops)) [self sleepFor:delay gen:gen];
    }
    CFRelease(client);
    ARLog(@"play: finished, injected events=%lu", (unsigned long)_injected);
    dispatch_async(dispatch_get_main_queue(), ^{ if (gen == self.gen) [self setStateAndNotify:ARStateIdle]; });
}

- (void)inject:(NSArray *)fingers client:(IOHIDEventSystemClientRef)client down:(NSMutableDictionary *)down {
    if (!fingers.count) return;
    uint64_t ts = mach_absolute_time();
    uint32_t pmask = 0; Boolean anyRange = false, anyTouch = false;
    for (NSArray *f in fingers) {
        pmask |= [f[4] unsignedIntValue];
        anyRange |= [f[5] boolValue]; anyTouch |= [f[6] boolValue];
    }
    NSArray *first = fingers.firstObject;
    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, ts, kDigTransducerHand, 0, 0, pmask, 0,
                                                          [first[2] doubleValue], [first[3] doubleValue], 0, 0, 0, anyRange, anyTouch, 0);
    if (!parent) { ARLog(@"play: IOHIDEventCreateDigitizerEvent returned NULL"); return; }
    for (NSArray *f in fingers) {
        IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, ts, [f[0] unsignedIntValue], [f[1] unsignedIntValue],
                                                                   [f[4] unsignedIntValue], [f[2] doubleValue], [f[3] doubleValue], 0, 0, 0,
                                                                   [f[5] boolValue], [f[6] boolValue], 0);
        if (!child) continue;
        IOHIDEventAppendEvent(parent, child, 0);
        CFRelease(child);
        if ([f[6] boolValue]) down[f[1]] = f; else [down removeObjectForKey:f[1]];
    }
    IOHIDEventSetSenderID(parent, 0x8000000817319372ULL);
    IOHIDEventSystemClientDispatchEvent(client, parent);
    CFRelease(parent);
    if (_injected++ == 0) ARLog(@"play: first event dispatched");
}

- (void)liftAll:(IOHIDEventSystemClientRef)client down:(NSMutableDictionary *)down {
    if (!down.count) return;
    NSMutableArray *ups = [NSMutableArray array];
    for (NSArray *f in down.allValues)
        [ups addObject:@[f[0], f[1], f[2], f[3], @(kDigEventRange | kDigEventTouch), @0, @0]];
    [self inject:ups client:client down:down];
    [down removeAllObjects];
}

#pragma mark Stop
- (void)stop {
    _cdToken++;
    if (_state == ARStateRecording) { [self stopRecording]; return; }
    self.gen++;               // playback thread notices, lifts fingers, exits
    [self setStateAndNotify:ARStateIdle];
}
@end
