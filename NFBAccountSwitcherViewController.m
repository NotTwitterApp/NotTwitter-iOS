#import "NFBAccountSwitcherViewController.h"

#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"
#import "NFBAccountAvatar.h"
#import "NFBBlueskyLoginViewController.h"
#import "NFBNotificationCoordinator.h"
#import "NFBTheme.h"

@interface NFBAccountSwitcherViewController ()

@property (nonatomic, strong) UIButton *backdropButton;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, copy) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, strong) NSLayoutConstraint *sheetHeightConstraint;
@property (nonatomic, strong) NSMutableArray<UIView *> *statusViews;
@property (nonatomic, strong) NSMutableArray<UIButton *> *deleteButtons;
@property (nonatomic, assign, getter=isEditingAccounts) BOOL editingAccounts;
@property (nonatomic, assign, getter=isExpanded) BOOL expanded;
@property (nonatomic, assign, getter=isSwitchingAccounts) BOOL switchingAccounts;
@property (nonatomic, assign) BOOL sheetPanActive;
@property (nonatomic, assign) CGFloat panStartSheetHeight;
@property (nonatomic, assign) CGFloat panStartTranslationY;

@end

@implementation NFBAccountSwitcherViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.accounts = [[NFBAtprotoSession sharedSession] savedAccountDictionaries];
  self.view.backgroundColor = UIColor.clearColor;

  self.backdropButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.backdropButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.backdropButton.backgroundColor = NFBIPAModalSheetScrimColor();
  self.backdropButton.alpha = 0.0;
  [self.backdropButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.backdropButton];

  self.sheetView = [[UIView alloc] init];
  self.sheetView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetAppearance(self.sheetView);
  [self.view addSubview:self.sheetView];
  UIPanGestureRecognizer *sheetPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSheetPan:)];
  sheetPan.cancelsTouchesInView = NO;
  [self.sheetView addGestureRecognizer:sheetPan];

  UIView *grabberRow = [[UIView alloc] init];
  grabberRow.translatesAutoresizingMaskIntoConstraints = NO;

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetGrabberAppearance(grabber);
  [grabberRow addSubview:grabber];
  [NSLayoutConstraint activateConstraints:@[
    [grabberRow.heightAnchor constraintEqualToConstant:18.0],
    [grabber.topAnchor constraintEqualToAnchor:grabberRow.topAnchor constant:6.0],
    [grabber.centerXAnchor constraintEqualToAnchor:grabberRow.centerXAnchor],
    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0]
  ]];

  UIButton *editButton = [UIButton buttonWithType:UIButtonTypeSystem];
  editButton.translatesAutoresizingMaskIntoConstraints = NO;
  [editButton setTitle:@"Edit" forState:UIControlStateNormal];
  [editButton setTitleColor:NFBColorText() forState:UIControlStateNormal];
  editButton.titleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  editButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
  [editButton addTarget:self action:@selector(editTapped) forControlEvents:UIControlEventTouchUpInside];
  self.editButton = editButton;

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = @"Accounts";
  titleLabel.textColor = NFBColorText();
  titleLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentCenter;

  UIView *titleRow = [[UIView alloc] init];
  titleRow.translatesAutoresizingMaskIntoConstraints = NO;
  [titleRow addSubview:editButton];
  [titleRow addSubview:titleLabel];
  [NSLayoutConstraint activateConstraints:@[
    [titleRow.heightAnchor constraintEqualToConstant:40.0],
    [editButton.leadingAnchor constraintEqualToAnchor:titleRow.leadingAnchor constant:16.0],
    [editButton.centerYAnchor constraintEqualToAnchor:titleRow.centerYAnchor],
    [editButton.widthAnchor constraintEqualToConstant:84.0],
    [editButton.heightAnchor constraintEqualToAnchor:titleRow.heightAnchor],
    [titleLabel.centerXAnchor constraintEqualToAnchor:titleRow.centerXAnchor],
    [titleLabel.centerYAnchor constraintEqualToAnchor:titleRow.centerYAnchor],
    [titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:editButton.trailingAnchor constant:8.0],
    [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:titleRow.trailingAnchor constant:-16.0]
  ]];

  self.statusViews = [NSMutableArray array];
  self.deleteButtons = [NSMutableArray array];
  NSMutableArray<UIView *> *rows = [NSMutableArray arrayWithObjects:grabberRow, titleRow, nil];
  for (NSUInteger index = 0; index < self.accounts.count; index++) {
    [rows addObject:[self accountRowForAccount:self.accounts[index] index:index]];
  }
  [rows addObject:[self addAccountLinkRow]];

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 0.0;
  [stack setCustomSpacing:0.0 afterView:grabberRow];
  [stack setCustomSpacing:2.0 afterView:titleRow];
  self.contentStack = stack;
  [self.sheetView addSubview:stack];

  self.sheetHeightConstraint = [self.sheetView.heightAnchor constraintEqualToConstant:[self compactSheetHeightForBounds:UIScreen.mainScreen.bounds safeAreaInsets:UIEdgeInsetsZero]];
  self.sheetHeightConstraint.priority = UILayoutPriorityRequired;
  NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
    [self.backdropButton.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.backdropButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.backdropButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.backdropButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

    [self.sheetView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.sheetView.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
    self.sheetHeightConstraint,

    [stack.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor],
    [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0]
  ]];
  [NSLayoutConstraint activateConstraints:constraints];

  self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, 420.0);
  [UIView animateWithDuration:0.38
                        delay:0.0
       usingSpringWithDamping:0.88
        initialSpringVelocity:0.62
                      options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                   animations:^{
    self.backdropButton.alpha = 1.0;
    self.sheetView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  if (self.sheetPanActive) return;
  self.sheetHeightConstraint.constant = self.isExpanded ? [self expandedSheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets] : [self compactSheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets];
}

- (CGFloat)compactSheetHeightForBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
  NSUInteger accountCount = self.accounts.count;
  CGFloat bottomPadding = MAX(14.0, safeAreaInsets.bottom + 8.0);
  CGFloat contentHeight = 18.0 + 40.0 + 2.0 + ((CGFloat)accountCount * 56.0) + 48.0 + bottomPadding;
  return ceil(MIN(contentHeight, [self expandedSheetHeightForBounds:bounds safeAreaInsets:safeAreaInsets]));
}

