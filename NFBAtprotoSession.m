#import "NFBChatPermission.h"
#import "NFBAtprotoSession.h"
#import "NFBTokenRefreshPolicy.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>

NSString * const NFBAtprotoSessionChangedNotification = @"NFBAtprotoSessionChangedNotification";
NSString * const NFBAtprotoOAuthCallbackReceivedNotification = @"NFBAtprotoOAuthCallbackReceivedNotification";

static NSString * const NFBAtprotoDefaultsKey = @"nfb_atproto_session";
static NSString * const NFBAtprotoAccountsDefaultsKey = @"nfb_atproto_accounts";
static NSString * const NFBAtprotoActiveAccountDIDDefaultsKey = @"nfb_atproto_active_account_did";
static NSString * const NFBAtprotoDefaultService = @"https://bsky.social";
static NSString * const NFBAtprotoDefaultIssuer = @"https://bsky.social";
static NSString * const NFBAtprotoDirectAppView = @"https://api.bsky.app";
static NSString * const NFBAtprotoPublicAppView = @"https://public.api.bsky.app";
static NSString * const NFBAtprotoAppViewProxy = @"did:web:api.bsky.app#bsky_appview";
static NSString * const NFBAtprotoChatProxy = @"did:web:api.bsky.chat#bsky_chat";
static NSString * const NFBAtprotoOAuthScope = @"atproto transition:generic transition:chat.bsky account:email?action=manage identity:handle";
static NSString * const NFBAtprotoNativeClientID = @"https://nottwitterapp.github.io/oauth/neofreebird-client-metadata.json";
static NSString * const NFBAtprotoNativeRedirectURI = @"io.github.nottwitterapp:/not-twitter/oauth/neofreebird-callback";
static NSString * const NFBAtprotoNativeRedirectScheme = @"io.github.nottwitterapp";
static NSString * const NFBAtprotoNativeRedirectPath = @"/not-twitter/oauth/neofreebird-callback";
static const NSTimeInterval NFBAtprotoAccessTokenRefreshTimerInterval = 15.0;

@interface NFBAtprotoSession (NFBPrivateErrors)
+ (NSError *)genericError:(NSString *)message;
@end

@interface NFBAtprotoSession ()
@property (nonatomic, copy, nullable) NSString *accessJwt;
@property (nonatomic, copy, nullable) NSString *refreshJwt;
@property (nonatomic, strong, nullable) NSDate *accessTokenExpiresAt;
@property (nonatomic, assign) NSTimeInterval accessTokenLifetime;
@property (nonatomic, copy, nullable) NSString *did;
@property (nonatomic, copy, nullable) NSString *handle;
@property (nonatomic, copy) NSString *serviceEndpoint;
@property (nonatomic, copy, nullable) NSDictionary *profile;
@property (atomic, assign, readwrite) NSUInteger accountGeneration;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, copy, nullable) NSString *oauthIssuer;
@property (nonatomic, copy, nullable) NSString *oauthAuthorizationEndpoint;
@property (nonatomic, copy, nullable) NSString *oauthTokenEndpoint;
@property (nonatomic, copy, nullable) NSString *oauthPAREndpoint;
@property (nonatomic, copy, nullable) NSString *oauthRevocationEndpoint;
@property (nonatomic, copy, nullable) NSString *oauthClientID;
@property (nonatomic, copy, nullable) NSString *oauthRedirectURI;
@property (nonatomic, copy, nullable) NSString *oauthTokenType;
@property (nonatomic, copy, nullable) NSData *dpopPrivateKeyData;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *dpopNonces;
@property (nonatomic, copy, nullable) NSString *pendingOAuthState;
@property (nonatomic, copy, nullable) NSString *pendingOAuthVerifier;
@property (nonatomic, copy, nullable) NSString *pendingOAuthIssuer;
@property (nonatomic, copy, nullable) NSString *pendingOAuthTokenEndpoint;
@property (nonatomic, copy, nullable) NSString *pendingOAuthServiceEndpoint;
@property (nonatomic, copy, nullable) NSString *pendingOAuthClientID;
@property (nonatomic, copy, nullable) NSString *pendingOAuthRedirectURI;
@property (nonatomic, copy, nullable) NSData *pendingOAuthDpopPrivateKeyData;
@property (nonatomic, copy, nullable) NFBAtprotoSignInCompletion pendingOAuthCompletion;
@property (nonatomic, assign) BOOL pendingOAuthCallbackReceived;
@property (nonatomic, strong, nullable) NSTimer *sessionRefreshTimer;
@property (nonatomic, assign) BOOL sessionRefreshInFlight;
@property (nonatomic, strong) NSMutableArray *sessionRefreshCompletions;
@property (nonatomic, strong, nullable) NSDate *lastSessionRefreshAttemptDate;
@property (nonatomic, strong) NSMutableSet<NSString *> *sessionRefreshAccountsInFlight;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *sessionRefreshCompletionsByAccount;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lastSessionRefreshAttemptDatesByAccount;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSError *> *sessionRefreshErrorsByAccount;

- (NSString *)pdsServiceEndpoint;
- (void)resolveCurrentPDSIfNeededWithCompletion:(void (^)(NSString *serviceEndpoint))completion;
- (void)postSessionChangedNotification;
- (void)startSessionRefreshMaintenance;
- (void)stopSessionRefreshMaintenance;
- (void)refreshSessionIfNeededForce:(BOOL)force;
- (void)finishSessionRefreshWithSuccess:(BOOL)success session:(nullable NSDictionary *)session error:(nullable NSError *)error;
- (void)finishSessionRefreshForAccountDID:(NSString *)accountDID success:(BOOL)success session:(nullable NSDictionary *)session error:(nullable NSError *)error;
- (BOOL)storeOAuthTokenResponse:(NSDictionary *)tokenResponse
                  forAccountDID:(NSString *)accountDID
                          issuer:(NSString *)issuer
                      serviceURL:(NSString *)serviceURL
                    tokenEndpoint:(NSString *)tokenEndpoint
                      redirectURI:(NSString *)redirectURI
                         clientID:(NSString *)clientID
                   dpopPrivateKey:(NSData *)dpopPrivateKey
                    expectedRefreshToken:(NSString *)expectedRefreshToken;
- (BOOL)shouldProactivelyRefreshAccessToken;
- (BOOL)isAccessTokenExpired;
- (void)clearCurrentSessionLocked;
- (NSDictionary *)storedSessionDictionaryLocked;
- (void)applyStoredSessionDictionaryLocked:(NSDictionary *)stored;
- (void)saveStoredSessionLocked;
- (void)upsertStoredAccountDictionaryLocked:(NSDictionary *)stored;
- (NSMutableArray<NSDictionary *> *)storedAccountsMutableCopy;
+ (NSString *)accountDIDFromStoredDictionary:(NSDictionary *)stored;
+ (NSString *)normalizedPDSServiceURL:(NSString *)serviceURL;
+ (BOOL)isAppViewServiceURL:(NSString *)serviceURL;
+ (nullable NSDate *)expirationDateForTokenResponse:(NSDictionary *)response;
+ (nullable NSDate *)expirationDateForJWT:(NSString *)jwt;
+ (nullable NSData *)base64URLDecodedData:(NSString *)string;
@end

@implementation NFBAtprotoSession

+ (instancetype)sharedSession {
    static NFBAtprotoSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        session = [[NFBAtprotoSession alloc] initPrivate];
    });
    return session;
}

- (instancetype)init {
    return [NFBAtprotoSession sharedSession];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _stateQueue = dispatch_queue_create("com.nottwitter.atproto.session", DISPATCH_QUEUE_SERIAL);
        _serviceEndpoint = NFBAtprotoDefaultService;
        _oauthIssuer = NFBAtprotoDefaultIssuer;
        _oauthTokenType = @"DPoP";
        _dpopNonces = [NSMutableDictionary dictionary];
        _sessionRefreshCompletions = [NSMutableArray array];
        _sessionRefreshAccountsInFlight = [NSMutableSet set];
        _sessionRefreshCompletionsByAccount = [NSMutableDictionary dictionary];
        _lastSessionRefreshAttemptDatesByAccount = [NSMutableDictionary dictionary];
        _sessionRefreshErrorsByAccount = [NSMutableDictionary dictionary];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
        [self loadStoredSession];
        if ([self hasSession]) {
            [self startSessionRefreshMaintenance];
            [self refreshSessionIfNeededForce:NO];
        }
    }
    return self;
}

- (void)postSessionChangedNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NFBAtprotoSessionChangedNotification object:self];
    });
}

- (void)startSessionRefreshMaintenance {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.sessionRefreshTimer) return;
        self.sessionRefreshTimer = [NSTimer timerWithTimeInterval:NFBAtprotoAccessTokenRefreshTimerInterval
                                                           target:self
                                                         selector:@selector(sessionRefreshTimerFired:)
                                                         userInfo:nil
                                                          repeats:YES];
        self.sessionRefreshTimer.tolerance = 3.0;
        [[NSRunLoop mainRunLoop] addTimer:self.sessionRefreshTimer forMode:NSRunLoopCommonModes];
    });
}

- (void)stopSessionRefreshMaintenance {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.sessionRefreshTimer invalidate];
        self.sessionRefreshTimer = nil;
    });
}

- (void)sessionRefreshTimerFired:(NSTimer *)timer {
    (void)timer;
    [self refreshSessionIfNeededForce:NO];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    (void)notification;
    [self refreshSessionIfNeededForce:NO];
}

- (BOOL)hasSession {
    __block BOOL hasSession = NO;
    dispatch_sync(self.stateQueue, ^{
        hasSession = self.accessJwt.length > 0 && self.refreshJwt.length > 0 && self.did.length > 0 && self.dpopPrivateKeyData.length > 0;
    });
    return hasSession;
}

- (NSArray<NSDictionary *> *)savedAccounts {
    return [self savedAccountDictionaries];
}

- (NSArray<NSDictionary *> *)savedAccountDictionaries {
    __block NSArray<NSDictionary *> *accounts = @[];
    dispatch_sync(self.stateQueue, ^{
        NSMutableArray<NSDictionary *> *storedAccounts = [self storedAccountsMutableCopy];
        if (self.did.length > 0) {
            NSDictionary *currentStored = [self storedSessionDictionaryLocked];
            if (currentStored.count > 0) {
                [self upsertStoredAccountDictionaryLocked:currentStored];
                storedAccounts = [self storedAccountsMutableCopy];
            }
        }

        NSMutableArray<NSDictionary *> *displayAccounts = [NSMutableArray array];
        for (NSDictionary *stored in storedAccounts) {
            if (![stored isKindOfClass:[NSDictionary class]]) continue;
            NSString *did = [self.class accountDIDFromStoredDictionary:stored];
            if (did.length == 0) continue;
            NSDictionary *profile = [stored[@"profile"] isKindOfClass:[NSDictionary class]] ? stored[@"profile"] : @{};
            NSString *handle = [profile[@"handle"] isKindOfClass:[NSString class]] && [profile[@"handle"] length] > 0 ? profile[@"handle"] : stored[@"handle"];
            if (![handle isKindOfClass:[NSString class]] || handle.length == 0) handle = did;
            NSString *displayName = [profile[@"displayName"] isKindOfClass:[NSString class]] && [profile[@"displayName"] length] > 0 ? profile[@"displayName"] : handle;
            NSString *avatar = [profile[@"avatar"] isKindOfClass:[NSString class]] ? profile[@"avatar"] : @"";
            NSNumber *following = [profile[@"followsCount"] respondsToSelector:@selector(stringValue)] ? profile[@"followsCount"] : @0;
            NSNumber *followers = [profile[@"followersCount"] respondsToSelector:@selector(stringValue)] ? profile[@"followersCount"] : @0;
            [displayAccounts addObject:@{
                @"did": did,
                @"handle": handle ?: did,
                @"displayName": displayName ?: handle ?: did,
                @"avatar": avatar ?: @"",
                @"followsCount": following,
                @"followersCount": followers,
                @"active": @([did isEqualToString:self.did ?: @""])
            }];
        }
        accounts = [displayAccounts copy];
    });
    return accounts;
}

- (BOOL)hasPendingOAuthSignIn {
    return self.pendingOAuthCompletion != nil;
}

- (BOOL)hasReceivedPendingOAuthCallback {
    return self.pendingOAuthCallbackReceived;
}

