#pragma once
#include <stdbool.h>
#include <math.h>

// A reversal at release cancels a drag, even after crossing the distance threshold.
static inline bool NFBShouldFinishSwipe(double progress, double velocityTowardDestination, bool cancelled) {
  if (cancelled || velocityTowardDestination < -350.0) return false;
  return progress >= 0.33 || velocityTowardDestination > 550.0;
}

#ifdef __OBJC__
#import <UIKit/UIKit.h>

@protocol NFBHorizontalPagingSurface <NSObject>
- (BOOL)nfb_canPageHorizontallyWithVelocity:(CGPoint)velocity;
@end

static inline BOOL NFBTouchIsInHorizontalScroller(UIView *root, CGPoint point) {
  for (UIView *view = [root hitTest:point withEvent:nil]; view && view != root; view = view.superview) {
    if ([view isKindOfClass:UISlider.class]) return YES;
    if (![view isKindOfClass:UIScrollView.class]) continue;
    UIScrollView *scroll = (UIScrollView *)view;
    if (scroll.scrollEnabled && (scroll.zoomScale > scroll.minimumZoomScale + 0.01 ||
        scroll.contentSize.width > CGRectGetWidth(scroll.bounds) + 1.0)) return YES;
  }
  return NO;
}
#endif