- (CGFloat)expandedSheetHeightForBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
  CGFloat height = CGRectGetHeight(bounds);
  if (height <= 0.0) height = CGRectGetHeight(UIScreen.mainScreen.bounds);
  CGFloat availableHeight = height - safeAreaInsets.top - 8.0;
  return ceil(MAX(0.0, availableHeight));
}

- (UIView *)separatorRow {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  UIView *line = [[UIView alloc] init];
  line.translatesAutoresizingMaskIntoConstraints = NO;
  line.backgroundColor = NFBColorBorder();
  [container addSubview:line];
  [NSLayoutConstraint activateConstraints:@[
    [container.heightAnchor constraintEqualToConstant:17.0],
    [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [line.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  return container;
}

- (UIControl *)accountRowForAccount:(NSDictionary *)account index:(NSUInteger)index {
  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.tag = (NSInteger)index;
  row.exclusiveTouch = YES;
  row.accessibilityTraits = UIAccessibilityTraitButton;
  [row addTarget:self action:@selector(accountTapped:) forControlEvents:UIControlEventTouchUpInside];

  UIImageView *avatar = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
  avatar.translatesAutoresizingMaskIntoConstraints = NO;
  avatar.contentMode = UIViewContentModeScaleAspectFill;
  avatar.clipsToBounds = YES;
  avatar.layer.cornerRadius = 18.0;

  UILabel *nameLabel = [[UILabel alloc] init];
  nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
  nameLabel.textColor = NFBColorText();
  nameLabel.font = NFBFont(15.0, NFBFontWeightHeavy);
  nameLabel.text = [NFBAtprotoClient displayNameForProfile:account];
  nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UILabel *handleLabel = [[UILabel alloc] init];
  handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  handleLabel.textColor = NFBColorSecondaryText();
  handleLabel.font = NFBFont(14.0, NFBFontWeightRegular);
  handleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:account]];
  handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIView *status = [self statusBubbleForAccount:account];
  UIView *actionSlot = [[UIView alloc] init];
  actionSlot.translatesAutoresizingMaskIntoConstraints = NO;

  UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
  deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
  deleteButton.tag = (NSInteger)index;
  deleteButton.backgroundColor = [UIColor systemRedColor];
  deleteButton.layer.cornerRadius = 10.0;
  deleteButton.hidden = !self.isEditingAccounts;
  [deleteButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  deleteButton.tintColor = UIColor.whiteColor;
  deleteButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
  deleteButton.contentEdgeInsets = UIEdgeInsetsMake(5.0, 5.0, 5.0, 5.0);
  [deleteButton addTarget:self action:@selector(deleteAccountTapped:) forControlEvents:UIControlEventTouchUpInside];

  status.hidden = self.isEditingAccounts;
  [actionSlot addSubview:status];
  [actionSlot addSubview:deleteButton];
  [self.statusViews addObject:status];
  [self.deleteButtons addObject:deleteButton];

  UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, handleLabel]];
  textStack.translatesAutoresizingMaskIntoConstraints = NO;
  textStack.axis = UILayoutConstraintAxisVertical;
  textStack.alignment = UIStackViewAlignmentFill;
  textStack.spacing = 1.0;

  [row addSubview:avatar];
  [row addSubview:textStack];
  [row addSubview:actionSlot];
  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:56.0],
    [avatar.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
    [avatar.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [avatar.widthAnchor constraintEqualToConstant:36.0],
    [avatar.heightAnchor constraintEqualToConstant:36.0],
    [textStack.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:12.0],
    [textStack.trailingAnchor constraintEqualToAnchor:actionSlot.leadingAnchor constant:-12.0],
    [textStack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [actionSlot.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16.0],
    [actionSlot.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [actionSlot.widthAnchor constraintEqualToConstant:24.0],
    [actionSlot.heightAnchor constraintEqualToConstant:24.0],
    [status.centerXAnchor constraintEqualToAnchor:actionSlot.centerXAnchor],
    [status.centerYAnchor constraintEqualToAnchor:actionSlot.centerYAnchor],
    [status.widthAnchor constraintEqualToConstant:22.0],
    [status.heightAnchor constraintEqualToConstant:22.0],
    [deleteButton.centerXAnchor constraintEqualToAnchor:actionSlot.centerXAnchor],
    [deleteButton.centerYAnchor constraintEqualToAnchor:actionSlot.centerYAnchor],
    [deleteButton.widthAnchor constraintEqualToConstant:20.0],
    [deleteButton.heightAnchor constraintEqualToConstant:20.0]
  ]];

  [self loadAvatarURL:[NFBAtprotoClient avatarURLForProfile:account] intoImageView:avatar];
  return row;
}

- (UIView *)statusBubbleForAccount:(NSDictionary *)account {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  if (![account[@"active"] boolValue]) return container;

  UIView *bubble = [[UIView alloc] init];
  bubble.translatesAutoresizingMaskIntoConstraints = NO;
  bubble.backgroundColor = NFBColorAccent();
  bubble.layer.cornerRadius = 10.0;
  [container addSubview:bubble];

  UIImageView *check = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_check")];
  check.translatesAutoresizingMaskIntoConstraints = NO;
  check.tintColor = UIColor.whiteColor;
  check.contentMode = UIViewContentModeScaleAspectFit;
  [bubble addSubview:check];

  [NSLayoutConstraint activateConstraints:@[
    [bubble.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
    [bubble.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    [bubble.widthAnchor constraintEqualToConstant:20.0],
    [bubble.heightAnchor constraintEqualToConstant:20.0],
    [check.centerXAnchor constraintEqualToAnchor:bubble.centerXAnchor],
    [check.centerYAnchor constraintEqualToAnchor:bubble.centerYAnchor],
    [check.widthAnchor constraintEqualToConstant:12.0],
    [check.heightAnchor constraintEqualToConstant:12.0]
  ]];
  return container;
}

- (UIControl *)addAccountLinkRow {
  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.exclusiveTouch = YES;
  row.accessibilityTraits = UIAccessibilityTraitButton;
  [row addTarget:self action:@selector(addAccountTapped) forControlEvents:UIControlEventTouchUpInside];

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = @"Add an account";
  label.textColor = NFBColorAccent();
  label.font = NFBFont(15.0, NFBFontWeightRegular);
  [row addSubview:label];

  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:48.0],
    [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
    [label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-16.0],
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
  ]];
  return row;
}

- (UIControl *)iconRowWithIconName:(NSString *)iconName title:(NSString *)title action:(SEL)action destructive:(BOOL)destructive {
  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.tintColor = destructive ? UIColor.systemRedColor : NFBColorText();
  icon.contentMode = UIViewContentModeScaleAspectFit;

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = title;
  label.textColor = destructive ? UIColor.systemRedColor : NFBColorText();
  label.font = NFBFont(18.0, NFBFontWeightHeavy);
  label.adjustsFontSizeToFitWidth = YES;
  label.minimumScaleFactor = 0.76;

  [row addSubview:icon];
  [row addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:NFBIPAModalSheetRowHeight()],
    [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:24.0],
    [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [icon.widthAnchor constraintEqualToConstant:26.0],
    [icon.heightAnchor constraintEqualToConstant:26.0],
    [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:22.0],
    [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-24.0],
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
  ]];
  return row;
}

- (void)editTapped {
  self.editingAccounts = !self.isEditingAccounts;
  [self.editButton setTitle:(self.isEditingAccounts ? @"Done" : @"Edit") forState:UIControlStateNormal];
  [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:^{
    for (UIView *status in self.statusViews) status.hidden = self.isEditingAccounts;
    for (UIButton *button in self.deleteButtons) button.hidden = !self.isEditingAccounts;
  } completion:nil];
}

- (void)deleteAccountTapped:(UIButton *)sender {
  if (sender.tag < 0 || (NSUInteger)sender.tag >= self.accounts.count) return;
  NSDictionary *account = self.accounts[(NSUInteger)sender.tag];
  NSString *did = [account[@"did"] isKindOfClass:[NSString class]] ? account[@"did"] : @"";
  if (did.length == 0) return;

  BOOL wasActive = [account[@"active"] boolValue];
  __weak typeof(self) weakSelf = self;
  [self confirmRemovalOfAccount:account completion:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if (wasActive) {
      [[NFBNotificationCoordinator sharedCoordinator] unregisterRemoteNotificationsForCurrentAccountWithCompletion:^{
        [strongSelf removeConfirmedAccountWithDID:did wasActive:wasActive];
      }];
      return;
    }
    [strongSelf removeConfirmedAccountWithDID:did wasActive:wasActive];
  }];
}