- (void)signInWithIdentifier:(NSString *)identifier
     authorizationURLHandler:(NFBAtprotoAuthorizationURLHandler)authorizationURLHandler
                  completion:(NFBAtprotoSignInCompletion)completion {
    NSString *loginIdentifier = [self.class normalizedLoginIdentifier:identifier];
    if (loginIdentifier.length == 0) {
        if (completion) completion(NO, nil, [self.class genericError:@"Enter your Bluesky handle or DID."]);
        return;
    }

    [self cancelPendingOAuthSignIn];

    NSData *dpopKeyData = [self.class generateP256PrivateKeyData];
    if (dpopKeyData.length == 0) {
        if (completion) completion(NO, nil, [self.class genericError:@"Could not create OAuth DPoP key."]);
        return;
    }

    NSString *redirectURI = NFBAtprotoNativeRedirectURI;
    NSString *clientID = NFBAtprotoNativeClientID;
    NSString *state = [self.class randomBase64URLStringWithByteCount:16];
    NSString *verifier = [self.class randomBase64URLStringWithByteCount:32];
    NSString *challenge = [self.class sha256Base64URLForString:verifier];

    self.pendingOAuthState = state;
    self.pendingOAuthVerifier = verifier;
    self.pendingOAuthClientID = clientID;
    self.pendingOAuthRedirectURI = redirectURI;
    self.pendingOAuthDpopPrivateKeyData = dpopKeyData;
    self.pendingOAuthCompletion = completion;
    self.pendingOAuthCallbackReceived = NO;

    [self resolveOAuthContextForIdentifier:loginIdentifier completion:^(NSString *serviceEndpoint, NSDictionary *metadata, NSError *error) {
        if (error || !metadata) {
            [self cancelPendingOAuthSignIn];
            if (completion) completion(NO, nil, error ?: [self.class genericError:@"Could not resolve Bluesky OAuth server."]);
            return;
        }

        NSString *issuer = [metadata[@"issuer"] isKindOfClass:[NSString class]] ? metadata[@"issuer"] : NFBAtprotoDefaultIssuer;
        NSString *authorizationEndpoint = [metadata[@"authorization_endpoint"] isKindOfClass:[NSString class]] ? metadata[@"authorization_endpoint"] : nil;
        NSString *tokenEndpoint = [metadata[@"token_endpoint"] isKindOfClass:[NSString class]] ? metadata[@"token_endpoint"] : nil;
        NSString *parEndpoint = [metadata[@"pushed_authorization_request_endpoint"] isKindOfClass:[NSString class]] ? metadata[@"pushed_authorization_request_endpoint"] : nil;

        if (authorizationEndpoint.length == 0 || tokenEndpoint.length == 0 || parEndpoint.length == 0) {
            [self cancelPendingOAuthSignIn];
            if (completion) completion(NO, nil, [self.class genericError:@"This Bluesky server does not expose the OAuth endpoints Not Twitter needs."]);
            return;
        }

        self.pendingOAuthIssuer = issuer;
        self.pendingOAuthTokenEndpoint = tokenEndpoint;
        self.pendingOAuthServiceEndpoint = serviceEndpoint ?: NFBAtprotoDefaultService;

        NSDictionary *form = @{
            @"client_id": clientID,
            @"redirect_uri": redirectURI,
            @"code_challenge": challenge,
            @"code_challenge_method": @"S256",
            @"state": state,
            @"login_hint": loginIdentifier,
            @"response_type": @"code",
            @"scope": NFBAtprotoOAuthScope
        };

        [self sendOAuthFormRequestToURL:parEndpoint
                                   form:form
                         dpopPrivateKey:dpopKeyData
                    authorizationToken:nil
                             completion:^(id value, NSHTTPURLResponse *response, NSError *parError) {
            if (parError || ![value isKindOfClass:[NSDictionary class]]) {
                [self cancelPendingOAuthSignIn];
                if (completion) completion(NO, nil, parError ?: [self.class genericError:@"Bluesky OAuth could not start."]);
                return;
            }

            NSString *requestURI = [(NSDictionary *)value objectForKey:@"request_uri"];
            if (![requestURI isKindOfClass:[NSString class]] || requestURI.length == 0) {
                [self cancelPendingOAuthSignIn];
                if (completion) completion(NO, nil, [self.class genericError:@"Bluesky OAuth did not return a request URI."]);
                return;
            }

            NSURLComponents *components = [NSURLComponents componentsWithString:authorizationEndpoint];
            components.queryItems = @[
                [NSURLQueryItem queryItemWithName:@"client_id" value:clientID],
                [NSURLQueryItem queryItemWithName:@"request_uri" value:requestURI]
            ];
            NSURL *authorizationURL = components.URL;
            if (!authorizationURL) {
                [self cancelPendingOAuthSignIn];
                if (completion) completion(NO, nil, [self.class genericError:@"Bluesky OAuth produced an invalid authorization URL."]);
                return;
            }

            if (authorizationURLHandler) authorizationURLHandler(authorizationURL);
        }];
    }];
}

- (BOOL)handleOAuthCallbackURL:(NSURL *)url {
    if (![[url.scheme lowercaseString] isEqualToString:NFBAtprotoNativeRedirectScheme]) return NO;
    if (url.path.length > 0 && ![url.path isEqualToString:NFBAtprotoNativeRedirectPath]) return NO;

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name.length > 0 && item.value.length > 0) params[item.name] = item.value;
    }

    NFBAtprotoSignInCompletion completion = self.pendingOAuthCompletion;
    [self handleOAuthCallbackParams:params completion:completion];
    return YES;
}

- (void)cancelPendingOAuthSignIn {
    self.pendingOAuthState = nil;
    self.pendingOAuthVerifier = nil;
    self.pendingOAuthIssuer = nil;
    self.pendingOAuthTokenEndpoint = nil;
    self.pendingOAuthServiceEndpoint = nil;
    self.pendingOAuthClientID = nil;
    self.pendingOAuthRedirectURI = nil;
    self.pendingOAuthDpopPrivateKeyData = nil;
    self.pendingOAuthCompletion = nil;
    self.pendingOAuthCallbackReceived = NO;
}

- (void)refreshSessionWithCompletion:(NFBAtprotoSignInCompletion)completion {
    [self refreshSessionForAccountDID:nil privateKey:nil rejectedToken:nil completion:completion];
}

- (void)refreshSessionForAccountDID:(NSString *)expectedDID
                       privateKey:(NSData *)expectedKey
                    rejectedToken:(NSString *)rejectedToken
                       completion:(NFBAtprotoSignInCompletion)completion {
    NFBAtprotoSignInCompletion completionCopy = [completion copy];
    __block NSString *accountDID = nil;
    __block NSString *refreshToken = nil;
    __block NSString *tokenEndpoint = nil;
    __block NSString *clientID = nil;
    __block NSString *issuer = nil;
    __block NSString *serviceEndpoint = nil;
    __block NSString *redirectURI = nil;
    __block NSData *dpopKeyData = nil;
    __block BOOL startsRefresh = NO;
    __block BOOL alreadyRenewed = NO;
    __block NSError *earlyError = nil;
    dispatch_sync(self.stateQueue, ^{
        NSDictionary *account = [self storedAccountForDIDLocked:expectedDID ?: self.did];
        accountDID = account[@"did"];
        refreshToken = account[@"refreshJwt"];
        tokenEndpoint = account[@"oauthTokenEndpoint"];
        clientID = account[@"oauthClientID"];
        issuer = account[@"oauthIssuer"] ?: NFBAtprotoDefaultIssuer;
        serviceEndpoint = account[@"serviceEndpoint"] ?: NFBAtprotoDefaultService;
        redirectURI = account[@"oauthRedirectURI"];
        dpopKeyData = account[@"dpopPrivateKey"];
        if (accountDID.length == 0 || refreshToken.length == 0 || tokenEndpoint.length == 0 || clientID.length == 0 || dpopKeyData.length == 0) return;
        if (expectedDID && (![accountDID isEqualToString:expectedDID] || ![dpopKeyData isEqual:expectedKey])) {
            earlyError = [self.class genericError:@"This account's login changed. Please try again."];
            return;
        }
        if (rejectedToken && ![account[@"accessJwt"] isEqualToString:rejectedToken]) {
            alreadyRenewed = YES;
            return;
        }
        @synchronized (self) {
            BOOL inFlight = [self.sessionRefreshAccountsInFlight containsObject:accountDID];
            NSDate *lastAttempt = self.lastSessionRefreshAttemptDatesByAccount[accountDID];
            NSError *lastError = self.sessionRefreshErrorsByAccount[accountDID];
            if (!inFlight && lastError && lastAttempt && -[lastAttempt timeIntervalSinceNow] < 60.0) {
                earlyError = lastError;
                return;
            }
            NSMutableArray *completions = self.sessionRefreshCompletionsByAccount[accountDID];
            if (!completions) {
                completions = [NSMutableArray array];
                self.sessionRefreshCompletionsByAccount[accountDID] = completions;
            }
            if (completionCopy) [completions addObject:completionCopy];
            if (inFlight) return;
            [self.sessionRefreshAccountsInFlight addObject:accountDID];
            self.lastSessionRefreshAttemptDatesByAccount[accountDID] = [NSDate date];
        }
        startsRefresh = YES;
    });

    if (accountDID.length == 0 || refreshToken.length == 0 || tokenEndpoint.length == 0 || clientID.length == 0 || dpopKeyData.length == 0) {
        NSError *error = [NSError errorWithDomain:@"NFBAtprotoSession"
                                             code:401
                                         userInfo:@{NSLocalizedDescriptionKey: @"No Bluesky OAuth refresh token is available."}];
        if (completionCopy) completionCopy(NO, nil, error);
        return;
    }


    if (earlyError || alreadyRenewed) {
        if (completionCopy) completionCopy(alreadyRenewed, nil, earlyError);
        return;
    }
    if (!startsRefresh) return;

    NSDictionary *form = @{
        @"grant_type": @"refresh_token",
        @"refresh_token": refreshToken,
        @"client_id": clientID
    };

    [self sendOAuthFormRequestToURL:tokenEndpoint
                               form:form
                     dpopPrivateKey:dpopKeyData
                 authorizationToken:nil
                         completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        if (error || ![value isKindOfClass:[NSDictionary class]]) {
            [self finishSessionRefreshForAccountDID:accountDID success:NO session:nil error:error ?: [self.class genericError:@"Bluesky OAuth refresh failed."]];
            return;
        }

        NSDictionary *tokenResponse = (NSDictionary *)value;
        BOOL storedResponse = [self storeOAuthTokenResponse:tokenResponse
                                                    forAccountDID:accountDID
                                                            issuer:issuer
                                                        serviceURL:serviceEndpoint
                                                      tokenEndpoint:tokenEndpoint
                                                        redirectURI:redirectURI
                                                           clientID:clientID
                                                     dpopPrivateKey:dpopKeyData
                                                      expectedRefreshToken:refreshToken];
        if (storedResponse && [self isCurrentAccountDID:accountDID privateKey:dpopKeyData]) [self postSessionChangedNotification];
        [self finishSessionRefreshForAccountDID:accountDID success:storedResponse session:storedResponse ? tokenResponse : nil error:storedResponse ? nil : [self.class genericError:@"The OAuth refresh response was invalid or the session changed."]];
    }];
}

- (void)finishSessionRefreshWithSuccess:(BOOL)success session:(NSDictionary *)session error:(NSError *)error {
    NSArray *completions = nil;
    @synchronized (self) {
        completions = [self.sessionRefreshCompletions copy];
        [self.sessionRefreshCompletions removeAllObjects];
        self.sessionRefreshInFlight = NO;
    }

    if (success) {
        [self startSessionRefreshMaintenance];
    }

    for (id item in completions) {
        NFBAtprotoSignInCompletion completion = (NFBAtprotoSignInCompletion)item;
        if (completion) completion(success, session, error);
    }
}

- (void)finishSessionRefreshForAccountDID:(NSString *)accountDID success:(BOOL)success session:(NSDictionary *)session error:(NSError *)error {
    NSArray *completions = nil;
    NSString *key = accountDID ?: @"";
    @synchronized (self) {
        completions = [self.sessionRefreshCompletionsByAccount[key] copy] ?: @[];
        [self.sessionRefreshCompletionsByAccount removeObjectForKey:key];
        [self.sessionRefreshAccountsInFlight removeObject:key];
        if (success) [self.sessionRefreshErrorsByAccount removeObjectForKey:key];
        else self.sessionRefreshErrorsByAccount[key] = error ?: [self.class genericError:@"OAuth refresh failed."];
    }

    if (success) [self startSessionRefreshMaintenance];

    for (id item in completions) {
        NFBAtprotoSignInCompletion completion = (NFBAtprotoSignInCompletion)item;
        if (completion) completion(success, session, error);
    }
}

