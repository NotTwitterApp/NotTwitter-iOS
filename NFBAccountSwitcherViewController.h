#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBAccountSwitcherViewController : UIViewController

@property (nonatomic, copy, nullable) dispatch_block_t addAccountHandler;
@property (nonatomic, copy, nullable) dispatch_block_t signOutHandler;
@property (nonatomic, copy, nullable) dispatch_block_t actionCompletionHandler;
@property (nonatomic, copy, nullable) dispatch_block_t dismissalHandler;
@property (nonatomic, copy, nullable) void (^prepareForAccountSwitch)(dispatch_block_t switchAccount);
@property (nonatomic, assign) CGFloat preferredSheetWidth;
@property (nonatomic, assign) BOOL sideMenuPresentation;

@end

NS_ASSUME_NONNULL_END
