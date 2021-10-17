//
//  RPVTroubleshootingController.m
//  iOS
//
//  Created by Matt Clarke on 04/07/2018.
//  Copyright © 2018 Matt Clarke. All rights reserved.
//

#import "RPVTroubleshootingController.h"
#import "RPVResources.h"

#if !TARGET_OS_TV
#import <TORoundedTableView/TORoundedTableView.h>
#import <TORoundedTableView/TORoundedTableViewCapCell.h>
#import <TORoundedTableView/TORoundedTableViewCell.h>
#endif

#import "RPVAccountChecker.h"
#import "RPVNotificationManager.h"
#import "RPVTroubleshootingCertificatesViewController.h"

@interface RPVTroubleshootingController ()
@property (nonatomic, strong) NSArray *dataSource;
@end

#define REUSE @"troubleshoot.cell"

@implementation RPVTroubleshootingController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

#if TARGET_OS_TV
    self.view.backgroundColor = [UIColor clearColor];
    [(UITableView *)self.tableView setBackgroundColor:[UIColor clearColor]];
#else
    if (@available(iOS 11.0, *)) {
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    }
#endif

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:REUSE];
    self.tableView.allowsSelection = YES;

    [[self navigationItem] setTitle:@"Troubleshooting"];

    [self _setupDataSource];
    [self.tableView reloadData];
}

- (void)loadView {
    [super loadView];

#if TARGET_OS_TV
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
#else
    // Styling on iPad.
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        self.tableView = [[TORoundedTableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        self.tableView.separatorColor = self.tableView.backgroundColor;
    } else {
        self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    }
#endif
}

- (void)_setupDataSource {
    // data sauce.
    NSMutableArray *items = [NSMutableArray array];

    NSMutableArray *onlineHelp = [NSMutableArray array];
    [onlineHelp addObject:@"Online Help"];
    [onlineHelp addObject:@"Online help page provides the latest information about ReProvision Reboorn."];
    [onlineHelp addObject:@"Go to Online Help Page"];

    [items addObject:onlineHelp];

    NSMutableArray *submitDevelopmentCSR = [NSMutableArray array];
    [submitDevelopmentCSR addObject:@"submitDevelopmentCSR"];
    [submitDevelopmentCSR addObject:@"This error usually occurs when the same Apple ID is logged in more than twice to applications like Cydia Impactor and ReProvision.\n\nEach application creates a certificate to sign applications with, but free accounts are limited to only two certificates.\n\nTo resolve this, tap below to remove the extra certificates."];
    [submitDevelopmentCSR addObject:@"Manage Certificates"];

    [items addObject:submitDevelopmentCSR];

#if !TARGET_OS_TV
    NSMutableArray *devices = [NSMutableArray array];
    [devices addObject:@"Missing application on Apple Watch"];
    [devices addObject:@"After signing an application that supports the Apple Watch, the corresponding Watch application should be automatically installed.\n\nIf this fails without an error, and you've recently paired a new Apple Watch, you may need to manually register it to your Apple ID.\n\nTo do this, please tap below."];
    [devices addObject:@"Register Apple Watch"];

    [items addObject:devices];
#endif

    self.dataSource = items;
}

// table view delegate.
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.dataSource.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[self.dataSource objectAtIndex:section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;

#if TARGET_OS_TV
    cell = [tableView dequeueReusableCellWithIdentifier:REUSE forIndexPath:indexPath];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:REUSE];
    }
#else
    // Fancy cell styling on iPad
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        cell = [self tableView:(TORoundedTableView *)tableView _ipadCellForIndexPath:indexPath];
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:REUSE forIndexPath:indexPath];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:REUSE];
        }
    }
#endif

    NSArray *items = [self.dataSource objectAtIndex:indexPath.section];
    NSString *str = [items objectAtIndex:indexPath.row];

    BOOL isBold = indexPath.row == 0;

    cell.textLabel.text = str;
#if TARGET_OS_TV
    cell.textLabel.textColor = isBold ? [UIColor darkGrayColor] : [UIColor grayColor];
#else

    if (@available(iOS 13.0, *)) {
        cell.textLabel.textColor = isBold ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    } else {
        cell.textLabel.textColor = isBold ? [UIColor darkTextColor] : [UIColor grayColor];
    }