- (BOOL)storeOAuthTokenResponse:(NSDictionary *)tokenResponse
                  forAccountDID:(NSString *)accountDID
                          issuer:(NSString *)issuer
                      serviceURL:(NSString *)serviceURL
                    tokenEndpoint:(NSString *)tokenEndpoint
                      redirectURI:(NSString *)redirectURI
                         clientID:(NSString *)clientID
                   dpopPrivateKey:(NSData *)dpopPrivateKey
                    expectedRefreshToken:(NSString *)expectedRefreshToken {
    if (![tokenResponse isKindOfClass:[NSDictionary class]] || accountDID.length == 0) return NO;
    NSString *accessToken = [tokenResponse[@"access_token"] isKindOfClass:NSString.class] ? tokenResponse[@"access_token"] : nil;
    id refreshValue = tokenResponse[@"refresh_token"];
    id subject = tokenResponse[@"sub"];
    if (accessToken.length == 0 || (refreshValue && (![refreshValue isKindOfClass:NSString.class] || [refreshValue length] == 0)) ||
        (subject && (![subject isKindOfClass:NSString.class] || ![subject isEqualToString:accountDID]))) return NO;
    NSDate *expiresAt = [self.class expirationDateForTokenResponse:tokenResponse];
    __block BOOL storedResponse = NO;
    dispatch_sync(self.stateQueue, ^{
        NSDictionary *current = nil;
        if ([self.did isEqualToString:accountDID]) current = [self storedSessionDictionaryLocked];
        else for (NSDictionary *account in [self storedAccountsMutableCopy]) {
            if ([[self.class accountDIDFromStoredDictionary:account] isEqualToString:accountDID]) { current = account; break; }
        }
        if (![current[@"refreshJwt"] isEqual:expectedRefreshToken] || ![current[@"dpopPrivateKey"] isEqual:dpopPrivateKey]) return;

        NSString *responseDID = [tokenResponse[@"sub"] isKindOfClass:[NSString class]] ? tokenResponse[@"sub"] : nil;
        NSString *targetDID = responseDID.length > 0 ? responseDID : accountDID;
        BOOL activeAccount = [accountDID isEqualToString:self.did ?: @""];
        if (activeAccount) {
            if ([tokenResponse[@"access_token"] isKindOfClass:[NSString class]]) self.accessJwt = tokenResponse[@"access_token"];
            if ([tokenResponse[@"refresh_token"] isKindOfClass:[NSString class]]) self.refreshJwt = tokenResponse[@"refresh_token"];
            self.accessTokenExpiresAt = expiresAt;
            self.accessTokenLifetime = expiresAt ? MAX(1.0, [expiresAt timeIntervalSinceNow]) : 600.0;
            self.did = targetDID;
            if ([tokenResponse[@"token_type"] isKindOfClass:[NSString class]]) self.oauthTokenType = tokenResponse[@"token_type"];
            else self.oauthTokenType = @"DPoP";
            self.oauthIssuer = issuer ?: NFBAtprotoDefaultIssuer;
            self.oauthTokenEndpoint = tokenEndpoint;
            self.oauthClientID = clientID;
            self.oauthRedirectURI = redirectURI;
            self.serviceEndpoint = [self.class normalizedPDSServiceURL:serviceURL ?: NFBAtprotoDefaultService];
            self.dpopPrivateKeyData = dpopPrivateKey;
            storedResponse = YES;
        }

        NSMutableArray<NSDictionary *> *accounts = [self storedAccountsMutableCopy];
        NSUInteger existingIndex = NSNotFound;
        for (NSUInteger index = 0; index < accounts.count; index++) {
            NSString *storedDID = [self.class accountDIDFromStoredDictionary:accounts[index]];
            if ([storedDID isEqualToString:accountDID] || [storedDID isEqualToString:targetDID]) {
                existingIndex = index;
                break;
            }
        }
        if (existingIndex == NSNotFound && !activeAccount) return;

        NSMutableDictionary *stored = existingIndex == NSNotFound ? [NSMutableDictionary dictionary] : [accounts[existingIndex] mutableCopy];
        stored[@"did"] = targetDID;
        [stored removeObjectForKey:@"accessTokenExpiresAt"];
        if (expiresAt) stored[@"accessTokenExpiresAt"] = expiresAt;
        stored[@"accessTokenLifetime"] = @(expiresAt ? MAX(1.0, [expiresAt timeIntervalSinceNow]) : 600.0);
        if ([tokenResponse[@"access_token"] isKindOfClass:[NSString class]]) stored[@"accessJwt"] = tokenResponse[@"access_token"];
        if ([tokenResponse[@"refresh_token"] isKindOfClass:[NSString class]]) stored[@"refreshJwt"] = tokenResponse[@"refresh_token"];
        if (issuer.length > 0) stored[@"oauthIssuer"] = issuer;
        if (tokenEndpoint.length > 0) stored[@"oauthTokenEndpoint"] = tokenEndpoint;
        if (clientID.length > 0) stored[@"oauthClientID"] = clientID;
        if (redirectURI.length > 0) stored[@"oauthRedirectURI"] = redirectURI;
        NSString *tokenType = [tokenResponse[@"token_type"] isKindOfClass:[NSString class]] ? tokenResponse[@"token_type"] : @"DPoP";
        stored[@"oauthTokenType"] = tokenType;
        stored[@"serviceEndpoint"] = [self.class normalizedPDSServiceURL:serviceURL ?: NFBAtprotoDefaultService];
        if (dpopPrivateKey.length > 0) stored[@"dpopPrivateKey"] = dpopPrivateKey;

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if (existingIndex == NSNotFound) [accounts insertObject:stored atIndex:0];
        else accounts[existingIndex] = stored;
        [defaults setObject:accounts forKey:NFBAtprotoAccountsDefaultsKey];
        if (activeAccount) {
            [defaults setObject:stored forKey:NFBAtprotoDefaultsKey];
            [defaults setObject:targetDID forKey:NFBAtprotoActiveAccountDIDDefaultsKey];
        }
        [defaults synchronize];
        storedResponse = YES; // Also accept rotation for a saved, inactive account.
    });
    return storedResponse;
}

- (void)refreshSessionIfNeededForce:(BOOL)force {
    if (![self hasSession]) {
        [self stopSessionRefreshMaintenance];
        return;
    }

    if (!force && ![self shouldProactivelyRefreshAccessToken]) return;

    [self refreshSessionWithCompletion:^(BOOL success, NSDictionary *session, NSError *error) {
        if (!success) {
            NSLog(@"NotTwitter ATProto proactive token refresh failed: %@", error.localizedDescription ?: @"unknown error");
        }
    }];
}

- (BOOL)isCurrentAccountDID:(NSString *)did privateKey:(NSData *)key {
    __block BOOL matches;
    dispatch_sync(self.stateQueue, ^{
        matches = [self.did isEqualToString:did] && [self.dpopPrivateKeyData isEqual:key];
    });
    return matches;
}

- (BOOL)shouldProactivelyRefreshAccessToken {
    __block NSDate *expirationDate;
    __block NSString *accountDID;
    __block NSTimeInterval lifetime;
    dispatch_sync(self.stateQueue, ^{
        expirationDate = self.accessTokenExpiresAt ?: [self.class expirationDateForJWT:self.accessJwt];
        accountDID = self.did;
        lifetime = self.accessTokenLifetime > 0 ? self.accessTokenLifetime : 600.0;
    });
    @synchronized (self) {
        NSDate *lastAttempt = self.lastSessionRefreshAttemptDatesByAccount[accountDID ?: @""];
        return NFBTokenRefreshIsDue(expirationDate ? [expirationDate timeIntervalSinceNow] : 0.0,
                                   lifetime, [self.sessionRefreshAccountsInFlight containsObject:accountDID ?: @""],
                                   lastAttempt ? -[lastAttempt timeIntervalSinceNow] : INFINITY);
    }
}

- (BOOL)isAccessTokenExpired {
    __block BOOL expired;
    dispatch_sync(self.stateQueue, ^{
        NSDate *expirationDate = self.accessTokenExpiresAt ?: [self.class expirationDateForJWT:self.accessJwt];
        expired = !expirationDate || [expirationDate timeIntervalSinceNow] <= 0.0;
    });
    return expired;
}

