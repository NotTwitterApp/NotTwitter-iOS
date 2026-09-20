#import "NFBSideMenuViewController.h"
#import "NFBGesturePolicy.h"

#import "NFBAccountSwitcherViewController.h"
#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"
#import "NFBAccountAvatar.h"
#import "NFBBlueskyLoginViewController.h"
#import "NFBNotificationCoordinator.h"
#import "NFBSettingsViewController.h"
#import "NFBTheme.h"
#import "NFBTimelineViewController.h"

@interface NFBSettingsDetailViewController : UIViewController
- (instancetype)initWithSectionID:(NSString *)sectionID title:(NSString *)title;
@end

@interface NFBSideMenuViewController () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, assign) CGFloat openingProgress;
@property (nonatomic, assign) BOOL closing;
@property (nonatomic, assign) BOOL entranceResolved;
@property (nonatomic, assign) BOOL hasAppeared;
@property (nonatomic, strong) UIPanGestureRecognizer *closePanGesture;
@property (nonatomic, strong) NSLayoutConstraint *panelWidthConstraint;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *panelEdgeView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *countsLabel;
@property (nonatomic, assign) CGFloat panelWidth;
@property (nonatomic, strong) UIStackView *settingsRowsStack;
@property (nonatomic, strong) UIImageView *settingsChevron;
@property (nonatomic, assign) BOOL settingsExpanded;
@property (nonatomic, strong) UIView *appearanceFooterView;
@property (nonatomic, strong) UIView *appearanceFooterSeparator;
@property (nonatomic, strong) UIControl *appearanceToggleControl;
@property (nonatomic, strong) UIImageView *appearanceToggleIconView;
@property (nonatomic, strong) UILabel *appearanceToggleLabel;
@property (nonatomic, strong) NFBAccountSwitcherViewController *activeAccountSwitcher;
@property (nonatomic, strong) UIWindow *activeAccountSwitcherWindow;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, copy) NSArray<NSDictionary *> *previewAccounts;

@end

@implementation NFBSideMenuViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBIPADashDrawerScrimColor();
  self.view.clipsToBounds = NO;

  UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissTapped:)];
  dismissTap.cancelsTouchesInView = NO;
  [self.view addGestureRecognizer:dismissTap];

  CGFloat width = MIN(CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.86, 320.0);
  self.panelWidth = width;
  self.panelView = [[UIView alloc] init];
  self.panelView.translatesAutoresizingMaskIntoConstraints = NO;
  self.panelView.backgroundColor = NFBIPADashDrawerBackgroundColor();
  self.panelView.clipsToBounds = NO;
  self.panelView.layer.shadowColor = UIColor.blackColor.CGColor;
  self.panelView.layer.shadowOpacity = 0.22;
  self.panelView.layer.shadowRadius = 18.0;
  self.panelView.layer.shadowOffset = CGSizeMake(5.0, 0.0);
  [self.view addSubview:self.panelView];

  UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
  pan.delegate = self;
  pan.maximumNumberOfTouches = 1;
  self.closePanGesture = pan;
  [self.view addGestureRecognizer:pan];

  UIView *edge = [[UIView alloc] init];
  edge.translatesAutoresizingMaskIntoConstraints = NO;
  edge.backgroundColor = NFBIPADashDrawerSeparatorColor();
  self.panelEdgeView = edge;
  [self.panelView addSubview:edge];

  self.panelWidthConstraint = [self.panelView.widthAnchor constraintEqualToConstant:width];
  [NSLayoutConstraint activateConstraints:@[
    [self.panelView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.panelView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.panelView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    self.panelWidthConstraint,
    [edge.topAnchor constraintEqualToAnchor:self.panelView.topAnchor],
    [edge.bottomAnchor constraintEqualToAnchor:self.panelView.bottomAnchor],
    [edge.trailingAnchor constraintEqualToAnchor:self.panelView.trailingAnchor],
    [edge.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];

  [self buildPanel];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  if (self.hasAppeared) { [self applyOpenProgress:1.0]; return; }
  if (self.interactiveOpening) [self updateOpeningTranslation:self.panelWidth * self.openingProgress];
  else [self applyOpenProgress:0.0];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (self.hasAppeared) return;
  self.hasAppeared = YES;
  if (self.interactiveOpening || self.entranceResolved) return;
  [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    [self applyOpenProgress:1.0];
  } completion:nil];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = MIN(CGRectGetWidth(self.view.bounds) * 0.86, 320.0);
  if (fabs(width - self.panelWidth) > 0.5) {
    self.panelWidth = width;
    self.panelWidthConstraint.constant = width;
    [self applyOpenProgress:self.openingProgress];
  }
}

- (void)applyOpenProgress:(CGFloat)progress {
  self.openingProgress = MIN(1.0, MAX(0.0, progress));
  self.panelView.transform = CGAffineTransformMakeTranslation((self.openingProgress - 1.0) * self.panelWidth, 0.0);
  self.view.backgroundColor = [NFBIPADashDrawerScrimColor() colorWithAlphaComponent:NFBIPADashDrawerScrimAlpha() * self.openingProgress];
}

- (void)updateOpeningTranslation:(CGFloat)translation {
  [self loadViewIfNeeded];
  [self applyOpenProgress:translation / MAX(1.0, self.panelWidth)];
}

- (void)finishOpeningWithVelocity:(CGFloat)velocity cancelled:(BOOL)cancelled {
  self.entranceResolved = YES;
  BOOL finish = NFBShouldFinishSwipe(self.openingProgress, velocity, cancelled);
  // Keep the appearance callback from playing a second entrance animation.
  if (!finish) { [self close]; return; }
  [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    [self applyOpenProgress:1.0];
  } completion:^(BOOL finished) { self.interactiveOpening = NO; }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
  if (recognizer != self.closePanGesture) return YES;
  CGPoint velocity = [self.closePanGesture velocityInView:self.view];
  return !self.closing && !self.interactiveOpening && velocity.x < 0.0 && fabs(velocity.x) > fabs(velocity.y);
}

- (void)dismissTapped:(UITapGestureRecognizer *)recognizer {
  CGPoint point = [recognizer locationInView:self.view];
  if (CGRectContainsPoint(self.panelView.frame, point)) return;
  [self close];
}

- (void)panelTapped:(UITapGestureRecognizer *)recognizer {
  (void)recognizer;
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
  CGFloat translation = [recognizer translationInView:self.view].x;
  if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged) {
    [self applyOpenProgress:1.0 + translation / MAX(1.0, self.panelWidth)];
  } else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
    BOOL close = NFBShouldFinishSwipe(1.0 - self.openingProgress, -[recognizer velocityInView:self.view].x, recognizer.state != UIGestureRecognizerStateEnded);
    if (close) [self close];
    else [UIView animateWithDuration:0.18 animations:^{ [self applyOpenProgress:1.0]; }];
  }
}

