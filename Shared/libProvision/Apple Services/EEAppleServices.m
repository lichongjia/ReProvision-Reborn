//
//  EEAppleServices.m
//  Extender Installer
//
//  Created by Matt Clarke on 28/04/2017.
//
//

#import "EEAppleServices.h"
#import "AuthKit.h"
#import "NSData+GZIP.h"
#import "RPVAuthentication.h"

NSString *const REClientID = @"XABBG36SBA";
NSString *const REProtocolVersion = @"QH65B2";


@interface EEAppleServices ()

@property (nonatomic, strong) NSString *teamid;
@property (nonatomic, strong) NSURLCredential *credentials;
@property (nonatomic, strong) RPVAuthentication *authentication;
@property (nonatomic, copy, readonly) NSURL *baseURL;
@property (nonatomic, copy, readonly) NSURL *servicesBaseURL;

@end

@implementation EEAppleServices

+ (instancetype)sharedInstance {
    static EEAppleServices *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[EEAppleServices alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        self.teamid = @"";
        self.authentication = [[RPVAuthentication alloc] init];
        _baseURL = [[NSURL URLWithString:[NSString stringWithFormat:@"https://developerservices2.apple.com/services/%@/", REProtocolVersion]] copy];
        _servicesBaseURL = [[NSURL URLWithString:@"https://developerservices2.apple.com/services/v1/"] copy];
    }

    return self;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Private methods.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSMutableURLRequest *)populateHeaders:(NSMutableURLRequest *)request method:(NSString *)method {
    NSDictionary<NSString *, NSString *> *appleHeaders = [self.authentication appleIDHeadersForRequest:request];
    AKDevice *currentDevice = [AKDevice currentDevice];
    NSDictionary<NSString *, NSString *> *httpHeaders = @{
        @"Content-Type": [method isEqualToString:@"POST"] ? @"text/x-xml-plist" : @"application/vnd.api+json",
        @"User-Agent": @"Xcode",
        @"Accept": [method isEqualToString:@"POST"] ? @"text/x-xml-plist" : @"application/vnd.api+json",
        @"Accept-Language": @"en-us",
        @"Connection": @"keep-alive",
        @"X-Xcode-Version": @"11.2 (11B52)",
        @"X-Apple-I-Identity-Id": [[self.credentials user] componentsSeparatedByString:@"|"][0] ?: 0,
        @"X-Apple-GS-Token": [self.credentials password] ?: 0,
        @"X-Mme-Device-Id": [currentDevice uniqueDeviceIdentifier] ?: 0,
        @"X-HTTP-Method-Override": method,
    };

    [httpHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];

    [appleHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];

    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        NSLog(@"%@: %@", key, value);
    }];

    return request;
}

- (void)_sendRequest:(NSMutableURLRequest *)request method:(NSString *)method data:(NSData *)data andCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    request.HTTPMethod = @"POST";
    request = [self populateHeaders:request method:method];

    [request setHTTPBody:data];

    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:nil delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            completionHandler(error, nil);
        } else {
            NSData *unpacked = [data isGzippedData] ? [data gunzippedData] : data;
            NSDictionary *plist = [method isEqualToString:@"POST"] ? [NSPropertyListSerialization propertyListWithData:unpacked options:NSPropertyListImmutable format:nil error:nil] : [NSJSONSerialization JSONObjectWithData:unpacked options:0 error:nil];
            ;

            if (!plist)
                completionHandler(error, nil);
            else
                // Hit the completion handler.
                completionHandler(nil, plist);
        }
    }];
    [task resume];
}

- (void)_sendRawServiceRequestWithName:(NSString *)name method:(NSString *)method systemType:(EESystemType)systemType extraDictionary:(NSDictionary *)extra andCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSString *urlStr = [NSString stringWithFormat:@"%@%@", self.servicesBaseURL, name];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlStr]];


    NSLog(@"Service request to URL: %@", urlStr);


    NSError *serializationError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:extra options:0 error:&serializationError];
    if (data == nil) {
        completionHandler(nil, nil);
        return;
    }

    [self _sendRequest:request method:method data:data andCompletionHandler:completionHandler];
}

