#import "NFBInteractiveSheet.h"
#import "NFBNotificationCoordinator.h"

#import <UserNotifications/UserNotifications.h>

#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"
#import "NFBBlueskyLoginViewController.h"
#import "NFBTheme.h"

NSString * const NFBNotificationCountsDidChangeNotification = @"NFBNotificationCountsDidChangeNotification";
NSString * const NFBActivityNotificationPreferencesDidChangeNotification = @"NFBActivityNotificationPreferencesDidChangeNotification";
NSString * const NFBActivityNotificationCategoryAll = @"all";
NSString * const NFBActivityNotificationCategoryTweets = @"tweets";
NSString * const NFBActivityNotificationCategoryArticles = @"articles";
NSString * const NFBActivityNotificationCategoryRetweets = @"retweets";
NSString * const NFBActivityNotificationCategoryReplies = @"replies";

static NSTimeInterval const NFBNotificationRefreshInterval = 60.0;
static NSString * const NFBRemotePushTokenDefaultsKey = @"nfb_remote_push_token";
static NSString * const NFBRemotePushRegisteredDIDDefaultsKey = @"nfb_remote_push_registered_did";
static NSString * const NFBRemotePushRegisteredTokenDefaultsKey = @"nfb_remote_push_registered_token";
static NSString * const NFBRemotePushRegisteredAppIDDefaultsKey = @"nfb_remote_push_registered_app_id";
static NSString * const NFBActivityNotificationCategoriesDefaultsKey = @"nfb_activity_notification_categories_by_did";
static NSString * const NFBMutedConversationURIsDefaultsKey = @"nfb_muted_conversation_uris";
static NSString * const NFBRemotePushFallbackAppID = @"com.nottwitter.atproto";

static NSString *NFBHexStringForDeviceToken(NSData *deviceToken) {
  if (deviceToken.length == 0) return @"";
  const unsigned char *bytes = deviceToken.bytes;
  NSMutableString *token = [NSMutableString stringWithCapacity:deviceToken.length * 2];
  for (NSUInteger index = 0; index < deviceToken.length; index++) {
    [token appendFormat:@"%02x", bytes[index]];
  }
  return [token copy];
}