- (void)close {
  [self closeWithCompletion:nil];
}

- (void)closeWithCompletion:(void (^)(void))completion {
  if (self.closing) return;
  self.closing = YES;
  [UIView animateWithDuration:0.18 animations:^{
    [self applyOpenProgress:0.0];
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:completion];
  }];
}

- (void)helpTapped {
  [self closeWithCompletion:^{
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://bsky.social/about/support"] options:@{} completionHandler:nil];
  }];
}

- (void)buildPanel {
  UIScrollView *scroll = [[UIScrollView alloc] init];
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.alwaysBounceVertical = YES;
  scroll.backgroundColor = NFBIPADashDrawerBackgroundColor();
  scroll.showsVerticalScrollIndicator = NO;
  self.scrollView = scroll;

  UIView *appearanceFooter = [self appearanceToggleFooter];

  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 0.0;

  [scroll addSubview:stack];
  [self.panelView addSubview:scroll];
  [self.panelView addSubview:appearanceFooter];
  UILayoutGuide *guide = self.panelView.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [scroll.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [scroll.leadingAnchor constraintEqualToAnchor:self.panelView.leadingAnchor],
    [scroll.trailingAnchor constraintEqualToAnchor:self.panelView.trailingAnchor],
    [scroll.bottomAnchor constraintEqualToAnchor:appearanceFooter.topAnchor],
    [appearanceFooter.leadingAnchor constraintEqualToAnchor:self.panelView.leadingAnchor],
    [appearanceFooter.trailingAnchor constraintEqualToAnchor:self.panelView.trailingAnchor],
    [appearanceFooter.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    [appearanceFooter.heightAnchor constraintEqualToConstant:64.0],
    [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
    [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
  ]];

  [stack addArrangedSubview:[self accountHeader]];
  [stack addArrangedSubview:[self menuRowWithTitle:@"Profile" iconName:@"nfb_profile" action:@selector(profileTapped)]];
  [stack addArrangedSubview:[self menuRowWithTitle:@"Not Twitter Blue" iconName:@"nfb_twitter_blue" action:@selector(notTwitterBlueTapped)]];
  [stack addArrangedSubview:[self menuRowWithTitle:@"Explore" iconName:@"nfb_search" action:@selector(searchTapped)]];
  [stack addArrangedSubview:[self menuRowWithTitle:@"Bookmarks" iconName:@"nfb_bookmark" action:@selector(bookmarksTapped)]];
  [stack addArrangedSubview:[self menuRowWithTitle:@"Lists" iconName:@"nfb_lists" action:@selector(listsTapped)]];
  [stack addArrangedSubview:[self menuRowWithTitle:@"Feeds" iconName:@"nfb_sparkle" action:@selector(feedsTapped)]];
  [stack addArrangedSubview:[self separatorWithTop:16.0 bottom:8.0]];
  [stack addArrangedSubview:[self disclosureRowWithTitle:@"Settings and Support"]];

  self.settingsRowsStack = [[UIStackView alloc] init];
  self.settingsRowsStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.settingsRowsStack.axis = UILayoutConstraintAxisVertical;
  self.settingsRowsStack.alignment = UIStackViewAlignmentFill;
  self.settingsRowsStack.spacing = 0.0;
  self.settingsRowsStack.hidden = YES;
  [self.settingsRowsStack addArrangedSubview:[self compactMenuRowWithTitle:@"Settings and privacy" iconName:@"nfb_settings" action:@selector(settingsTapped)]];
  [self.settingsRowsStack addArrangedSubview:[self compactMenuRowWithTitle:@"Help Center" iconName:@"nfb_info" action:@selector(helpTapped)]];
  [self.settingsRowsStack addArrangedSubview:[self compactMenuRowWithTitle:@"Sign out" iconName:@"nfb_close" action:@selector(signOutTapped)]];
  [stack addArrangedSubview:self.settingsRowsStack];
  [self refreshAppearanceToggleAnimated:NO];
}

- (UIView *)accountHeader {
  NSDictionary *account = [[NFBAtprotoSession sharedSession] currentAccountDictionary];
  NSArray<NSDictionary *> *savedAccounts = [[NFBAtprotoSession sharedSession] savedAccountDictionaries];

  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;

  self.avatarView = [[UIImageView alloc] initWithImage:NFBBrandIconImage() ?: NFBDefaultAvatarImage()];
  self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarView.clipsToBounds = YES;
  self.avatarView.layer.cornerRadius = 22.0;
  self.avatarView.userInteractionEnabled = YES;
  UITapGestureRecognizer *avatarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileTapped)];
  [self.avatarView addGestureRecognizer:avatarTap];

  UIView *accountAccessory = [self accountAccessoryViewForAccounts:savedAccounts currentDID:account[@"did"]];

  UILabel *name = [[UILabel alloc] init];
  name.translatesAutoresizingMaskIntoConstraints = NO;
  name.textColor = NFBIPADashDrawerPrimaryTextColor();
  name.font = NFBFont(20.0, NFBFontWeightHeavy);
  name.text = account[@"displayName"] ?: @"Not Twitter";
  name.lineBreakMode = NSLineBreakByTruncatingTail;
  name.userInteractionEnabled = YES;
  UITapGestureRecognizer *nameTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileTapped)];
  [name addGestureRecognizer:nameTap];

  UILabel *handle = [[UILabel alloc] init];
  handle.translatesAutoresizingMaskIntoConstraints = NO;
  handle.textColor = NFBIPADashDrawerSecondaryTextColor();
  handle.font = NFBFont(15.0, NFBFontWeightRegular);
  NSString *handleValue = [NFBAtprotoClient handleForProfile:account];
  handle.text = [@"@" stringByAppendingString:handleValue];
  handle.lineBreakMode = NSLineBreakByTruncatingTail;
  handle.userInteractionEnabled = YES;
  UITapGestureRecognizer *handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileTapped)];
  [handle addGestureRecognizer:handleTap];

  UILabel *counts = [[UILabel alloc] init];
  counts.translatesAutoresizingMaskIntoConstraints = NO;
  counts.textColor = NFBIPADashDrawerSecondaryTextColor();
  counts.font = NFBFont(15.0, NFBFontWeightRegular);
  self.countsLabel = counts;
  [self refreshCountsLabel];

  [container addSubview:self.avatarView];
  [container addSubview:accountAccessory];
  [container addSubview:name];
  [container addSubview:handle];
  [container addSubview:counts];

  [NSLayoutConstraint activateConstraints:@[
    [container.heightAnchor constraintGreaterThanOrEqualToConstant:146.0],
    [self.avatarView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20.0],
    [self.avatarView.topAnchor constraintEqualToAnchor:container.topAnchor constant:14.0],
    [self.avatarView.widthAnchor constraintEqualToConstant:44.0],
    [self.avatarView.heightAnchor constraintEqualToConstant:44.0],
    [accountAccessory.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20.0],
    [accountAccessory.centerYAnchor constraintEqualToAnchor:self.avatarView.centerYAnchor],
    [name.leadingAnchor constraintEqualToAnchor:self.avatarView.leadingAnchor],
    [name.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20.0],
    [name.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:12.0],
    [handle.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
    [handle.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
    [handle.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:1.0],
    [counts.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
    [counts.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
    [counts.topAnchor constraintEqualToAnchor:handle.bottomAnchor constant:14.0],
    [counts.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-18.0]
  ]];

  [self loadAvatarURL:account[@"avatar"]];
  return container;
}

- (UIView *)accountAccessoryViewForAccounts:(NSArray<NSDictionary *> *)accounts currentDID:(NSString *)currentDID {
  NSMutableArray<NSDictionary *> *otherAccounts = [NSMutableArray array];
  for (NSDictionary *account in accounts) {
    if (![account isKindOfClass:[NSDictionary class]]) continue;
    NSString *did = [account[@"did"] isKindOfClass:[NSString class]] ? account[@"did"] : @"";
    if (did.length == 0 || [did isEqualToString:currentDID ?: @""]) continue;
    [otherAccounts addObject:account];
  }
  self.previewAccounts = otherAccounts;

  if (otherAccounts.count == 0) {
    UIButton *addAccount = [UIButton buttonWithType:UIButtonTypeCustom];
    addAccount.translatesAutoresizingMaskIntoConstraints = NO;
    [addAccount setImage:NFBTemplateIcon(@"nfb_account_add") forState:UIControlStateNormal];
    addAccount.tintColor = NFBIPADashDrawerPrimaryTextColor();
    addAccount.imageView.contentMode = UIViewContentModeScaleAspectFit;
    addAccount.contentEdgeInsets = UIEdgeInsetsMake(5.0, 5.0, 5.0, 5.0);
    [addAccount addTarget:self action:@selector(accountSwitcherTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
      [addAccount.widthAnchor constraintEqualToConstant:36.0],
      [addAccount.heightAnchor constraintEqualToConstant:36.0]
    ]];
    return addAccount;
  }

  UIControl *preview = [[UIControl alloc] init];
  preview.translatesAutoresizingMaskIntoConstraints = NO;

  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisHorizontal;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.spacing = 8.0;
  stack.userInteractionEnabled = YES;
  [preview addSubview:stack];

  NSUInteger avatarCount = MIN(otherAccounts.count, (NSUInteger)2);
  for (NSUInteger index = 0; index < avatarCount; index++) {
    NSDictionary *account = otherAccounts[index];
    UIControl *avatarButton = [[UIControl alloc] init];
    avatarButton.translatesAutoresizingMaskIntoConstraints = NO;
    avatarButton.tag = (NSInteger)index;
    avatarButton.exclusiveTouch = YES;
    [avatarButton addTarget:self action:@selector(accountPreviewAvatarTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *avatar = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    avatar.layer.cornerRadius = 14.0;
    avatar.layer.borderWidth = 1.5;
    avatar.layer.borderColor = NFBIPADashDrawerBackgroundColor().CGColor;
    avatar.userInteractionEnabled = NO;
    [avatarButton addSubview:avatar];
    [stack addArrangedSubview:avatarButton];
    [NSLayoutConstraint activateConstraints:@[
      [avatarButton.widthAnchor constraintEqualToConstant:38.0],
      [avatarButton.heightAnchor constraintEqualToConstant:44.0],
      [avatar.centerXAnchor constraintEqualToAnchor:avatarButton.centerXAnchor],
      [avatar.centerYAnchor constraintEqualToAnchor:avatarButton.centerYAnchor],
      [avatar.widthAnchor constraintEqualToConstant:28.0],
      [avatar.heightAnchor constraintEqualToConstant:28.0]
    ]];
    [self loadAvatarURL:[NFBAtprotoClient avatarURLForProfile:account] intoImageView:avatar];
  }

  UIControl *moreButton = [[UIControl alloc] init];
  moreButton.translatesAutoresizingMaskIntoConstraints = NO;
  moreButton.exclusiveTouch = YES;
  [moreButton addTarget:self action:@selector(accountSwitcherTapped) forControlEvents:UIControlEventTouchUpInside];

  UIView *moreCircle = [[UIView alloc] init];
  moreCircle.translatesAutoresizingMaskIntoConstraints = NO;
  moreCircle.backgroundColor = NFBIPADashDrawerBackgroundColor();
  moreCircle.layer.cornerRadius = 15.0;
  moreCircle.layer.borderColor = [NFBIPADashDrawerSecondaryTextColor() colorWithAlphaComponent:0.65].CGColor;
  moreCircle.layer.borderWidth = 1.5;
  moreCircle.userInteractionEnabled = NO;

  UIImageView *moreIcon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_more")];
  moreIcon.translatesAutoresizingMaskIntoConstraints = NO;
  moreIcon.tintColor = NFBIPADashDrawerPrimaryTextColor();
  moreIcon.contentMode = UIViewContentModeScaleAspectFit;
  [moreCircle addSubview:moreIcon];

  UIView *dot = [[UIView alloc] init];
  dot.translatesAutoresizingMaskIntoConstraints = NO;
  dot.backgroundColor = NFBColorAccent();
  dot.layer.cornerRadius = 3.0;
  dot.hidden = otherAccounts.count <= 2;
  [moreCircle addSubview:dot];

  [moreButton addSubview:moreCircle];
  [stack addArrangedSubview:moreButton];
  [NSLayoutConstraint activateConstraints:@[
    [moreButton.widthAnchor constraintEqualToConstant:44.0],
    [moreButton.heightAnchor constraintEqualToConstant:44.0],
    [moreCircle.centerXAnchor constraintEqualToAnchor:moreButton.centerXAnchor],
    [moreCircle.centerYAnchor constraintEqualToAnchor:moreButton.centerYAnchor],
    [moreCircle.widthAnchor constraintEqualToConstant:30.0],
    [moreCircle.heightAnchor constraintEqualToConstant:30.0],
    [moreIcon.centerXAnchor constraintEqualToAnchor:moreCircle.centerXAnchor],
    [moreIcon.centerYAnchor constraintEqualToAnchor:moreCircle.centerYAnchor],
    [moreIcon.widthAnchor constraintEqualToConstant:18.0],
    [moreIcon.heightAnchor constraintEqualToConstant:18.0],
    [dot.trailingAnchor constraintEqualToAnchor:moreCircle.trailingAnchor constant:1.0],
    [dot.topAnchor constraintEqualToAnchor:moreCircle.topAnchor constant:-1.0],
    [dot.widthAnchor constraintEqualToConstant:6.0],
    [dot.heightAnchor constraintEqualToConstant:6.0],
    [stack.topAnchor constraintEqualToAnchor:preview.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor],
    [preview.heightAnchor constraintEqualToConstant:44.0],
    [preview.widthAnchor constraintEqualToConstant:(CGFloat)avatarCount * 38.0 + (CGFloat)avatarCount * 8.0 + 44.0]
  ]];

  return preview;
}

- (NSAttributedString *)countsTextFollowing:(NSNumber *)following followers:(NSNumber *)followers {
  NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
  NSDictionary *countAttrs = @{NSForegroundColorAttributeName: NFBIPADashDrawerPrimaryTextColor(), NSFontAttributeName: NFBFont(15.0, NFBFontWeightBold)};
  NSDictionary *labelAttrs = @{NSForegroundColorAttributeName: NFBIPADashDrawerSecondaryTextColor(), NSFontAttributeName: NFBFont(15.0, NFBFontWeightRegular)};
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:NFBShortCountString(following.integerValue) attributes:countAttrs]];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" Following   " attributes:labelAttrs]];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:NFBShortCountString(followers.integerValue) attributes:countAttrs]];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" Followers" attributes:labelAttrs]];
  return text;
}

