#import <UIKit/UIKit.h>

@class NFBActorCell;

@protocol NFBActorCellDelegate <NSObject>
- (void)actorCellDidTapFollow:(NFBActorCell *)cell;
@end

@interface NFBActorCell : UITableViewCell
@property (nonatomic, weak) id<NFBActorCellDelegate> delegate;
@property (nonatomic, strong, readonly) NSDictionary *profile;
@property (nonatomic, strong, readonly) UIButton *followButton;
- (void)configureWithProfile:(NSDictionary *)profile;
@end

