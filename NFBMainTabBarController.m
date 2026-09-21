#import "NFBMainTabBarController.h"
#import "NFBGesturePolicy.h"

#import "NFBAtprotoSession.h"
#import "NFBBlueskyLoginViewController.h"
#import "NFBComposeViewController.h"
#import "NFBMessagesViewController.h"
#import "NFBNeoFreeBirdUI.h"
#import "NFBNotificationCoordinator.h"
#import "NFBSideMenuViewController.h"
#import "NFBTimelineViewController.h"
#import "NFBTheme.h"
#import "NFBTweetDetailViewController.h"

static NSInteger const NFBTabBadgeViewTag = 93841;
static NSInteger const NFBTabBadgeLabelTag = 93842;
static NSString * const NFBNavigationStackDidChangeNotification = @"NFBNavigationStackDidChangeNotification";

static NSString *NFBNotificationStringForKeys(NSDictionary *dictionary, NSArray<NSString *> *keys) {
  if (![dictionary isKindOfClass:NSDictionary.class]) return @"";
  for (NSString *key in keys) {
    id value = dictionary[key];
    if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) return value;
    if ([value respondsToSelector:@selector(stringValue)]) {
      NSString *stringValue = [value stringValue];
      if (stringValue.length > 0) return stringValue;
    }
  }
  return @"";
}

static NSDictionary *NFBNotificationDictionaryForKeys(NSDictionary *dictionary, NSArray<NSString *> *keys) {
  if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
  for (NSString *key in keys) {
    id value = dictionary[key];
    if ([value isKindOfClass:NSDictionary.class]) return value;
  }
  return nil;
}

@interface NFBPlaceholderTabViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title iconName:(NSString *)iconName;

@end

@implementation NFBPlaceholderTabViewController {
  NSString *_placeholderTitle;
  NSString *_iconName;
}

- (instancetype)initWithTitle:(NSString *)title iconName:(NSString *)iconName {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _placeholderTitle = [title copy];
    _iconName = [iconName copy];
    self.title = title;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBColorBackground();
  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(_iconName)];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.tintColor = NFBColorSecondaryText();
  icon.contentMode = UIViewContentModeScaleAspectFit;

  UILabel *title = [[UILabel alloc] init];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.text = _placeholderTitle;
  title.textColor = NFBColorText();
  title.font = NFBFont(28.0, NFBFontWeightHeavy);

  [self.view addSubview:icon];
  [self.view addSubview:title];
  [NSLayoutConstraint activateConstraints:@[
    [icon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [icon.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-36.0],
    [icon.widthAnchor constraintEqualToConstant:52.0],
    [icon.heightAnchor constraintEqualToConstant:52.0],
    [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:18.0]
  ]];
}

@end

@interface NFBBackTransition : NSObject <UIViewControllerAnimatedTransitioning>
@end
@implementation NFBBackTransition
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
  return UIAccessibilityIsReduceMotionEnabled() ? 0.15 : 0.4;
}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
  UIView *from = [context viewForKey:UITransitionContextFromViewKey];
  UIView *to = [context viewForKey:UITransitionContextToViewKey];
  UIViewController *destination = [context viewControllerForKey:UITransitionContextToViewControllerKey];
  CGRect finalFrame = [context finalFrameForViewController:destination];
  CGFloat width = CGRectGetWidth(context.containerView.bounds);
  to.frame = finalFrame;
  CGFloat direction = context.containerView.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? -1.0 : 1.0;
  to.transform = CGAffineTransformMakeTranslation(-direction * width / 3.0, 0.0);
  [context.containerView insertSubview:to belowSubview:from];
  UIView *shade = [[UIView alloc] initWithFrame:to.bounds];
  shade.backgroundColor = UIColor.blackColor;
  shade.alpha = 0.12;
  [to addSubview:shade];
  [UIView animateWithDuration:[self transitionDuration:context] delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
    from.transform = CGAffineTransformMakeTranslation(direction * width, 0.0);
    to.transform = CGAffineTransformIdentity;
    shade.alpha = 0.0;
  } completion:^(BOOL finished) {
    [shade removeFromSuperview];
    from.transform = CGAffineTransformIdentity;
    to.transform = CGAffineTransformIdentity;
    [context completeTransition:!context.transitionWasCancelled];
  }];
}
@end

@interface NFBNavigationController : UINavigationController <UIGestureRecognizerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIPanGestureRecognizer *nfbFullWidthBackPanGestureRecognizer;
@property (nonatomic, strong) UIPercentDrivenInteractiveTransition *nfbBackInteraction;
@property (nonatomic, assign) BOOL nfbBackTransitionInFlight;
@end

@implementation NFBNavigationController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.delegate = self;
  [self configureInteractivePopGesture];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self configureInteractivePopGesture];
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
  [super pushViewController:viewController animated:animated];
  [self configureInteractivePopGesture];
}

- (NSArray<UIViewController *> *)popToRootViewControllerAnimated:(BOOL)animated {
  NSArray<UIViewController *> *controllers = [super popToRootViewControllerAnimated:animated];
  [self configureInteractivePopGesture];
  return controllers;
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
  UIViewController *controller = [super popViewControllerAnimated:animated];
  [self configureInteractivePopGesture];
  return controller;
}

