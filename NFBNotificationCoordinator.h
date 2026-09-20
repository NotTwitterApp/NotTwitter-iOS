#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFBNotificationCountsDidChangeNotification;
extern NSString * const NFBActivityNotificationPreferencesDidChangeNotification;
extern NSString * const NFBActivityNotificationCategoryAll;
extern NSString * const NFBActivityNotificationCategoryTweets;
extern NSString * const NFBActivityNotificationCategoryArticles;
extern NSString * const NFBActivityNotificationCategoryRetweets;
extern NSString * const NFBActivityNotificationCategoryReplies;

@interface NFBNotificationCoordinator : NSObject

@property (nonatomic, assign, readonly) NSUInteger homeBadgeCount;
@property (nonatomic, assign, readonly) NSUInteger notificationBadgeCount;
@property (nonatomic, assign, readonly) NSUInteger messageBadgeCount;

+ (instancetype)sharedCoordinator;

+ (NSArray<NSString *> *)activityNotificationCategoryIDs;
+ (NSString *)activityNotificationTitleForCategory:(NSString *)categoryID;
+ (NSArray<NSString *> *)activityNotificationCategoriesForProfile:(NSDictionary *)profile;
+ (BOOL)activityNotificationsEnabledForProfile:(NSDictionary *)profile;
+ (BOOL)activityNotificationCategories:(NSArray<NSString *> *)categories includeCategory:(NSString *)categoryID;
+ (BOOL)activitySubscriptionPostEnabledForCategories:(NSArray<NSString *> *)categories;
+ (BOOL)activitySubscriptionReplyEnabledForCategories:(NSArray<NSString *> *)categories;
+ (void)setActivityNotificationCategories:(NSArray<NSString *> *)categories forProfile:(NSDictionary *)profile;
+ (BOOL)subscribedPostNotificationItem:(NSDictionary *)item matchesActivityNotificationPreferencesForProfile:(NSDictionary *)profile;
+ (NSString *)conversationURIForPost:(NSDictionary *)post;
+ (BOOL)isConversationMutedForPost:(NSDictionary *)post;
+ (void)setConversationMuted:(BOOL)muted forPost:(NSDictionary *)post;
+ (BOOL)notificationItemIsMutedByConversationSetting:(NSDictionary *)item;
+ (void)presentActivityNotificationChecklistForProfile:(NSDictionary *)profile
                                    fromViewController:(UIViewController *)viewController
                                            sourceView:(nullable UIView *)sourceView
                                            completion:(nullable dispatch_block_t)completion;
+ (void)setArticleNotificationsOnlyForProfile:(NSDictionary *)profile
                            fromViewController:(UIViewController *)viewController
                                    completion:(nullable dispatch_block_t)completion;

- (void)start;
- (void)registerForRemoteNotificationsIfPossible;
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;
- (void)handleRemoteNotificationUserInfo:(NSDictionary *)userInfo completion:(nullable void (^)(UIBackgroundFetchResult result))completion;
- (void)unregisterRemoteNotificationsForCurrentAccountWithCompletion:(nullable dispatch_block_t)completion;
- (void)refreshBadgeCounts;
- (void)refreshBadgeCountsAllowingLocalAlerts:(BOOL)allowLocalAlerts completion:(nullable void (^)(UIBackgroundFetchResult result))completion;
- (void)clearHomeBadge;
- (void)clearHomeBadgeWithFeedItems:(NSArray<NSDictionary *> *)items;
- (void)clearNotificationBadge;
- (void)refreshMessageBadge;

@end

NS_ASSUME_NONNULL_END
