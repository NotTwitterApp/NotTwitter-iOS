#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NFBExternalCardView;

@protocol NFBExternalCardViewDelegate <NSObject>
@optional
- (void)externalCardViewDidTapCard:(NFBExternalCardView *)view;
- (void)externalCardViewDidTapReadOnWebsite:(NFBExternalCardView *)view;
- (void)externalCardViewDidUpdateContent:(NFBExternalCardView *)view;
@end

@interface NFBExternalCardView : UIControl

@property (nonatomic, weak, nullable) id<NFBExternalCardViewDelegate> delegate;
@property (nonatomic, copy, readonly, nullable) NSDictionary *card;
@property (nonatomic, assign) BOOL quotedCardStyle;

- (void)configureWithCard:(nullable NSDictionary *)card;
- (void)configureWithCard:(nullable NSDictionary *)card compact:(BOOL)compact;
- (void)configureWithCard:(nullable NSDictionary *)card compact:(BOOL)compact fullArticleReader:(BOOL)fullArticleReader;
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
- (void)applyTheme;

@end

NS_ASSUME_NONNULL_END
