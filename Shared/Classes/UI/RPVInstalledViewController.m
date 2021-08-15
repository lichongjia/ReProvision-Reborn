//
//  RPVInstalledViewController.m
//  iOS
//
//  Created by Matt Clarke on 03/07/2018.
//  Copyright © 2018 Matt Clarke. All rights reserved.
//

#import "RPVInstalledViewController.h"
#import "RPVInstalledMainHeaderView.h"
#import "RPVResources.h"

#import "RPVEntitlementsViewController.h"

#import "RPVApplication.h"
#import "RPVApplicationDatabase.h"
#import "RPVErrors.h"
#import "RPVNotificationManager.h"

#import "RPVInstalledCollectionViewCell.h"
#import "RPVInstalledTableViewCell.h"

#import "RPVApplicationDetailController.h"

#import "RPVIpaBundleApplication.h"

#if TARGET_OS_TV
#import "RPVStickyScrollView.h"
#else
#import "RPVAppIdsLabel.h"
#endif

// Fake data source stuff...
#if TARGET_OS_TV
#define USE_FAKE_DATA 1
#else
#define USE_FAKE_DATA 0
#endif

#define TABLE_VIEWS_INSET 20

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
+ (instancetype)applicationProxyForIdentifier:(NSString *)arg1;
@end

@interface RPVInstalledViewController ()

// Views
@property (nonatomic, strong) UIScrollView *rootScrollView;

@property (nonatomic, strong) UIView *topBackgroundView;
@property (nonatomic, strong) CAGradientLayer *topBackgroundGradientLayer;

@property (nonatomic, strong) RPVInstalledMainHeaderView *mainHeaderView;
@property (nonatomic, strong) UICollectionView *expiringCollectionView;
@property (nonatomic, strong) UITableView *recentTableView;
@property (nonatomic, strong) UITableView *otherApplicationsTableView;
@property (nonatomic, strong) RPVAppIdsLabel *appIdsLabel;

#if TARGET_OS_TV
@property (nonatomic, strong) RPVInstalledSectionHeaderViewController *expiringSectionHeader;
@property (nonatomic, strong) RPVInstalledSectionHeaderViewController *recentSectionHeader;
@property (nonatomic, strong) RPVInstalledSectionHeaderViewController *otherApplicationsSectionHeader;
#else
@property (nonatomic, strong) RPVInstalledSectionHeaderView *expiringSectionHeaderView;
@property (nonatomic, strong) RPVInstalledSectionHeaderView *recentSectionHeaderView;
@property (nonatomic, strong) RPVInstalledSectionHeaderView *otherApplicationsSectionHeaderView;
#endif

// Data sources
@property (nonatomic, strong) NSMutableArray *expiringSoonDataSource;
@property (nonatomic, strong) NSMutableArray *recentlySignedDataSource;
@property (nonatomic, strong) NSMutableArray *otherApplicationsDataSource;

@property (nonatomic, strong) NSMutableDictionary *currentSigningProgress;
@end

@implementation RPVInstalledViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.

    [self.expiringCollectionView registerClass:[RPVInstalledCollectionViewCell class] forCellWithReuseIdentifier:@"installed.cell"];
    [self.recentTableView registerClass:[RPVInstalledTableViewCell class] forCellReuseIdentifier:@"installed.cell"];

    self.currentSigningProgress = [NSMutableDictionary dictionary];

    [[RPVApplicationSigning sharedInstance] addSigningUpdatesObserver:self];

    // Reload data sources.
    [self _reloadDataSources];
#if TARGET_OS_TV
    [self.recentSectionHeader requestNewButtonEnabledState];
    [self.expiringSectionHeader requestNewButtonEnabledState];
    [self.otherApplicationsSectionHeader requestNewButtonEnabledState];
#else
    [self.recentSectionHeaderView requestNewButtonEnabledState];
    [self.expiringSectionHeaderView requestNewButtonEnabledState];
    [self.otherApplicationsSectionHeaderView requestNewButtonEnabledState];
#endif

    // Handle reloading data when the user has signed in.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reloadDataForUserDidSignIn:) name:@"jp.soh.reprovision.ios/userDidSignIn" object:nil];

    // Reload data when the resign threshold changes.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reloadDataForUserDidSignIn:) name:@"jp.soh.reprovision.ios/resigningThresholdDidChange" object:nil];

#if TARGET_OS_TV
    [[self navigationItem] setTitle:@"Installed"];
#endif
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    // Dispose of any resources that can be recreated.
}