static NSString *NFBNotificationStringValue(id value) {
  return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *NFBRemotePushAppID(void) {
  NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
  return bundleID.length > 0 ? bundleID : NFBRemotePushFallbackAppID;
}

static NSDictionary *NFBNotificationDictionaryValue(id value) {
  return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray<NSString *> *NFBActivityNotificationIndividualCategories(void) {
  return @[NFBActivityNotificationCategoryTweets, NFBActivityNotificationCategoryArticles, NFBActivityNotificationCategoryRetweets, NFBActivityNotificationCategoryReplies];
}

static NSString *NFBActivityNotificationProfileDID(NSDictionary *profile) {
  return NFBNotificationStringValue(NFBNotificationDictionaryValue(profile)[@"did"]);
}

@interface NFBNotificationCoordinator ()

@property (nonatomic, assign, readwrite) NSUInteger homeBadgeCount;
@property (nonatomic, assign, readwrite) NSUInteger notificationBadgeCount;
@property (nonatomic, assign, readwrite) NSUInteger messageBadgeCount;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, copy) NSString *homeTopPostID;
@property (nonatomic, copy) NSString *remoteDeviceToken;
@property (nonatomic, copy) NSString *registeredRemoteDID;
@property (nonatomic, copy) NSString *registeredRemoteToken;
@property (nonatomic, copy) NSString *registeredRemoteAppID;
@property (nonatomic, assign) BOOL refreshing;
@property (nonatomic, assign) NSUInteger observedAccountGeneration;
@property (nonatomic, assign) BOOL localAlertsPrimed;
@property (nonatomic, assign) BOOL requestedRemoteRegistration;
@property (nonatomic, assign) BOOL remoteRegistrationInFlight;

+ (NSArray<NSString *> *)activityNotificationCategoriesByTogglingCategory:(NSString *)categoryID currentCategories:(NSArray<NSString *> *)currentCategories;
+ (void)applyActivityNotificationCategories:(NSArray<NSString *> *)categories
                                   previous:(NSArray<NSString *> *)previous
                                 forProfile:(NSDictionary *)profile
                         fromViewController:(UIViewController *)viewController
                                 completion:(dispatch_block_t)completion;

@end

@interface NFBActivityNotificationOptionRow : UIControl

@property (nonatomic, copy) NSString *categoryID;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *checkBubble;
@property (nonatomic, strong) UIImageView *checkImageView;
@property (nonatomic, strong) UIView *separatorView;

- (instancetype)initWithCategoryID:(NSString *)categoryID title:(NSString *)title subtitle:(NSString *)subtitle;
- (void)setChecked:(BOOL)checked animated:(BOOL)animated;

@end

@implementation NFBActivityNotificationOptionRow

- (instancetype)initWithCategoryID:(NSString *)categoryID title:(NSString *)title subtitle:(NSString *)subtitle {
  self = [super init];
  if (self) {
    self.categoryID = categoryID ?: @"";
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = NFBIPAModalSheetBackgroundColor();
    self.exclusiveTouch = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = title;
    _titleLabel.textColor = NFBColorText();
    _titleLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.text = subtitle;
    _subtitleLabel.textColor = NFBColorSecondaryText();
    _subtitleLabel.font = NFBFont(13.0, NFBFontWeightRegular);
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentFill;
    textStack.spacing = 2.0;

    _checkBubble = [[UIView alloc] init];
    _checkBubble.translatesAutoresizingMaskIntoConstraints = NO;
    _checkBubble.layer.cornerRadius = 11.0;
    _checkBubble.layer.borderWidth = 1.5;
    _checkBubble.layer.borderColor = NFBColorSecondaryText().CGColor;
    _checkBubble.backgroundColor = UIColor.clearColor;

    _checkImageView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_check")];
    _checkImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkImageView.tintColor = UIColor.whiteColor;
    _checkImageView.contentMode = UIViewContentModeScaleAspectFit;
    _checkImageView.alpha = 0.0;
    [_checkBubble addSubview:_checkImageView];

    _separatorView = [[UIView alloc] init];
    _separatorView.translatesAutoresizingMaskIntoConstraints = NO;
    _separatorView.backgroundColor = NFBColorBorder();

    [self addSubview:textStack];
    [self addSubview:_checkBubble];
    [self addSubview:_separatorView];

    [NSLayoutConstraint activateConstraints:@[
      [self.heightAnchor constraintEqualToConstant:NFBIPAModalSheetRowHeight()],
      [textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24.0],
      [textStack.trailingAnchor constraintEqualToAnchor:_checkBubble.leadingAnchor constant:-16.0],
      [textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_checkBubble.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24.0],
      [_checkBubble.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_checkBubble.widthAnchor constraintEqualToConstant:22.0],
      [_checkBubble.heightAnchor constraintEqualToConstant:22.0],
      [_checkImageView.centerXAnchor constraintEqualToAnchor:_checkBubble.centerXAnchor],
      [_checkImageView.centerYAnchor constraintEqualToAnchor:_checkBubble.centerYAnchor],
      [_checkImageView.widthAnchor constraintEqualToConstant:12.0],
      [_checkImageView.heightAnchor constraintEqualToConstant:12.0],
      [_separatorView.leadingAnchor constraintEqualToAnchor:textStack.leadingAnchor],
      [_separatorView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_separatorView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [_separatorView.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
    ]];

    self.accessibilityLabel = title;
    self.accessibilityValue = subtitle;
  }
  return self;
}

- (void)setHighlighted:(BOOL)highlighted {
  [super setHighlighted:highlighted];
  UIColor *targetColor = highlighted ? NFBIPAModalSheetRowHighlightColor() : NFBIPAModalSheetBackgroundColor();
  [UIView animateWithDuration:0.12 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:^{
    self.backgroundColor = targetColor;
  } completion:nil];
}

- (void)setChecked:(BOOL)checked animated:(BOOL)animated {
  self.selected = checked;
  self.accessibilityTraits = UIAccessibilityTraitButton | (checked ? UIAccessibilityTraitSelected : 0);
  void (^changes)(void) = ^{
    self.checkBubble.backgroundColor = checked ? NFBColorAccent() : UIColor.clearColor;
    self.checkBubble.layer.borderColor = (checked ? NFBColorAccent() : NFBColorSecondaryText()).CGColor;
    self.checkImageView.alpha = checked ? 1.0 : 0.0;
  };
  if (animated) {
    [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
  } else {
    changes();
  }
}

@end

@interface NFBActivityNotificationChecklistViewController : UIViewController

@property (nonatomic, copy) NSDictionary *profile;
@property (nonatomic, copy) dispatch_block_t completionHandler;
@property (nonatomic, strong) UIButton *backdropButton;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) NSLayoutConstraint *sheetHeightConstraint;
@property (nonatomic, copy) NSArray<NSString *> *selectedCategories;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NFBActivityNotificationOptionRow *> *rowsByCategory;
@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, assign) BOOL animatedIn;
@property (nonatomic, assign) BOOL applying;

- (instancetype)initWithProfile:(NSDictionary *)profile completion:(dispatch_block_t)completion;

@end

@implementation NFBActivityNotificationChecklistViewController

- (instancetype)initWithProfile:(NSDictionary *)profile completion:(dispatch_block_t)completion {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    self.profile = [profile copy] ?: @{};
    self.completionHandler = [completion copy];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    self.rowsByCategory = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.selectedCategories = [NFBNotificationCoordinator activityNotificationCategoriesForProfile:self.profile ?: @{}];
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
  NFBInstallSheetDismissGesture(self.sheetView, self.backdropButton, self, @selector(cancelTapped));
  [self.view addSubview:self.sheetView];

  UIView *grabberRow = [[UIView alloc] init];
  grabberRow.translatesAutoresizingMaskIntoConstraints = NO;

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetGrabberAppearance(grabber);
  [grabberRow addSubview:grabber];

  UIView *titleRow = [self titleRow];
  NSMutableArray<UIView *> *arranged = [NSMutableArray arrayWithObjects:grabberRow, titleRow, nil];
  for (NSString *categoryID in [NFBNotificationCoordinator activityNotificationCategoryIDs]) {
    NFBActivityNotificationOptionRow *row = [[NFBActivityNotificationOptionRow alloc] initWithCategoryID:categoryID
                                                                                                   title:[NFBNotificationCoordinator activityNotificationTitleForCategory:categoryID]
                                                                                                subtitle:[self subtitleForCategory:categoryID]];
    [row addTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.rowsByCategory[categoryID] = row;
    [arranged addObject:row];
  }
  NFBActivityNotificationOptionRow *lastRow = (NFBActivityNotificationOptionRow *)arranged.lastObject;
  lastRow.separatorView.hidden = YES;

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:arranged];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 0.0;
  [self.sheetView addSubview:stack];

  self.sheetHeightConstraint = [self.sheetView.heightAnchor constraintEqualToConstant:[self sheetHeightForBounds:UIScreen.mainScreen.bounds safeAreaInsets:UIEdgeInsetsZero]];
  [NSLayoutConstraint activateConstraints:@[
    [self.backdropButton.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.backdropButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.backdropButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.backdropButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.sheetView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.sheetView.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
    self.sheetHeightConstraint,
    [stack.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor],
    [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0],
    [grabberRow.heightAnchor constraintEqualToConstant:18.0],
    [grabber.topAnchor constraintEqualToAnchor:grabberRow.topAnchor constant:6.0],
    [grabber.centerXAnchor constraintEqualToAnchor:grabberRow.centerXAnchor],
    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0]
  ]];

  self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, 420.0);
  [self updateRowsAnimated:NO];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (self.animatedIn) return;
  self.animatedIn = YES;
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
  self.sheetHeightConstraint.constant = [self sheetHeightForBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets];
}

- (UIView *)titleRow {
  UIView *row = [[UIView alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = @"Account notifications";
  titleLabel.textColor = NFBColorText();
  titleLabel.font = NFBFont(16.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentCenter;

  UILabel *subtitleLabel = [[UILabel alloc] init];
  subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  subtitleLabel.text = [self messageText];
  subtitleLabel.textColor = NFBColorSecondaryText();
  subtitleLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  subtitleLabel.textAlignment = NSTextAlignmentCenter;
  subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIStackView *labelStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
  labelStack.translatesAutoresizingMaskIntoConstraints = NO;
  labelStack.axis = UILayoutConstraintAxisVertical;
  labelStack.alignment = UIStackViewAlignmentFill;
  labelStack.spacing = 3.0;

  UIButton *doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
  doneButton.translatesAutoresizingMaskIntoConstraints = NO;
  [doneButton setTitle:@"Done" forState:UIControlStateNormal];
  [doneButton setTitleColor:NFBColorText() forState:UIControlStateNormal];
  doneButton.titleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  doneButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentTrailing;
  [doneButton addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];

  [row addSubview:labelStack];
  [row addSubview:doneButton];
  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:64.0],
    [labelStack.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
    [labelStack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [labelStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:row.leadingAnchor constant:76.0],
    [labelStack.trailingAnchor constraintLessThanOrEqualToAnchor:doneButton.leadingAnchor constant:-8.0],
    [doneButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16.0],
    [doneButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [doneButton.widthAnchor constraintEqualToConstant:64.0],
    [doneButton.heightAnchor constraintEqualToAnchor:row.heightAnchor]
  ]];
  return row;
}

- (NSString *)messageText {
  NSString *handle = [NFBAtprotoClient handleForProfile:self.profile ?: @{}];
  return handle.length > 0 ? [NSString stringWithFormat:@"Choose what to get from @%@.", handle] : @"Choose what to get from this account.";
}

- (NSString *)subtitleForCategory:(NSString *)categoryID {
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryAll]) return @"Tweets, articles, retweets, and replies";
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryTweets]) return @"Original posts";
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryArticles]) return @"Standard.site articles";
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryRetweets]) return @"Retweets from this account";
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryReplies]) return @"Replies from this account";
  return @"Notifications from this account";
}

