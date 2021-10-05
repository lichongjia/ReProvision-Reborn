//
//  RPVApplicationDetailController.m
//  iOS
//
//  Created by Matt Clarke on 14/07/2018.
//  Copyright © 2018 Matt Clarke. All rights reserved.
//

#import "RPVApplicationDetailController.h"
#import "RPVApplication.h"
#import "RPVApplicationSigning.h"
#import "RPVCalendarController.h"
#import "RPVEntitlementsViewController.h"
#import "RPVIpaBundleApplication.h"
#import "RPVResources.h"

#import <MBCircularProgressBarView.h>
#import <MarqueeLabel.h>

#define IS_IPAD UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad

@interface LSResourceProxy : NSObject
@property (nonatomic, readonly) NSString *localizedName;
@end

@interface LSBundleProxy : LSResourceProxy
@property (nonatomic, readonly) NSString *bundleIdentifier;  //@synthesize bundleIdentifier=_bundleIdentifier - In the implementation block
@property (nonatomic, readonly) NSString *bundleType;
@property (nonatomic, readonly) NSURL *bundleURL;            //@synthesize bundleURL=_bundleURL - In the implementation block
@property (nonatomic, readonly) NSString *bundleExecutable;  //@synthesize bundleExecutable=_bundleExecutable - In the implementation block
@property (nonatomic, readonly) NSString *canonicalExecutablePath;
@property (nonatomic, readonly) NSURL *containerURL;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@property (nonatomic, readonly) NSURL *bundleContainerURL;  //@synthesize bundleContainerURL=_bundleContainerURL - In the implementation block
@property (nonatomic, readonly) NSURL *appStoreReceiptURL;
@end

@interface LSApplicationProxy : LSBundleProxy
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (getter=isInstalled, nonatomic, readonly) BOOL installed;
@property (nonatomic, readonly) NSString *localizedName;  //@synthesize itemName=_itemName - In the implementation block
+ (instancetype)applicationProxyForIdentifier:(NSString *)arg1;
@end

@interface RPVApplicationDetailController ()

// Basic heirarchy
@property (nonatomic, strong) UIVisualEffectView *backgroundView;
@property (nonatomic, strong) UIView *darkeningView;
@property (nonatomic, strong) UIView *contentView;

// Components
@property (nonatomic, strong) UIImageView *applicationIconView;
@property (nonatomic, strong) MarqueeLabel *applicationNameLabel;
@property (nonatomic, strong) MarqueeLabel *applicationBundleIdentifierLabel;

@property (nonatomic, strong) UILabel *versionTitle;
@property (nonatomic, strong) UILabel *applicationVersionLabel;

@property (nonatomic, strong) UILabel *installedSizeTitle;
@property (nonatomic, strong) UILabel *applicationInstalledSizeLabel;

@property (nonatomic, strong) UILabel *calendarTitle;
@property (nonatomic, strong) RPVCalendarController *calendarController;

@property (nonatomic, strong) MarqueeLabel *percentCompleteLabel;
@property (nonatomic, strong) MBCircularProgressBarView *progressBar;

@property (nonatomic, strong) UIButton *signingButton;

// Exit controls
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UITapGestureRecognizer *closeGestureRecogniser;

// Data source
@property (nonatomic, strong) RPVApplication *application;

@end

@implementation RPVApplicationDetailController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (instancetype)initWithApplication:(RPVApplication *)application {
    self = [super init];

    if (self) {
        self.application = application;
        self.lockWhenInstalling = NO;

        // Signing Notifications.
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_onSigningStatusUpdate:) name:@"jp.soh.reprovision/signingUpdate" object:nil];
    }

    return self;
}

- (void)setCurrentSigningPercent:(int)percent {
    if (percent < 100)  // no need to show progress if 100% done
        [self _signingProgressDidUpdate:percent];
}

- (void)setButtonTitle:(NSString *)title {
    if (!self.isViewLoaded) {
        [self loadView];
    }

    [self.signingButton setTitle:title
                        forState:UIControlStateNormal];
    [self.signingButton setTitle:title forState:UIControlStateHighlighted];
}

- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:CGRectZero];
    self.view.backgroundColor = [UIColor clearColor];

    // Load up blur view, and content view as needed.
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    self.backgroundView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.backgroundView.contentView.userInteractionEnabled = YES;

    [self.view addSubview:self.backgroundView];

    // Darkening view.
    self.darkeningView = [[UIView alloc] initWithFrame:CGRectZero];
    self.darkeningView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.2];
    self.darkeningView.userInteractionEnabled = NO;

    [self.backgroundView.contentView addSubview:self.darkeningView];

    // Content view
    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.cornerRadius = 12.5;
    self.contentView.backgroundColor = [UIColor whiteColor];
    self.contentView.userInteractionEnabled = YES;

    [self.view addSubview:self.contentView];

    [self _setupContentViewComponents];
}

- (void)_setupContentViewComponents {
    // Load components for the content view, from the application's info.

    // Icon
    [self _addApplicationIconComponent];

    // Title.
    [self _addApplicationNameComponent];

    // Bundle ID.
    [self _addApplicationBundleIdentifierComponent];

    // Signing button
    [self _addMajorButtonComponent];

    // Version
    [self _addApplicationVersionComponent];

    // Installed size
    [self _addApplicationInstalledSizeComponent];

    // Calendar & Gesture recognizers
    if ([self.application.class isEqual:[RPVApplication class]]) {
        [self _addCalendarComponent];

        UILongPressGestureRecognizer *longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleLongPressForInstalledApps:)];
        longPressGestureRecognizer.minimumPressDuration = 1.0;
        [self.view addGestureRecognizer:longPressGestureRecognizer];
    } else {
        UILongPressGestureRecognizer *longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleLongPressForIPA:)];
        longPressGestureRecognizer.minimumPressDuration = 1.0;
        [self.view addGestureRecognizer:longPressGestureRecognizer];
    }

    // Progress bar etc
    [self _addProgressComponents];

    // Exit controls
    [self _addCloseControls];
}

- (void)_addApplicationNameComponent {
    self.applicationNameLabel = [[MarqueeLabel alloc] initWithFrame:CGRectZero];
    self.applicationNameLabel.text = [self.application applicationName];
    self.applicationNameLabel.textColor = [UIColor blackColor];
    self.applicationNameLabel.font = [UIFont systemFontOfSize:18.6 weight:UIFontWeightBold];

    // MarqueeLabel specific
    self.applicationNameLabel.fadeLength = 8.0;
    self.applicationNameLabel.trailingBuffer = 10.0;

    [self.contentView addSubview:self.applicationNameLabel];
}

- (void)_addApplicationIconComponent {
    self.applicationIconView = [[UIImageView alloc] initWithImage:[self.application applicationIcon]];

    [self.contentView addSubview:self.applicationIconView];
}

- (void)_addApplicationBundleIdentifierComponent {
    self.applicationBundleIdentifierLabel = [[MarqueeLabel alloc] initWithFrame:CGRectZero];
    self.applicationBundleIdentifierLabel.text = [self.application bundleIdentifier];
    self.applicationBundleIdentifierLabel.textColor = [UIColor grayColor];
    self.applicationBundleIdentifierLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];

    // MarqueeLabel specific
    self.applicationBundleIdentifierLabel.fadeLength = 8.0;
    self.applicationBundleIdentifierLabel.trailingBuffer = 10.0;

    [self.contentView addSubview:self.applicationBundleIdentifierLabel];
}

- (void)_addApplicationVersionComponent {
    self.versionTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    self.versionTitle.text = @"Version";
    self.versionTitle.textColor = [UIColor grayColor];
    self.versionTitle.textAlignment = NSTextAlignmentCenter;
    self.versionTitle.font = [UIFont systemFontOfSize:14];

    [self.contentView addSubview:self.versionTitle];

    self.applicationVersionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.applicationVersionLabel.text = [self.application applicationVersion];
    self.applicationVersionLabel.textColor = [UIColor blackColor];
    self.applicationVersionLabel.textAlignment = NSTextAlignmentCenter;
    self.applicationVersionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];

    [self.contentView addSubview:self.applicationVersionLabel];
}

