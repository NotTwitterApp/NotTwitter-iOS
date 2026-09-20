#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBActorListViewController : UIViewController

- (instancetype)initWithPost:(NSDictionary *)post selectedType:(NSString *)type;
- (instancetype)initWithProfile:(NSDictionary *)profile actor:(NSString *)actor selectedKind:(NSString *)kind;
- (instancetype)initWithActors:(NSArray<NSDictionary *> *)actors title:(nullable NSString *)title;

@end

NS_ASSUME_NONNULL_END