- (CGFloat)sheetHeightForBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
  CGFloat height = CGRectGetHeight(bounds);
  if (height <= 0.0) height = CGRectGetHeight(UIScreen.mainScreen.bounds);
  CGFloat bottomPadding = MAX(18.0, safeAreaInsets.bottom + 10.0);
  CGFloat contentHeight = 18.0 + 64.0 + (NFBIPAModalSheetRowHeight() * (CGFloat)[NFBNotificationCoordinator activityNotificationCategoryIDs].count) + bottomPadding;
  CGFloat availableHeight = height - safeAreaInsets.top - 8.0;
  return ceil(MIN(contentHeight, MAX(0.0, availableHeight)));
}

- (BOOL)categoryIsChecked:(NSString *)categoryID {
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryAll] && [self.selectedCategories containsObject:NFBActivityNotificationCategoryAll]) return YES;
  return [NFBNotificationCoordinator activityNotificationCategories:self.selectedCategories ?: @[] includeCategory:categoryID];
}

- (void)updateRowsAnimated:(BOOL)animated {
  for (NSString *categoryID in [NFBNotificationCoordinator activityNotificationCategoryIDs]) {
    [self.rowsByCategory[categoryID] setChecked:[self categoryIsChecked:categoryID] animated:animated];
  }
}

- (void)setRowsEnabled:(BOOL)enabled {
  for (NFBActivityNotificationOptionRow *row in self.rowsByCategory.allValues) {
    row.userInteractionEnabled = enabled;
    row.alpha = enabled ? 1.0 : 0.55;
  }
}

- (void)optionTapped:(NFBActivityNotificationOptionRow *)sender {
  if (self.applying || sender.categoryID.length == 0) return;
  UISelectionFeedbackGenerator *feedback = [[UISelectionFeedbackGenerator alloc] init];
  [feedback selectionChanged];
  NSArray<NSString *> *previous = self.selectedCategories ?: @[];
  NSArray<NSString *> *next = [NFBNotificationCoordinator activityNotificationCategoriesByTogglingCategory:sender.categoryID currentCategories:previous];
  self.selectedCategories = next ?: @[];
  [self updateRowsAnimated:YES];
  self.applying = YES;
  [self setRowsEnabled:NO];

  __weak typeof(self) weakSelf = self;
  [NFBNotificationCoordinator applyActivityNotificationCategories:next ?: @[]
                                                         previous:previous
                                                       forProfile:self.profile ?: @{}
                                               fromViewController:self
                                                       completion:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    strongSelf.selectedCategories = [NFBNotificationCoordinator activityNotificationCategoriesForProfile:strongSelf.profile ?: @{}];
    strongSelf.applying = NO;
    [strongSelf setRowsEnabled:YES];
    [strongSelf updateRowsAnimated:YES];
    if (strongSelf.completionHandler) strongSelf.completionHandler();
  }];
}

- (void)cancelTapped {
  [self dismissSheet];
}

- (void)doneTapped {
  [self dismissSheet];
}

- (void)dismissSheet {
  if (self.dismissing) return;
  self.dismissing = YES;
  CGFloat height = MAX(CGRectGetHeight(self.sheetView.bounds), self.sheetHeightConstraint.constant);
  [UIView animateWithDuration:0.24
                        delay:0.0
                      options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseIn
                   animations:^{
    self.backdropButton.alpha = 0.0;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, height + 24.0);
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:nil];
  }];
}

@end

@implementation NFBNotificationCoordinator

+ (instancetype)sharedCoordinator {
  static NFBNotificationCoordinator *coordinator = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    coordinator = [[NFBNotificationCoordinator alloc] initPrivate];
  });
  return coordinator;
}

+ (NSArray<NSString *> *)activityNotificationCategoryIDs {
  return @[NFBActivityNotificationCategoryAll, NFBActivityNotificationCategoryTweets, NFBActivityNotificationCategoryArticles, NFBActivityNotificationCategoryRetweets, NFBActivityNotificationCategoryReplies];
}

+ (NSString *)activityNotificationTitleForCategory:(NSString *)categoryID {
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryAll]) return @"All";
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryTweets]) return @"Tweets";
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryArticles]) return @"Articles";
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryRetweets]) return @"Retweets";
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryReplies]) return @"Replies";
  return @"Notifications";
}

+ (NSDictionary *)storedActivityNotificationCategoriesByDID {
  NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:NFBActivityNotificationCategoriesDefaultsKey];
  return [stored isKindOfClass:NSDictionary.class] ? stored : @{};
}

