#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NFBPostActionKind) {
  NFBPostActionKindReply,
  NFBPostActionKindRepost,
  NFBPostActionKindLike,
  NFBPostActionKindBookmark,
  NFBPostActionKindShare,
  NFBPostActionKindFollow,
  NFBPostActionKindDelete
};

typedef void (^NFBPostActionPostUpdateHandler)(NSDictionary *updatedPost, NSDictionary *originalPost);
typedef void (^NFBPostActionProfileUpdateHandler)(NSDictionary *updatedProfile, NSDictionary *originalProfile);
typedef void (^NFBPostActionDeleteHandler)(NSDictionary *deletedPost);
typedef void (^NFBPostActionReloadHandler)(void);

@interface NFBPostActionCoordinator : NSObject

@property (nonatomic, weak, nullable) UIViewController *presentingViewController;
@property (nonatomic, copy, nullable) NFBPostActionPostUpdateHandler postUpdateHandler;
@property (nonatomic, copy, nullable) NFBPostActionProfileUpdateHandler profileUpdateHandler;
@property (nonatomic, copy, nullable) NFBPostActionDeleteHandler deleteHandler;
@property (nonatomic, copy, nullable) NFBPostActionReloadHandler reloadHandler;

- (instancetype)initWithPresentingViewController:(UIViewController *)presentingViewController;

- (void)performReplyForPost:(NSDictionary *)post sourceView:(nullable UIView *)sourceView;
- (void)performRepostForPost:(NSDictionary *)post sourceView:(nullable UIView *)sourceView;
- (void)performLikeForPost:(NSDictionary *)post sourceView:(nullable UIView *)sourceView;
- (void)performBookmarkForPost:(NSDictionary *)post sourceView:(nullable UIView *)sourceView;
- (void)performShareForPost:(NSDictionary *)post sourceView:(nullable UIView *)sourceView;
- (void)performDeleteForPost:(NSDictionary *)post sourceView:(nullable UIView *)sourceView;
- (void)presentMoreMenuForPost:(NSDictionary *)post sourceView:(nullable UIView *)sourceView;
- (nullable UIMenu *)contextMenuForPost:(NSDictionary *)post API_AVAILABLE(ios(13.0));

- (void)performFollowForProfile:(NSDictionary *)profile
                      sourceView:(nullable UIView *)sourceView
                      completion:(nullable void (^)(NSDictionary *updatedProfile, NSError *_Nullable error))completion;
- (void)performBlockForProfile:(NSDictionary *)profile
                     sourceView:(nullable UIView *)sourceView
                     completion:(nullable void (^)(NSDictionary *updatedProfile, NSError *_Nullable error))completion;
- (void)performGoToProfile:(NSDictionary *)profile;

+ (BOOL)isPostAuthoredByCurrentUser:(NSDictionary *)post;
+ (BOOL)isProfileCurrentUser:(NSDictionary *)profile;
+ (NSString *)followTitleForProfile:(NSDictionary *)profile;
+ (BOOL)shouldHideFollowButtonForProfile:(NSDictionary *)profile;
+ (void)configureFollowButton:(UIButton *)button profile:(NSDictionary *)profile overDarkBackground:(BOOL)overDarkBackground;
+ (void)animateActionView:(nullable UIView *)view kind:(NFBPostActionKind)kind activating:(BOOL)activating;
+ (void)playActionFeedbackForKind:(NFBPostActionKind)kind activating:(BOOL)activating;

@end

NS_ASSUME_NONNULL_END