- (void)loadView {
    [super loadView];

    // Root view is a scrollview, sized to mainHeader + header + expiringcollection + header + tableview (no scrolling)
#if TARGET_OS_TV
    self.rootScrollView = [[RPVStickyScrollView alloc] initWithFrame:CGRectZero];
    self.rootScrollView.backgroundColor = [UIColor clearColor];
#else
    self.rootScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.rootScrollView.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
#endif
    self.rootScrollView.delegate = self;
    self.rootScrollView.alwaysBounceVertical = YES;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        self.rootScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
#endif
    [self.view addSubview:self.rootScrollView];

    // Background view for fancy UI
    self.topBackgroundView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.rootScrollView addSubview:self.topBackgroundView];

    self.topBackgroundGradientLayer = [CAGradientLayer layer];
    self.topBackgroundGradientLayer.frame = CGRectZero;

    UIColor *startColor = [UIColor colorWithRed:147.0 / 255.0 green:99.0 / 255.0 blue:207.0 / 255.0 alpha:1.0];
    UIColor *endColor = [UIColor colorWithRed:116.0 / 255.0 green:158.0 / 255.0 blue:201.0 / 255.0 alpha:1.0];
    self.topBackgroundGradientLayer.colors = @[(id)startColor.CGColor, (id)endColor.CGColor];
    self.topBackgroundGradientLayer.startPoint = CGPointMake(0.75, 0.75);
    self.topBackgroundGradientLayer.endPoint = CGPointMake(0.25, 0.25);

    [self.topBackgroundView.layer insertSublayer:self.topBackgroundGradientLayer atIndex:0];

    // Topmost header for date and title
#if !TARGET_OS_TV
    self.mainHeaderView = [[RPVInstalledMainHeaderView alloc] initWithFrame:CGRectZero];
    self.mainHeaderView.delegate = self;
    [self.mainHeaderView configureWithTitle:@"Installed"];
    [self.rootScrollView addSubview:self.mainHeaderView];
#endif

    // Section header for expiring apps
#if TARGET_OS_TV
    self.expiringSectionHeader = [[RPVInstalledSectionHeaderViewController alloc] init];
    [self.expiringSectionHeader configureWithTitle:@"Expiring Soon" buttonLabel:@"Sign" section:1 andDelegate:self];
    self.expiringSectionHeader.invertColours = YES;
    [self.rootScrollView addSubview:self.expiringSectionHeader.view];
#else
    self.expiringSectionHeaderView = [[RPVInstalledSectionHeaderView alloc] initWithFrame:CGRectZero];
    [self.expiringSectionHeaderView configureWithTitle:@"Expiring Soon" buttonLabel:@"Sign" section:1 andDelegate:self];
    self.expiringSectionHeaderView.invertColours = YES;
    [self.rootScrollView addSubview:self.expiringSectionHeaderView];
#endif

    // Collectionview for expiring items
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = [self _collectionCellSize];
#if TARGET_OS_TV
    layout.minimumLineSpacing = 22;
#else
    layout.minimumLineSpacing = 15;
#endif
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;

    self.expiringCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.expiringCollectionView.backgroundColor = [UIColor clearColor];
    self.expiringCollectionView.delegate = self;
    self.expiringCollectionView.dataSource = self;
#if TARGET_OS_TV
    self.expiringCollectionView.clipsToBounds = NO;
#endif
    [self.rootScrollView addSubview:self.expiringCollectionView];

    // Section header for recent items
#if TARGET_OS_TV
    self.recentSectionHeader = [[RPVInstalledSectionHeaderViewController alloc] init];
    [self.recentSectionHeader configureWithTitle:@"Recently Signed" buttonLabel:@"Sign" section:2 andDelegate:self];
    self.recentSectionHeader.invertColours = NO;
    [self.rootScrollView addSubview:self.recentSectionHeader.view];
#else
    self.recentSectionHeaderView = [[RPVInstalledSectionHeaderView alloc] initWithFrame:CGRectZero];
    [self.recentSectionHeaderView configureWithTitle:@"Recently Signed" buttonLabel:@"Sign" section:2 andDelegate:self];
    self.recentSectionHeaderView.invertColours = NO;
    [self.rootScrollView addSubview:self.recentSectionHeaderView];
#endif

    // Table View for recent items.
#if TARGET_OS_TV
    self.recentTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
#else
    self.recentTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
#endif
    self.recentTableView.delegate = self;
    self.recentTableView.dataSource = self;
    self.recentTableView.scrollEnabled = NO;
    self.recentTableView.backgroundColor = [UIColor clearColor];
#if TARGET_OS_TV
#else
    self.recentTableView.separatorColor = [UIColor clearColor];
#endif
    [self.rootScrollView addSubview:self.recentTableView];

    // Section header for other apps
#if TARGET_OS_TV
    self.otherApplicationsSectionHeader = [[RPVInstalledSectionHeaderViewController alloc] init];
    [self.otherApplicationsSectionHeader configureWithTitle:@"Other Applications" buttonLabel:@"Add" section:3 andDelegate:self];
    self.otherApplicationsSectionHeader.invertColours = NO;
    [self.rootScrollView addSubview:self.otherApplicationsSectionHeader.view];