- (void)removeConfirmedAccountWithDID:(NSString *)did wasActive:(BOOL)wasActive {
  BOOL removed = [[NFBAtprotoSession sharedSession] removeAccountWithDID:did];
  self.accounts = [[NFBAtprotoSession sharedSession] savedAccountDictionaries];
  if (!removed) {
    [self rebuildAccountRows];
    [self presentAccountErrorWithTitle:@"Couldn't log out" message:@"That account is no longer saved on this device."];
    return;
  }

  if (self.accounts.count == 0) {
    dispatch_block_t signOutHandler = self.signOutHandler;
    dispatch_block_t completionHandler = self.actionCompletionHandler;
    [self dismissThenRun:^{
      if (signOutHandler) {
        signOutHandler();
      } else {
        NFBPresentBlueskyLoginIfNeeded();
        if (completionHandler) completionHandler();
      }
    }];
    return;
  }

  if (wasActive) {
    dispatch_block_t completionHandler = self.actionCompletionHandler;
    [self dismissThenRun:completionHandler];
    return;
  }

  [self rebuildAccountRows];
  self.sheetHeightConstraint.constant = self.isExpanded ? [self expandedSheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets] : [self compactSheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets];
  [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:^{
    [self.view layoutIfNeeded];
  } completion:nil];
}