- (void)_sendServiceRequestWithName:(NSString *)name method:(NSString *)method systemType:(EESystemType)systemType extraDictionary:(NSDictionary *)extra andCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    // Now, body. (thanks altsign)
    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
    [extra enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:value]];
    }];

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.queryItems = queryItems;

    NSString *queryString = components.query ?: @"";

    [self _sendRawServiceRequestWithName:name method:method systemType:systemType extraDictionary:@{ @"urlEncodedQueryParams": queryString } andCompletionHandler:completionHandler];
}

- (void)_doActionWithName:(NSString *)action systemType:(EESystemType)systemType extraDictionary:(NSDictionary *)extra andCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSString *os = @"";

    if (systemType != EESystemTypeUndefined)
        os = systemType == EESystemTypeiOS || systemType == EESystemTypewatchOS ? @"ios/" : @"tvos/";

    NSString *urlStr = [NSString stringWithFormat:@"%@%@%@?clientId=%@", self.baseURL, os, action, REClientID];

    NSLog(@"Request to URL: %@", urlStr);

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlStr]];

    NSString *method = @"POST";

    // Now, body.
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    [dict setObject:REClientID forKey:@"clientId"];
    [dict setObject:REProtocolVersion forKey:@"protocolVersion"];
    [dict setObject:[[NSUUID UUID] UUIDString] forKey:@"requestId"];
    [dict setObject:@[@"en_US"] forKey:@"userLocale"];

    // Automatically switch this dependant on device type.
    /*
     * Available options:
     * mac
     * ios
     * tvos
     * watchos
     */
    switch (systemType) {
        case EESystemTypeiOS:
            [dict setObject:@"ios" forKey:@"DTDK_Platform"];
            //[dict setObject:@"ios" forKey:@"subPlatform"];
            break;
        case EESystemTypewatchOS:
            [dict setObject:@"watchos" forKey:@"DTDK_Platform"];
            //[dict setObject:@"watchOS" forKey:@"subPlatform"];
            break;
        case EESystemTypetvOS:
            [dict setObject:@"tvos" forKey:@"DTDK_Platform"];
            [dict setObject:@"tvOS" forKey:@"subPlatform"];
            break;
        default:
            break;
    }

    if (extra) {
        for (NSString *key in extra.allKeys) {
            if ([extra objectForKey:key])  // do a nil check.
                [dict setObject:[extra objectForKey:key] forKey:key];
        }
    }

    // We want this as an XML plist.
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];

    [self _sendRequest:request method:method data:data andCompletionHandler:completionHandler];
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Sign-In methods.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)ensureSessionWithIdentity:(NSString *)identity gsToken:(NSString *)token andCompletionHandler:(void (^)(NSError *error, NSDictionary *plist))completionHandler {
    self.credentials = [[NSURLCredential alloc] initWithUser:identity password:token persistence:NSURLCredentialPersistencePermanent];

    // TODO: Validate credentials

    NSMutableDictionary *resultDictionary = [NSMutableDictionary dictionary];
    [resultDictionary setObject:@"authenticated" forKey:@"reason"];
    [resultDictionary setObject:@"" forKey:@"userString"];

    completionHandler(nil, resultDictionary);
}