#else
    self.otherApplicationsSectionHeaderView = [[RPVInstalledSectionHeaderView alloc] initWithFrame:CGRectZero];
    [self.otherApplicationsSectionHeaderView configureWithTitle:@"Other Applications" buttonLabel:@"Add" section:3 andDelegate:self];
    self.otherApplicationsSectionHeaderView.invertColours = NO;
    self.otherApplicationsSectionHeaderView.showButton = NO;
    [self.rootScrollView addSubview:self.otherApplicationsSectionHeaderView];
#endif

    // Table view for applications that are sideloaded on another Team ID.
#if TARGET_OS_TV
    self.otherApplicationsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
#else
    self.otherApplicationsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
#endif
    self.otherApplicationsTableView.delegate = self;
    self.otherApplicationsTableView.dataSource = self;
    self.otherApplicationsTableView.scrollEnabled = NO;
    self.otherApplicationsTableView.backgroundColor = [UIColor clearColor];
#if TARGET_OS_TV
#else
    self.otherApplicationsTableView.separatorColor = [UIColor clearColor];
#endif
    self.otherApplicationsTableView.allowsSelectionDuringEditing = YES;
    [self.rootScrollView addSubview:self.otherApplicationsTableView];

    // UILabel to show the count of App IDs
#if TARGET_OS_TV
#else
    self.appIdsLabel = [[RPVAppIdsLabel alloc] init];
    [self.rootScrollView addSubview:self.appIdsLabel];
#endif

    // Add long press gesture recognizer to table view(s)
#if TARGET_OS_TV
#else
    UILongPressGestureRecognizer *longPressGestureRecognizerForRecent = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressOnTableView:)];
    longPressGestureRecognizerForRecent.minimumPressDuration = 0.75;
    [self.recentTableView addGestureRecognizer:longPressGestureRecognizerForRecent];

    UILongPressGestureRecognizer *longPressGestureRecognizerForOther = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressOnTableView:)];
    longPressGestureRecognizerForOther.minimumPressDuration = 0.75;
    [self.otherApplicationsTableView addGestureRecognizer:longPressGestureRecognizerForOther];
#endif
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

#if TARGET_OS_TV
    self.rootScrollView.frame = self.view.bounds;
#else
    CGFloat rootHeight = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? self.view.bounds.size.height : self.view.bounds.size.height - [(UITabBarController *)self.parentViewController tabBar].frame.size.height;
    self.rootScrollView.frame = CGRectMake(0, 0, self.view.bounds.size.width, rootHeight);
#endif

#if TARGET_OS_TV
    CGFloat yOffset = 160.0;  // top tab bar

    CGFloat mainHeaderHeight = 0;
    CGFloat sectionHeaderHeight = 80;
#else
    CGFloat yOffset = [UIApplication sharedApplication].statusBarFrame.size.height + 10.0;
    CGFloat mainHeaderHeight = 80;
    CGFloat sectionHeaderHeight = 50;
#endif

    self.mainHeaderView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, mainHeaderHeight);

    yOffset += mainHeaderHeight + 5;

#if TARGET_OS_TV
    self.expiringSectionHeader.view.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
#else
    self.expiringSectionHeaderView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
#endif

    yOffset += sectionHeaderHeight;

    CGFloat tvOSInset = 0.0;
#if TARGET_OS_TV
    tvOSInset = 20.0;
#endif
    if (self.expiringSoonDataSource.count == 0) {
        self.expiringCollectionView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, [self _tableViewCellHeight]);
        [self.expiringCollectionView.collectionViewLayout invalidateLayout];
    } else {
        self.expiringCollectionView.frame = CGRectMake(0 - tvOSInset, yOffset, self.view.bounds.size.width + tvOSInset, [self _collectionCellSize].height + 50);
    }

    yOffset += self.expiringCollectionView.frame.size.height;  // CollectionView's insets handle extra offsetting.

    // Top background view.
    self.topBackgroundView.frame = CGRectMake(0, 0, self.view.bounds.size.width, yOffset);

    // Stop implicit animation.
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    self.topBackgroundGradientLayer.frame = self.topBackgroundView.bounds;
    [CATransaction commit];

    yOffset += 5;

#if TARGET_OS_TV
    self.recentSectionHeader.view.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
#else
    self.recentSectionHeaderView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
#endif

    yOffset += sectionHeaderHeight + 5;

    // Table View's frame height is: insetTop + (n*itemheight) + insetBottom
#if TARGET_OS_TV
    CGFloat height = [self tableView:self.recentTableView numberOfRowsInSection:0] * [self _tableViewCellHeight];
    height += [self tableView:self.recentTableView numberOfRowsInSection:0] * 20.0;  // interim insets

    // Grouped header insets
    yOffset -= 20.0;
#else
    CGFloat height = [self tableView:self.recentTableView numberOfRowsInSection:0] * [self _tableViewCellHeight];
#endif
    self.recentTableView.frame = CGRectMake(TABLE_VIEWS_INSET, yOffset, self.view.bounds.size.width - (TABLE_VIEWS_INSET * 2), height);
    self.recentTableView.contentSize = CGSizeMake(self.view.bounds.size.width - (TABLE_VIEWS_INSET * 2), height);

    yOffset += height + 15;

    // Other applications table view.