+ (BOOL)hasStoredActivityNotificationCategoriesForProfile:(NSDictionary *)profile {
  NSString *did = NFBActivityNotificationProfileDID(profile);
  if (did.length == 0) return NO;
  return [self storedActivityNotificationCategoriesByDID][did] != nil;
}

+ (NSArray<NSString *> *)normalizedActivityNotificationCategories:(NSArray *)categories {
  if (![categories isKindOfClass:NSArray.class] || categories.count == 0) return @[];
  NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
  for (id value in categories) {
    NSString *category = NFBNotificationStringValue(value);
    if ([category isEqualToString:NFBActivityNotificationCategoryAll]) return @[NFBActivityNotificationCategoryAll];
  }
  for (NSString *category in NFBActivityNotificationIndividualCategories()) {
    if ([categories containsObject:category]) [set addObject:category];
  }
  if (set.count == NFBActivityNotificationIndividualCategories().count) return @[NFBActivityNotificationCategoryAll];
  return set.array ?: @[];
}

+ (NSArray<NSString *> *)activityNotificationCategoriesForProfile:(NSDictionary *)profile {
  NSString *did = NFBActivityNotificationProfileDID(profile);
  NSDictionary *stored = [self storedActivityNotificationCategoriesByDID];
  id storedCategories = did.length > 0 ? stored[did] : nil;
  if ([storedCategories isKindOfClass:NSArray.class]) return [self normalizedActivityNotificationCategories:storedCategories];

  NSDictionary *viewer = NFBNotificationDictionaryValue(NFBNotificationDictionaryValue(profile)[@"viewer"]);
  NSDictionary *activitySubscription = NFBNotificationDictionaryValue(viewer[@"activitySubscription"]);
  BOOL post = [activitySubscription[@"post"] respondsToSelector:@selector(boolValue)] && [activitySubscription[@"post"] boolValue];
  BOOL reply = [activitySubscription[@"reply"] respondsToSelector:@selector(boolValue)] && [activitySubscription[@"reply"] boolValue];
  return (post || reply) ? @[NFBActivityNotificationCategoryAll] : @[];
}

+ (BOOL)activityNotificationsEnabledForProfile:(NSDictionary *)profile {
  return [self activityNotificationCategoriesForProfile:profile].count > 0;
}

+ (BOOL)activityNotificationCategories:(NSArray<NSString *> *)categories includeCategory:(NSString *)categoryID {
  NSArray<NSString *> *normalized = [self normalizedActivityNotificationCategories:categories];
  if ([normalized containsObject:NFBActivityNotificationCategoryAll]) return YES;
  return [normalized containsObject:categoryID];
}

+ (BOOL)activitySubscriptionPostEnabledForCategories:(NSArray<NSString *> *)categories {
  return [self normalizedActivityNotificationCategories:categories].count > 0;
}

+ (BOOL)activitySubscriptionReplyEnabledForCategories:(NSArray<NSString *> *)categories {
  NSArray<NSString *> *normalized = [self normalizedActivityNotificationCategories:categories];
  return [self activityNotificationCategories:normalized includeCategory:NFBActivityNotificationCategoryReplies];
}

+ (void)setActivityNotificationCategories:(NSArray<NSString *> *)categories forProfile:(NSDictionary *)profile {
  NSString *did = NFBActivityNotificationProfileDID(profile);
  if (did.length == 0) return;
  NSArray<NSString *> *normalized = [self normalizedActivityNotificationCategories:categories];
  NSMutableDictionary *stored = [[self storedActivityNotificationCategoriesByDID] mutableCopy] ?: [NSMutableDictionary dictionary];
  stored[did] = normalized ?: @[];
  [NSUserDefaults.standardUserDefaults setObject:stored forKey:NFBActivityNotificationCategoriesDefaultsKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBActivityNotificationPreferencesDidChangeNotification object:self userInfo:@{@"did": did, @"categories": normalized ?: @[]}];
}

+ (NSMutableSet<NSString *> *)mutedConversationURISet {
  NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:NFBMutedConversationURIsDefaultsKey];
  NSMutableSet<NSString *> *set = [NSMutableSet set];
  for (id value in stored ?: @[]) {
    if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) [set addObject:value];
  }
  return set;
}

