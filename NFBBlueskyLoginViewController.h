#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBBlueskyLoginViewController : UIViewController
- (instancetype)initWithAddAccountMode:(BOOL)addAccountMode;
@end

void NFBPresentBlueskyLoginIfNeeded(void);
void NFBPresentBlueskyAddAccount(void);
UIViewController *_Nullable NFBTopMostViewController(void);

NS_ASSUME_NONNULL_END
