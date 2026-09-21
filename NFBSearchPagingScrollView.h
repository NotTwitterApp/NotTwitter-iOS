#import <UIKit/UIKit.h>
#import "NFBGesturePolicy.h"

@interface NFBSearchPagingScrollView : UIScrollView <UIGestureRecognizerDelegate, NFBHorizontalPagingSurface>
@property (nonatomic) NSInteger pageCount;
@end
