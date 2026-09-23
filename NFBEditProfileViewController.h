#import <UIKit/UIKit.h>
@interface NFBEditProfileViewController : UIViewController
- (instancetype)initWithProfile:(NSDictionary *)profile completion:(void (^)(NSDictionary *profile))completion;
@end