#if TARGET_OS_TV
    self.otherApplicationsSectionHeader.view.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
#else
    self.otherApplicationsSectionHeaderView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
#endif

    yOffset += sectionHeaderHeight + 5;

    // Table View's frame height is: insetTop + (n*itemheight) + insetBottom
#if TARGET_OS_TV
    CGFloat otherAppsHeight = [self tableView:self.otherApplicationsTableView numberOfRowsInSection:0] * [self _tableViewCellHeight];
    otherAppsHeight += [self tableView:self.otherApplicationsTableView numberOfRowsInSection:0] * 20.0;  // interim insets

    // Grouped header insets
    yOffset -= 30.0;
#else
    CGFloat otherAppsHeight = [self tableView:self.otherApplicationsTableView numberOfRowsInSection:0] * [self _tableViewCellHeight];
#endif
    self.otherApplicationsTableView.frame = CGRectMake(TABLE_VIEWS_INSET, yOffset, self.view.bounds.size.width - (TABLE_VIEWS_INSET * 2), otherAppsHeight);
    self.otherApplicationsTableView.contentSize = CGSizeMake(self.view.bounds.size.width - (TABLE_VIEWS_INSET * 2), otherAppsHeight);

    yOffset += otherAppsHeight + 15;

#if TARGET_OS_TV
#else
    self.appIdsLabel.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
    yOffset += sectionHeaderHeight + 5;
#endif

    // Finally, set content size for overall scrolling region.
    self.rootScrollView.contentSize = CGSizeMake(self.view.bounds.size.width, yOffset);

#if TARGET_OS_TV
    [self.rootScrollView setContentOffset:CGPointMake(0, 20) animated:NO];
#endif
}

#if TARGET_OS_TV
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    // Check for tabbar hide and show!
    static NSString *kUITabBarButtonClassName = @"UITabBarButton";

    NSString *prevFocusViewClassName = NSStringFromClass([context.previouslyFocusedView class]);
    NSString *nextFocusedView = NSStringFromClass([context.nextFocusedView class]);

    RPVStickyScrollView *stickyScrollView = (RPVStickyScrollView *)self.rootScrollView;

    if (![prevFocusViewClassName isEqualToString:kUITabBarButtonClassName] &&
        [nextFocusedView isEqualToString:kUITabBarButtonClassName]) {
        stickyScrollView.stickyYPosition = 20.0;
        [coordinator addCoordinatedAnimations:^{
            [stickyScrollView setContentOffset:CGPointMake(0, 20.0)];
        } completion:^{
        }];
    } else {
        stickyScrollView.stickyYPosition = 140.0;
        [coordinator addCoordinatedAnimations:^{
            if (stickyScrollView.contentOffset.y < 140.0) [stickyScrollView setContentOffset:CGPointMake(0, 140.0)];
        } completion:^{
        }];
    }
}

#endif

- (CGSize)_collectionCellSize {
#if TARGET_OS_TV
    return CGSizeMake(400, 350);

#else
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? CGSizeMake(195, 183) : CGSizeMake(130, 122);

#endif
}

- (CGFloat)_tableViewCellHeight {
#if TARGET_OS_TV
    return 120;

#else
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 95 : 75;

#endif
}

// Status bar colouration
#if !TARGET_OS_TV
- (UIStatusBarStyle)preferredStatusBarStyle {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? UIStatusBarStyleDefault : UIStatusBarStyleLightContent;
}

#endif

//////////////////////////////////////////////////////////////////////////////////
// Data sources.
//////////////////////////////////////////////////////////////////////////////////

- (void)_reloadDataForUserDidSignIn:(id)sender {
    [self _reloadDataSources];

    // Reload header enabled states
#if TARGET_OS_TV
    [self.recentSectionHeader requestNewButtonEnabledState];
    [self.expiringSectionHeader requestNewButtonEnabledState];
    [self.otherApplicationsSectionHeader requestNewButtonEnabledState];
#else
    [self.recentSectionHeaderView requestNewButtonEnabledState];
    [self.expiringSectionHeaderView requestNewButtonEnabledState];
    [self.otherApplicationsSectionHeaderView requestNewButtonEnabledState];
    [self.appIdsLabel updateText];
#endif
}