#endif
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.textLabel.textAlignment = NSTextAlignmentLeft;

    // Also handle if a link cell.
    if (indexPath.row == 2) {
        cell.textLabel.textColor = [UIApplication sharedApplication].delegate.window.tintColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

#if !TARGET_OS_TV
- (UITableViewCell *)tableView:(TORoundedTableView *)tableView _ipadCellForIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"Cell";
    static NSString *capCellIdentifier = @"CapCell";

    // Work out if this cell needs the top or bottom corners rounded (Or if the section only has 1 row, both!)
    BOOL isTop = (indexPath.row == 0);
    BOOL isBottom = indexPath.row == ([tableView numberOfRowsInSection:indexPath.section] - 1);

    // Create a common table cell instance we can configure
    UITableViewCell *cell = nil;

    // If it's a non-cap cell, dequeue one with the regular identifier
    if (!isTop && !isBottom) {
        TORoundedTableViewCell *normalCell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        if (normalCell == nil) {
            normalCell = [[TORoundedTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
        }

        cell = normalCell;
    } else {
        // If the cell is indeed one that needs rounded corners, dequeue from the pool of cap cells
        TORoundedTableViewCapCell *capCell = [tableView dequeueReusableCellWithIdentifier:capCellIdentifier];
        if (capCell == nil) {
            capCell = [[TORoundedTableViewCapCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:capCellIdentifier];
        }

        // Configure the cell to set the appropriate corners as rounded
        capCell.topCornersRounded = isTop;
        capCell.bottomCornersRounded = isBottom;
        cell = capCell;
    }

    cell.textLabel.opaque = YES;

    if (@available(iOS 13.0, *)) {
        cell.textLabel.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    } else {
        // Fallback on earlier versions
        cell.textLabel.backgroundColor = [UIColor whiteColor];
    }

    return cell;
}
#endif

- (CGRect)boundedRectForFont:(UIFont *)font andText:(id)text width:(CGFloat)width {
    if (!text || !font) {
        return CGRectZero;
    }

    if (![text isKindOfClass:[NSAttributedString class]]) {
        NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName: font }];
        CGRect rect = [attributedText boundingRectWithSize:(CGSize){ width, CGFLOAT_MAX }
                                                   options:NSStringDrawingUsesLineFragmentOrigin
                                                   context:nil];
        return rect;
    } else {
        return [(NSAttributedString *)text boundingRectWithSize:(CGSize){ width, CGFLOAT_MAX }
                                                        options:NSStringDrawingUsesLineFragmentOrigin
                                                        context:nil];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIFont *font = [UIFont systemFontOfSize:18];
    NSArray *items = [self.dataSource objectAtIndex:indexPath.section];
    NSString *str = [items objectAtIndex:indexPath.row];

    CGFloat extra = 24;

    // We also need to add an additional 20pt for each instance of "\n\n" in the string.
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        NSArray *split = [str componentsSeparatedByString:@"\n\n"];
        extra += (split.count - 1) * 20;
    }

    return [self boundedRectForFont:font andText:str width:self.tableView.contentSize.width].size.height + extra;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

// Selection.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row == 2) {
        // This is a link.
        switch (indexPath.section) {
            case 0: {
                // Online Help Page
                if (@available(iOS 10.0, *)) {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://satoh.dev/blog/reprovision-reborn-frequently-asked-questions/"] options:[NSDictionary dictionary] completionHandler:nil];
                } else {
                    // Fallback on earlier versions
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://satoh.dev/blog/reprovision-reborn-frequently-asked-questions/"]];
                }
            }
            case 1: {
                // Jump to the certificate management panel.
                RPVTroubleshootingCertificatesViewController *certsController = [[RPVTroubleshootingCertificatesViewController alloc] init];

                [self.navigationController pushViewController:certsController animated:YES];

                break;
            }
            case 2: {
                // Register active Apple Watch
                if ([RPVResources hasActivePairedWatch])
                    [[RPVAccountChecker sharedInstance] registerCurrentWatchForTeamID:[RPVResources getTeamID] withIdentity:[RPVResources getUsername] gsToken:[RPVResources getPassword] andCompletionHandler:^(NSError *error) {
                        // Error only happens if user already has registered this device!

                        NSString *notificationString = @"";
                        if (error) {
                            notificationString = @"Your Apple Watch has already been registered!";
                        } else {
                            notificationString = @"Your Apple Watch has been registered.";
                        }

                        [[RPVNotificationManager sharedInstance] sendNotificationWithTitle:@"" body:notificationString isDebugMessage:NO isUrgentMessage:YES andNotificationID:nil];
                    }];
                else
                    [[RPVNotificationManager sharedInstance] sendNotificationWithTitle:@"Error" body:@"No Apple Watch is currently paired!" isDebugMessage:NO isUrgentMessage:YES andNotificationID:nil];

                break;
            }

            default:
                break;
        }
    }
}

@end