- (void)_addApplicationInstalledSizeComponent {
    self.installedSizeTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    self.installedSizeTitle.text = @"Size";
    self.installedSizeTitle.textColor = [UIColor grayColor];
    self.installedSizeTitle.textAlignment = NSTextAlignmentCenter;
    self.installedSizeTitle.font = [UIFont systemFontOfSize:14];

    [self.contentView addSubview:self.installedSizeTitle];

    self.applicationInstalledSizeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.applicationInstalledSizeLabel.text = [NSString stringWithFormat:@"%.2f MB", [self.application applicationInstalledSize].floatValue / 1024.0 / 1024.0];
    self.applicationInstalledSizeLabel.textColor = [UIColor blackColor];
    self.applicationInstalledSizeLabel.textAlignment = NSTextAlignmentCenter;
    self.applicationInstalledSizeLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];

    [self.contentView addSubview:self.applicationInstalledSizeLabel];
}

- (void)_addMajorButtonComponent {
    self.signingButton = [UIButton buttonWithType:UIButtonTypeCustom];

    [self.signingButton setTitle:@"BTN" forState:UIControlStateNormal];
    self.signingButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];

    self.signingButton.layer.cornerRadius = 14.0;
    self.signingButton.backgroundColor = [UIColor whiteColor];

    // Add gradient
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.signingButton.bounds;
    gradient.cornerRadius = self.signingButton.layer.cornerRadius;

    UIColor *startColor = [UIColor colorWithRed:147.0 / 255.0 green:99.0 / 255.0 blue:207.0 / 255.0 alpha:1.0];
    UIColor *endColor = [UIColor colorWithRed:116.0 / 255.0 green:158.0 / 255.0 blue:201.0 / 255.0 alpha:1.0];
    gradient.colors = @[(id)startColor.CGColor, (id)endColor.CGColor];
    gradient.startPoint = CGPointMake(1.0, 0.5);
    gradient.endPoint = CGPointMake(0.0, 0.5);

    [self.signingButton.layer insertSublayer:gradient atIndex:0];

    // Button colouration
    [self.signingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.signingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];

    [self.signingButton addTarget:self action:@selector(_userDidTapMajorButton:) forControlEvents:UIControlEventTouchUpInside];

    [self.contentView addSubview:self.signingButton];
}

- (void)_addCalendarComponent {
    self.calendarTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    self.calendarTitle.text = @"Expires";
    self.calendarTitle.textColor = [UIColor grayColor];
    self.calendarTitle.textAlignment = NSTextAlignmentCenter;
    self.calendarTitle.font = [UIFont systemFontOfSize:14];

    [self.contentView addSubview:self.calendarTitle];

    self.calendarController = [[RPVCalendarController alloc] initWithDate:[self.application applicationExpiryDate]];

    [self.contentView addSubview:self.calendarController.view];
}

- (void)_addCloseControls {
    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.alpha = 0.5;
    self.closeButton.clipsToBounds = YES;

    // Button image (cross)
    [self.closeButton setImage:[UIImage imageNamed:@"buttonClose"] forState:UIControlStateNormal];

    [self.closeButton addTarget:self action:@selector(_userDidTapCloseButton:) forControlEvents:UIControlEventTouchUpInside];

    self.closeGestureRecogniser = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_userDidTapToClose:)];
    [self.backgroundView.contentView addGestureRecognizer:self.closeGestureRecogniser];

    [self.view addSubview:self.closeButton];
}