- (void)signInWithUsername:(NSString *)username password:(NSString *)password andCompletionHandler:(void (^)(NSError *, NSDictionary *, NSURLCredential *))completionHandler {
    [self.authentication authenticateWithUsername:username password:password withCompletion:^(NSError *error, NSString *userIdentity, NSString *gsToken) {
        if (error) {
            NSMutableDictionary *resultDictionary = [NSMutableDictionary dictionary];

            if (error.code == -22406) {
                [resultDictionary setObject:@"Your Apple ID or password is incorrect. App-specific passwords are not supported." forKey:@"userString"];
                [resultDictionary setObject:@"incorrectCredentials" forKey:@"reason"];
            } else if (error.code == 5000) {  // Internal error
                [resultDictionary setObject:error.localizedDescription forKey:@"userString"];
                [resultDictionary setObject:@"incorrectCredentials" forKey:@"reason"];
            } else if (error.code == 4010 || error.code == 4011) {
                [resultDictionary setObject:@"2FA code is required" forKey:@"userString"];
                [resultDictionary setObject:@"appSpecificRequired" forKey:@"reason"];
            } else {
                if (![error.localizedDescription isEqualToString:@""]) {
                    [resultDictionary setObject:[NSString stringWithFormat:@"%@ (%ld)", error.localizedDescription, (long)error.code] forKey:@"userString"];
                } else {
                    [resultDictionary setObject:[NSString stringWithFormat:@"Unknown error occurred (%ld)", (long)error.code] forKey:@"userString"];
                }

                [resultDictionary setObject:@"incorrectCredentials" forKey:@"reason"];
            }

            completionHandler(nil, resultDictionary, nil);

            return;
        }

        self.credentials = [[NSURLCredential alloc] initWithUser:userIdentity password:gsToken persistence:NSURLCredentialPersistencePermanent];

        // Do a request to listTeams.action to check that the user is a member of a team
        [self listTeamsWithCompletionHandler:^(NSError *error, NSDictionary *plist) {
            NSArray *teams = [plist objectForKey:@"teams"];

            if (!teams) {
                // Error of some kind?
                // TODO: HANDLE ME

                completionHandler(error, plist, nil);
                return;
            }

            NSMutableDictionary *resultDictionary = [NSMutableDictionary dictionary];

            [resultDictionary setObject:@"" forKey:@"userString"];
            [resultDictionary setObject:@"authenticated" forKey:@"reason"];

            completionHandler(nil, resultDictionary, self.credentials);
        }];
    }];
}

- (void)requestTwoFactorLoginCodeWithCompletionHandler:(void (^)(NSError *))completion {
    [self.authentication requestLoginCodeWithCompletion:completion];
}

- (void)validateLoginCode:(NSString *)code andCompletionHandler:(void (^)(NSError *, NSDictionary *, NSURLCredential *))completionHandler {
    [self.authentication validateLoginCode:code withCompletion:^(NSError *error, NSString *userIdentity, NSString *gsToken) {
        if (error) {
            NSMutableDictionary *resultDictionary = [NSMutableDictionary dictionary];

            if (error.code == 4012) {
                [resultDictionary setObject:@"2FA code is incorrect" forKey:@"userString"];
                [resultDictionary setObject:@"incorrectCredentials" forKey:@"reason"];
            } else {
                if (![error.localizedDescription isEqualToString:@""]) {
                    [resultDictionary setObject:[NSString stringWithFormat:@"%@ (%ld)", error.localizedDescription, (long)error.code] forKey:@"userString"];
                } else {
                    [resultDictionary setObject:[NSString stringWithFormat:@"Unknown error occurred (%ld)", (long)error.code] forKey:@"userString"];
                }

                [resultDictionary setObject:@"incorrectCredentials" forKey:@"reason"];
            }

            completionHandler(nil, resultDictionary, nil);

            return;
        }

        self.credentials = [[NSURLCredential alloc] initWithUser:userIdentity password:gsToken persistence:NSURLCredentialPersistencePermanent];

        // Do a request to listTeams.action to check that the user is a member of a team
        [self listTeamsWithCompletionHandler:^(NSError *error, NSDictionary *plist) {
            NSArray *teams = [plist objectForKey:@"teams"];

            if (!teams) {
                // Error of some kind?
                // TODO: HANDLE ME

                completionHandler(error, plist, nil);
                return;
            }

            NSMutableDictionary *resultDictionary = [NSMutableDictionary dictionary];

            [resultDictionary setObject:@"" forKey:@"userString"];
            [resultDictionary setObject:@"authenticated" forKey:@"reason"];

            completionHandler(nil, resultDictionary, self.credentials);
        }];
    }];
}