- (void)signOut {
    [self cancelPendingOAuthSignIn];
    NSString *activeDID = self.did;
    if (activeDID.length > 0) {
        [self removeAccountWithDID:activeDID];
        return;
    }
    dispatch_sync(self.stateQueue, ^{
        [self clearCurrentSessionLocked];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:NFBAtprotoDefaultsKey];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:NFBAtprotoActiveAccountDIDDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
    [self stopSessionRefreshMaintenance];
    [self postSessionChangedNotification];
}

- (BOOL)canSwitchToAccountWithDID:(NSString *)did {
    NSDictionary *stored = [self storedAccountForDID:did];
    return [stored[@"dpopPrivateKey"] isKindOfClass:NSData.class] && [stored[@"dpopPrivateKey"] length] > 0 &&
           [stored[@"accessJwt"] isKindOfClass:NSString.class] && [stored[@"accessJwt"] length] > 0 &&
           [stored[@"refreshJwt"] isKindOfClass:NSString.class] && [stored[@"refreshJwt"] length] > 0;
}

- (BOOL)switchToAccountWithDID:(NSString *)did {
    if (did.length == 0) return NO;
    [self cancelPendingOAuthSignIn];
    __block BOOL switched = NO;
    dispatch_sync(self.stateQueue, ^{
        [self saveStoredSessionLocked];
        NSArray<NSDictionary *> *accounts = [[NSUserDefaults standardUserDefaults] arrayForKey:NFBAtprotoAccountsDefaultsKey];
        for (NSDictionary *stored in accounts) {
            if (![stored isKindOfClass:[NSDictionary class]]) continue;
            NSString *storedDID = [self.class accountDIDFromStoredDictionary:stored];
            if (![storedDID isEqualToString:did]) continue;
            if (![stored[@"dpopPrivateKey"] isKindOfClass:NSData.class] || [stored[@"dpopPrivateKey"] length] == 0 ||
                ![stored[@"accessJwt"] isKindOfClass:NSString.class] || [stored[@"accessJwt"] length] == 0 ||
                ![stored[@"refreshJwt"] isKindOfClass:NSString.class] || [stored[@"refreshJwt"] length] == 0) return;
            [self applyStoredSessionDictionaryLocked:stored];
            if (self.dpopPrivateKeyData.length == 0 || self.accessJwt.length == 0 || self.refreshJwt.length == 0) return;
            [[NSUserDefaults standardUserDefaults] setObject:stored forKey:NFBAtprotoDefaultsKey];
            [[NSUserDefaults standardUserDefaults] setObject:storedDID forKey:NFBAtprotoActiveAccountDIDDefaultsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self.dpopNonces removeAllObjects];
            switched = YES;
            return;
        }
    });
    if (switched) {
        [self startSessionRefreshMaintenance];
        [self refreshSessionIfNeededForce:NO];
        [self postSessionChangedNotification];
    }
    return switched;
}

- (BOOL)removeAccountWithDID:(NSString *)did {
    if (did.length == 0) return NO;
    [self cancelPendingOAuthSignIn];
    @synchronized (self) {
        [self.sessionRefreshAccountsInFlight removeObject:did];
        [self.sessionRefreshCompletionsByAccount removeObjectForKey:did];
        [self.lastSessionRefreshAttemptDatesByAccount removeObjectForKey:did];
    }
    __block BOOL activeRemoved = NO;
    __block BOOL removed = NO;
    dispatch_sync(self.stateQueue, ^{
        NSMutableArray<NSDictionary *> *accounts = [self storedAccountsMutableCopy];
        NSMutableArray<NSDictionary *> *remaining = [NSMutableArray array];
        for (NSDictionary *stored in accounts) {
            NSString *storedDID = [self.class accountDIDFromStoredDictionary:stored];
            if ([storedDID isEqualToString:did]) {
                removed = YES;
                activeRemoved = activeRemoved || [storedDID isEqualToString:self.did ?: @""];
                continue;
            }
            if (stored) [remaining addObject:stored];
        }

        [[NSUserDefaults standardUserDefaults] setObject:remaining forKey:NFBAtprotoAccountsDefaultsKey];
        if (activeRemoved) {
            NSDictionary *nextAccount = remaining.firstObject;
            if ([nextAccount isKindOfClass:[NSDictionary class]]) {
                [self applyStoredSessionDictionaryLocked:nextAccount];
                NSString *nextDID = [self.class accountDIDFromStoredDictionary:nextAccount];
                if (nextDID.length > 0) [[NSUserDefaults standardUserDefaults] setObject:nextDID forKey:NFBAtprotoActiveAccountDIDDefaultsKey];
                [[NSUserDefaults standardUserDefaults] setObject:nextAccount forKey:NFBAtprotoDefaultsKey];
            } else {
                [self clearCurrentSessionLocked];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:NFBAtprotoDefaultsKey];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:NFBAtprotoActiveAccountDIDDefaultsKey];
            }
            [self.dpopNonces removeAllObjects];
        }
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
    if (removed || activeRemoved) {
        if ([self hasSession]) {
            [self startSessionRefreshMaintenance];
            [self refreshSessionIfNeededForce:NO];
        } else {
            [self stopSessionRefreshMaintenance];
        }
        [self postSessionChangedNotification];
    }
    return removed;
}

- (void)xrpcGET:(NSString *)method
        service:(NSString *)serviceURL
         params:(NSDictionary<NSString *,id> *)params
  authenticated:(BOOL)authenticated
     completion:(NFBAtprotoValueCompletion)completion {
    if (serviceURL.length == 0 && authenticated) {
        [self resolveCurrentPDSIfNeededWithCompletion:^(NSString *service) {
            [self sendXrpc:method
                   service:service
                    method:@"GET"
                      body:nil
                    params:params
             authenticated:authenticated
                     proxy:nil
              refreshOn401:YES
                completion:completion];
        }];
        return;
    }

    NSString *service = serviceURL.length > 0 ? [self.class normalizedServiceURL:serviceURL] : [self pdsServiceEndpoint];
    [self sendXrpc:method
           service:service
            method:@"GET"
              body:nil
            params:params
     authenticated:authenticated
             proxy:nil
      refreshOn401:YES
        completion:completion];
}

- (void)xrpcPOST:(NSString *)method
         service:(NSString *)serviceURL
            body:(NSDictionary<NSString *,id> *)body
   authenticated:(BOOL)authenticated
      completion:(NFBAtprotoValueCompletion)completion {
    if (serviceURL.length == 0 && authenticated) {
        [self resolveCurrentPDSIfNeededWithCompletion:^(NSString *service) {
            [self sendXrpc:method
                   service:service
                    method:@"POST"
                      body:body
                    params:nil
             authenticated:authenticated
                     proxy:nil
              refreshOn401:YES
                completion:completion];
        }];
        return;
    }

    NSString *service = serviceURL.length > 0 ? [self.class normalizedServiceURL:serviceURL] : [self pdsServiceEndpoint];
    [self sendXrpc:method
           service:service
            method:@"POST"
              body:body
            params:nil
     authenticated:authenticated
             proxy:nil
      refreshOn401:YES
        completion:completion];
}

- (void)xrpcPOSTData:(NSString *)method
              service:(NSString *)serviceURL
                 data:(NSData *)data
          contentType:(NSString *)contentType
        authenticated:(BOOL)authenticated
           completion:(NFBAtprotoValueCompletion)completion {
    if (serviceURL.length == 0 && authenticated) {
        [self resolveCurrentPDSIfNeededWithCompletion:^(NSString *service) {
            [self sendXrpcData:method
                       service:service
                          data:data
                   contentType:contentType
                 authenticated:authenticated
                  refreshOn401:YES
        allowProactiveRefresh:YES
                    completion:completion];
        }];
        return;
    }

    NSString *service = serviceURL.length > 0 ? [self.class normalizedServiceURL:serviceURL] : [self pdsServiceEndpoint];
    [self sendXrpcData:method
               service:service
                  data:data
           contentType:contentType
         authenticated:authenticated
          refreshOn401:YES
allowProactiveRefresh:YES
            completion:completion];
}

- (void)xrpcGETViaAppViewProxy:(NSString *)method
                         params:(NSDictionary<NSString *,id> *)params
                     completion:(NFBAtprotoValueCompletion)completion {
    [self resolveCurrentPDSIfNeededWithCompletion:^(NSString *service) {
        [self sendXrpc:method
               service:service
                method:@"GET"
                  body:nil
                params:params
         authenticated:YES
                 proxy:NFBAtprotoAppViewProxy
          refreshOn401:YES
            completion:completion];
    }];
}

- (void)xrpcPOSTViaAppViewProxy:(NSString *)method
                           body:(NSDictionary<NSString *,id> *)body
                     completion:(NFBAtprotoValueCompletion)completion {
    [self resolveCurrentPDSIfNeededWithCompletion:^(NSString *service) {
        [self sendXrpc:method
               service:service
                method:@"POST"
                  body:body
                params:nil
         authenticated:YES
                 proxy:NFBAtprotoAppViewProxy
          refreshOn401:YES
            completion:completion];
    }];
}

- (void)xrpcGETViaChatProxy:(NSString *)method
                      params:(NSDictionary<NSString *,id> *)params
                  completion:(NFBAtprotoValueCompletion)completion {
    [self resolveCurrentPDSIfNeededWithCompletion:^(NSString *service) {
        [self sendXrpc:method
               service:service
                method:@"GET"
                  body:nil
                params:params
         authenticated:YES
                 proxy:NFBAtprotoChatProxy
          refreshOn401:YES
            completion:completion];
    }];
}

- (void)xrpcPOSTViaChatProxy:(NSString *)method
                        body:(NSDictionary<NSString *,id> *)body
                  completion:(NFBAtprotoValueCompletion)completion {
    [self resolveCurrentPDSIfNeededWithCompletion:^(NSString *service) {
        [self sendXrpc:method
               service:service
                method:@"POST"
                  body:body
                params:nil
         authenticated:YES
                 proxy:NFBAtprotoChatProxy
          refreshOn401:YES
            completion:completion];
    }];
}

- (NSString *)pdsServiceEndpoint {
    return [self.class normalizedPDSServiceURL:self.serviceEndpoint];
}

- (void)resolveCurrentPDSIfNeededWithCompletion:(void (^)(NSString *serviceEndpoint))completion {
    NSString *currentService = [self pdsServiceEndpoint];
    NSString *defaultService = [self.class normalizedServiceURL:NFBAtprotoDefaultService];
    NSString *did = self.did;
    if (did.length == 0 || ![currentService isEqualToString:defaultService]) {
        if (completion) completion(currentService);
        return;
    }

    [self resolvePDSForDID:did completion:^(NSString *resolvedService) {
        NSString *service = [self.class normalizedPDSServiceURL:resolvedService ?: currentService];
        dispatch_sync(self.stateQueue, ^{
            self.serviceEndpoint = service;
            [self saveStoredSessionLocked];
        });
        if (completion) completion(service);
    }];
}

- (NSDictionary *)currentAccountDictionary {
    __block NSDictionary *account;
    dispatch_sync(self.stateQueue, ^{
        NSString *did = self.did ?: @"did:plc:nottwitter";
        NSString *handle = self.handle ?: @"bsky.app";
        NSDictionary *profile = self.profile ?: @{};
        NSString *displayName = [profile[@"displayName"] isKindOfClass:NSString.class] && [profile[@"displayName"] length] > 0 ? profile[@"displayName"] : handle;
        NSString *avatar = [profile[@"avatar"] isKindOfClass:NSString.class] ? profile[@"avatar"] : @"";
        account = @{@"did": did, @"handle": handle, @"displayName": displayName, @"avatar": avatar};
    });
    return account;
}

- (void)updateProfileFromDictionary:(NSDictionary *)profile {
    if (![profile isKindOfClass:[NSDictionary class]]) return;
    dispatch_sync(self.stateQueue, ^{
        // The response may have started before the user switched accounts.
        if (![profile[@"did"] isKindOfClass:NSString.class] || ![self.did isEqualToString:profile[@"did"]]) return;
        self.profile = profile;
        if ([profile[@"handle"] isKindOfClass:[NSString class]]) self.handle = profile[@"handle"];
        [self saveStoredSessionLocked];
    });
}

- (void)handleOAuthCallbackParams:(NSDictionary<NSString *, NSString *> *)params completion:(NFBAtprotoSignInCompletion)completion {
    NSString *state = params[@"state"];
    NSString *code = params[@"code"];
    NSString *issuer = params[@"iss"];
    NSString *errorString = params[@"error"];

    if (errorString.length > 0) {
        [self cancelPendingOAuthSignIn];
        if (completion) completion(NO, nil, [self.class genericError:errorString]);
        return;
    }

    if (self.pendingOAuthState.length == 0 || ![state isEqualToString:self.pendingOAuthState]) {
        [self cancelPendingOAuthSignIn];
        if (completion) completion(NO, nil, [self.class genericError:@"Bluesky OAuth state did not match."]);
        return;
    }

    if (self.pendingOAuthIssuer.length > 0 && issuer.length > 0 && ![issuer isEqualToString:self.pendingOAuthIssuer]) {
        [self cancelPendingOAuthSignIn];
        if (completion) completion(NO, nil, [self.class genericError:@"Bluesky OAuth issuer did not match."]);
        return;
    }

    if (code.length == 0) {
        [self cancelPendingOAuthSignIn];
        if (completion) completion(NO, nil, [self.class genericError:@"Bluesky OAuth did not return a code."]);
        return;
    }

    self.pendingOAuthCallbackReceived = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NFBAtprotoOAuthCallbackReceivedNotification object:self];
    });

    NSString *tokenEndpoint = self.pendingOAuthTokenEndpoint;
    NSString *clientID = self.pendingOAuthClientID;
    NSString *redirectURI = self.pendingOAuthRedirectURI;
    NSString *verifier = self.pendingOAuthVerifier;
    NSString *serviceEndpoint = self.pendingOAuthServiceEndpoint ?: NFBAtprotoDefaultService;
    NSString *resolvedIssuer = self.pendingOAuthIssuer ?: issuer ?: NFBAtprotoDefaultIssuer;
    NSData *dpopKeyData = self.pendingOAuthDpopPrivateKeyData;

    NSDictionary *form = @{
        @"grant_type": @"authorization_code",
        @"redirect_uri": redirectURI ?: @"",
        @"code": code,
        @"code_verifier": verifier ?: @"",
        @"client_id": clientID ?: @""
    };

    [self sendOAuthFormRequestToURL:tokenEndpoint
                               form:form
                     dpopPrivateKey:dpopKeyData
                 authorizationToken:nil
                         completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        if (error || ![value isKindOfClass:[NSDictionary class]]) {
            [self cancelPendingOAuthSignIn];
            if (completion) completion(NO, nil, error ?: [self.class genericError:@"Bluesky OAuth token exchange failed."]);
            return;
        }

        NSDictionary *tokenResponse = (NSDictionary *)value;
        NSString *subjectDID = [tokenResponse[@"sub"] isKindOfClass:[NSString class]] ? tokenResponse[@"sub"] : nil;
        if (subjectDID.length == 0 || ![tokenResponse[@"access_token"] isKindOfClass:NSString.class] ||
            [tokenResponse[@"access_token"] length] == 0 || ![tokenResponse[@"refresh_token"] isKindOfClass:NSString.class] ||
            [tokenResponse[@"refresh_token"] length] == 0) {
            [self cancelPendingOAuthSignIn];
            if (completion) completion(NO, nil, [self.class genericError:@"Bluesky returned an incomplete OAuth session."]);
            return;
        }
        [self resolvePDSForDID:subjectDID completion:^(NSString *resolvedServiceEndpoint) {
            NSString *tokenServiceEndpoint = resolvedServiceEndpoint.length > 0 ? resolvedServiceEndpoint : serviceEndpoint;
            [self applyOAuthTokenResponse:tokenResponse
                                issuer:resolvedIssuer
                            serviceURL:tokenServiceEndpoint
                           tokenEndpoint:tokenEndpoint
                             redirectURI:redirectURI
                                clientID:clientID
                          dpopPrivateKey:dpopKeyData];
            [self cancelPendingOAuthSignIn];
            [self fetchCurrentProfileWithCompletion:^{
                [self postSessionChangedNotification];
                if (completion) completion(YES, tokenResponse, nil);
            }];
        }];
    }];
}

- (void)fetchCurrentProfileWithCompletion:(void (^)(void))completion {
    NSString *actor = self.did ?: self.handle;
    if (actor.length == 0) {
        if (completion) completion();
        return;
    }

    [self xrpcGET:@"app.bsky.actor.getProfile"
          service:NFBAtprotoDirectAppView
           params:@{@"actor": actor}
    authenticated:NO
       completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        if ([value isKindOfClass:[NSDictionary class]]) {
            [self updateProfileFromDictionary:value];
        }
        if (completion) completion();
    }];
}