- (void)_addProgressComponents {
    self.percentCompleteLabel = [[MarqueeLabel alloc] initWithFrame:CGRectZero];
    self.percentCompleteLabel.text = @"0% complete";
    self.percentCompleteLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.percentCompleteLabel.hidden = YES;
    self.percentCompleteLabel.textColor = [UIColor grayColor];

    // MarqueeLabel specific
    self.percentCompleteLabel.fadeLength = 8.0;
    self.percentCompleteLabel.trailingBuffer = 10.0;

    [self.contentView addSubview:self.percentCompleteLabel];

    self.progressBar = [[MBCircularProgressBarView alloc] initWithFrame:CGRectZero];

    self.progressBar.value = 0.0;
    self.progressBar.maxValue = 100.0;
    self.progressBar.showUnitString = NO;
    self.progressBar.showValueString = NO;
    self.progressBar.progressCapType = kCGLineCapRound;
    self.progressBar.emptyCapType = kCGLineCapRound;
    self.progressBar.progressLineWidth = 1.5;
    self.progressBar.progressColor = [UIColor darkGrayColor];
    self.progressBar.progressStrokeColor = [UIColor darkGrayColor];
    self.progressBar.emptyLineColor = [UIColor lightGrayColor];
    self.progressBar.backgroundColor = [UIColor clearColor];

    self.progressBar.hidden = YES;

    [self.contentView addSubview:self.progressBar];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // Layout blur, content, then the closing box.

    self.backgroundView.frame = self.view.bounds;
    self.darkeningView.frame = self.backgroundView.bounds;

    CGFloat itemInsetY = 25;
    CGFloat itemInsetX = 15;
    CGFloat innerItemInsetY = 7;
    CGFloat buttonTextMargin = 20;

    CGFloat y = itemInsetX;  // Ends up being used for contentView height.
    CGFloat contentViewWidth = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? [UIScreen mainScreen].bounds.size.width * 0.5 : [UIScreen mainScreen].bounds.size.width * 0.95;

    self.applicationIconView.frame = CGRectMake(15, y, 60, 60);

    // Signing button.
    [self.signingButton sizeToFit];
    self.signingButton.frame = CGRectMake(contentViewWidth - itemInsetX - self.signingButton.frame.size.width - (buttonTextMargin * 2), (y + self.applicationIconView.frame.size.height / 2) - 14, self.signingButton.frame.size.width + (buttonTextMargin * 2), 28);

    for (CALayer *layer in self.signingButton.layer.sublayers) {
        layer.frame = self.signingButton.bounds;
    }

    // Name and bundle ID are same height?
    CGFloat insetAfterIcon = self.applicationIconView.frame.origin.x + self.applicationIconView.frame.size.width + itemInsetX;
    self.applicationNameLabel.frame = CGRectMake(insetAfterIcon, y + 5, contentViewWidth - insetAfterIcon - itemInsetX * 2 - self.signingButton.frame.size.width, 30);

    // Bundle ID.
    self.applicationBundleIdentifierLabel.frame = CGRectMake(insetAfterIcon, y + 35, contentViewWidth - insetAfterIcon - itemInsetX * 2 - self.signingButton.frame.size.width, 20);

    // Progress bar and label.
    self.progressBar.frame = CGRectMake(self.applicationBundleIdentifierLabel.frame.origin.x, self.applicationBundleIdentifierLabel.frame.origin.y, 20, 20);
    self.percentCompleteLabel.frame = CGRectMake(self.applicationBundleIdentifierLabel.frame.origin.x + self.progressBar.frame.size.width + 5, self.applicationBundleIdentifierLabel.frame.origin.y, self.applicationBundleIdentifierLabel.frame.size.width - 5 - self.progressBar.frame.size.width, 20);

    y += 60 + itemInsetY;

    // Verison label

    CGFloat detailItemWidth = contentViewWidth / 3 - itemInsetX * 2;
    self.versionTitle.frame = CGRectMake(contentViewWidth / 2 - detailItemWidth - itemInsetX, y, detailItemWidth, 20);
    self.applicationVersionLabel.frame = CGRectMake(self.versionTitle.frame.origin.x, y + 20 + innerItemInsetY, detailItemWidth, 20);

    // Installed size

    self.installedSizeTitle.frame = CGRectMake(contentViewWidth / 2 + itemInsetX, y, detailItemWidth, 20);
    self.applicationInstalledSizeLabel.frame = CGRectMake(self.installedSizeTitle.frame.origin.x, y + 20 + innerItemInsetY, detailItemWidth, 20);

    y += 40 + itemInsetY + innerItemInsetY;

    // Calendar, only if not an IPA application
    if ([self.application.class isEqual:[RPVApplication class]]) {
        self.calendarTitle.frame = CGRectMake(itemInsetX, y, contentViewWidth - itemInsetX * 2, 20);
        self.calendarController.view.frame = CGRectMake(0, y + 20 + innerItemInsetY, contentViewWidth, [self.calendarController calendarHeight]);

        y += 20 + [self.calendarController calendarHeight] + itemInsetY + innerItemInsetY;
    }

    self.contentView.frame = CGRectMake(self.view.frame.size.width / 2 - contentViewWidth / 2, self.view.frame.size.height / 2 - y / 2, contentViewWidth, y);

    // Close button.
    self.closeButton.frame = CGRectMake(self.contentView.frame.origin.x, self.contentView.frame.origin.y - 35, 30, 30);
    self.closeButton.layer.cornerRadius = self.closeButton.frame.size.width / 2.0;
}