- (void)rebuildAccountRows {
  NSArray<UIView *> *existing = [self.contentStack.arrangedSubviews copy];
  for (NSUInteger index = 2; index < existing.count; index++) {
    UIView *view = existing[index];
    [self.contentStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  self.statusViews = [NSMutableArray array];
  self.deleteButtons = [NSMutableArray array];
  for (NSUInteger index = 0; index < self.accounts.count; index++) {
    [self.contentStack addArrangedSubview:[self accountRowForAccount:self.accounts[index] index:index]];
  }
  [self.contentStack addArrangedSubview:[self addAccountLinkRow]];
  [self.editButton setTitle:(self.isEditingAccounts ? @"Done" : @"Edit") forState:UIControlStateNormal];
}

- (void)accountTapped:(UIControl *)sender {
  if (self.isSwitchingAccounts) return;
  if (self.isEditingAccounts) return;
  if (sender.tag < 0 || (NSUInteger)sender.tag >= self.accounts.count) return;
  NSDictionary *account = self.accounts[(NSUInteger)sender.tag];
  NSString *did = [account[@"did"] isKindOfClass:[NSString class]] ? account[@"did"] : @"";
  if ([account[@"active"] boolValue]) {
    [self dismissThenRun:nil];
    return;
  }
  if (did.length == 0) {
    [self presentAccountErrorWithTitle:@"Couldn't switch accounts" message:@"This saved account is missing its Bluesky identifier."];
    return;
  }

  if (![[NFBAtprotoSession sharedSession] canSwitchToAccountWithDID:did]) {
    self.accounts = [[NFBAtprotoSession sharedSession] savedAccountDictionaries];
    [self rebuildAccountRows];
    [self presentAccountErrorWithTitle:@"Couldn't switch accounts" message:@"This account needs to be added again before it can be used."];
    return;
  }

  self.switchingAccounts = YES;
  self.contentStack.userInteractionEnabled = NO;
  if (@available(iOS 10.0, *)) {
    UISelectionFeedbackGenerator *feedback = [[UISelectionFeedbackGenerator alloc] init];
    [feedback selectionChanged];
  }
  dispatch_block_t completionHandler = self.actionCompletionHandler;
  void (^prepare)(dispatch_block_t) = self.prepareForAccountSwitch;
  UIViewController *presenter = self.presentingViewController;
  dispatch_block_t switchAccount = ^{
    if ([[NFBAtprotoSession sharedSession] switchToAccountWithDID:did]) {
      if (completionHandler) completionHandler();
    } else {
      UIViewController *target = presenter ?: UIApplication.sharedApplication.keyWindow.rootViewController;
      UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't switch accounts" message:@"This account needs to be added again before it can be used." preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
      [target presentViewController:alert animated:YES completion:nil];
    }
  };
  // The reference dismisses the account sheet/drawer before swapping screens.
  [self dismissThenRun:^{
    if (prepare) prepare(switchAccount);
    else switchAccount();
  }];
}

- (void)addAccountTapped {
  dispatch_block_t addHandler = self.addAccountHandler;
  [self dismissThenRun:^{
    if (addHandler) {
      addHandler();
    } else {
      NFBPresentBlueskyAddAccount();
    }
  }];
}

- (void)signOutTapped {
  dispatch_block_t signOutHandler = self.signOutHandler;
  dispatch_block_t completionHandler = self.actionCompletionHandler;
  NSDictionary *account = [[NFBAtprotoSession sharedSession] currentAccountDictionary];
  __weak typeof(self) weakSelf = self;
  [self confirmRemovalOfAccount:account completion:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [[NFBNotificationCoordinator sharedCoordinator] unregisterRemoteNotificationsForCurrentAccountWithCompletion:^{
      [[NFBAtprotoSession sharedSession] signOut];
      [strongSelf dismissThenRun:^{
        if (signOutHandler) {
          signOutHandler();
        } else {
          if (![[NFBAtprotoSession sharedSession] hasSession]) NFBPresentBlueskyLoginIfNeeded();
          if (completionHandler) completionHandler();
        }
      }];
    }];
  }];
}

- (NSString *)promptHandleForAccount:(NSDictionary *)account {
  NSString *handle = [NFBAtprotoClient handleForProfile:account];
  if (![handle isKindOfClass:[NSString class]] || handle.length == 0) {
    handle = [account[@"did"] isKindOfClass:[NSString class]] ? account[@"did"] : @"";
  }
  return handle.length > 0 ? [@"@" stringByAppendingString:handle] : @"this account";
}

- (void)confirmRemovalOfAccount:(NSDictionary *)account completion:(dispatch_block_t)completion {
  NSString *handle = [self promptHandleForAccount:account];
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Log out of %@?", handle]
                                                                 message:@"You can add this account again later."
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
  [alert addAction:[UIAlertAction actionWithTitle:@"Log out" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
    (void)action;
    if (completion) completion();
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  UIPopoverPresentationController *popover = alert.popoverPresentationController;
  if (popover) {
    popover.sourceView = self.sheetView ?: self.view;
    popover.sourceRect = (self.sheetView ?: self.view).bounds;
    popover.permittedArrowDirections = 0;
  }
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentAccountErrorWithTitle:(NSString *)title message:(NSString *)message {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)cancelTapped {
  [self dismissThenRun:nil];
}

- (void)dismissThenRun:(dispatch_block_t)handler {
  if (self.dismissing) return;
  self.dismissing = YES;
  CGFloat distance = MAX(420.0, CGRectGetHeight(self.sheetView.bounds) + 80.0);
  [UIView animateWithDuration:0.23 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseIn animations:^{
    self.backdropButton.alpha = 0.0;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, distance);
  } completion:^(BOOL finished) {
    (void)finished;
    if (self.dismissalHandler) {
      self.dismissalHandler();
      if (handler) handler();
    } else {
      [self dismissViewControllerAnimated:NO completion:handler];
    }
  }];
}

- (void)handleSheetPan:(UIPanGestureRecognizer *)recognizer {
  if (self.dismissing) return;
  CGPoint translation = [recognizer translationInView:self.view];
  CGPoint velocity = [recognizer velocityInView:self.view];
  CGFloat compactHeight = [self compactSheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets];
  CGFloat expandedHeight = [self expandedSheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets];

  if (recognizer.state == UIGestureRecognizerStateBegan) {
    self.sheetPanActive = YES;
    self.panStartSheetHeight = self.sheetHeightConstraint.constant;
    self.panStartTranslationY = translation.y;
    return;
  }

  CGFloat deltaY = translation.y - self.panStartTranslationY;

  if (recognizer.state == UIGestureRecognizerStateChanged) {
    CGFloat proposedHeight = self.panStartSheetHeight - deltaY;
    if (proposedHeight > compactHeight || self.isExpanded) {
      self.sheetView.transform = CGAffineTransformIdentity;
      self.sheetHeightConstraint.constant = MIN(expandedHeight, MAX(compactHeight, proposedHeight));
      CGFloat progress = (self.sheetHeightConstraint.constant - compactHeight) / MAX(1.0, expandedHeight - compactHeight);
      self.backdropButton.alpha = MIN(1.0, 1.0 + (0.14 * progress));
      [self.view layoutIfNeeded];
      return;
    }

    CGFloat y = MAX(0.0, deltaY);
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, y);
    self.backdropButton.alpha = MAX(0.0, 1.0 - MIN(1.0, y / 260.0));
    return;
  }

  if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
    self.sheetPanActive = NO;
    if (recognizer.state == UIGestureRecognizerStateCancelled) {
      [self setExpanded:self.isExpanded animated:YES];
      return;
    }
    if (self.sheetHeightConstraint.constant > compactHeight + 1.0 || self.isExpanded) {
      CGFloat midpoint = compactHeight + ((expandedHeight - compactHeight) * 0.42);
      BOOL shouldExpand = velocity.y < -450.0 || (velocity.y < 450.0 && self.sheetHeightConstraint.constant >= midpoint);
      [self setExpanded:shouldExpand animated:YES];
      return;
    }

    CGFloat y = MAX(0.0, deltaY);
    if (y > 84.0 || velocity.y > 850.0) {
      [self dismissThenRun:nil];
      return;
    }

    [UIView animateWithDuration:0.32
                          delay:0.0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.55
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{
      self.backdropButton.alpha = 1.0;
      self.sheetView.transform = CGAffineTransformIdentity;
    } completion:nil];
  }
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
  _expanded = expanded;
  CGFloat targetHeight = expanded ? [self expandedSheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets] : [self compactSheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets];
  void (^animations)(void) = ^{
    self.sheetView.transform = CGAffineTransformIdentity;
    self.sheetHeightConstraint.constant = targetHeight;
    self.backdropButton.alpha = expanded ? 1.0 : 1.0;
    [self.view layoutIfNeeded];
  };
  if (!animated) {
    animations();
    return;
  }
  [UIView animateWithDuration:0.34
                        delay:0.0
       usingSpringWithDamping:0.88
        initialSpringVelocity:0.58
                      options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                   animations:animations
                   completion:nil];
}

- (void)loadAvatarURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
  NFBLoadAccountAvatar(imageView, urlString);
}

@end
