#import "NFBSearchPagingScrollView.h"
#import "NFBSearchPagingPolicy.h"

@implementation NFBSearchPagingScrollView
- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.pagingEnabled = YES;
    self.directionalLockEnabled = YES;
    self.showsHorizontalScrollIndicator = NO;
    self.showsVerticalScrollIndicator = NO;
    self.scrollsToTop = NO;
    self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  }
  return self;
}
- (BOOL)nfb_canPageHorizontallyWithVelocity:(CGPoint)velocity {
  return NFBSearchPagingHasDestination(NFBSearchPageForOffset(self.contentOffset.x, CGRectGetWidth(self.bounds), self.pageCount), self.pageCount, velocity.x);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
  if (gesture != self.panGestureRecognizer) return [super gestureRecognizerShouldBegin:gesture];
  CGPoint velocity = [self.panGestureRecognizer velocityInView:self];
  long page = NFBSearchPageForOffset(self.contentOffset.x, CGRectGetWidth(self.bounds), self.pageCount);
  if (!NFBSearchPagingShouldBegin(page, self.pageCount, velocity.x, velocity.y)) return NO;
  CGPoint point = [gesture locationInView:self];
  if (NFBTouchIsInHorizontalScroller(self, point)) return NO;
  // Once the horizontal page owns the drag, stop the underlying vertical list,
  // including an in-progress fling. Do not cancel horizontal media controls.
  for (UIView *view = [self hitTest:point withEvent:nil]; view && view != self; view = view.superview) {
    if (![view isKindOfClass:UIScrollView.class]) continue;
    UIScrollView *scroll = (UIScrollView *)view;
    [scroll setContentOffset:scroll.contentOffset animated:NO];
    scroll.panGestureRecognizer.enabled = NO;
    scroll.panGestureRecognizer.enabled = YES;
  }
  return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
  return [other isKindOfClass:UIScreenEdgePanGestureRecognizer.class];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
  if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) return NO;
  if (![other.view isKindOfClass:UIScrollView.class]) return NO;
  UIScrollView *scroll = (UIScrollView *)other.view;
  return scroll.contentSize.width <= CGRectGetWidth(scroll.bounds) + 1;
}
@end