- (void)refreshCountsLabel {
  if (!self.countsLabel) return;
  NSDictionary *profile = [NFBAtprotoSession sharedSession].profile ?: @{};
  NSNumber *following = [profile[@"followsCount"] respondsToSelector:@selector(stringValue)] ? profile[@"followsCount"] : @0;
  NSNumber *followers = [profile[@"followersCount"] respondsToSelector:@selector(stringValue)] ? profile[@"followersCount"] : @0;
  self.countsLabel.textColor = NFBIPADashDrawerPrimaryTextColor();
  self.countsLabel.attributedText = [self countsTextFollowing:following followers:followers];
}

- (UIView *)separatorWithTop:(CGFloat)top bottom:(CGFloat)bottom {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  UIView *line = [[UIView alloc] init];
  line.translatesAutoresizingMaskIntoConstraints = NO;
  line.backgroundColor = NFBIPADashDrawerSeparatorColor();
  [container addSubview:line];
  [NSLayoutConstraint activateConstraints:@[
    [container.heightAnchor constraintEqualToConstant:top + bottom + 1.0],
    [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [line.topAnchor constraintEqualToAnchor:container.topAnchor constant:top],
    [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  return container;
}

- (UIView *)menuRowWithTitle:(NSString *)title iconName:(NSString *)iconName action:(SEL)action {
  return [self rowWithTitle:title iconName:iconName fontSize:20.0 iconSize:24.0 height:56.0 leftInset:20.0 spacing:20.0 action:action];
}

- (UIView *)compactMenuRowWithTitle:(NSString *)title iconName:(NSString *)iconName action:(SEL)action {
  return [self rowWithTitle:title iconName:iconName fontSize:15.0 iconSize:20.0 height:48.0 leftInset:20.0 spacing:20.0 action:action];
}

- (UIView *)rowWithTitle:(NSString *)title iconName:(NSString *)iconName fontSize:(CGFloat)fontSize iconSize:(CGFloat)iconSize height:(CGFloat)height leftInset:(CGFloat)leftInset spacing:(CGFloat)spacing action:(SEL)action {
  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  if (action) [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.tintColor = NFBIPADashDrawerPrimaryTextColor();
  icon.contentMode = UIViewContentModeScaleAspectFit;

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = title;
  label.textColor = NFBIPADashDrawerPrimaryTextColor();
  label.font = NFBFont(fontSize, fontSize >= 20.0 ? NFBFontWeightBold : NFBFontWeightMedium);
  label.numberOfLines = 0;
  label.userInteractionEnabled = NO;
  row.isAccessibilityElement = YES;
  row.accessibilityLabel = title;
  row.accessibilityTraits = UIAccessibilityTraitButton;

  [row addSubview:icon];
  [row addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:height],
    [label.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:12.0],
    [label.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-12.0],
    [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:leftInset],
    [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [icon.widthAnchor constraintEqualToConstant:iconSize],
    [icon.heightAnchor constraintEqualToConstant:iconSize],
    [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:spacing],
    [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-24.0],
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
  ]];
  return row;
}

- (UIView *)disclosureRowWithTitle:(NSString *)title {
  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  [row addTarget:self action:@selector(toggleSettingsRows) forControlEvents:UIControlEventTouchUpInside];

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = title;
  label.textColor = NFBIPADashDrawerPrimaryTextColor();
  label.font = NFBFont(15.0, NFBFontWeightBold);

  self.settingsChevron = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_chevron_down")];
  self.settingsChevron.translatesAutoresizingMaskIntoConstraints = NO;
  self.settingsChevron.tintColor = NFBIPADashDrawerPrimaryTextColor();
  self.settingsChevron.contentMode = UIViewContentModeScaleAspectFit;

  [row addSubview:label];
  [row addSubview:self.settingsChevron];
  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:48.0],
    [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20.0],
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [label.trailingAnchor constraintLessThanOrEqualToAnchor:self.settingsChevron.leadingAnchor constant:-12.0],
    [self.settingsChevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20.0],
    [self.settingsChevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [self.settingsChevron.widthAnchor constraintEqualToConstant:18.0],
    [self.settingsChevron.heightAnchor constraintEqualToConstant:18.0]
  ]];
  return row;
}

- (UIView *)appearanceToggleFooter {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  container.backgroundColor = NFBIPADashDrawerBackgroundColor();
  self.appearanceFooterView = container;

  UIView *separator = [[UIView alloc] init];
  separator.translatesAutoresizingMaskIntoConstraints = NO;
  separator.backgroundColor = NFBIPADashDrawerSeparatorColor();
  self.appearanceFooterSeparator = separator;

  UIControl *toggle = [[UIControl alloc] init];
  toggle.translatesAutoresizingMaskIntoConstraints = NO;
  [toggle addTarget:self action:@selector(appearanceToggleTapped) forControlEvents:UIControlEventTouchUpInside];
  UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(appearanceToggleLongPressed:)];
  longPress.minimumPressDuration = 0.38;
  [toggle addGestureRecognizer:longPress];
  self.appearanceToggleControl = toggle;

  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_dark_mode_off")];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.contentMode = UIViewContentModeScaleAspectFit;
  icon.tintColor = NFBIPADashDrawerPrimaryTextColor();
  icon.userInteractionEnabled = NO;
  self.appearanceToggleIconView = icon;

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = @"Dark mode";
  label.textColor = NFBIPADashDrawerPrimaryTextColor();
  label.font = NFBFont(17.0, NFBFontWeightBold);
  label.adjustsFontSizeToFitWidth = YES;
  label.minimumScaleFactor = 0.78;
  label.userInteractionEnabled = NO;
  self.appearanceToggleLabel = label;

  [toggle addSubview:icon];
  [toggle addSubview:label];
  [container addSubview:separator];
  [container addSubview:toggle];

  [NSLayoutConstraint activateConstraints:@[
    [separator.topAnchor constraintEqualToAnchor:container.topAnchor],
    [separator.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [separator.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [toggle.topAnchor constraintEqualToAnchor:container.topAnchor],
    [toggle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [toggle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [toggle.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    [icon.leadingAnchor constraintEqualToAnchor:toggle.leadingAnchor constant:20.0],
    [icon.centerYAnchor constraintEqualToAnchor:toggle.centerYAnchor],
    [icon.widthAnchor constraintEqualToConstant:25.0],
    [icon.heightAnchor constraintEqualToConstant:25.0],
    [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:18.0],
    [label.trailingAnchor constraintEqualToAnchor:toggle.trailingAnchor constant:-24.0],
    [label.centerYAnchor constraintEqualToAnchor:toggle.centerYAnchor]
  ]];

  return container;
}

- (void)applyThemeToPanelSubview:(UIView *)view {
  if (view == self.panelView || view == self.scrollView || view == self.appearanceFooterView) {
    view.backgroundColor = NFBIPADashDrawerBackgroundColor();
  } else if (view == self.panelEdgeView || view == self.appearanceFooterSeparator) {
    view.backgroundColor = NFBIPADashDrawerSeparatorColor();
  } else if ([view isKindOfClass:UIImageView.class]) {
    ((UIImageView *)view).tintColor = NFBIPADashDrawerPrimaryTextColor();
  } else if ([view isKindOfClass:UILabel.class]) {
    if (view == self.countsLabel) {
      [self refreshCountsLabel];
      return;
    }
    UILabel *label = (UILabel *)view;
    NSString *text = label.text ?: @"";
    BOOL secondary = [text hasPrefix:@"@"];
    label.textColor = secondary ? NFBIPADashDrawerSecondaryTextColor() : NFBIPADashDrawerPrimaryTextColor();
  } else if ([view isKindOfClass:UIButton.class]) {
    ((UIButton *)view).tintColor = NFBIPADashDrawerPrimaryTextColor();
  }
  for (UIView *subview in view.subviews) [self applyThemeToPanelSubview:subview];
}

- (void)refreshAppearanceToggleAnimated:(BOOL)animated {
  void (^changes)(void) = ^{
    BOOL darkInterface = ![NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight];
    self.view.backgroundColor = NFBIPADashDrawerScrimColor();
    self.panelView.backgroundColor = NFBIPADashDrawerBackgroundColor();
    self.scrollView.backgroundColor = NFBIPADashDrawerBackgroundColor();
    self.panelEdgeView.backgroundColor = NFBIPADashDrawerSeparatorColor();
    self.appearanceFooterView.backgroundColor = NFBIPADashDrawerBackgroundColor();
    self.appearanceFooterSeparator.backgroundColor = NFBIPADashDrawerSeparatorColor();
    self.appearanceToggleIconView.image = NFBTemplateIcon(darkInterface ? @"nfb_dark_mode_off" : @"nfb_dark_mode_on");
    self.appearanceToggleIconView.tintColor = NFBIPADashDrawerPrimaryTextColor();
    self.appearanceToggleLabel.textColor = NFBIPADashDrawerPrimaryTextColor();
    [self applyThemeToPanelSubview:self.panelView];
    [self refreshCountsLabel];
  };
  if (animated) {
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
  } else {
    changes();
  }
}

- (void)refreshAppearanceToggle {
  [self refreshAppearanceToggleAnimated:NO];
}

- (void)appearanceToggleTapped {
  BOOL darkInterface = ![NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight];
  NFBSetDisplayMode(darkInterface ? NFBDisplayModeLight : NFBPreferredDarkDisplayMode());
  [self refreshAppearanceToggleAnimated:YES];
}

- (void)appearanceToggleLongPressed:(UILongPressGestureRecognizer *)recognizer {
  if (recognizer.state != UIGestureRecognizerStateBegan) return;
  [self displaySettingsShortcutTapped];
}

- (void)displaySettingsShortcutTapped {
  UIViewController *presenter = self.presentingViewController;
  if (!presenter) presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
  [UIView animateWithDuration:0.18 animations:^{
    self.view.alpha = 0.0;
    self.panelView.transform = CGAffineTransformMakeTranslation(-self.panelWidth, 0.0);
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:^{
      NFBSettingsViewController *settings = [[NFBSettingsViewController alloc] init];
      UIViewController *display = [[NFBSettingsDetailViewController alloc] initWithSectionID:@"display" title:@"Display"];
      UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
      nav.viewControllers = @[settings, display];
      NFBApplyNavigationAppearance(nav);
      nav.modalPresentationStyle = UIModalPresentationFullScreen;
      [presenter presentViewController:nav animated:YES completion:nil];
    }];
  }];
}

- (void)notTwitterBlueTapped {
  UIViewController *presenter = self.presentingViewController;
  if (!presenter) presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
  [UIView animateWithDuration:0.18 animations:^{
    self.view.alpha = 0.0;
    self.panelView.transform = CGAffineTransformMakeTranslation(-self.panelWidth, 0.0);
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:^{
      NFBSettingsViewController *settings = [[NFBSettingsViewController alloc] init];
      UIViewController *blue = [[NFBSettingsDetailViewController alloc] initWithSectionID:@"blue" title:@"Not Twitter Blue"];
      UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
      nav.viewControllers = @[settings, blue];
      NFBApplyNavigationAppearance(nav);
      nav.modalPresentationStyle = UIModalPresentationFullScreen;
      [presenter presentViewController:nav animated:YES completion:nil];
    }];
  }];
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  [self refreshAppearanceToggleAnimated:YES];
}

- (void)toggleSettingsRows {
  self.settingsExpanded = !self.settingsExpanded;
  [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
    self.settingsRowsStack.hidden = !self.settingsExpanded;
    self.settingsChevron.transform = self.settingsExpanded ? CGAffineTransformMakeRotation((CGFloat)M_PI) : CGAffineTransformIdentity;
    [self.panelView layoutIfNeeded];
  } completion:nil];
}

- (UITabBarController *)tabBarControllerFromController:(UIViewController *)controller {
  if (!controller) return nil;
  if ([controller isKindOfClass:UITabBarController.class]) return (UITabBarController *)controller;
  if (controller.tabBarController) return controller.tabBarController;
  if (controller.parentViewController) {
    UITabBarController *parentTabBar = [self tabBarControllerFromController:controller.parentViewController];
    if (parentTabBar) return parentTabBar;
  }
  if (controller.presentingViewController) {
    UITabBarController *presentingTabBar = [self tabBarControllerFromController:controller.presentingViewController];
    if (presentingTabBar) return presentingTabBar;
  }
  return nil;
}

- (BOOL)selectTabWithAccessibilityLabel:(NSString *)label {
  UIViewController *presenter = self.presentingViewController ?: UIApplication.sharedApplication.keyWindow.rootViewController;
  UITabBarController *tabBar = [self tabBarControllerFromController:presenter];
  if ([tabBar isKindOfClass:UITabBarController.class]) {
    for (UIViewController *controller in tabBar.viewControllers) {
      if ([controller.tabBarItem.accessibilityLabel isEqualToString:label]) {
        tabBar.selectedViewController = controller;
        return YES;
      }
    }
  }
  return NO;
}

- (UINavigationController *)selectedNavigationController {
  UIViewController *presenter = self.presentingViewController ?: UIApplication.sharedApplication.keyWindow.rootViewController;
  UITabBarController *tabBar = [self tabBarControllerFromController:presenter];
  UIViewController *selected = tabBar.selectedViewController ?: presenter;
  if ([selected isKindOfClass:UINavigationController.class]) return (UINavigationController *)selected;
  if (selected.navigationController) return selected.navigationController;
  if ([presenter isKindOfClass:UINavigationController.class]) return (UINavigationController *)presenter;
  return presenter.navigationController;
}

- (void)profileTapped {
  BOOL selectedExistingTab = [self selectTabWithAccessibilityLabel:@"Profile"];
  UINavigationController *nav = selectedExistingTab ? nil : [self selectedNavigationController];
  [self closeWithCompletion:^{
    if (selectedExistingTab) return;
    NFBTimelineViewController *profile = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:nil];
    if (nav) {
      [nav popToRootViewControllerAnimated:NO];
      [nav pushViewController:profile animated:YES];
    }
  }];
}

- (void)searchTapped {
  [self selectTabWithAccessibilityLabel:@"Explore"];
  [self close];
}

- (void)pushTimelineKind:(NFBTimelineKind)kind {
  UINavigationController *nav = [self selectedNavigationController];
  [self closeWithCompletion:^{
    if (!nav) return;
    NFBTimelineViewController *controller = [[NFBTimelineViewController alloc] initWithKind:kind actor:nil];
    [nav pushViewController:controller animated:YES];
  }];
}

- (void)bookmarksTapped {
  [self pushTimelineKind:NFBTimelineKindBookmarks];
}

- (void)listsTapped {
  [self pushTimelineKind:NFBTimelineKindLists];
}

- (void)feedsTapped {
  [self pushTimelineKind:NFBTimelineKindFeeds];
}

- (void)accountSwitcherTapped {
  UIWindow *baseWindow = self.view.window ?: UIApplication.sharedApplication.keyWindow;
  if (!baseWindow) return;
  CGRect windowFrame = UIScreen.mainScreen.bounds;
  if (@available(iOS 13.0, *)) {
    if (baseWindow.windowScene) windowFrame = baseWindow.windowScene.coordinateSpace.bounds;
  }

  NFBAccountSwitcherViewController *switcher = [[NFBAccountSwitcherViewController alloc] init];
  switcher.sideMenuPresentation = YES;
  switcher.preferredSheetWidth = CGRectGetWidth(windowFrame);
  __weak typeof(self) weakSelf = self;
  __weak NFBAccountSwitcherViewController *weakSwitcher = switcher;
  switcher.dismissalHandler = ^{
    NFBAccountSwitcherViewController *strongSwitcher = weakSwitcher;
    if (!strongSwitcher) return;
    __strong typeof(weakSelf) strongSelf = weakSelf;
    UIWindow *overlayWindow = strongSelf.activeAccountSwitcherWindow;
    overlayWindow.hidden = YES;
    overlayWindow.rootViewController = nil;
    [strongSelf.previousKeyWindow makeKeyWindow];
    if (strongSelf.activeAccountSwitcher == strongSwitcher) {
      strongSelf.activeAccountSwitcher = nil;
    }
    strongSelf.activeAccountSwitcherWindow = nil;
    strongSelf.previousKeyWindow = nil;
  };
  switcher.prepareForAccountSwitch = ^(dispatch_block_t switchAccount) {
    [weakSelf closeWithCompletion:switchAccount];
  };
  switcher.actionCompletionHandler = ^{
    [weakSelf close];
  };
  switcher.addAccountHandler = ^{
    [weakSelf closeWithCompletion:^{
      NFBPresentBlueskyAddAccount();
    }];
  };
  switcher.signOutHandler = ^{
    BOOL hasSession = [[NFBAtprotoSession sharedSession] hasSession];
    [weakSelf closeWithCompletion:^{
      if (!hasSession) NFBPresentBlueskyLoginIfNeeded();
    }];
  };

  self.activeAccountSwitcher = switcher;
  self.previousKeyWindow = baseWindow;

  UIWindow *overlayWindow = nil;
  if (@available(iOS 13.0, *)) {
    if (baseWindow.windowScene) {
      overlayWindow = [[UIWindow alloc] initWithWindowScene:baseWindow.windowScene];
    }
  }
  if (!overlayWindow) {
    overlayWindow = [[UIWindow alloc] initWithFrame:windowFrame];
  }
  overlayWindow.frame = windowFrame;
  overlayWindow.backgroundColor = UIColor.clearColor;
  overlayWindow.windowLevel = baseWindow.windowLevel + 1.0;
  overlayWindow.rootViewController = switcher;
  self.activeAccountSwitcherWindow = overlayWindow;
  [overlayWindow makeKeyAndVisible];
}

- (void)accountPreviewAvatarTapped:(UIControl *)sender {
  if (sender.tag < 0 || (NSUInteger)sender.tag >= self.previewAccounts.count) {
    [self accountSwitcherTapped];
    return;
  }
  NSDictionary *account = self.previewAccounts[(NSUInteger)sender.tag];
  NSString *did = [account[@"did"] isKindOfClass:NSString.class] ? account[@"did"] : @"";
  if (did.length == 0) {
    [self accountSwitcherTapped];
    return;
  }
  if (![[NFBAtprotoSession sharedSession] canSwitchToAccountWithDID:did]) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't switch accounts" message:@"This account needs to be added again before it can be used." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return;
  }
  UIViewController *presenter = self.presentingViewController;
  [self closeWithCompletion:^{
    if ([[NFBAtprotoSession sharedSession] switchToAccountWithDID:did]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't switch accounts" message:@"This account needs to be added again before it can be used." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
  }];
}

- (void)signOutTapped {
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    [self closeWithCompletion:^{
      NFBPresentBlueskyLoginIfNeeded();
    }];
    return;
  }

  __weak typeof(self) weakSelf = self;
  [self confirmSignOutCurrentAccountWithCompletion:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [[NFBNotificationCoordinator sharedCoordinator] unregisterRemoteNotificationsForCurrentAccountWithCompletion:^{
      [[NFBAtprotoSession sharedSession] signOut];
      BOOL hasSession = [[NFBAtprotoSession sharedSession] hasSession];
      [strongSelf closeWithCompletion:^{
        if (!hasSession) NFBPresentBlueskyLoginIfNeeded();
      }];
    }];
  }];
}

