#import "NFBInteractiveSheet.h"
#import "NFBNeoFreeBirdUI.h"

#import "NFBTheme.h"

@interface BHCustomTabBarItem : NSObject <NSCoding>
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *pageID;
@end

@implementation BHCustomTabBarItem

- (void)encodeWithCoder:(NSCoder *)encoder {
  [encoder encodeObject:self.title forKey:@"title"];
  [encoder encodeObject:self.pageID forKey:@"pageID"];
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  self = [super init];
  if (self) {
    _title = [decoder decodeObjectForKey:@"title"];
    _pageID = [decoder decodeObjectForKey:@"pageID"];
  }
  return self;
}

@end

@implementation NFBNeoFreeBirdTabDefinition

- (instancetype)initWithPageID:(NSString *)pageID
                         title:(NSString *)title
                      iconName:(NSString *)iconName
              selectedIconName:(NSString *)selectedIconName {
  self = [super init];
  if (self) {
    _pageID = [pageID copy];
    _title = [title copy];
    _iconName = [iconName copy];
    _selectedIconName = [selectedIconName copy];
  }
  return self;
}

@end

@interface NFBNeoFreeBirdActionSheetViewController : UIViewController

@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *actions;
@property (nonatomic, copy, nullable) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *subtitleText;
@property (nonatomic, copy, nullable) NSString *cancelTitle;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *displayedActions;
@property (nonatomic, strong) UIButton *backdropButton;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, assign) BOOL dismissing;

@end

@implementation NFBNeoFreeBirdActionSheetViewController

static NSInteger const NFBNeoFreeBirdActionSheetRowHighlightTag = 48219;

static NSString *NFBActionSheetStringValue(id value) {
  return [value isKindOfClass:NSString.class] ? value : @"";
}

