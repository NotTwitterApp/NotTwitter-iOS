#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NFBQuotedPostView;
@class NFBMediaTransitionSource;

@protocol NFBQuotedPostViewDelegate <NSObject>
@optional
- (void)quotedPostViewDidTapPost:(NFBQuotedPostView *)view;
- (void)quotedPostView:(NFBQuotedPostView *)view didTapLinkURL:(NSURL *)url;
- (void)quotedPostView:(NFBQuotedPostView *)view didTapMediaAtIndex:(NSUInteger)index transitionSource:(NFBMediaTransitionSource *)transitionSource;
- (void)quotedPostViewDidTapExternalCard:(NFBQuotedPostView *)view;
- (void)quotedPostViewDidTapExternalCardWebsite:(NFBQuotedPostView *)view;
@end

@interface NFBQuotedPostView : UIControl

@property (nonatomic, weak, nullable) id<NFBQuotedPostViewDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) NSDictionary *post;

// Disable for callers that lay out the card with a fixed, precomputed height.
@property (nonatomic) BOOL translationEnabled;

- (void)configureWithPost:(nullable NSDictionary *)post;
- (void)applyTheme;

@end

NS_ASSUME_NONNULL_END