- (void)configureInteractivePopGesture {
  if (self.nfbBackTransitionInFlight) return;
  self.interactivePopGestureRecognizer.enabled = self.viewControllers.count > 1;
  self.interactivePopGestureRecognizer.delegate = self;
  if (!self.nfbFullWidthBackPanGestureRecognizer) {
    self.nfbFullWidthBackPanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(nfbFullWidthBackPanned:)];
    self.nfbFullWidthBackPanGestureRecognizer.cancelsTouchesInView = YES;
    self.nfbFullWidthBackPanGestureRecognizer.maximumNumberOfTouches = 1;
    self.nfbFullWidthBackPanGestureRecognizer.delaysTouchesBegan = NO;
    self.nfbFullWidthBackPanGestureRecognizer.allowedScrollTypesMask = UIScrollTypeMaskAll;
    self.nfbFullWidthBackPanGestureRecognizer.delegate = self;
    [self.view addGestureRecognizer:self.nfbFullWidthBackPanGestureRecognizer];
    [self.nfbFullWidthBackPanGestureRecognizer requireGestureRecognizerToFail:self.interactivePopGestureRecognizer];
  }
  self.nfbFullWidthBackPanGestureRecognizer.enabled = self.viewControllers.count > 1;
}

- (void)nfbFullWidthBackPanned:(UIPanGestureRecognizer *)gesture {
  CGFloat width = MAX(1.0, CGRectGetWidth(self.view.bounds));
  CGFloat direction = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? -1.0 : 1.0;
  CGFloat progress = MIN(1.0, MAX(0.0, direction * [gesture translationInView:self.view].x / width));
  if (gesture.state == UIGestureRecognizerStateBegan) {
    if (self.viewControllers.count <= 1 || self.transitionCoordinator || self.nfbBackTransitionInFlight) return;
    self.nfbBackTransitionInFlight = YES;
    [self nfbStopVerticalScrollingAtPoint:[gesture locationInView:self.view]];
    self.nfbBackInteraction = [[UIPercentDrivenInteractiveTransition alloc] init];
    self.nfbBackInteraction.completionCurve = UIViewAnimationCurveEaseOut;
    [self popViewControllerAnimated:YES];
    [self.nfbBackInteraction updateInteractiveTransition:progress];
  } else if (gesture.state == UIGestureRecognizerStateChanged) {
    [self.nfbBackInteraction updateInteractiveTransition:progress];
  } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
    if (!self.nfbBackInteraction) return;
    BOOL finish = NFBBackSwipeShouldFinish(progress, direction * [gesture velocityInView:self.view].x, gesture.state != UIGestureRecognizerStateEnded);
    self.nfbBackInteraction.completionSpeed = 0.99;
    self.nfbBackInteraction.completionCurve = UIViewAnimationCurveEaseInOut;
    if (finish) [self.nfbBackInteraction finishInteractiveTransition];
    else [self.nfbBackInteraction cancelInteractiveTransition];
    // Keep the interaction alive until didShow, including a cancelled pop.
  }
}

- (void)nfbStopVerticalScrollingAtPoint:(CGPoint)point {
  for (UIView *view = [self.view hitTest:point withEvent:nil]; view && view != self.view; view = view.superview) {
    if (![view isKindOfClass:UIScrollView.class]) continue;
    UIScrollView *scroll = (UIScrollView *)view;
    if (!scroll.scrollEnabled || scroll.contentSize.width > CGRectGetWidth(scroll.bounds) + 1.0 || scroll.zoomScale > scroll.minimumZoomScale + 0.01) continue;
    [scroll setContentOffset:scroll.contentOffset animated:NO];
    scroll.panGestureRecognizer.enabled = NO;
    scroll.panGestureRecognizer.enabled = YES;
  }
}

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC toViewController:(UIViewController *)toVC {
  return operation == UINavigationControllerOperationPop && self.nfbBackInteraction ? [[NFBBackTransition alloc] init] : nil;
}

- (id<UIViewControllerInteractiveTransitioning>)navigationController:(UINavigationController *)navigationController interactionControllerForAnimationController:(id<UIViewControllerAnimatedTransitioning>)animationController {
  return self.nfbBackInteraction;
}

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
  (void)navigationController;
  (void)viewController;
  (void)animated;
  self.nfbBackInteraction = nil;
  self.nfbBackTransitionInFlight = NO;
  [self configureInteractivePopGesture];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBNavigationStackDidChangeNotification object:self];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  if (gestureRecognizer == self.interactivePopGestureRecognizer || gestureRecognizer == self.nfbFullWidthBackPanGestureRecognizer) {
    if (self.viewControllers.count <= 1) return NO;
    if (self.transitionCoordinator || self.nfbBackTransitionInFlight || self.presentedViewController) return NO;
    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
    CGFloat direction = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? -1.0 : 1.0;
    if (gestureRecognizer == self.nfbFullWidthBackPanGestureRecognizer) {
      CGPoint point = [gestureRecognizer locationInView:self.view];
      if (NFBTouchIsInHorizontalScrollerForVelocity(self.view, point, velocity)) return NO;
      id<NFBHorizontalPagingSurface> top = (id)self.topViewController;
      if ([top respondsToSelector:@selector(nfb_canPageHorizontallyWithVelocity:)] && [top nfb_canPageHorizontallyWithVelocity:velocity]) return NO;
    }
    if (gestureRecognizer == self.nfbFullWidthBackPanGestureRecognizer) {
      if (!NFBBackSwipeShouldBegin(direction * velocity.x, velocity.y)) return NO;
    } else if (direction * velocity.x < 0.0) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  if (gestureRecognizer == self.nfbFullWidthBackPanGestureRecognizer && gestureRecognizer.state == UIGestureRecognizerStatePossible &&
      [otherGestureRecognizer.view isKindOfClass:UIScrollView.class]) {
    UIScrollView *scroll = (UIScrollView *)otherGestureRecognizer.view;
    return scroll.contentSize.width <= CGRectGetWidth(scroll.bounds) + 1.0 && scroll.zoomScale <= scroll.minimumZoomScale + 0.01;
  }
  return NO;
}