- (void)_reloadDataSources {
    NSMutableArray *expiringSoon = [NSMutableArray array];
    NSMutableArray *recentlySigned = [NSMutableArray array];

    if (!USE_FAKE_DATA) {
        NSDate *now = [NSDate date];
        int thresholdForExpiration = [RPVResources thresholdForResigning];  // days

        NSDate *expirationDate = [now dateByAddingTimeInterval:60 * 60 * 24 * thresholdForExpiration];

        if (![[RPVApplicationDatabase sharedInstance] getApplicationsWithExpiryDateBefore:&expiringSoon andAfter:&recentlySigned date:expirationDate forTeamID:[RPVResources getTeamID]]) {
            // :(
        } else {
            self.expiringSoonDataSource = expiringSoon;
            self.recentlySignedDataSource = recentlySigned;

            // Reload the collection view and table view.
            [self.expiringCollectionView reloadData];
            [self.recentTableView reloadData];
        }

        // Also grab any other sideloaded applications
        self.otherApplicationsDataSource = [[[RPVApplicationDatabase sharedInstance] getAllSideloadedApplicationsNotMatchingTeamID:[RPVResources getTeamID]] mutableCopy];

        // Ensure they all actually have a mobileprovision!
        for (RPVApplication *application in [self.otherApplicationsDataSource copy]) {
            if (![application hasEmbeddedMobileprovision]) [self.otherApplicationsDataSource removeObject:application];
        }

        [self.otherApplicationsTableView reloadData];
    } else {
        [self _debugCreateFakeDataSources];

        // Reload the collection view and table views.
        [self.expiringCollectionView reloadData];
        [self.recentTableView reloadData];
        [self.otherApplicationsTableView reloadData];
    }

    // Relayout for any changes!
    [self.view setNeedsLayout];

    // Set the sideloaded apps table to be editing if necessary.
    // [self.otherApplicationsTableView setEditing:self.otherApplicationsDataSource.count > 0 animated:NO];
}

- (void)_debugCreateFakeDataSources {
    self.expiringSoonDataSource = [NSMutableArray array];
    self.recentlySignedDataSource = [NSMutableArray array];
    self.otherApplicationsDataSource = [NSMutableArray array];

    for (int i = 0; i < 2; i++) {
#if TARGET_OS_TV
        LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:@"jp.soh.reprovision.tvos"];
#else
        LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:@"jp.soh.reprovision.ios"];
#endif
        RPVApplication *application = [[RPVApplication alloc] initWithApplicationProxy:proxy];

        [self.recentlySignedDataSource addObject:application];
        [self.expiringSoonDataSource addObject:application];
        [self.otherApplicationsDataSource addObject:application];
    }
}

//////////////////////////////////////////////////////////////////////////////////
// Scroll View delegate methods.
//////////////////////////////////////////////////////////////////////////////////

// Gives the effect that the top area goes infinitely upwards
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = scrollView.contentOffset.y;

    CGFloat totalTopAreaHeight = self.expiringCollectionView.frame.origin.y + self.expiringCollectionView.frame.size.height;

    if (offsetY < 0) {
        totalTopAreaHeight += fabs(offsetY);

        self.topBackgroundView.frame = CGRectMake(0, offsetY, self.view.frame.size.width, totalTopAreaHeight);
    } else {
        self.topBackgroundView.frame = CGRectMake(0, 0, self.view.frame.size.width, totalTopAreaHeight);
    }

    // Really, Apple? Animating frame change implcitly?
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];

    self.topBackgroundGradientLayer.frame = self.topBackgroundView.bounds;

    [CATransaction commit];
}

//////////////////////////////////////////////////////////////////////////////////
// Collection View delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RPVInstalledCollectionViewCell *cell = (RPVInstalledCollectionViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:@"installed.cell" forIndexPath:indexPath];

    RPVApplication *application;
    NSString *fallbackString = @"";
    if (self.expiringSoonDataSource.count > 0)
        application = [self.expiringSoonDataSource objectAtIndex:indexPath.row];
    else
        fallbackString = @"No applications are expiring soon";

    [cell configureWithApplication:application fallbackDisplayName:fallbackString andExpiryDate:[application applicationExpiryDate]];

    return cell;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.expiringSoonDataSource.count > 0 ? self.expiringSoonDataSource.count : 1;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(0, 20, 15, 20);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGSize size = self.expiringSoonDataSource.count > 0 ? [(UICollectionViewFlowLayout *)collectionViewLayout itemSize] : CGSizeMake(self.view.frame.size.width - 40, 50);
    if (size.width <= 0) {
        size.width = CGRectGetWidth([[UIScreen mainScreen] bounds]) - 40;
    }

    return size;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    // Show detail view
    if (self.expiringSoonDataSource.count > 0) {
        RPVApplication *application = [self.expiringSoonDataSource objectAtIndex:indexPath.row];
        NSString *buttonTitle = @"Sign";

        [self _showApplicationDetailController:application withButtonTitle:buttonTitle isDestructiveResign:NO];
    }
}

