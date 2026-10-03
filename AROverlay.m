#import "AROverlay.h"
#import "ARCore.h"
#import "ARPrefs.h"

@interface UIWindow (ARPrivate)
- (void)_setSecure:(BOOL)secure;
@end

@interface ARWindow : UIWindow
@end
@implementation ARWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return (v == self || v == self.rootViewController.view) ? nil : v;   // touches outside the panel pass through
}
@end

typedef NS_ENUM(NSInteger, ARPanelMode) { ARPanelDot, ARPanelBar, ARPanelFull };

@interface AROverlay () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@end

@implementation AROverlay {
    ARWindow *_win;
    UIVisualEffectView *_panel;
    UIStackView *_stack, *_top, *_rows;
    UILabel *_status;
    UIButton *_rec, *_play, *_stop, *_more, *_settings, *_mini, *_dot;
    UITableView *_table;
    NSArray<NSString *> *_names;
    NSLayoutConstraint *_widthC;
    ARPanelMode _mode;
    UILabel *_speedL, *_loopsL, *_ldL, *_sdL, *_empty;
    UIStepper *_speedS, *_loopsS, *_ldS, *_sdS;
}

static const double kSpeeds[] = {0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4};
static const int kSpeedCount = 8;

static AROverlay *gOverlay;

+ (void)install {
    if (![ARPreferences enabled]) { [self uninstall]; return; }
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        @try {
            gOverlay = [AROverlay new];
            [gOverlay build];
        } @catch (NSException *exception) {
            ARLog(@"overlay installation failed: %@", exception);
            gOverlay = nil;
            [ARPreferences setEnabled:NO];
        }
    });
    if (gOverlay) gOverlay->_win.hidden = NO;
}

+ (void)uninstall {
    if (gOverlay) gOverlay->_win.hidden = YES;
}

#pragma mark Build
- (UIButton *)iconButton:(NSString *)sym action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    [b.widthAnchor constraintEqualToConstant:34].active = YES;
    [b.heightAnchor constraintEqualToConstant:34].active = YES;
    return b;
}

