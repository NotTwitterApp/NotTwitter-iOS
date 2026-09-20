#import "NFBInteractiveSheet.h"
#import "NFBGesturePolicy.h"
#import <objc/runtime.h>

@interface NFBInteractiveSheetDrag : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *sheet;
@property (nonatomic, weak) UIView *backdrop;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL cancelAction;
@property (nonatomic, weak) UIScrollView *scroll;
@property (nonatomic, assign) BOOL composer;
@property (nonatomic, assign) BOOL settling;
@end

@implementation NFBInteractiveSheetDrag
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
  UIPanGestureRecognizer *pan = (id)gesture;
  CGPoint velocity = [pan velocityInView:self.sheet.superview];
  if (self.settling || velocity.y <= fabs(velocity.x)) return NO;
  CGPoint point = [pan locationInView:self.sheet];
  if (self.composer && point.y > self.sheet.safeAreaInsets.top + 64.0) return NO;
  self.scroll = nil;
  for (UIView *view = [self.sheet hitTest:point withEvent:nil]; view && view != self.sheet; view = view.superview) {
    if ([view isKindOfClass:UISlider.class] || [view isKindOfClass:UIDatePicker.class] || [view isKindOfClass:UIPickerView.class]) return NO;
    if ([view isKindOfClass:UIScrollView.class]) {
      UIScrollView *scroll = (id)view;
      if (scroll.contentOffset.y > -scroll.adjustedContentInset.top + 1.0) return NO;
      self.scroll = scroll;
    }
  }
  return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
  return other == self.scroll.panGestureRecognizer;
}
- (void)panned:(UIPanGestureRecognizer *)pan {
  CGFloat distance = MAX(0.0, [pan translationInView:self.sheet.superview].y);
  CGFloat height = MAX(1.0, CGRectGetHeight(self.sheet.bounds));
  if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
    self.sheet.transform = CGAffineTransformMakeTranslation(0.0, distance);
    self.backdrop.alpha = MAX(0.0, 1.0 - distance / height);
    if (self.scroll) self.scroll.contentOffset = CGPointMake(self.scroll.contentOffset.x, -self.scroll.adjustedContentInset.top);
    return;
  }
  if (pan.state != UIGestureRecognizerStateEnded && pan.state != UIGestureRecognizerStateCancelled && pan.state != UIGestureRecognizerStateFailed) return;
  BOOL finish = NFBShouldFinishSwipe(distance / height, [pan velocityInView:self.sheet.superview].y, pan.state != UIGestureRecognizerStateEnded);
  self.settling = YES;
  if (finish && !self.composer) {
    [self invokeCancel];
    return;
  }
  // The composer's own Cancel action preserves the existing save-draft choice.
  [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    self.sheet.transform = finish && !self.composer ? CGAffineTransformMakeTranslation(0.0, height) : CGAffineTransformIdentity;
    self.backdrop.alpha = finish ? 0.0 : 1.0;
  } completion:^(BOOL completed) {
    self.settling = NO;
    if (finish) [self invokeCancel];
  }];
}
- (void)invokeCancel {
  id target = self.target;
  if ([target respondsToSelector:self.cancelAction]) {
    void (*cancel)(id, SEL) = (void (*)(id, SEL))[target methodForSelector:self.cancelAction];
    cancel(target, self.cancelAction);
  }
}
@end

static char NFBInteractiveSheetKey;
static void NFBInstallDismissGesture(UIView *sheet, UIView *backdrop, id target, SEL action, BOOL composer) {
  if (!sheet || objc_getAssociatedObject(sheet, &NFBInteractiveSheetKey)) return;
  NFBInteractiveSheetDrag *drag = [[NFBInteractiveSheetDrag alloc] init];
  drag.sheet = sheet; drag.backdrop = backdrop; drag.target = target;
  drag.cancelAction = action; drag.composer = composer;
  UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:drag action:@selector(panned:)];
  pan.maximumNumberOfTouches = 1;
  pan.delegate = drag;
  [sheet addGestureRecognizer:pan];
  objc_setAssociatedObject(sheet, &NFBInteractiveSheetKey, drag, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void NFBInstallSheetDismissGesture(UIView *sheet, UIView *backdrop, id target, SEL cancelAction) {
  NFBInstallDismissGesture(sheet, backdrop, target, cancelAction, NO);
}
void NFBInstallComposerDismissGesture(UIView *composer, id target, SEL cancelAction) {
  NFBInstallDismissGesture(composer, nil, target, cancelAction, YES);
}