- (void)fallback2FACodeRequest:(void (^)(NSError *, NSDictionary *, NSURLCredential *))completionHandler {
    [self.authentication fallback2FACodeRequest:^(NSError *error, NSString *userIdentity, NSString *gsToken) {
        if (error) {
            NSMutableDictionary *resultDictionary = [NSMutableDictionary dictionary];

            if (error.code == 4012) {
                [resultDictionary setObject:@"2FA code is incorrect" forKey:@"userString"];
                [resultDictionary setObject:@"incorrectCredentials" forKey:@"reason"];
            } else {
                if (![error.localizedDescription isEqualToString:@""]) {
                    [resultDictionary setObject:[NSString stringWithFormat:@"%@ (%ld)", error.localizedDescription, (long)error.code] forKey:@"userString"];
                } else {
                    [resultDictionary setObject:[NSString stringWithFormat:@"Unknown error occurred (%ld)", (long)error.code] forKey:@"userString"];
                }

                [resultDictionary setObject:@"incorrectCredentials" forKey:@"reason"];
            }

            completionHandler(nil, resultDictionary, nil);

            return;
        }

        self.credentials = [[NSURLCredential alloc] initWithUser:userIdentity password:gsToken persistence:NSURLCredentialPersistencePermanent];

        // Do a request to listTeams.action to check that the user is a member of a team
        [self listTeamsWithCompletionHandler:^(NSError *error, NSDictionary *plist) {
            NSArray *teams = [plist objectForKey:@"teams"];

            if (!teams) {
                // Error of some kind?
                // TODO: HANDLE ME

                completionHandler(error, plist, nil);
                return;
            }

            NSMutableDictionary *resultDictionary = [NSMutableDictionary dictionary];

            [resultDictionary setObject:@"" forKey:@"userString"];
            [resultDictionary setObject:@"authenticated" forKey:@"reason"];

            completionHandler(nil, resultDictionary, self.credentials);
        }];
    }];
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Team ID methods.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)currentTeamID {
    return self.teamid;
}

- (void)updateCurrentTeamIDWithTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback andCallback:(void (^)(NSError *, NSString *))completionHandler {
    // We also want to pull the Team ID for this user, rather than find it on installation.
    [self listTeamsWithCompletionHandler:^(NSError *error, NSDictionary *plist) {
        if (error) {
            // XXX: It is possible for a user to never have signed up for a development
            // account with Apple with their existing ID. Thus, we should hit here if
            // that's the case!

            self.teamid = @"";
            completionHandler(error, @"");
            return;
        }

        NSArray *teams = [plist objectForKey:@"teams"];
        if (!teams) {
            completionHandler(error, @"");
            return;
        }

        NSString *teamId;

        // If there are multiple teams this user is in, request which one they want to use.
        if (teams.count > 1) {
            teamId = teamIDCallback(teams);
        } else if (teams.count == 1) {
            NSDictionary *onlyTeam = teams[0];
            teamId = [onlyTeam objectForKey:@"teamId"];
        } else {
            completionHandler(error, @"");
            return;
        }

        self.teamid = teamId;

        completionHandler(error, self.teamid);
    }];
}

- (void)viewDeveloperWithCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    [self _doActionWithName:@"viewDeveloper.action" systemType:EESystemTypeUndefined extraDictionary:nil andCompletionHandler:^(NSError *error, NSDictionary *plist) {
        if (error) {
            completionHandler(error, nil);
        } else {
            // Hit the completion handler.
            completionHandler(nil, plist);
        }
    }];
}

