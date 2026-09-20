#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NFBTimelineKind) {
  NFBTimelineKindHome,
  NFBTimelineKindSearch,
  NFBTimelineKindNotifications,
  NFBTimelineKindProfile,
  NFBTimelineKindBookmarks,
  NFBTimelineKindLists,
  NFBTimelineKindFeeds,
  NFBTimelineKindFeedTimeline,
  NFBTimelineKindListTimeline
};

@interface NFBTimelineViewController : UIViewController

- (instancetype)initWithKind:(NFBTimelineKind)kind actor:(nullable NSString *)actor;
- (instancetype)initWithFeedActor:(NSString *)actor recordKey:(NSString *)recordKey title:(nullable NSString *)title;
- (instancetype)initWithSearchQuery:(NSString *)query;
- (void)refreshTimeline;
- (void)scrollToTopForTabSelection;
- (void)handleHomeTabReselectionWithUnreadBadgeCount:(NSUInteger)badgeCount;
- (void)selectNotificationsTabWithID:(NSString *)tabID refresh:(BOOL)refresh;
- (void)animateCurrentProfileReselection;
- (BOOL)isViewingProfileForProfile:(NSDictionary *)profile;

@end

NS_ASSUME_NONNULL_END