- (UIStackView *)rowTitle:(NSString *)title label:(UILabel *)v stepper:(UIStepper *)s min:(double)mn max:(double)mx step:(double)st {
    UILabel *t = [UILabel new]; t.text = title; t.font = [UIFont systemFontOfSize:14]; t.textColor = UIColor.labelColor;
    v.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    v.textAlignment = NSTextAlignmentRight; v.textColor = UIColor.secondaryLabelColor;
    [v.widthAnchor constraintEqualToConstant:56].active = YES;
    s.minimumValue = mn; s.maximumValue = mx; s.stepValue = st;
    [s addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *r = [[UIStackView alloc] initWithArrangedSubviews:@[t, v, s]];
    r.spacing = 6; r.alignment = UIStackViewAlignmentCenter;
    return r;
}

- (void)build {
    ARWindow *w = [[ARWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    w.windowLevel = UIWindowLevelAlert + 100000;
    w.backgroundColor = UIColor.clearColor;
    w.rootViewController = [UIViewController new];
    w.rootViewController.view.backgroundColor = UIColor.clearColor;
    if ([w respondsToSelector:@selector(_setSecure:)]) [w _setSecure:YES];
    w.hidden = NO;
    _win = w;

    _panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    _panel.layer.cornerRadius = 20; _panel.clipsToBounds = YES;
    _panel.frame = CGRectMake(20, 90, 290, 60);
    [w.rootViewController.view addSubview:_panel];

    _rec  = [self iconButton:@"record.circle" action:@selector(tapRec)];
    _play = [self iconButton:@"play.fill" action:@selector(tapPlay)];
    _stop = [self iconButton:@"stop.fill" action:@selector(tapStop)];
    _more = [self iconButton:@"list.bullet" action:@selector(tapMore)];
    _settings = [self iconButton:@"gearshape.fill" action:@selector(tapSettings)];
    _mini = [self iconButton:@"minus.circle" action:@selector(tapMini)];
    _status = [UILabel new];
    _status.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _status.textColor = UIColor.secondaryLabelColor;
    _status.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_status setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _top = [[UIStackView alloc] initWithArrangedSubviews:@[_rec, _play, _stop, _more, _settings, _mini]];
    _top.spacing = 4; _top.distribution = UIStackViewDistributionEqualSpacing;

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.dataSource = self; _table.delegate = self; _table.backgroundColor = UIColor.clearColor;
    _table.rowHeight = 42; _table.layer.cornerRadius = 10; _table.clipsToBounds = YES;
    _empty = [UILabel new]; _empty.text = @"No recordings yet"; _empty.textAlignment = NSTextAlignmentCenter;
    _empty.font = [UIFont systemFontOfSize:13]; _empty.textColor = UIColor.secondaryLabelColor;
    [_table.heightAnchor constraintEqualToConstant:150].active = YES;

    _speedS = [UIStepper new]; _speedL = [UILabel new];
    _loopsS = [UIStepper new]; _loopsL = [UILabel new];
    _ldS = [UIStepper new];    _ldL = [UILabel new];
    _sdS = [UIStepper new];    _sdL = [UILabel new];
    UIStackView *r1 = [self rowTitle:@"Speed" label:_speedL stepper:_speedS min:0 max:kSpeedCount - 1 step:1];
    UIStackView *r2 = [self rowTitle:@"Loops (0 = ∞)" label:_loopsL stepper:_loopsS min:0 max:9999 step:1];
    UIStackView *r3 = [self rowTitle:@"Loop delay" label:_ldL stepper:_ldS min:0 max:120 step:0.5];
    UIStackView *r4 = [self rowTitle:@"Start delay" label:_sdL stepper:_sdS min:0 max:15 step:1];
    _rows = [[UIStackView alloc] initWithArrangedSubviews:@[_table, r1, r2, r3, r4]];
    _rows.axis = UILayoutConstraintAxisVertical; _rows.spacing = 8;

    _stack = [[UIStackView alloc] initWithArrangedSubviews:@[_status, _top, _rows]];
    _stack.axis = UILayoutConstraintAxisVertical; _stack.spacing = 6;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel.contentView addSubview:_stack];
    _widthC = [_stack.widthAnchor constraintEqualToConstant:270];
    [NSLayoutConstraint activateConstraints:@[
        _widthC,
        [_stack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:10],
        [_stack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:8],
    ]];

    // Minimised dot
    _dot = [UIButton buttonWithType:UIButtonTypeSystem];
    _dot.frame = CGRectMake(0, 0, 44, 44);
    _dot.layer.cornerRadius = 22; _dot.clipsToBounds = YES;
    [_dot setImage:[UIImage systemImageNamed:@"hand.tap.fill"] forState:UIControlStateNormal];
    _dot.tintColor = UIColor.whiteColor;
    [_dot addTarget:self action:@selector(tapDot) forControlEvents:UIControlEventTouchUpInside];
    _dot.hidden = YES;
    [w.rootViewController.view addSubview:_dot];
    [_dot addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

    // Drag the panel by its status label / top row background
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    pan.delegate = self;
    pan.cancelsTouchesInView = NO;
    [_panel addGestureRecognizer:pan];

    ARController *c = [ARController shared];
    __weak AROverlay *ws = self;
    c.onChange = ^{ [ws refresh]; };
    c.excludeTouch = ^BOOL(CGPoint n) { return [ws hitsPanel:n]; };

    [self reloadNames];
    [self syncSettingControls];
    [self setMode:ARPanelBar];
    [self refresh];
    ARLog(@"overlay installed");
}

#pragma mark Layout / state
- (BOOL)hitsPanel:(CGPoint)n {
    UIScreen *s = UIScreen.mainScreen;
    CGSize fs = s.fixedCoordinateSpace.bounds.size;
    CGPoint p = [s.coordinateSpace convertPoint:CGPointMake(n.x * fs.width, n.y * fs.height) fromCoordinateSpace:s.fixedCoordinateSpace];
    UIView *v = _mode == ARPanelDot ? _dot : _panel;
    CGRect r = CGRectInset([v convertRect:v.bounds toCoordinateSpace:s.coordinateSpace], -10, -10);
    return CGRectContainsPoint(r, p);
}

- (void)setMode:(ARPanelMode)m {
    _mode = m;
    BOOL dot = (m == ARPanelDot);
    _panel.hidden = dot; _dot.hidden = !dot;
    if (dot) _dot.center = CGPointMake(CGRectGetMidX(_panel.frame), CGRectGetMidY(_panel.frame));
    _rows.hidden = (m != ARPanelFull);
    if (m == ARPanelFull) { [self reloadNames]; [self syncSettingControls]; }
    [self relayout];
}

- (void)relayout {
    if (_mode == ARPanelDot) return;
    [_stack setNeedsLayout]; [_stack layoutIfNeeded];
    CGSize fit = [_stack systemLayoutSizeFittingSize:CGSizeMake(270, UILayoutFittingCompressedSize.height)
                       withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect f = _panel.frame;
    f.size = CGSizeMake(290, fit.height + 16);
    CGRect bounds = UIScreen.mainScreen.bounds;
    f.origin.x = MAX(4, MIN(f.origin.x, bounds.size.width - f.size.width - 4));
    f.origin.y = MAX(40, MIN(f.origin.y, bounds.size.height - f.size.height - 4));
    [UIView animateWithDuration:0.18 animations:^{ self->_panel.frame = f; }];
}

- (void)drag:(UIPanGestureRecognizer *)g {
    UIView *v = (_mode == ARPanelDot) ? _dot : _panel;
    CGPoint t = [g translationInView:_win];
    CGRect b = UIScreen.mainScreen.bounds;
    CGPoint c = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    c.x = MAX(v.bounds.size.width / 2, MIN(c.x, b.size.width - v.bounds.size.width / 2));
    c.y = MAX(v.bounds.size.height / 2, MIN(c.y, b.size.height - v.bounds.size.height / 2));
    v.center = c;
    [g setTranslation:CGPointZero inView:_win];
    if (_mode == ARPanelDot) _panel.center = c; else _dot.center = c;
}

- (void)reloadNames {
    _names = [ARStore names];
    _table.backgroundView = _names.count ? nil : _empty;
    [_table reloadData];
}

- (void)syncSettingControls {
    ARController *c = [ARController shared];
    int si = 3; for (int i = 0; i < kSpeedCount; i++) if (fabs(kSpeeds[i] - c.speed) < 0.01) si = i;
    _speedS.value = si; _loopsS.value = c.loops; _ldS.value = c.loopDelay; _sdS.value = c.startDelay;
    [self updateSettingLabels];
}
- (void)updateSettingLabels {
    _speedL.text = [NSString stringWithFormat:@"%gx", kSpeeds[(int)_speedS.value]];
    _loopsL.text = _loopsS.value == 0 ? @"∞" : [NSString stringWithFormat:@"%d", (int)_loopsS.value];
    _ldL.text = [NSString stringWithFormat:@"%.1fs", _ldS.value];
    _sdL.text = [NSString stringWithFormat:@"%ds", (int)_sdS.value];
}
- (void)settingsChanged {
    ARController *c = [ARController shared];
    c.speed = kSpeeds[(int)_speedS.value]; c.loops = (NSInteger)_loopsS.value;
    c.loopDelay = _ldS.value; c.startDelay = _sdS.value;
    [self updateSettingLabels];
}

- (void)refresh {
    ARController *c = [ARController shared];
    _status.text = [c statusText];
    BOOL idle = c.state == ARStateIdle;
    _rec.enabled = idle || c.state == ARStateRecording;
    _play.enabled = idle && c.current.frames.count > 0;
    _stop.enabled = !idle;
    _more.enabled = idle;
    [_rec setImage:[UIImage systemImageNamed:c.state == ARStateRecording ? @"stop.circle.fill" : @"record.circle"
                            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]]
          forState:UIControlStateNormal];
    _rec.tintColor = c.state == ARStateRecording ? UIColor.systemRedColor : UIColor.systemBlueColor;
    UIColor *dotColor = UIColor.systemGrayColor;
    if (c.state == ARStateRecording) dotColor = UIColor.systemRedColor;
    else if (c.state == ARStatePlaying) dotColor = UIColor.systemGreenColor;
    else if (c.state == ARStateCountdown) dotColor = UIColor.systemOrangeColor;
    _dot.backgroundColor = dotColor;
    _panel.alpha = c.state == ARStatePlaying ? 0.45 : 1.0;
    _dot.alpha = c.state == ARStatePlaying ? 0.6 : 1.0;
    _settings.enabled = idle;
    if (_mode == ARPanelFull && !idle) [self setMode:ARPanelBar];
    if (idle) [self reloadNames];
}

#pragma mark Actions
- (void)tapRec {
    ARController *c = [ARController shared];
    if (c.state == ARStateRecording) [c stopRecording]; else [c startRecording];
    if (c.state != ARStateIdle && _mode == ARPanelFull) [self setMode:ARPanelBar];
}
- (void)tapPlay { [[ARController shared] play]; }
- (void)tapStop { [[ARController shared] stop]; }
- (void)tapMore { [self setMode:_mode == ARPanelFull ? ARPanelBar : ARPanelFull]; }
- (void)tapSettings {
    NSURL *url = [NSURL URLWithString:@"autom8://settings"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) ARLog(@"AutoM8 is not installed; settings shortcut unavailable");
    }];
}
- (void)tapMini { [self setMode:ARPanelDot]; }
- (void)tapDot { [self setMode:ARPanelBar]; }

#pragma mark Gestures
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    if (_mode != ARPanelFull) return YES;
    CGPoint p = [touch locationInView:_stack];
    return !CGRectContainsPoint(_rows.frame, p);   // the list and steppers keep their own gestures
}

#pragma mark Table
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _names.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    NSString *n = _names[ip.row];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.text = n; cell.textLabel.font = [UIFont systemFontOfSize:14];
    ARRecording *cur = [ARController shared].current;
    BOOL sel = [cur.name isEqualToString:n];
    cell.accessoryType = sel ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = sel ? [NSString stringWithFormat:@"%.1fs · %lu frames", cur.duration, (unsigned long)cur.frames.count] : @"";
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [[ARController shared] selectName:_names[ip.row]];
    [t reloadData];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    NSString *n = _names[ip.row];
    [ARStore deleteNamed:n];
    if ([[ARController shared].current.name isEqualToString:n]) {
        NSArray *rest = [ARStore names];
        [[ARController shared] selectName:rest.count ? rest.firstObject : nil];
    }
    [self reloadNames];
    [self refresh];
}
@end
