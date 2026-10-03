#import "AMViewController.h"
#import "../ARPrefs.h"
#import <notify.h>
#import <math.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kDockNotification = @"com.local.autorec.toggleDock";
static const double kSpeeds[] = {0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4};
static const NSInteger kSpeedCount = 8;

@implementation AMViewController {
    UISwitch *_enabled;
    UISwitch *_loop;
    UIStepper *_speedS, *_loopsS, *_loopDelayS, *_startDelayS;
    UILabel *_speedV, *_loopsV, *_loopDelayV, *_startDelayV;
    UILabel *_status;
    NSURL *_temporaryBackupURL;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AutoM8";
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Import" style:UIBarButtonItemStylePlain target:self action:@selector(importBackup)],
        [[UIBarButtonItem alloc] initWithTitle:@"Export" style:UIBarButtonItemStylePlain target:self action:@selector(exportBackup)]
    ];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *header = [UILabel new];
    header.text = @"AutoRec settings";
    header.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];

    UILabel *info = [UILabel new];
    info.text = @"Control the floating recorder dock and playback behavior.";
    info.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    info.textColor = UIColor.secondaryLabelColor;
    info.numberOfLines = 0;

    _enabled = [UISwitch new];
    _loop = [UISwitch new];
    _speedS = [UIStepper new]; _speedV = [UILabel new];
    _loopsS = [UIStepper new]; _loopsV = [UILabel new];
    _loopDelayS = [UIStepper new]; _loopDelayV = [UILabel new];
    _startDelayS = [UIStepper new]; _startDelayV = [UILabel new];
    _speedS.minimumValue = 0; _speedS.maximumValue = kSpeedCount - 1; _speedS.stepValue = 1;
    _loopsS.minimumValue = 0; _loopsS.maximumValue = 9999; _loopsS.stepValue = 1;
    _loopDelayS.minimumValue = 0; _loopDelayS.maximumValue = 120; _loopDelayS.stepValue = 0.5;
    _startDelayS.minimumValue = 0; _startDelayS.maximumValue = 15; _startDelayS.stepValue = 1;
    [_speedS addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    [_loopsS addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    [_loopDelayS addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    [_startDelayS addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    _enabled.on = [ARPreferences enabled];
    _loop.on = [ARPreferences loopEnabled];
    [_enabled addTarget:self action:@selector(enabledChanged) forControlEvents:UIControlEventValueChanged];
    [_loop addTarget:self action:@selector(loopChanged) forControlEvents:UIControlEventValueChanged];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        header, info,
        [self row:@"Floating dock" control:_enabled],
        [self row:@"Loop playback" control:_loop],
        [self safeModeLabel],
        [self settingRow:@"Speed" value:_speedV stepper:_speedS],
        [self settingRow:@"Loops (0 = ∞)" value:_loopsV stepper:_loopsS],
        [self settingRow:@"Loop delay" value:_loopDelayV stepper:_loopDelayS],
        [self settingRow:@"Start delay" value:_startDelayV stepper:_startDelayS]
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24]
    ]];

    _status = [UILabel new];
    _status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _status.textColor = UIColor.secondaryLabelColor;
    _status.numberOfLines = 0;
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_status];
    [NSLayoutConstraint activateConstraints:@[
        [_status.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor],
        [_status.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor],
        [_status.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:28]
    ]];
    [self refreshSettings];
    [self refreshStatus];
}