@end

@interface NFBMainTabBarController () <UITabBarControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, assign) BOOL sideMenuPresentationInProgress;
@property (nonatomic, strong) NFBSideMenuViewController *interactiveSideMenu;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *leftEdgeMenuGestureRecognizer;
@property (nonatomic, strong) UIVisualEffectView *nfbTabBarBackgroundView;
@property (nonatomic, strong) UIView *nfbTabBarDividerView;
@property (nonatomic, assign) NSUInteger currentHomeBadgeCount;
@property (nonatomic, assign) NSUInteger currentNotificationBadgeCount;
@property (nonatomic, assign) NSUInteger currentMessageBadgeCount;
@property (nonatomic, assign) BOOL reselectingCurrentTab;
@property (nonatomic, copy) NSString *displayedAccountDID;
@property (nonatomic, assign) NSUInteger displayedAccountGeneration;
@end

@implementation NFBMainTabBarController

- (void)viewDidLoad {
  [super viewDidLoad];
  NFBApplyNeoFreeBirdFirstRunDefaults();
  self.delegate = self;
  [self configureTabBarAppearance];
  [self configureLeftEdgeMenuGesture];

  self.displayedAccountDID = [NFBAtprotoSession sharedSession].did ?: @"";
  self.displayedAccountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  [self rebuildTabControllers];
  [self updateLeftEdgeMenuGestureEnabled];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged:) name:NFBAtprotoSessionChangedNotification object:[NFBAtprotoSession sharedSession]];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationCountsChanged:) name:NFBNotificationCountsDidChangeNotification object:[NFBNotificationCoordinator sharedCoordinator]];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(navigationStackChanged:) name:NFBNavigationStackDidChangeNotification object:nil];
  [[NFBNotificationCoordinator sharedCoordinator] start];
}

- (void)configureLeftEdgeMenuGesture {
  if (self.leftEdgeMenuGestureRecognizer) return;
  UIScreenEdgePanGestureRecognizer *edgePan = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(leftEdgeMenuPanned:)];
  edgePan.edges = UIRectEdgeLeft;
  edgePan.cancelsTouchesInView = YES;
  edgePan.delegate = self;
  self.leftEdgeMenuGestureRecognizer = edgePan;
  [self.view addGestureRecognizer:edgePan];
  [self updateLeftEdgeMenuGestureEnabled];
}

- (UIViewController *)topPresentedControllerFromController:(UIViewController *)controller {
  UIViewController *current = controller ?: self;
  while (current.presentedViewController) current = current.presentedViewController;
  return current;
}

- (UINavigationController *)selectedNavigationController {
  UIViewController *selected = self.selectedViewController;
  if ([selected isKindOfClass:UINavigationController.class]) return (UINavigationController *)selected;
  return selected.navigationController;
}

- (BOOL)selectedNavigationControllerCanPop {
  UINavigationController *navigationController = [self selectedNavigationController];
  if (!navigationController || navigationController.viewControllers.count <= 1) return NO;
  return navigationController.topViewController != navigationController.viewControllers.firstObject;
}

- (UIViewController *)selectedRootSurfaceController {
  UIViewController *selected = self.selectedViewController;
  UINavigationController *navigationController = [self selectedNavigationController];
  if (navigationController) return navigationController.viewControllers.firstObject ?: navigationController;
  return selected ?: self;
}

- (BOOL)viewControllerOrVisibleChildHasPresentedController:(UIViewController *)controller {
  if (!controller) return NO;
  if (controller.presentedViewController) return YES;
  if ([controller isKindOfClass:UINavigationController.class]) {
    UINavigationController *navigationController = (UINavigationController *)controller;
    if (navigationController.topViewController.presentedViewController) return YES;
  }
  if ([controller isKindOfClass:UITabBarController.class]) {
    UITabBarController *tabBarController = (UITabBarController *)controller;
    if (tabBarController.selectedViewController.presentedViewController) return YES;
  }
  return NO;
}

- (BOOL)selectedTabIsAtRootSurface {
  UIViewController *selected = self.selectedViewController;
  if (!selected) return NO;
  if ([self viewControllerOrVisibleChildHasPresentedController:self]) return NO;
  if ([self viewControllerOrVisibleChildHasPresentedController:selected]) return NO;

  UINavigationController *navigationController = [self selectedNavigationController];
  if (!navigationController) return selected.navigationController.viewControllers.firstObject == selected || selected.navigationController == nil;
  if (navigationController.viewControllers.count != 1) return NO;
  return navigationController.topViewController == navigationController.viewControllers.firstObject;
}

- (void)updateLeftEdgeMenuGestureEnabled {
  if (!self.leftEdgeMenuGestureRecognizer || self.interactiveSideMenu) return;
  self.leftEdgeMenuGestureRecognizer.enabled = [self selectedTabIsAtRootSurface];
}

- (BOOL)canBeginLeftEdgeMenuGesture:(UIGestureRecognizer *)gestureRecognizer {
  if (gestureRecognizer != self.leftEdgeMenuGestureRecognizer) return YES;
  if (self.sideMenuPresentationInProgress) return NO;
  if ([self selectedNavigationControllerCanPop]) return NO;
  if (![self selectedTabIsAtRootSurface]) return NO;

  CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
  if (fabs(velocity.x) + fabs(velocity.y) > 1.0) {
    if (velocity.x <= 0.0 || fabs(velocity.x) < fabs(velocity.y)) return NO;
  }
  return YES;
}