////////////////////////////////////////////////////////////////////////////////
// Animations
////////////////////////////////////////////////////////////////////////////////

- (void)animateForPresentation {
    self.contentView.frame = CGRectMake(self.contentView.frame.origin.x, self.view.frame.size.height, self.contentView.frame.size.width, self.contentView.frame.size.height);
    self.closeButton.frame = CGRectMake(self.closeButton.frame.origin.x, self.view.frame.size.height, self.closeButton.frame.size.width, self.closeButton.frame.size.height);
    self.view.alpha = 0.0;

    [UIView animateWithDuration:0.3
                          delay:0.0
         usingSpringWithDamping:0.765
          initialSpringVelocity:0.15
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         self.view.alpha = 1.0;
                         self.contentView.frame = CGRectMake(self.contentView.frame.origin.x, self.view.frame.size.height / 2 - self.contentView.frame.size.height / 2, self.contentView.frame.size.width, self.contentView.frame.size.height);
                         self.closeButton.frame = CGRectMake(self.closeButton.frame.origin.x, self.contentView.frame.origin.y - self.closeButton.frame.size.height - 5, self.closeButton.frame.size.width, self.closeButton.frame.size.height);
                     }
                     completion:^(BOOL finished){

                     }];
}

- (void)animateForDismissalWithCompletion:(void (^)(void))completionHandler {
    [UIView animateWithDuration:0.3
        delay:0.0
        options:UIViewAnimationOptionCurveEaseInOut
        animations:^{
            self.view.alpha = 0.0;
            self.closeButton.frame = CGRectMake(self.closeButton.frame.origin.x, self.view.frame.size.height, self.closeButton.frame.size.width, self.closeButton.frame.size.height);
            self.contentView.frame = CGRectMake(self.contentView.frame.origin.x, self.view.frame.size.height, self.contentView.frame.size.width, self.contentView.frame.size.height);
        }
        completion:^(BOOL finished) {
            if (finished) {
                self.contentView.transform = CGAffineTransformMakeScale(1.0, 1.0);

                completionHandler();
            }
        }];
}

////////////////////////////////////////////////////////////////////////////////
// Button callbacks
////////////////////////////////////////////////////////////////////////////////

- (void)_userDidTapCloseButton:(id)button {
    // animate out, and hide.
    [self animateForDismissalWithCompletion:^{
        [self removeFromParentViewController];
        [self.view removeFromSuperview];

        // Unregister for notifications
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }];
}

- (void)_userDidTapMajorButton:(id)button {
    if (self.warnUserOnResign) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Warning"
                             message:[NSString stringWithFormat:@"This will remove the current certificate of '%@', and replaces it with a new certificate from your Apple ID.\nThis may result in the loss of the app's saved settings and files.\n\nAre you sure you want to continue?", [self.application applicationName]]
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *continueButton = [UIAlertAction
            actionWithTitle:@"Continue"
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {
                        [self _initiateSigningForCurrentApplication];
                    }];

        UIAlertAction *cancelButton = [UIAlertAction
            actionWithTitle:@"Cancel"
                      style:UIAlertActionStyleCancel
                    handler:^(UIAlertAction *action){

                    }];

        [alert addAction:continueButton];
        [alert addAction:cancelButton];

        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self _initiateSigningForCurrentApplication];
    }
}

////////////////////////////////////////////////////////////////////////////////
// UILongPressGestureRecognizer callbacks
////////////////////////////////////////////////////////////////////////////////