//////////////////////////////////////////////////////////////////////////////////
// Table View delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([tableView isEqual:self.recentTableView])
        return self.recentlySignedDataSource.count > 0 ? self.recentlySignedDataSource.count : 1;
    else
        return self.otherApplicationsDataSource.count > 0 ? self.otherApplicationsDataSource.count : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RPVInstalledTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"installed.cell"];

    if (!cell) {
        cell = [[RPVInstalledTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"installed.cell"];
    }

    RPVApplication *application;
    NSString *fallbackString = @"";
    if ([tableView isEqual:self.recentTableView]) {
        if (self.recentlySignedDataSource.count > 0)
            application = [self.recentlySignedDataSource objectAtIndex:indexPath.row];
        else
            fallbackString = @"No applications are recently signed";
    } else {
        if (self.otherApplicationsDataSource.count > 0)
            application = [self.otherApplicationsDataSource objectAtIndex:indexPath.row];
        else
            fallbackString = @"No other sideloaded applications";
    }

    [cell configureWithApplication:application fallbackDisplayName:fallbackString andExpiryDate:[application applicationExpiryDate]];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self _tableViewCellHeight];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    RPVApplication *application;
    NSString *buttonTitle = @"";
    BOOL isDestructiveResign = NO;
    if ([tableView isEqual:self.otherApplicationsTableView] && (self.otherApplicationsDataSource.count > 0)) {
        buttonTitle = @"ADD";
        isDestructiveResign = YES;
        application = [self.otherApplicationsDataSource objectAtIndex:indexPath.row];
    } else if ([tableView isEqual:self.recentTableView] && (self.recentlySignedDataSource.count > 0)) {
        buttonTitle = @"SIGN";
        application = [self.recentlySignedDataSource objectAtIndex:indexPath.row];
    } else {
        return;
    }

    [self _showApplicationDetailController:application withButtonTitle:buttonTitle isDestructiveResign:isDestructiveResign];
}

- (void)_showApplicationDetailController:(RPVApplication *)application withButtonTitle:(NSString *)buttonTitle isDestructiveResign:(BOOL)isDestructiveResign {
    RPVApplicationDetailController *detailController = [[RPVApplicationDetailController alloc] initWithApplication:application];
    detailController.warnUserOnResign = isDestructiveResign;

    // Update with current states.
    [detailController setButtonTitle:buttonTitle];
    if ([[self.currentSigningProgress allKeys] containsObject:[application bundleIdentifier]]) {
        int currentPercent = [[self.currentSigningProgress objectForKey:[application bundleIdentifier]] intValue];
        [detailController setCurrentSigningPercent:currentPercent];
    }

    // Add to the rootViewController of the application, as an effective overlay.
    detailController.view.alpha = 0.0;

    UIViewController *rootController = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootController addChildViewController:detailController];
    [rootController.view addSubview:detailController.view];

    detailController.view.frame = rootController.view.bounds;

    // Animate in!
    [detailController animateForPresentation];
}

// We provide editing only for the other applications table.

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)arg2 {
    return NO;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

//////////////////////////////////////////////////////////////////////////////////
// Table View gesture methods.
//////////////////////////////////////////////////////////////////////////////////

- (void)handleLongPressOnTableView:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        // Table = sender.view
        UITableView *tableView = (UITableView *)sender.view;
        CGPoint touchPoint = [sender locationInView:tableView];
        NSIndexPath *indexPath = [tableView indexPathForRowAtPoint:touchPoint];
        if (indexPath != nil) {
            RPVInstalledTableViewCell *selectedCell = (RPVInstalledTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
            NSString *bundleIdentifierForSelectedApp = [selectedCell bundleIdentifier];

            LSApplicationProxy *selectedApp = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifierForSelectedApp];
            NSString *bundleLocation = [selectedApp bundleURL].path;
            NSString *dataLocation = [selectedApp containerURL].path;

            if (selectedApp != nil) {
                NSString *title = selectedApp.localizedName;
                NSString *message = [NSString stringWithFormat:@"Bundle ID: %@\nBundle: %@\n Data: %@", bundleIdentifierForSelectedApp, bundleLocation, dataLocation];
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];

                [alertController addAction:[UIAlertAction actionWithTitle:@"Copy Bundle ID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                     UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                                     pasteboard.string = bundleIdentifierForSelectedApp;
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
                                     BOOL result = [[RPVApplicationSigning sharedInstance] removeApplicationWithBundleIdentifier:bundleIdentifierForSelectedApp];
                                     if (result && ![[LSApplicationProxy applicationProxyForIdentifier:bundleIdentifierForSelectedApp] isInstalled]) {
                                         BOOL isRecent = [tableView isEqual:self.recentTableView];
                                         NSMutableArray *dataSourceForSelectedCell = isRecent ? self.recentlySignedDataSource : self.otherApplicationsDataSource;
                                         UITableView *collectionViewForSelectedCell = isRecent ? self.recentTableView : self.expiringCollectionView;
                                         [dataSourceForSelectedCell removeObject:[self _applicationForBundleIdentifier:bundleIdentifierForSelectedApp]];
                                         [collectionViewForSelectedCell reloadData];
                                         [self.view setNeedsLayout];
                                     } else {
                                         [selectedCell flashNotificationFailure];
                                     }
                                 }]];

                [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){
                                           }]];

                [self presentViewController:alertController animated:YES completion:nil];
            }
        }
    }
}

