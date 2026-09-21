#pragma once
#include <stdbool.h>
#include <math.h>

// A reversal at release cancels a drag, even after crossing the distance threshold.
static inline bool NFBShouldFinishSwipe(double progress, double velocityTowardDestination, bool cancelled) {
  if (cancelled || velocityTowardDestination < -350.0) return false;
  return progress >= 0.33 || velocityTowardDestination > 550.0;
}

// Twitter 9.67 TFNNavigationControllerTransitionAnimator: full-width starts at
// <=45 degrees; release finishes at 60% or >=200 pt/s, unless reversed <-200.
static inline bool NFBBackSwipeShouldBegin(double velocityTowardBack, double verticalVelocity) {
  return isfinite(velocityTowardBack) && isfinite(verticalVelocity) &&
         velocityTowardBack > 0.0 && fabs(verticalVelocity) <= velocityTowardBack;
}
static inline bool NFBBackSwipeShouldFinish(double progress, double velocityTowardBack, bool cancelled) {
  if (cancelled || !isfinite(progress) || !isfinite(velocityTowardBack) || velocityTowardBack < -200.0) return false;
  return progress >= 0.6 || velocityTowardBack >= 200.0;
}

#ifdef __OBJC__
#import <UIKit/UIKit.h>

@protocol NFBHorizontalPagingSurface <NSObject>
- (BOOL)nfb_canPageHorizontallyWithVelocity:(CGPoint)velocity;
@end

static inline BOOL NFBTouchIsInHorizontalScrollerForVelocity(UIView *root, CGPoint point, CGPoint velocity) {
  for (UIView *view = [root hitTest:point withEvent:nil]; view && view != root; view = view.superview) {
    if ([view isKindOfClass:UISlider.class]) return YES;
    if (![view isKindOfClass:UIScrollView.class]) continue;
    UIScrollView *scroll = (UIScrollView *)view;
    if ([scroll respondsToSelector:@selector(nfb_canPageHorizontallyWithVelocity:)]) {
      if ([(id<NFBHorizontalPagingSurface>)scroll nfb_canPageHorizontallyWithVelocity:velocity]) return YES;
      continue;
    }
    if (scroll.scrollEnabled && (scroll.zoomScale > scroll.minimumZoomScale + 0.01 ||
        scroll.contentSize.width > CGRectGetWidth(scroll.bounds) + 1.0)) return YES;
  }
  return NO;
}
// Non-directional callers still give every horizontal scroller priority.
static inline BOOL NFBTouchIsInHorizontalScroller(UIView *root, CGPoint point) {
  return NFBTouchIsInHorizontalScrollerForVelocity(root, point, CGPointMake(1, 0)) ||
         NFBTouchIsInHorizontalScrollerForVelocity(root, point, CGPointMake(-1, 0));
}
#endif