- (void)showMessage:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportBackup {
    NSDictionary *payload = [ARStore backupPayload];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) {
        [self showMessage:@"Backup failed" message:error.localizedDescription ?: @"AutoRec could not create a backup."];
        return;
    }

    NSString *filename = [NSString stringWithFormat:@"AutoRec-backup-%@.json", [[[NSDate date] description] substringToIndex:10]];
    _temporaryBackupURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
    if (![data writeToURL:_temporaryBackupURL options:NSDataWritingAtomic error:&error]) {
        [self showMessage:@"Backup failed" message:error.localizedDescription ?: @"AutoRec could not write the backup."];
        return;
    }

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[_temporaryBackupURL] asCopy:YES];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importBackup {
    UTType *jsonType = [UTType typeWithIdentifier:@"public.json"] ?: [UTType typeWithIdentifier:@"public.data"];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[jsonType] asCopy:YES];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (_temporaryBackupURL) {
        [[NSFileManager defaultManager] removeItemAtURL:_temporaryBackupURL error:nil];
        _temporaryBackupURL = nil;
        [self showMessage:@"Backup exported" message:@"Your AutoRec recordings and settings were saved to the selected location."];
        return;
    }
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];
    NSError *error = nil;
    NSDictionary *payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    if (![payload isKindOfClass:[NSDictionary class]]) {
        [self showMessage:@"Import failed" message:error.localizedDescription ?: @"The selected file is not a valid JSON backup."];
        return;
    }
    if (![ARStore restoreFromBackupPayload:payload error:&error]) {
        [self showMessage:@"Import failed" message:error.localizedDescription ?: @"The AutoRec backup could not be restored."];
        return;
    }
    [self refreshSettings];
    [self refreshStatus];
    [self showMessage:@"Backup restored" message:@"Recordings and settings were restored. Existing recordings were preserved."];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (_temporaryBackupURL) {
        [[NSFileManager defaultManager] removeItemAtURL:_temporaryBackupURL error:nil];
        _temporaryBackupURL = nil;
    }
}

- (UILabel *)safeModeLabel {
    UILabel *label = [UILabel new];
    label.text = @"Safe mode: Always enabled";
    label.textColor = UIColor.secondaryLabelColor;
    return label;
}

- (UIStackView *)settingRow:(NSString *)title value:(UILabel *)value stepper:(UIStepper *)stepper {
    UILabel *label = [UILabel new];
    label.text = title;
    value.textAlignment = NSTextAlignmentRight;
    value.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    value.textColor = UIColor.secondaryLabelColor;
    [value.widthAnchor constraintEqualToConstant:58].active = YES;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, value, stepper]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    return row;
}

- (UIStackView *)row:(NSString *)title control:(UIView *)control {
    UILabel *label = [UILabel new];
    label.text = title;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionEqualSpacing;
    return row;
}

- (void)enabledChanged {
    [ARPreferences setEnabled:_enabled.isOn];
    notify_post([kDockNotification UTF8String]);
    [self refreshStatus];
}

- (void)loopChanged {
    [ARPreferences setLoopEnabled:_loop.isOn];
    [self refreshStatus];
}

- (void)settingsChanged {
    [ARPreferences setSpeed:kSpeeds[(NSInteger)_speedS.value]];
    [ARPreferences setLoops:(NSInteger)_loopsS.value];
    [ARPreferences setLoopDelay:_loopDelayS.value];
    [ARPreferences setStartDelay:_startDelayS.value];
    [self refreshSettings];
}

- (void)refreshSettings {
    _enabled.on = [ARPreferences enabled];
    _loop.on = [ARPreferences loopEnabled];
    double speed = [ARPreferences speed];
    NSInteger speedIndex = 3;
    for (NSInteger i = 0; i < kSpeedCount; i++) if (fabs(kSpeeds[i] - speed) < 0.01) speedIndex = i;
    _speedS.value = speedIndex;
    _loopsS.value = [ARPreferences loops];
    _loopDelayS.value = [ARPreferences loopDelay];
    _startDelayS.value = [ARPreferences startDelay];
    _speedV.text = [NSString stringWithFormat:@"%gx", kSpeeds[(NSInteger)_speedS.value]];
    _loopsV.text = _loopsS.value == 0 ? @"∞" : [NSString stringWithFormat:@"%ld", (long)_loopsS.value];
    _loopDelayV.text = [NSString stringWithFormat:@"%.1fs", _loopDelayS.value];
    _startDelayV.text = [NSString stringWithFormat:@"%lds", (long)_startDelayS.value];
}

- (void)refreshStatus {
    if (!_status) return;
    _status.text = _enabled.isOn
        ? @"The floating dock is enabled. Recordings are limited to 20 minutes."
        : @"The floating dock is disabled. AutoRec will remain inactive until enabled.";
}
@end