- (void)_handleLongPressForInstalledApps:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        NSString *bundleIdentifierForApp = [self.application bundleIdentifier];
        LSApplicationProxy *selectedApp = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifierForApp];
        NSString *bundleLocation = [selectedApp bundleURL].path;
        NSString *dataLocation = [selectedApp containerURL].path;

        if (selectedApp != nil && self.percentCompleteLabel.hidden) {
            NSString *title = selectedApp.localizedName;
            NSString *message = [NSString stringWithFormat:@"Bundle ID: %@\nBundle: %@\n Data: %@", bundleIdentifierForApp, bundleLocation, dataLocation];
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Copy Bundle ID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                 UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                                 pasteboard.string = bundleIdentifierForApp;
                             }]];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Copy Bundle Location" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                 UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                                 pasteboard.string = bundleLocation;
                             }]];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Copy Data Location" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                 UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                                 pasteboard.string = dataLocation;
                             }]];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Show Entitlements" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                 RPVEntitlementsViewController *entitlementsViewController = [[RPVEntitlementsViewController alloc] init];
                                 UIWindow *alertWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

                                 entitlementsViewController.onDismiss = ^{
                                     [UIView animateWithDuration:0.25 animations:^{
                                         alertWindow.alpha = 0.0;
                                     } completion:^(BOOL finished) {
                                         if (finished) {
                                             [alertWindow setHidden:YES];
                                         }
                                     }];
                                 };

                                 alertWindow.rootViewController = entitlementsViewController;
                                 alertWindow.windowLevel = UIWindowLevelStatusBar;
                                 alertWindow.alpha = 0;
                                 [alertWindow setTintColor:[UIColor colorWithRed:147.0 / 255.0 green:99.0 / 255.0 blue:207.0 / 255.0 alpha:1.0]];

                                 entitlementsViewController.titleLabel.text = @"Entitlements";

                                 NSDictionary *infoplist = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundleLocation]];
                                 if (!infoplist || [infoplist allKeys].count == 0) return;
                                 NSString *binaryLocation = [bundleLocation stringByAppendingFormat:@"/%@", [infoplist objectForKey:@"CFBundleExecutable"]];
                                 [entitlementsViewController updateEntitlementsViewForBinaryAtLocation:binaryLocation];

                                 [alertWindow makeKeyAndVisible];

                                 [UIView animateWithDuration:0.25 animations:^{
                                     alertWindow.alpha = 1.0;
                                 } completion:^(BOOL finished){
                                 }];
                             }]];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Uninstall" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                                 BOOL result = [[RPVApplicationSigning sharedInstance] removeApplicationWithBundleIdentifier:bundleIdentifierForApp];
                                 if (result && ![[LSApplicationProxy applicationProxyForIdentifier:bundleIdentifierForApp] isInstalled]) {
                                     UIAlertController *doneAlertVC = [UIAlertController alertControllerWithTitle:nil
                                                                                                          message:[NSString stringWithFormat:@"Successfully uninstalled %@", selectedApp.localizedName]
                                                                                                   preferredStyle:UIAlertControllerStyleAlert];
                                     [self presentViewController:doneAlertVC animated:YES completion:nil];
                                     dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                         [self _userDidTapCloseButton:nil];
                                         [doneAlertVC dismissViewControllerAnimated:YES completion:nil];
                                     });
                                     [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"jp.soh.reprovision.ios/resigningThresholdDidChange" object:nil]];  // Fake notification to update table
                                 } else {
                                     // Error
                                     UIAlertController *errorAlertVC = [UIAlertController alertControllerWithTitle:nil
                                                                                                           message:[NSString stringWithFormat:@"Failed to uninstall %@", selectedApp.localizedName]
                                                                                                    preferredStyle:UIAlertControllerStyleAlert];
                                     [self presentViewController:errorAlertVC animated:YES completion:nil];
                                     dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                         [errorAlertVC dismissViewControllerAnimated:YES completion:nil];
                                     });
                                 }
                             }]];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){
                                       }]];

            [self presentViewController:alertController animated:YES completion:nil];
        }
    }
}