- (void)xrpcPOST:(NSString *)method forAccountDID:(NSString *)accountDID body:(NSDictionary *)body completion:(NFBAtprotoValueCompletion)completion {
    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    if (!data) { if (completion) completion(nil, nil, error); return; }
    [self xrpcPOSTData:method forAccountDID:accountDID data:data contentType:@"application/json" completion:completion];
}

- (void)xrpcPOSTData:(NSString *)method forAccountDID:(NSString *)accountDID data:(NSData *)data contentType:(NSString *)contentType completion:(NFBAtprotoValueCompletion)completion {
    NSDictionary *account = [self storedAccountForDID:accountDID];
    NSData *key = account[@"dpopPrivateKey"];
    if (!key.length || ![account[@"accessJwt"] length]) {
        if (completion) completion(nil, nil, [self.class genericError:@"This account needs to be added again before it can be used."]);
        return;
    }
    NSString *service = [self.class normalizedPDSServiceURL:account[@"serviceEndpoint"] ?: NFBAtprotoDefaultService];
    void (^send)(NSString *) = ^(NSString *resolved) {
        if (!resolved.length) {
            if (completion) completion(nil, nil, [self.class genericError:@"Could not find this account's server. Please try again."]);
            return;
        }
        [self sendAccountPOST:method accountDID:accountDID privateKey:key service:resolved data:data contentType:contentType proactive:YES retry:YES completion:completion];
    };
    if ([service isEqualToString:NFBAtprotoDefaultService]) [self resolvePDSForDID:accountDID completion:send];
    else send(service);
}

- (void)sendAccountPOST:(NSString *)method accountDID:(NSString *)accountDID privateKey:(NSData *)key
                service:(NSString *)service data:(NSData *)data contentType:(NSString *)contentType
              proactive:(BOOL)proactive retry:(BOOL)retry completion:(NFBAtprotoValueCompletion)completion {
    NSDictionary *account = [self storedAccountForDID:accountDID];
    NSString *token = account[@"accessJwt"];
    if (!token.length || ![account[@"dpopPrivateKey"] isEqual:key]) {
        if (completion) completion(nil, nil, [self.class genericError:@"This account was removed or its login changed. Please try again."]);
        return;
    }
    NSDate *expiry = account[@"accessTokenExpiresAt"] ?: [self.class expirationDateForJWT:token];
    NSTimeInterval lifetime = [account[@"accessTokenLifetime"] doubleValue];
    BOOL refreshDue;
    @synchronized (self) {
        NSDate *attempt = self.lastSessionRefreshAttemptDatesByAccount[accountDID];
        refreshDue = NFBTokenRefreshIsDue(expiry ? [expiry timeIntervalSinceNow] : 0, lifetime > 0 ? lifetime : 600,
            [self.sessionRefreshAccountsInFlight containsObject:accountDID], attempt ? -[attempt timeIntervalSinceNow] : INFINITY);
    }
    if (proactive && refreshDue) {
        [self refreshSessionForAccountDID:accountDID privateKey:key rejectedToken:token completion:^(BOOL success, NSDictionary *value, NSError *error) {
            NSDictionary *fresh = [self storedAccountForDID:accountDID];
            NSDate *freshExpiry = fresh[@"accessTokenExpiresAt"] ?: [self.class expirationDateForJWT:fresh[@"accessJwt"]];
            if (!success && (!freshExpiry || [freshExpiry timeIntervalSinceNow] <= 0)) {
                if (completion) completion(nil, nil, error); return;
            }
            [self sendAccountPOST:method accountDID:accountDID privateKey:key service:service data:data contentType:contentType proactive:NO retry:retry completion:completion];
        }];
        return;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/%@", service, method]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 180;
    request.HTTPBody = data;
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"%@ %@", account[@"oauthTokenType"] ?: @"DPoP", token] forHTTPHeaderField:@"Authorization"];
    [self addDPoPHeaderToRequest:request privateKeyData:key authorizationToken:token];
    [self sendRequest:request dpopKeyData:key authorizationToken:token retryOnNonce:YES completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        if (response.statusCode == 401 && retry) {
            [self refreshSessionForAccountDID:accountDID privateKey:key rejectedToken:token completion:^(BOOL success, NSDictionary *refreshed, NSError *refreshError) {
                if (!success) { if (completion) completion(value, response, refreshError ?: error); return; }
                [self sendAccountPOST:method accountDID:accountDID privateKey:key service:service data:data contentType:contentType proactive:NO retry:NO completion:completion];
            }];
        } else if (completion) completion(value, response, error);
    }];
}

- (void)sendXrpc:(NSString *)xrpcMethod
         service:(NSString *)service
          method:(NSString *)httpMethod
            body:(NSDictionary *)body
          params:(NSDictionary *)params
   authenticated:(BOOL)authenticated
          proxy:(NSString *)proxy
    refreshOn401:(BOOL)refreshOn401
      completion:(NFBAtprotoValueCompletion)completion {
    [self sendXrpc:xrpcMethod
           service:service
            method:httpMethod
              body:body
            params:params
     authenticated:authenticated
             proxy:proxy
      refreshOn401:refreshOn401
allowProactiveRefresh:YES
        completion:completion];
}

- (void)sendXrpc:(NSString *)xrpcMethod
         service:(NSString *)service
          method:(NSString *)httpMethod
            body:(NSDictionary *)body
          params:(NSDictionary *)params
   authenticated:(BOOL)authenticated
          proxy:(NSString *)proxy
    refreshOn401:(BOOL)refreshOn401
allowProactiveRefresh:(BOOL)allowProactiveRefresh
      completion:(NFBAtprotoValueCompletion)completion {
    [self sendXrpc:xrpcMethod service:service method:httpMethod body:body params:params
     authenticated:authenticated proxy:proxy refreshOn401:refreshOn401
     allowProactiveRefresh:allowProactiveRefresh expectedDID:nil expectedKey:nil completion:completion];
}

- (void)sendXrpc:(NSString *)xrpcMethod
         service:(NSString *)service
          method:(NSString *)httpMethod
            body:(NSDictionary *)body
          params:(NSDictionary *)params
   authenticated:(BOOL)authenticated
          proxy:(NSString *)proxy
    refreshOn401:(BOOL)refreshOn401
allowProactiveRefresh:(BOOL)allowProactiveRefresh
      expectedDID:(NSString *)expectedDID
      expectedKey:(NSData *)expectedKey
      completion:(NFBAtprotoValueCompletion)completion {
    NSUInteger accountGeneration = self.accountGeneration;
    __block BOOL sessionChanged = NO;
    __block NSString *requestAccountDID = @"";
    __block NSString *token = nil;
    __block NSString *tokenType = nil;
    __block NSData *dpopKeyData = nil;
    dispatch_sync(self.stateQueue, ^{
        if (authenticated) {
            if (expectedDID && (![self.did isEqualToString:expectedDID] || ![self.dpopPrivateKeyData isEqual:expectedKey])) { sessionChanged = YES; return; }
            requestAccountDID = self.did ?: @"";
            token = self.accessJwt;
            tokenType = self.oauthTokenType ?: @"DPoP";
            dpopKeyData = self.dpopPrivateKeyData;
        }
    });
    if (sessionChanged) {
        if (completion) completion(nil, nil, [self.class genericError:@"The active session changed before the request could be retried."]);
        return;
    }
    if (authenticated && allowProactiveRefresh && [self shouldProactivelyRefreshAccessToken]) {
        [self refreshSessionForAccountDID:requestAccountDID privateKey:dpopKeyData rejectedToken:token completion:^(BOOL success, NSDictionary *session, NSError *refreshError) {
            if (![self isCurrentAccountDID:requestAccountDID privateKey:dpopKeyData]) {
                if (completion) completion(nil, nil, [self.class genericError:@"The active account changed before this request could be sent."]);
                return;
            }
            if (!success && [self isAccessTokenExpired]) {
                if (completion) completion(nil, nil, refreshError ?: [self.class genericError:@"Bluesky OAuth refresh failed."]);
                return;
            }
            [self sendXrpc:xrpcMethod
                   service:service
                    method:httpMethod
                      body:body
                    params:params
             authenticated:authenticated
                     proxy:proxy
              refreshOn401:refreshOn401
allowProactiveRefresh:NO
                expectedDID:requestAccountDID
                expectedKey:dpopKeyData
                completion:completion];
        }];
        return;
    }

    NSURL *url = [self.class xrpcURLWithService:service method:xrpcMethod params:params];
    if (!url) {
        if (completion) completion(nil, nil, [self.class genericError:@"Invalid ATProto service URL."]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = httpMethod ?: @"GET";
    if ([xrpcMethod isEqualToString:@"app.bsky.embed.getEmbedExternalView"]) {
        request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    }
    request.timeoutInterval = 20.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"NotTwitter/1 ATProto OAuth" forHTTPHeaderField:@"User-Agent"];

    if (token.length > 0 && dpopKeyData.length > 0) {
        [request setValue:[NSString stringWithFormat:@"%@ %@", tokenType, token] forHTTPHeaderField:@"Authorization"];
        [self addDPoPHeaderToRequest:request privateKeyData:dpopKeyData authorizationToken:token];
    }

    if (proxy.length > 0) {
        [request setValue:proxy forHTTPHeaderField:@"atproto-proxy"];
    }

    if (body) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }

    NSLog(@"NotTwitter ATProto %@ %@ host=%@ proxy=%@ auth=%@",
          request.HTTPMethod ?: @"GET",
          xrpcMethod ?: @"",
          request.URL.host ?: @"",
          proxy.length > 0 ? proxy : @"none",
          token.length > 0 ? @"yes" : @"no");

    [self sendRequest:request dpopKeyData:dpopKeyData authorizationToken:token retryOnNonce:YES completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        if ([request.HTTPMethod isEqualToString:@"GET"] && accountGeneration != self.accountGeneration) {
            if (completion) completion(nil, response, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
            return;
        }
        if (response.statusCode == 401 && authenticated && refreshOn401) {
            if (![self isCurrentAccountDID:requestAccountDID privateKey:dpopKeyData]) {
                if (completion) completion(value, response, error);
                return;
            }
            [self refreshSessionForAccountDID:requestAccountDID privateKey:dpopKeyData rejectedToken:token completion:^(BOOL success, NSDictionary *session, NSError *refreshError) {
                if (![self isCurrentAccountDID:requestAccountDID privateKey:dpopKeyData]) {
                    if (completion) completion(nil, response, [self.class genericError:@"The active session changed before the request could be retried."]);
                    return;
                }
                if (!success) {
                    if (completion) completion(nil, response, refreshError ?: error);
                    return;
                }
                [self sendXrpc:xrpcMethod
                       service:service
                        method:httpMethod
                          body:body
                        params:params
                 authenticated:authenticated
                         proxy:proxy
                  refreshOn401:NO
         allowProactiveRefresh:NO
                    expectedDID:requestAccountDID
                    expectedKey:dpopKeyData
                    completion:completion];
            }];
            return;
        }

        if (completion) completion(value, response, error);
    }];
}

- (void)sendXrpcData:(NSString *)xrpcMethod
             service:(NSString *)service
                data:(NSData *)data
         contentType:(NSString *)contentType
       authenticated:(BOOL)authenticated
        refreshOn401:(BOOL)refreshOn401
allowProactiveRefresh:(BOOL)allowProactiveRefresh
          completion:(NFBAtprotoValueCompletion)completion {
    [self sendXrpcData:xrpcMethod service:service data:data contentType:contentType
     authenticated:authenticated refreshOn401:refreshOn401
     allowProactiveRefresh:allowProactiveRefresh expectedDID:nil expectedKey:nil completion:completion];
}

- (void)sendXrpcData:(NSString *)xrpcMethod
             service:(NSString *)service
                data:(NSData *)data
         contentType:(NSString *)contentType
       authenticated:(BOOL)authenticated
        refreshOn401:(BOOL)refreshOn401