//////////////////////////////////////////////////////////////////////////////////
// Application Signing delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (void)applicationSigningDidStart {
}

- (void)applicationSigningUpdateProgress:(int)progress forBundleIdentifier:(NSString *)bundleIdentifier {
    [self.currentSigningProgress setObject:[NSNumber numberWithInt:progress] forKey:bundleIdentifier];

    if (progress == 100) {
        // Great success! Now we can move items around!
        dispatch_async(dispatch_get_main_queue(), ^{
            int oldDataSource = 0;
            RPVApplication *application;

            // Check expiring
            for (RPVApplication *app in self.expiringSoonDataSource) {
                if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
                    oldDataSource = 1;
                    application = app;
                    break;
                }
            }

            // Check recents
            for (RPVApplication *app in self.recentlySignedDataSource) {
                if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
                    oldDataSource = 2;
                    application = app;
                    break;
                }
            }

            // Check others
            for (RPVApplication *app in self.otherApplicationsDataSource) {
                if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
                    oldDataSource = 3;
                    application = app;
                    break;
                }
            }

            if (!application || ![[application locationOfApplicationOnFilesystem] checkResourceIsReachableAndReturnError:nil]) {
                // We've just had this called from installing an IPA.
                // Or, it is possible that user resigned the app signed with another account.
                // Reload data, and reload tables etc.

                [self _reloadDataSources];
#if TARGET_OS_TV
                [self.recentSectionHeader requestNewButtonEnabledState];
                [self.expiringSectionHeader requestNewButtonEnabledState];
                [self.otherApplicationsSectionHeader requestNewButtonEnabledState];
#else
                    [self.recentSectionHeaderView requestNewButtonEnabledState];
                    [self.expiringSectionHeaderView requestNewButtonEnabledState];
                    [self.otherApplicationsSectionHeaderView requestNewButtonEnabledState];
                    [self.appIdsLabel updateText];
#endif

                return;
            }

            // Move from the old data source to number 2.
            if (oldDataSource == 1) {
                // Batch updates, or straight-up reloadData.
                if (self.expiringSoonDataSource.count - 1 == 0) {
                    // Remove items from data source.
                    [self.expiringSoonDataSource removeObject:application];

                    [self.expiringCollectionView reloadData];
                } else {
                    [self.expiringCollectionView performBatchUpdates:^{
                        int index = (int)[self.expiringSoonDataSource indexOfObject:application];

                        // Remove items from data source.
                        [self.expiringSoonDataSource removeObjectAtIndex:index];

                        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                        [self.expiringCollectionView deleteItemsAtIndexPaths:[NSArray arrayWithObject:indexPath]];
                    } completion:^(BOOL finished){
                    }];
                }
            } else if (oldDataSource == 2) {
                // Effectively this will be a re-order, but oh well.
                // Newest items go at the bottom.

                // Just reload into no applications.
                if (self.recentlySignedDataSource.count - 1 == 0) {
                    [self.recentlySignedDataSource removeObject:application];
                    [self.recentTableView reloadData];
                } else {
                    [self.recentTableView beginUpdates];

                    int index = (int)[self.recentlySignedDataSource indexOfObject:application];
                    [self.recentlySignedDataSource removeObjectAtIndex:index];

                    // Delete the row from the table
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];

                    [self.recentTableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];

                    [self.recentTableView endUpdates];
                }
            } else if (oldDataSource == 3) {
                if (self.otherApplicationsDataSource.count - 1 == 0) {
                    [self.otherApplicationsDataSource removeObject:application];
                    [self.otherApplicationsTableView reloadData];
                } else {
                    [self.otherApplicationsTableView beginUpdates];

                    int index = (int)[self.otherApplicationsDataSource indexOfObject:application];
                    [self.otherApplicationsDataSource removeObjectAtIndex:index];

                    // Delete the row from the table
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];

                    [self.otherApplicationsTableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];

                    [self.otherApplicationsTableView endUpdates];
                }
            }

            // Now that we've removed the old application, create a new object for it to handle changes
            // in the bundle URL of the application on-disk.
            application = [[RPVApplicationDatabase sharedInstance] getApplicationWithBundleIdentifier:[application bundleIdentifier]];

            [self.recentTableView beginUpdates];

            // And add to source 2.
            [self.recentlySignedDataSource addObject:application];
            int index = (int)[self.recentlySignedDataSource indexOfObject:application];

            if (self.recentlySignedDataSource.count == 1) {
                // Reload the table instead to hide the no apps label
                [self.recentTableView reloadData];
            } else {
                // Add the row to the table
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];

                [self.recentTableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }

            [self.recentTableView endUpdates];

            // We now need to relayout everything!
            [self.view setNeedsLayout];

            // Flash notification on this cell.
            dispatch_async(dispatch_get_main_queue(), ^() {
                [[self _cellForApplication:application] flashNotificationSuccess];
            });
        });
    }
}

