#import <UIKit/UIKit.h>
@interface NFBAdvancedSearchViewController : UITableViewController
@property (nonatomic, copy) void (^search)(NSString *query);
- (instancetype)initWithQuery:(NSString *)query;
@end
