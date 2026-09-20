#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBMainTabBarController : UITabBarController

- (void)openURL:(NSURL *)url;
- (void)openNotificationUserInfo:(NSDictionary *)userInfo;

@end

NS_ASSUME_NONNULL_END