- (void)applicationSigningDidEncounterError:(NSError *)error forBundleIdentifier:(NSString *)bundleIdentifier {
    [self.currentSigningProgress setObject:@100 forKey:bundleIdentifier];

    // Find cell for this identifier.
    // Flash notification on this cell.
    dispatch_async(dispatch_get_main_queue(), ^() {
        [[self _cellForApplication:[self _applicationForBundleIdentifier:bundleIdentifier]] flashNotificationFailure];
    });
}

- (void)applicationSigningCompleteWithError:(NSError *)error {
}

- (void)startApplicationSigningForSection:(NSInteger)section {
    NSString *startAlertString = @"";

    switch (section) {
        case 1:
            startAlertString = @"Starting signing for applications expiring soon";
            break;

        case 2:
            startAlertString = @"Starting signing for all applications";
            break;

        case 3:
            startAlertString = @"Starting signing for other sideloaded applications";
            break;

        default:
            break;
    }

    [[RPVNotificationManager sharedInstance] sendNotificationWithTitle:@"DEBUG" body:startAlertString isDebugMessage:YES andNotificationID:nil];

    if (section == 3) {
        // Sign all other sideloaded applications to this Team ID.
        [[RPVApplicationSigning sharedInstance] resignSpecificApplications:self.otherApplicationsDataSource
                                                                withTeamID:[RPVResources getTeamID]
                                                                  username:[RPVResources getUsername]
                                                                  password:[RPVResources getPassword]];
    } else {
        [[RPVApplicationSigning sharedInstance] resignApplications:(section == 1)
                                            thresholdForExpiration:[RPVResources thresholdForResigning]
                                                        withTeamID:[RPVResources getTeamID]
                                                          username:[RPVResources getUsername]
                                                          password:[RPVResources getPassword]];
    }
}

- (RPVApplication *)_applicationForBundleIdentifier:(NSString *)bundleIdentifier {
    RPVApplication *application;

    // Check expiring
    for (RPVApplication *app in self.expiringSoonDataSource) {
        if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
            application = app;
            break;
        }
    }

    // Check recents
    for (RPVApplication *app in self.recentlySignedDataSource) {
        if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
            application = app;
            break;
        }
    }

    // Check others
    for (RPVApplication *app in self.otherApplicationsDataSource) {
        if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
            application = app;
            break;
        }
    }

    return application;
}

- (id)_cellForApplication:(RPVApplication *)application {
    NSString *bundleIdentifier = [application bundleIdentifier];

    // Check expiring
    for (RPVApplication *app in self.expiringSoonDataSource) {
        if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
            int index = (int)[self.expiringSoonDataSource indexOfObject:app];
            NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
            return [self.expiringCollectionView cellForItemAtIndexPath:path];
        }
    }

    // Check recents
    for (RPVApplication *app in self.recentlySignedDataSource) {
        if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
            int index = (int)[self.recentlySignedDataSource indexOfObject:app];
            NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
            return [self.recentTableView cellForRowAtIndexPath:path];
        }
    }

    // Check others
    for (RPVApplication *app in self.otherApplicationsDataSource) {
        if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
            int index = (int)[self.otherApplicationsDataSource indexOfObject:app];
            NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
            return [self.otherApplicationsTableView cellForRowAtIndexPath:path];
        }
    }

    return nil;
}

//////////////////////////////////////////////////////////////////////////////////
// Header View delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (void)didRecieveHeaderButtonInputWithSection:(NSInteger)section {
    // Handle button input!
    NSLog(@"Got input: %d", (int)section);
    [self startApplicationSigningForSection:section];
}

- (BOOL)isButtonEnabledForSection:(NSInteger)section {
    switch (section) {
        case 1:
            return self.expiringSoonDataSource.count > 0;

        case 2:
            return self.recentlySignedDataSource.count > 0;

        case 3:
            return self.otherApplicationsDataSource.count > 0;

        default:
            return NO;
    }
}

//////////////////////////////////////////////////////////////////////////////////
//  File Picker delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (void)installButtonTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    if (![[[url pathExtension] lowercaseString] isEqualToString:@"ipa"]) return;

    // Incoming URL is a fileURL!

    // Create an RPVApplication for this incoming .ipa, and display the installation popup.
    RPVIpaBundleApplication *ipaApplication = [[RPVIpaBundleApplication alloc] initWithIpaURL:url];

    RPVApplicationDetailController *detailController = [[RPVApplicationDetailController alloc] initWithApplication:ipaApplication];

    // Update with current states.
    [detailController setButtonTitle:@"INSTALL"];
    detailController.lockWhenInstalling = YES;

    // Add to the rootViewController of the application, as an effective overlay.
    detailController.view.alpha = 0.0;

    UIViewController *rootController = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootController addChildViewController:detailController];
    [rootController.view addSubview:detailController.view];

    detailController.view.frame = rootController.view.bounds;

    // Animate in!
    [detailController animateForPresentation];
}

@end
