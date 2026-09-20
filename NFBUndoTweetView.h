#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBUndoTweetView : UIView
@property (nonatomic, strong, readonly) UIButton *undoButton;
@property (nonatomic, strong, readonly) UIButton *sendNowButton;
- (void)applyTheme;
- (void)updateWithRemainingTime:(NSTimeInterval)remaining totalInterval:(NSTimeInterval)totalInterval;
- (void)resetProgress;
@end

NS_ASSUME_NONNULL_END
