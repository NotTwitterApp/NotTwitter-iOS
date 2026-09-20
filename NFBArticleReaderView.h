#import <UIKit/UIKit.h>

@interface NFBArticleReaderView : UIView
@property (nonatomic, copy) void (^heightDidChange)(void);
@property (nonatomic, copy) void (^openURL)(NSURL *url);
@property (nonatomic, readonly) CGFloat contentHeight;
- (void)displayArticle:(NSDictionary *)article;
- (void)applyTheme;
- (void)refresh;
@end
