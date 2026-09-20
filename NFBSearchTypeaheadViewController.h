#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NFBSearchTypeaheadViewController;

@protocol NFBSearchTypeaheadViewControllerDelegate <NSObject>
@optional
- (void)searchTypeaheadViewController:(NFBSearchTypeaheadViewController *)viewController didSelectSearchQuery:(NSString *)query;
- (void)searchTypeaheadViewController:(NFBSearchTypeaheadViewController *)viewController didSelectActor:(NSString *)actor;
@end

@interface NFBSearchTypeaheadViewController : UIViewController

@property (nonatomic, weak, nullable) id<NFBSearchTypeaheadViewControllerDelegate> delegate;

- (instancetype)initWithInitialQuery:(nullable NSString *)query;

+ (void)addRecentSearchQuery:(NSString *)query;
+ (void)addRecentSearchProfile:(NSDictionary *)profile;

@end

NS_ASSUME_NONNULL_END