allowProactiveRefresh:(BOOL)allowProactiveRefresh
          expectedDID:(NSString *)expectedDID
      expectedKey:(NSData *)expectedKey
      completion:(NFBAtprotoValueCompletion)completion {
    __block BOOL sessionChanged = NO;
    __block NSString *requestAccountDID = @"";
    __block NSString *token = nil;
    __block NSString *tokenType = nil;
    __block NSData *dpopKeyData = nil;
    dispatch_sync(self.stateQueue, ^{
        if (authenticated) {
            if (expectedDID && (![self.did isEqualToString:expectedDID] || ![self.dpopPrivateKeyData isEqual:expectedKey])) { sessionChanged = YES; return; }
            requestAccountDID = self.did ?: @"";
            token = self.accessJwt;
            tokenType = self.oauthTokenType ?: @"DPoP";
            dpopKeyData = self.dpopPrivateKeyData;
        }
    });
    if (sessionChanged) {
        if (completion) completion(nil, nil, [self.class genericError:@"The active session changed before the request could be retried."]);
        return;
    }
    if (authenticated && allowProactiveRefresh && [self shouldProactivelyRefreshAccessToken]) {
        [self refreshSessionForAccountDID:requestAccountDID privateKey:dpopKeyData rejectedToken:token completion:^(BOOL success, NSDictionary *session, NSError *refreshError) {
            if (![self isCurrentAccountDID:requestAccountDID privateKey:dpopKeyData]) {
                if (completion) completion(nil, nil, [self.class genericError:@"The active account changed before this request could be sent."]);
                return;
            }
            if (!success && [self isAccessTokenExpired]) {
                if (completion) completion(nil, nil, refreshError ?: [self.class genericError:@"Bluesky OAuth refresh failed."]);
                return;
            }
            [self sendXrpcData:xrpcMethod
                       service:service
                          data:data
                   contentType:contentType
                 authenticated:authenticated
                  refreshOn401:refreshOn401
        allowProactiveRefresh:NO
                    expectedDID:requestAccountDID
                    expectedKey:dpopKeyData
                    completion:completion];
        }];
        return;
    }

    NSURL *url = [self.class xrpcURLWithService:service method:xrpcMethod params:nil];
    if (!url) {
        if (completion) completion(nil, nil, [self.class genericError:@"Invalid ATProto service URL."]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 90.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"NotTwitter/1 ATProto OAuth" forHTTPHeaderField:@"User-Agent"];
    [request setValue:contentType.length > 0 ? contentType : @"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = data ?: [NSData data];

    if (token.length > 0 && dpopKeyData.length > 0) {
        [request setValue:[NSString stringWithFormat:@"%@ %@", tokenType, token] forHTTPHeaderField:@"Authorization"];
        [self addDPoPHeaderToRequest:request privateKeyData:dpopKeyData authorizationToken:token];
    }

    NSLog(@"NotTwitter ATProto POST %@ host=%@ bytes=%lu auth=%@",
          xrpcMethod ?: @"",
          request.URL.host ?: @"",
          (unsigned long)request.HTTPBody.length,
          token.length > 0 ? @"yes" : @"no");

    [self sendRequest:request dpopKeyData:dpopKeyData authorizationToken:token retryOnNonce:YES completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        if (response.statusCode == 401 && authenticated && refreshOn401) {
            if (![self isCurrentAccountDID:requestAccountDID privateKey:dpopKeyData]) {
                if (completion) completion(value, response, error);
                return;
            }
            [self refreshSessionForAccountDID:requestAccountDID privateKey:dpopKeyData rejectedToken:token completion:^(BOOL success, NSDictionary *session, NSError *refreshError) {
                if (![self isCurrentAccountDID:requestAccountDID privateKey:dpopKeyData]) {
                    if (completion) completion(nil, response, [self.class genericError:@"The active session changed before the request could be retried."]);
                    return;
                }
                if (!success) {
                    if (completion) completion(nil, response, refreshError ?: error);
                    return;
                }
                [self sendXrpcData:xrpcMethod
                           service:service
                              data:data
                       contentType:contentType
                     authenticated:authenticated
                      refreshOn401:NO
            allowProactiveRefresh:NO
                        expectedDID:requestAccountDID
                        expectedKey:dpopKeyData
                        completion:completion];
            }];
            return;
        }

        if (completion) completion(value, response, error);
    }];
}

- (void)sendOAuthFormRequestToURL:(NSString *)urlString
                             form:(NSDictionary<NSString *, NSString *> *)form
                   dpopPrivateKey:(NSData *)dpopPrivateKeyData
               authorizationToken:(NSString *)authorizationToken
                       completion:(NFBAtprotoValueCompletion)completion {
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url) {
        if (completion) completion(nil, nil, [self.class genericError:@"Invalid Bluesky OAuth endpoint."]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"NotTwitter/1 ATProto OAuth" forHTTPHeaderField:@"User-Agent"];
    if (authorizationToken.length > 0) {
        [request setValue:[NSString stringWithFormat:@"DPoP %@", authorizationToken] forHTTPHeaderField:@"Authorization"];
    }
    request.HTTPBody = [[self.class formEncodedStringForDictionary:form] dataUsingEncoding:NSUTF8StringEncoding];
    [self addDPoPHeaderToRequest:request privateKeyData:dpopPrivateKeyData authorizationToken:authorizationToken];
    [self sendRequest:request dpopKeyData:dpopPrivateKeyData authorizationToken:authorizationToken retryOnNonce:YES completion:completion];
}

- (void)sendRequest:(NSMutableURLRequest *)request
        dpopKeyData:(NSData *)dpopKeyData
 authorizationToken:(NSString *)authorizationToken
       retryOnNonce:(BOOL)retryOnNonce
         completion:(NFBAtprotoValueCompletion)completion {
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *urlResponse, NSError *error) {
        NSHTTPURLResponse *response = [urlResponse isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)urlResponse : nil;
        id value = @{};

        if (data.length > 0) {
            NSError *jsonError = nil;
            value = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError) value = @{};
        }

        NSString *nonce = [response valueForHTTPHeaderField:@"DPoP-Nonce"];
        if (nonce.length > 0) {
            NSString *origin = [self.class originForURL:request.URL];
            if (origin.length > 0) dispatch_sync(self.stateQueue, ^{ self.dpopNonces[origin] = nonce; });
        }

        if (retryOnNonce && dpopKeyData.length > 0 && [self.class responseRequestsDpopNonce:response value:value]) {
            NSMutableURLRequest *retry = [request mutableCopy];
            [self addDPoPHeaderToRequest:retry privateKeyData:dpopKeyData authorizationToken:authorizationToken];
            [self sendRequest:retry dpopKeyData:dpopKeyData authorizationToken:authorizationToken retryOnNonce:NO completion:completion];
            return;
        }

        if (error) {
            if (completion) completion(nil, response, error);
            return;
        }

        if (response.statusCode >= 400) {
            NSString *message = [value isKindOfClass:[NSDictionary class]] && [value[@"message"] isKindOfClass:[NSString class]] ? value[@"message"] : nil;
            if (message.length == 0 && [value isKindOfClass:[NSDictionary class]] && [value[@"error_description"] isKindOfClass:[NSString class]]) message = value[@"error_description"];
            if (message.length == 0 && [value isKindOfClass:[NSDictionary class]] && [value[@"error"] isKindOfClass:[NSString class]]) message = value[@"error"];
            NSLog(@"NotTwitter ATProto error %ld host=%@ message=%@", (long)response.statusCode, request.URL.host ?: @"", message ?: @"ATProto request failed.");
            NSMutableDictionary *errorInfo = [@{NSLocalizedDescriptionKey: message ?: @"ATProto request failed."} mutableCopy];
            NSString *errorName = [value isKindOfClass:NSDictionary.class] && [value[@"error"] isKindOfClass:NSString.class] ? value[@"error"] : nil;
            if (errorName.length > 0) errorInfo[NFBChatErrorNameKey] = errorName;
            NSError *statusError = [NSError errorWithDomain:@"NFBAtprotoSession"
                                                       code:response.statusCode
                                                   userInfo:errorInfo];
            if (completion) completion(value, response, statusError);
            return;
        }

        if (completion) completion(value ?: @{}, response, nil);
    }];
    [task resume];
}

- (void)addDPoPHeaderToRequest:(NSMutableURLRequest *)request privateKeyData:(NSData *)privateKeyData authorizationToken:(NSString *)authorizationToken {
    NSString *origin = [self.class originForURL:request.URL];
    __block NSString *nonce = nil;
    dispatch_sync(self.stateQueue, ^{ nonce = origin.length > 0 ? self.dpopNonces[origin] : nil; });
    NSString *proof = [self.class dpopProofForRequest:request privateKeyData:privateKeyData nonce:nonce authorizationToken:authorizationToken];
    if (proof.length > 0) [request setValue:proof forHTTPHeaderField:@"DPoP"];
}

- (void)resolveOAuthContextForIdentifier:(NSString *)identifier completion:(void (^)(NSString *serviceEndpoint, NSDictionary *metadata, NSError *error))completion {
    [self resolvePDSForIdentifier:identifier completion:^(NSString *serviceEndpoint) {
        NSString *service = [self.class normalizedPDSServiceURL:serviceEndpoint ?: NFBAtprotoDefaultService];
        NSString *resourceMetadataURL = [service stringByAppendingString:@"/.well-known/oauth-protected-resource"];
        [self fetchJSONFromURL:resourceMetadataURL completion:^(id resourceValue, NSHTTPURLResponse *resourceResponse, NSError *resourceError) {
            NSArray *authorizationServers = [resourceValue isKindOfClass:[NSDictionary class]] && [resourceValue[@"authorization_servers"] isKindOfClass:[NSArray class]] ? resourceValue[@"authorization_servers"] : nil;
            NSString *issuer = nil;
            for (id server in authorizationServers) {
                if ([server isKindOfClass:[NSString class]] && [(NSString *)server length] > 0) {
                    issuer = [self.class normalizedServiceURL:server];
                    break;
                }
            }

            void (^fetchFallbackMetadata)(void) = ^{
                NSString *metadataURL = [service stringByAppendingString:@"/.well-known/oauth-authorization-server"];
                [self fetchJSONFromURL:metadataURL completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
                    if ([value isKindOfClass:[NSDictionary class]] && response.statusCode < 400) {
                        completion(service, value, nil);
                        return;
                    }

                    NSString *fallbackURL = [NFBAtprotoDefaultIssuer stringByAppendingString:@"/.well-known/oauth-authorization-server"];
                    [self fetchJSONFromURL:fallbackURL completion:^(id fallbackValue, NSHTTPURLResponse *fallbackResponse, NSError *fallbackError) {
                        if ([fallbackValue isKindOfClass:[NSDictionary class]] && fallbackResponse.statusCode < 400) {
                            completion(service, fallbackValue, nil);
                        } else {
                            completion(nil, nil, fallbackError ?: error ?: resourceError ?: [self.class genericError:@"Could not load Bluesky OAuth metadata."]);
                        }
                    }];
                }];
            };

            if (issuer.length == 0 || resourceResponse.statusCode >= 400) {
                fetchFallbackMetadata();
                return;
            }

            NSString *metadataURL = [issuer stringByAppendingString:@"/.well-known/oauth-authorization-server"];
            [self fetchJSONFromURL:metadataURL completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
                if ([value isKindOfClass:[NSDictionary class]] && response.statusCode < 400) {
                    completion(service, value, nil);
                } else {
                    fetchFallbackMetadata();
                }
            }];
        }];
    }];
}

- (void)resolvePDSForIdentifier:(NSString *)identifier completion:(void (^)(NSString *serviceEndpoint))completion {
    NSString *trimmed = [self.class normalizedLoginIdentifier:identifier];
    if ([trimmed hasPrefix:@"did:"]) {
        [self resolvePDSForDID:trimmed completion:completion];
        return;
    }

    NSString *handle = [trimmed lowercaseString];
    NSString *url = [NSString stringWithFormat:@"%@/xrpc/com.atproto.identity.resolveHandle?handle=%@", NFBAtprotoDefaultService, [self.class percentEncodedQueryValue:handle]];
    [self fetchJSONFromURL:url completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        NSString *did = [value isKindOfClass:[NSDictionary class]] && [value[@"did"] isKindOfClass:[NSString class]] ? value[@"did"] : nil;
        if (did.length > 0) {
            [self resolvePDSForDID:did completion:completion];
        } else {
            completion(NFBAtprotoDefaultService);
        }
    }];
}