+ (NSString *)conversationURIForPost:(NSDictionary *)post {
  if (![post isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *record = NFBNotificationDictionaryValue(post[@"record"]);
  NSDictionary *reply = NFBNotificationDictionaryValue(record[@"reply"]);
  NSDictionary *root = NFBNotificationDictionaryValue(reply[@"root"]);
  NSString *rootURI = NFBNotificationStringValue(root[@"uri"]);
  if (rootURI.length > 0) return rootURI;
  return NFBNotificationStringValue(post[@"uri"]);
}

+ (BOOL)isConversationMutedForPost:(NSDictionary *)post {
  NSString *conversationURI = [self conversationURIForPost:post];
  if (conversationURI.length == 0) return NO;
  return [[self mutedConversationURISet] containsObject:conversationURI];
}

+ (void)setConversationMuted:(BOOL)muted forPost:(NSDictionary *)post {
  NSString *conversationURI = [self conversationURIForPost:post];
  if (conversationURI.length == 0) return;
  NSMutableSet<NSString *> *set = [self mutedConversationURISet];
  if (muted) [set addObject:conversationURI];
  else [set removeObject:conversationURI];
  NSArray *sorted = [[set allObjects] sortedArrayUsingSelector:@selector(compare:)];
  [NSUserDefaults.standardUserDefaults setObject:sorted forKey:NFBMutedConversationURIsDefaultsKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[self sharedCoordinator] refreshBadgeCounts];
}

+ (BOOL)notificationItemIsMutedByConversationSetting:(NSDictionary *)item {
  if (![item isKindOfClass:NSDictionary.class]) return NO;
  NSMutableSet<NSString *> *muted = [self mutedConversationURISet];
  if (muted.count == 0) return NO;
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item ?: @{}];
  NSString *conversationURI = [self conversationURIForPost:post];
  if (conversationURI.length > 0 && [muted containsObject:conversationURI]) return YES;
  NSString *targetURI = NFBNotificationStringValue(item[@"targetURI"]);
  return targetURI.length > 0 && [muted containsObject:targetURI];
}

+ (BOOL)postIsReply:(NSDictionary *)post {
  NSDictionary *record = NFBNotificationDictionaryValue(post[@"record"]);
  return [record[@"reply"] isKindOfClass:NSDictionary.class];
}

+ (BOOL)notificationItemIsRetweet:(NSDictionary *)item {
  NSDictionary *reason = NFBNotificationDictionaryValue(item[@"feedReason"]);
  NSString *type = NFBNotificationStringValue(reason[@"$type"]);
  if ([type containsString:@"reasonRepost"]) return YES;
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
  NSDictionary *postReason = NFBNotificationDictionaryValue(post[@"reason"]);
  NSString *postReasonType = NFBNotificationStringValue(postReason[@"$type"]);
  return [postReasonType containsString:@"reasonRepost"];
}

+ (BOOL)subscribedPostNotificationItem:(NSDictionary *)item matchesActivityNotificationPreferencesForProfile:(NSDictionary *)profile {
  NSArray<NSString *> *categories = [self activityNotificationCategoriesForProfile:profile];
  if (categories.count == 0 && ![self hasStoredActivityNotificationCategoriesForProfile:profile]) return YES;
  if (categories.count == 0) return NO;
  if ([categories containsObject:NFBActivityNotificationCategoryAll]) return YES;

  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
  BOOL isArticle = [NFBAtprotoClient externalCardIsStandardSiteArticle:[NFBAtprotoClient externalCardForPost:post]];
  BOOL isReply = [self postIsReply:post];
  BOOL isRetweet = [self notificationItemIsRetweet:item];
  if (isArticle && [self activityNotificationCategories:categories includeCategory:NFBActivityNotificationCategoryArticles]) return YES;
  if (isReply && [self activityNotificationCategories:categories includeCategory:NFBActivityNotificationCategoryReplies]) return YES;
  if (isRetweet && [self activityNotificationCategories:categories includeCategory:NFBActivityNotificationCategoryRetweets]) return YES;
  if (!isArticle && !isReply && !isRetweet && [self activityNotificationCategories:categories includeCategory:NFBActivityNotificationCategoryTweets]) return YES;
  return NO;
}

+ (NSArray<NSString *> *)activityNotificationCategoriesByTogglingCategory:(NSString *)categoryID currentCategories:(NSArray<NSString *> *)currentCategories {
  NSArray<NSString *> *normalized = [self normalizedActivityNotificationCategories:currentCategories];
  if ([categoryID isEqualToString:NFBActivityNotificationCategoryAll]) {
    return [normalized containsObject:NFBActivityNotificationCategoryAll] ? @[] : @[NFBActivityNotificationCategoryAll];
  }

  NSMutableOrderedSet<NSString *> *next = [NSMutableOrderedSet orderedSet];
  if ([normalized containsObject:NFBActivityNotificationCategoryAll]) {
    for (NSString *category in NFBActivityNotificationIndividualCategories()) [next addObject:category];
  } else {
    for (NSString *category in normalized) [next addObject:category];
  }
  if ([next containsObject:categoryID]) [next removeObject:categoryID];
  else [next addObject:categoryID];
  return [self normalizedActivityNotificationCategories:next.array ?: @[]];
}

+ (void)applyActivityNotificationCategories:(NSArray<NSString *> *)categories
                                   previous:(NSArray<NSString *> *)previous
                                 forProfile:(NSDictionary *)profile
                         fromViewController:(UIViewController *)viewController
                                 completion:(dispatch_block_t)completion {
  NSString *did = NFBActivityNotificationProfileDID(profile);
  if (did.length == 0) return;
  NSArray<NSString *> *normalized = [self normalizedActivityNotificationCategories:categories];
  [self setActivityNotificationCategories:normalized forProfile:profile];
  BOOL post = [self activitySubscriptionPostEnabledForCategories:normalized];
  BOOL reply = [self activitySubscriptionReplyEnabledForCategories:normalized];
  [[NFBAtprotoClient sharedClient] setActivitySubscriptionForSubject:did post:post reply:reply completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) {
        [self setActivityNotificationCategories:previous ?: @[] forProfile:profile];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Notifications"
                                                                       message:error.localizedDescription ?: @"Could not update notifications for this account."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [viewController presentViewController:alert animated:YES completion:nil];
      }
      if (completion) completion();
    });
  }];
}

+ (void)presentActivityNotificationChecklistForProfile:(NSDictionary *)profile
                                    fromViewController:(UIViewController *)viewController
                                            sourceView:(UIView *)sourceView
                                            completion:(dispatch_block_t)completion {
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
    return;
  }
  (void)sourceView;
  NSString *did = NFBActivityNotificationProfileDID(profile);
  if (did.length == 0 || !viewController) return;

  dispatch_block_t showDrawer = ^{
    NFBActivityNotificationChecklistViewController *drawer = [[NFBActivityNotificationChecklistViewController alloc] initWithProfile:profile completion:completion];
    [viewController presentViewController:drawer animated:NO completion:nil];
  };
  if (viewController.presentedViewController) {
    [viewController dismissViewControllerAnimated:YES completion:showDrawer];
    return;
  }
  showDrawer();
}

+ (void)setArticleNotificationsOnlyForProfile:(NSDictionary *)profile
                            fromViewController:(UIViewController *)viewController
                                    completion:(dispatch_block_t)completion {
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
    return;
  }
  NSString *did = NFBActivityNotificationProfileDID(profile);
  if (did.length == 0 || !viewController) return;

  NSArray<NSString *> *previous = [self activityNotificationCategoriesForProfile:profile];
  [self applyActivityNotificationCategories:@[NFBActivityNotificationCategoryArticles]
                                   previous:previous
                                 forProfile:profile
                         fromViewController:viewController
                                 completion:completion];
}

- (instancetype)init {
  return [NFBNotificationCoordinator sharedCoordinator];
}

