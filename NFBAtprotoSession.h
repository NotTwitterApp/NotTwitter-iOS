#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFBAtprotoSessionChangedNotification;
extern NSString * const NFBAtprotoOAuthCallbackReceivedNotification;

typedef void (^NFBAtprotoValueCompletion)(id _Nullable value, NSHTTPURLResponse *_Nullable response, NSError *_Nullable error);
typedef void (^NFBAtprotoSignInCompletion)(BOOL success, NSDictionary *_Nullable session, NSError *_Nullable error);
typedef void (^NFBAtprotoAuthorizationURLHandler)(NSURL *authorizationURL);

@interface NFBAtprotoSession : NSObject

@property (nonatomic, readonly, nullable) NSString *accessJwt;
@property (nonatomic, readonly, nullable) NSString *refreshJwt;
@property (nonatomic, readonly, nullable) NSString *did;
@property (nonatomic, readonly, nullable) NSString *handle;
@property (nonatomic, readonly) NSString *serviceEndpoint;
@property (nonatomic, readonly, nullable) NSDictionary *profile;
@property (nonatomic, readonly) NSArray<NSDictionary *> *savedAccounts;
// Changes only when the active identity changes, not when its token refreshes.
@property (atomic, readonly) NSUInteger accountGeneration;

+ (instancetype)sharedSession;

- (BOOL)hasSession;
- (BOOL)hasPendingOAuthSignIn;
- (BOOL)hasReceivedPendingOAuthCallback;
- (void)signInWithIdentifier:(NSString *)identifier
     authorizationURLHandler:(NFBAtprotoAuthorizationURLHandler)authorizationURLHandler
                  completion:(NFBAtprotoSignInCompletion)completion;
- (BOOL)handleOAuthCallbackURL:(NSURL *)url;
- (void)cancelPendingOAuthSignIn;
- (void)refreshSessionWithCompletion:(NFBAtprotoSignInCompletion)completion;
- (void)signOut;
- (NSArray<NSDictionary *> *)savedAccountDictionaries;
- (BOOL)switchToAccountWithDID:(NSString *)did;
- (BOOL)canSwitchToAccountWithDID:(NSString *)did;
- (BOOL)removeAccountWithDID:(NSString *)did;

// Account-scoped writes never change the account displayed by the app.
- (void)xrpcPOST:(NSString *)method forAccountDID:(NSString *)accountDID
           body:(NSDictionary *)body completion:(NFBAtprotoValueCompletion)completion;
- (void)xrpcPOSTData:(NSString *)method forAccountDID:(NSString *)accountDID
               data:(NSData *)data contentType:(NSString *)contentType
         completion:(NFBAtprotoValueCompletion)completion;

- (void)xrpcGET:(NSString *)method
        service:(nullable NSString *)serviceURL
         params:(nullable NSDictionary<NSString *, id> *)params
  authenticated:(BOOL)authenticated
     completion:(NFBAtprotoValueCompletion)completion;

- (void)xrpcPOST:(NSString *)method
         service:(nullable NSString *)serviceURL
           body:(nullable NSDictionary<NSString *, id> *)body
  authenticated:(BOOL)authenticated
     completion:(NFBAtprotoValueCompletion)completion;

- (void)xrpcPOSTData:(NSString *)method
              service:(nullable NSString *)serviceURL
                 data:(NSData *)data
          contentType:(NSString *)contentType
        authenticated:(BOOL)authenticated
           completion:(NFBAtprotoValueCompletion)completion;

- (void)xrpcGETViaAppViewProxy:(NSString *)method
                         params:(nullable NSDictionary<NSString *, id> *)params
                     completion:(NFBAtprotoValueCompletion)completion;

- (void)xrpcPOSTViaAppViewProxy:(NSString *)method
                           body:(nullable NSDictionary<NSString *, id> *)body
                     completion:(NFBAtprotoValueCompletion)completion;

- (void)xrpcGETViaChatProxy:(NSString *)method
                      params:(nullable NSDictionary<NSString *, id> *)params
                  completion:(NFBAtprotoValueCompletion)completion;

- (void)xrpcPOSTViaChatProxy:(NSString *)method
                        body:(nullable NSDictionary<NSString *, id> *)body
                  completion:(NFBAtprotoValueCompletion)completion;

- (void)resolvePDSForDID:(NSString *)did completion:(void (^)(NSString *_Nullable serviceEndpoint))completion;

- (NSDictionary *)currentAccountDictionary;
- (void)updateProfileFromDictionary:(nullable NSDictionary *)profile;

@end

NS_ASSUME_NONNULL_END