- (void)resolvePDSForDID:(NSString *)did completion:(void (^)(NSString *serviceEndpoint))completion {
    NSString *urlString = nil;
    if ([did hasPrefix:@"did:plc:"]) {
        urlString = [@"https://plc.directory/" stringByAppendingString:did];
    } else if ([did hasPrefix:@"did:web:"]) {
        NSString *host = [[did substringFromIndex:[@"did:web:" length]] stringByReplacingOccurrencesOfString:@"%3A" withString:@":" options:NSCaseInsensitiveSearch range:NSMakeRange(0, did.length - [@"did:web:" length])];
        urlString = [NSString stringWithFormat:@"https://%@/.well-known/did.json", host];
    }

    if (urlString.length == 0) {
        completion(NFBAtprotoDefaultService);
        return;
    }

    [self fetchJSONFromURL:urlString completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        NSArray *services = [value isKindOfClass:[NSDictionary class]] ? value[@"service"] : nil;
        if ([services isKindOfClass:[NSArray class]]) {
            for (NSDictionary *service in services) {
                if (![service isKindOfClass:[NSDictionary class]]) continue;
                NSString *serviceID = [service[@"id"] isKindOfClass:[NSString class]] ? service[@"id"] : @"";
                NSString *type = [service[@"type"] isKindOfClass:[NSString class]] ? service[@"type"] : @"";
                NSString *endpoint = [service[@"serviceEndpoint"] isKindOfClass:[NSString class]] ? service[@"serviceEndpoint"] : nil;
                if ([serviceID isEqualToString:@"#atproto_pds"] || [type isEqualToString:@"AtprotoPersonalDataServer"]) {
                    completion(endpoint ?: NFBAtprotoDefaultService);
                    return;
                }
            }
        }
        completion(NFBAtprotoDefaultService);
    }];
}

- (void)fetchJSONFromURL:(NSString *)urlString completion:(NFBAtprotoValueCompletion)completion {
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url) {
        if (completion) completion(nil, nil, [self.class genericError:@"Invalid URL."]);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 15.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"NotTwitter/1 ATProto OAuth" forHTTPHeaderField:@"User-Agent"];
    [self sendRequest:request dpopKeyData:nil authorizationToken:nil retryOnNonce:NO completion:completion];
}

- (void)applyOAuthTokenResponse:(NSDictionary *)tokenResponse
                         issuer:(NSString *)issuer
                     serviceURL:(NSString *)serviceURL
                   tokenEndpoint:(NSString *)tokenEndpoint
                     redirectURI:(NSString *)redirectURI
                         clientID:(NSString *)clientID
                  dpopPrivateKey:(NSData *)dpopPrivateKey {
    dispatch_sync(self.stateQueue, ^{
        NSString *nextDID = [tokenResponse[@"sub"] isKindOfClass:NSString.class] ? tokenResponse[@"sub"] : self.did;
        if (![(self.did ?: @"") isEqualToString:nextDID ?: @""]) {
            self.accountGeneration++;
            self.profile = nil;
            self.handle = nil;
        }
        if ([tokenResponse[@"access_token"] isKindOfClass:[NSString class]]) self.accessJwt = tokenResponse[@"access_token"];
        if ([tokenResponse[@"refresh_token"] isKindOfClass:[NSString class]]) self.refreshJwt = tokenResponse[@"refresh_token"];
        self.accessTokenExpiresAt = [self.class expirationDateForTokenResponse:tokenResponse];
        self.accessTokenLifetime = self.accessTokenExpiresAt ? MAX(1.0, [self.accessTokenExpiresAt timeIntervalSinceNow]) : 600.0;
        if ([tokenResponse[@"sub"] isKindOfClass:[NSString class]]) self.did = tokenResponse[@"sub"];
        if ([tokenResponse[@"token_type"] isKindOfClass:[NSString class]]) self.oauthTokenType = tokenResponse[@"token_type"];
        else self.oauthTokenType = @"DPoP";
        self.oauthIssuer = issuer ?: NFBAtprotoDefaultIssuer;
        self.oauthTokenEndpoint = tokenEndpoint;
        self.oauthClientID = clientID;
        self.oauthRedirectURI = redirectURI;
        self.serviceEndpoint = [self.class normalizedPDSServiceURL:serviceURL ?: NFBAtprotoDefaultService];
        self.dpopPrivateKeyData = dpopPrivateKey;
        [self saveStoredSessionLocked];
    });
    [self startSessionRefreshMaintenance];
}

- (void)clearCurrentSessionLocked {
    if (self.did.length) self.accountGeneration++;
    self.accessJwt = nil;
    self.accessTokenExpiresAt = nil;
    self.accessTokenLifetime = 0;
    self.refreshJwt = nil;
    self.did = nil;
    self.handle = nil;
    self.profile = nil;
    self.serviceEndpoint = NFBAtprotoDefaultService;
    self.oauthIssuer = NFBAtprotoDefaultIssuer;
    self.oauthAuthorizationEndpoint = nil;
    self.oauthTokenEndpoint = nil;
    self.oauthPAREndpoint = nil;
    self.oauthRevocationEndpoint = nil;
    self.oauthClientID = nil;
    self.oauthRedirectURI = nil;
    self.oauthTokenType = @"DPoP";
    self.dpopPrivateKeyData = nil;
    [self.dpopNonces removeAllObjects];
}

// Must be called on stateQueue. An absent account deliberately has no fallback.
- (NSDictionary *)storedAccountForDIDLocked:(NSString *)accountDID {
    if (!accountDID.length) return nil;
    if ([self.did isEqualToString:accountDID]) return [self storedSessionDictionaryLocked];
    for (NSDictionary *account in [self storedAccountsMutableCopy]) {
        if ([[self.class accountDIDFromStoredDictionary:account] isEqualToString:accountDID]) return account;
    }
    return nil;
}

- (NSDictionary *)storedAccountForDID:(NSString *)accountDID {
    __block NSDictionary *account;
    dispatch_sync(self.stateQueue, ^{ account = [self storedAccountForDIDLocked:accountDID]; });
    return account;
}

- (NSDictionary *)storedSessionDictionaryLocked {
    NSMutableDictionary *stored = [NSMutableDictionary dictionary];
    if (self.accessJwt) stored[@"accessJwt"] = self.accessJwt;
    if (self.accessTokenExpiresAt) stored[@"accessTokenExpiresAt"] = self.accessTokenExpiresAt;
    stored[@"accessTokenLifetime"] = @(self.accessTokenLifetime);
    if (self.refreshJwt) stored[@"refreshJwt"] = self.refreshJwt;
    if (self.did) stored[@"did"] = self.did;
    if (self.handle) stored[@"handle"] = self.handle;
    if (self.serviceEndpoint) stored[@"serviceEndpoint"] = self.serviceEndpoint;
    if (self.profile) stored[@"profile"] = self.profile;
    if (self.oauthIssuer) stored[@"oauthIssuer"] = self.oauthIssuer;
    if (self.oauthTokenEndpoint) stored[@"oauthTokenEndpoint"] = self.oauthTokenEndpoint;
    if (self.oauthClientID) stored[@"oauthClientID"] = self.oauthClientID;
    if (self.oauthRedirectURI) stored[@"oauthRedirectURI"] = self.oauthRedirectURI;
    if (self.oauthTokenType) stored[@"oauthTokenType"] = self.oauthTokenType;
    if (self.dpopPrivateKeyData) stored[@"dpopPrivateKey"] = self.dpopPrivateKeyData;
    return [stored copy];
}

- (void)applyStoredSessionDictionaryLocked:(NSDictionary *)stored {
    if (![stored isKindOfClass:[NSDictionary class]]) {
        [self clearCurrentSessionLocked];
        return;
    }
    NSString *nextDID = [self.class accountDIDFromStoredDictionary:stored];
    if (![(self.did ?: @"") isEqualToString:nextDID]) self.accountGeneration++;
    self.dpopPrivateKeyData = [stored[@"dpopPrivateKey"] isKindOfClass:[NSData class]] ? stored[@"dpopPrivateKey"] : nil;
    self.accessJwt = [stored[@"accessJwt"] isKindOfClass:[NSString class]] ? stored[@"accessJwt"] : nil;
    self.accessTokenExpiresAt = [stored[@"accessTokenExpiresAt"] isKindOfClass:NSDate.class] ? stored[@"accessTokenExpiresAt"] : nil;
    self.accessTokenLifetime = [stored[@"accessTokenLifetime"] respondsToSelector:@selector(doubleValue)] ? [stored[@"accessTokenLifetime"] doubleValue] : 600.0;
    self.refreshJwt = [stored[@"refreshJwt"] isKindOfClass:[NSString class]] ? stored[@"refreshJwt"] : nil;
    self.did = nextDID;
    self.handle = [stored[@"handle"] isKindOfClass:[NSString class]] ? stored[@"handle"] : nil;
    self.serviceEndpoint = [stored[@"serviceEndpoint"] isKindOfClass:[NSString class]] ? [self.class normalizedPDSServiceURL:stored[@"serviceEndpoint"]] : NFBAtprotoDefaultService;
    self.profile = [stored[@"profile"] isKindOfClass:[NSDictionary class]] ? stored[@"profile"] : nil;
    self.oauthIssuer = [stored[@"oauthIssuer"] isKindOfClass:[NSString class]] ? stored[@"oauthIssuer"] : NFBAtprotoDefaultIssuer;
    self.oauthTokenEndpoint = [stored[@"oauthTokenEndpoint"] isKindOfClass:[NSString class]] ? stored[@"oauthTokenEndpoint"] : nil;
    self.oauthClientID = [stored[@"oauthClientID"] isKindOfClass:[NSString class]] ? stored[@"oauthClientID"] : nil;
    self.oauthRedirectURI = [stored[@"oauthRedirectURI"] isKindOfClass:[NSString class]] ? stored[@"oauthRedirectURI"] : nil;
    self.oauthTokenType = [stored[@"oauthTokenType"] isKindOfClass:[NSString class]] ? stored[@"oauthTokenType"] : @"DPoP";
}

- (NSMutableArray<NSDictionary *> *)storedAccountsMutableCopy {
    NSArray *accounts = [[NSUserDefaults standardUserDefaults] arrayForKey:NFBAtprotoAccountsDefaultsKey];
    NSMutableArray<NSDictionary *> *mutableAccounts = [NSMutableArray array];
    for (NSDictionary *account in accounts) {
        if ([account isKindOfClass:[NSDictionary class]]) [mutableAccounts addObject:account];
    }
    return mutableAccounts;
}

- (void)upsertStoredAccountDictionaryLocked:(NSDictionary *)stored {
    NSString *did = [self.class accountDIDFromStoredDictionary:stored];
    if (did.length == 0) return;
    NSMutableArray<NSDictionary *> *accounts = [self storedAccountsMutableCopy];
    NSUInteger existingIndex = NSNotFound;
    for (NSUInteger index = 0; index < accounts.count; index++) {
        NSString *storedDID = [self.class accountDIDFromStoredDictionary:accounts[index]];
        if ([storedDID isEqualToString:did]) {
            existingIndex = index;
            break;
        }
    }
    if (existingIndex == NSNotFound) {
        [accounts insertObject:stored atIndex:0];
    } else {
        accounts[existingIndex] = stored;
    }
    [[NSUserDefaults standardUserDefaults] setObject:accounts forKey:NFBAtprotoAccountsDefaultsKey];
}

+ (NSString *)accountDIDFromStoredDictionary:(NSDictionary *)stored {
    if (![stored isKindOfClass:[NSDictionary class]]) return @"";
    NSString *did = [stored[@"did"] isKindOfClass:[NSString class]] ? stored[@"did"] : nil;
    if (did.length > 0) return did;
    NSDictionary *profile = [stored[@"profile"] isKindOfClass:[NSDictionary class]] ? stored[@"profile"] : nil;
    did = [profile[@"did"] isKindOfClass:[NSString class]] ? profile[@"did"] : nil;
    return did ?: @"";
}

- (void)loadStoredSession {
    dispatch_sync(self.stateQueue, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray<NSDictionary *> *accounts = [defaults arrayForKey:NFBAtprotoAccountsDefaultsKey];
        NSString *activeDID = [defaults stringForKey:NFBAtprotoActiveAccountDIDDefaultsKey];
        NSDictionary *selected = nil;

        for (NSDictionary *account in accounts) {
            if (![account isKindOfClass:[NSDictionary class]]) continue;
            NSString *did = [self.class accountDIDFromStoredDictionary:account];
            if (activeDID.length > 0 && [did isEqualToString:activeDID]) {
                selected = account;
                break;
            }
        }
        if (!selected && accounts.count > 0) {
            for (NSDictionary *account in accounts) {
                if ([account isKindOfClass:[NSDictionary class]]) {
                    selected = account;
                    break;
                }
            }
        }
        if (!selected) {
            NSDictionary *legacy = [defaults dictionaryForKey:NFBAtprotoDefaultsKey];
            if ([legacy isKindOfClass:[NSDictionary class]]) selected = legacy;
        }

        if (![selected isKindOfClass:[NSDictionary class]]) return;
        [self applyStoredSessionDictionaryLocked:selected];
        if (self.dpopPrivateKeyData.length == 0) {
            [self clearCurrentSessionLocked];
            [defaults removeObjectForKey:NFBAtprotoDefaultsKey];
            [defaults removeObjectForKey:NFBAtprotoActiveAccountDIDDefaultsKey];
            [defaults synchronize];
            return;
        }
        [self saveStoredSessionLocked];
    });
}