- (void)_handleLongPressForIPA:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        if (self.percentCompleteLabel.hidden) {
            NSString *bundleIdentifierForApp = [self.application bundleIdentifier];
            NSString *applicationName = self.application.applicationName;
            NSString *title = applicationName;
            NSString *message = [NSString stringWithFormat:@"Bundle ID: %@", bundleIdentifierForApp];
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Copy Bundle ID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                 UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                                 pasteboard.string = bundleIdentifierForApp;
                             }]];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Show Entitlements" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                 RPVEntitlementsViewController *entitlementsViewController = [[RPVEntitlementsViewController alloc] init];
                                 UIWindow *alertWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

                                 entitlementsViewController.onDismiss = ^{
                                     [UIView animateWithDuration:0.25 animations:^{
                                         alertWindow.alpha = 0.0;
                                     } completion:^(BOOL finished) {
                                         if (finished) {
                                             [alertWindow setHidden:YES];
                                         }
                                     }];
                                 };

                                 alertWindow.rootViewController = entitlementsViewController;
                                 alertWindow.windowLevel = UIWindowLevelStatusBar;
                                 alertWindow.alpha = 0;
                                 [alertWindow setTintColor:[UIColor colorWithRed:147.0 / 255.0 green:99.0 / 255.0 blue:207.0 / 255.0 alpha:1.0]];

                                 entitlementsViewController.titleLabel.text = @"Entitlements";

                                 NSData *binaryData = [(RPVIpaBundleApplication *)self.application _loadFileWithFormat:[NSString stringWithFormat:@"Payload/*/%@", applicationName] fromIPA:[(RPVIpaBundleApplication *)[self application] cachedURL] multipleCandiateChooser:^NSString *(NSArray *candidates) {
                                     return [candidates firstObject];
                                 }];
                                 NSString *binaryLocation = [NSString stringWithFormat:@"/tmp/%@", applicationName];
                                 [binaryData writeToURL:[NSURL fileURLWithPath:binaryLocation] atomically:YES];

                                 [entitlementsViewController updateEntitlementsViewForBinaryAtLocation:binaryLocation];

                                 [alertWindow makeKeyAndVisible];

                                 [UIView animateWithDuration:0.25 animations:^{
                                     alertWindow.alpha = 1.0;
                                 } completion:^(BOOL finished){
                                 }];
                             }]];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){
                                       }]];

            [self presentViewController:alertController animated:YES completion:nil];
        }
    }
}


////////////////////////////////////////////////////////////////////////////////
// UITapGesture callbacks
////////////////////////////////////////////////////////////////////////////////

- (void)_userDidTapToClose:(id)sender {
    [self _userDidTapCloseButton:nil];
}

////////////////////////////////////////////////////////////////////////////////
// Application signing callbacks
////////////////////////////////////////////////////////////////////////////////

- (void)_initiateSigningForCurrentApplication {
    // Start signing this one app.
    [[RPVApplicationSigning sharedInstance] resignSpecificApplications:@[self.application]
                                                            withTeamID:[RPVResources getTeamID]
                                                              username:[RPVResources getUsername]
                                                              password:[RPVResources getPassword]];
}

- (void)_onSigningStatusUpdate:(NSNotification *)notification {
    NSString *bundleIdentifier = [[notification userInfo] objectForKey:@"bundleIdentifier"];
    int percent = [[[notification userInfo] objectForKey:@"percent"] intValue];

    if ([bundleIdentifier isEqualToString:[self.application bundleIdentifier]]) {
        [self _signingProgressDidUpdate:percent];
    }
}

- (void)_signingProgressDidUpdate:(int)percent {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (percent > 0) {
            self.percentCompleteLabel.hidden = NO;
            self.progressBar.hidden = NO;

            self.signingButton.alpha = 0.5;
            self.signingButton.enabled = NO;

            self.applicationBundleIdentifierLabel.hidden = YES;

            // If necessary, "lock" user exit controls.
            if (self.lockWhenInstalling) {
                self.closeButton.hidden = YES;
                self.closeGestureRecogniser.enabled = NO;
            }
        }

        // Update progess bar!
        [UIView animateWithDuration:percent == 0 ? 0.0 : 0.35
            delay:0.0
            options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                self.progressBar.value = percent;
                self.percentCompleteLabel.text = [NSString stringWithFormat:@"%d%% complete", percent];
            } completion:^(BOOL finished) {
                if (finished && percent == 100) {
                    self.percentCompleteLabel.hidden = YES;
                    self.progressBar.hidden = YES;

                    self.signingButton.alpha = 1.0;
                    self.signingButton.enabled = YES;

                    self.applicationBundleIdentifierLabel.hidden = NO;

                    // If necessary, "unlock" user exit controls.
                    if (self.lockWhenInstalling) {
                        self.closeButton.hidden = NO;
                        self.closeGestureRecogniser.enabled = YES;
                    }

                    // Close the view if percentage is 100.
                    [self _userDidTapCloseButton:nil];
                }
            }];
    });
}


@end
