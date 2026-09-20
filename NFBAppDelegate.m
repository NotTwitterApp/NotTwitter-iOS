#import "NFBAppDelegate.h"

#import "NFBAtprotoSession.h"
#import "NFBLocalPostStore.h"
#import "NFBMainTabBarController.h"
#import "NFBNotificationCoordinator.h"
#import "NFBTheme.h"

@interface NFBAppDelegate ()

@property (nonatomic, strong) NFBMainTabBarController *mainTabBarController;
@property (nonatomic, copy) NSString *lastRoutedNotificationSignature;

@end

static UNNotificationPresentationOptions NFBNotificationCenterPresentationOptions(void) {
  UNNotificationPresentationOptions options = UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound;
  options |= UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList;
  return options;
}

@implementation NFBAppDelegate

- (NSString *)routeSignatureForNotificationUserInfo:(NSDictionary *)userInfo {
  if (![userInfo isKindOfClass:NSDictionary.class]) return @"";
  return userInfo.description ?: @"";
}

- (void)routeNotificationUserInfoIfNeeded:(NSDictionary *)userInfo {
  if (![userInfo isKindOfClass:NSDictionary.class] || userInfo.count == 0) return;
  NSString *signature = [self routeSignatureForNotificationUserInfo:userInfo];
  if (signature.length > 0 && [signature isEqualToString:self.lastRoutedNotificationSignature]) return;
  self.lastRoutedNotificationSignature = signature;
  [self.mainTabBarController openNotificationUserInfo:userInfo];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application;
  UNUserNotificationCenter.currentNotificationCenter.delegate = self;
  [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
  [[NFBNotificationCoordinator sharedCoordinator] registerForRemoteNotificationsIfPossible];

  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  NFBApplyAppAppearance(self.window);
  self.mainTabBarController = [[NFBMainTabBarController alloc] init];
  self.window.rootViewController = self.mainTabBarController;
  [self.window makeKeyAndVisible];
  [[NFBLocalPostStore sharedStore] processDueScheduledPostsWithCompletion:nil];

  NSDictionary *launchNotification = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
  if ([launchNotification isKindOfClass:NSDictionary.class]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self routeNotificationUserInfoIfNeeded:launchNotification];
    });
  }

  return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
  (void)application;
  (void)options;

  if ([[NFBAtprotoSession sharedSession] handleOAuthCallbackURL:url]) return YES;
  [self.mainTabBarController openURL:url];
  return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
  (void)application;
  [[NFBNotificationCoordinator sharedCoordinator] refreshBadgeCounts];
  [[NFBLocalPostStore sharedStore] processDueScheduledPostsWithCompletion:nil];
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler {
  (void)application;
  [[NFBNotificationCoordinator sharedCoordinator] refreshBadgeCountsAllowingLocalAlerts:YES completion:completionHandler];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  (void)application;
  [[NFBNotificationCoordinator sharedCoordinator] didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  (void)application;
  [[NFBNotificationCoordinator sharedCoordinator] didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler {
  (void)application;
  [[NFBNotificationCoordinator sharedCoordinator] handleRemoteNotificationUserInfo:userInfo completion:completionHandler];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
  (void)center;
  (void)notification;
  completionHandler(NFBNotificationCenterPresentationOptions());
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
  (void)center;
  NSDictionary *userInfo = response.notification.request.content.userInfo ?: @{};
  [self routeNotificationUserInfoIfNeeded:userInfo];
  completionHandler();
}

@end