- (void)leftEdgeMenuPanned:(UIScreenEdgePanGestureRecognizer *)gesture {
  if (gesture.state == UIGestureRecognizerStateBegan) {
    if (![self canBeginLeftEdgeMenuGesture:gesture]) return;
    UIViewController *presenter = [self selectedRootSurfaceController];
    if (!presenter) return;
    self.sideMenuPresentationInProgress = YES;
    NFBSideMenuViewController *menu = [[NFBSideMenuViewController alloc] init];
    menu.interactiveOpening = YES;
    menu.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.interactiveSideMenu = menu;
    [presenter presentViewController:menu animated:NO completion:^{
      self.sideMenuPresentationInProgress = NO;
    }];
  }
  if (!self.interactiveSideMenu) return;
  [self.interactiveSideMenu updateOpeningTranslation:[gesture translationInView:self.view].x];
  if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
    [self.interactiveSideMenu finishOpeningWithVelocity:[gesture velocityInView:self.view].x cancelled:gesture.state != UIGestureRecognizerStateEnded];
    self.interactiveSideMenu = nil;
  }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  return [self canBeginLeftEdgeMenuGesture:gestureRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  if (gestureRecognizer == self.leftEdgeMenuGestureRecognizer || otherGestureRecognizer == self.leftEdgeMenuGestureRecognizer) {
    return NO;
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  UINavigationController *navigationController = [self selectedNavigationController];
  if (gestureRecognizer == self.leftEdgeMenuGestureRecognizer && otherGestureRecognizer == navigationController.interactivePopGestureRecognizer) {
    return YES;
  }
  return NO;
}

- (void)navigationStackChanged:(NSNotification *)notification {
  (void)notification;
  [self updateLeftEdgeMenuGestureEnabled];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
  }
  [self updateLeftEdgeMenuGestureEnabled];
  [self applyCurrentTabBadges];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self layoutIPATabBarChrome];
  [self updateLeftEdgeMenuGestureEnabled];
  [self applyCurrentTabBadges];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureTabBarAppearance {
  NFBApplyTabBarAppearance(self.tabBar);
  [self configureIPATabBarChrome];
}

- (void)configureIPATabBarChrome {
  self.tabBar.clipsToBounds = NO;
  self.tabBar.opaque = NO;
  self.tabBar.backgroundColor = UIColor.clearColor;

  if (!self.nfbTabBarBackgroundView) {
    self.nfbTabBarBackgroundView = [[UIVisualEffectView alloc] initWithEffect:NFBIPATabBarBackgroundEffect()];
    self.nfbTabBarBackgroundView.userInteractionEnabled = NO;
    [self.tabBar insertSubview:self.nfbTabBarBackgroundView atIndex:0];
  }
  self.nfbTabBarBackgroundView.effect = NFBIPATabBarBackgroundEffect();
  self.nfbTabBarBackgroundView.backgroundColor = NFBIPAColor(NFBIPAColorRoleTabBarBackground);
  self.nfbTabBarBackgroundView.contentView.backgroundColor = NFBIPAColor(NFBIPAColorRoleTabBarBackground);

  if (!self.nfbTabBarDividerView) {
    self.nfbTabBarDividerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.nfbTabBarDividerView.userInteractionEnabled = NO;
    [self.tabBar insertSubview:self.nfbTabBarDividerView aboveSubview:self.nfbTabBarBackgroundView];
  }
  self.nfbTabBarDividerView.backgroundColor = NFBIPAColor(NFBIPAColorRoleTabBarDivider);
  [self layoutIPATabBarChrome];
}

- (void)layoutIPATabBarChrome {
  if (!self.nfbTabBarBackgroundView || !self.nfbTabBarDividerView) return;
  self.nfbTabBarBackgroundView.frame = self.tabBar.bounds;
  CGFloat pixel = 1.0 / UIScreen.mainScreen.scale;
  self.nfbTabBarDividerView.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(self.tabBar.bounds), pixel);
  [self.tabBar sendSubviewToBack:self.nfbTabBarBackgroundView];
  [self.tabBar bringSubviewToFront:self.nfbTabBarDividerView];
}

- (UIViewController *)controllerForTabDefinition:(NFBNeoFreeBirdTabDefinition *)definition {
  if ([definition.pageID isEqualToString:@"home"]) {
    return [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindHome actor:nil];
  }
  if ([definition.pageID isEqualToString:@"guide"]) {
    return [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindSearch actor:nil];
  }
  if ([definition.pageID isEqualToString:@"ntab"]) {
    return [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindNotifications actor:nil];
  }
  if ([definition.pageID isEqualToString:@"messages"]) {
    return [[NFBMessagesViewController alloc] init];
  }
  if ([definition.pageID isEqualToString:@"profile"]) {
    return [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:nil];
  }
  return [[NFBPlaceholderTabViewController alloc] initWithTitle:definition.title iconName:definition.iconName];
}

