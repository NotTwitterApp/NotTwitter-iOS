#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBSideMenuViewController : UIViewController
@property (nonatomic, assign) BOOL interactiveOpening;
- (void)updateOpeningTranslation:(CGFloat)translation;
- (void)finishOpeningWithVelocity:(CGFloat)velocity cancelled:(BOOL)cancelled;
@end

NS_ASSUME_NONNULL_END