- (void)confirmSignOutCurrentAccountWithCompletion:(dispatch_block_t)completion {
  NSDictionary *account = [[NFBAtprotoSession sharedSession] currentAccountDictionary];
  NSString *handle = [NFBAtprotoClient handleForProfile:account];
  if (![handle isKindOfClass:[NSString class]] || handle.length == 0) handle = account[@"did"];
  NSString *promptHandle = handle.length > 0 ? [@"@" stringByAppendingString:handle] : @"this account";
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Log out of %@?", promptHandle]
                                                                 message:@"You can add this account again later."
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
  [alert addAction:[UIAlertAction actionWithTitle:@"Log out" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
    (void)action;
    if (completion) completion();
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  UIPopoverPresentationController *popover = alert.popoverPresentationController;
  if (popover) {
    popover.sourceView = self.panelView ?: self.view;
    popover.sourceRect = (self.panelView ?: self.view).bounds;
    popover.permittedArrowDirections = 0;
  }
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)settingsTapped {
  UIViewController *presenter = self.presentingViewController;
  if (!presenter) presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
  [UIView animateWithDuration:0.18 animations:^{
    self.view.alpha = 0.0;
    self.panelView.transform = CGAffineTransformMakeTranslation(-self.panelWidth, 0.0);
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:^{
      NFBSettingsViewController *settings = [[NFBSettingsViewController alloc] init];
      UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
      NFBApplyNavigationAppearance(nav);
      nav.modalPresentationStyle = UIModalPresentationFullScreen;
      [presenter presentViewController:nav animated:YES completion:nil];
    }];
  }];
}

- (void)loadAvatarURL:(NSString *)urlString {
  NFBLoadAccountAvatar(self.avatarView, urlString);
}

- (void)loadAvatarURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
  NFBLoadAccountAvatar(imageView, urlString);
}

@end