- (UINavigationController *)navigationControllerForController:(UIViewController *)controller tabDefinition:(NFBNeoFreeBirdTabDefinition *)definition {
  NFBNavigationController *nav = [[NFBNavigationController alloc] initWithRootViewController:controller];
  NFBApplyNavigationAppearance(nav);
  if (self.leftEdgeMenuGestureRecognizer && nav.interactivePopGestureRecognizer) {
    [self.leftEdgeMenuGestureRecognizer requireGestureRecognizerToFail:nav.interactivePopGestureRecognizer];
  }
  UIImage *image = NFBTemplateIcon(definition.iconName);
  UIImage *selectedImage = NFBTemplateIcon(definition.selectedIconName ?: definition.iconName);
  nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"" image:image selectedImage:selectedImage];
  nav.tabBarItem.accessibilityLabel = definition.title;
  nav.tabBarItem.imageInsets = UIEdgeInsetsMake(5.0, 0.0, -5.0, 0.0);
  nav.tabBarItem.titlePositionAdjustment = UIOffsetMake(0.0, 300.0);
  NSDictionary *hiddenAttributes = @{
    NSForegroundColorAttributeName: UIColor.clearColor,
    NSFontAttributeName: [UIFont systemFontOfSize:0.1]
  };
  [nav.tabBarItem setTitleTextAttributes:hiddenAttributes forState:UIControlStateNormal];
  [nav.tabBarItem setTitleTextAttributes:hiddenAttributes forState:UIControlStateSelected];
  return nav;
}

- (void)sessionChanged:(NSNotification *)notification {
  (void)notification;
  if (!NSThread.isMainThread) {
    dispatch_async(dispatch_get_main_queue(), ^{ [self sessionChanged:notification]; });
    return;
  }
  NSString *accountDID = [NFBAtprotoSession sharedSession].did ?: @"";
  NSUInteger accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  if ([self.displayedAccountDID isEqualToString:accountDID] && self.displayedAccountGeneration == accountGeneration) return;
  self.displayedAccountDID = accountDID;
  self.displayedAccountGeneration = accountGeneration;
  NSUInteger selectedIndex = self.selectedIndex;
  UIView *previousScreen = self.isViewLoaded ? [self.view snapshotViewAfterScreenUpdates:NO] : nil;
  self.currentHomeBadgeCount = 0;
  self.currentNotificationBadgeCount = 0;
  self.currentMessageBadgeCount = 0;
  // Reference T1HostViewController changes the whole account navigation tree,
  // preserves the current panel, and crossfades it over 0.35 seconds.
  [self rebuildTabControllers];
  self.selectedIndex = selectedIndex < self.viewControllers.count ? selectedIndex : 0;
  [self applyCurrentTabBadges];
  [self updateLeftEdgeMenuGestureEnabled];
  [self.view layoutIfNeeded];
  if (previousScreen) {
    previousScreen.userInteractionEnabled = NO;
    [self.view addSubview:previousScreen];
    [UIView animateWithDuration:0.35 animations:^{
      previousScreen.alpha = 0.0;
    } completion:^(BOOL finished) {
      (void)finished;
      [previousScreen removeFromSuperview];
    }];
  }
}

- (void)rebuildTabControllers {
  NSMutableArray<UIViewController *> *controllers = [NSMutableArray array];
  for (NFBNeoFreeBirdTabDefinition *definition in NFBNeoFreeBirdVisibleTabDefinitions()) {
    UIViewController *controller = [self controllerForTabDefinition:definition];
    if (controller) [controllers addObject:[self navigationControllerForController:controller tabDefinition:definition]];
  }
  self.viewControllers = controllers;
}

- (void)notificationCountsChanged:(NSNotification *)notification {
  NSDictionary *counts = notification.userInfo ?: @{};
  self.currentHomeBadgeCount = [counts[@"home"] respondsToSelector:@selector(unsignedIntegerValue)] ? [counts[@"home"] unsignedIntegerValue] : 0;
  self.currentNotificationBadgeCount = [counts[@"notifications"] respondsToSelector:@selector(unsignedIntegerValue)] ? [counts[@"notifications"] unsignedIntegerValue] : 0;
  self.currentMessageBadgeCount = [counts[@"messages"] respondsToSelector:@selector(unsignedIntegerValue)] ? [counts[@"messages"] unsignedIntegerValue] : 0;
  [self applyCurrentTabBadges];
}

- (NSArray<UIControl *> *)orderedTabControls {
  NSMutableArray<UIControl *> *tabControls = [NSMutableArray array];
  for (UIView *subview in self.tabBar.subviews) {
    if ([subview isKindOfClass:UIControl.class]) [tabControls addObject:(UIControl *)subview];
  }
  [tabControls sortUsingComparator:^NSComparisonResult(UIControl *a, UIControl *b) {
    CGFloat ax = CGRectGetMinX(a.frame);
    CGFloat bx = CGRectGetMinX(b.frame);
    if (ax < bx) return NSOrderedAscending;
    if (ax > bx) return NSOrderedDescending;
    return NSOrderedSame;
  }];
  return tabControls;
}

- (void)applyCurrentTabBadges {
  [self setBadgeValueForPage:@"home" count:self.currentHomeBadgeCount dotOnly:YES messageBadge:NO];
  [self setBadgeValueForPage:@"ntab" count:self.currentNotificationBadgeCount dotOnly:NO messageBadge:NO];
  [self setBadgeValueForPage:@"messages" count:self.currentMessageBadgeCount dotOnly:NO messageBadge:YES];
}

