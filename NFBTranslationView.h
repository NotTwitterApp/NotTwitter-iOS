#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Inline reference-style translation, shared by post cells, Reader and bios.
@interface NFBTranslationView : UIStackView
@property (nonatomic, copy, nullable) void (^sizeChanged)(void);
- (void)configureWithPost:(nullable NSDictionary *)post bodyFont:(UIFont *)font;
- (void)configureWithText:(NSString *)text languages:(NSArray *)languages title:(NSString *)title bodyFont:(UIFont *)font;
- (void)reset;
- (void)applyTheme;
@end
NS_ASSUME_NONNULL_END