- (instancetype)initPrivate {
  self = [super init];
  if (self) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    _remoteDeviceToken = [[defaults stringForKey:NFBRemotePushTokenDefaultsKey] copy] ?: @"";
    _registeredRemoteDID = [[defaults stringForKey:NFBRemotePushRegisteredDIDDefaultsKey] copy] ?: @"";
    _registeredRemoteToken = [[defaults stringForKey:NFBRemotePushRegisteredTokenDefaultsKey] copy] ?: @"";
    _registeredRemoteAppID = [[defaults stringForKey:NFBRemotePushRegisteredAppIDDefaultsKey] copy] ?: @"";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged:) name:NFBAtprotoSessionChangedNotification object:[NFBAtprotoSession sharedSession]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self.refreshTimer invalidate];
}

- (void)start {
  self.observedAccountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  [self requestNotificationAuthorizationIfNeeded];
  [self registerStoredRemoteTokenForCurrentSession];
  [self startTimerIfNeeded];
  [self refreshBadgeCounts];
}

- (void)startTimerIfNeeded {
  if (self.refreshTimer) return;
  self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:NFBNotificationRefreshInterval target:self selector:@selector(refreshTimerFired:) userInfo:nil repeats:YES];
  self.refreshTimer.tolerance = 10.0;
}

- (void)refreshTimerFired:(NSTimer *)timer {
  (void)timer;
  BOOL shouldDeliverLocalAlerts = UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
  [self refreshBadgeCountsAllowingLocalAlerts:shouldDeliverLocalAlerts completion:nil];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
  (void)notification;
  [self refreshBadgeCounts];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
  (void)notification;
  [self refreshBadgeCounts];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
  (void)notification;
  [self refreshBadgeCountsAllowingLocalAlerts:YES completion:nil];
}

- (void)sessionChanged:(NSNotification *)notification {
  (void)notification;
  NSUInteger generation = [NFBAtprotoSession sharedSession].accountGeneration;
  if (generation == self.observedAccountGeneration) return;
  self.observedAccountGeneration = generation;
  self.refreshing = NO;
  self.homeTopPostID = nil;
  self.homeBadgeCount = 0;
  self.notificationBadgeCount = 0;
  self.messageBadgeCount = 0;
  self.localAlertsPrimed = NO;
  [self publishCounts];
  if ([[NFBAtprotoSession sharedSession] hasSession]) {
    [self registerStoredRemoteTokenForCurrentSession];
    [self refreshBadgeCounts];
  }
}

- (void)requestNotificationAuthorizationIfNeeded {
  UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
  [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
    NSLog(@"NotTwitter notification settings auth=%ld alert=%ld sound=%ld badge=%ld", (long)settings.authorizationStatus, (long)settings.alertSetting, (long)settings.soundSetting, (long)settings.badgeSetting);
    if ([self notificationSettingsAllowRemoteRegistration:settings]) {
      [self registerForRemoteNotificationsIfPossible];
      return;
    }
    if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) return;
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionBadge | UNAuthorizationOptionSound;
    [center requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError *error) {
      if (error) NSLog(@"NotTwitter notification authorization failed: %@", error.localizedDescription);
      NSLog(@"NotTwitter notification authorization granted=%@", granted ? @"YES" : @"NO");
      if (granted) [self registerForRemoteNotificationsIfPossible];
    }];
  }];
}

- (BOOL)notificationSettingsAllowRemoteRegistration:(UNNotificationSettings *)settings {
  if (settings.authorizationStatus == UNAuthorizationStatusAuthorized) return YES;
  if (settings.authorizationStatus == UNAuthorizationStatusProvisional) return YES;
  if (@available(iOS 14.0, *)) {
    if (settings.authorizationStatus == UNAuthorizationStatusEphemeral) return YES;
  }
  return NO;
}

- (void)registerForRemoteNotificationsIfPossible {
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self registerForRemoteNotificationsIfPossible];
    });
    return;
  }
  if (self.requestedRemoteRegistration) {
    [self registerStoredRemoteTokenForCurrentSession];
    return;
  }
  self.requestedRemoteRegistration = YES;
  NSLog(@"NotTwitter requesting APNs remote notification token");
  [UIApplication.sharedApplication registerForRemoteNotifications];
}

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  NSString *token = NFBHexStringForDeviceToken(deviceToken);
  if (token.length == 0) return;
  NSLog(@"NotTwitter APNs token received length=%lu", (unsigned long)token.length);
  BOOL changed = ![token isEqualToString:self.remoteDeviceToken ?: @""];
  self.remoteDeviceToken = token;
  [NSUserDefaults.standardUserDefaults setObject:token forKey:NFBRemotePushTokenDefaultsKey];
  if (changed) {
    self.registeredRemoteToken = @"";
    self.registeredRemoteDID = @"";
    self.registeredRemoteAppID = @"";
    [NSUserDefaults.standardUserDefaults removeObjectForKey:NFBRemotePushRegisteredTokenDefaultsKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:NFBRemotePushRegisteredDIDDefaultsKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:NFBRemotePushRegisteredAppIDDefaultsKey];
  }
  [NSUserDefaults.standardUserDefaults synchronize];
  [self registerStoredRemoteTokenForCurrentSession];
}

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  NSLog(@"NotTwitter APNs registration failed: %@", error.localizedDescription ?: error);
}

- (void)registerStoredRemoteTokenForCurrentSession {
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self registerStoredRemoteTokenForCurrentSession];
    });
    return;
  }
  if (self.remoteRegistrationInFlight) return;
  if (![[NFBAtprotoSession sharedSession] hasSession]) return;

  NSString *token = self.remoteDeviceToken ?: @"";
  NSString *did = [NFBAtprotoSession sharedSession].did ?: @"";
  NSString *appID = NFBRemotePushAppID();
  if (token.length == 0 || did.length == 0 || appID.length == 0) return;
  if ([token isEqualToString:self.registeredRemoteToken ?: @""] &&
      [did isEqualToString:self.registeredRemoteDID ?: @""] &&
      [appID isEqualToString:self.registeredRemoteAppID ?: @""]) return;

  self.remoteRegistrationInFlight = YES;
  NSLog(@"NotTwitter registering live push did=%@ appID=%@", did, appID);
  [[NFBAtprotoClient sharedClient] registerPushToken:token appID:appID completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    dispatch_async(dispatch_get_main_queue(), ^{
      self.remoteRegistrationInFlight = NO;
      NSString *currentDID = [NFBAtprotoSession sharedSession].did ?: @"";
      if (![currentDID isEqualToString:did]) {
        [self registerStoredRemoteTokenForCurrentSession];
        return;
      }
      if (error) {
        NSLog(@"NotTwitter push register failed: %@", error.localizedDescription ?: error);
        return;
      }
      self.registeredRemoteToken = token;
      self.registeredRemoteDID = did;
      self.registeredRemoteAppID = appID;
      [NSUserDefaults.standardUserDefaults setObject:token forKey:NFBRemotePushRegisteredTokenDefaultsKey];
      [NSUserDefaults.standardUserDefaults setObject:did forKey:NFBRemotePushRegisteredDIDDefaultsKey];
      [NSUserDefaults.standardUserDefaults setObject:appID forKey:NFBRemotePushRegisteredAppIDDefaultsKey];
      [NSUserDefaults.standardUserDefaults synchronize];
      NSLog(@"NotTwitter push registered for %@", did);
    });
  }];
}