- (void)setBadgeValueForPage:(NSString *)pageID count:(NSUInteger)count dotOnly:(BOOL)dotOnly messageBadge:(BOOL)messageBadge {
  NSArray<NFBNeoFreeBirdTabDefinition *> *definitions = NFBNeoFreeBirdVisibleTabDefinitions();
  NSArray<UIControl *> *tabControls = [self orderedTabControls];
  [definitions enumerateObjectsUsingBlock:^(NFBNeoFreeBirdTabDefinition *definition, NSUInteger index, BOOL *stop) {
    (void)stop;
    if (![definition.pageID isEqualToString:pageID] || index >= self.viewControllers.count || index >= tabControls.count) return;
    UITabBarItem *item = self.viewControllers[index].tabBarItem;
    item.badgeValue = nil;
    item.badgeColor = UIColor.clearColor;
    if (count == 0) {
      [self removeCustomBadgeFromTabControl:tabControls[index]];
      item.accessibilityValue = nil;
      return;
    }
    [self updateCustomBadgeOnTabControl:tabControls[index] count:count dotOnly:dotOnly messageBadge:messageBadge];
    item.accessibilityValue = dotOnly ? @"New posts" : [NSString stringWithFormat:@"%lu unread", (unsigned long)count];
  }];
}

- (void)removeCustomBadgeFromTabControl:(UIControl *)control {
  UIView *badge = [control viewWithTag:NFBTabBadgeViewTag];
  [badge removeFromSuperview];
}

- (void)updateCustomBadgeOnTabControl:(UIControl *)control count:(NSUInteger)count dotOnly:(BOOL)dotOnly messageBadge:(BOOL)messageBadge {
  UIView *badge = [control viewWithTag:NFBTabBadgeViewTag];
  UILabel *label = nil;
  if (!badge) {
    badge = [[UIView alloc] initWithFrame:CGRectZero];
    badge.tag = NFBTabBadgeViewTag;
    badge.userInteractionEnabled = NO;
    badge.clipsToBounds = YES;
    [control addSubview:badge];

    label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.tag = NFBTabBadgeLabelTag;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = NFBFont(11.0, NFBFontWeightHeavy);
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.72;
    label.userInteractionEnabled = NO;
    [badge addSubview:label];
  } else {
    label = (UILabel *)[badge viewWithTag:NFBTabBadgeLabelTag];
  }

  UIColor *accent = messageBadge ? NFBColorBlue() : NFBColorAccent();
  if (dotOnly) {
    badge.backgroundColor = accent;
    badge.layer.borderWidth = 0.0;
    badge.layer.borderColor = nil;
    label.hidden = YES;
    CGFloat size = 7.0;
    badge.frame = CGRectMake(CGRectGetMidX(control.bounds) + 10.0, 9.0, size, size);
    badge.layer.cornerRadius = size * 0.5;
    return;
  }

  NSString *text = count > 99 ? @"99+" : [NSString stringWithFormat:@"%lu", (unsigned long)count];
  label.hidden = NO;
  label.text = text;
  label.textColor = UIColor.whiteColor;

  CGFloat height = messageBadge ? 17.0 : 18.0;
  CGFloat textWidth = ceil([text sizeWithAttributes:@{NSFontAttributeName: label.font}].width);
  CGFloat horizontalPadding = messageBadge ? 7.0 : 9.0;
  CGFloat width = MAX(height, textWidth + horizontalPadding);
  CGFloat originX = CGRectGetMidX(control.bounds) + (messageBadge ? 7.0 : 7.5);
  CGFloat originY = 5.0;
  badge.frame = CGRectMake(originX, originY, width, height);
  badge.layer.cornerRadius = height * 0.5;
  // Twitter 9.67 T1TabView uses a filled badge and an opaque edge matching
  // the page background (black in Lights out), with white count text.
  badge.backgroundColor = accent;
  badge.layer.borderWidth = messageBadge ? 1.5 : 0.0;
  badge.layer.borderColor = messageBadge ? NFBColorBackground().CGColor : nil;
  badge.layer.allowsEdgeAntialiasing = YES;
  label.frame = badge.bounds;
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  self.view.backgroundColor = NFBColorBackground();
  [self configureTabBarAppearance];
  for (UIViewController *controller in self.viewControllers) {
    if ([controller isKindOfClass:UINavigationController.class]) {
      NFBApplyNavigationAppearance((UINavigationController *)controller);
    }
  }
  [self notificationCountsChanged:[NSNotification notificationWithName:NFBNotificationCountsDidChangeNotification object:[NFBNotificationCoordinator sharedCoordinator] userInfo:@{
    @"home": @([NFBNotificationCoordinator sharedCoordinator].homeBadgeCount),
    @"notifications": @([NFBNotificationCoordinator sharedCoordinator].notificationBadgeCount),
    @"messages": @([NFBNotificationCoordinator sharedCoordinator].messageBadgeCount)
  }]];
}

- (void)openURL:(NSURL *)url {
  [[NFBAtprotoSession sharedSession] handleOAuthCallbackURL:url];
}

- (NSUInteger)indexForPageID:(NSString *)pageID {
  __block NSUInteger foundIndex = NSNotFound;
  [NFBNeoFreeBirdVisibleTabDefinitions() enumerateObjectsUsingBlock:^(NFBNeoFreeBirdTabDefinition *definition, NSUInteger index, BOOL *stop) {
    if ([definition.pageID isEqualToString:pageID]) {
      foundIndex = index;
      *stop = YES;
    }
  }];
  return foundIndex;
}

- (NSArray<NSDictionary *> *)notificationRouteDictionariesFromUserInfo:(NSDictionary *)userInfo {
  if (![userInfo isKindOfClass:NSDictionary.class]) return @[];
  NSMutableArray<NSDictionary *> *sources = [NSMutableArray array];
  void (^addSource)(NSDictionary *) = ^(NSDictionary *source) {
    if ([source isKindOfClass:NSDictionary.class] && ![sources containsObject:source]) [sources addObject:source];
  };

  addSource(userInfo);
  NSDictionary *topLevelData = NFBNotificationDictionaryForKeys(userInfo, @[@"data"]);
  addSource(topLevelData);
  NSDictionary *notification = NFBNotificationDictionaryForKeys(userInfo, @[@"notification", @"payload"]);
  addSource(notification);
  addSource(NFBNotificationDictionaryForKeys(notification, @[@"data", @"payload"]));
  addSource(NFBNotificationDictionaryForKeys(topLevelData, @[@"notification", @"payload"]));
  addSource(NFBNotificationDictionaryForKeys(topLevelData, @[@"data", @"payload"]));
  return sources;
}