static BOOL NFBActionSheetBoolValue(id value) {
  return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

- (void)viewDidLoad {
  [super viewDidLoad];
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

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetGrabberAppearance(grabber);

  UIView *grabberRow = [[UIView alloc] init];
  grabberRow.translatesAutoresizingMaskIntoConstraints = NO;
  [grabberRow addSubview:grabber];

  UIScrollView *scrollView = [[UIScrollView alloc] init];
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.alwaysBounceVertical = NO;
  [self.sheetView addSubview:scrollView];

  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 0.0;
  [stack addArrangedSubview:grabberRow];
  [scrollView addSubview:stack];

  UIView *header = [self headerViewIfNeeded];
  if (header) {
    [stack addArrangedSubview:header];
    [stack setCustomSpacing:2.0 afterView:header];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *displayedActions = [NSMutableArray array];
  NSUInteger index = 0;
  for (NSDictionary<NSString *, id> *action in self.actions ?: @[]) {
    NSMutableDictionary<NSString *, id> *displayAction = [action mutableCopy] ?: [NSMutableDictionary dictionary];
    if (![displayAction[@"id"] isKindOfClass:NSString.class] || [(NSString *)displayAction[@"id"] length] == 0) {
      displayAction[@"id"] = [NSString stringWithFormat:@"action-%lu", (unsigned long)index];
    }
    [displayedActions addObject:[displayAction copy]];
    index++;
  }
  if (self.cancelTitle.length > 0) {
    [displayedActions addObject:@{
      @"id": @"cancel",
      @"title": self.cancelTitle,
      @"centered": @YES,
      @"separated": @YES
    }];
  }
  self.displayedActions = displayedActions;

  NSMutableArray<NSLayoutConstraint *> *rowHeightConstraints = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *action in self.displayedActions ?: @[]) {
    UIControl *row = [self rowForAction:action];
    [stack addArrangedSubview:row];
    [rowHeightConstraints addObject:[row.heightAnchor constraintGreaterThanOrEqualToConstant:[self rowHeightForAction:action]]];
  }

  [NSLayoutConstraint activateConstraints:@[
    [self.backdropButton.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.backdropButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.backdropButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.backdropButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.sheetView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:18.0],
    [self.sheetView.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14.0],
    [scrollView.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor],
    [scrollView.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor],
    [scrollView.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor],
    [scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0],
    [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
    [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
    [grabberRow.heightAnchor constraintEqualToConstant:18.0],
    [grabber.topAnchor constraintEqualToAnchor:grabberRow.topAnchor constant:6.0],
    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0],
    [grabber.centerXAnchor constraintEqualToAnchor:grabberRow.centerXAnchor]
  ]];
  [NSLayoutConstraint activateConstraints:rowHeightConstraints];
  NSLayoutConstraint *fitContent = [scrollView.heightAnchor constraintEqualToAnchor:stack.heightAnchor];
  fitContent.priority = UILayoutPriorityDefaultHigh;
  fitContent.active = YES;

  self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, 300.0);
  self.sheetView.alpha = 0.0;
  [UIView animateWithDuration:0.24 delay:0.0 usingSpringWithDamping:0.92 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut animations:^{
    self.backdropButton.alpha = 1.0;
    self.sheetView.alpha = 1.0;
    self.sheetView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (UIView *)headerViewIfNeeded {
  NSString *title = self.titleText.length > 0 ? self.titleText : @"";
  NSString *subtitle = self.subtitleText.length > 0 ? self.subtitleText : @"";
  if (title.length == 0 && subtitle.length == 0) return nil;

  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;

  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 2.0;
  [container addSubview:stack];

  if (title.length > 0) {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.textColor = NFBColorText();
    titleLabel.font = NFBFont(20.0, NFBFontWeightHeavy);
    titleLabel.numberOfLines = 2;
    [stack addArrangedSubview:titleLabel];
  }

  if (subtitle.length > 0) {
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = subtitle;
    subtitleLabel.textColor = NFBColorSecondaryText();
    subtitleLabel.font = NFBFont(14.0, NFBFontWeightRegular);
    subtitleLabel.numberOfLines = 3;
    [stack addArrangedSubview:subtitleLabel];
  }

  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:6.0],
    [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:24.0],
    [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-24.0],
    [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12.0]
  ]];
  return container;
}

- (CGFloat)rowHeightForAction:(NSDictionary<NSString *, id> *)action {
  return NFBIPAModalSheetRowHeight();
}

- (UIControl *)rowForAction:(NSDictionary<NSString *, id> *)action {
  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.backgroundColor = UIColor.clearColor;
  row.accessibilityIdentifier = NFBActionSheetStringValue(action[@"id"]);
  [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
  [row addTarget:self action:@selector(rowTouchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [row addTarget:self action:@selector(rowTouchReset:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

  UIView *highlight = [[UIView alloc] init];
  highlight.translatesAutoresizingMaskIntoConstraints = NO;
  highlight.backgroundColor = [NFBIPAModalSheetRowHighlightColor() colorWithAlphaComponent:0.0];
  highlight.userInteractionEnabled = NO;
  highlight.tag = NFBNeoFreeBirdActionSheetRowHighlightTag;
  [row addSubview:highlight];

  if (NFBActionSheetBoolValue(action[@"separated"])) {
    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = NFBColorBorder();
    separator.userInteractionEnabled = NO;
    [row addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
      [separator.topAnchor constraintEqualToAnchor:row.topAnchor],
      [separator.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:24.0],
      [separator.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-24.0],
      [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
    ]];
  }

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = NFBActionSheetStringValue(action[@"title"]);
  BOOL destructive = NFBActionSheetBoolValue(action[@"destructive"]);
  UIColor *rowTintColor = destructive ? [UIColor colorWithRed:0.96 green:0.25 blue:0.36 alpha:1.0] : NFBColorText();
  titleLabel.textColor = rowTintColor;
  titleLabel.font = NFBFont(18.0, NFBFontWeightRegular);
  titleLabel.userInteractionEnabled = NO;
  titleLabel.numberOfLines = 0;
  titleLabel.lineBreakMode = NSLineBreakByWordWrapping;

  NSString *subtitle = NFBActionSheetStringValue(action[@"subtitle"]);
  UIStackView *labelStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel]];
  labelStack.translatesAutoresizingMaskIntoConstraints = NO;
  labelStack.axis = UILayoutConstraintAxisVertical;
  labelStack.alignment = UIStackViewAlignmentFill;
  labelStack.spacing = 4.0;
  labelStack.userInteractionEnabled = NO;
  [row addSubview:labelStack];
  if (subtitle.length > 0) {
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = subtitle;
    subtitleLabel.textColor = NFBColorSecondaryText();
    subtitleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    subtitleLabel.userInteractionEnabled = NO;
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [labelStack addArrangedSubview:subtitleLabel];
  }

  NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
    [highlight.topAnchor constraintEqualToAnchor:row.topAnchor],
    [highlight.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
    [highlight.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    [highlight.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    [labelStack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [labelStack.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:12.0],
    [labelStack.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-12.0]
  ]];

  BOOL centered = NFBActionSheetBoolValue(action[@"centered"]);
  NSString *iconName = NFBActionSheetStringValue(action[@"icon"]);
  if (centered) {
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = NFBFont(16.0, NFBFontWeightBold);
    [constraints addObjectsFromArray:@[
      [labelStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:row.leadingAnchor constant:24.0],
      [labelStack.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-24.0],
      [labelStack.centerXAnchor constraintEqualToAnchor:row.centerXAnchor]
    ]];
  } else if (iconName.length > 0) {
    UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = rowTintColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;
    [row addSubview:icon];
    [constraints addObjectsFromArray:@[
      [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:24.0],
      [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
      [icon.widthAnchor constraintEqualToConstant:24.0],
      [icon.heightAnchor constraintEqualToConstant:24.0],
      [labelStack.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:20.0]
    ]];
  } else {
    [constraints addObjectsFromArray:@[
      [labelStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:24.0]
    ]];
  }

  NSString *accessoryIconName = NFBActionSheetBoolValue(action[@"selected"]) ? @"nfb_check" : NFBActionSheetStringValue(action[@"accessoryIcon"]);
  if (!centered && accessoryIconName.length > 0) {
    UIImageView *accessory = [[UIImageView alloc] initWithImage:NFBTemplateIcon(accessoryIconName)];
    accessory.translatesAutoresizingMaskIntoConstraints = NO;
    accessory.tintColor = NFBActionSheetBoolValue(action[@"selected"]) ? NFBColorAccent() : NFBColorSecondaryText();
    accessory.contentMode = UIViewContentModeScaleAspectFit;
    accessory.userInteractionEnabled = NO;
    [row addSubview:accessory];
    [constraints addObjectsFromArray:@[
      [accessory.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-24.0],
      [accessory.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
      [accessory.widthAnchor constraintEqualToConstant:20.0],
      [accessory.heightAnchor constraintEqualToConstant:20.0],
      [labelStack.trailingAnchor constraintLessThanOrEqualToAnchor:accessory.leadingAnchor constant:-18.0]
    ]];
  } else {
    [constraints addObject:[labelStack.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-24.0]];
  }

  [NSLayoutConstraint activateConstraints:constraints];
  return row;
}

- (void)rowTouchDown:(UIControl *)row {
  [self setHighlighted:YES forRow:row];
}

- (void)rowTouchReset:(UIControl *)row {
  [self setHighlighted:NO forRow:row];
}

- (void)setHighlighted:(BOOL)highlighted forRow:(UIControl *)row {
  UIView *highlight = [row viewWithTag:NFBNeoFreeBirdActionSheetRowHighlightTag];
  [UIView animateWithDuration:0.08 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
    highlight.backgroundColor = [NFBIPAModalSheetRowHighlightColor() colorWithAlphaComponent:highlighted ? 1.0 : 0.0];
  } completion:nil];
}

- (void)rowTapped:(UIControl *)row {
  [self setHighlighted:NO forRow:row];
  NSString *identifier = row.accessibilityIdentifier ?: @"";
  NSDictionary<NSString *, id> *selectedAction = nil;
  for (NSDictionary<NSString *, id> *action in self.displayedActions ?: @[]) {
    NSString *actionID = NFBActionSheetStringValue(action[@"id"]);
    if ([actionID isEqualToString:identifier]) {
      selectedAction = action;
      break;
    }
  }
  dispatch_block_t handler = (dispatch_block_t)selectedAction[@"handler"];
  [self dismissThenRun:handler];
}

- (void)cancelTapped {
  [self dismissThenRun:nil];
}

- (void)dismissThenRun:(dispatch_block_t)handler {
  if (self.dismissing) return;
  self.dismissing = YES;
  CGFloat sheetHeight = MAX(260.0, CGRectGetHeight(self.sheetView.bounds));
  [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction animations:^{
    self.backdropButton.alpha = 0.0;
    self.sheetView.alpha = 0.0;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, sheetHeight + 24.0);
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:handler];
  }];
}

@end

@interface NFBNeoFreeBirdRetweetSheetViewController : UIViewController

@property (nonatomic, assign) BOOL reposted;
@property (nonatomic, copy, nullable) dispatch_block_t retweetHandler;
@property (nonatomic, copy, nullable) dispatch_block_t quoteHandler;
@property (nonatomic, strong) UIView *sheetView;

@end

@implementation NFBNeoFreeBirdRetweetSheetViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.clearColor;

  UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
  backdrop.translatesAutoresizingMaskIntoConstraints = NO;
  backdrop.backgroundColor = NFBIPAModalSheetScrimColor();
  backdrop.alpha = 0.0;
  [backdrop addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:backdrop];

  self.sheetView = [[UIView alloc] init];
  self.sheetView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetAppearance(self.sheetView);
  NFBInstallSheetDismissGesture(self.sheetView, backdrop, self, @selector(cancelTapped));
  [self.view addSubview:self.sheetView];

  UIView *grabber = [[UIView alloc] init];
  grabber.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyModalSheetGrabberAppearance(grabber);

  UIView *grabberRow = [[UIView alloc] init];
  grabberRow.translatesAutoresizingMaskIntoConstraints = NO;
  [grabberRow addSubview:grabber];

  UIControl *retweetRow = [self rowWithIconName:@"nfb_retweet"
                                          title:self.reposted ? @"Undo Retweet" : @"Retweet"
                                         action:@selector(retweetTapped)];
  UIControl *quoteRow = [self rowWithIconName:@"nfb_compose_square"
                                        title:@"Quote Tweet"
                                       action:@selector(quoteTapped)];
  UIControl *cancelRow = [self rowWithIconName:nil title:@"Cancel" action:@selector(cancelTapped)];

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[grabberRow, retweetRow, quoteRow, cancelRow]];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 0.0;
  [self.sheetView addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [backdrop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [backdrop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [backdrop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [backdrop.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

    [self.sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.sheetView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:18.0],

    [stack.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0],

    [grabber.widthAnchor constraintEqualToConstant:35.0],
    [grabber.heightAnchor constraintEqualToConstant:5.0],
    [grabber.centerXAnchor constraintEqualToAnchor:grabberRow.centerXAnchor],
    [grabber.topAnchor constraintEqualToAnchor:grabberRow.topAnchor constant:6.0],
    [grabberRow.heightAnchor constraintEqualToConstant:18.0],
    [retweetRow.heightAnchor constraintEqualToConstant:NFBIPAModalSheetRowHeight()],
    [quoteRow.heightAnchor constraintEqualToConstant:NFBIPAModalSheetRowHeight()],
    [cancelRow.heightAnchor constraintEqualToConstant:NFBIPAModalSheetRowHeight()]
  ]];

  self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, 260.0);
  self.sheetView.alpha = 0.0;
  [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    backdrop.alpha = 1.0;
    self.sheetView.alpha = 1.0;
    self.sheetView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (UIControl *)rowWithIconName:(NSString *)iconName title:(NSString *)title action:(SEL)action {
  UIControl *row = [[UIControl alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.backgroundColor = UIColor.clearColor;
  [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

  UIView *highlight = [[UIView alloc] init];
  highlight.translatesAutoresizingMaskIntoConstraints = NO;
  highlight.backgroundColor = [NFBIPAModalSheetRowHighlightColor() colorWithAlphaComponent:0.0];
  highlight.userInteractionEnabled = NO;
  [row addSubview:highlight];

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = title;
  label.textColor = NFBColorText();
  label.font = NFBFont(18.0, NFBFontWeightRegular);
  label.userInteractionEnabled = NO;
  [row addSubview:label];

  NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
    [highlight.topAnchor constraintEqualToAnchor:row.topAnchor],
    [highlight.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
    [highlight.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    [highlight.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-20.0]
  ]];

  if (iconName.length > 0) {
    UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = NFBColorText();
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;
    [row addSubview:icon];
    [constraints addObjectsFromArray:@[
      [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:24.0],
      [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
      [icon.widthAnchor constraintEqualToConstant:24.0],
      [icon.heightAnchor constraintEqualToConstant:24.0],
      [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:20.0]
    ]];
  } else {
    label.textAlignment = NSTextAlignmentCenter;
    [constraints addObjectsFromArray:@[
      [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20.0],
      [label.centerXAnchor constraintEqualToAnchor:row.centerXAnchor]
    ]];
  }
  [NSLayoutConstraint activateConstraints:constraints];
  return row;
}

- (void)dismissThenRun:(dispatch_block_t)handler {
  [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
    self.view.alpha = 0.0;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, 260.0);
  } completion:^(BOOL finished) {
    (void)finished;
    [self dismissViewControllerAnimated:NO completion:handler];
  }];
}

- (void)retweetTapped {
  [self dismissThenRun:self.retweetHandler];
}

- (void)quoteTapped {
  [self dismissThenRun:self.quoteHandler];
}

- (void)cancelTapped {
  [self dismissThenRun:nil];
}

@end

static UIColor *NFBNeoFreeBirdColorFromHex(NSUInteger rgb) {
  return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0
                         green:((rgb >> 8) & 0xff) / 255.0
                          blue:(rgb & 0xff) / 255.0
                         alpha:1.0];
}

static BOOL NFBNeoFreeBirdBoolForKey(NSString *key, BOOL defaultValue) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  return [defaults objectForKey:key] ? [defaults boolForKey:key] : defaultValue;
}

static NSArray<NSString *> *NFBNeoFreeBirdPageIDsFromArchive(NSString *key) {
  id savedItems = [NSUserDefaults.standardUserDefaults objectForKey:key];
  if (![savedItems isKindOfClass:NSData.class]) return @[];

  NSArray *items = nil;
  @try {
    items = [NSKeyedUnarchiver unarchiveObjectWithData:savedItems];
  } @catch (NSException *exception) {
    (void)exception;
    return @[];
  }

  if (![items isKindOfClass:NSArray.class]) return @[];

  NSMutableArray<NSString *> *pageIDs = [NSMutableArray array];
  for (id item in items) {
    NSString *pageID = nil;
    if ([item respondsToSelector:@selector(pageID)]) {
      pageID = [item valueForKey:@"pageID"];
    } else if ([item isKindOfClass:NSDictionary.class]) {
      pageID = item[@"pageID"];
    } else if ([item isKindOfClass:NSString.class]) {
      pageID = item;
    }
    if ([pageID isKindOfClass:NSString.class] && pageID.length > 0) {
      [pageIDs addObject:pageID];
    }
  }
  return pageIDs;
}

static NFBNeoFreeBirdTabDefinition *NFBNeoFreeBirdTab(NSString *pageID, NSString *title, NSString *iconName, NSString *selectedIconName) {
  return [[NFBNeoFreeBirdTabDefinition alloc] initWithPageID:pageID title:title iconName:iconName selectedIconName:selectedIconName];
}

static NSDictionary<NSString *, NFBNeoFreeBirdTabDefinition *> *NFBNeoFreeBirdTabDefinitionsByPageID(void) {
  static NSDictionary<NSString *, NFBNeoFreeBirdTabDefinition *> *definitions = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    definitions = @{
      @"home": NFBNeoFreeBirdTab(@"home", @"Home", @"nfb_tab_home", @"nfb_tab_home_selected"),
      @"guide": NFBNeoFreeBirdTab(@"guide", @"Explore", @"nfb_tab_guide", @"nfb_tab_guide_selected"),
      @"grok": NFBNeoFreeBirdTab(@"grok", @"Grok", @"nfb_tab_grok", @"nfb_tab_grok_selected"),
      @"audiospace": NFBNeoFreeBirdTab(@"audiospace", @"Spaces", @"nfb_tab_audiospace", @"nfb_tab_audiospace_selected"),
      @"communities": NFBNeoFreeBirdTab(@"communities", @"Communities", @"nfb_tab_communities", @"nfb_tab_communities_selected"),
      @"ntab": NFBNeoFreeBirdTab(@"ntab", @"Notifications", @"nfb_tab_ntab", @"nfb_tab_ntab_selected"),
      @"messages": NFBNeoFreeBirdTab(@"messages", @"Messages", @"nfb_tab_messages", @"nfb_tab_messages_selected"),
      @"profile": NFBNeoFreeBirdTab(@"profile", @"Profile", @"nfb_tab_profile", @"nfb_tab_profile_selected"),
      @"media": NFBNeoFreeBirdTab(@"media", @"Video", @"nfb_tab_media", @"nfb_tab_media_selected")
    };
  });
  return definitions;
}

static NSArray<NSString *> *NFBNeoFreeBirdDefaultVisiblePageIDs(void) {
  return @[@"home", @"guide", @"ntab", @"messages"];
}

static NSArray<NSString *> *NFBNeoFreeBirdCanonicalPageOrder(void) {
  return @[@"home", @"guide", @"grok", @"audiospace", @"communities", @"ntab", @"messages", @"profile", @"media"];
}

static NSSet<NSString *> *NFBNeoFreeBirdSuppressedTabPageIDs(void) {
  return [NSSet setWithArray:@[@"grok", @"audiospace"]];
}

void NFBApplyNeoFreeBirdFirstRunDefaults(void) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  if (![defaults objectForKey:@"FirstRun_4.3"]) {
    [defaults setValue:@"1strun" forKey:@"FirstRun_4.3"];
    NSArray<NSString *> *enabledKeys = @[
      @"dw_v",
      @"hide_promoted",
      @"voice",
      @"undo_tweet",
      @"TrustedFriends",
      @"disableSensitiveTweetWarnings",
      @"disable_immersive_player",
      @"custom_voice_upload",
      @"hide_premium_offer",
      @"disableMediaTab",
      @"disableArticles",
      @"disableHighlights",
      @"hide_view_count",
      @"hide_grok_analyze",
      @"restore_reply_context",
      @"disable_xchat",
      @"hide_topics",
      @"hide_topics_to_follow",
      @"hide_who_to_follow",
      @"no_tab_bar_hiding"
    ];
    for (NSString *key in enabledKeys) {
      [defaults setBool:YES forKey:key];
    }
  }

  if (![defaults objectForKey:@"color_twitter_icon_in_top_bar"]) {
    [defaults setBool:YES forKey:@"color_twitter_icon_in_top_bar"];
  }
  if (![defaults objectForKey:@"nfb_default_blue_migration_v1"]) {
    BOOL userSelectedColor = [defaults objectForKey:@"bh_last_selected_color_theme"] != nil;
    if (!userSelectedColor) {
      [defaults setInteger:1 forKey:@"bh_color_theme_selectedColor"];
      [defaults setInteger:1 forKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    }
    [defaults setBool:YES forKey:@"nfb_default_blue_migration_v1"];
  }
  [defaults synchronize];
}

UIColor *NFBNeoFreeBirdAccentColor(void) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  NSInteger colorID = 1;
  if ([defaults objectForKey:@"bh_color_theme_selectedColor"]) {
    colorID = [defaults integerForKey:@"bh_color_theme_selectedColor"];
  } else if ([defaults objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"]) {
    colorID = [defaults integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
  }

  switch (colorID) {
    case 1: return NFBNeoFreeBirdColorFromHex(0x1d9bf0);
    case 2: return NFBNeoFreeBirdColorFromHex(0xffd400);
    case 3: return NFBNeoFreeBirdColorFromHex(0xf91880);
    case 4: return NFBNeoFreeBirdColorFromHex(0x7856ff);
    case 5: return NFBNeoFreeBirdColorFromHex(0xff7a00);
    case 6: return NFBNeoFreeBirdColorFromHex(0x00ba7c);
    default: return NFBNeoFreeBirdColorFromHex(0x1d9bf0);
  }
}

UIColor *NFBNeoFreeBirdTabBarSelectedTintColor(void) {
  return NFBNeoFreeBirdBoolForKey(@"tab_bar_theming", NO) ? NFBNeoFreeBirdAccentColor() : NFBColorText();
}

UIColor *NFBNeoFreeBirdTabBarNormalTintColor(void) {
  return NFBColorSecondaryText();
}

BOOL NFBNeoFreeBirdRestoreTabLabels(void) {
  return NFBNeoFreeBirdBoolForKey(@"restore_tab_labels", NO);
}

BOOL NFBNeoFreeBirdColorTopBirdIcon(void) {
  return NFBNeoFreeBirdBoolForKey(@"color_twitter_icon_in_top_bar", YES);
}

BOOL NFBNeoFreeBirdHideViewCount(void) {
  return NFBNeoFreeBirdBoolForKey(@"hide_view_count", YES);
}

NSArray<NFBNeoFreeBirdTabDefinition *> *NFBNeoFreeBirdVisibleTabDefinitions(void) {
  NSDictionary<NSString *, NFBNeoFreeBirdTabDefinition *> *byPageID = NFBNeoFreeBirdTabDefinitionsByPageID();
  NSArray<NSString *> *allowed = NFBNeoFreeBirdPageIDsFromArchive(@"allowed");
  NSArray<NSString *> *hidden = NFBNeoFreeBirdPageIDsFromArchive(@"hidden");
  NSMutableSet<NSString *> *hiddenSet = [NSMutableSet setWithArray:hidden];
  [hiddenSet unionSet:NFBNeoFreeBirdSuppressedTabPageIDs()];

  NSArray<NSString *> *pageIDs = allowed.count > 0 ? allowed : NFBNeoFreeBirdDefaultVisiblePageIDs();
  if (allowed.count == 0 && hidden.count > 0) pageIDs = NFBNeoFreeBirdCanonicalPageOrder();

  NSMutableArray<NFBNeoFreeBirdTabDefinition *> *tabs = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  for (NSString *pageID in pageIDs) {
    if ([hiddenSet containsObject:pageID]) continue;
    if ([seen containsObject:pageID]) continue;
    NFBNeoFreeBirdTabDefinition *definition = byPageID[pageID];
    if (!definition) continue;
    [tabs addObject:definition];
    [seen addObject:pageID];
  }
  return tabs.count > 0 ? tabs : @[byPageID[@"home"], byPageID[@"guide"], byPageID[@"ntab"], byPageID[@"messages"]];
}

void NFBPresentNeoFreeBirdRetweetSheet(UIViewController *presenter,
                                       BOOL reposted,
                                       dispatch_block_t retweetHandler,
                                       dispatch_block_t quoteHandler) {
  if (!presenter) return;
  NFBNeoFreeBirdRetweetSheetViewController *sheet = [[NFBNeoFreeBirdRetweetSheetViewController alloc] init];
  sheet.reposted = reposted;
  sheet.retweetHandler = retweetHandler;
  sheet.quoteHandler = quoteHandler;
  sheet.modalPresentationStyle = UIModalPresentationOverFullScreen;
  sheet.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  [presenter presentViewController:sheet animated:NO completion:nil];
}

void NFBPresentNeoFreeBirdActionSheet(UIViewController *presenter,
                                      NSArray<NSDictionary<NSString *, id> *> *actions,
                                      NSString *cancelTitle) {
  NFBPresentNeoFreeBirdMenuSheet(presenter, nil, nil, actions, cancelTitle);
}

void NFBPresentNeoFreeBirdMenuSheet(UIViewController *presenter,
                                    NSString *title,
                                    NSString *subtitle,
                                    NSArray<NSDictionary<NSString *, id> *> *actions,
                                    NSString *cancelTitle) {
  if (!presenter) return;
  NFBNeoFreeBirdActionSheetViewController *sheet = [[NFBNeoFreeBirdActionSheetViewController alloc] init];
  sheet.titleText = title;
  sheet.subtitleText = subtitle;
  sheet.actions = actions ?: @[];
  sheet.cancelTitle = cancelTitle;
  sheet.modalPresentationStyle = UIModalPresentationOverFullScreen;
  sheet.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  [presenter presentViewController:sheet animated:NO completion:nil];
}