- (void)handleRemoteNotificationUserInfo:(NSDictionary *)userInfo completion:(void (^)(UIBackgroundFetchResult result))completion {
  (void)userInfo;
  [self refreshBadgeCountsAllowingLocalAlerts:NO completion:completion];
}

- (void)unregisterRemoteNotificationsForCurrentAccountWithCompletion:(dispatch_block_t)completion {
  NSString *token = self.remoteDeviceToken ?: @"";
  NSString *did = [NFBAtprotoSession sharedSession].did ?: @"";
  NSString *appID = NFBRemotePushAppID();
  if (token.length == 0 || did.length == 0 || appID.length == 0) {
    if (completion) completion();
    return;
  }

  [[NFBAtprotoClient sharedClient] unregisterPushToken:token appID:appID completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    if (error) NSLog(@"NotTwitter push unregister failed: %@", error.localizedDescription ?: error);
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.registeredRemoteDID isEqualToString:did]) {
        self.registeredRemoteDID = @"";
        self.registeredRemoteToken = @"";
        self.registeredRemoteAppID = @"";
        [NSUserDefaults.standardUserDefaults removeObjectForKey:NFBRemotePushRegisteredDIDDefaultsKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:NFBRemotePushRegisteredTokenDefaultsKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:NFBRemotePushRegisteredAppIDDefaultsKey];
        [NSUserDefaults.standardUserDefaults synchronize];
      }
      if (completion) completion();
    });
  }];
}

- (void)refreshBadgeCounts {
  [self refreshBadgeCountsAllowingLocalAlerts:NO completion:nil];
}

- (void)refreshMessageBadge {
  [self refreshBadgeCountsAllowingLocalAlerts:NO completion:nil];
}

- (void)refreshBadgeCountsAllowingLocalAlerts:(BOOL)allowLocalAlerts completion:(void (^)(UIBackgroundFetchResult result))completion {
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self refreshBadgeCountsAllowingLocalAlerts:allowLocalAlerts completion:completion];
    });
    return;
  }

  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    self.homeTopPostID = nil;
    self.homeBadgeCount = 0;
    self.notificationBadgeCount = 0;
    self.messageBadgeCount = 0;
    self.localAlertsPrimed = NO;
    [self publishCounts];
    if (completion) completion(UIBackgroundFetchResultNoData);
    return;
  }

  if (self.refreshing) {
    if (completion) completion(UIBackgroundFetchResultNoData);
    return;
  }

  self.refreshing = YES;
  NSUInteger accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
  NSString *sessionDID = [NFBAtprotoSession sharedSession].did ?: @"";
  NSUInteger oldHomeCount = self.homeBadgeCount;
  NSUInteger oldNotificationCount = self.notificationBadgeCount;
  NSUInteger oldMessageCount = self.messageBadgeCount;
  __block NSUInteger nextHomeCount = oldHomeCount;
  __block NSUInteger nextNotificationCount = oldNotificationCount;
  __block NSUInteger nextMessageCount = oldMessageCount;
  __block BOOL sawSuccess = NO;
  dispatch_group_t group = dispatch_group_create();

  dispatch_group_enter(group);
  [[NFBAtprotoClient sharedClient] fetchHomeTimelineWithCursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!error && accountGeneration == [NFBAtprotoSession sharedSession].accountGeneration) {
        sawSuccess = YES;
        nextHomeCount = [self homeBadgeCountForFeedItems:items ?: @[] previousTopID:self.homeTopPostID];
      }
      dispatch_group_leave(group);
    });
  }];

  dispatch_group_enter(group);
  [[NFBAtprotoClient sharedClient] fetchNotificationsWithCursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!error && accountGeneration == [NFBAtprotoSession sharedSession].accountGeneration) {
        sawSuccess = YES;
        nextNotificationCount = [self unreadNotificationCountForItems:items ?: @[]];
      }
      dispatch_group_leave(group);
    });
  }];

  dispatch_group_enter(group);
  [self fetchUnreadMessageCountWithCompletion:^(NSUInteger count, BOOL success) {
    if (success) {
      sawSuccess = YES;
      nextMessageCount = count;
    }
    dispatch_group_leave(group);
  }];

  dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    NSString *currentDID = [NFBAtprotoSession sharedSession].did ?: @"";
    if (accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration || ![currentDID isEqualToString:sessionDID]) {
      if (completion) completion(UIBackgroundFetchResultNoData);
      return;
    }
    self.refreshing = NO;

    BOOL changed = nextHomeCount != oldHomeCount || nextNotificationCount != oldNotificationCount || nextMessageCount != oldMessageCount;
    BOOL canAlert = allowLocalAlerts && self.localAlertsPrimed && UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    if (canAlert) {
      if (nextNotificationCount > oldNotificationCount) [self postLocalAlertForKind:@"notifications" count:nextNotificationCount];
      if (nextMessageCount > oldMessageCount) [self postLocalAlertForKind:@"messages" count:nextMessageCount];
    }

    self.homeBadgeCount = nextHomeCount;
    self.notificationBadgeCount = nextNotificationCount;
    self.messageBadgeCount = nextMessageCount;
    self.localAlertsPrimed = YES;
    [self publishCounts];
    if (completion) completion(!sawSuccess ? UIBackgroundFetchResultFailed : (changed ? UIBackgroundFetchResultNewData : UIBackgroundFetchResultNoData));
  });
}