- (void)saveStoredSessionLocked {
    NSDictionary *stored = [self storedSessionDictionaryLocked];
    NSString *did = [self.class accountDIDFromStoredDictionary:stored];
    if (did.length == 0 || self.dpopPrivateKeyData.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:stored forKey:NFBAtprotoDefaultsKey];
    [defaults setObject:did forKey:NFBAtprotoActiveAccountDIDDefaultsKey];
    [self upsertStoredAccountDictionaryLocked:stored];
    [defaults synchronize];
}

+ (NSURL *)xrpcURLWithService:(NSString *)service method:(NSString *)method params:(NSDictionary *)params {
    NSString *normalized = [self normalizedServiceURL:service];
    NSString *base = [normalized stringByAppendingFormat:@"/xrpc/%@", method ?: @""];
    NSURLComponents *components = [NSURLComponents componentsWithString:base];
    NSMutableArray *queryItems = [NSMutableArray array];
    [params enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (!key || !value || value == [NSNull null]) return;
        if ([value isKindOfClass:[NSArray class]]) {
            for (id item in (NSArray *)value) {
                [queryItems addObject:[NSURLQueryItem queryItemWithName:[key description] value:[item description]]];
            }
        } else {
            [queryItems addObject:[NSURLQueryItem queryItemWithName:[key description] value:[value description]]];
        }
    }];
    if (queryItems.count > 0) components.queryItems = queryItems;
    return components.URL;
}

+ (NSString *)normalizedServiceURL:(NSString *)serviceURL {
    NSString *trimmed = [self trimmedString:serviceURL];
    if (trimmed.length == 0) trimmed = NFBAtprotoDefaultService;
    if (![trimmed hasPrefix:@"http://"] && ![trimmed hasPrefix:@"https://"]) {
        trimmed = [@"https://" stringByAppendingString:trimmed];
    }
    while ([trimmed hasSuffix:@"/"] && trimmed.length > [@"https://" length]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    return trimmed;
}

+ (NSString *)normalizedPDSServiceURL:(NSString *)serviceURL {
    NSString *normalized = [self normalizedServiceURL:serviceURL];
    return [self isAppViewServiceURL:normalized] ? NFBAtprotoDefaultService : normalized;
}

+ (BOOL)isAppViewServiceURL:(NSString *)serviceURL {
    NSString *normalized = [self normalizedServiceURL:serviceURL];
    return [normalized isEqualToString:[self normalizedServiceURL:NFBAtprotoDirectAppView]] ||
           [normalized isEqualToString:[self normalizedServiceURL:NFBAtprotoPublicAppView]];
}

+ (NSString *)normalizedLoginIdentifier:(NSString *)identifier {
    NSString *trimmed = [[self trimmedString:identifier] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@"]];
    if ([trimmed hasPrefix:@"did:"]) return trimmed;
    return [trimmed lowercaseString];
}

+ (NSString *)trimmedString:(NSString *)string {
    if (![string isKindOfClass:[NSString class]]) return @"";
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSError *)genericError:(NSString *)message {
    return [NSError errorWithDomain:@"NFBAtprotoSession"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"ATProto error."}];
}

+ (NSString *)formEncodedStringForDictionary:(NSDictionary<NSString *, NSString *> *)dictionary {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]]) return;
        [parts addObject:[NSString stringWithFormat:@"%@=%@", [self formEncodedValue:key], [self formEncodedValue:value]]];
    }];
    return [parts componentsJoinedByString:@"&"];
}

+ (NSString *)formEncodedValue:(NSString *)value {
    NSString *encoded = [self percentEncodedQueryValue:value ?: @""];
    return [encoded stringByReplacingOccurrencesOfString:@"%20" withString:@"+"];
}

+ (NSString *)percentEncodedQueryValue:(NSString *)value {
    NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"!*'();:@&=+$,/?#[]%"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

+ (NSString *)originForURL:(NSURL *)url {
    if (!url.scheme || !url.host) return @"";
    NSString *port = url.port ? [NSString stringWithFormat:@":%@", url.port] : @"";
    return [NSString stringWithFormat:@"%@://%@%@", url.scheme, url.host, port];
}

+ (BOOL)responseRequestsDpopNonce:(NSHTTPURLResponse *)response value:(id)value {
    NSString *wwwAuthenticate = [response.allHeaderFields[@"WWW-Authenticate"] isKindOfClass:[NSString class]] ? response.allHeaderFields[@"WWW-Authenticate"] : nil;
    if (response.statusCode == 401 && [wwwAuthenticate containsString:@"use_dpop_nonce"]) return YES;
    if (response.statusCode == 400 && [value isKindOfClass:[NSDictionary class]] && [value[@"error"] isEqual:@"use_dpop_nonce"]) return YES;
    return NO;
}

+ (NSData *)generateP256PrivateKeyData {
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
    if (error) CFRelease(error);
    if (!key) return nil;
    CFErrorRef exportError = NULL;
    NSData *data = CFBridgingRelease(SecKeyCopyExternalRepresentation(key, &exportError));
    if (exportError) CFRelease(exportError);
    CFRelease(key);
    return data;
}

+ (SecKeyRef)privateKeyFromData:(NSData *)data {
    if (data.length == 0) return nil;
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)attributes, &error);
    if (error) CFRelease(error);
    return key;
}

+ (NSDictionary *)publicJWKForPrivateKey:(SecKeyRef)privateKey {
    if (!privateKey) return nil;
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (!publicKey) return nil;
    CFErrorRef error = NULL;
    NSData *publicData = CFBridgingRelease(SecKeyCopyExternalRepresentation(publicKey, &error));
    if (error) CFRelease(error);
    CFRelease(publicKey);
    if (publicData.length != 65) return nil;
    const unsigned char *bytes = publicData.bytes;
    if (bytes[0] != 0x04) return nil;
    NSData *xData = [publicData subdataWithRange:NSMakeRange(1, 32)];
    NSData *yData = [publicData subdataWithRange:NSMakeRange(33, 32)];
    return @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": [self base64URLEncodedStringForData:xData],
        @"y": [self base64URLEncodedStringForData:yData]
    };
}

+ (NSString *)dpopProofForRequest:(NSURLRequest *)request privateKeyData:(NSData *)privateKeyData nonce:(NSString *)nonce authorizationToken:(NSString *)authorizationToken {
    SecKeyRef privateKey = [self privateKeyFromData:privateKeyData];
    if (!privateKey) return nil;
    NSDictionary *jwk = [self publicJWKForPrivateKey:privateKey];
    if (!jwk) {
        CFRelease(privateKey);
        return nil;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"iat"] = @((NSInteger)[[NSDate date] timeIntervalSince1970]);
    payload[@"jti"] = [self randomBase64URLStringWithByteCount:16];
    payload[@"htm"] = request.HTTPMethod ?: @"GET";
    payload[@"htu"] = [self dpopHTUForURL:request.URL];
    if (nonce.length > 0) payload[@"nonce"] = nonce;
    if (authorizationToken.length > 0) payload[@"ath"] = [self sha256Base64URLForString:authorizationToken];

    NSDictionary *header = @{
        @"alg": @"ES256",
        @"typ": @"dpop+jwt",
        @"jwk": jwk
    };

    NSString *headerPart = [self base64URLJSON:header];
    NSString *payloadPart = [self base64URLJSON:payload];
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerPart, payloadPart];
    NSData *message = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    CFErrorRef error = NULL;
    NSData *derSignature = CFBridgingRelease(SecKeyCreateSignature(privateKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)message, &error));
    if (error) CFRelease(error);
    CFRelease(privateKey);
    NSData *rawSignature = [self rawECDSASignatureFromDERSignature:derSignature componentLength:32];
    if (rawSignature.length == 0) return nil;
    return [NSString stringWithFormat:@"%@.%@", signingInput, [self base64URLEncodedStringForData:rawSignature]];
}

+ (NSString *)dpopHTUForURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    components.query = nil;
    components.fragment = nil;
    return components.URL.absoluteString ?: url.absoluteString;
}

+ (NSString *)base64URLJSON:(id)object {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return [self base64URLEncodedStringForData:json ?: [NSData data]];
}

+ (NSString *)sha256Base64URLForString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [self base64URLEncodedStringForData:[NSData dataWithBytes:hash length:sizeof(hash)]];
}

+ (NSString *)randomBase64URLStringWithByteCount:(NSUInteger)byteCount {
    NSMutableData *data = [NSMutableData dataWithLength:byteCount];
    if (SecRandomCopyBytes(kSecRandomDefault, byteCount, data.mutableBytes) != errSecSuccess) return [[NSUUID UUID] UUIDString];
    return [self base64URLEncodedStringForData:data];
}

+ (NSString *)base64URLEncodedStringForData:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

+ (NSData *)base64URLDecodedData:(NSString *)string {
    if (string.length == 0) return nil;
    NSString *base64 = [string stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) base64 = [base64 stringByPaddingToLength:base64.length + (4 - remainder) withString:@"=" startingAtIndex:0];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

+ (NSDate *)expirationDateForTokenResponse:(NSDictionary *)response {
    id value = response[@"expires_in"];
    NSTimeInterval lifetime = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0.0;
    if (NFBTokenLifetimeIsValid(lifetime)) return [NSDate dateWithTimeIntervalSinceNow:lifetime];
    NSString *token = [response[@"access_token"] isKindOfClass:NSString.class] ? response[@"access_token"] : nil;
    return [self expirationDateForJWT:token];
}

+ (NSDate *)expirationDateForJWT:(NSString *)jwt {
    NSArray<NSString *> *parts = [jwt componentsSeparatedByString:@"."];
    if (parts.count < 2) return nil;

    NSData *payloadData = [self base64URLDecodedData:parts[1]];
    if (payloadData.length == 0) return nil;

    id payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
    if (![payload isKindOfClass:[NSDictionary class]]) return nil;

    id exp = ((NSDictionary *)payload)[@"exp"];
    NSTimeInterval timestamp = 0.0;
    if ([exp respondsToSelector:@selector(doubleValue)]) timestamp = [exp doubleValue];
    if (timestamp <= 0.0) return nil;

    return [NSDate dateWithTimeIntervalSince1970:timestamp];
}

+ (NSData *)rawECDSASignatureFromDERSignature:(NSData *)derSignature componentLength:(NSUInteger)componentLength {
    if (derSignature.length < 8) return nil;
    const uint8_t *bytes = derSignature.bytes;
    NSUInteger index = 0;
    if (bytes[index++] != 0x30) return nil;
    if (![self skipDERLengthInBytes:bytes length:derSignature.length index:&index]) return nil;
    NSData *r = [self readDERIntegerInBytes:bytes length:derSignature.length index:&index componentLength:componentLength];
    NSData *s = [self readDERIntegerInBytes:bytes length:derSignature.length index:&index componentLength:componentLength];
    if (r.length != componentLength || s.length != componentLength) return nil;
    NSMutableData *raw = [NSMutableData dataWithData:r];
    [raw appendData:s];
    return raw;
}

+ (BOOL)skipDERLengthInBytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index {
    if (*index >= length) return NO;
    uint8_t first = bytes[(*index)++];
    if ((first & 0x80) == 0) return *index + first <= length;
    NSUInteger count = first & 0x7f;
    if (count == 0 || count > sizeof(NSUInteger) || *index + count > length) return NO;
    NSUInteger value = 0;
    for (NSUInteger i = 0; i < count; i++) value = (value << 8) | bytes[(*index)++];
    return *index + value <= length;
}

+ (NSData *)readDERIntegerInBytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index componentLength:(NSUInteger)componentLength {
    if (*index >= length || bytes[(*index)++] != 0x02) return nil;
    if (*index >= length) return nil;
    NSUInteger integerLength = bytes[(*index)++];
    if (integerLength & 0x80) {
        NSUInteger count = integerLength & 0x7f;
        if (count == 0 || count > sizeof(NSUInteger) || *index + count > length) return nil;
        integerLength = 0;
        for (NSUInteger i = 0; i < count; i++) integerLength = (integerLength << 8) | bytes[(*index)++];
    }
    if (*index + integerLength > length) return nil;
    const uint8_t *integerBytes = bytes + *index;
    *index += integerLength;
    while (integerLength > 0 && integerBytes[0] == 0x00) {
        integerBytes++;
        integerLength--;
    }
    if (integerLength > componentLength) return nil;
    NSMutableData *component = [NSMutableData dataWithLength:componentLength];
    memcpy((uint8_t *)component.mutableBytes + (componentLength - integerLength), integerBytes, integerLength);
    return component;
}

@end