- (NSString *)notificationRouteStringFromUserInfo:(NSDictionary *)userInfo keys:(NSArray<NSString *> *)keys {
  for (NSDictionary *source in [self notificationRouteDictionariesFromUserInfo:userInfo]) {
    NSString *value = NFBNotificationStringForKeys(source, keys);
    if (value.length > 0) return value;
  }
  return @"";
}

- (NSString *)notificationPostURIFromUserInfo:(NSDictionary *)userInfo reason:(NSString *)reason {
  NSString *reasonSubject = [self notificationRouteStringFromUserInfo:userInfo keys:@[@"reasonSubject", @"reason_subject"]];
  NSString *normalizedReason = reason.lowercaseString ?: @"";
  if (([normalizedReason isEqualToString:@"like"] || [normalizedReason isEqualToString:@"repost"]) && reasonSubject.length > 0) return reasonSubject;

  return [self notificationRouteStringFromUserInfo:userInfo keys:@[@"targetURI", @"targetUri", @"postURI", @"postUri", @"uri", @"subject"]];
}

- (NSString *)notificationActorFromUserInfo:(NSDictionary *)userInfo {
  NSString *actor = [self notificationRouteStringFromUserInfo:userInfo keys:@[@"actor", @"did", @"handle", @"authorDid", @"authorDID", @"authorHandle", @"senderDid", @"senderHandle"]];
  if (actor.length > 0) return actor;

  for (NSDictionary *source in [self notificationRouteDictionariesFromUserInfo:userInfo]) {
    NSDictionary *profile = NFBNotificationDictionaryForKeys(source, @[@"author", @"profile", @"user", @"actorProfile", @"sender", @"senderUser"]);
    actor = NFBNotificationStringForKeys(profile, @[@"did", @"handle"]);
    if (actor.length > 0) return actor;
  }
  return @"";
}

- (BOOL)notificationReasonRoutesToProfile:(NSString *)reason {
  NSString *normalizedReason = reason.lowercaseString ?: @"";
  return [normalizedReason isEqualToString:@"follow"] || [normalizedReason isEqualToString:@"starterpack-joined"];
}

- (BOOL)notificationUserInfoRoutesToMessages:(NSDictionary *)userInfo {
  NSString *kind = [[self notificationRouteStringFromUserInfo:userInfo keys:@[@"kind", @"category", @"notificationKind"]] lowercaseString];
  NSString *reason = [[self notificationRouteStringFromUserInfo:userInfo keys:@[@"reason", @"notificationReason", @"event"]] lowercaseString];
  NSString *type = [[self notificationRouteStringFromUserInfo:userInfo keys:@[@"type", @"notificationType", @"apsCategory"]] lowercaseString];
  NSString *collection = [[self notificationRouteStringFromUserInfo:userInfo keys:@[@"collection", @"lexicon", @"appViewType"]] lowercaseString];
  return [kind isEqualToString:@"messages"] ||
         [kind isEqualToString:@"message"] ||
         [type containsString:@"chat"] ||
         [type containsString:@"message"] ||
         [reason containsString:@"chat"] ||
         [reason containsString:@"message"] ||
         [collection containsString:@"chat.bsky"] ||
         [collection containsString:@"convo"];
}

- (NSString *)notificationTabIDForReason:(NSString *)reason {
  NSString *normalizedReason = reason.lowercaseString ?: @"";
  if ([normalizedReason isEqualToString:@"mention"] ||
      [normalizedReason isEqualToString:@"reply"] ||
      [normalizedReason isEqualToString:@"quote"]) {
    return @"mentions";
  }
  return @"all";
}

- (void)openNotificationDestinationFromUserInfo:(NSDictionary *)userInfo navigationController:(UINavigationController *)navigationController {
  if (!navigationController) return;
  NSString *reason = [self notificationRouteStringFromUserInfo:userInfo keys:@[@"reason", @"notificationReason", @"event"]];

  if ([self notificationReasonRoutesToProfile:reason]) {
    NSString *actor = [self notificationActorFromUserInfo:userInfo];
    if (actor.length == 0) return;
    NFBTimelineViewController *profile = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
    [navigationController pushViewController:profile animated:YES];
    return;
  }

  NSString *postURI = [self notificationPostURIFromUserInfo:userInfo reason:reason];
  if (postURI.length == 0) return;

  NSString *cid = [self notificationRouteStringFromUserInfo:userInfo keys:@[@"cid"]];
  NSMutableDictionary *post = [@{
    @"uri": postURI,
    @"cid": cid ?: @"",
    @"record": @{@"text": @""},
    @"author": @{}
  } mutableCopy];
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
  [navigationController pushViewController:detail animated:YES];
}