- (void)listTeamsWithCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    [self _doActionWithName:@"listTeams.action" systemType:EESystemTypeUndefined extraDictionary:nil andCompletionHandler:^(NSError *error, NSDictionary *plist) {
        if (error) {
            completionHandler(error, nil);
        } else {
            // Hit the completion handler.
            completionHandler(nil, plist);
        }
    }];
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Device methods
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)addDevice:(NSString *)udid deviceName:(NSString *)name forTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:udid forKey:@"deviceNumber"];
    [extra setObject:name forKey:@"name"];

    [self _doActionWithName:@"addDevice.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)listDevicesForTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:@"500" forKey:@"pageSize"];
    [extra setObject:@"1" forKey:@"pageNumber"];
    [extra setObject:@"name=asc" forKey:@"sort"];
    [extra setObject:@"false" forKey:@"includeRemovedDevices"];

    [self _doActionWithName:@"listDevices.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Application ID methods.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)listAllApplicationsForTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];

    [self _doActionWithName:@"listAppIds.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)addApplicationId:(NSString *)applicationIdentifier name:(NSString *)applicationName enabledFeatures:(NSDictionary *)enabledFeatures teamID:(NSString *)teamID entitlements:(NSDictionary *)entitlements systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:applicationIdentifier forKey:@"identifier"];
    [extra setObject:applicationName forKey:@"name"];
    [extra setObject:@"explicit" forKey:@"type"];

    // Features - assume caller has correctly set "on", "off", "whatever"
    for (NSString *key in [enabledFeatures allKeys]) {
        if ([enabledFeatures objectForKey:key]) [extra setObject:[enabledFeatures objectForKey:key] forKey:key];
    }

    [extra setObject:entitlements forKey:@"entitlements"];

    [self _doActionWithName:@"addAppId.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)updateApplicationIdId:(NSString *)appIdId enabledFeatures:(NSDictionary *)enabledFeatures teamID:(NSString *)teamID entitlements:(NSDictionary *)entitlements systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler;
{
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:appIdId forKey:@"appIdId"];
    [extra setObject:@"explicit" forKey:@"type"];

    // Features - assume caller has correctly set "on", "off", "whatever"
    for (NSString *key in [enabledFeatures allKeys]) {
        [extra setObject:[enabledFeatures objectForKey:key] forKey:key];
    }

    [extra setObject:entitlements forKey:@"entitlements"];

    [self _doActionWithName:@"updateAppId.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)deleteApplicationIdId:(NSString *)appIdId teamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:appIdId forKey:@"appIdId"];

    [self _doActionWithName:@"deleteAppId.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)listAllApplicationGroupsForTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    // CHECKME: is this the right dictionary?
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];

    [self _doActionWithName:@"listApplicationGroups.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)addApplicationGroupWithIdentifier:(NSString *)identifier andName:(NSString *)groupName forTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:identifier forKey:@"identifier"];
    [extra setObject:groupName forKey:@"name"];

    [self _doActionWithName:@"addApplicationGroup.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)assignApplicationGroup:(NSString *)applicationGroup toApplicationIdId:(NSString *)appIdId teamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:appIdId forKey:@"appIdId"];
    [extra setObject:applicationGroup forKey:@"applicationGroups"];

    [self _doActionWithName:@"assignApplicationGroupToAppId.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Certificates methods.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)listAllDevelopmentCertificatesWithFiltering:(BOOL)useFilter teamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];

    if (useFilter) [extra setObject:@"IOS_DEVELOPMENT" forKey:@"filter[certificateType]"];

    [self _sendServiceRequestWithName:@"certificates" method:@"GET" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)listAllDevelopmentCertificatesForTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    [self listAllDevelopmentCertificatesWithFiltering:NO teamID:teamID systemType:systemType withCompletionHandler:completionHandler];
}

- (void)listAllProvisioningProfilesForTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];

    [self _doActionWithName:@"listProvisioningProfiles.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)getProvisioningProfileForAppIdId:(NSString *)appIdId withTeamID:(NSString *)teamID systemType:(EESystemType)systemType andCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:appIdId forKey:@"appIdId"];

    [self _doActionWithName:@"downloadTeamProvisioningProfile.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)deleteProvisioningProfileForApplication:(NSString *)applicationId andTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    [self listAllProvisioningProfilesForTeamID:teamID systemType:systemType withCompletionHandler:^(NSError *error, NSDictionary *plist) {
        if (error) {
            completionHandler(error, nil);
            return;
        }

        NSArray *provisioningProfiles = [plist objectForKey:@"provisioningProfiles"];

        // We want the provisioning profile that has an appId that matches our provided bundle identifier.
        // Then, we take it's provisioningProfileId.

        NSString *provisioningProfileId = @"";

        for (NSDictionary *profile in provisioningProfiles) {
            NSDictionary *appId = [profile objectForKey:@"appId"];

            // For whatever reason, Impactor/Extender will add some extra stuff to identifier.
            BOOL matches = [[appId objectForKey:@"identifier"] rangeOfString:applicationId].location != NSNotFound;

            if (matches) {
                provisioningProfileId = [profile objectForKey:@"provisioningProfileId"];
                break;
            }
        }

        if (![provisioningProfileId isEqualToString:@""]) {
            // Onwards to deletion!

            NSMutableDictionary *extra = [NSMutableDictionary dictionary];
            [extra setObject:teamID forKey:@"teamId"];
            [extra setObject:provisioningProfileId forKey:@"provisioningProfileId"];

            [self _doActionWithName:@"deleteProvisioningProfile.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
        } else {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: NSLocalizedString(@"No provisioning profile contains the provided bundle identifier.", nil),
                NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"No provisioning profile contains the provided bundle identifier.", nil)
            };
            NSError *error = [NSError errorWithDomain:NSInvalidArgumentException
                                                 code:-1
                                             userInfo:userInfo];


            completionHandler(error, nil);
            return;
        }
    }];
}

- (void)revokeCertificateForSerialNumber:(NSString *)serialNumber andTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];
    [extra setObject:serialNumber forKey:@"serialNumber"];

    [self _doActionWithName:@"revokeDevelopmentCert.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)revokeCertificateForIdentifier:(NSString *)identifier andTeamID:(NSString *)teamID systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:teamID forKey:@"teamId"];

    [self _sendServiceRequestWithName:[NSString stringWithFormat:@"certificates/%@", identifier] method:@"DELETE" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];
}

- (void)submitCodeSigningRequestForTeamID:(NSString *)teamId machineName:(NSString *)machineName machineID:(NSString *)machineID codeSigningRequest:(NSData *)csr systemType:(EESystemType)systemType withCompletionHandler:(void (^)(NSError *, NSDictionary *))completionHandler {
    NSString *stringifiedCSR = [[NSString alloc] initWithData:csr encoding:NSUTF8StringEncoding];

    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setObject:@"DEVELOPMENT" forKey:@"certificateType"];
    [extra setObject:teamId forKey:@"teamId"];
    [extra setObject:stringifiedCSR forKey:@"csrContent"];
    [extra setObject:machineID forKey:@"machineId"];
    [extra setObject:machineName forKey:@"machineName"];

    NSDictionary *obj = @{
        @"data": @{
            @"attributes": extra,
            @"type": @"certificates"
        },
    };
    //[self _doActionWithName:@"submitDevelopmentCSR.action" systemType:systemType extraDictionary:extra andCompletionHandler:completionHandler];

    [self _sendRawServiceRequestWithName:@"certificates" method:@"post" systemType:systemType extraDictionary:obj andCompletionHandler:completionHandler];
    // use post to make existing code to use json
}

@end