- (void)fetchUnreadMessageCountWithCompletion:(void (^)(NSUInteger count, BOOL success))completion {
  __block NSUInteger acceptedCount = 0;
  __block NSUInteger requestCount = 0;
  __block BOOL acceptedSuccess = NO;
  __block BOOL requestSuccess = NO;
  dispatch_group_t group = dispatch_group_create();

  dispatch_group_enter(group);
  [[NFBAtprotoClient sharedClient] fetchChatConversationsWithCursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    if (!error) {
      acceptedSuccess = YES;
      acceptedCount = [self unreadMessageCountForConversations:items ?: @[] countRequests:NO];
    }
    dispatch_group_leave(group);
  }];

  dispatch_group_enter(group);
  [[NFBAtprotoClient sharedClient] fetchChatConversationRequestsWithCursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    if (!error) {
      requestSuccess = YES;
      requestCount = [self unreadMessageCountForConversations:items ?: @[] countRequests:YES];
    }
    dispatch_group_leave(group);
  }];

  dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    if (completion) completion(acceptedCount + requestCount, acceptedSuccess || requestSuccess);
  });
}

- (NSUInteger)homeBadgeCountForFeedItems:(NSArray<NSDictionary *> *)items previousTopID:(NSString *)previousTopID {
  NSString *topID = [self stablePostIDForFeedItem:items.firstObject ?: @{}];
  if (topID.length == 0) return self.homeBadgeCount;
  if (previousTopID.length == 0) {
    self.homeTopPostID = topID;
    return 0;
  }

  NSUInteger count = 0;
  for (NSDictionary *item in items) {
    NSString *stableID = [self stablePostIDForFeedItem:item];
    if (stableID.length == 0) continue;
    if ([stableID isEqualToString:previousTopID]) break;
    count++;
  }
  if (count == 0) self.homeTopPostID = topID;
  return MAX(self.homeBadgeCount, count);
}

- (NSString *)stablePostIDForFeedItem:(NSDictionary *)item {
  if (![item isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
  NSString *stableID = [NFBAtprotoClient stableIDForPost:post];
  if (stableID.length == 0 && [post[@"uri"] isKindOfClass:NSString.class]) stableID = post[@"uri"];
  return stableID ?: @"";
}

- (NSUInteger)unreadNotificationCountForItems:(NSArray<NSDictionary *> *)items {
  NSUInteger count = 0;
  for (NSDictionary *item in items) {
    if ([self.class notificationItemIsMutedByConversationSetting:item]) continue;
    NSString *reason = NFBNotificationStringValue(item[@"reason"]);
    if ([reason isEqualToString:@"subscribed-post"]) {
      NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
      NSDictionary *author = [item[@"author"] isKindOfClass:NSDictionary.class] ? item[@"author"] : nil;
      if (!author) author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
      if (![self.class subscribedPostNotificationItem:item matchesActivityNotificationPreferencesForProfile:author]) continue;
    }
    id isRead = item[@"isRead"];
    if (![isRead respondsToSelector:@selector(boolValue)] || ![isRead boolValue]) count++;
  }
  return count;
}

- (NSUInteger)unreadMessageCountForConversations:(NSArray<NSDictionary *> *)conversations countRequests:(BOOL)countRequests {
  NSUInteger count = 0;
  for (NSDictionary *conversation in conversations) {
    id unread = conversation[@"unreadCount"];
    NSInteger unreadValue = [unread respondsToSelector:@selector(integerValue)] ? [unread integerValue] : 0;
    if (unreadValue > 0) count += (NSUInteger)unreadValue;
    else if (countRequests) count += 1;
  }
  return count;
}

- (void)clearHomeBadge {
  if (self.homeBadgeCount == 0) return;
  self.homeBadgeCount = 0;
  [self publishCounts];
}

- (void)clearHomeBadgeWithFeedItems:(NSArray<NSDictionary *> *)items {
  NSString *topID = [self stablePostIDForFeedItem:items.firstObject ?: @{}];
  if (topID.length > 0) self.homeTopPostID = topID;
  self.homeBadgeCount = 0;
  [self publishCounts];
}

- (void)clearNotificationBadge {
  if (self.notificationBadgeCount == 0) return;
  self.notificationBadgeCount = 0;
  [self publishCounts];
}

- (void)publishCounts {
  NSUInteger appBadge = self.notificationBadgeCount + self.messageBadgeCount;
  UIApplication.sharedApplication.applicationIconBadgeNumber = (NSInteger)appBadge;
  NSDictionary *userInfo = @{
    @"home": @(self.homeBadgeCount),
    @"notifications": @(self.notificationBadgeCount),
    @"messages": @(self.messageBadgeCount)
  };
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBNotificationCountsDidChangeNotification object:self userInfo:userInfo];
}

- (void)postLocalAlertForKind:(NSString *)kind count:(NSUInteger)count {
  if (count == 0) return;
  UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
  if ([kind isEqualToString:@"messages"]) {
    content.title = count == 1 ? @"New message" : @"New messages";
    content.body = count == 1 ? @"You have 1 unread message." : [NSString stringWithFormat:@"You have %lu unread messages.", (unsigned long)count];
    content.threadIdentifier = @"not-twitter-messages";
    content.categoryIdentifier = @"not-twitter-messages";
  } else {
    content.title = count == 1 ? @"New notification" : @"New notifications";
    content.body = count == 1 ? @"You have 1 unread notification." : [NSString stringWithFormat:@"You have %lu unread notifications.", (unsigned long)count];
    content.threadIdentifier = @"not-twitter-notifications";
    content.categoryIdentifier = @"not-twitter-notifications";
  }
  content.sound = UNNotificationSound.defaultSound;
  content.userInfo = @{@"kind": kind ?: @"notifications", @"source": @"local"};
  NSUInteger appBadge = [kind isEqualToString:@"messages"] ? (self.notificationBadgeCount + count) : (count + self.messageBadgeCount);
  content.badge = @(appBadge);
  NSString *identifier = [NSString stringWithFormat:@"not-twitter-%@-%@", kind, NSUUID.UUID.UUIDString];
  UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.0 repeats:NO];
  UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
  [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:nil];
}

@end