- (void)openNotificationUserInfo:(NSDictionary *)userInfo {
  BOOL isMessage = [self notificationUserInfoRoutesToMessages:userInfo];
  NSString *pageID = isMessage ? @"messages" : @"ntab";
  NSUInteger index = [self indexForPageID:pageID];
  if (index == NSNotFound || index >= self.viewControllers.count) return;

  UIViewController *controller = self.viewControllers[index];
  self.selectedIndex = index;
  UIViewController *root = controller;
  UINavigationController *navigationController = nil;
  if ([controller isKindOfClass:UINavigationController.class]) {
    navigationController = (UINavigationController *)controller;
    [navigationController popToRootViewControllerAnimated:NO];
    root = navigationController.viewControllers.firstObject ?: navigationController;
  }

  if (isMessage) {
    [[NFBNotificationCoordinator sharedCoordinator] refreshMessageBadge];
    if ([root respondsToSelector:@selector(refreshConversations)]) [(id)root refreshConversations];
  } else {
    [[NFBNotificationCoordinator sharedCoordinator] clearNotificationBadge];
    NSString *reason = [self notificationRouteStringFromUserInfo:userInfo keys:@[@"reason", @"notificationReason", @"event"]];
    NSString *tabID = [self notificationTabIDForReason:reason];
    if ([root respondsToSelector:@selector(selectNotificationsTabWithID:refresh:)]) {
      [(id)root selectNotificationsTabWithID:tabID refresh:YES];
    } else if ([root respondsToSelector:@selector(refreshTimeline)]) {
      [(id)root refreshTimeline];
    }
    [self openNotificationDestinationFromUserInfo:userInfo navigationController:navigationController];
  }
}

#pragma mark - UITabBarControllerDelegate

- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController {
  self.reselectingCurrentTab = viewController == tabBarController.selectedViewController;
  return YES;
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
  [self updateLeftEdgeMenuGestureEnabled];
  BOOL reselectedCurrentTab = self.reselectingCurrentTab;
  self.reselectingCurrentTab = NO;
  NSUInteger index = [tabBarController.viewControllers indexOfObject:viewController];
  if (index == NSNotFound) return;
  NSMutableArray<UIControl *> *tabControls = [NSMutableArray array];
  for (UIView *subview in tabBarController.tabBar.subviews) {
    if ([subview isKindOfClass:UIControl.class]) [tabControls addObject:(UIControl *)subview];
  }
  [tabControls sortUsingComparator:^NSComparisonResult(UIControl *a, UIControl *b) {
    CGFloat ax = CGRectGetMinX(a.frame);
    CGFloat bx = CGRectGetMinX(b.frame);
    if (ax < bx) return NSOrderedAscending;
    if (ax > bx) return NSOrderedDescending;
    return NSOrderedSame;
  }];
  if (index >= tabControls.count) return;
  UIControl *control = tabControls[index];
  control.transform = CGAffineTransformMakeScale(0.92, 0.92);
  [UIView animateWithDuration:0.46
                        delay:0.0
       usingSpringWithDamping:0.54
        initialSpringVelocity:0.62
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                   animations:^{
    control.transform = CGAffineTransformIdentity;
  } completion:nil];

  NSString *label = viewController.tabBarItem.accessibilityLabel ?: @"";
  UIViewController *root = viewController;
  UINavigationController *navigationController = nil;
  UIViewController *stackRoot = viewController;
  if ([viewController isKindOfClass:UINavigationController.class]) {
    navigationController = (UINavigationController *)viewController;
    root = navigationController.topViewController ?: navigationController.viewControllers.firstObject;
    stackRoot = navigationController.viewControllers.firstObject ?: root;
  }
  if ([label isEqualToString:@"Home"]) {
    if (reselectedCurrentTab) {
      UIViewController *targetRoot = stackRoot ?: root;
      void (^handleHomeReselection)(void) = ^{
        if ([targetRoot respondsToSelector:@selector(handleHomeTabReselectionWithUnreadBadgeCount:)]) {
          [(id)targetRoot handleHomeTabReselectionWithUnreadBadgeCount:self.currentHomeBadgeCount];
        } else if ([targetRoot respondsToSelector:@selector(scrollToTopForTabSelection)]) {
          [(id)targetRoot scrollToTopForTabSelection];
        }
      };
      if (navigationController.viewControllers.count > 1) {
        [navigationController popToRootViewControllerAnimated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), handleHomeReselection);
      } else {
        handleHomeReselection();
      }
    } else if ([root respondsToSelector:@selector(refreshTimeline)]) {
      [(id)root refreshTimeline];
    }
  } else if ([label isEqualToString:@"Notifications"]) {
    [[NFBNotificationCoordinator sharedCoordinator] clearNotificationBadge];
    UIViewController *targetRoot = stackRoot ?: root;
    void (^handleNotificationsSelection)(void) = ^{
      if (reselectedCurrentTab && [targetRoot respondsToSelector:@selector(scrollToTopForTabSelection)]) {
        [(id)targetRoot scrollToTopForTabSelection];
      }
      if ([targetRoot respondsToSelector:@selector(refreshTimeline)]) [(id)targetRoot refreshTimeline];
    };
    if (reselectedCurrentTab && navigationController.viewControllers.count > 1) {
      [navigationController popToRootViewControllerAnimated:YES];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), handleNotificationsSelection);
    } else {
      handleNotificationsSelection();
    }
  } else if ([label isEqualToString:@"Messages"]) {
    [[NFBNotificationCoordinator sharedCoordinator] refreshMessageBadge];
    if ([root respondsToSelector:@selector(refreshConversations)]) [(id)root refreshConversations];
  }
}

- (void)presentComposer {
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
    return;
  }
  NFBComposeViewController *compose = [[NFBComposeViewController alloc] init];
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:compose];
  NFBApplyNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self.selectedViewController presentViewController:nav animated:YES completion:nil];
}

@end
