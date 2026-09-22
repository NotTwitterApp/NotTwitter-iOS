#import "NFBSearchPagingScrollView.h"
#import "NFBSearchPagingPolicy.h"
#import "NFBAdvancedSearchViewController.h"
#import "NFBSearchQuery.h"
#import "NFBSearchOptions.h"
#import "NFBSearchResultFilter.h"
#import "NFBActorCell.h"
#import "NFBRepostContext.h"
#import "NFBChatPermission.h"
#import "NFBTimelineViewController.h"
#import "NFBFeedRoute.h"
#import "NFBBookmarkSearch.h"

#import "NFBAtprotoClient.h"
#import "NFBActorListViewController.h"
#import "NFBAtprotoSession.h"
#import "NFBAccountAvatar.h"
#import "NFBBlueskyLoginViewController.h"
#import "NFBComposeViewController.h"
#import "NFBLinkRouter.h"
#import "NFBNeoFreeBirdUI.h"
#import "NFBNotificationCoordinator.h"
#import "NFBPostActionCoordinator.h"
#import "NFBPostCell.h"
#import "NFBProfilePresentation.h"
#import "NFBGesturePolicy.h"
#import "NFBSearchTypeaheadViewController.h"
#import "NFBSettingsViewController.h"
#import "NFBSideMenuViewController.h"
#import "NFBTheme.h"
#import "NFBMediaViewerViewController.h"
#import "NFBMessagesViewController.h"
#import "NFBTweetDetailViewController.h"

#import <SafariServices/SafariServices.h>
#import <QuartzCore/QuartzCore.h>

static NSInteger const NFBProfileTabUnderlineTag = 74017;
static NSString * const NFBDismissedNotificationActivityGroupsDefaultsKey = @"nfb_dismissed_notification_activity_groups";
static NSString * const NFBPositiveNotificationActivityGroupsDefaultsKey = @"nfb_positive_notification_activity_groups";
static NSString * const NFBNotificationAdvancedFiltersDidChangeNotification = @"NFBNotificationAdvancedFiltersDidChangeNotification";
static NSString * const NFBNotificationFilterQualityKey = @"nfb_notification_filter_quality";
static NSString * const NFBNotificationFilterYouDoNotFollowKey = @"nfb_notification_filter_you_do_not_follow";
static NSString * const NFBNotificationFilterNotFollowingYouKey = @"nfb_notification_filter_not_following_you";
static NSString * const NFBNotificationFilterNewAccountsKey = @"nfb_notification_filter_new_accounts";
static NSString * const NFBNotificationFilterDefaultAvatarKey = @"nfb_notification_filter_default_avatar";

@interface NFBProfileResourceCell : UITableViewCell
- (void)configureWithItem:(NSDictionary *)item;
@end

@interface NFBProfileResourceCell ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIView *bottomBorder;
@property (nonatomic, copy) NSString *imageURLString;
@end

@implementation NFBProfileResourceCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) [self buildSubviews];
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.imageURLString = nil;
  self.iconView.image = nil;
  self.titleLabel.text = nil;
  self.subtitleLabel.text = nil;
  self.descriptionLabel.text = nil;
  [self applyTheme];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

  self.iconView = [[UIImageView alloc] init];
  self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.iconView.contentMode = UIViewContentModeScaleAspectFill;
  self.iconView.clipsToBounds = YES;
  self.iconView.layer.cornerRadius = 12.0;

  self.titleLabel = [[UILabel alloc] init];
  self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.titleLabel.numberOfLines = 1;
  self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.subtitleLabel = [[UILabel alloc] init];
  self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.subtitleLabel.font = NFBFont(14.0, NFBFontWeightRegular);
  self.subtitleLabel.numberOfLines = 1;
  self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.descriptionLabel = [[UILabel alloc] init];
  self.descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.descriptionLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.descriptionLabel.numberOfLines = 2;
  self.descriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel, self.descriptionLabel]];
  textStack.translatesAutoresizingMaskIntoConstraints = NO;
  textStack.axis = UILayoutConstraintAxisVertical;
  textStack.alignment = UIStackViewAlignmentFill;
  textStack.spacing = 1.0;

  self.bottomBorder = [[UIView alloc] init];
  self.bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;

  [self.contentView addSubview:self.iconView];
  [self.contentView addSubview:textStack];
  [self.contentView addSubview:self.bottomBorder];

  [NSLayoutConstraint activateConstraints:@[
    [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
    [self.iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
    [self.iconView.widthAnchor constraintEqualToConstant:56.0],
    [self.iconView.heightAnchor constraintEqualToConstant:56.0],
    [textStack.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:12.0],
    [textStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
    [textStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
    [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
    [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:82.0],
    [self.bottomBorder.leadingAnchor constraintEqualToAnchor:textStack.leadingAnchor],
    [self.bottomBorder.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
    [self.bottomBorder.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  [self applyTheme];
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.iconView.backgroundColor = NFBColorElevatedBackground();
  self.titleLabel.textColor = NFBColorText();
  self.subtitleLabel.textColor = NFBColorSecondaryText();
  self.descriptionLabel.textColor = NFBColorText();
  NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);
}

- (void)configureWithItem:(NSDictionary *)item {
  [self applyTheme];
  NSDictionary *resource = [item[@"resource"] isKindOfClass:NSDictionary.class] ? item[@"resource"] : @{};
  NSDictionary *record = [resource[@"record"] isKindOfClass:NSDictionary.class] ? resource[@"record"] : @{};
  NSDictionary *creator = [resource[@"creator"] isKindOfClass:NSDictionary.class] ? resource[@"creator"] : @{};
  NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"list";

  NSString *title = [resource[@"name"] isKindOfClass:NSString.class] ? resource[@"name"] : nil;
  if (title.length == 0) title = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : nil;
  if (title.length == 0) title = [resource[@"displayName"] isKindOfClass:NSString.class] ? resource[@"displayName"] : nil;
  self.titleLabel.text = title.length > 0 ? title : ([type isEqualToString:@"starterPack"] ? @"Starter Pack" : ([type isEqualToString:@"feed"] ? @"Feed" : @"List"));

  NSString *description = [resource[@"description"] isKindOfClass:NSString.class] ? resource[@"description"] : nil;
  if (description.length == 0) description = [record[@"description"] isKindOfClass:NSString.class] ? record[@"description"] : nil;
  self.descriptionLabel.text = description ?: @"";
  self.descriptionLabel.hidden = description.length == 0;

  self.subtitleLabel.text = [self subtitleForResource:resource record:record type:type];

  NSString *avatar = [resource[@"avatar"] isKindOfClass:NSString.class] ? resource[@"avatar"] : nil;
  if (avatar.length == 0) avatar = [creator[@"avatar"] isKindOfClass:NSString.class] ? creator[@"avatar"] : nil;
  [self loadImageURL:avatar type:type];
}

- (NSString *)subtitleForResource:(NSDictionary *)resource record:(NSDictionary *)record type:(NSString *)type {
  if ([type isEqualToString:@"feed"]) {
    NSDictionary *creator = [resource[@"creator"] isKindOfClass:NSDictionary.class] ? resource[@"creator"] : @{};
    NSString *handle = [NFBAtprotoClient displayHandleForProfile:creator];
    NSNumber *likes = [resource[@"likeCount"] respondsToSelector:@selector(integerValue)] ? resource[@"likeCount"] : nil;
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:@"Feed"];
    if (handle.length > 0) [parts addObject:[@"@" stringByAppendingString:handle]];
    if (likes.integerValue > 0) [parts addObject:[NSString stringWithFormat:@"%@ likes", NFBShortCountString(likes.integerValue)]];
    if ([resource[@"_nfbSavedFeedSaved"] boolValue]) [parts addObject:@"Saved"];
    return [parts componentsJoinedByString:@" · "];
  }

  if ([type isEqualToString:@"starterPack"]) {
    NSNumber *accounts = [resource[@"listItemCount"] respondsToSelector:@selector(integerValue)] ? resource[@"listItemCount"] : nil;
    if (!accounts) accounts = [resource[@"joinedAllTimeCount"] respondsToSelector:@selector(integerValue)] ? resource[@"joinedAllTimeCount"] : nil;
    NSNumber *feeds = [resource[@"feedCount"] respondsToSelector:@selector(integerValue)] ? resource[@"feedCount"] : nil;
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:@"Starter Pack"];
    if (accounts.integerValue > 0) [parts addObject:[NSString stringWithFormat:@"%@ %@", NFBShortCountString(accounts.integerValue), accounts.integerValue == 1 ? @"account" : @"accounts"]];
    if (feeds.integerValue > 0) [parts addObject:[NSString stringWithFormat:@"%@ %@", NFBShortCountString(feeds.integerValue), feeds.integerValue == 1 ? @"feed" : @"feeds"]];
    return [parts componentsJoinedByString:@" · "];
  }

  NSString *purpose = [resource[@"purpose"] isKindOfClass:NSString.class] ? resource[@"purpose"] : [record[@"purpose"] isKindOfClass:NSString.class] ? record[@"purpose"] : @"";
  NSString *label = [purpose hasSuffix:@"#modlist"] ? @"Block List" : @"Follow List";
  if ([resource[@"_nfbViewerMuted"] boolValue]) label = @"Muted List";
  if ([resource[@"_nfbViewerBlocked"] boolValue]) label = @"Blocked List";
  NSNumber *count = [resource[@"listItemCount"] respondsToSelector:@selector(integerValue)] ? resource[@"listItemCount"] : nil;
  if (count.integerValue > 0) return [NSString stringWithFormat:@"%@ · %@ %@", label, NFBShortCountString(count.integerValue), count.integerValue == 1 ? @"account" : @"accounts"];
  return label;
}

- (void)loadImageURL:(NSString *)urlString type:(NSString *)type {
  self.imageURLString = urlString;
  if (urlString.length == 0) {
    self.iconView.contentMode = UIViewContentModeCenter;
    self.iconView.tintColor = NFBColorSecondaryText();
    self.iconView.image = NFBTemplateIcon([type isEqualToString:@"starterPack"] ? @"nfb_people" : ([type isEqualToString:@"feed"] ? @"nfb_hash" : @"nfb_lists"));
    return;
  }

  self.iconView.contentMode = UIViewContentModeScaleAspectFill;
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.imageURLString isEqualToString:urlString]) self.iconView.image = image;
    });
  }] resume];
}

@end

@interface NFBTrendCell : UITableViewCell
- (void)configureWithTrend:(NSDictionary *)trend;
@end

@interface NFBTrendCell ()
@property (nonatomic, strong) UILabel *contextLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIView *bottomBorder;
@end

@implementation NFBTrendCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) [self buildSubviews];
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.contextLabel.text = nil;
  self.titleLabel.text = nil;
  self.descriptionLabel.text = nil;
  self.descriptionLabel.hidden = NO;
  [self applyTheme];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

  self.contextLabel = [[UILabel alloc] init];
  self.contextLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.contextLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  self.contextLabel.numberOfLines = 1;
  self.contextLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.titleLabel = [[UILabel alloc] init];
  self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleLabel.font = NFBFont(15.0, NFBFontWeightHeavy);
  self.titleLabel.numberOfLines = 1;
  self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.descriptionLabel = [[UILabel alloc] init];
  self.descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.descriptionLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  self.descriptionLabel.numberOfLines = 2;
  self.descriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.contextLabel, self.titleLabel, self.descriptionLabel]];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 3.0;

  self.bottomBorder = [[UIView alloc] init];
  self.bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;

  [self.contentView addSubview:stack];
  [self.contentView addSubview:self.bottomBorder];

  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
    [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
    [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
    [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
    [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:74.0],
    [self.bottomBorder.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
    [self.bottomBorder.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
    [self.bottomBorder.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  [self applyTheme];
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.contextLabel.textColor = NFBColorSecondaryText();
  self.titleLabel.textColor = NFBColorText();
  self.descriptionLabel.textColor = NFBColorSecondaryText();
  NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);
}

- (void)configureWithTrend:(NSDictionary *)trend {
  [self applyTheme];
  NSString *kind = [trend[@"kind"] isKindOfClass:NSString.class] ? trend[@"kind"] : @"topic";
  NSString *category = [trend[@"category"] isKindOfClass:NSString.class] ? trend[@"category"] : @"";
  if ([kind isEqualToString:@"suggested"]) {
    self.contextLabel.text = @"Suggested feed";
  } else {
    self.contextLabel.text = category.length > 0 ? [NSString stringWithFormat:@"%@ · Trending", category] : @"Trending";
  }
  NSString *displayName = [trend[@"displayName"] isKindOfClass:NSString.class] ? trend[@"displayName"] : @"";
  NSString *name = [trend[@"name"] isKindOfClass:NSString.class] ? trend[@"name"] : @"";
  self.titleLabel.text = displayName.length > 0 ? displayName : (name.length > 0 ? name : @"Trending");
  NSString *description = [trend[@"description"] isKindOfClass:NSString.class] ? trend[@"description"] : @"";
  self.descriptionLabel.text = description.length > 0 ? description : ([kind isEqualToString:@"suggested"] ? @"Suggested feed" : @"");
  self.descriptionLabel.hidden = self.descriptionLabel.text.length == 0;
}

@end

@interface NFBNotificationActivityCell : UITableViewCell
@property (nonatomic, strong, readonly) UIButton *moreButton;
@property (nonatomic, strong, readonly) UIButton *positiveFeedbackButton;
@property (nonatomic, strong, readonly) UIButton *negativeFeedbackButton;
- (void)configureWithGroup:(NSDictionary *)group;
@end

@interface NFBNotificationActivityCell ()
@property (nonatomic, strong) UIImageView *reasonIconView;
@property (nonatomic, strong) UIStackView *avatarStack;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong, readwrite) UIButton *moreButton;
@property (nonatomic, strong, readwrite) UIButton *positiveFeedbackButton;
@property (nonatomic, strong, readwrite) UIButton *negativeFeedbackButton;
@property (nonatomic, strong) UIView *unreadDot;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UIView *bottomBorder;
@end

@implementation NFBNotificationActivityCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) [self buildSubviews];
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  for (UIView *view in self.avatarStack.arrangedSubviews) {
    [self.avatarStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  self.previewLabel.text = nil;
  self.summaryLabel.text = nil;
  [self.moreButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
  [self.positiveFeedbackButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
  [self.negativeFeedbackButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
  [self applyTheme];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleDefault);

  self.reasonIconView = [[UIImageView alloc] init];
  self.reasonIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.reasonIconView.contentMode = UIViewContentModeScaleAspectFit;
  [self.reasonIconView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.reasonIconView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.avatarStack = [[UIStackView alloc] init];
  self.avatarStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarStack.axis = UILayoutConstraintAxisHorizontal;
  self.avatarStack.alignment = UIStackViewAlignmentCenter;
  self.avatarStack.spacing = -8.0;

  self.unreadDot = [[UIView alloc] init];
  self.unreadDot.translatesAutoresizingMaskIntoConstraints = NO;
  self.unreadDot.layer.cornerRadius = 4.0;

  self.timeLabel = [[UILabel alloc] init];
  self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.timeLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  self.timeLabel.numberOfLines = 1;
  [self.timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.moreButton.accessibilityLabel = @"More";
  self.moreButton.tintColor = NFBColorSecondaryText();
  [self.moreButton setImage:NFBTemplateIcon(@"nfb_more") forState:UIControlStateNormal];
  self.moreButton.imageEdgeInsets = UIEdgeInsetsMake(7.0, 7.0, 7.0, 7.0);
  [self.moreButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.moreButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.positiveFeedbackButton = [self feedbackButtonWithIcon:@"nfb_check" accessibilityLabel:@"Show more like this"];
  self.negativeFeedbackButton = [self feedbackButtonWithIcon:@"nfb_close" accessibilityLabel:@"Show less like this"];
  self.positiveFeedbackButton.hidden = YES;
  self.negativeFeedbackButton.hidden = YES;
  self.moreButton.hidden = YES;

  UIStackView *statusRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.unreadDot, self.timeLabel]];
  statusRow.translatesAutoresizingMaskIntoConstraints = NO;
  statusRow.axis = UILayoutConstraintAxisHorizontal;
  statusRow.alignment = UIStackViewAlignmentCenter;
  statusRow.spacing = 5.0;

  UIView *topRow = [[UIView alloc] init];
  topRow.translatesAutoresizingMaskIntoConstraints = NO;
  [topRow addSubview:self.avatarStack];
  [topRow addSubview:statusRow];

  self.summaryLabel = [[UILabel alloc] init];
  self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.summaryLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.summaryLabel.numberOfLines = 0;
  self.summaryLabel.lineBreakMode = NSLineBreakByWordWrapping;

  self.previewLabel = [[UILabel alloc] init];
  self.previewLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.previewLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.previewLabel.numberOfLines = 3;
  self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIStackView *contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[topRow, self.summaryLabel, self.previewLabel]];
  contentStack.translatesAutoresizingMaskIntoConstraints = NO;
  contentStack.axis = UILayoutConstraintAxisVertical;
  contentStack.alignment = UIStackViewAlignmentFill;
  contentStack.spacing = 5.0;

  self.bottomBorder = [[UIView alloc] init];
  self.bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;

  [self.contentView addSubview:self.reasonIconView];
  [self.contentView addSubview:contentStack];
  [self.contentView addSubview:self.bottomBorder];

  [NSLayoutConstraint activateConstraints:@[
    [self.reasonIconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
    [self.reasonIconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:17.0],
    [self.reasonIconView.widthAnchor constraintEqualToConstant:24.0],
    [self.reasonIconView.heightAnchor constraintEqualToConstant:24.0],
    [contentStack.leadingAnchor constraintEqualToAnchor:self.reasonIconView.trailingAnchor constant:13.0],
    [contentStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
    [contentStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10.0],
    [contentStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],
    [topRow.heightAnchor constraintGreaterThanOrEqualToConstant:28.0],
    [self.avatarStack.leadingAnchor constraintEqualToAnchor:topRow.leadingAnchor],
    [self.avatarStack.centerYAnchor constraintEqualToAnchor:topRow.centerYAnchor],
    [self.avatarStack.trailingAnchor constraintLessThanOrEqualToAnchor:statusRow.leadingAnchor constant:-12.0],
    [statusRow.trailingAnchor constraintEqualToAnchor:topRow.trailingAnchor],
    [statusRow.centerYAnchor constraintEqualToAnchor:topRow.centerYAnchor],
    [self.unreadDot.widthAnchor constraintEqualToConstant:8.0],
    [self.unreadDot.heightAnchor constraintEqualToConstant:8.0],
    [self.bottomBorder.leadingAnchor constraintEqualToAnchor:contentStack.leadingAnchor],
    [self.bottomBorder.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
    [self.bottomBorder.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];

  UIView *selectedView = [[UIView alloc] init];
  selectedView.backgroundColor = NFBIPATableCellSelectedBackgroundColor();
  self.selectedBackgroundView = selectedView;
  [self applyTheme];
}

- (UIButton *)feedbackButtonWithIcon:(NSString *)iconName accessibilityLabel:(NSString *)accessibilityLabel {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.accessibilityLabel = accessibilityLabel;
  button.tintColor = NFBColorSecondaryText();
  [button setImage:NFBTemplateIcon(iconName) forState:UIControlStateNormal];
  button.imageEdgeInsets = UIEdgeInsetsMake(8.0, 8.0, 8.0, 8.0);
  [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  return button;
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleDefault);
  self.summaryLabel.textColor = NFBColorText();
  self.previewLabel.textColor = NFBColorSecondaryText();
  self.timeLabel.textColor = NFBColorSecondaryText();
  self.moreButton.tintColor = NFBColorSecondaryText();
  self.positiveFeedbackButton.tintColor = self.positiveFeedbackButton.isSelected ? NFBColorAccent() : NFBColorSecondaryText();
  self.negativeFeedbackButton.tintColor = NFBColorSecondaryText();
  self.unreadDot.backgroundColor = NFBColorAccent();
  NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);
  self.reasonIconView.alpha = 1.0;
}

- (void)configureWithGroup:(NSDictionary *)group {
  [self applyTheme];
  NSString *reason = [group[@"reason"] isKindOfClass:NSString.class] ? group[@"reason"] : @"";
  self.reasonIconView.image = NFBTemplateIcon([self iconNameForReason:reason]);
  self.reasonIconView.tintColor = [self tintColorForReason:reason];

  BOOL isRead = [group[@"isRead"] respondsToSelector:@selector(boolValue)] ? [group[@"isRead"] boolValue] : YES;
  self.unreadDot.hidden = isRead;
  self.contentView.backgroundColor = isRead ? NFBColorBackground() : [NFBColorAccent() colorWithAlphaComponent:0.07];
  self.positiveFeedbackButton.selected = [group[@"positiveFeedback"] respondsToSelector:@selector(boolValue)] && [group[@"positiveFeedback"] boolValue];
  self.positiveFeedbackButton.tintColor = self.positiveFeedbackButton.isSelected ? NFBColorAccent() : NFBColorSecondaryText();

  NSArray *users = [group[@"users"] isKindOfClass:NSArray.class] ? group[@"users"] : @[];
  for (NSUInteger index = 0; index < MIN(users.count, (NSUInteger)5); index++) {
    NSDictionary *profile = [users[index] isKindOfClass:NSDictionary.class] ? users[index] : @{};
    UIImageView *avatar = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage() ?: NFBBrandIconImage()];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    avatar.layer.cornerRadius = 14.0;
    avatar.layer.borderWidth = 1.5;
    avatar.layer.borderColor = NFBColorBackground().CGColor;

    [self.avatarStack addArrangedSubview:avatar];
    [NSLayoutConstraint activateConstraints:@[
      [avatar.widthAnchor constraintEqualToConstant:28.0],
      [avatar.heightAnchor constraintEqualToConstant:28.0]
    ]];
    [self loadAvatarURL:[NFBAtprotoClient avatarURLForProfile:profile] intoImageView:avatar];
  }

  self.summaryLabel.attributedText = [self summaryTextForGroup:group];
  NSString *preview = [group[@"text"] isKindOfClass:NSString.class] ? group[@"text"] : @"";
  self.previewLabel.text = preview;
  self.previewLabel.hidden = preview.length == 0;
  self.timeLabel.text = [NFBAtprotoClient relativeTimeForPost:@{@"indexedAt": [group[@"createdAt"] isKindOfClass:NSString.class] ? group[@"createdAt"] : @""}];
  self.isAccessibilityElement = YES;
  self.accessibilityTraits = UIAccessibilityTraitButton;
  NSMutableArray<NSString *> *accessibilityParts = [NSMutableArray array];
  NSString *summary = self.summaryLabel.attributedText.string ?: @"";
  if (summary.length > 0) [accessibilityParts addObject:summary];
  if (preview.length > 0) [accessibilityParts addObject:preview];
  if (self.timeLabel.text.length > 0) [accessibilityParts addObject:self.timeLabel.text];
  self.accessibilityLabel = [accessibilityParts componentsJoinedByString:@", "];
  BOOL profileRoute = [reason isEqualToString:@"follow"] || [reason isEqualToString:@"starterpack-joined"];
  if (profileRoute && users.count > 1) self.accessibilityHint = @"Displays users in a list";
  else if (profileRoute) self.accessibilityHint = @"";
  else self.accessibilityHint = @"Opens this Tweet";
}

- (NSString *)iconNameForReason:(NSString *)reason {
  if ([reason isEqualToString:@"like"]) return @"nfb_like_filled";
  if ([reason isEqualToString:@"repost"]) return @"nfb_retweet";
  if ([reason isEqualToString:@"follow"] || [reason isEqualToString:@"starterpack-joined"]) return @"nfb_profile";
  return @"nfb_notifications";
}

- (UIColor *)tintColorForReason:(NSString *)reason {
  if ([reason isEqualToString:@"like"]) return [UIColor colorWithRed:0.976 green:0.094 blue:0.502 alpha:1.0];
  if ([reason isEqualToString:@"repost"]) return [UIColor colorWithRed:0.0 green:0.729 blue:0.486 alpha:1.0];
  return NFBColorAccent();
}

- (BOOL)notificationTargetIsReplyForGroup:(NSDictionary *)group {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:group];
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  return [record[@"reply"] isKindOfClass:NSDictionary.class];
}

- (NSString *)actionTextForGroup:(NSDictionary *)group {
  NSString *reason = [group[@"reason"] isKindOfClass:NSString.class] ? group[@"reason"] : @"";
  BOOL targetIsReply = [self notificationTargetIsReplyForGroup:group];
  if ([reason isEqualToString:@"like"]) return targetIsReply ? @"liked your reply" : @"liked your Tweet";
  if ([reason isEqualToString:@"repost"]) return targetIsReply ? @"Retweeted your reply" : @"Retweeted your Tweet";
  if ([reason isEqualToString:@"follow"]) return @"followed you";
  if ([reason isEqualToString:@"starterpack-joined"]) return @"joined from your Starter Pack";
  return @"interacted with you";
}

- (NSAttributedString *)summaryTextForGroup:(NSDictionary *)group {
  NSArray *users = [group[@"users"] isKindOfClass:NSArray.class] ? group[@"users"] : @[];
  NSDictionary *firstUser = [users.firstObject isKindOfClass:NSDictionary.class] ? users.firstObject : @{};
  NSDictionary *secondUser = users.count == 2 && [users[1] isKindOfClass:NSDictionary.class] ? users[1] : nil;
  NSString *firstName = [NFBAtprotoClient displayNameForProfile:firstUser];
  NSString *action = [self actionTextForGroup:group];

  NSMutableString *plain = [NSMutableString stringWithString:firstName.length > 0 ? firstName : @"Someone"];
  if (secondUser) {
    [plain appendFormat:@" and %@", [NFBAtprotoClient displayNameForProfile:secondUser]];
  } else if (users.count > 1) {
    [plain appendFormat:@" and %lu others", (unsigned long)(users.count - 1)];
  }
  [plain appendFormat:@" %@", action];

  NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:plain attributes:@{
    NSForegroundColorAttributeName: NFBColorText(),
    NSFontAttributeName: NFBFont(15.0, NFBFontWeightRegular)
  }];
  if (firstName.length > 0) {
    [text addAttributes:@{NSFontAttributeName: NFBFont(15.0, NFBFontWeightBold)} range:[plain rangeOfString:firstName]];
  }
  if (secondUser) {
    NSString *secondName = [NFBAtprotoClient displayNameForProfile:secondUser];
    if (secondName.length > 0) [text addAttributes:@{NSFontAttributeName: NFBFont(15.0, NFBFontWeightBold)} range:[plain rangeOfString:secondName]];
  }
  return text;
}

- (void)loadAvatarURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
  if (urlString.length == 0) return;
  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    imageView.image = cached;
    return;
  }
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    [[self.class imageCache] setObject:image forKey:urlString];
    dispatch_async(dispatch_get_main_queue(), ^{
      imageView.image = image;
    });
  }] resume];
}

+ (NSCache *)imageCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 120;
  });
  return cache;
}

@end

@interface NFBTimelineViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchBarDelegate, UIContextMenuInteractionDelegate, NFBActorCellDelegate, UIGestureRecognizerDelegate, NFBPostCellDelegate, NFBSearchTypeaheadViewControllerDelegate, NFBMediaViewerViewControllerDelegate>

@property (nonatomic, assign) NFBTimelineKind kind;
@property (nonatomic, copy, nullable) NSString *actor;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, assign) BOOL refreshSuccessSoundPending;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *bookmarkItems;
@property (nonatomic, copy, nullable) NSString *cursor;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic) NFBSearchTab searchTab;
@property (nonatomic) BOOL searchFollowingOnly;
@property (nonatomic) NSUInteger searchEmptyPageCount;
@property (nonatomic, strong) UISearchBar *searchResultsBar;
@property (nonatomic, strong) UIView *searchTabsView;
@property (nonatomic) BOOL searchPageContentOnly;
@property (nonatomic, weak) NFBTimelineViewController *searchResultsHost;
@property (nonatomic, strong) NFBSearchPagingScrollView *searchPager;
@property (nonatomic, strong) UIScrollView *searchTabsScrollView;
@property (nonatomic, copy) NSArray<NFBTimelineViewController *> *searchPages;
@property (nonatomic) CGSize searchPagerLayoutSize;
@property (nonatomic) BOOL searchHostAppeared;
@property (nonatomic) BOOL searchPagingInteractionSuppressed;
@property (nonatomic, strong) UIView *searchEmptyView;
@property (nonatomic, strong) UILabel *searchEmptyTitle;
@property (nonatomic, strong) UILabel *searchEmptySubtitle;
@property (nonatomic, strong) UIView *searchTabUnderline;
@property (nonatomic, copy) NSArray<UIButton *> *searchTabButtons;
@property (nonatomic, strong) NSLayoutConstraint *searchUnderlineCenter;
@property (nonatomic, strong) NSLayoutConstraint *searchUnderlineWidth;
@property (nonatomic, copy) NSString *timelineTitleOverride;
@property (nonatomic, copy) NSString *feedRouteActor;
@property (nonatomic, copy) NSString *feedRouteRecordKey;
@property (nonatomic, copy) NSDictionary *feedMetadata;
@property (nonatomic, assign) CGFloat feedHeaderWidth;
@property (nonatomic, strong) UILabel *feedHeaderTitleLabel;
@property (nonatomic, strong) UIView *feedNavigationTitleContent;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyLoadingView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSDictionary *profile;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL hasLoadedOnce;
@property (nonatomic, assign) NSUInteger timelineLoadGeneration;
@property (nonatomic, strong) UIView *homeTabsView;
@property (nonatomic, strong) UIView *homeTabsBorder;
@property (nonatomic, strong) UIView *homeTabUnderline;
@property (nonatomic, strong) NSLayoutConstraint *homeTabUnderlineCenterXConstraint;
@property (nonatomic, copy) NSArray<UIButton *> *homeTabButtons;
@property (nonatomic, strong) UIScrollView *homeTabsScrollView;
@property (nonatomic, strong) UIStackView *homeTabsStack;
@property (nonatomic, copy) NSArray<NSDictionary *> *homeFeedTabs;
@property (nonatomic, assign) NSInteger selectedHomeFeedIndex;
@property (nonatomic, strong) UIPanGestureRecognizer *homeFeedPanGesture;
@property (nonatomic, assign) BOOL homeFeedPanTracking;
@property (nonatomic, assign) BOOL suppressTimelineSelectionForSwipe;
@property (nonatomic, strong) UITableView *homeFeedPreviewTableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *homeFeedPreviewItems;
@property (nonatomic, strong) UIView *homeFeedPreviewLoadingView;
@property (nonatomic, strong) UIImageView *homeFeedPreviewLoadingImageView;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<NSDictionary *> *> *homeFeedItemsCache;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *homeFeedCursorCache;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *homeFeedPrefetchingIndexes;
@property (nonatomic, assign) NSInteger homeFeedPreviewIndex;
@property (nonatomic, assign) BOOL homeFeedSwitchAnimating;
@property (nonatomic, strong) UILongPressGestureRecognizer *feedResourceLongPressGesture;
@property (nonatomic, strong) NSIndexPath *feedResourceDragIndexPath;
@property (nonatomic, strong) UIView *feedResourceDragSnapshotView;
@property (nonatomic, assign) CGPoint feedResourceDragTouchOffset;
@property (nonatomic, assign) CGPoint feedResourceDragStartCenter;
@property (nonatomic, assign) BOOL feedResourceDragCanReorder;
@property (nonatomic, assign) BOOL feedResourceDidDrag;
@property (nonatomic, assign) BOOL feedResourceOrderDirty;
@property (nonatomic, strong) UIView *feedResourceMenuOverlay;
@property (nonatomic, strong) UIVisualEffectView *feedResourceMenuBlurView;
@property (nonatomic, strong) UIView *feedResourceMenuView;
@property (nonatomic, copy) NSDictionary *feedResourceMenuItem;
@property (nonatomic, strong) NSIndexPath *feedResourceMenuIndexPath;
@property (nonatomic, strong) UIButton *avatarButton;
@property (nonatomic, strong) UIImageView *avatarButtonImageView;
@property (nonatomic, strong) UIButton *composeButton;
@property (nonatomic, assign) NSUInteger owningAccountGeneration;
@property (nonatomic, assign) NSUInteger accountChromeGeneration;
@property (nonatomic, assign) NSUInteger profileMessageCapabilityGeneration;
@property (nonatomic, assign) BOOL profileMessageOpening;
@property (nonatomic, assign) BOOL searchResultsMode;
@property (nonatomic, copy) NSString *selectedProfileTabID;
@property (nonatomic, copy) NSString *selectedNotificationsTabID;
@property (nonatomic, copy) NSString *loadedProfileActor;
@property (nonatomic, copy) NSString *loadingProfileActor;
@property (nonatomic, copy) NSString *loadingKnownFollowersActor;
@property (nonatomic, copy) NSArray<UIButton *> *profileTabButtons;
@property (nonatomic, strong) UIView *notificationsTabsView;
@property (nonatomic, strong) UIView *notificationsTabsBorder;
@property (nonatomic, copy) NSArray<UIButton *> *notificationsTabButtons;
@property (nonatomic, strong) UIPanGestureRecognizer *sectionPanGesture;
@property (nonatomic, strong) UIView *sectionPanOverlay;
@property (nonatomic, strong) UIView *sectionPanSnapshot;
@property (nonatomic, strong) UIView *sectionPanIncoming;
@property (nonatomic, assign) NSInteger sectionPanTarget;
@property (nonatomic, assign) NSInteger sectionPanDirection;
@property (nonatomic, assign) BOOL sectionPanAnimating;
@property (nonatomic, assign) CGFloat profileNavigationAlpha;
@property (nonatomic, assign) CGFloat profileNavigationBackgroundAlpha;
@property (nonatomic, assign) BOOL profileNavigationAppearanceConfigured;
@property (nonatomic, strong) UIView *profileNavigationTitleContainer;
@property (nonatomic, strong) UIStackView *profileNavigationTitleStack;
@property (nonatomic, strong) UILabel *profileNavigationTitleLabel;
@property (nonatomic, strong) UILabel *profileNavigationSubtitleLabel;
@property (nonatomic, strong) UIButton *profileNavigationBackButton;
@property (nonatomic, strong) UIButton *profileNavigationSearchButton;
@property (nonatomic, strong) UIButton *profileNavigationMoreButton;
@property (nonatomic, weak) UIView *profileHeaderView;
@property (nonatomic, weak) UIView *profileHeaderBannerView;
@property (nonatomic, weak) UIImageView *profileHeaderBannerImageView;
@property (nonatomic, weak) UIImageView *profileHeaderAvatarImageView;
@property (nonatomic, strong) NSLayoutConstraint *profileHeaderBannerHeightConstraint;
@property (nonatomic, assign) CGFloat profileHeaderLayoutWidth;
@property (nonatomic, assign) CGFloat profileHeaderLayoutSafeTop;
- (NFBProfileElements)profileElements;
@property (nonatomic, assign) CGFloat profileExpandedHeaderHeight;
@property (nonatomic, assign) CGFloat profileCurrentHeaderHeight;
@property (nonatomic, weak) UIVisualEffectView *profileBannerBlurView;
@property (nonatomic, strong) UIView *profileCoverChromeView;
@property (nonatomic, strong) UIImageView *profileCoverChromeImageView;
@property (nonatomic, strong) UIVisualEffectView *profileCoverChromeBlurView;
@property (nonatomic, strong) UIView *profileCoverChromeScrimView;
@property (nonatomic, strong) NSCache *profileImageCache;
@property (nonatomic, strong) NFBPostActionCoordinator *postActionCoordinator;

- (void)cancelHomeFeedPan;
- (void)restoreFloatingComposeButtonVisibility;
- (void)resetHomeFeedTabsForAccountChange;

@end

@implementation NFBTimelineViewController

- (instancetype)initWithKind:(NFBTimelineKind)kind actor:(NSString *)actor {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _kind = kind;
    _owningAccountGeneration = [NFBAtprotoSession sharedSession].accountGeneration;
    _actor = [actor copy];
    _items = [NSMutableArray array];
    if (kind == NFBTimelineKindBookmarks) _bookmarkItems = [NSMutableArray array];
    _searchQuery = @"";
    _selectedProfileTabID = @"tweets";
    _selectedNotificationsTabID = @"all";
    _selectedHomeFeedIndex = 0;
    _profileNavigationAlpha = 0.0;
    _profileNavigationBackgroundAlpha = 0.0;
    _profileImageCache = [[NSCache alloc] init];
    _profileImageCache.countLimit = 32;
    _homeFeedPreviewIndex = NSNotFound;
    _homeFeedItemsCache = [NSMutableDictionary dictionary];
    _homeFeedCursorCache = [NSMutableDictionary dictionary];
    _homeFeedPrefetchingIndexes = [NSMutableSet set];
    if (kind == NFBTimelineKindLists) {
      _homeFeedTabs = @[
        @{@"type": @"follow-lists", @"label": @"Follow Lists"},
        @{@"type": @"block-lists", @"label": @"Block Lists"}
      ];
    } else if (kind == NFBTimelineKindFeeds) {
      _homeFeedTabs = @[
        @{@"type": @"saved-feeds", @"label": @"My Feeds"},
        @{@"type": @"discover-feeds", @"label": @"Discover"}
      ];
    } else {
      _homeFeedTabs = @[
        @{@"type": @"for-you", @"label": @"For you"},
        @{@"type": @"following", @"label": @"Following"}
      ];
    }
  }
  return self;
}

- (instancetype)initWithFeedActor:(NSString *)actor recordKey:(NSString *)recordKey title:(NSString *)title {
  self = [self initWithKind:NFBTimelineKindFeedTimeline actor:nil];
  if (self) {
    _feedRouteActor = [actor copy];
    _feedRouteRecordKey = [recordKey copy];
    _timelineTitleOverride = [title copy];
  }
  return self;
}

- (void)updateFeedHeader {
  if (self.kind != NFBTimelineKindFeedTimeline || !self.feedMetadata) return;
  CGFloat width = CGRectGetWidth(self.tableView.bounds);
  self.feedHeaderWidth = width;
  UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];
  header.backgroundColor = NFBColorBackground();
  UIStackView *stack = [[UIStackView alloc] init];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.spacing = 8;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  NSDictionary *creator = [self.feedMetadata[@"creator"] isKindOfClass:NSDictionary.class] ? self.feedMetadata[@"creator"] : @{};
  NSString *name = [self.feedMetadata[@"displayName"] isKindOfClass:NSString.class] ? self.feedMetadata[@"displayName"] : self.timelineTitleOverride ?: @"Feed";
  NSString *actor = self.feedRouteActor ? @"" : (creator[@"handle"] ?: creator[@"did"] ?: @"");
  NSString *description = [self.feedMetadata[@"description"] isKindOfClass:NSString.class] ? self.feedMetadata[@"description"] : @"";
  NSInteger likes = [self.feedMetadata[@"likeCount"] respondsToSelector:@selector(integerValue)] ? [self.feedMetadata[@"likeCount"] integerValue] : 0;
  NSArray *texts = @[name, actor, description, [NSString stringWithFormat:@"%ld likes", (long)likes]];
  for (NSUInteger i = 0; i < texts.count; i++) {
    if ([texts[i] length] == 0) continue;
    UILabel *label = [[UILabel alloc] init];
    label.text = texts[i];
    label.numberOfLines = 0;
    label.font = NFBFont(i == 0 ? 31 : 13, i == 0 ? NFBFontWeightHeavy : (i == 2 ? NFBFontWeightBold : NFBFontWeightRegular));
    label.textColor = i == 0 ? NFBColorText() : NFBColorSecondaryText();
    if (i == 0) {
      self.feedHeaderTitleLabel = label;
      label.accessibilityTraits |= UIAccessibilityTraitHeader;
    }
    [stack addArrangedSubview:label];
    if (i == 0) [stack setCustomSpacing:0 afterView:label];
    if (i == 2) [stack setCustomSpacing:16 afterView:label];
  }
  [header addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
    [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
    [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],
    [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16]
  ]];
  CGFloat height = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
  header.frame = CGRectMake(0, 0, width, ceil(height));
  [header setNeedsLayout];
  [header layoutIfNeeded];
  UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, ceil(height) - 0.5, width, 0.5)];
  line.backgroundColor = NFBColorBorder();
  line.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
  [header addSubview:line];
  self.tableView.tableHeaderView = header;
  self.timelineTitleOverride = name;
  [self configureFeedNavigationTitle];
}

- (void)configureFeedNavigationTitle {
  UIView *content = NFBTitleView(self.timelineTitleOverride.length > 0 ? self.timelineTitleOverride : @"Feed", nil);
  UIView *container = [[UIView alloc] initWithFrame:content.frame];
  content.frame = container.bounds;
  content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [container addSubview:content];
  self.feedNavigationTitleContent = content;
  // Animate our inner view; UINavigationBar owns the outer view during pushes/pops.
  [self updateFeedNavigationForScrollOffset];
  self.navigationItem.titleView = container;
}

- (void)updateFeedNavigationForScrollOffset {
  if (self.kind != NFBTimelineKindFeedTimeline || !self.feedNavigationTitleContent) return;
  CGFloat alpha = 1.0;
  if (self.feedHeaderTitleLabel && self.tableView.tableHeaderView) {
    CGRect titleFrame = [self.feedHeaderTitleLabel convertRect:self.feedHeaderTitleLabel.bounds toView:self.tableView];
    CGFloat visibleTop = CGRectGetMinY(self.tableView.bounds) + self.tableView.adjustedContentInset.top;
    // Start only after the final line of the expanded title has left the viewport.
    // Measured geometry also covers wrapped titles, font-size changes and rotation.
    CGFloat progress = MIN(1.0, MAX(0.0, (visibleTop - CGRectGetMaxY(titleFrame)) / 16.0));
    alpha = progress * progress * (3.0 - 2.0 * progress);
  }
  self.feedNavigationTitleContent.alpha = alpha;
  self.feedNavigationTitleContent.transform = CGAffineTransformMakeTranslation(0.0, 4.0 * (1.0 - alpha));
  self.feedNavigationTitleContent.accessibilityElementsHidden = alpha < 0.5;
}

- (void)loadFeedPageWithCursor:(NSString *)cursor completion:(NFBAtprotoArrayCompletion)completion {
  if (self.actor.length == 0 && self.feedRouteActor.length > 0) {
    [[NFBAtprotoClient sharedClient] fetchProfileForActor:self.feedRouteActor completion:^(NSDictionary *profile, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        NSString *did = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
        if (error || did.length == 0) {
          completion(nil, nil, error ?: [NSError errorWithDomain:@"NFBFeed" code:1 userInfo:@{NSLocalizedDescriptionKey: @"This topic could not be loaded. Pull down to retry."}]);
          return;
        }
        self.actor = [NSString stringWithFormat:@"at://%@/app.bsky.feed.generator/%@", did, self.feedRouteRecordKey];
        [self loadFeedPageWithCursor:cursor completion:completion];
      });
    }];
    return;
  }
  if (!cursor) {
    [[NFBAtprotoClient sharedClient] fetchFeedMetadataForURI:self.actor completion:^(NSDictionary *metadata, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!error && metadata.count) {
          self.feedMetadata = metadata;
          [self updateFeedHeader];
        }
      });
    }];
  }
  [[NFBAtprotoClient sharedClient] fetchFeedWithURI:self.actor ?: @"" cursor:cursor completion:completion];
}

- (instancetype)initWithSearchQuery:(NSString *)query {
  self = [self initWithKind:NFBTimelineKindSearch actor:nil];
  if (self) {
    _searchResultsMode = YES;
    _searchQuery = [[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy] ?: @"";
  }
  return self;
}

- (NFBPostActionCoordinator *)postActionCoordinator {
  if (!_postActionCoordinator) {
    _postActionCoordinator = [[NFBPostActionCoordinator alloc] initWithPresentingViewController:self];
    __weak typeof(self) weakSelf = self;
    _postActionCoordinator.postUpdateHandler = ^(NSDictionary *updatedPost, NSDictionary *originalPost) {
      [weakSelf applyUpdatedPost:updatedPost originalPost:originalPost];
    };
    _postActionCoordinator.deleteHandler = ^(NSDictionary *deletedPost) {
      [weakSelf removeDeletedPost:deletedPost];
    };
    _postActionCoordinator.reloadHandler = ^{
      [weakSelf refreshTimeline];
    };
    _postActionCoordinator.profileUpdateHandler = ^(NSDictionary *updatedProfile, NSDictionary *originalProfile) {
      (void)originalProfile;
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      strongSelf.profile = updatedProfile;
      if (strongSelf.kind == NFBTimelineKindProfile) {
        [strongSelf updateProfileHeader];
        [strongSelf refreshProfileMessageCapabilityIfNeeded];
      }
    };
  }
  _postActionCoordinator.presentingViewController = self;
  return _postActionCoordinator;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBColorBackground();
  if (self.kind == NFBTimelineKindProfile) {
    self.edgesForExtendedLayout = UIRectEdgeTop;
    self.extendedLayoutIncludesOpaqueBars = YES;
  }
  [self configureNavigation];
  if ([self isSearchResultsHost]) { [self configureSearchTabs]; [self configureSearchPager]; }
  else [self configureTableView];
  [self configureFloatingComposeButtonIfNeeded];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(feedListCacheInvalidated:) name:NFBAtprotoFeedListCacheDidInvalidateNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(advancedNotificationFiltersChanged:) name:NFBNotificationAdvancedFiltersDidChangeNotification object:nil];

  if ([self isSearchResultsHost]) return;
  if (self.kind == NFBTimelineKindHome) {
    [self loadHomeFeedTabs];
    [self refreshTimeline];
  } else if (self.kind != NFBTimelineKindSearch) {
    [self refreshTimeline];
  } else {
    [self refreshTimeline];
  }
}

- (void)configureHomeNavigationAppearance {
  if (self.kind != NFBTimelineKindHome) return;
  // The reference treats the title bar and feed selector as one header:
  // only the separator below the tabs is visible.
  UINavigationBarAppearance *appearance = [self.navigationController.navigationBar.standardAppearance copy];
  appearance.shadowColor = UIColor.clearColor;
  self.navigationItem.standardAppearance = appearance;
  self.navigationItem.scrollEdgeAppearance = appearance;
  self.navigationItem.compactAppearance = appearance;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  if (self.searchPager) {
    [self loadSearchPagesNearIndex:self.searchTab];
    self.searchPager.userInteractionEnabled = NO;
    [self.searchPages[self.searchTab] beginAppearanceTransition:YES animated:animated];
  }
  [self configureHomeNavigationAppearance];
  if (self.kind == NFBTimelineKindHome) {
    // Explicitly identify the vertical feed, rather than the horizontal tab scroller.
    // Selector availability avoids the Linux toolchain's missing OS-version helper.
    if ([self respondsToSelector:@selector(setContentScrollView:forEdge:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
      [self setContentScrollView:self.tableView forEdge:NSDirectionalRectEdgeTop];
#pragma clang diagnostic pop
    }
    self.navigationController.hidesBarsOnSwipe = YES;
  }
  [self configurePushedBackButtonIfNeeded];
  [self configurePushedProfileBackButtonIfNeeded];
  [self restoreFloatingComposeButtonVisibility];
  if (self.kind == NFBTimelineKindProfile) self.profileNavigationAppearanceConfigured = NO;
  [self configureProfileNavigationAppearanceIfNeeded];
  [self updateFeedNavigationForScrollOffset];
  if (self.kind == NFBTimelineKindProfile && self.profile) [self refreshProfileMessageCapabilityIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  if (self.searchPager) {
    self.searchPager.panGestureRecognizer.enabled = NO;
    [self.searchPager setContentOffset:CGPointMake(self.searchTab * CGRectGetWidth(self.searchPager.bounds), 0) animated:NO];
    self.searchPager.panGestureRecognizer.enabled = YES;
    [self setSearchPageInteractionEnabled:YES];
    self.searchHostAppeared = NO;
    [self.searchPages[self.searchTab] beginAppearanceTransition:NO animated:animated];
  }
  if (self.kind == NFBTimelineKindHome) {
    self.navigationController.hidesBarsOnSwipe = NO;
    [self.navigationController setNavigationBarHidden:NO animated:animated];
  }
  [self dismissFeedResourceMenuAnimated:NO];
  [self finishFeedResourceDragPersisting:NO];
  if (self.kind == NFBTimelineKindProfile && self.navigationController) {
    NFBApplyNavigationAppearance(self.navigationController);
  }
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (self.searchPager) {
    [self.searchPages[self.searchTab] endAppearanceTransition];
    self.searchHostAppeared = YES;
    self.searchPager.userInteractionEnabled = YES;
  }
  if ([self requiresAuth] && ![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
  }
}

- (BOOL)shouldAutomaticallyForwardAppearanceMethods { return ![self isSearchResultsHost]; }
- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  if (self.searchPager) [self.searchPages[self.searchTab] endAppearanceTransition];
}

- (void)configureRootAccountAvatarButton {
  UIView *avatarContainer = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 44.0, 44.0)];
  self.avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.avatarButton.frame = CGRectMake(0.0, 6.0, 32.0, 32.0);
  self.avatarButton.clipsToBounds = YES;
  self.avatarButton.layer.cornerRadius = 16.0;
  self.avatarButton.accessibilityLabel = @"Account menu";

  self.avatarButtonImageView = [[UIImageView alloc] initWithImage:NFBBrandIconImage() ?: NFBDefaultAvatarImage()];
  self.avatarButtonImageView.frame = self.avatarButton.bounds;
  self.avatarButtonImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.avatarButtonImageView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarButtonImageView.clipsToBounds = YES;
  self.avatarButtonImageView.layer.cornerRadius = 16.0;
  [self.avatarButton addSubview:self.avatarButtonImageView];

  [self.avatarButton addTarget:self action:@selector(accountMenuTapped) forControlEvents:UIControlEventTouchUpInside];
  [avatarContainer addSubview:self.avatarButton];
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:avatarContainer];
  [self refreshAccountChrome];
}

- (void)configureDiscoverTopicsButton {
  UIButton *topicsButton = [UIButton buttonWithType:UIButtonTypeCustom];
  topicsButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
  topicsButton.accessibilityLabel = @"Topics";
  topicsButton.tintColor = NFBColorText();
  [topicsButton setImage:NFBTemplateIcon(@"nfb_settings") forState:UIControlStateNormal];
  topicsButton.imageEdgeInsets = UIEdgeInsetsMake(10.0, 10.0, 10.0, 10.0);
  [topicsButton addTarget:self action:@selector(topicsTapped) forControlEvents:UIControlEventTouchUpInside];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:topicsButton];
}

- (void)configureNotificationsSettingsButton {
  UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
  settingsButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
  settingsButton.accessibilityLabel = @"Notification settings";
  settingsButton.tintColor = NFBColorText();
  [settingsButton setImage:NFBTemplateIcon(@"nfb_settings") forState:UIControlStateNormal];
  settingsButton.imageEdgeInsets = UIEdgeInsetsMake(10.0, 10.0, 10.0, 10.0);
  [settingsButton addTarget:self action:@selector(notificationSettingsTapped) forControlEvents:UIControlEventTouchUpInside];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:settingsButton];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self layoutSearchPager];
  if (self.feedMetadata && fabs(self.feedHeaderWidth - CGRectGetWidth(self.tableView.bounds)) > 0.5) [self updateFeedHeader];
  [self updateFeedNavigationForScrollOffset];
  [self restoreFloatingComposeButtonVisibility];
  if (self.kind == NFBTimelineKindProfile) {
    if (self.profile && (fabs(self.profileHeaderLayoutWidth - CGRectGetWidth(self.view.bounds)) > 0.5 ||
                        fabs(self.profileHeaderLayoutSafeTop - self.view.window.safeAreaInsets.top) > 0.5)) {
      [self updateProfileHeader];
    } else [self updateProfileNavigationForScrollOffset];
  }
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureNavigation {
  if (self.searchPageContentOnly) return;
  self.navigationItem.leftBarButtonItem = nil;
  self.navigationItem.leftBarButtonItems = nil;
  self.navigationItem.rightBarButtonItem = nil;
  self.navigationItem.rightBarButtonItems = nil;
  if (self.kind == NFBTimelineKindHome) self.title = nil;
  else if (self.kind == NFBTimelineKindSearch) self.title = self.searchResultsMode ? @"Search" : @"Explore";
  else if (self.kind == NFBTimelineKindNotifications) {
    self.title = nil;
    self.navigationItem.titleView = NFBTitleView(@"Notifications", nil);
  } else if (self.kind == NFBTimelineKindBookmarks) {
    self.title = nil;
    self.navigationItem.titleView = NFBTitleView(@"Bookmarks", nil);
  } else if (self.kind == NFBTimelineKindLists) {
    self.title = nil;
    self.navigationItem.titleView = NFBTitleView(@"Lists", nil);
  } else if (self.kind == NFBTimelineKindFeeds) {
    self.title = nil;
    self.navigationItem.titleView = NFBTitleView(@"Feeds", nil);
  } else if (self.kind == NFBTimelineKindFeedTimeline) {
    self.title = nil;
    [self configureFeedNavigationTitle];
  } else if (self.kind == NFBTimelineKindListTimeline) {
    self.title = nil;
    self.navigationItem.titleView = NFBTitleView(self.timelineTitleOverride.length > 0 ? self.timelineTitleOverride : @"List", nil);
  } else {
    self.title = nil;
    self.navigationItem.titleView = NFBTitleView(@"Profile", nil);
  }

  if (self.kind == NFBTimelineKindHome) {
    UIImageView *logo = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_twitter_logo")];
    logo.tintColor = NFBNeoFreeBirdColorTopBirdIcon() ? NFBColorAccent() : NFBColorText();
    logo.contentMode = UIViewContentModeScaleAspectFit;
    logo.frame = CGRectMake(0, 0, 32.0, 32.0);
    self.navigationItem.titleView = logo;

    [self configureRootAccountAvatarButton];

    UIButton *feedsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    feedsButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    feedsButton.accessibilityLabel = @"Manage Feeds";
    feedsButton.tintColor = NFBColorText();
    UIImage *sparkle = NFBTemplateIcon(@"nfb_sparkle");
    [feedsButton setImage:sparkle forState:UIControlStateNormal];
    feedsButton.imageEdgeInsets = UIEdgeInsetsMake(10.0, 10.0, 10.0, 10.0);
    [feedsButton addTarget:self action:@selector(manageFeedsTapped) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:feedsButton];
  } else if (self.kind == NFBTimelineKindProfile) {
    self.title = nil;
    [self updateProfileNavigationTitleViewWithTitle:@"Profile" subtitle:nil];
    self.navigationItem.rightBarButtonItem = nil;
  } else if (self.kind == NFBTimelineKindNotifications) {
    [self configureRootAccountAvatarButton];
    [self configureNotificationsSettingsButton];
  }

  if (self.kind == NFBTimelineKindSearch) {
    if (self.searchResultsMode && self.navigationController.viewControllers.firstObject != self) {
      self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
      self.navigationItem.hidesBackButton = YES;
    }
    if (self.searchResultsMode) { [self configureSearchResultsNavigation]; return; }
    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.searchResultsUpdater = self;
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchBar.placeholder = @"Search Twitter";
    searchController.searchBar.text = self.searchResultsMode ? self.searchQuery : @"";
    searchController.searchBar.delegate = self;
    searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchController.searchBar.tintColor = NFBColorAccent();
    UITextField *field = nil;
    if (@available(iOS 13.0, *)) {
      field = searchController.searchBar.searchTextField;
    }
    field.textColor = NFBColorText();
    field.backgroundColor = NFBColorElevatedBackground();
    field.font = NFBFont(17.0, NFBFontWeightRegular);
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    if (!self.searchResultsMode) {
      [self configureRootAccountAvatarButton];
      [self configureDiscoverTopicsButton];
    }
  }

  if (self.kind == NFBTimelineKindFeeds || self.kind == NFBTimelineKindBookmarks) {
    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.searchResultsUpdater = self;
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchBar.placeholder = self.kind == NFBTimelineKindBookmarks ? @"Search Bookmarks" : @"Search Feeds";
    if (self.kind == NFBTimelineKindBookmarks) searchController.searchBar.accessibilityHint = @"Filter by text or author, for example from:username coffee.";
    searchController.searchBar.text = self.searchQuery;
    searchController.searchBar.delegate = self;
    searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchController.searchBar.tintColor = NFBColorAccent();
    UITextField *field = nil;
    if (@available(iOS 13.0, *)) field = searchController.searchBar.searchTextField;
    field.textColor = NFBColorText();
    field.backgroundColor = NFBColorElevatedBackground();
    field.font = NFBFont(17.0, NFBFontWeightRegular);
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
  }
}

- (void)configurePushedProfileBackButtonIfNeeded {
  if (self.kind != NFBTimelineKindProfile || !self.navigationController) return;
  [self updateProfileNavigationTitleViewWithTitle:[self currentProfileNavigationTitle] subtitle:[self currentProfileNavigationSubtitle]];
}

- (void)configurePushedBackButtonIfNeeded {
  if (!self.navigationController || self.navigationController.viewControllers.firstObject == self) return;
  if (self.kind == NFBTimelineKindProfile || (self.kind == NFBTimelineKindSearch && self.searchResultsMode)) return;
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
  self.navigationItem.hidesBackButton = YES;
}

- (BOOL)isPushedProfileController {
  return self.kind == NFBTimelineKindProfile && self.navigationController.viewControllers.firstObject != self;
}

- (NSString *)currentProfileNavigationTitle {
  if (self.profile) {
    NSString *displayName = [NFBAtprotoClient displayNameForProfile:self.profile];
    if (displayName.length > 0) return displayName;
  }
  return @"Profile";
}

- (NSString *)currentProfileNavigationSubtitle {
  if (!self.profile) return nil;
  NSString *handle = [NFBAtprotoClient handleForProfile:self.profile];
  return handle.length > 0 ? [@"@" stringByAppendingString:handle] : nil;
}

- (void)updateProfileNavigationTitleViewWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
  if (self.kind != NFBTimelineKindProfile) return;
  BOOL pushed = [self isPushedProfileController];
  self.navigationItem.hidesBackButton = pushed;
  self.navigationItem.titleView = nil;

  CGFloat screenWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
  CGFloat width = MIN(screenWidth - (pushed ? 112.0 : 72.0), pushed ? 300.0 : 260.0);
  if (width < 180.0) width = 180.0;
  UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 44.0)];
  container.backgroundColor = UIColor.clearColor;

  UIButton *backButton = nil;
  UIBarButtonItem *backItem = nil;
  if (pushed) {
    backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    backButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    backButton.contentEdgeInsets = UIEdgeInsetsMake(8.0, 0.0, 8.0, 16.0);
    [backButton setImage:NFBTemplateIcon(@"nfb_arrow_left") forState:UIControlStateNormal];
    backButton.tintColor = (self.profileNavigationBackgroundAlpha < 0.46 && [self profileStringForKey:@"banner"].length > 0) ? UIColor.whiteColor : NFBColorText();
    backButton.accessibilityLabel = @"Back";
    [backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    backItem = [[UIBarButtonItem alloc] initWithCustomView:backButton];
  }

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.text = title.length > 0 ? title : @"Profile";
  titleLabel.textColor = NFBColorText();
  titleLabel.font = NFBFont(subtitle.length > 0 ? 16.0 : 18.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentLeft;
  titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UILabel *subtitleLabel = [[UILabel alloc] init];
  subtitleLabel.text = subtitle ?: @"";
  subtitleLabel.textColor = NFBColorSecondaryText();
  subtitleLabel.font = NFBFont(12.0, NFBFontWeightRegular);
  subtitleLabel.textAlignment = NSTextAlignmentLeft;
  subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  subtitleLabel.hidden = subtitle.length == 0;

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:subtitle.length > 0 ? @[
    titleLabel,
    subtitleLabel
  ] : @[titleLabel]];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentLeading;
  stack.spacing = 0.0;
  stack.alpha = self.profileNavigationAlpha;
  stack.hidden = self.profileNavigationAlpha <= 0.01;
  [container addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor],
    [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    [titleLabel.widthAnchor constraintLessThanOrEqualToConstant:width],
    [subtitleLabel.widthAnchor constraintLessThanOrEqualToConstant:width]
  ]];

  self.profileNavigationTitleContainer = container;
  self.profileNavigationTitleStack = stack;
  self.profileNavigationTitleLabel = titleLabel;
  self.profileNavigationSubtitleLabel = subtitleLabel;
  self.profileNavigationBackButton = backButton;
  UIBarButtonItem *titleItem = [[UIBarButtonItem alloc] initWithCustomView:container];
  if (pushed && backItem) {
    self.navigationItem.leftBarButtonItems = @[backItem, titleItem];
  } else {
    self.navigationItem.leftBarButtonItems = nil;
    self.navigationItem.leftBarButtonItem = titleItem;
  }

  UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeCustom];
  searchButton.frame = CGRectMake(0.0, 0.0, 38.0, 44.0);
  searchButton.contentEdgeInsets = UIEdgeInsetsMake(10.0, 7.0, 10.0, 7.0);
  [searchButton setImage:NFBTemplateIcon(@"nfb_search") forState:UIControlStateNormal];
  searchButton.tintColor = (self.profileNavigationBackgroundAlpha < 0.46 && [self profileStringForKey:@"banner"].length > 0) ? UIColor.whiteColor : NFBColorText();
  searchButton.accessibilityLabel = @"Search";
  [searchButton addTarget:self action:@selector(profileSearchTapped) forControlEvents:UIControlEventTouchUpInside];
  self.profileNavigationSearchButton = searchButton;
  UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithCustomView:searchButton];
  NSMutableArray<UIBarButtonItem *> *rightItems = [NSMutableArray array];
  if (self.profile) {
    UIButton *moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
    moreButton.frame = CGRectMake(0.0, 0.0, 38.0, 44.0);
    moreButton.contentEdgeInsets = UIEdgeInsetsMake(11.0, 7.0, 11.0, 7.0);
    [moreButton setImage:NFBTemplateIcon(@"nfb_more") forState:UIControlStateNormal];
    moreButton.tintColor = searchButton.tintColor;
    moreButton.accessibilityLabel = @"More";
    [moreButton addTarget:self action:@selector(profileMoreTapped) forControlEvents:UIControlEventTouchUpInside];
    self.profileNavigationMoreButton = moreButton;
    [rightItems addObject:[[UIBarButtonItem alloc] initWithCustomView:moreButton]];
  } else {
    self.profileNavigationMoreButton = nil;
  }
  [rightItems addObject:searchItem];
  self.navigationItem.rightBarButtonItems = rightItems;
}

- (void)configureProfileNavigationAppearanceIfNeeded {
  if (self.kind != NFBTimelineKindProfile || !self.navigationController) return;
  [self updateProfileNavigationForScrollOffset];
}

- (CGFloat)smoothProfileProgressForOffset:(CGFloat)offset start:(CGFloat)start end:(CGFloat)end {
  if (end <= start) return offset >= end ? 1.0 : 0.0;
  CGFloat progress = MIN(1.0, MAX(0.0, (offset - start) / (end - start)));
  return progress * progress * (3.0 - 2.0 * progress);
}

- (UIBlurEffectStyle)profileChromeBlurStyle {
  if ([NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight]) return UIBlurEffectStyleSystemChromeMaterialLight;
  return UIBlurEffectStyleSystemChromeMaterialDark;
}

- (CGFloat)profileCollapsedChromeHeight {
  // Navigation bars differ by device, orientation and iOS version. Cover their
  // actual bottom edge, including the second line, in this view's coordinates.
  UINavigationBar *bar = self.navigationController.navigationBar;
  CGFloat bottom = self.view.window.safeAreaInsets.top + CGRectGetHeight(bar.bounds);
  if (bar.window && self.view.window == bar.window) bottom = CGRectGetMaxY([bar convertRect:bar.bounds toView:self.view]);
  UILabel *subtitle = self.profileNavigationSubtitleLabel;
  if (subtitle.window && !subtitle.hidden) bottom = MAX(bottom, CGRectGetMaxY([subtitle convertRect:subtitle.bounds toView:self.view]) + 8.0);
  return ceil(MAX(44.0, bottom));
}

- (CGFloat)profileExpandedBannerHeight {
  CGFloat safeTop = self.view.window.safeAreaInsets.top;
  if ([self profileStringForKey:@"banner"].length == 0) return safeTop + 48.0;
  CGFloat ratio = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact ? 4.0 : 3.0;
  CGFloat width = CGRectGetWidth(self.view.bounds);
  return MAX(safeTop + 48.0, ceil(width / ratio));
}

- (CGFloat)profileMinimumBannerHeight {
  CGFloat expandedHeight = [self profileExpandedBannerHeight];
  CGFloat collapsedHeight = [self profileCollapsedChromeHeight];
  return MIN(collapsedHeight, expandedHeight);
}

- (CGFloat)profileBannerCollapseDistance {
  return MAX(44.0, [self profileExpandedBannerHeight] - [self profileMinimumBannerHeight] + 24.0);
}

- (void)configureProfileCoverChromeViewIfNeeded {
  if (self.kind != NFBTimelineKindProfile || self.profileCoverChromeView) return;

  CGFloat width = CGRectGetWidth(self.view.bounds);
  if (width <= 0.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds);
  UIView *chrome = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, [self profileExpandedBannerHeight])];
  chrome.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  chrome.userInteractionEnabled = YES;
  [chrome addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileBannerTapped)]];
  chrome.clipsToBounds = YES;
  chrome.alpha = 0.0;
  chrome.hidden = YES;
  chrome.layer.zPosition = 10.0;

  UIImageView *imageView = [[UIImageView alloc] initWithFrame:chrome.bounds];
  imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  imageView.image = NFBDefaultCoverImage();
  imageView.contentMode = UIViewContentModeScaleAspectFill;
  imageView.clipsToBounds = YES;

  UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithFrame:chrome.bounds];
  blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  blurView.effect = [UIBlurEffect effectWithStyle:[self profileChromeBlurStyle]];
  blurView.alpha = 0.0;

  UIView *scrim = [[UIView alloc] initWithFrame:chrome.bounds];
  scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  scrim.backgroundColor = UIColor.blackColor;
  scrim.alpha = 0.0;

  [chrome addSubview:imageView];
  [chrome addSubview:blurView];
  [chrome addSubview:scrim];
  [self.view addSubview:chrome];

  self.profileCoverChromeView = chrome;
  self.profileCoverChromeImageView = imageView;
  self.profileCoverChromeBlurView = blurView;
  self.profileCoverChromeScrimView = scrim;
}

- (void)updateProfileCoverChromeImage:(UIImage *)image {
  [self configureProfileCoverChromeViewIfNeeded];
  self.profileCoverChromeImageView.image = image ?: NFBDefaultCoverImage();
}

- (void)updateProfileCoverChromeTheme {
  if (!self.profileCoverChromeBlurView) return;
  self.profileCoverChromeBlurView.effect = [UIBlurEffect effectWithStyle:[self profileChromeBlurStyle]];
}

- (void)applyProfileNavigationAppearanceWithBackgroundAlpha:(CGFloat)backgroundAlpha titleAlpha:(CGFloat)titleAlpha {
  self.navigationController.navigationBar.translucent = YES;
  self.navigationController.navigationBar.tintColor = (backgroundAlpha < 0.46 && [self profileStringForKey:@"banner"].length > 0) ? UIColor.whiteColor : NFBColorText();
  self.profileNavigationTitleStack.alpha = titleAlpha;
  self.profileNavigationTitleStack.hidden = titleAlpha <= 0.01;
  self.profileNavigationTitleLabel.textColor = NFBColorText();
  self.profileNavigationSubtitleLabel.textColor = NFBColorSecondaryText();
  self.profileNavigationBackButton.tintColor = (backgroundAlpha < 0.46 && [self profileStringForKey:@"banner"].length > 0) ? UIColor.whiteColor : NFBColorText();
  UIColor *controlTint = (backgroundAlpha < 0.46 && [self profileStringForKey:@"banner"].length > 0) ? UIColor.whiteColor : NFBColorText();
  self.profileNavigationSearchButton.tintColor = controlTint;
  self.profileNavigationMoreButton.tintColor = controlTint;
  if (NSClassFromString(@"UINavigationBarAppearance")) {
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = UIColor.clearColor;
    appearance.shadowColor = [NFBColorBorder() colorWithAlphaComponent:0.72 * backgroundAlpha];
    appearance.titleTextAttributes = @{
      NSForegroundColorAttributeName: [NFBColorText() colorWithAlphaComponent:titleAlpha],
      NSFontAttributeName: NFBFont(19.0, NFBFontWeightHeavy)
    };
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.compactAppearance = appearance;
  } else {
    [self.navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    self.navigationController.navigationBar.shadowImage = [UIImage new];
    self.navigationController.navigationBar.backgroundColor = UIColor.clearColor;
  }
}

- (void)updateProfileNavigationForScrollOffset {
  if (self.kind != NFBTimelineKindProfile) return;
  [self configureProfileCoverChromeViewIfNeeded];
  CGFloat offsetY = MAX(0.0, self.tableView.contentOffset.y);
  CGFloat coverHeight = [self profileExpandedBannerHeight];
  CGFloat minimumBannerHeight = [self profileMinimumBannerHeight];
  CGFloat coverCollapseDistance = [self profileBannerCollapseDistance];
  CGFloat collapseProgress = MIN(1.0, MAX(0.0, offsetY / coverCollapseDistance));
  CGFloat chromeAlpha = [self smoothProfileProgressForOffset:offsetY start:0.0 end:10.0];
  CGFloat backgroundAlpha = [self smoothProfileProgressForOffset:offsetY start:0.0 end:coverCollapseDistance];
  CGFloat titleAlpha = [self smoothProfileProgressForOffset:offsetY start:coverCollapseDistance - 8.0 end:coverCollapseDistance + 36.0];
  CGFloat bannerBlurAlpha = [self smoothProfileProgressForOffset:offsetY start:0.0 end:coverCollapseDistance + 18.0];
  CGFloat bannerHeight = minimumBannerHeight + ((coverHeight - minimumBannerHeight) * (1.0 - collapseProgress));
  CGFloat coverScale = 1.08 - (0.08 * collapseProgress);
  CGFloat expandedHeaderHeight = self.profileExpandedHeaderHeight > 0.0 ? self.profileExpandedHeaderHeight : CGRectGetHeight(self.profileHeaderView.bounds);
  CGFloat headerHeight = expandedHeaderHeight - (coverHeight - bannerHeight);
  self.profileHeaderBannerHeightConstraint.constant = MAX(minimumBannerHeight, bannerHeight);
  self.profileHeaderBannerImageView.transform = CGAffineTransformMakeScale(coverScale, coverScale);
  if (self.profileHeaderView && fabs(self.profileCurrentHeaderHeight - headerHeight) >= 0.5) {
    CGRect headerFrame = self.profileHeaderView.frame;
    headerFrame.size.width = CGRectGetWidth(self.tableView.bounds) > 0.0 ? CGRectGetWidth(self.tableView.bounds) : headerFrame.size.width;
    headerFrame.size.height = headerHeight;
    self.profileHeaderView.frame = headerFrame;
    self.profileCurrentHeaderHeight = headerHeight;
    CGPoint contentOffset = self.tableView.contentOffset;
    self.tableView.tableHeaderView = nil;
    self.tableView.tableHeaderView = self.profileHeaderView;
    self.tableView.contentOffset = contentOffset;
  }
  [self.profileHeaderView layoutIfNeeded];
  CGFloat chromeHeight = MAX([self profileCollapsedChromeHeight], bannerHeight);
  CGRect chromeFrame = self.profileCoverChromeView.frame;
  chromeFrame.origin = CGPointZero;
  chromeFrame.size.width = CGRectGetWidth(self.view.bounds);
  chromeFrame.size.height = chromeHeight;
  self.profileCoverChromeView.frame = chromeFrame;
  self.profileCoverChromeImageView.frame = self.profileCoverChromeView.bounds;
  self.profileCoverChromeBlurView.frame = self.profileCoverChromeView.bounds;
  self.profileCoverChromeScrimView.frame = self.profileCoverChromeView.bounds;
  self.profileCoverChromeImageView.hidden = [self profileStringForKey:@"banner"].length == 0;
  self.profileCoverChromeView.backgroundColor = NFBColorElevatedBackground();
  self.profileCoverChromeImageView.transform = CGAffineTransformMakeScale(coverScale, coverScale);
  self.profileCoverChromeView.alpha = chromeAlpha;
  self.profileCoverChromeView.hidden = chromeAlpha <= 0.01;
  self.profileCoverChromeBlurView.alpha = bannerBlurAlpha;
  self.profileCoverChromeScrimView.alpha = 0.18 + (0.12 * bannerBlurAlpha);
  self.profileBannerBlurView.alpha = bannerBlurAlpha;
  BOOL appearanceChanged = fabs(backgroundAlpha - self.profileNavigationBackgroundAlpha) >= 0.01 ||
      fabs(titleAlpha - self.profileNavigationAlpha) >= 0.01 ||
      !self.profileNavigationAppearanceConfigured;
  self.profileNavigationBackgroundAlpha = backgroundAlpha;
  self.profileNavigationAlpha = titleAlpha;
  if (appearanceChanged) {
    self.profileNavigationAppearanceConfigured = YES;
    [self applyProfileNavigationAppearanceWithBackgroundAlpha:backgroundAlpha titleAlpha:titleAlpha];
  }
}

- (void)backTapped {
  if (self.navigationController.viewControllers.count > 1) {
    [self.navigationController popViewControllerAnimated:YES];
  } else if (self.presentingViewController) {
    [self dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)configureTableView {
  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.estimatedRowHeight = 156.0;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  [self registerTimelineCellsForTableView:self.tableView];

  self.refreshControl = NFBCreateRefreshControl(self, @selector(refreshTimeline));
  self.tableView.refreshControl = self.refreshControl;

  self.emptyStateView = [[UIView alloc] init];
  self.emptyStateView.backgroundColor = UIColor.clearColor;
  self.emptyLoadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
  self.emptyLoadingView.translatesAutoresizingMaskIntoConstraints = NO;
  self.emptyLoadingView.tintColor = NFBColorAccent();
  self.emptyLoadingView.contentMode = UIViewContentModeScaleAspectFit;
  self.emptyLoadingView.hidden = YES;
  self.emptyLabel = [[UILabel alloc] init];
  self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.emptyLabel.textAlignment = NSTextAlignmentCenter;
  self.emptyLabel.textColor = NFBColorSecondaryText();
  self.emptyLabel.font = NFBFont(17.0, NFBFontWeightRegular);
  self.emptyLabel.numberOfLines = 0;
  [self.emptyStateView addSubview:self.emptyLoadingView];
  [self.emptyStateView addSubview:self.emptyLabel];
  [NSLayoutConstraint activateConstraints:@[
    [self.emptyLoadingView.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
    [self.emptyLoadingView.centerYAnchor constraintEqualToAnchor:self.emptyStateView.centerYAnchor constant:-6.0],
    [self.emptyLoadingView.widthAnchor constraintEqualToConstant:28.0],
    [self.emptyLoadingView.heightAnchor constraintEqualToConstant:28.0],
    [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor constant:28.0],
    [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor constant:-28.0],
    [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.emptyStateView.centerYAnchor]
  ]];
  self.tableView.backgroundView = self.emptyStateView;

  if (self.kind == NFBTimelineKindHome || self.kind == NFBTimelineKindLists || self.kind == NFBTimelineKindFeeds) [self configureHomeTabsView];
  if (self.kind == NFBTimelineKindNotifications) [self configureNotificationsTabsView];
  if (self.searchResultsMode) [self configureSearchEmptyState];
  [self.view addSubview:self.tableView];
  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  NSLayoutYAxisAnchor *topAnchor = (self.kind == NFBTimelineKindHome || self.kind == NFBTimelineKindLists || self.kind == NFBTimelineKindFeeds) ? self.homeTabsView.bottomAnchor : (self.kind == NFBTimelineKindNotifications ? self.notificationsTabsView.bottomAnchor : (self.kind == NFBTimelineKindProfile ? self.view.topAnchor : guide.topAnchor));
  if (self.searchPageContentOnly) topAnchor = self.view.topAnchor;
  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
  ]];
  if (self.kind == NFBTimelineKindProfile) [self configureProfileCoverChromeViewIfNeeded];
  if (self.kind == NFBTimelineKindHome) [self configureHomeFeedSwipeGestures];
  if (self.kind == NFBTimelineKindNotifications || self.kind == NFBTimelineKindProfile) [self configureSectionSwipeGesture];
  if (self.kind == NFBTimelineKindFeeds) [self configureFeedResourceLongPressGesture];
}

- (void)registerTimelineCellsForTableView:(UITableView *)tableView {
  [tableView registerClass:[NFBActorCell class] forCellReuseIdentifier:@"searchActor"];
  [tableView registerClass:[NFBPostCell class] forCellReuseIdentifier:@"post"];
  [tableView registerClass:[NFBProfileResourceCell class] forCellReuseIdentifier:@"profileResource"];
  [tableView registerClass:[NFBTrendCell class] forCellReuseIdentifier:@"trend"];
  [tableView registerClass:[NFBNotificationActivityCell class] forCellReuseIdentifier:@"notificationActivity"];
}

- (void)scrollToTopForTabSelection {
  if (self.searchPager) { [self.searchPages[self.searchTab] scrollToTopForTabSelection]; return; }
  if (!self.isViewLoaded || !self.tableView) return;
  if (self.homeFeedPanTracking) [self cancelHomeFeedPan];
  CGFloat topOffsetY = -self.tableView.contentInset.top;
  if (@available(iOS 11.0, *)) {
    topOffsetY = -self.tableView.adjustedContentInset.top;
  }
  CGPoint targetOffset = CGPointMake(self.tableView.contentOffset.x, topOffsetY);
  if (fabs(self.tableView.contentOffset.y - targetOffset.y) <= 1.0) return;
  [self.tableView setContentOffset:targetOffset animated:YES];
}

- (BOOL)isTimelineAtTopForTabSelection {
  if (!self.isViewLoaded || !self.tableView) return NO;
  CGFloat topOffsetY = -self.tableView.contentInset.top;
  if (@available(iOS 11.0, *)) {
    topOffsetY = -self.tableView.adjustedContentInset.top;
  }
  return self.tableView.contentOffset.y <= topOffsetY + 2.0;
}

- (void)configureHomeFeedSwipeGestures {
  if (!self.homeFeedPreviewTableView) {
    self.homeFeedPreviewTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.homeFeedPreviewTableView.scrollsToTop = NO;
    self.homeFeedPreviewTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.homeFeedPreviewTableView.dataSource = self;
    self.homeFeedPreviewTableView.delegate = self;
    self.homeFeedPreviewTableView.estimatedRowHeight = self.tableView.estimatedRowHeight;
    self.homeFeedPreviewTableView.rowHeight = UITableViewAutomaticDimension;
    self.homeFeedPreviewTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    NFBIPAApplyTableViewAppearance(self.homeFeedPreviewTableView);
    self.homeFeedPreviewTableView.userInteractionEnabled = NO;
    self.homeFeedPreviewTableView.hidden = YES;
    self.homeFeedPreviewTableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self registerTimelineCellsForTableView:self.homeFeedPreviewTableView];

    self.homeFeedPreviewLoadingView = [[UIView alloc] init];
    self.homeFeedPreviewLoadingView.backgroundColor = NFBColorBackground();
    self.homeFeedPreviewLoadingImageView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
    self.homeFeedPreviewLoadingImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.homeFeedPreviewLoadingImageView.tintColor = NFBColorAccent();
    self.homeFeedPreviewLoadingImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.homeFeedPreviewLoadingView addSubview:self.homeFeedPreviewLoadingImageView];
    [NSLayoutConstraint activateConstraints:@[
      [self.homeFeedPreviewLoadingImageView.centerXAnchor constraintEqualToAnchor:self.homeFeedPreviewLoadingView.centerXAnchor],
      [self.homeFeedPreviewLoadingImageView.centerYAnchor constraintEqualToAnchor:self.homeFeedPreviewLoadingView.centerYAnchor],
      [self.homeFeedPreviewLoadingImageView.widthAnchor constraintEqualToConstant:28.0],
      [self.homeFeedPreviewLoadingImageView.heightAnchor constraintEqualToConstant:28.0]
    ]];

    [self.view insertSubview:self.homeFeedPreviewTableView belowSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
      [self.homeFeedPreviewTableView.topAnchor constraintEqualToAnchor:self.tableView.topAnchor],
      [self.homeFeedPreviewTableView.leadingAnchor constraintEqualToAnchor:self.tableView.leadingAnchor],
      [self.homeFeedPreviewTableView.trailingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor],
      [self.homeFeedPreviewTableView.bottomAnchor constraintEqualToAnchor:self.tableView.bottomAnchor]
    ]];
  }
  if (self.homeFeedPanGesture) return;
  self.homeFeedPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(homeFeedPanned:)];
  self.homeFeedPanGesture.cancelsTouchesInView = YES;
  self.homeFeedPanGesture.delegate = self;
  [self.tableView addGestureRecognizer:self.homeFeedPanGesture];
}

- (void)configureFeedResourceLongPressGesture {
  if (self.feedResourceLongPressGesture) return;
  self.feedResourceLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(feedResourceLongPressed:)];
  self.feedResourceLongPressGesture.minimumPressDuration = 0.36;
  self.feedResourceLongPressGesture.cancelsTouchesInView = YES;
  self.feedResourceLongPressGesture.delegate = self;
  [self.tableView addGestureRecognizer:self.feedResourceLongPressGesture];
}

- (void)configureSectionSwipeGesture {
  if (self.sectionPanGesture) return;
  self.sectionPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sectionPanned:)];
  self.sectionPanGesture.maximumNumberOfTouches = 1;
  self.sectionPanGesture.delegate = self;
  [self.tableView addGestureRecognizer:self.sectionPanGesture];
}

- (NSArray<NSDictionary *> *)swipeSectionTabs {
  return self.kind == NFBTimelineKindProfile ? [self profileTabDefinitions] : [self notificationTabDefinitions];
}

- (NSInteger)selectedSwipeSectionIndex {
  NSString *selected = self.kind == NFBTimelineKindProfile ? self.selectedProfileTabID : self.selectedNotificationsTabID;
  NSArray *tabs = [self swipeSectionTabs];
  for (NSUInteger index = 0; index < tabs.count; index++) if ([tabs[index][@"id"] isEqualToString:selected]) return index;
  return 0;
}

- (BOOL)nfb_canPageHorizontallyWithVelocity:(CGPoint)velocity {
  if (self.searchPager) return [self.searchPager nfb_canPageHorizontallyWithVelocity:velocity];
  if (!self.sectionPanGesture || self.sectionPanAnimating || self.sectionPanOverlay) return NO;
  NSInteger target = [self selectedSwipeSectionIndex] + (velocity.x < 0 ? 1 : -1);
  return target >= 0 && target < (NSInteger)[self swipeSectionTabs].count;
}

- (void)sectionPanned:(UIPanGestureRecognizer *)gesture {
  CGFloat width = MAX(1.0, CGRectGetWidth(self.tableView.bounds));
  CGPoint velocity = [gesture velocityInView:self.view];
  if (gesture.state == UIGestureRecognizerStateBegan) {
    self.sectionPanDirection = velocity.x < 0 ? 1 : -1;
    self.sectionPanTarget = [self selectedSwipeSectionIndex] + self.sectionPanDirection;
    CGRect viewport = [self.tableView convertRect:self.tableView.bounds toView:self.view];
    NSArray<UIButton *> *buttons = self.kind == NFBTimelineKindProfile ? self.profileTabButtons : self.notificationsTabButtons;
    UIButton *tab = buttons.firstObject;
    if (tab) {
      CGRect tabsFrame = [tab convertRect:tab.bounds toView:self.view];
      CGFloat top = MAX(CGRectGetMinY(viewport), CGRectGetMaxY(tabsFrame));
      viewport.size.height = MAX(0.0, CGRectGetMaxY(viewport) - top);
      viewport.origin.y = top;
    }
    self.sectionPanOverlay = [[UIView alloc] initWithFrame:viewport];
    self.sectionPanOverlay.clipsToBounds = YES;
    self.sectionPanOverlay.backgroundColor = NFBColorBackground();
    CGRect capture = [self.view convertRect:viewport toView:self.tableView];
    self.sectionPanSnapshot = [self.tableView resizableSnapshotViewFromRect:capture afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
    self.sectionPanSnapshot.frame = self.sectionPanOverlay.bounds;
    self.sectionPanIncoming = [[UIView alloc] initWithFrame:self.sectionPanOverlay.bounds];
    self.sectionPanIncoming.backgroundColor = NFBColorBackground();
    UIActivityIndicatorView *loading = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    loading.color = NFBColorSecondaryText();
    loading.center = CGPointMake(width / 2.0, 40.0);
    [loading startAnimating];
    [self.sectionPanIncoming addSubview:loading];
    self.sectionPanIncoming.transform = CGAffineTransformMakeTranslation(self.sectionPanDirection * width, 0.0);
    [self.sectionPanOverlay addSubview:self.sectionPanIncoming];
    if (self.sectionPanSnapshot) [self.sectionPanOverlay addSubview:self.sectionPanSnapshot];
    [self.view addSubview:self.sectionPanOverlay];
    self.suppressTimelineSelectionForSwipe = YES;
    return;
  }
  if (!self.sectionPanOverlay || self.sectionPanAnimating) return;
  CGFloat distance = MIN(width, MAX(0.0, -self.sectionPanDirection * [gesture translationInView:self.view].x));
  CGFloat translation = -self.sectionPanDirection * distance;
  if (gesture.state == UIGestureRecognizerStateChanged) {
    self.sectionPanSnapshot.transform = CGAffineTransformMakeTranslation(translation, 0.0);
    self.sectionPanIncoming.transform = CGAffineTransformMakeTranslation(self.sectionPanDirection * width + translation, 0.0);
    return;
  }
  if (gesture.state != UIGestureRecognizerStateEnded && gesture.state != UIGestureRecognizerStateCancelled && gesture.state != UIGestureRecognizerStateFailed) return;
  BOOL finish = NFBShouldFinishSwipe(distance / width, -self.sectionPanDirection * velocity.x, gesture.state != UIGestureRecognizerStateEnded);
  self.sectionPanAnimating = YES;
  if (finish) {
    NSArray *tabs = [self swipeSectionTabs];
    if (self.sectionPanTarget >= 0 && self.sectionPanTarget < (NSInteger)tabs.count) {
      if (self.kind == NFBTimelineKindProfile) [self selectProfileTabWithID:tabs[self.sectionPanTarget][@"id"]];
      else [self selectNotificationsTabWithID:tabs[self.sectionPanTarget][@"id"] refresh:YES];
    }
  }
  [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    self.sectionPanSnapshot.transform = CGAffineTransformMakeTranslation(finish ? -self.sectionPanDirection * width : 0.0, 0.0);
    self.sectionPanIncoming.transform = CGAffineTransformMakeTranslation(finish ? 0.0 : self.sectionPanDirection * width, 0.0);
  } completion:^(BOOL completed) {
    [self.sectionPanOverlay removeFromSuperview];
    self.sectionPanOverlay = nil;
    self.sectionPanSnapshot = nil;
    self.sectionPanIncoming = nil;
    self.sectionPanAnimating = NO;
    self.suppressTimelineSelectionForSwipe = NO;
  }];
}

- (BOOL)isSearchResultsHost { return self.searchResultsMode && !self.searchPageContentOnly; }

- (void)configureSearchPager {
  self.searchPager = [[NFBSearchPagingScrollView alloc] initWithFrame:CGRectZero];
  self.searchPager.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchPager.pageCount = NFBSearchTabTitles().count;
  self.searchPager.delegate = self;
  [self.view addSubview:self.searchPager];
  [NSLayoutConstraint activateConstraints:@[
    [self.searchPager.topAnchor constraintEqualToAnchor:self.searchTabsView.bottomAnchor],
    [self.searchPager.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.searchPager.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.searchPager.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
  ]];
  NSMutableArray *pages = [NSMutableArray array];
  for (NSInteger index = 0; index < self.searchPager.pageCount; index++) {
    NFBTimelineViewController *page = [[NFBTimelineViewController alloc] initWithSearchQuery:self.searchQuery];
    page.searchPageContentOnly = YES;
    page.searchResultsHost = self;
    page.searchTab = index;
    page.searchFollowingOnly = self.searchFollowingOnly;
    [pages addObject:page];
  }
  self.searchPages = pages;
}
- (void)loadSearchPagesNearIndex:(NSInteger)index {
  for (NSInteger neighbor = MAX(0, index - 1); neighbor <= MIN((NSInteger)self.searchPages.count - 1, index + 1); neighbor++) {
    NFBTimelineViewController *page = self.searchPages[neighbor];
    if (page.parentViewController != self) {
      [self addChildViewController:page];
      // Accessing the view starts only this page's independent first request.
      [self.searchPager addSubview:page.view];
      [page didMoveToParentViewController:self];
    }
    page.view.frame = CGRectMake(neighbor * CGRectGetWidth(self.searchPager.bounds), 0, CGRectGetWidth(self.searchPager.bounds), CGRectGetHeight(self.searchPager.bounds));
    page.tableView.scrollsToTop = neighbor == self.searchTab;
    page.tableView.userInteractionEnabled = !self.searchPagingInteractionSuppressed;
    page.suppressTimelineSelectionForSwipe = self.searchPagingInteractionSuppressed;
  }
}
- (void)layoutSearchPager {
  if (!self.searchPager) return;
  CGSize size = self.searchPager.bounds.size;
  if (size.width <= 0) return;
  BOOL resized = !CGSizeEqualToSize(size, self.searchPagerLayoutSize);
  if (resized) {
    self.searchPagerLayoutSize = size;
    // A size change cancels a partial gesture at the committed category.
    self.searchPager.panGestureRecognizer.enabled = NO;
    self.searchPager.panGestureRecognizer.enabled = YES;
    self.searchPager.contentSize = CGSizeMake(size.width * self.searchPages.count, size.height);
    [self.searchPager setContentOffset:CGPointMake(self.searchTab * size.width, 0) animated:NO];
    for (NSUInteger index = 0; index < self.searchPages.count; index++) {
      NFBTimelineViewController *page = self.searchPages[index];
      if (page.isViewLoaded) page.view.frame = CGRectMake(index * size.width, 0, size.width, size.height);
    }
    [self setSearchPageInteractionEnabled:YES];
  }
  [self loadSearchPagesNearIndex:self.searchTab];
  [self updateSearchPageIndicator];
}
- (void)updateSearchPageIndicator {
  if (!self.searchPager || !self.searchTabButtons.count) return;
  CGFloat width = CGRectGetWidth(self.searchPager.bounds);
  CGFloat progress = width > 0 ? self.searchPager.contentOffset.x / width : self.searchTab;
  progress = MIN(self.searchTabButtons.count - 1, MAX(0, progress));
  NSInteger first = (NSInteger)floor(progress), second = MIN(first + 1, (NSInteger)self.searchTabButtons.count - 1);
  CGFloat fraction = progress - first;
  UIButton *left = self.searchTabButtons[first], *right = self.searchTabButtons[second];
  CGFloat x1 = [left convertPoint:CGPointMake(CGRectGetMidX(left.bounds), 0) toView:self.searchTabsView].x;
  CGFloat x2 = [right convertPoint:CGPointMake(CGRectGetMidX(right.bounds), 0) toView:self.searchTabsView].x;
  CGFloat w1 = MAX(28, [left.currentTitle sizeWithAttributes:@{NSFontAttributeName:left.titleLabel.font}].width);
  CGFloat w2 = MAX(28, [right.currentTitle sizeWithAttributes:@{NSFontAttributeName:right.titleLabel.font}].width);
  self.searchUnderlineCenter.constant = x1 + (x2 - x1) * fraction;
  self.searchUnderlineWidth.constant = w1 + (w2 - w1) * fraction;
  [self.searchTabsView layoutIfNeeded];
}
- (void)setSearchPageInteractionEnabled:(BOOL)enabled {
  self.searchPagingInteractionSuppressed = !enabled;
  for (NFBTimelineViewController *page in self.searchPages) {
    if (!page.isViewLoaded) continue;
    // Native page scrolling cancels a tap on the outgoing row/control.
    page.tableView.userInteractionEnabled = enabled;
    page.suppressTimelineSelectionForSwipe = !enabled;
  }
}
- (void)finishSearchPaging {
  if (!self.searchPager || self.searchPager.dragging || self.searchPager.decelerating) return;
  NSInteger selected = NFBSearchSettledPageForOffset(self.searchPager.contentOffset.x, CGRectGetWidth(self.searchPager.bounds), self.searchPages.count);
  if (selected != self.searchTab) {
    NFBTimelineViewController *previous = self.searchPages[self.searchTab];
    self.searchTab = selected;
    [self loadSearchPagesNearIndex:selected];
    if (self.searchHostAppeared) {
      [previous beginAppearanceTransition:NO animated:YES]; [previous endAppearanceTransition];
      [self.searchPages[selected] beginAppearanceTransition:YES animated:YES]; [self.searchPages[selected] endAppearanceTransition];
    }
  }
  for (NFBTimelineViewController *page in self.searchPages) if (page.isViewLoaded) page.tableView.scrollsToTop = page.searchTab == self.searchTab;
  [self setSearchPageInteractionEnabled:YES];
  [self updateSearchTabs];
  UIButton *selectedButton = self.searchTabButtons[self.searchTab];
  CGRect frame = [selectedButton convertRect:selectedButton.bounds toView:self.searchTabsScrollView];
  [self.searchTabsScrollView scrollRectToVisible:frame animated:NO];
  [self updateSearchPageIndicator];
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
  if (scrollView != self.searchPager) return;
  [self setSearchPageInteractionEnabled:NO];
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
  if (scrollView == self.searchPager && !decelerate) [self finishSearchPaging];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
  if (scrollView == self.searchPager) [self finishSearchPaging];
}
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
  if (scrollView == self.searchPager) [self finishSearchPaging];
}

- (void)configureSearchEmptyState {
  self.searchEmptyView = [[UIView alloc] init]; self.searchEmptyView.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchEmptyTitle = [[UILabel alloc] init]; self.searchEmptyTitle.numberOfLines = 0; self.searchEmptyTitle.font = NFBFont(31, NFBFontWeightHeavy);
  self.searchEmptySubtitle = [[UILabel alloc] init]; self.searchEmptySubtitle.numberOfLines = 0; self.searchEmptySubtitle.font = NFBFont(15, NFBFontWeightRegular);
  UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem]; [settings setTitle:@"Search settings" forState:UIControlStateNormal]; settings.tintColor = NFBColorAccent(); settings.titleLabel.font = NFBFont(15, NFBFontWeightBold); settings.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  [settings addTarget:self action:@selector(searchSettingsTapped) forControlEvents:UIControlEventTouchUpInside];
  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.searchEmptyTitle, self.searchEmptySubtitle, settings]]; stack.translatesAutoresizingMaskIntoConstraints = NO; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 8;
  [self.searchEmptyView addSubview:stack]; [self.emptyStateView addSubview:self.searchEmptyView];
  [NSLayoutConstraint activateConstraints:@[[self.searchEmptyView.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor constant:32], [self.searchEmptyView.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor constant:-32], [self.searchEmptyView.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor constant:32], [stack.leadingAnchor constraintEqualToAnchor:self.searchEmptyView.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:self.searchEmptyView.trailingAnchor], [stack.topAnchor constraintEqualToAnchor:self.searchEmptyView.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:self.searchEmptyView.bottomAnchor], [settings.heightAnchor constraintEqualToConstant:44]]];
  self.searchEmptyView.hidden = YES;
}
- (void)configureSearchResultsNavigation {
  self.title = nil;
  self.navigationItem.searchController = nil;
  UISearchBar *bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 240, 36)];
  bar.searchBarStyle = UISearchBarStyleMinimal;
  bar.placeholder = @"Search Twitter"; bar.text = self.searchQuery; bar.delegate = self;
  bar.tintColor = NFBColorAccent();
  NFBIPAApplySearchTextFieldAppearance(bar.searchTextField, @"Search Twitter");
  bar.searchTextField.backgroundColor = NFBColorElevatedBackground();
  bar.searchTextField.layer.cornerRadius = 18; bar.searchTextField.clipsToBounds = YES;
  self.searchResultsBar = bar;
  self.navigationItem.titleView = bar;
  UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:NFBTemplateIcon(@"nfb_filter") style:UIBarButtonItemStylePlain target:self action:@selector(searchFiltersTapped)];
  filter.accessibilityLabel = @"Search filters";
  if (self.searchFollowingOnly) filter.image = NFBTemplateIcon(@"nfb_filter_filled");
  self.navigationItem.rightBarButtonItem = filter;
  // Saved search/settings actions live on the query's context menu, leaving the
  // reference's compact back / search field / filter navigation row intact.
  [bar addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];
}

- (void)configureSearchTabs {
  self.searchTabsView = [[UIView alloc] init]; self.searchTabsView.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchTabsView.backgroundColor = NFBColorBackground();
  UIScrollView *scroll = [[UIScrollView alloc] init]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.showsHorizontalScrollIndicator = NO;
  scroll.scrollsToTop = NO; scroll.delegate = self; self.searchTabsScrollView = scroll;
  UIStackView *stack = [[UIStackView alloc] init]; stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisHorizontal; stack.distribution = UIStackViewDistributionFillEqually;
  NSMutableArray *buttons = [NSMutableArray array];
  [NFBSearchTabTitles() enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom]; button.tag = index;
    [button setTitle:title forState:UIControlStateNormal];
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    [button addTarget:self action:@selector(searchTabTapped:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:button]; [buttons addObject:button];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:68].active = YES;
  }];
  self.searchTabButtons = buttons;
  UIView *line = [[UIView alloc] init]; line.translatesAutoresizingMaskIntoConstraints = NO; line.backgroundColor = NFBColorBorder();
  [self.view addSubview:self.searchTabsView]; [self.searchTabsView addSubview:scroll]; [scroll addSubview:stack]; [self.searchTabsView addSubview:line];
  [NSLayoutConstraint activateConstraints:@[
    [self.searchTabsView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.searchTabsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.searchTabsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.searchTabsView.heightAnchor constraintEqualToConstant:48],
    [scroll.leadingAnchor constraintEqualToAnchor:self.searchTabsView.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.searchTabsView.trailingAnchor],
    [scroll.topAnchor constraintEqualToAnchor:self.searchTabsView.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.searchTabsView.bottomAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
    [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
    [stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor], [stack.widthAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    [line.leadingAnchor constraintEqualToAnchor:self.searchTabsView.leadingAnchor], [line.trailingAnchor constraintEqualToAnchor:self.searchTabsView.trailingAnchor],
    [line.bottomAnchor constraintEqualToAnchor:self.searchTabsView.bottomAnchor], [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  self.searchTabUnderline = [[UIView alloc] init]; self.searchTabUnderline.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchTabUnderline.backgroundColor = NFBColorAccent(); self.searchTabUnderline.layer.cornerRadius = 2;
  [self.searchTabsView addSubview:self.searchTabUnderline];
  [self.searchTabUnderline.heightAnchor constraintEqualToConstant:4].active = YES;
  [self.searchTabUnderline.bottomAnchor constraintEqualToAnchor:self.searchTabsView.bottomAnchor].active = YES;
  [self updateSearchTabs];

}
- (void)updateSearchTabs {
  if (!self.searchTabsView) return;
  self.searchTabsView.backgroundColor = NFBColorBackground();
  for (UIButton *button in self.searchTabButtons) {
    BOOL selected = button.tag == self.searchTab;
    [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
    button.titleLabel.font = NFBFont(15, selected ? NFBFontWeightHeavy : NFBFontWeightBold);
    button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
  }
  UIButton *selected = self.searchTabButtons[self.searchTab];
  self.searchUnderlineCenter.active = NO; self.searchUnderlineWidth.active = NO;
  self.searchUnderlineCenter = [self.searchTabUnderline.centerXAnchor constraintEqualToAnchor:self.searchTabsView.leadingAnchor constant:[selected convertPoint:CGPointMake(CGRectGetMidX(selected.bounds), 0) toView:self.searchTabsView].x];
  self.searchUnderlineWidth = [self.searchTabUnderline.widthAnchor constraintEqualToConstant:MAX(28, [selected.currentTitle sizeWithAttributes:@{NSFontAttributeName:selected.titleLabel.font}].width)];
  self.searchUnderlineCenter.active = YES; self.searchUnderlineWidth.active = YES;
  [self updateSearchPageIndicator];
}
- (void)searchTabTapped:(UIButton *)button {
  if (!self.searchPager || self.searchPager.dragging || !self.searchHostAppeared) return;
  NSInteger target = button.tag;
  if (target < 0 || target >= (NSInteger)self.searchPages.count) return;
  [self loadSearchPagesNearIndex:target];
  [self setSearchPageInteractionEnabled:NO];
  CGPoint offset = CGPointMake(target * CGRectGetWidth(self.searchPager.bounds), 0);
  if (fabs(self.searchPager.contentOffset.x - offset.x) < 0.5) { [self finishSearchPaging]; return; }
  [self.searchPager setContentOffset:offset animated:YES];
}
- (void)restartSearch {
  if (self.searchPager) {
    self.searchPager.panGestureRecognizer.enabled = NO;
    [self.searchPager setContentOffset:CGPointMake(self.searchTab * CGRectGetWidth(self.searchPager.bounds), 0) animated:NO];
    self.searchPager.panGestureRecognizer.enabled = YES;
    [self setSearchPageInteractionEnabled:YES];
    for (NFBTimelineViewController *page in self.searchPages) {
      page.searchQuery = self.searchQuery; page.searchFollowingOnly = self.searchFollowingOnly;
      if (page.isViewLoaded) [page restartSearch];
    }
    [self updateSearchTabs];
    return;
  }
  ++self.timelineLoadGeneration;
  self.loading = NO; self.searchEmptyPageCount = 0;
  self.cursor = nil; [self.items removeAllObjects];
  self.tableView.tableFooterView = nil;
  [self.tableView reloadData]; [self.tableView setContentOffset:CGPointZero animated:NO];
  [self refreshTimeline];
}
- (NSArray<NSDictionary *> *)filteredSearchItems:(NSArray<NSDictionary *> *)items {
  NSMutableArray *filtered = [NSMutableArray array];
  BOOL people = self.searchTab == NFBSearchTabPeople;
  for (NSDictionary *item in items) {
    if (NFBSearchResultMatches(item, people, self.searchFollowingOnly, self.searchTab, NFBSearchHidesSensitiveContent(), NFBSearchExcludesMutedAccounts()) && (people || NFBSearchCountsMatch(item[@"post"], self.searchQuery))) [filtered addObject:item];
  }
  return filtered;
}
- (void)continueFilteredSearchIfNeeded:(NSUInteger)pageCount {
  if (!self.searchResultsMode) return;
  if (pageCount > 0) self.searchEmptyPageCount = 0;
  else self.searchEmptyPageCount++;
  if (self.cursor.length > 0) {
    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem]; more.frame = CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 52);
    [more setTitle:@"Show more results" forState:UIControlStateNormal]; more.tintColor = NFBColorAccent(); more.titleLabel.font = NFBFont(15, NFBFontWeightBold);
    [more addTarget:self action:@selector(loadMoreSearchResults) forControlEvents:UIControlEventTouchUpInside];
    self.tableView.tableFooterView = more;
    if (pageCount == 0 && self.searchEmptyPageCount < 5) [self loadNextPageReplacing:NO];
  } else self.tableView.tableFooterView = nil;
}
- (void)loadMoreSearchResults { self.searchEmptyPageCount = 0; [self loadNextPageReplacing:NO]; }
- (void)advancedSearchTapped {
  NFBAdvancedSearchViewController *advanced = [[NFBAdvancedSearchViewController alloc] initWithQuery:self.searchQuery];
  __weak typeof(self) weakSelf = self;
  advanced.search = ^(NSString *query) { if (![weakSelf ownsCurrentAccount]) return; [NFBSearchTypeaheadViewController addRecentSearchQuery:query]; [weakSelf performSearchQuery:query]; };
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:advanced]; NFBApplyNavigationAppearance(nav);
  [self presentViewController:nav animated:YES completion:nil];
}
- (void)searchFiltersTapped { [self presentSearchOptions:NO]; }
- (void)searchSettingsTapped {
  if (self.searchResultsHost) { [self.searchResultsHost searchSettingsTapped]; return; }
  [self presentSearchOptions:YES];
}
- (void)presentSearchOptions:(BOOL)settings {
  NFBSearchOptionsViewController *options = [[NFBSearchOptionsViewController alloc] initWithSettings:settings];
  options.followingOnly = self.searchFollowingOnly;
  options.query = self.searchQuery;
  __weak typeof(self) weakSelf = self;
  options.openAdvancedSearch = ^{ [weakSelf advancedSearchTapped]; };
  options.openSettings = ^{ [weakSelf searchSettingsTapped]; };
  options.applyFilters = ^(BOOL following) { weakSelf.searchFollowingOnly = following; [weakSelf configureSearchResultsNavigation]; [weakSelf restartSearch]; };
  options.settingsChanged = ^{ [weakSelf restartSearch]; };
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:options]; NFBApplyNavigationAppearance(nav);
  [self presentViewController:nav animated:YES completion:nil];
}
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
  __weak typeof(self) weakSelf = self;
  return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    BOOL saved = [NFBSavedSearches() containsObject:strongSelf.searchQuery];
    UIAction *save = [UIAction actionWithTitle:saved ? @"Remove from saved search" : @"Save search" image:NFBTemplateIcon(@"nfb_bookmark") identifier:nil handler:^(UIAction *action) { NFBSetSearchSaved(weakSelf.searchQuery, !saved); }];
    UIAction *settings = [UIAction actionWithTitle:@"Search settings" image:NFBTemplateIcon(@"nfb_settings") identifier:nil handler:^(UIAction *action) { [weakSelf searchSettingsTapped]; }];
    return [UIMenu menuWithTitle:@"" children:@[save, settings]];
  }];
}
- (void)actorCellDidTapFollow:(NFBActorCell *)cell {
  NSString *did = cell.profile[@"did"];
  __weak typeof(self) weakSelf = self;
  [[self postActionCoordinator] performFollowForProfile:cell.profile sourceView:cell.followButton completion:^(NSDictionary *profile, NSError *error) {
    if (error || ![weakSelf ownsCurrentAccount] || weakSelf.searchTab != NFBSearchTabPeople) return;
    for (NSUInteger index = 0; index < weakSelf.items.count; index++) {
      if ([weakSelf.items[index][@"did"] isEqualToString:did]) { weakSelf.items[index] = profile; break; }
    }
    [weakSelf.tableView reloadData];
  }];
}

- (void)configureHomeTabsView {
  self.homeTabsView = [[UIView alloc] init];
  self.homeTabsView.translatesAutoresizingMaskIntoConstraints = NO;
  self.homeTabsView.backgroundColor = NFBColorBackground();

  self.homeTabsScrollView = [[UIScrollView alloc] init];
  self.homeTabsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.homeTabsScrollView.showsHorizontalScrollIndicator = NO;
  self.homeTabsScrollView.alwaysBounceHorizontal = YES;
  self.homeTabsScrollView.scrollsToTop = NO;
  self.homeTabsScrollView.backgroundColor = NFBColorBackground();

  self.homeTabsStack = [[UIStackView alloc] init];
  self.homeTabsStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.homeTabsStack.axis = UILayoutConstraintAxisHorizontal;
  self.homeTabsStack.alignment = UIStackViewAlignmentFill;
  self.homeTabsStack.distribution = UIStackViewDistributionFill;

  self.homeTabsBorder = [[UIView alloc] init];
  self.homeTabsBorder.translatesAutoresizingMaskIntoConstraints = NO;
  self.homeTabsBorder.backgroundColor = NFBColorBorder();

  self.homeTabUnderline = [[UIView alloc] init];
  self.homeTabUnderline.translatesAutoresizingMaskIntoConstraints = NO;
  self.homeTabUnderline.backgroundColor = NFBColorAccent();
  self.homeTabUnderline.layer.cornerRadius = 2.0;

  [self.homeTabsView addSubview:self.homeTabsScrollView];
  [self.homeTabsScrollView addSubview:self.homeTabsStack];
  [self.homeTabsView addSubview:self.homeTabsBorder];
  [self.homeTabsView addSubview:self.homeTabUnderline];
  [self.view addSubview:self.homeTabsView];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.homeTabsView.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [self.homeTabsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.homeTabsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.homeTabsView.heightAnchor constraintEqualToConstant:53.0],
    [self.homeTabsScrollView.topAnchor constraintEqualToAnchor:self.homeTabsView.topAnchor],
    [self.homeTabsScrollView.leadingAnchor constraintEqualToAnchor:self.homeTabsView.leadingAnchor],
    [self.homeTabsScrollView.trailingAnchor constraintEqualToAnchor:self.homeTabsView.trailingAnchor],
    [self.homeTabsScrollView.bottomAnchor constraintEqualToAnchor:self.homeTabsView.bottomAnchor],
    [self.homeTabsStack.topAnchor constraintEqualToAnchor:self.homeTabsScrollView.contentLayoutGuide.topAnchor],
    [self.homeTabsStack.leadingAnchor constraintEqualToAnchor:self.homeTabsScrollView.contentLayoutGuide.leadingAnchor],
    [self.homeTabsStack.trailingAnchor constraintEqualToAnchor:self.homeTabsScrollView.contentLayoutGuide.trailingAnchor],
    [self.homeTabsStack.bottomAnchor constraintEqualToAnchor:self.homeTabsScrollView.contentLayoutGuide.bottomAnchor],
    [self.homeTabsStack.heightAnchor constraintEqualToAnchor:self.homeTabsScrollView.frameLayoutGuide.heightAnchor],
    [self.homeTabsStack.widthAnchor constraintGreaterThanOrEqualToAnchor:self.homeTabsScrollView.frameLayoutGuide.widthAnchor],
    [self.homeTabsBorder.leadingAnchor constraintEqualToAnchor:self.homeTabsView.leadingAnchor],
    [self.homeTabsBorder.trailingAnchor constraintEqualToAnchor:self.homeTabsView.trailingAnchor],
    [self.homeTabsBorder.bottomAnchor constraintEqualToAnchor:self.homeTabsView.bottomAnchor],
    [self.homeTabsBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.homeTabUnderline.bottomAnchor constraintEqualToAnchor:self.homeTabsView.bottomAnchor],
    [self.homeTabUnderline.widthAnchor constraintEqualToConstant:56.0],
    [self.homeTabUnderline.heightAnchor constraintEqualToConstant:4.0]
  ]];
  [self rebuildHomeTabButtons];
}

- (UIButton *)homeTabButtonWithTitle:(NSString *)title selected:(BOOL)selected {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [button setTitle:title forState:UIControlStateNormal];
  [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
  button.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  button.titleLabel.numberOfLines = 1;
  button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  button.titleLabel.textAlignment = NSTextAlignmentCenter;
  button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
  button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
  NSLayoutConstraint *minimumWidth = [button.widthAnchor constraintGreaterThanOrEqualToConstant:128.0];
  NSLayoutConstraint *maximumWidth = [button.widthAnchor constraintLessThanOrEqualToConstant:176.0];
  minimumWidth.identifier = @"nfbFeedTabMinimumWidth";
  maximumWidth.identifier = @"nfbFeedTabMaximumWidth";
  maximumWidth.priority = UILayoutPriorityDefaultHigh;
  minimumWidth.active = YES;
  maximumWidth.active = YES;
  [button addTarget:self action:@selector(homeFeedTabTapped:) forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (void)loadHomeFeedTabs {
  if (![self ownsCurrentAccount]) return;
  [[NFBAtprotoClient sharedClient] fetchSubscribedHomeFeedsWithCompletion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount]) return;
      NSMutableArray *tabs = [@[
        @{@"type": @"for-you", @"label": @"For you"},
        @{@"type": @"following", @"label": @"Following"}
      ] mutableCopy];
      if (!error) {
        NSSet *fixedForYouLabels = [NSSet setWithArray:@[@"discover", @"for you", @"for-you"]];
        NSMutableSet *addedURIs = [NSMutableSet set];
        for (NSDictionary *item in items) {
          NSString *label = [item[@"label"] isKindOfClass:NSString.class] ? item[@"label"] : @"";
          NSString *normalized = [[[label lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"  " withString:@" "];
          NSString *uri = [item[@"uri"] isKindOfClass:NSString.class] ? item[@"uri"] : @"";
          if (label.length == 0 || uri.length == 0 || [fixedForYouLabels containsObject:normalized] || [addedURIs containsObject:uri]) continue;
          [addedURIs addObject:uri];
          [tabs addObject:item];
        }
      }
      self.homeFeedTabs = tabs;
      if (self.selectedHomeFeedIndex >= (NSInteger)tabs.count) self.selectedHomeFeedIndex = 0;
      [self rebuildHomeTabButtons];
      [self prefetchAdjacentHomeFeeds];
    });
  }];
}

- (NSArray<NSDictionary *> *)defaultHomeFeedTabs {
  return @[
    @{@"type": @"for-you", @"label": @"For you"},
    @{@"type": @"following", @"label": @"Following"}
  ];
}

- (void)resetHomeFeedTabsForAccountChange {
  if (self.kind != NFBTimelineKindHome) return;
  self.selectedHomeFeedIndex = 0;
  self.homeFeedTabs = [self defaultHomeFeedTabs];
  [self.homeFeedItemsCache removeAllObjects];
  [self.homeFeedCursorCache removeAllObjects];
  [self.homeFeedPrefetchingIndexes removeAllObjects];
  [self hideHomeFeedPreview];
  [self rebuildHomeTabButtons];
}

- (void)rebuildHomeTabButtons {
  if (!self.homeTabsStack) return;
  for (UIView *view in self.homeTabsStack.arrangedSubviews) {
    [self.homeTabsStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
  [self.homeFeedTabs enumerateObjectsUsingBlock:^(NSDictionary *tab, NSUInteger index, BOOL *stop) {
    (void)stop;
    NSString *title = [tab[@"label"] isKindOfClass:NSString.class] ? tab[@"label"] : @"Feed";
    UIButton *button = [self homeTabButtonWithTitle:title selected:(NSInteger)index == self.selectedHomeFeedIndex];
    button.tag = (NSInteger)index;
    [self.homeTabsStack addArrangedSubview:button];
    [buttons addObject:button];
  }];
  self.homeTabButtons = buttons;
  [self updateHomeTabsSelection];
}

- (void)collapseInactiveHomeFeedTabs {
  BOOL changed = NO;
  for (UIButton *button in self.homeTabButtons) {
    if (button.tag == self.selectedHomeFeedIndex) continue;
    for (NSLayoutConstraint *constraint in button.constraints) {
      CGFloat width;
      if ([constraint.identifier isEqualToString:@"nfbFeedTabMinimumWidth"]) width = 128.0;
      else if ([constraint.identifier isEqualToString:@"nfbFeedTabMaximumWidth"]) width = 176.0;
      else continue;
      if (constraint.constant != width) {
        constraint.constant = width;
        changed = YES;
      }
    }
  }
  if (changed) [self.homeTabsView layoutIfNeeded];
}

- (void)updateHomeTabsSelection {
  // Shared by tab taps, completed swipes and programmatic feed changes.
  [self collapseInactiveHomeFeedTabs];
  [self.homeTabButtons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
    (void)stop;
    BOOL selected = (NSInteger)index == self.selectedHomeFeedIndex;
    [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
    button.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
    button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
  }];
  if (self.selectedHomeFeedIndex < (NSInteger)self.homeTabButtons.count) {
    UIButton *button = self.homeTabButtons[(NSUInteger)self.selectedHomeFeedIndex];
    self.homeTabUnderline.hidden = NO;
    self.homeTabUnderlineCenterXConstraint.active = NO;
    self.homeTabUnderlineCenterXConstraint = [self.homeTabUnderline.centerXAnchor constraintEqualToAnchor:button.centerXAnchor];
    self.homeTabUnderlineCenterXConstraint.active = YES;
    [self.homeTabsScrollView scrollRectToVisible:button.frame animated:YES];
  } else {
    self.homeTabUnderline.hidden = YES;
  }
}

- (void)homeFeedTabTapped:(UIButton *)sender {
  [sender layoutIfNeeded];
  NSString *fullName = [sender titleForState:UIControlStateNormal] ?: @"";
  CGFloat textWidth = [fullName sizeWithAttributes:@{NSFontAttributeName:sender.titleLabel.font}].width;
  CGFloat availableWidth = CGRectGetWidth([sender contentRectForBounds:sender.bounds]);
  BOOL truncated = textWidth > availableWidth + 0.5;
  if (sender.tag != self.selectedHomeFeedIndex) [self switchToHomeFeedIndex:sender.tag direction:0 animated:NO];
  if (truncated) {
    CGFloat expandedWidth = ceil(textWidth) + sender.contentEdgeInsets.left + sender.contentEdgeInsets.right;
    for (NSLayoutConstraint *constraint in sender.constraints) {
      if ([constraint.identifier isEqualToString:@"nfbFeedTabMinimumWidth"] ||
          [constraint.identifier isEqualToString:@"nfbFeedTabMaximumWidth"]) {
        constraint.constant = MAX(176.0, expandedWidth);
      }
    }
    [self.homeTabsView layoutIfNeeded];
    // Very long names remain readable by scrolling the strip from the title's start.
    CGRect visibleTitle = sender.frame;
    visibleTitle.size.width = MIN(CGRectGetWidth(visibleTitle), CGRectGetWidth(self.homeTabsScrollView.bounds));
    [self.homeTabsScrollView scrollRectToVisible:visibleTitle animated:YES];
  }
}

- (NSNumber *)homeFeedCacheKeyForIndex:(NSInteger)index {
  return @(MAX(0, index));
}

- (void)cacheCurrentHomeFeedState {
  if (self.kind != NFBTimelineKindHome || self.selectedHomeFeedIndex < 0) return;
  NSNumber *key = [self homeFeedCacheKeyForIndex:self.selectedHomeFeedIndex];
  self.homeFeedItemsCache[key] = [self.items copy] ?: @[];
  if (self.cursor.length > 0) self.homeFeedCursorCache[key] = self.cursor;
  else [self.homeFeedCursorCache removeObjectForKey:key];
}

- (NSArray<NSDictionary *> *)cachedHomeFeedItemsForIndex:(NSInteger)index {
  NSArray *items = self.homeFeedItemsCache[[self homeFeedCacheKeyForIndex:index]];
  return [items isKindOfClass:NSArray.class] ? items : @[];
}

- (NSString *)cachedHomeFeedCursorForIndex:(NSInteger)index {
  NSString *cursor = self.homeFeedCursorCache[[self homeFeedCacheKeyForIndex:index]];
  return [cursor isKindOfClass:NSString.class] ? cursor : nil;
}

- (void)prepareHomeFeedPreviewForIndex:(NSInteger)index direction:(NSInteger)direction translation:(CGFloat)translation {
  if (index < 0 || index >= (NSInteger)self.homeFeedTabs.count || !self.homeFeedPreviewTableView) return;
  CGFloat width = MAX(1.0, CGRectGetWidth(self.tableView.bounds));
  self.homeFeedPreviewIndex = index;
  self.homeFeedPreviewItems = [self cachedHomeFeedItemsForIndex:index];
  BOOL hasCachedItems = self.homeFeedPreviewItems.count > 0;
  self.homeFeedPreviewTableView.backgroundView = hasCachedItems ? nil : self.homeFeedPreviewLoadingView;
  if (hasCachedItems) NFBStopLoadingAnimation(self.homeFeedPreviewLoadingImageView);
  else NFBStartLoadingAnimation(self.homeFeedPreviewLoadingImageView);
  [self.homeFeedPreviewTableView reloadData];
  self.homeFeedPreviewTableView.hidden = NO;
  self.homeFeedPreviewTableView.contentOffset = CGPointZero;
  self.homeFeedPreviewTableView.transform = CGAffineTransformMakeTranslation((direction > 0 ? width : -width) + translation, 0.0);
  [self.view bringSubviewToFront:self.homeFeedPreviewTableView];
  [self.view bringSubviewToFront:self.tableView];
  [self restoreFloatingComposeButtonVisibility];
}

- (void)hideHomeFeedPreview {
  self.homeFeedPreviewTableView.hidden = YES;
  self.homeFeedPreviewTableView.transform = CGAffineTransformIdentity;
  self.homeFeedPreviewTableView.backgroundView = nil;
  self.homeFeedPreviewItems = @[];
  self.homeFeedPreviewIndex = NSNotFound;
  NFBStopLoadingAnimation(self.homeFeedPreviewLoadingImageView);
  [self restoreFloatingComposeButtonVisibility];
}

- (void)prefetchHomeFeedAtIndex:(NSInteger)index {
  if (![self ownsCurrentAccount]) return;
  if (index < 0 || index >= (NSInteger)self.homeFeedTabs.count) return;
  NSNumber *key = [self homeFeedCacheKeyForIndex:index];
  if (self.homeFeedItemsCache[key] || [self.homeFeedPrefetchingIndexes containsObject:key]) return;
  [self.homeFeedPrefetchingIndexes addObject:key];
  NSDictionary *tab = self.homeFeedTabs[(NSUInteger)index];
  NFBAtprotoArrayCompletion completion = ^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self ownsCurrentAccount]) return;
      [self.homeFeedPrefetchingIndexes removeObject:key];
      if (error) return;
      self.homeFeedItemsCache[key] = items ?: @[];
      if (cursor.length > 0) self.homeFeedCursorCache[key] = cursor;
    });
  };
  NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"for-you";
  if ([type isEqualToString:@"following"]) {
    [[NFBAtprotoClient sharedClient] fetchHomeTimelineWithCursor:nil completion:completion];
  } else if ([type isEqualToString:@"feed"]) {
    NSString *uri = [tab[@"uri"] isKindOfClass:NSString.class] ? tab[@"uri"] : @"";
    if (uri.length > 0) [[NFBAtprotoClient sharedClient] fetchFeedWithURI:uri cursor:nil completion:completion];
    else [self.homeFeedPrefetchingIndexes removeObject:key];
  } else {
    [[NFBAtprotoClient sharedClient] fetchDiscoverFeedWithCursor:nil completion:completion];
  }
}

- (void)prefetchAdjacentHomeFeeds {
  if (self.kind != NFBTimelineKindHome) return;
  [self prefetchHomeFeedAtIndex:self.selectedHomeFeedIndex - 1];
  [self prefetchHomeFeedAtIndex:self.selectedHomeFeedIndex + 1];
}

- (void)homeFeedPanned:(UIPanGestureRecognizer *)gesture {
  if (self.kind != NFBTimelineKindHome || self.homeFeedSwitchAnimating) return;

  CGPoint translation = [gesture translationInView:self.tableView];
  CGPoint velocity = [gesture velocityInView:self.tableView];
  CGFloat width = MAX(1.0, CGRectGetWidth(self.tableView.bounds));
  NSInteger direction = translation.x < 0.0 ? 1 : -1;
  NSInteger targetIndex = self.selectedHomeFeedIndex + direction;
  BOOL canMove = targetIndex >= 0 && targetIndex < (NSInteger)self.homeFeedTabs.count;
  CGFloat clampedTranslation = translation.x;
  if (!canMove) clampedTranslation *= 0.18;

  if (gesture.state == UIGestureRecognizerStateBegan) {
    [self beginSuppressingTimelineSelectionForSwipe];
    return;
  }

  if (gesture.state == UIGestureRecognizerStateChanged) {
    if (canMove) {
      [self prepareHomeFeedPreviewForIndex:targetIndex direction:direction translation:clampedTranslation];
    } else {
      [self hideHomeFeedPreview];
    }
    self.tableView.transform = CGAffineTransformMakeTranslation(clampedTranslation, 0.0);
    return;
  }

  if (gesture.state == UIGestureRecognizerStateEnded) {
    BOOL shouldCommit = canMove && NFBShouldFinishSwipe(fabs(translation.x) / width, -direction * velocity.x, false);
    if (shouldCommit) {
      [self finishHomeFeedPanToIndex:targetIndex direction:direction currentTranslation:clampedTranslation velocity:velocity.x];
    } else {
      [self cancelHomeFeedPan];
    }
    return;
  }

  if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
    [self cancelHomeFeedPan];
  }
}

- (void)beginSuppressingTimelineSelectionForSwipe {
  self.homeFeedPanTracking = YES;
  self.suppressTimelineSelectionForSwipe = YES;
  self.tableView.allowsSelection = NO;
  NSIndexPath *selectedPath = self.tableView.indexPathForSelectedRow;
  if (selectedPath) [self.tableView deselectRowAtIndexPath:selectedPath animated:NO];
}

- (void)endSuppressingTimelineSelectionAfterSwipe {
  self.homeFeedPanTracking = NO;
  self.tableView.allowsSelection = YES;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (!self.homeFeedPanTracking) self.suppressTimelineSelectionForSwipe = NO;
  });
}

- (void)cancelHomeFeedPan {
  [UIView animateWithDuration:0.18
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                   animations:^{
    self.tableView.transform = CGAffineTransformIdentity;
    self.homeFeedPreviewTableView.transform = CGAffineTransformIdentity;
  } completion:^(BOOL finished) {
    (void)finished;
    [self hideHomeFeedPreview];
    [self endSuppressingTimelineSelectionAfterSwipe];
  }];
}

- (void)finishHomeFeedPanToIndex:(NSInteger)index direction:(NSInteger)direction currentTranslation:(CGFloat)currentTranslation velocity:(CGFloat)velocityX {
  (void)currentTranslation;
  if (index < 0 || index >= (NSInteger)self.homeFeedTabs.count || index == self.selectedHomeFeedIndex) {
    [self cancelHomeFeedPan];
    return;
  }

  CGFloat width = MAX(1.0, CGRectGetWidth(self.tableView.bounds));
  UIView *outgoingSnapshot = [self.tableView snapshotViewAfterScreenUpdates:NO];
  outgoingSnapshot.frame = self.tableView.frame;
  outgoingSnapshot.transform = self.tableView.transform;
  [self.view addSubview:outgoingSnapshot];

  [self cacheCurrentHomeFeedState];
  NSArray<NSDictionary *> *cachedDestinationItems = [self cachedHomeFeedItemsForIndex:index];
  NSString *cachedDestinationCursor = [self cachedHomeFeedCursorForIndex:index];
  self.tableView.transform = CGAffineTransformMakeTranslation(direction > 0 ? width : -width, 0.0);
  self.selectedHomeFeedIndex = index;
  [self updateHomeTabsSelection];
  [self.items removeAllObjects];
  if (cachedDestinationItems.count > 0) {
    [self.items addObjectsFromArray:cachedDestinationItems];
    self.cursor = cachedDestinationCursor;
    self.hasLoadedOnce = YES;
    [self updateEmptyState:@""];
  } else {
    self.cursor = nil;
    self.hasLoadedOnce = NO;
  }
  [self.tableView reloadData];
  if (cachedDestinationItems.count == 0) [self refreshTimeline];

  CGFloat outgoingTarget = direction > 0 ? -width : width;
  CGFloat duration = fabs(velocityX) > 900.0 ? 0.18 : 0.24;
  self.homeFeedSwitchAnimating = YES;
  [UIView animateWithDuration:duration
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                   animations:^{
    outgoingSnapshot.transform = CGAffineTransformMakeTranslation(outgoingTarget, 0.0);
    self.tableView.transform = CGAffineTransformIdentity;
  } completion:^(BOOL finished) {
    (void)finished;
    [outgoingSnapshot removeFromSuperview];
    self.tableView.transform = CGAffineTransformIdentity;
    [self hideHomeFeedPreview];
    self.homeFeedSwitchAnimating = NO;
    [self endSuppressingTimelineSelectionAfterSwipe];
    [self prefetchAdjacentHomeFeeds];
  }];
}

- (void)switchToHomeFeedIndex:(NSInteger)index direction:(NSInteger)direction animated:(BOOL)animated {
  if (self.kind != NFBTimelineKindHome && self.kind != NFBTimelineKindLists && self.kind != NFBTimelineKindFeeds) return;
  if (self.homeFeedSwitchAnimating) return;
  if (index < 0 || index >= (NSInteger)self.homeFeedTabs.count || index == self.selectedHomeFeedIndex) return;

  if (self.kind == NFBTimelineKindHome) [self cacheCurrentHomeFeedState];
  [self dismissFeedResourceMenuAnimated:NO];
  self.selectedHomeFeedIndex = index;
  [self updateHomeTabsSelection];
  [self.items removeAllObjects];
  [self.tableView reloadData];
  [self refreshTimeline];

  if (!animated) return;
  CGFloat width = MAX(1.0, CGRectGetWidth(self.tableView.bounds));
  CGFloat startOffset = direction >= 0 ? width : -width;
  self.homeFeedSwitchAnimating = YES;
  self.tableView.transform = CGAffineTransformMakeTranslation(startOffset, 0.0);
  [UIView animateWithDuration:0.22
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                   animations:^{
    self.tableView.transform = CGAffineTransformIdentity;
  } completion:^(BOOL finished) {
    (void)finished;
    self.homeFeedSwitchAnimating = NO;
  }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  if (gestureRecognizer == self.feedResourceLongPressGesture) {
    if (self.kind != NFBTimelineKindFeeds) return NO;
    CGPoint location = [gestureRecognizer locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    return [self feedResourceItemAtIndexPath:indexPath].count > 0;
  }
  if (gestureRecognizer == self.sectionPanGesture) {
    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
    CGPoint point = [gestureRecognizer locationInView:self.view];
    if (fabs(velocity.x) <= fabs(velocity.y) || (point.x < 24.0 && velocity.x > 0.0)) return NO;
    if (NFBTouchIsInHorizontalScroller(self.view, point)) return NO;
    return [self nfb_canPageHorizontallyWithVelocity:velocity];
  }
  if (gestureRecognizer == self.homeFeedPanGesture) {
    if (self.kind != NFBTimelineKindHome || self.homeFeedTabs.count <= 1 || self.homeFeedSwitchAnimating) return NO;
    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.tableView];
    if (fabs(velocity.x) <= fabs(velocity.y)) return NO;
    CGPoint location = [gestureRecognizer locationInView:self.view];
    UIView *hit = [self.view hitTest:location withEvent:nil];
    for (UIView *view = hit; view && view != self.tableView; view = view.superview) {
      if ([view isKindOfClass:UIScrollView.class] && ((UIScrollView *)view).contentSize.width > CGRectGetWidth(view.bounds) + 1.0) return NO;
    }
    if (location.x < 24.0 && velocity.x > 0.0) return NO;
    NSInteger targetIndex = self.selectedHomeFeedIndex + (velocity.x < 0.0 ? 1 : -1);
    if (targetIndex < 0 || targetIndex >= (NSInteger)self.homeFeedTabs.count) return NO;
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  if (gestureRecognizer == self.homeFeedPanGesture || otherGestureRecognizer == self.homeFeedPanGesture) {
    return NO;
  }
  return NO;
}

- (NSArray<NSDictionary *> *)notificationTabDefinitions {
  return @[
    @{@"id": @"all", @"title": @"All"},
    @{@"id": @"mentions", @"title": @"Mentions"}
  ];
}

- (NSArray<NSString *> *)notificationReasonsForSelectedTab {
  if ([self.selectedNotificationsTabID isEqualToString:@"mentions"]) return @[@"mention", @"reply", @"quote"];
  return nil;
}

- (void)configureNotificationsTabsView {
  if (![self notificationTabIDIsAvailable:self.selectedNotificationsTabID]) {
    self.selectedNotificationsTabID = @"all";
  }

  self.notificationsTabsView = [[UIView alloc] init];
  self.notificationsTabsView.translatesAutoresizingMaskIntoConstraints = NO;
  self.notificationsTabsView.backgroundColor = NFBColorBackground();

  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisHorizontal;
  stack.alignment = UIStackViewAlignmentFill;
  stack.distribution = UIStackViewDistributionFillEqually;

  self.notificationsTabsBorder = [[UIView alloc] init];
  self.notificationsTabsBorder.translatesAutoresizingMaskIntoConstraints = NO;
  self.notificationsTabsBorder.backgroundColor = NFBColorBorder();

  NSMutableArray *buttons = [NSMutableArray array];
  NSArray<NSDictionary *> *tabs = [self notificationTabDefinitions];
  [tabs enumerateObjectsUsingBlock:^(NSDictionary *tab, NSUInteger index, BOOL *stop) {
    (void)stop;
    UIButton *button = [self notificationTabButtonWithTitle:tab[@"title"] selected:[tab[@"id"] isEqualToString:self.selectedNotificationsTabID]];
    button.tag = (NSInteger)index;
    [button addTarget:self action:@selector(notificationTabTapped:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:button];
    [buttons addObject:button];
  }];
  self.notificationsTabButtons = buttons;

  [self.notificationsTabsView addSubview:stack];
  [self.notificationsTabsView addSubview:self.notificationsTabsBorder];
  [self.view addSubview:self.notificationsTabsView];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.notificationsTabsView.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [self.notificationsTabsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.notificationsTabsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.notificationsTabsView.heightAnchor constraintEqualToConstant:53.0],
    [stack.topAnchor constraintEqualToAnchor:self.notificationsTabsView.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:self.notificationsTabsView.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:self.notificationsTabsView.trailingAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:self.notificationsTabsView.bottomAnchor],
    [self.notificationsTabsBorder.leadingAnchor constraintEqualToAnchor:self.notificationsTabsView.leadingAnchor],
    [self.notificationsTabsBorder.trailingAnchor constraintEqualToAnchor:self.notificationsTabsView.trailingAnchor],
    [self.notificationsTabsBorder.bottomAnchor constraintEqualToAnchor:self.notificationsTabsView.bottomAnchor],
    [self.notificationsTabsBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
}

- (BOOL)notificationTabIDIsAvailable:(NSString *)tabID {
  if (![tabID isKindOfClass:NSString.class]) return NO;
  for (NSDictionary *tab in [self notificationTabDefinitions]) {
    NSString *availableID = [tab[@"id"] isKindOfClass:NSString.class] ? tab[@"id"] : @"";
    if ([availableID isEqualToString:tabID]) return YES;
  }
  return NO;
}

- (NSInteger)notificationTabIndexForID:(NSString *)tabID {
  NSArray<NSDictionary *> *tabs = [self notificationTabDefinitions];
  for (NSUInteger index = 0; index < tabs.count; index++) {
    NSString *availableID = [tabs[index][@"id"] isKindOfClass:NSString.class] ? tabs[index][@"id"] : @"";
    if ([availableID isEqualToString:tabID]) return (NSInteger)index;
  }
  return NSNotFound;
}

- (UIButton *)notificationTabButtonWithTitle:(NSString *)title selected:(BOOL)selected {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [button setTitle:title forState:UIControlStateNormal];
  [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
  button.titleLabel.font = NFBFont(15.0, selected ? NFBFontWeightHeavy : NFBFontWeightBold);
  UIView *underline = [[UIView alloc] init];
  underline.translatesAutoresizingMaskIntoConstraints = NO;
  underline.backgroundColor = NFBColorAccent();
  underline.layer.cornerRadius = 2.0;
  underline.hidden = !selected;
  underline.tag = NFBProfileTabUnderlineTag;
  [button addSubview:underline];
  [NSLayoutConstraint activateConstraints:@[
    [underline.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
    [underline.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
    [underline.widthAnchor constraintEqualToConstant:56.0],
    [underline.heightAnchor constraintEqualToConstant:4.0]
  ]];
  return button;
}

- (void)updateNotificationsTabSelection {
  NSArray<NSDictionary *> *tabs = [self notificationTabDefinitions];
  [self.notificationsTabButtons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
    (void)stop;
    NSString *tabID = index < tabs.count ? tabs[index][@"id"] : @"";
    BOOL selected = [tabID isEqualToString:self.selectedNotificationsTabID];
    [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
    button.titleLabel.font = NFBFont(15.0, selected ? NFBFontWeightHeavy : NFBFontWeightBold);
    for (UIView *subview in button.subviews) {
      if (subview.tag == NFBProfileTabUnderlineTag) {
        subview.hidden = !selected;
        subview.backgroundColor = NFBColorAccent();
      }
    }
  }];
}

- (void)switchNotificationsTabInDirection:(NSInteger)direction {
  if (self.kind != NFBTimelineKindNotifications || direction == 0) return;
  NSArray<NSDictionary *> *tabs = [self notificationTabDefinitions];
  NSInteger currentIndex = [self notificationTabIndexForID:self.selectedNotificationsTabID ?: @"all"];
  if (currentIndex == NSNotFound) currentIndex = 0;
  NSInteger targetIndex = currentIndex + direction;
  if (targetIndex < 0 || targetIndex >= (NSInteger)tabs.count) return;
  NSString *tabID = [tabs[(NSUInteger)targetIndex][@"id"] isKindOfClass:NSString.class] ? tabs[(NSUInteger)targetIndex][@"id"] : @"all";
  [self selectNotificationsTabWithID:tabID refresh:YES];
}

- (void)selectNotificationsTabWithID:(NSString *)tabID refresh:(BOOL)refresh {
  if (self.kind != NFBTimelineKindNotifications) return;
  if (![self notificationTabIDIsAvailable:tabID]) tabID = @"all";
  BOOL changed = ![tabID isEqualToString:self.selectedNotificationsTabID];
  if (changed) {
    self.selectedNotificationsTabID = [tabID copy];
    self.timelineLoadGeneration++;
    self.loading = NO;
    self.cursor = nil;
    self.hasLoadedOnce = NO;
    self.refreshSuccessSoundPending = NO;
    [self.refreshControl endRefreshing];
    [self.items removeAllObjects];
    [self.tableView reloadData];
  }
  [self updateNotificationsTabSelection];
  if (refresh || changed) [self refreshTimeline];
}

- (void)notificationTabTapped:(UIButton *)sender {
  NSArray<NSDictionary *> *tabs = [self notificationTabDefinitions];
  if (sender.tag < 0 || sender.tag >= (NSInteger)tabs.count) return;
  NSString *tabID = tabs[(NSUInteger)sender.tag][@"id"];
  if (![tabID isKindOfClass:NSString.class] || [tabID isEqualToString:self.selectedNotificationsTabID]) return;
  self.selectedNotificationsTabID = tabID;
  self.timelineLoadGeneration++;
  self.loading = NO;
  self.cursor = nil;
  self.hasLoadedOnce = NO;
  self.refreshSuccessSoundPending = NO;
  [self.refreshControl endRefreshing];
  [self updateNotificationsTabSelection];
  [self.items removeAllObjects];
  [self.tableView reloadData];
  [self refreshTimeline];
}

- (NSDictionary *)currentHomeFeedTab {
  if (self.selectedHomeFeedIndex >= 0 && self.selectedHomeFeedIndex < (NSInteger)self.homeFeedTabs.count) {
    return self.homeFeedTabs[(NSUInteger)self.selectedHomeFeedIndex];
  }
  return @{@"type": @"for-you", @"label": @"For you"};
}

- (void)handleHomeTabReselectionWithUnreadBadgeCount:(NSUInteger)badgeCount {
  if (self.kind != NFBTimelineKindHome) {
    [self scrollToTopForTabSelection];
    return;
  }

  NSDictionary *currentTab = [self currentHomeFeedTab];
  NSString *currentType = [currentTab[@"type"] isKindOfClass:NSString.class] ? currentTab[@"type"] : @"for-you";
  BOOL viewingMainFeed = [currentType isEqualToString:@"for-you"];
  if (badgeCount > 0 && viewingMainFeed && [self isTimelineAtTopForTabSelection]) {
    __block NSInteger followingIndex = -1;
    [self.homeFeedTabs enumerateObjectsUsingBlock:^(NSDictionary *tab, NSUInteger index, BOOL *stop) {
      NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"";
      if ([type isEqualToString:@"following"]) {
        followingIndex = (NSInteger)index;
        *stop = YES;
      }
    }];
    if (followingIndex >= 0) {
      if (self.homeFeedPanTracking) [self cancelHomeFeedPan];
      [self switchToHomeFeedIndex:followingIndex direction:1 animated:NO];
      return;
    }
  }

  [self scrollToTopForTabSelection];
}

- (void)configureFloatingComposeButtonIfNeeded {
  if (self.searchPageContentOnly) return;
  if (self.kind != NFBTimelineKindHome && self.kind != NFBTimelineKindSearch) return;
  if (self.composeButton) {
    [self restoreFloatingComposeButtonVisibility];
    return;
  }
  self.composeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.composeButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.composeButton.backgroundColor = NFBColorAccent();
  self.composeButton.layer.cornerRadius = 28.0;
  self.composeButton.layer.shadowColor = UIColor.blackColor.CGColor;
  self.composeButton.layer.shadowOpacity = 0.35;
  self.composeButton.layer.shadowRadius = 10.0;
  self.composeButton.layer.shadowOffset = CGSizeMake(0, 4);
  [self.composeButton setImage:NFBTemplateIcon(@"nfb_compose") forState:UIControlStateNormal];
  self.composeButton.tintColor = UIColor.whiteColor;
  self.composeButton.imageEdgeInsets = UIEdgeInsetsMake(14.0, 14.0, 14.0, 14.0);
  [self.composeButton addTarget:self action:@selector(composeTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.composeButton];
  [NSLayoutConstraint activateConstraints:@[
    [self.composeButton.widthAnchor constraintEqualToConstant:56.0],
    [self.composeButton.heightAnchor constraintEqualToConstant:56.0],
    [self.composeButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-18.0],
    [self.composeButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18.0]
  ]];
  [self restoreFloatingComposeButtonVisibility];
}

- (void)restoreFloatingComposeButtonVisibility {
  if (self.searchPageContentOnly) return;
  if (self.kind != NFBTimelineKindHome && self.kind != NFBTimelineKindSearch) return;
  if (!self.isViewLoaded) return;
  if (!self.composeButton || self.composeButton.superview != self.view) {
    [self configureFloatingComposeButtonIfNeeded];
    return;
  }
  self.composeButton.hidden = NO;
  self.composeButton.alpha = 1.0;
  self.composeButton.enabled = YES;
  self.composeButton.backgroundColor = NFBColorAccent();
  [self.view bringSubviewToFront:self.composeButton];
}

- (BOOL)requiresAuth {
  return self.kind == NFBTimelineKindHome ||
         self.kind == NFBTimelineKindNotifications ||
         self.kind == NFBTimelineKindBookmarks ||
         self.kind == NFBTimelineKindLists ||
         self.kind == NFBTimelineKindFeeds ||
         (self.kind == NFBTimelineKindProfile && self.actor.length == 0);
}

- (void)refreshTimeline {
  if (self.searchPager) { [self.searchPages[self.searchTab] refreshTimeline]; return; }
  if (self.searchResultsMode) { ++self.timelineLoadGeneration; self.loading = NO; self.searchEmptyPageCount = 0; }
  if (self.kind == NFBTimelineKindBookmarks && self.loading) {
    [self.refreshControl endRefreshing];
    return;
  }
  if (self.refreshControl.isRefreshing) {
    self.refreshSuccessSoundPending = YES;
    NFBPlaySound(@"pull.aac");
  }
  self.cursor = nil;
  self.hasLoadedOnce = NO;
  [self loadNextPageReplacing:YES];
}

- (void)loadNextPageReplacing:(BOOL)replacing {
  if (![self ownsCurrentAccount]) return;
  if (self.loading) {
    self.refreshSuccessSoundPending = NO;
    [self.refreshControl endRefreshing];
    return;
  }

  if ([self requiresAuth] && ![[NFBAtprotoSession sharedSession] hasSession]) {
    [self.bookmarkItems removeAllObjects];
    [self.items removeAllObjects];
    [self.tableView reloadData];
    self.refreshSuccessSoundPending = NO;
    [self.refreshControl endRefreshing];
    [self updateEmptyState:@"Sign in with Bluesky to load this tab."];
    return;
  }

  if (self.kind == NFBTimelineKindSearch) [self updateSearchHeaderVisible:!self.searchResultsMode && self.searchQuery.length == 0];

  self.loading = YES;
  [self updateEmptyState:(!self.hasLoadedOnce || ((self.kind == NFBTimelineKindBookmarks || self.searchResultsMode) && self.items.count == 0)) ? @"Loading..." : @""];
  NSString *nextCursor = replacing ? nil : self.cursor;
  NSUInteger requestGeneration = ++self.timelineLoadGeneration;
  NSString *requestProfileTabID = self.kind == NFBTimelineKindProfile ? (self.selectedProfileTabID ?: @"tweets") : @"";

  __weak typeof(self) weakSelf = self;
  NFBAtprotoArrayCompletion completion = ^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if (![strongSelf ownsCurrentAccount] || requestGeneration != strongSelf.timelineLoadGeneration) return;
      if (requestProfileTabID.length > 0 && ![requestProfileTabID isEqualToString:strongSelf.selectedProfileTabID ?: @"tweets"]) return;
      strongSelf.loading = NO;
      strongSelf.hasLoadedOnce = YES;
      BOOL shouldPlayRefreshSound = strongSelf.refreshSuccessSoundPending;
      strongSelf.refreshSuccessSoundPending = NO;
      [strongSelf.refreshControl endRefreshing];

      if (error) {
        [strongSelf updateEmptyState:error.localizedDescription ?: @"Could not load Bluesky data."];
        return;
      }

      if (shouldPlayRefreshSound) NFBPlaySound(@"refresh.aac");
      NSArray<NSDictionary *> *displayItems = strongSelf.kind == NFBTimelineKindNotifications ? [strongSelf groupedNotificationItemsFromItems:items ?: @[]] : (items ?: @[]);
      if (strongSelf.searchResultsMode) displayItems = [strongSelf filteredSearchItems:displayItems];
      if (strongSelf.kind == NFBTimelineKindBookmarks) {
        if (replacing) [strongSelf.bookmarkItems removeAllObjects];
        [strongSelf.bookmarkItems addObjectsFromArray:displayItems];
        [strongSelf filterBookmarkItems];
      } else {
        if (replacing) [strongSelf.items removeAllObjects];
        if (strongSelf.searchResultsMode) {
          NSMutableSet *seen = [NSMutableSet set];
          BOOL people = strongSelf.searchTab == NFBSearchTabPeople;
          for (NSDictionary *existing in strongSelf.items) [seen addObject:(people ? existing[@"did"] : existing[@"post"][@"uri"]) ?: @""];
          for (NSDictionary *item in displayItems) {
            NSString *key = (people ? item[@"did"] : item[@"post"][@"uri"]) ?: @"";
            if (key.length && ![seen containsObject:key]) { [strongSelf.items addObject:item]; [seen addObject:key]; }
          }
        } else if (displayItems.count > 0) [strongSelf.items addObjectsFromArray:displayItems];
      }
      strongSelf.cursor = ((strongSelf.kind == NFBTimelineKindBookmarks || strongSelf.searchResultsMode) && [cursor isEqualToString:nextCursor]) ? nil : cursor;
      if (strongSelf.kind == NFBTimelineKindHome) {
        NSNumber *key = [strongSelf homeFeedCacheKeyForIndex:strongSelf.selectedHomeFeedIndex];
        strongSelf.homeFeedItemsCache[key] = [strongSelf.items copy] ?: @[];
        if (strongSelf.cursor.length > 0) strongSelf.homeFeedCursorCache[key] = strongSelf.cursor;
        else [strongSelf.homeFeedCursorCache removeObjectForKey:key];
      }
      [strongSelf.tableView reloadData];
      [strongSelf updateEmptyState:strongSelf.items.count == 0 ? [strongSelf emptyMessageForCurrentView] : @""];
      if (strongSelf.kind == NFBTimelineKindHome && replacing) {
        NSDictionary *tab = [strongSelf currentHomeFeedTab];
        NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"for-you";
        if ([type isEqualToString:@"following"]) {
          [[NFBNotificationCoordinator sharedCoordinator] clearHomeBadgeWithFeedItems:items ?: @[]];
        }
      }
      if (strongSelf.kind == NFBTimelineKindNotifications && replacing) {
        [[NFBAtprotoClient sharedClient] markNotificationsSeenWithCompletion:^(NSDictionary *value, NSError *markError) {
          (void)value;
          if (!markError) [[NFBNotificationCoordinator sharedCoordinator] clearNotificationBadge];
        }];
      }
      if (strongSelf.kind == NFBTimelineKindHome && replacing) [strongSelf prefetchAdjacentHomeFeeds];
      [strongSelf loadRemainingBookmarksForSearch];
      [strongSelf continueFilteredSearchIfNeeded:displayItems.count];
    });
  };

  if (self.kind == NFBTimelineKindHome) {
    [self refreshAccountChrome];
    NSDictionary *tab = [self currentHomeFeedTab];
    NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"for-you";
    if ([type isEqualToString:@"following"]) {
      [[NFBAtprotoClient sharedClient] fetchHomeTimelineWithCursor:nextCursor completion:completion];
    } else if ([type isEqualToString:@"feed"]) {
      [[NFBAtprotoClient sharedClient] fetchFeedWithURI:tab[@"uri"] cursor:nextCursor completion:completion];
    } else {
      [[NFBAtprotoClient sharedClient] fetchDiscoverFeedWithCursor:nextCursor completion:completion];
    }
  } else if (self.kind == NFBTimelineKindSearch) {
    if (!self.searchResultsMode && self.searchQuery.length == 0) {
      [[NFBAtprotoClient sharedClient] fetchTrendingTopicsWithCompletion:completion];
    } else if (self.searchQuery.length == 0) {
      completion(@[], nil, nil);
    } else {
      if (self.searchTab == NFBSearchTabPeople) [[NFBAtprotoClient sharedClient] searchActors:self.searchQuery limit:25 cursor:nextCursor completion:completion];
      else [[NFBAtprotoClient sharedClient] searchPosts:self.searchQuery sort:self.searchTab == NFBSearchTabLatest ? @"latest" : @"top" followingOnly:self.searchFollowingOnly mediaTab:self.searchTab cursor:nextCursor completion:completion];
    }
  } else if (self.kind == NFBTimelineKindNotifications) {
    [[NFBAtprotoClient sharedClient] fetchNotificationsWithCursor:nextCursor reasons:[self notificationReasonsForSelectedTab] completion:completion];
  } else if (self.kind == NFBTimelineKindBookmarks) {
    [[NFBAtprotoClient sharedClient] fetchBookmarksWithCursor:nextCursor completion:completion];
  } else if (self.kind == NFBTimelineKindLists) {
    NSDictionary *tab = [self currentHomeFeedTab];
    NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"follow-lists";
    [[NFBAtprotoClient sharedClient] fetchCurrentUserListsForKind:[type isEqualToString:@"block-lists"] ? @"block" : @"follow" completion:completion];
  } else if (self.kind == NFBTimelineKindFeeds) {
    NSDictionary *tab = [self currentHomeFeedTab];
    NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"saved-feeds";
    if ([type isEqualToString:@"discover-feeds"]) {
      [[NFBAtprotoClient sharedClient] searchFeedGenerators:self.searchQuery ?: @"" cursor:nextCursor completion:completion];
    } else {
      [[NFBAtprotoClient sharedClient] fetchSavedFeedResourcesWithCompletion:completion];
    }
  } else if (self.kind == NFBTimelineKindFeedTimeline) {
    [self loadFeedPageWithCursor:nextCursor completion:completion];
  } else if (self.kind == NFBTimelineKindListTimeline) {
    [[NFBAtprotoClient sharedClient] fetchListFeedWithURI:self.actor ?: @"" cursor:nextCursor completion:completion];
  } else {
    NSString *actor = self.actor.length > 0 ? self.actor : ([NFBAtprotoSession sharedSession].did ?: [NFBAtprotoSession sharedSession].handle);
    BOOL profileNeedsHeader = self.profile == nil || ![self.loadedProfileActor isEqualToString:actor];
    BOOL profileHeaderLoading = self.loadingProfileActor.length > 0 && [self.loadingProfileActor isEqualToString:actor];
    NSString *tabID = self.selectedProfileTabID ?: @"tweets";
    NSString *profileFilter = [self authorFeedFilterForProfileTab:tabID];
    void (^loadProfileTimeline)(void) = ^{
      if ([self profileTabUsesAuthorFeed:tabID]) {
        NFBAtprotoArrayCompletion profileCompletion = completion;
        BOOL shouldPrependPinned = [self shouldDisplayPinnedPostForProfileTab:tabID replacing:replacing cursor:nextCursor];
        NSString *pinnedURI = shouldPrependPinned ? [self profilePinnedPostURI] : @"";
        if (pinnedURI.length > 0) {
          __weak typeof(self) weakTimeline = self;
          profileCompletion = ^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
            if (error) {
              completion(items, cursor, error);
              return;
            }
            [[NFBAtprotoClient sharedClient] fetchPostForURI:pinnedURI completion:^(NSDictionary *pinnedPost, NSError *pinnedError) {
              __strong typeof(weakTimeline) strongTimeline = weakTimeline;
              if (!strongTimeline || pinnedError || pinnedPost.count == 0) {
                completion(items, cursor, nil);
                return;
              }
              completion([strongTimeline profileItems:items byPrependingPinnedPost:pinnedPost uri:pinnedURI], cursor, nil);
            }];
          };
        }
        if ([tabID isEqualToString:@"with_replies"]) {
          [[NFBAtprotoClient sharedClient] fetchAuthorFeedWithRepliesForActor:actor cursor:nextCursor completion:profileCompletion];
        } else {
          [[NFBAtprotoClient sharedClient] fetchAuthorFeedForActor:actor filter:profileFilter cursor:nextCursor completion:profileCompletion];
        }
      } else if ([tabID isEqualToString:@"articles"]) {
        [[NFBAtprotoClient sharedClient] fetchAuthorArticlesForActor:actor cursor:nextCursor completion:completion];
      } else if ([tabID isEqualToString:@"likes"]) {
        [[NFBAtprotoClient sharedClient] fetchActorLikesForActor:actor cursor:nextCursor completion:completion];
      } else if ([tabID isEqualToString:@"lists"]) {
        [[NFBAtprotoClient sharedClient] fetchListsForActor:actor cursor:nextCursor completion:completion];
      } else if ([tabID isEqualToString:@"starter-packs"]) {
        [[NFBAtprotoClient sharedClient] fetchStarterPacksForActor:actor cursor:nextCursor completion:completion];
      } else {
        completion(@[], nil, nil);
      }
    };

    if (replacing && profileNeedsHeader && !profileHeaderLoading) {
      [self loadProfileHeaderForActor:actor completion:^(BOOL success) {
        if (![self ownsCurrentAccount] || requestGeneration != self.timelineLoadGeneration) return;
        if (!success) {
          self.loading = NO;
          self.hasLoadedOnce = YES;
          self.refreshSuccessSoundPending = NO;
          [self.refreshControl endRefreshing];
          [self updateEmptyState:@"Could not load this profile."];
          return;
        }
        loadProfileTimeline();
      }];
    } else {
      if (profileNeedsHeader && !profileHeaderLoading) [self loadProfileHeaderForActor:actor];
      loadProfileTimeline();
    }
  }
}

- (NSString *)emptyMessageForCurrentView {
  if (self.kind == NFBTimelineKindSearch) {
    if (self.searchQuery.length == 0) return self.searchResultsMode ? @"No results found." : @"No trends right now.";
    if (self.cursor.length) return @"No matching results yet. Tap Show more results to keep searching.";
    return [NSString stringWithFormat:@"No results for “%@”\n\nTry searching for something else, or check your search settings.", self.searchQuery];
  }
  if (self.kind == NFBTimelineKindNotifications) {
    return [self notificationEmptyStateSubtitle];
  }
  if (self.kind == NFBTimelineKindBookmarks) {
    if (self.searchQuery.length > 0) return @"No Bookmarks match your search.";
    return @"You haven't added any Tweets to your Bookmarks yet.";
  }
  if (self.kind == NFBTimelineKindLists) {
    NSDictionary *tab = [self currentHomeFeedTab];
    NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"follow-lists";
    return [type isEqualToString:@"block-lists"] ? @"No Block Lists yet." : @"You haven't made any Follow Lists yet.";
  }
  if (self.kind == NFBTimelineKindFeeds) {
    NSDictionary *tab = [self currentHomeFeedTab];
    NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"saved-feeds";
    return [type isEqualToString:@"discover-feeds"] ? @"No Feeds found." : @"No saved Feeds yet.";
  }
  if (self.kind == NFBTimelineKindFeedTimeline) return @"No Tweets in this Feed yet.";
  if (self.kind == NFBTimelineKindListTimeline) return @"No Tweets in this List yet.";
  if (self.kind != NFBTimelineKindProfile) return @"Nothing to show yet.";
  NSString *tabID = self.selectedProfileTabID ?: @"tweets";
  if ([tabID isEqualToString:@"likes"]) return @"No Likes yet.";
  if ([tabID isEqualToString:@"lists"]) return @"No Lists yet.";
  if ([tabID isEqualToString:@"starter-packs"]) return @"No Starter Packs yet.";
  if ([tabID isEqualToString:@"articles"]) return @"No Articles yet.";
  if ([tabID isEqualToString:@"media"]) return @"No Media yet.";
  if ([tabID isEqualToString:@"with_replies"]) return @"No Tweets and replies yet.";
  return @"No Tweets yet.";
}

- (NSString *)notificationEmptyStateTitle {
  if ([self.selectedNotificationsTabID isEqualToString:@"mentions"]) return @"Join the conversation";
  return @"Nothing to see here \u2014 yet";
}

- (NSString *)notificationEmptyStateSubtitle {
  if ([self.selectedNotificationsTabID isEqualToString:@"mentions"]) {
    return @"When someone on Twitter mentions you in a Tweet or reply, you\u2019ll find it here.";
  }
  return @"Notifications about new Tweets, Retweets, recommendations, and more will show up here as you follow more people.";
}

- (BOOL)isNotificationEmptyStateMessage:(NSString *)message {
  if (self.kind != NFBTimelineKindNotifications || message.length == 0) return NO;
  return [message isEqualToString:[self notificationEmptyStateSubtitle]];
}

- (NSAttributedString *)notificationEmptyStateAttributedString {
  NSString *title = [self notificationEmptyStateTitle];
  NSString *subtitle = [self notificationEmptyStateSubtitle];
  NSString *text = [NSString stringWithFormat:@"%@\n%@", title, subtitle];

  NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
  paragraph.alignment = NSTextAlignmentCenter;
  paragraph.lineSpacing = 5.0;

  NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
    NSParagraphStyleAttributeName: paragraph,
    NSForegroundColorAttributeName: NFBColorSecondaryText(),
    NSFontAttributeName: NFBFont(15.0, NFBFontWeightRegular)
  }];
  [attributed addAttributes:@{
    NSForegroundColorAttributeName: NFBColorText(),
    NSFontAttributeName: NFBFont(21.0, NFBFontWeightHeavy)
  } range:NSMakeRange(0, title.length)];
  return attributed;
}

- (NSString *)dismissedNotificationActivityGroupsDefaultsKey {
  NSString *did = [NFBAtprotoSession sharedSession].did ?: @"";
  if (did.length == 0) did = @"anonymous";
  return [NSString stringWithFormat:@"%@:%@", NFBDismissedNotificationActivityGroupsDefaultsKey, did];
}

- (NSSet<NSString *> *)dismissedNotificationActivityGroupKeys {
  NSArray *storedKeys = [NSUserDefaults.standardUserDefaults arrayForKey:[self dismissedNotificationActivityGroupsDefaultsKey]];
  NSMutableSet<NSString *> *keys = [NSMutableSet set];
  for (id value in storedKeys ?: @[]) {
    if ([value isKindOfClass:NSString.class] && [value length] > 0) [keys addObject:value];
  }
  return keys;
}

- (NSString *)positiveFeedbackNotificationActivityGroupsDefaultsKey {
  NSString *did = [NFBAtprotoSession sharedSession].did ?: @"";
  if (did.length == 0) did = @"anonymous";
  return [NSString stringWithFormat:@"%@:%@", NFBPositiveNotificationActivityGroupsDefaultsKey, did];
}

- (NSSet<NSString *> *)positiveFeedbackNotificationActivityGroupKeys {
  NSArray *storedKeys = [NSUserDefaults.standardUserDefaults arrayForKey:[self positiveFeedbackNotificationActivityGroupsDefaultsKey]];
  NSMutableSet<NSString *> *keys = [NSMutableSet set];
  for (id value in storedKeys ?: @[]) {
    if ([value isKindOfClass:NSString.class] && [value length] > 0) [keys addObject:value];
  }
  return keys;
}

- (void)addPositiveFeedbackNotificationActivityGroupKey:(NSString *)key {
  if (key.length == 0) return;
  NSMutableSet<NSString *> *keys = [[self positiveFeedbackNotificationActivityGroupKeys] mutableCopy];
  [keys addObject:key];
  NSArray *sorted = [keys.allObjects sortedArrayUsingSelector:@selector(compare:)];
  [NSUserDefaults.standardUserDefaults setObject:sorted forKey:[self positiveFeedbackNotificationActivityGroupsDefaultsKey]];
  [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)addDismissedNotificationActivityGroupKey:(NSString *)key {
  if (key.length == 0) return;
  NSMutableSet<NSString *> *keys = [[self dismissedNotificationActivityGroupKeys] mutableCopy];
  [keys addObject:key];
  NSArray *sorted = [keys.allObjects sortedArrayUsingSelector:@selector(compare:)];
  [NSUserDefaults.standardUserDefaults setObject:sorted forKey:[self dismissedNotificationActivityGroupsDefaultsKey]];
  [NSUserDefaults.standardUserDefaults synchronize];
}

- (BOOL)isTweetNotificationReason:(NSString *)reason {
  return [reason isEqualToString:@"mention"] ||
         [reason isEqualToString:@"reply"] ||
         [reason isEqualToString:@"quote"] ||
         [reason isEqualToString:@"subscribed-post"];
}

- (NSArray<NSDictionary *> *)groupedNotificationItemsFromItems:(NSArray<NSDictionary *> *)rawItems {
  NSMutableArray<NSDictionary *> *displayItems = [NSMutableArray array];
  NSMutableDictionary<NSString *, NSMutableDictionary *> *groupsByKey = [NSMutableDictionary dictionary];
  NSSet<NSString *> *dismissedGroupKeys = [self dismissedNotificationActivityGroupKeys];
  NSSet<NSString *> *positiveFeedbackGroupKeys = [self positiveFeedbackNotificationActivityGroupKeys];

  for (NSDictionary *item in rawItems) {
    if (![item isKindOfClass:NSDictionary.class]) continue;
    if ([NFBNotificationCoordinator notificationItemIsMutedByConversationSetting:item]) continue;
    NSString *reason = [item[@"reason"] isKindOfClass:NSString.class] ? item[@"reason"] : @"";
    if ([self isTweetNotificationReason:reason]) {
      if ([reason isEqualToString:@"subscribed-post"]) {
        NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
        NSDictionary *author = [item[@"author"] isKindOfClass:NSDictionary.class] ? item[@"author"] : nil;
        if (!author) author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
        if (![NFBNotificationCoordinator subscribedPostNotificationItem:item matchesActivityNotificationPreferencesForProfile:author]) continue;
      }
      NSMutableDictionary *tweetItem = [item mutableCopy];
      tweetItem[@"type"] = @"notificationTweet";
      [displayItems addObject:tweetItem];
      continue;
    }

    if ([self notificationItemIsHiddenByAdvancedFilters:item]) continue;

    NSString *key = [self notificationActivityGroupKeyForItem:item];
    if ([dismissedGroupKeys containsObject:key]) continue;
    NSMutableDictionary *group = groupsByKey[key];
    if (!group) {
      BOOL profileRoute = [self notificationItemRoutesToProfile:item];
      NSDictionary *post = profileRoute ? @{} : ([NFBAtprotoClient postFromFeedItem:item] ?: @{});
      NSString *text = profileRoute ? @"" : ([NFBAtprotoClient textForPost:post] ?: @"");
      group = [@{
        @"type": @"notificationActivityGroup",
        @"reason": reason ?: @"",
        @"groupKey": key ?: @"",
        @"route": profileRoute ? @"profile" : @"post",
        @"users": [NSMutableArray array],
        @"text": text,
        @"post": post,
	        @"targetURI": [item[@"targetURI"] isKindOfClass:NSString.class] ? item[@"targetURI"] : @"",
	        @"createdAt": [item[@"createdAt"] isKindOfClass:NSString.class] ? item[@"createdAt"] : @"",
	        @"isRead": @YES,
	        @"positiveFeedback": @([positiveFeedbackGroupKeys containsObject:key])
	      } mutableCopy];
      groupsByKey[key] = group;
      [displayItems addObject:group];
    }

    NSMutableArray *users = [group[@"users"] isKindOfClass:NSMutableArray.class] ? group[@"users"] : nil;
    NSDictionary *author = [item[@"author"] isKindOfClass:NSDictionary.class] ? item[@"author"] : @{};
    [self addNotificationAuthor:author toUsers:users];
    BOOL itemRead = [item[@"isRead"] respondsToSelector:@selector(boolValue)] ? [item[@"isRead"] boolValue] : YES;
    if (!itemRead) group[@"isRead"] = @NO;
    NSString *createdAt = [item[@"createdAt"] isKindOfClass:NSString.class] ? item[@"createdAt"] : @"";
    NSString *currentCreatedAt = [group[@"createdAt"] isKindOfClass:NSString.class] ? group[@"createdAt"] : @"";
    if (createdAt.length > 0 && [createdAt compare:currentCreatedAt] == NSOrderedDescending) {
      group[@"createdAt"] = createdAt;
      if (![self notificationGroupRoutesToProfile:group]) {
        NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item] ?: @{};
        group[@"post"] = post;
        NSString *text = [NFBAtprotoClient textForPost:post];
        group[@"text"] = text ?: @"";
      }
    }
  }

  [displayItems sortUsingComparator:^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
    NSString *firstDate = [first[@"createdAt"] isKindOfClass:NSString.class] ? first[@"createdAt"] : @"";
    NSString *secondDate = [second[@"createdAt"] isKindOfClass:NSString.class] ? second[@"createdAt"] : @"";
    return [secondDate compare:firstDate];
  }];
  return displayItems;
}

- (BOOL)advancedNotificationFilterEnabledForKey:(NSString *)key {
  return key.length > 0 && [NSUserDefaults.standardUserDefaults boolForKey:key];
}

- (BOOL)anyAdvancedNotificationFilterEnabled {
  return [self advancedNotificationFilterEnabledForKey:NFBNotificationFilterQualityKey] ||
         [self advancedNotificationFilterEnabledForKey:NFBNotificationFilterYouDoNotFollowKey] ||
         [self advancedNotificationFilterEnabledForKey:NFBNotificationFilterNotFollowingYouKey] ||
         [self advancedNotificationFilterEnabledForKey:NFBNotificationFilterNewAccountsKey] ||
         [self advancedNotificationFilterEnabledForKey:NFBNotificationFilterDefaultAvatarKey];
}

- (BOOL)notificationItemIsHiddenByAdvancedFilters:(NSDictionary *)item {
  if (![self anyAdvancedNotificationFilterEnabled]) return NO;
  NSDictionary *author = [item[@"author"] isKindOfClass:NSDictionary.class] ? item[@"author"] : @{};
  if (author.count == 0) return [self advancedNotificationFilterEnabledForKey:NFBNotificationFilterQualityKey];
  if ([self advancedNotificationFilterEnabledForKey:NFBNotificationFilterQualityKey] && [self notificationAuthorFailsQualityFilter:author]) return YES;
  if ([self advancedNotificationFilterEnabledForKey:NFBNotificationFilterYouDoNotFollowKey] && [self notificationAuthorLacksViewerRecord:@"following" author:author]) return YES;
  if ([self advancedNotificationFilterEnabledForKey:NFBNotificationFilterNotFollowingYouKey] && [self notificationAuthorLacksViewerRecord:@"followedBy" author:author]) return YES;
  if ([self advancedNotificationFilterEnabledForKey:NFBNotificationFilterNewAccountsKey] && [self notificationAuthorIsNewAccount:author]) return YES;
  if ([self advancedNotificationFilterEnabledForKey:NFBNotificationFilterDefaultAvatarKey] && [self notificationAuthorUsesDefaultAvatar:author]) return YES;
  return NO;
}

- (BOOL)notificationAuthorFailsQualityFilter:(NSDictionary *)author {
  NSString *did = [author[@"did"] isKindOfClass:NSString.class] ? author[@"did"] : @"";
  NSString *handle = [author[@"handle"] isKindOfClass:NSString.class] ? author[@"handle"] : @"";
  if (did.length == 0 || handle.length == 0) return YES;
  NSDictionary *viewer = [author[@"viewer"] isKindOfClass:NSDictionary.class] ? author[@"viewer"] : @{};
  id blocking = viewer[@"blocking"];
  id blockedBy = viewer[@"blockedBy"];
  if ([blocking isKindOfClass:NSString.class] && [blocking length] > 0) return YES;
  if ([blockedBy isKindOfClass:NSString.class] && [blockedBy length] > 0) return YES;
  if ([blocking respondsToSelector:@selector(boolValue)] && [blocking boolValue]) return YES;
  if ([blockedBy respondsToSelector:@selector(boolValue)] && [blockedBy boolValue]) return YES;
  return [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class];
}

- (BOOL)notificationAuthorLacksViewerRecord:(NSString *)viewerKey author:(NSDictionary *)author {
  NSDictionary *viewer = [author[@"viewer"] isKindOfClass:NSDictionary.class] ? author[@"viewer"] : nil;
  if (viewer.count == 0) return NO;
  NSString *recordURI = [viewer[viewerKey] isKindOfClass:NSString.class] ? viewer[viewerKey] : @"";
  return recordURI.length == 0;
}

- (BOOL)notificationAuthorIsNewAccount:(NSDictionary *)author {
  NSString *createdAt = [author[@"createdAt"] isKindOfClass:NSString.class] ? author[@"createdAt"] : @"";
  NSTimeInterval created = [self notificationTimeIntervalFromISOString:createdAt];
  if (created <= 0.0) return NO;
  NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - created;
  return age >= 0.0 && age < (30.0 * 24.0 * 60.0 * 60.0);
}

- (BOOL)notificationAuthorUsesDefaultAvatar:(NSDictionary *)author {
  return [NFBAtprotoClient avatarURLForProfile:author].length == 0;
}

- (void)addNotificationAuthor:(NSDictionary *)author toUsers:(NSMutableArray *)users {
  if (!users || author.count == 0) return;
  NSString *did = [author[@"did"] isKindOfClass:NSString.class] ? author[@"did"] : @"";
  for (NSDictionary *existing in users) {
    NSString *existingDID = [existing[@"did"] isKindOfClass:NSString.class] ? existing[@"did"] : @"";
    if (did.length > 0 && [existingDID isEqualToString:did]) return;
  }
  [users addObject:author];
}

- (BOOL)notificationItemRoutesToProfile:(NSDictionary *)item {
  NSString *route = [item[@"route"] isKindOfClass:NSString.class] ? item[@"route"] : @"";
  if ([route isEqualToString:@"profile"]) return YES;
  NSString *reason = [item[@"reason"] isKindOfClass:NSString.class] ? item[@"reason"] : @"";
  return [reason isEqualToString:@"follow"] || [reason isEqualToString:@"starterpack-joined"];
}

- (BOOL)notificationGroupRoutesToProfile:(NSDictionary *)group {
  NSString *route = [group[@"route"] isKindOfClass:NSString.class] ? group[@"route"] : @"";
  if ([route isEqualToString:@"profile"]) return YES;
  NSString *reason = [group[@"reason"] isKindOfClass:NSString.class] ? group[@"reason"] : @"";
  return [reason isEqualToString:@"follow"] || [reason isEqualToString:@"starterpack-joined"];
}

- (NSString *)notificationPeopleTitleForGroup:(NSDictionary *)group {
  NSString *reason = [group[@"reason"] isKindOfClass:NSString.class] ? group[@"reason"] : @"";
  if ([reason isEqualToString:@"follow"]) return @"Followed";
  if ([reason isEqualToString:@"starterpack-joined"]) return @"People";
  if ([reason isEqualToString:@"like"]) return @"Liked";
  if ([reason isEqualToString:@"repost"]) return @"Retweeted";
  return @"People";
}

- (NSString *)notificationActivityGroupKeyForItem:(NSDictionary *)item {
  NSString *reason = [item[@"reason"] isKindOfClass:NSString.class] ? item[@"reason"] : @"notification";
  NSString *targetURI = [item[@"targetURI"] isKindOfClass:NSString.class] ? item[@"targetURI"] : @"";
  if (([reason isEqualToString:@"like"] || [reason isEqualToString:@"repost"]) && targetURI.length > 0) {
    return [NSString stringWithFormat:@"%@:%@", reason, targetURI];
  }
  if ([reason isEqualToString:@"follow"] || [reason isEqualToString:@"starterpack-joined"]) {
    NSString *createdAt = [item[@"createdAt"] isKindOfClass:NSString.class] ? item[@"createdAt"] : @"";
    NSTimeInterval time = [self notificationTimeIntervalFromISOString:createdAt];
    NSInteger bucket = time > 0 ? (NSInteger)floor(time / (12.0 * 60.0 * 60.0)) : 0;
    return [NSString stringWithFormat:@"%@:%ld", reason, (long)bucket];
  }
  NSString *uri = [NFBAtprotoClient postURIFromFeedItem:item];
  return [NSString stringWithFormat:@"%@:%@", reason, uri.length > 0 ? uri : [[NSUUID UUID] UUIDString]];
}

- (NSTimeInterval)notificationTimeIntervalFromISOString:(NSString *)dateString {
  if (dateString.length == 0) return 0;
  static NSDateFormatter *millisecondsFormatter = nil;
  static NSDateFormatter *secondsFormatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    millisecondsFormatter = [[NSDateFormatter alloc] init];
    millisecondsFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    millisecondsFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    millisecondsFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

    secondsFormatter = [[NSDateFormatter alloc] init];
    secondsFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    secondsFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    secondsFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
  });
  NSDate *date = [millisecondsFormatter dateFromString:dateString] ?: [secondsFormatter dateFromString:dateString];
  return date ? date.timeIntervalSince1970 : 0;
}

- (BOOL)profileTabUsesAuthorFeed:(NSString *)tabID {
  if ([tabID isEqualToString:@"tweets"]) return YES;
  if ([tabID isEqualToString:@"with_replies"]) return YES;
  if ([tabID isEqualToString:@"media"]) return YES;
  return NO;
}

- (NSString *)profilePinnedPostURI {
  NSDictionary *pinnedPost = [self.profile[@"pinnedPost"] isKindOfClass:NSDictionary.class] ? self.profile[@"pinnedPost"] : nil;
  if (!pinnedPost) {
    NSDictionary *record = [self.profile[@"profileRecord"] isKindOfClass:NSDictionary.class] ? self.profile[@"profileRecord"] : nil;
    pinnedPost = [record[@"pinnedPost"] isKindOfClass:NSDictionary.class] ? record[@"pinnedPost"] : nil;
  }
  NSString *uri = [pinnedPost[@"uri"] isKindOfClass:NSString.class] ? pinnedPost[@"uri"] : @"";
  return uri;
}

- (BOOL)shouldDisplayPinnedPostForProfileTab:(NSString *)tabID replacing:(BOOL)replacing cursor:(NSString *)cursor {
  if (!replacing || cursor.length > 0) return NO;
  return [tabID isEqualToString:@"tweets"];
}

- (NSArray<NSDictionary *> *)profileItems:(NSArray<NSDictionary *> *)items byPrependingPinnedPost:(NSDictionary *)pinnedPost uri:(NSString *)pinnedURI {
  if (pinnedPost.count == 0 || pinnedURI.length == 0) return items ?: @[];
  NSMutableArray<NSDictionary *> *nextItems = [NSMutableArray arrayWithObject:@{@"post": pinnedPost, @"reason": @"pinned"}];
  for (NSDictionary *item in items ?: @[]) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if ([uri isEqualToString:pinnedURI]) continue;
    [nextItems addObject:item];
  }
  return nextItems;
}

- (BOOL)profileTabUsesResourceCells:(NSString *)tabID {
  return [tabID isEqualToString:@"lists"] || [tabID isEqualToString:@"starter-packs"];
}

- (NSString *)authorFeedFilterForProfileTab:(NSString *)tabID {
  if ([tabID isEqualToString:@"with_replies"]) return @"posts_with_replies";
  if ([tabID isEqualToString:@"media"]) return @"posts_with_media";
  return @"posts_no_replies";
}

- (void)updateSearchHeaderVisible:(BOOL)visible {
  if (self.kind != NFBTimelineKindSearch || self.searchResultsMode) return;
  if (!visible) {
    self.tableView.tableHeaderView = nil;
    return;
  }

  CGFloat width = CGRectGetWidth(self.view.bounds);
  if (width <= 0) width = CGRectGetWidth(UIScreen.mainScreen.bounds);
  UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 50.0)];
  header.backgroundColor = NFBColorBackground();

  UILabel *title = [[UILabel alloc] init];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.text = @"What's happening";
  title.textColor = NFBColorText();
  title.font = NFBFont(20.0, NFBFontWeightHeavy);

  UIView *topBorder = [[UIView alloc] init];
  topBorder.translatesAutoresizingMaskIntoConstraints = NO;
  topBorder.backgroundColor = NFBColorBorder();

  UIView *bottomBorder = [[UIView alloc] init];
  bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableSeparatorAppearance(bottomBorder);

  [header addSubview:title];
  [header addSubview:topBorder];
  [header addSubview:bottomBorder];
  [NSLayoutConstraint activateConstraints:@[
    [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
    [title.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    [topBorder.topAnchor constraintEqualToAnchor:header.topAnchor],
    [topBorder.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
    [topBorder.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
    [topBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [bottomBorder.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
    [bottomBorder.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
    [bottomBorder.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
    [bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  self.tableView.tableHeaderView = header;
}

- (void)refreshAccountChrome {
  if (![self ownsCurrentAccount]) return;
  if (!self.avatarButtonImageView) return;
  NFBAtprotoSession *session = [NFBAtprotoSession sharedSession];
  NSString *accountDID = session.did ?: @"";
  NSUInteger generation = ++self.accountChromeGeneration;
  // Use the selected account immediately, including its default avatar when
  // there is no photo. Profile/network refresh must not retain the old account.
  [self loadNavigationAvatarURL:session.currentAccountDictionary[@"avatar"]];
  NSString *actor = session.did ?: session.handle;
  if (actor.length == 0) return;
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] fetchProfileForActor:actor completion:^(NSDictionary *value, NSError *error) {
    if (error || !value) return;
    NSString *avatar = [NFBAtprotoClient avatarURLForProfile:value];
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || ![strongSelf ownsCurrentAccount] || generation != strongSelf.accountChromeGeneration ||
          ![accountDID isEqualToString:[NFBAtprotoSession sharedSession].did ?: @""]) return;
      [strongSelf loadNavigationAvatarURL:avatar];
    });
  }];
}

- (void)loadProfileHeaderForActor:(NSString *)actor {
  [self loadProfileHeaderForActor:actor completion:nil];
}

- (void)loadProfileHeaderForActor:(NSString *)actor completion:(void (^)(BOOL success))completion {
  if (actor.length == 0) return;
  self.loadingProfileActor = actor;
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] fetchProfileForActor:actor completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if ([strongSelf.loadingProfileActor isEqualToString:actor]) strongSelf.loadingProfileActor = nil;
      if (error || !value) {
        if (completion) completion(NO);
        return;
      }
      strongSelf.profile = value;
      strongSelf.loadedProfileActor = actor;
      [strongSelf updateProfileHeader];
      [strongSelf refreshProfileMessageCapabilityIfNeeded];
      [strongSelf refreshProfileKnownFollowersIfNeeded];
      if (completion) completion(YES);
      [strongSelf preloadProfileImagesForProfile:value completion:^(NSDictionary *hydratedProfile) {
        __strong typeof(weakSelf) hydratedSelf = weakSelf;
        if (!hydratedSelf || ![hydratedSelf.loadedProfileActor isEqualToString:actor] || hydratedProfile.count == 0) return;
        NSMutableDictionary *updatedProfile = [hydratedSelf.profile isKindOfClass:NSDictionary.class] ? [hydratedSelf.profile mutableCopy] : [NSMutableDictionary dictionary];
        UIImage *loadedAvatar = [hydratedProfile[@"_nfbLoadedAvatar"] isKindOfClass:UIImage.class] ? hydratedProfile[@"_nfbLoadedAvatar"] : nil;
        UIImage *loadedBanner = [hydratedProfile[@"_nfbLoadedBanner"] isKindOfClass:UIImage.class] ? hydratedProfile[@"_nfbLoadedBanner"] : nil;
        if (loadedAvatar) updatedProfile[@"_nfbLoadedAvatar"] = loadedAvatar;
        if (loadedBanner) updatedProfile[@"_nfbLoadedBanner"] = loadedBanner;
        hydratedSelf.profile = updatedProfile;
        [hydratedSelf updateProfileHeader];
      }];
    });
  }];
}

- (void)preloadProfileImagesForProfile:(NSDictionary *)profile completion:(void (^)(NSDictionary *hydratedProfile))completion {
  NSMutableDictionary *hydrated = [profile mutableCopy];
  dispatch_group_t group = dispatch_group_create();
  NSArray<NSString *> *keys = @[@"avatar", @"banner"];
  for (NSString *key in keys) {
    NSString *urlString = [profile[key] isKindOfClass:NSString.class] ? profile[key] : @"";
    if (urlString.length == 0) continue;
    UIImage *cached = [self.profileImageCache objectForKey:urlString];
    if (cached) {
      hydrated[[@"_nfbLoaded" stringByAppendingString:[key capitalizedString]]] = cached;
      continue;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) continue;
    dispatch_group_enter(group);
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      (void)response;
      if (!error && data.length > 0) {
        UIImage *image = [UIImage imageWithData:data];
        if (image) {
          @synchronized (hydrated) {
            [self.profileImageCache setObject:image forKey:urlString];
            hydrated[[@"_nfbLoaded" stringByAppendingString:[key capitalizedString]]] = image;
          }
        }
      }
      dispatch_group_leave(group);
    }] resume];
  }
  dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    if (completion) completion(hydrated);
  });
}

- (void)updateProfileHeader {
  if (self.kind != NFBTimelineKindProfile || !self.profile) return;
  NSString *displayName = [NFBAtprotoClient displayNameForProfile:self.profile];
  NSString *handleText = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:self.profile]];
  [self updateProfileNavigationTitleViewWithTitle:displayName.length > 0 ? displayName : @"Profile" subtitle:handleText];

  NSArray<NSDictionary *> *tabs = [self profileTabDefinitions];
  if (![self profileTabs:tabs containTabID:self.selectedProfileTabID]) self.selectedProfileTabID = @"tweets";

  CGFloat width = CGRectGetWidth(self.view.bounds);
  if (width <= 0) width = CGRectGetWidth(UIScreen.mainScreen.bounds);
  CGFloat headerHeight = 1.0;
  self.profileHeaderLayoutWidth = width;
  self.profileHeaderLayoutSafeTop = self.view.window.safeAreaInsets.top;
  NFBProfileElements elements = [self profileElements];
  UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, headerHeight)];
  header.backgroundColor = NFBColorBackground();
  header.clipsToBounds = YES;
  self.profileHeaderView = header;

  UIImage *preloadedBanner = [self.profile[@"_nfbLoadedBanner"] isKindOfClass:UIImage.class] ? self.profile[@"_nfbLoadedBanner"] : nil;
  [self updateProfileCoverChromeImage:preloadedBanner ?: NFBDefaultCoverImage()];
  UIView *banner = [[UIView alloc] init];
  banner.translatesAutoresizingMaskIntoConstraints = NO;
  banner.backgroundColor = NFBColorElevatedBackground();
  banner.clipsToBounds = YES;
  self.profileHeaderBannerView = banner;

  UIImageView *bannerImage = [[UIImageView alloc] initWithImage:preloadedBanner ?: NFBDefaultCoverImage()];
  bannerImage.hidden = [self profileStringForKey:@"banner"].length == 0;
  bannerImage.translatesAutoresizingMaskIntoConstraints = NO;
  bannerImage.contentMode = UIViewContentModeScaleAspectFill;
  bannerImage.clipsToBounds = YES;
  self.profileHeaderBannerImageView = bannerImage;
  banner.userInteractionEnabled = YES;
  [banner addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileBannerTapped)]];
  banner.isAccessibilityElement = [self profileStringForKey:@"banner"].length > 0;
  banner.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitImage;
  banner.accessibilityLabel = @"View cover photo";

  UIVisualEffectView *bannerBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:[self profileChromeBlurStyle]]];
  bannerBlur.translatesAutoresizingMaskIntoConstraints = NO;
  bannerBlur.alpha = self.profileNavigationBackgroundAlpha;
  [banner addSubview:bannerImage];
  [banner addSubview:bannerBlur];
  self.profileBannerBlurView = bannerBlur;

  UIImage *preloadedAvatar = [self.profile[@"_nfbLoadedAvatar"] isKindOfClass:UIImage.class] ? self.profile[@"_nfbLoadedAvatar"] : nil;
  UIImageView *avatar = [[UIImageView alloc] initWithImage:preloadedAvatar ?: (NFBDefaultAvatarImage() ?: NFBBrandIconImage())];
  avatar.translatesAutoresizingMaskIntoConstraints = NO;
  avatar.contentMode = UIViewContentModeScaleAspectFill;
  avatar.clipsToBounds = YES;
  avatar.layer.cornerRadius = 48.0;
  avatar.layer.borderWidth = 4.0;
  avatar.layer.borderColor = NFBColorBackground().CGColor;
  self.profileHeaderAvatarImageView = avatar;
  avatar.userInteractionEnabled = YES;
  [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profileAvatarTapped)]];
  avatar.isAccessibilityElement = YES;
  BOOL hasAvatar = [NFBAtprotoClient avatarURLForProfile:self.profile].length > 0;
  avatar.accessibilityTraits = UIAccessibilityTraitImage | (hasAvatar ? UIAccessibilityTraitButton : 0);
  avatar.accessibilityLabel = hasAvatar ? @"View profile photo" : @"Default profile photo";

  UIStackView *actions = [self profileActionsStack];

  UILabel *name = [[UILabel alloc] init];
  name.translatesAutoresizingMaskIntoConstraints = NO;
  name.font = NFBFont(20.0, NFBFontWeightHeavy);
  name.textColor = NFBColorText();
  name.text = displayName;
  name.numberOfLines = 0;
  name.lineBreakMode = NSLineBreakByWordWrapping;
  name.adjustsFontSizeToFitWidth = NO;
  name.minimumScaleFactor = 0.84;
  name.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
  [name setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  [name setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  UIImageView *verifiedBadge = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
  verifiedBadge.translatesAutoresizingMaskIntoConstraints = NO;
  verifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
  verifiedBadge.hidden = ![NFBAtprotoClient isProfileVerified:self.profile];
  [verifiedBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [verifiedBadge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[name, verifiedBadge]];
  nameRow.translatesAutoresizingMaskIntoConstraints = NO;
  nameRow.axis = UILayoutConstraintAxisHorizontal;
  nameRow.alignment = UIStackViewAlignmentCenter;
  nameRow.spacing = 4.0;
  [nameRow setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [nameRow setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

  UILabel *handle = [[UILabel alloc] init];
  handle.translatesAutoresizingMaskIntoConstraints = NO;
  handle.font = NFBFont(15.0, NFBFontWeightRegular);
  handle.textColor = NFBColorSecondaryText();
  NSString *pronouns = [self profileStringForKey:@"pronouns"];
  handle.text = pronouns.length > 0 ? [NSString stringWithFormat:@"%@  %@", handleText, pronouns] : handleText;
  handle.numberOfLines = 1;
  handle.lineBreakMode = NSLineBreakByTruncatingTail;

  UILabel *followsYou = [[UILabel alloc] init];
  followsYou.translatesAutoresizingMaskIntoConstraints = NO;
  followsYou.hidden = !elements.followsYou;
  NFBIPAApplyFollowsYouBadgeAppearance(followsYou);

  UIStackView *handleRow = [[UIStackView alloc] initWithArrangedSubviews:@[handle, followsYou]];
  handleRow.translatesAutoresizingMaskIntoConstraints = NO;
  handleRow.axis = UILayoutConstraintAxisHorizontal;
  handleRow.alignment = UIStackViewAlignmentCenter;
  handleRow.spacing = 6.0;

  UILabel *bio = [[UILabel alloc] init];
  bio.translatesAutoresizingMaskIntoConstraints = NO;
  bio.font = NFBFont(15.0, NFBFontWeightRegular);
  bio.textColor = NFBColorText();
  bio.numberOfLines = 0;
  NSString *bioText = [self.profile[@"description"] isKindOfClass:[NSString class]] ? self.profile[@"description"] : @"";
  bio.attributedText = NFBTweetBodyAttributedString(bioText, bio.font);

  UIStackView *metadata = [self profileMetadataStack];

  UIStackView *counts = [[UIStackView alloc] init];
  counts.translatesAutoresizingMaskIntoConstraints = NO;
  counts.axis = UILayoutConstraintAxisHorizontal;
  counts.alignment = UIStackViewAlignmentCenter;
  counts.spacing = 18.0;
  NSNumber *following = [self.profile[@"followsCount"] isKindOfClass:NSNumber.class] ? self.profile[@"followsCount"] : nil;
  NSNumber *followers = [self.profile[@"followersCount"] isKindOfClass:NSNumber.class] ? self.profile[@"followersCount"] : nil;
  if (elements.counts && following) [counts addArrangedSubview:[self profileCountControlWithCount:following label:@"Following" selector:@selector(profileFollowingCountTapped)]];
  if (elements.counts && followers) [counts addArrangedSubview:[self profileCountControlWithCount:followers label:@"Followers" selector:@selector(profileFollowersCountTapped)]];

  UIView *mutualFollowers = [self profileMutualFollowersView];

  UIScrollView *tabsScroll = [[UIScrollView alloc] init];
  tabsScroll.translatesAutoresizingMaskIntoConstraints = NO;
  tabsScroll.showsHorizontalScrollIndicator = NO;
  tabsScroll.backgroundColor = NFBColorBackground();

  UIStackView *tabsStack = [[UIStackView alloc] init];
  tabsStack.translatesAutoresizingMaskIntoConstraints = NO;
  tabsStack.axis = UILayoutConstraintAxisHorizontal;
  tabsStack.alignment = UIStackViewAlignmentFill;
  tabsStack.distribution = UIStackViewDistributionFill;
  NSMutableArray<UIButton *> *tabButtons = [NSMutableArray array];
  [tabs enumerateObjectsUsingBlock:^(NSDictionary *tab, NSUInteger index, BOOL *stop) {
    (void)stop;
    UIButton *button = [self profileTabButtonWithTitle:tab[@"title"] selected:[tab[@"id"] isEqualToString:self.selectedProfileTabID]];
    button.tag = (NSInteger)index;
    [tabsStack addArrangedSubview:button];
    [tabButtons addObject:button];
    CGFloat tabWidth = [tab[@"width"] respondsToSelector:@selector(doubleValue)] ? [tab[@"width"] doubleValue] : 96.0;
    [button.widthAnchor constraintEqualToConstant:tabWidth].active = YES;
  }];
  self.profileTabButtons = tabButtons;

  UIView *tabsBottomBorder = [[UIView alloc] init];
  tabsBottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
  tabsBottomBorder.backgroundColor = NFBColorBorder();

  [header addSubview:banner];
  [header addSubview:avatar];
  [header addSubview:actions];
  UIStackView *details = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, handleRow]];
  details.translatesAutoresizingMaskIntoConstraints = NO;
  details.axis = UILayoutConstraintAxisVertical;
  details.alignment = UIStackViewAlignmentLeading;
  details.spacing = 12.0;
  [details setCustomSpacing:1.0 afterView:nameRow];
  if (bioText.length > 0) [details addArrangedSubview:bio];
  if (metadata.arrangedSubviews.count > 0) [details addArrangedSubview:metadata];
  if (counts.arrangedSubviews.count > 0) [details addArrangedSubview:counts];
  if (mutualFollowers) [details addArrangedSubview:mutualFollowers];
  [header addSubview:details];
  for (UIView *row in details.arrangedSubviews) {
    [row.widthAnchor constraintLessThanOrEqualToAnchor:details.widthAnchor].active = YES;
  }
  if (bioText.length > 0) [bio.widthAnchor constraintEqualToAnchor:details.widthAnchor].active = YES;
  if (mutualFollowers) [mutualFollowers.widthAnchor constraintEqualToAnchor:details.widthAnchor].active = YES;
  [header addSubview:tabsScroll];
  [tabsScroll addSubview:tabsStack];
  [header addSubview:tabsBottomBorder];

  self.profileHeaderBannerHeightConstraint = [banner.heightAnchor constraintEqualToConstant:[self profileExpandedBannerHeight]];
  [NSLayoutConstraint activateConstraints:@[
    [banner.topAnchor constraintEqualToAnchor:header.topAnchor],
    [banner.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
    [banner.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
    self.profileHeaderBannerHeightConstraint,
    [bannerImage.topAnchor constraintEqualToAnchor:banner.topAnchor],
    [bannerImage.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor],
    [bannerImage.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor],
    [bannerImage.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor],
    [bannerBlur.topAnchor constraintEqualToAnchor:banner.topAnchor],
    [bannerBlur.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor],
    [bannerBlur.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor],
    [bannerBlur.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor],
    [avatar.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
    [avatar.topAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-48.0],
    [avatar.widthAnchor constraintEqualToConstant:96.0],
    [avatar.heightAnchor constraintEqualToConstant:96.0],
    [actions.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    [actions.topAnchor constraintEqualToAnchor:banner.bottomAnchor constant:12.0],
    [verifiedBadge.widthAnchor constraintEqualToConstant:20.0],
    [verifiedBadge.heightAnchor constraintEqualToConstant:20.0],
    [details.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
    [details.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    [details.topAnchor constraintEqualToAnchor:avatar.bottomAnchor constant:9.0],
    [followsYou.heightAnchor constraintGreaterThanOrEqualToConstant:18.0],
    [tabsScroll.topAnchor constraintEqualToAnchor:details.bottomAnchor constant:14.0],
    [tabsScroll.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
    [tabsScroll.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
    [tabsScroll.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
    [tabsScroll.heightAnchor constraintEqualToConstant:53.0],
    [tabsStack.topAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.topAnchor],
    [tabsStack.leadingAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.leadingAnchor],
    [tabsStack.trailingAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.trailingAnchor],
    [tabsStack.bottomAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.bottomAnchor],
    [tabsStack.heightAnchor constraintEqualToAnchor:tabsScroll.frameLayoutGuide.heightAnchor],
    [tabsStack.widthAnchor constraintGreaterThanOrEqualToAnchor:tabsScroll.frameLayoutGuide.widthAnchor],
    [tabsBottomBorder.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
    [tabsBottomBorder.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
    [tabsBottomBorder.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
    [tabsBottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  CGSize fitting = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                         withHorizontalFittingPriority:UILayoutPriorityRequired
                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
  headerHeight = ceil(fitting.height);
  header.frame = CGRectMake(0, 0, width, headerHeight);
  self.profileExpandedHeaderHeight = headerHeight;
  self.profileCurrentHeaderHeight = headerHeight;
  self.tableView.tableHeaderView = header;
  [self updateProfileTabSelection];
  if (!preloadedAvatar) [self loadHeaderAvatar:avatar];
  if (!preloadedBanner && [self profileStringForKey:@"banner"].length > 0) [self loadHeaderBanner:bannerImage];
  [self updateProfileNavigationForScrollOffset];
}

- (NSString *)profileStringForKey:(NSString *)key {
  id value = self.profile[key];
  return [value isKindOfClass:NSString.class] ? value : @"";
}

- (id)profileValueForKey:(NSString *)key {
  return self.profile[key];
}

- (NFBProfileElements)profileElements {
  NSDictionary *viewer = [self.profile[@"viewer"] isKindOfClass:NSDictionary.class] ? self.profile[@"viewer"] : @{};
  NFBProfileState state = {
    .hasProfile = [self profileStringForKey:@"did"].length > 0,
    .signedIn = [[NFBAtprotoSession sharedSession] hasSession],
    .ownProfile = [self isCurrentProfileOwner],
    .blocking = NFBProfileViewerIsBlocking(viewer),
    .blockedBy = NFBProfileViewerIsBlockedBy(viewer),
    .following = NFBProfileRelationshipPresent(viewer[@"following"]),
    .followsViewer = NFBProfileRelationshipPresent(viewer[@"followedBy"]),
    .canMessage = [self profileCanMessage]
  };
  return NFBProfileElementsForState(state);
}

- (BOOL)isCurrentProfileOwner {
  NSString *profileDID = [self.profile[@"did"] isKindOfClass:NSString.class] ? self.profile[@"did"] : @"";
  return profileDID.length > 0 && [[NFBAtprotoSession sharedSession].did isEqualToString:profileDID];
}

- (BOOL)profileCanMessage {
  if (![[NFBAtprotoSession sharedSession] hasSession] || [self isCurrentProfileOwner]) return NO;

  NSDictionary *viewer = [self.profile[@"viewer"] isKindOfClass:NSDictionary.class] ? self.profile[@"viewer"] : @{};
  if (NFBProfileViewerIsBlocking(viewer) || NFBProfileViewerIsBlockedBy(viewer)) return NO;
  id resolved = self.profile[@"_nfbCanMessage"];
  if ([resolved isKindOfClass:NSNumber.class]) return [resolved boolValue];
  return NO; // Match the reference: wait for the relationship/permission result.
}

- (void)refreshProfileMessageCapabilityIfNeeded {
  if (self.kind != NFBTimelineKindProfile || !self.profile || [self isCurrentProfileOwner]) return;
  NSString *profileDID = [self.profile[@"did"] isKindOfClass:NSString.class] ? self.profile[@"did"] : @"";
  if (profileDID.length == 0 || ![self ownsCurrentAccount]) return;
  NSUInteger generation = ++self.profileMessageCapabilityGeneration;
  NSMutableDictionary *pendingProfile = [self.profile mutableCopy];
  [pendingProfile removeObjectForKey:@"_nfbCanMessage"];
  self.profile = pendingProfile;
  [self updateProfileHeader];
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] canMessageProfile:self.profile completion:^(BOOL canMessage) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || ![strongSelf ownsCurrentAccount] || strongSelf.kind != NFBTimelineKindProfile || generation != strongSelf.profileMessageCapabilityGeneration) return;
      NSString *currentDID = [strongSelf.profile[@"did"] isKindOfClass:NSString.class] ? strongSelf.profile[@"did"] : @"";
      if (![currentDID isEqualToString:profileDID]) return;
      BOOL current = [strongSelf profileCanMessage];
      if (current == canMessage && [strongSelf.profile[@"_nfbCanMessage"] respondsToSelector:@selector(boolValue)]) return;
      NSMutableDictionary *updated = [strongSelf.profile mutableCopy];
      updated[@"_nfbCanMessage"] = @(canMessage);
      strongSelf.profile = updated;
      [strongSelf updateProfileHeader];
    });
  }];
}

- (void)refreshProfileKnownFollowersIfNeeded {
  if (self.kind != NFBTimelineKindProfile || !self.profile || [self isCurrentProfileOwner]) return;
  if ([self.profile[@"_nfbKnownFollowersLoaded"] respondsToSelector:@selector(boolValue)] && [self.profile[@"_nfbKnownFollowersLoaded"] boolValue]) return;
  NSString *actor = [self.profile[@"did"] isKindOfClass:NSString.class] ? self.profile[@"did"] : @"";
  if (actor.length == 0) actor = [self.profile[@"handle"] isKindOfClass:NSString.class] ? self.profile[@"handle"] : @"";
  if (actor.length == 0 || [self.loadingKnownFollowersActor isEqualToString:actor]) return;
  self.loadingKnownFollowersActor = actor;
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] fetchProfileActorsForActor:actor kind:@"known" cursor:nil completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if ([strongSelf.loadingKnownFollowersActor isEqualToString:actor]) strongSelf.loadingKnownFollowersActor = nil;
      NSString *currentActor = [strongSelf.profile[@"did"] isKindOfClass:NSString.class] ? strongSelf.profile[@"did"] : @"";
      if (![currentActor isEqualToString:actor]) return;
      NSMutableDictionary *updated = [strongSelf.profile mutableCopy];
      updated[@"_nfbKnownFollowersLoaded"] = @YES;
      if (!error && items.count > 0) {
        updated[@"_nfbKnownFollowers"] = items;
        updated[@"_nfbKnownFollowersCount"] = @(items.count);
      }
      strongSelf.profile = updated;
      [strongSelf updateProfileHeader];
    });
  }];
}

- (NSArray<NSDictionary *> *)profileTabDefinitions {
  NSMutableArray<NSDictionary *> *tabs = [@[
    @{@"id": @"tweets", @"title": @"Tweets", @"width": @96.0},
    @{@"id": @"with_replies", @"title": @"Tweets & replies", @"width": @152.0},
    @{@"id": @"articles", @"title": @"Articles", @"width": @96.0},
    @{@"id": @"media", @"title": @"Media", @"width": @96.0}
  ] mutableCopy];
  if ([self isCurrentProfileOwner]) [tabs addObject:@{@"id": @"likes", @"title": @"Likes", @"width": @96.0}];
  NSDictionary *associated = [self.profile[@"associated"] isKindOfClass:NSDictionary.class] ? self.profile[@"associated"] : @{};
  if ([self isCurrentProfileOwner] || ([associated[@"lists"] isKindOfClass:NSNumber.class] && [associated[@"lists"] integerValue] > 0))
    [tabs addObject:@{@"id": @"lists", @"title": @"Lists", @"width": @96.0}];
  if ([self isCurrentProfileOwner] || ([associated[@"starterPacks"] isKindOfClass:NSNumber.class] && [associated[@"starterPacks"] integerValue] > 0))
    [tabs addObject:@{@"id": @"starter-packs", @"title": @"Starter Packs", @"width": @136.0}];
  return tabs;
}

- (BOOL)profileTabs:(NSArray<NSDictionary *> *)tabs containTabID:(NSString *)tabID {
  for (NSDictionary *tab in tabs) {
    if ([tab[@"id"] isEqualToString:tabID]) return YES;
  }
  return NO;
}

- (UIStackView *)profileActionsStack {
  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisHorizontal;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.spacing = 8.0;
  NFBProfileElements elements = [self profileElements];
  if (elements.edit) {
    UIButton *edit = [self profilePillButtonWithTitle:@"Edit profile" filled:NO];
    [edit addTarget:self action:@selector(editProfileTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:edit];
  }
  if (elements.message) {
    UIButton *message = [self profileIconButtonWithIcon:@"nfb_messages" accessibilityLabel:@"Message"];
    // Reference TFNButton size class 2: 18pt image inside a 34pt circle.
    message.imageEdgeInsets = UIEdgeInsetsMake(8.0, 8.0, 8.0, 8.0);
    [message addTarget:self action:@selector(profileMessageTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:message];
  }
  if (elements.notifications) {
    BOOL enabled = [NFBNotificationCoordinator activityNotificationsEnabledForProfile:self.profile ?: @{}];
    UIButton *notifications = [self profileIconButtonWithIcon:enabled ? @"nfb_notifications_filled" : @"nfb_notifications" accessibilityLabel:@"Notifications"];
    if (enabled) {
      notifications.tintColor = NFBColorAccent();
      notifications.layer.borderColor = NFBColorAccent().CGColor;
    }
    [notifications addTarget:self action:@selector(profileNotificationsTapped:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:notifications];
  }
  if (elements.follow) {
    UIButton *follow = [self profilePillButtonWithTitle:[NFBPostActionCoordinator followTitleForProfile:self.profile] filled:YES];
    [NFBPostActionCoordinator configureFollowButton:follow profile:self.profile overDarkBackground:NO];
    [follow addTarget:self action:@selector(profileFollowTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:follow];
  }
  return stack;
}

- (UIButton *)profilePillButtonWithTitle:(NSString *)title filled:(BOOL)filled {
  UIButton *button = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.layer.cornerRadius = 17.0;
  button.layer.borderWidth = filled ? 0.0 : 1.0;
  button.layer.borderColor = NFBColorSecondaryText().CGColor;
  button.backgroundColor = filled ? NFBColorText() : UIColor.clearColor;
  [button setTitle:title forState:UIControlStateNormal];
  [button setTitleColor:filled ? NFBColorBackground() : NFBColorText() forState:UIControlStateNormal];
  button.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
  [NSLayoutConstraint activateConstraints:@[
    [button.heightAnchor constraintEqualToConstant:34.0],
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:104.0]
  ]];
  return button;
}

- (UIButton *)profileIconButtonWithIcon:(NSString *)iconName accessibilityLabel:(NSString *)accessibilityLabel {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.layer.cornerRadius = 17.0;
  button.layer.borderWidth = 1.0;
  button.layer.borderColor = NFBColorSecondaryText().CGColor;
  button.tintColor = NFBColorText();
  button.accessibilityLabel = accessibilityLabel;
  [button setImage:NFBTemplateIcon(iconName) forState:UIControlStateNormal];
  button.imageEdgeInsets = UIEdgeInsetsMake(6.0, 6.0, 6.0, 6.0);
  [NSLayoutConstraint activateConstraints:@[
    [button.widthAnchor constraintEqualToConstant:34.0],
    [button.heightAnchor constraintEqualToConstant:34.0]
  ]];
  return button;
}

- (UIStackView *)profileMetadataStack {
	  UIStackView *stack = [[UIStackView alloc] init];
	  stack.translatesAutoresizingMaskIntoConstraints = NO;
	  stack.axis = UILayoutConstraintAxisVertical;
	  stack.alignment = UIStackViewAlignmentLeading;
	  stack.spacing = 3.0;

  NSString *website = [self profileStringForKey:@"website"];
  NSString *websiteText = [self displayWebsiteTextForProfileWebsite:website];
	  if (websiteText.length > 0) {
	    UIView *websiteItem = [self profileMetadataItemWithIcon:@"nfb_link" text:websiteText accent:YES];
	    [stack addArrangedSubview:websiteItem];
	    [websiteItem.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor].active = YES;
	  }

  UIStackView *detailRow = [[UIStackView alloc] init];
	  detailRow.translatesAutoresizingMaskIntoConstraints = NO;
	  detailRow.axis = UILayoutConstraintAxisHorizontal;
	  detailRow.alignment = UIStackViewAlignmentCenter;
	  detailRow.distribution = UIStackViewDistributionFill;
	  detailRow.spacing = 7.0;
	  [detailRow setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	  [detailRow setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

  NSString *birthday = [self formattedBirthdayTextFromValue:[self profileValueForKey:@"birthday"]];
  if (birthday.length > 0) [detailRow addArrangedSubview:[self profileMetadataItemWithIcon:@"nfb_birthday" text:birthday accent:NO]];

  NSString *joined = [self joinedTextForProfile];
  if (joined.length > 0) [detailRow addArrangedSubview:[self profileMetadataItemWithIcon:@"nfb_calendar" text:joined accent:NO]];
  if (detailRow.arrangedSubviews.count > 0) [stack addArrangedSubview:detailRow];
  return stack;
}

- (UIView *)profileMetadataItemWithIcon:(NSString *)iconName text:(NSString *)text accent:(BOOL)accent {
  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.tintColor = NFBColorSecondaryText();
  icon.contentMode = UIViewContentModeScaleAspectFit;

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = text;
  label.textColor = accent ? NFBColorAccent() : NFBColorSecondaryText();
  label.font = NFBFont(15.0, NFBFontWeightRegular);
  label.numberOfLines = 1;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *item = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
  item.translatesAutoresizingMaskIntoConstraints = NO;
	  item.axis = UILayoutConstraintAxisHorizontal;
	  item.alignment = UIStackViewAlignmentCenter;
	  item.spacing = 4.0;
	  [item setContentHuggingPriority:accent ? UILayoutPriorityDefaultLow : UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	  [item setContentCompressionResistancePriority:accent ? UILayoutPriorityDefaultLow : UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [NSLayoutConstraint activateConstraints:@[
    [icon.widthAnchor constraintEqualToConstant:18.0],
    [icon.heightAnchor constraintEqualToConstant:18.0]
  ]];
  return item;
}

- (NSAttributedString *)profileCountsTextFollowing:(NSNumber *)following followers:(NSNumber *)followers {
  NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
  NSDictionary *countAttrs = @{NSForegroundColorAttributeName: NFBColorText(), NSFontAttributeName: NFBFont(15.0, NFBFontWeightBold)};
  NSDictionary *labelAttrs = @{NSForegroundColorAttributeName: NFBColorSecondaryText(), NSFontAttributeName: NFBFont(15.0, NFBFontWeightRegular)};
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:NFBShortCountString(following.integerValue) attributes:countAttrs]];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" Following   " attributes:labelAttrs]];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:NFBShortCountString(followers.integerValue) attributes:countAttrs]];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" Followers" attributes:labelAttrs]];
  return text;
}

- (UIControl *)profileCountControlWithCount:(NSNumber *)count label:(NSString *)label selector:(SEL)selector {
  UIControl *control = [[UIControl alloc] init];
  control.translatesAutoresizingMaskIntoConstraints = NO;
  [control addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];

  UILabel *textLabel = [[UILabel alloc] init];
  textLabel.translatesAutoresizingMaskIntoConstraints = NO;
  textLabel.numberOfLines = 1;
  textLabel.attributedText = [self profileCountTextWithCount:count label:label];
  [control addSubview:textLabel];
  [NSLayoutConstraint activateConstraints:@[
    [textLabel.topAnchor constraintEqualToAnchor:control.topAnchor],
    [textLabel.leadingAnchor constraintEqualToAnchor:control.leadingAnchor],
    [textLabel.trailingAnchor constraintEqualToAnchor:control.trailingAnchor],
    [textLabel.bottomAnchor constraintEqualToAnchor:control.bottomAnchor],
    [control.heightAnchor constraintEqualToConstant:24.0]
  ]];
  return control;
}

- (NSAttributedString *)profileCountTextWithCount:(NSNumber *)count label:(NSString *)label {
  NSDictionary *countAttrs = @{NSForegroundColorAttributeName: NFBColorText(), NSFontAttributeName: NFBFont(15.0, NFBFontWeightBold)};
  NSDictionary *labelAttrs = @{NSForegroundColorAttributeName: NFBColorSecondaryText(), NSFontAttributeName: NFBFont(15.0, NFBFontWeightRegular)};
  NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:NFBShortCountString(count.integerValue) attributes:countAttrs];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:(label.length > 0 ? label : @"")] attributes:labelAttrs]];
  return text;
}

- (NSArray<NSDictionary *> *)profileKnownFollowers {
  if (![self profileElements].mutuals) return @[];
  NSArray *known = [self.profile[@"_nfbKnownFollowers"] isKindOfClass:NSArray.class] ? self.profile[@"_nfbKnownFollowers"] : @[];
  NSMutableArray<NSDictionary *> *profiles = [NSMutableArray array];
  for (NSDictionary *profile in known) {
    if ([profile isKindOfClass:NSDictionary.class]) [profiles addObject:profile];
  }
  return profiles;
}

- (NSString *)profileMutualFollowersText {
  NSArray<NSDictionary *> *known = [self profileKnownFollowers];
  if (known.count == 0) return @"";
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  NSUInteger displayCount = MIN(3, known.count);
  for (NSUInteger index = 0; index < displayCount; index++) {
    NSString *name = [NFBAtprotoClient displayNameForProfile:known[index]];
    if (name.length == 0) name = [NFBAtprotoClient handleForProfile:known[index]];
    if (name.length > 0) [names addObject:name];
  }
  NSInteger total = [self.profile[@"_nfbKnownFollowersCount"] respondsToSelector:@selector(integerValue)] ? [self.profile[@"_nfbKnownFollowersCount"] integerValue] : (NSInteger)known.count;
  if (names.count == 0) return @"";
  if (total <= 1 || names.count == 1) return [NSString stringWithFormat:@"Followed by %@", names.firstObject];
  if (total == 2 && names.count >= 2) return [NSString stringWithFormat:@"Followed by %@ and %@", names[0], names[1]];
  if (total == 3 && names.count >= 3) return [NSString stringWithFormat:@"Followed by %@, %@, and %@", names[0], names[1], names[2]];
  NSInteger others = MAX(1, total - 3);
  if (names.count >= 3) return [NSString stringWithFormat:@"Followed by %@, %@, %@, and %@ %@", names[0], names[1], names[2], NFBShortCountString(others), others == 1 ? @"other" : @"others"];
  return [NSString stringWithFormat:@"Followed by %@ and %@ %@", names.firstObject, NFBShortCountString(MAX(1, total - 1)), total - 1 == 1 ? @"other" : @"others"];
}

- (UIView *)profileMutualFollowersView {
  NSArray<NSDictionary *> *known = [self profileKnownFollowers];
  NSString *text = [self profileMutualFollowersText];
  if (known.count == 0 || text.length == 0) return nil;

  UIControl *control = [[UIControl alloc] init];
  control.translatesAutoresizingMaskIntoConstraints = NO;
  [control addTarget:self action:@selector(profileKnownFollowersTapped) forControlEvents:UIControlEventTouchUpInside];

  UIView *facepile = [[UIView alloc] init];
  facepile.translatesAutoresizingMaskIntoConstraints = NO;
  [control addSubview:facepile];

  NSUInteger imageCount = MIN(3, known.count);
  CGFloat avatarSize = 32.0;
  for (NSUInteger index = 0; index < imageCount; index++) {
    UIImageView *avatar = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage() ?: NFBBrandIconImage()];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    avatar.layer.cornerRadius = avatarSize / 2.0;
    avatar.layer.borderWidth = 2.0;
    avatar.layer.borderColor = NFBColorBackground().CGColor;
    [facepile addSubview:avatar];
    [NSLayoutConstraint activateConstraints:@[
      [avatar.leadingAnchor constraintEqualToAnchor:facepile.leadingAnchor constant:(CGFloat)index * 22.0],
      [avatar.centerYAnchor constraintEqualToAnchor:facepile.centerYAnchor],
      [avatar.widthAnchor constraintEqualToConstant:avatarSize],
      [avatar.heightAnchor constraintEqualToConstant:avatarSize]
    ]];
    [self loadProfileMutualAvatarForProfile:known[index] intoImageView:avatar];
  }

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = text;
  label.textColor = NFBColorSecondaryText();
  label.font = NFBFont(14.0, NFBFontWeightRegular);
  label.numberOfLines = 2;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  [control addSubview:label];

  CGFloat facepileWidth = avatarSize + (CGFloat)(MAX(1, imageCount) - 1) * 22.0;
  [NSLayoutConstraint activateConstraints:@[
    [facepile.leadingAnchor constraintEqualToAnchor:control.leadingAnchor],
    [facepile.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
    [facepile.widthAnchor constraintEqualToConstant:facepileWidth],
    [facepile.heightAnchor constraintEqualToConstant:34.0],
    [label.leadingAnchor constraintEqualToAnchor:facepile.trailingAnchor constant:10.0],
    [label.trailingAnchor constraintEqualToAnchor:control.trailingAnchor],
    [label.topAnchor constraintEqualToAnchor:control.topAnchor],
    [label.bottomAnchor constraintEqualToAnchor:control.bottomAnchor],
    [control.heightAnchor constraintGreaterThanOrEqualToConstant:34.0]
  ]];
  return control;
}

- (void)loadProfileMutualAvatarForProfile:(NSDictionary *)profile intoImageView:(UIImageView *)imageView {
  NSString *urlString = [NFBAtprotoClient avatarURLForProfile:profile];
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      imageView.image = image;
    });
  }] resume];
}

- (NSString *)profileActorIdentifier {
  NSString *actor = [self.profile[@"did"] isKindOfClass:NSString.class] ? self.profile[@"did"] : @"";
  if (actor.length == 0) actor = [self.profile[@"handle"] isKindOfClass:NSString.class] ? self.profile[@"handle"] : @"";
  if (actor.length == 0) actor = self.actor ?: @"";
  return actor;
}

- (void)profileFollowingCountTapped {
  NFBActorListViewController *list = [[NFBActorListViewController alloc] initWithProfile:self.profile ?: @{} actor:[self profileActorIdentifier] selectedKind:@"following"];
  [self.navigationController pushViewController:list animated:YES];
}

- (void)profileFollowersCountTapped {
  NFBActorListViewController *list = [[NFBActorListViewController alloc] initWithProfile:self.profile ?: @{} actor:[self profileActorIdentifier] selectedKind:@"followers"];
  [self.navigationController pushViewController:list animated:YES];
}

- (void)profileKnownFollowersTapped {
  NFBActorListViewController *list = [[NFBActorListViewController alloc] initWithProfile:self.profile ?: @{} actor:[self profileActorIdentifier] selectedKind:@"known"];
  [self.navigationController pushViewController:list animated:YES];
}

- (NSString *)displayWebsiteTextForProfileWebsite:(NSString *)website {
  NSString *trimmed = [website stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmed.length == 0) return @"";
  NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
  if (!components.host && ![trimmed containsString:@"://"]) components = [NSURLComponents componentsWithString:[@"https://" stringByAppendingString:trimmed]];
  NSString *host = components.host ?: @"";
  NSString *path = components.path ?: @"";
  if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
  NSString *display = host.length > 0 ? [host stringByAppendingString:(path.length > 0 ? path : @"")] : trimmed;
  while ([display hasSuffix:@"/"]) display = [display substringToIndex:display.length - 1];
  return display.length > 0 ? display : trimmed;
}

- (UIButton *)profileTabButtonWithTitle:(NSString *)title selected:(BOOL)selected {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [button setTitle:title forState:UIControlStateNormal];
  [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
  button.titleLabel.font = NFBFont(15.0, selected ? NFBFontWeightHeavy : NFBFontWeightBold);
  button.titleLabel.numberOfLines = 1;
  button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  button.titleLabel.textAlignment = NSTextAlignmentCenter;
  button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 10.0, 0.0, 10.0);
  [button addTarget:self action:@selector(profileTabTapped:) forControlEvents:UIControlEventTouchUpInside];

  UIView *underline = [[UIView alloc] init];
  underline.translatesAutoresizingMaskIntoConstraints = NO;
  underline.backgroundColor = NFBColorAccent();
  underline.layer.cornerRadius = 2.0;
  underline.hidden = !selected;
  underline.tag = NFBProfileTabUnderlineTag;
  [button addSubview:underline];
  [NSLayoutConstraint activateConstraints:@[
    [button.heightAnchor constraintEqualToConstant:53.0],
    [underline.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
    [underline.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
    [underline.widthAnchor constraintEqualToConstant:56.0],
    [underline.heightAnchor constraintEqualToConstant:4.0]
  ]];
  return button;
}

- (void)updateProfileTabSelection {
  NSArray<NSDictionary *> *tabs = [self profileTabDefinitions];
  [self.profileTabButtons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
    (void)stop;
    NSString *tabID = index < tabs.count ? tabs[index][@"id"] : @"";
    BOOL selected = [tabID isKindOfClass:NSString.class] && [tabID isEqualToString:self.selectedProfileTabID];
    [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
    button.titleLabel.font = NFBFont(15.0, selected ? NFBFontWeightHeavy : NFBFontWeightBold);
    if (selected) {
      for (UIView *parent = button.superview; parent; parent = parent.superview) {
        if (![parent isKindOfClass:UIScrollView.class]) continue;
        [(UIScrollView *)parent scrollRectToVisible:CGRectInset([button convertRect:button.bounds toView:parent], -12.0, 0.0) animated:YES];
        break;
      }
    }
    for (UIView *subview in button.subviews) {
      if (subview.tag == NFBProfileTabUnderlineTag) {
        subview.hidden = !selected;
        subview.backgroundColor = NFBColorAccent();
      }
    }
  }];
}

- (void)profileTabTapped:(UIButton *)sender {
  NSArray<NSDictionary *> *tabs = [self profileTabDefinitions];
  if (sender.tag < 0 || sender.tag >= (NSInteger)tabs.count) return;
  [self selectProfileTabWithID:tabs[(NSUInteger)sender.tag][@"id"]];
}

- (void)selectProfileTabWithID:(NSString *)tabID {
  if (![tabID isKindOfClass:NSString.class] || [tabID isEqualToString:self.selectedProfileTabID]) return;
  self.cursor = nil;
  self.hasLoadedOnce = NO;
  self.selectedProfileTabID = tabID;
  self.timelineLoadGeneration++;
  self.loading = NO;
  self.refreshSuccessSoundPending = NO;
  [self.refreshControl endRefreshing];
  [self updateProfileTabSelection];
  [self.items removeAllObjects];
  [self.tableView reloadData];
  [self refreshTimeline];
}

- (void)editProfileTapped {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit profile" message:@"Profile editing is not wired in this native build yet." preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareProfileTapped {
  NSString *handle = [self.profile[@"handle"] isKindOfClass:NSString.class] ? self.profile[@"handle"] : [NFBAtprotoClient canonicalHandleForProfile:self.profile ?: @{}];
  NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://bsky.app/profile/%@", handle]];
  if (!url) return;
  UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
  [self presentViewController:activity animated:YES completion:nil];
}

- (void)profileSearchTapped {
  NSString *handle = self.profile ? [NFBAtprotoClient canonicalHandleForProfile:self.profile ?: @{}] : @"";
  if ((handle.length == 0 || [handle isEqualToString:@"unknown.bsky.social"]) && [self.actor isKindOfClass:NSString.class]) handle = self.actor;
  handle = [handle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if ([handle hasPrefix:@"@"]) handle = [handle substringFromIndex:1];
  if ([handle hasPrefix:@"did:"]) return;
  if (handle.length == 0) return;
  NSString *query = [NSString stringWithFormat:@"from:%@", handle];
  [NFBSearchTypeaheadViewController addRecentSearchQuery:query];
  NFBTimelineViewController *results = [[NFBTimelineViewController alloc] initWithSearchQuery:query];
  [self.navigationController pushViewController:results animated:YES];
}

- (void)profileMessageTapped {
  if (self.profileMessageOpening || ![self ownsCurrentAccount]) return;
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
    return;
  }
  NSString *did = [self.profile[@"did"] isKindOfClass:NSString.class] ? self.profile[@"did"] : @"";
  if (did.length == 0 || [did isEqualToString:[NFBAtprotoSession sharedSession].did ?: @""]) return;
  self.profileMessageOpening = YES;
  [[NFBAtprotoClient sharedClient] fetchChatConversationForMembers:@[did] completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      self.profileMessageOpening = NO;
      if (![self ownsCurrentAccount] || ![self.profile[@"did"] isEqual:did]) return;
      if (error || !value) {
        if (NFBChatErrorIsPermissionDenied(error)) {
          self.profileMessageCapabilityGeneration++;
          NSMutableDictionary *updated = [self.profile mutableCopy];
          updated[@"_nfbCanMessage"] = @NO;
          self.profile = updated;
          [self updateProfileHeader];
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Messages"
                                                                       message:NFBChatErrorIsPermissionDenied(error) ? @"Sorry! You cannot message this account." : (error.localizedDescription ?: @"Could not open that conversation.")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
      }
      NSMutableDictionary *conversation = [value mutableCopy];
      NSArray *members = [conversation[@"members"] isKindOfClass:NSArray.class] ? conversation[@"members"] : @[];
      if (members.count == 0 && self.profile) conversation[@"members"] = @[self.profile];
      NFBConversationViewController *thread = [[NFBConversationViewController alloc] initWithConversation:conversation];
      [self.navigationController pushViewController:thread animated:YES];
    });
  }];
}

- (void)profileNotificationsTapped:(UIButton *)sender {
  if (![self profileElements].notifications) return;
  __weak typeof(self) weakSelf = self;
  [NFBNotificationCoordinator presentActivityNotificationChecklistForProfile:self.profile ?: @{}
                                                          fromViewController:self
                                                                  sourceView:sender
                                                                  completion:^{
    [weakSelf updateProfileHeader];
  }];
}

- (void)profileMoreTapped {
  NSDictionary *profile = self.profile ?: @{};
  NSString *handle = [NFBAtprotoClient handleForProfile:profile];
  NSString *displayHandle = handle.length > 0 ? [@"@" stringByAppendingString:handle] : @"this account";
  __weak typeof(self) weakSelf = self;
  void (^showUnavailable)(NSString *) = ^(NSString *title) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:@"This option isn’t available yet."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [strongSelf presentViewController:alert animated:YES completion:nil];
  };

  NSMutableArray<NSDictionary<NSString *, id> *> *actions = [NSMutableArray array];
  [actions addObject:@{@"id": @"share", @"title": @"Share profile", @"icon": @"nfb_share", @"handler": [^{ [weakSelf shareProfileTapped]; } copy]}];
  if ([self profileElements].notifications) [actions addObject:@{
    @"id": @"notifications",
    @"title": @"Notifications",
    @"subtitle": @"Choose which updates you get from this account",
    @"icon": @"nfb_notifications",
    @"handler": [^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [NFBNotificationCoordinator presentActivityNotificationChecklistForProfile:profile
                                                          fromViewController:strongSelf
                                                                  sourceView:nil
                                                                  completion:^{
      [strongSelf updateProfileHeader];
    }];
  } copy]
  }];

  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  BOOL blocking = [viewer[@"blocking"] isKindOfClass:NSString.class] && [viewer[@"blocking"] length] > 0;
  BOOL blockingByList = [viewer[@"blockingByList"] isKindOfClass:NSDictionary.class];
  if (![self isCurrentProfileOwner]) {
    [actions addObject:@{
      @"id": @"mute",
      @"title": [NSString stringWithFormat:@"Mute %@", displayHandle],
      @"subtitle": @"Muting accounts is not available yet",
      @"icon": @"nfb_close",
      @"handler": [^{
        showUnavailable(@"Mute account");
      } copy]
    }];
  }
  if (!blockingByList && ![self isCurrentProfileOwner]) {
    [actions addObject:@{
      @"id": @"block",
      @"title": [NSString stringWithFormat:@"%@ %@", blocking ? @"Unblock" : @"Block", displayHandle],
      @"subtitle": blocking ? @"Let this account interact with you again" : @"Stop this account from interacting with you",
      @"icon": @"nfb_close",
      @"destructive": blocking ? @NO : @YES,
      @"handler": [^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      [[strongSelf postActionCoordinator] performBlockForProfile:profile sourceView:nil completion:nil];
    } copy]
    }];
  }
  if (![self isCurrentProfileOwner]) {
    [actions addObject:@{
      @"id": @"report",
      @"title": @"Report account",
      @"subtitle": @"Report flow is not available yet",
      @"icon": @"nfb_info",
      @"destructive": @YES,
      @"handler": [^{
        showUnavailable(@"Report account");
      } copy]
    }];
  }

  NFBPresentNeoFreeBirdMenuSheet(self, @"Profile options", handle.length > 0 ? displayHandle : nil, actions, nil);
}

- (void)profileFollowTapped {
  [[self postActionCoordinator] performFollowForProfile:self.profile ?: @{} sourceView:nil completion:nil];
}

- (NSString *)joinedTextForProfile {
  NSString *dateString = [self profileStringForKey:@"createdAt"];
  NSDate *date = [self profileDateFromString:dateString];
  if (!date) return @"";
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.dateFormat = @"MMMM yyyy";
  return [@"Joined " stringByAppendingString:[formatter stringFromDate:date]];
}

- (NSString *)formattedBirthdayTextFromValue:(id)birthday {
  NSInteger month = 0;
  NSInteger day = 0;
  NSInteger year = 0;
  if ([birthday isKindOfClass:NSDictionary.class]) {
    NSDictionary *dictionary = birthday;
    month = [dictionary[@"month"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"month"] integerValue] : 0;
    day = [dictionary[@"day"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"day"] integerValue] : 0;
    year = [dictionary[@"year"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"year"] integerValue] : 0;
  } else if ([birthday isKindOfClass:NSString.class]) {
    NSString *birthdayString = birthday;
    if (birthdayString.length == 0) return @"";
    NSArray<NSString *> *parts = [birthdayString componentsSeparatedByString:@"-"];
    if (parts.count >= 3) {
      year = parts.firstObject.integerValue;
      month = parts[(NSUInteger)parts.count - 2].integerValue;
      day = parts.lastObject.integerValue;
    } else if (parts.count == 2) {
      month = parts.firstObject.integerValue;
      day = parts.lastObject.integerValue;
    }
  } else {
    return @"";
  }
  if (month < 1 || month > 12 || day < 1 || day > 31) return @"";
  NSDate *now = [NSDate date];
  NSCalendar *calendar = [NSCalendar currentCalendar];
  NSDateComponents *components = [calendar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
  if (components.month == month && components.day == day) return [self isCurrentProfileOwner] ? @"Happy birthday!" : @"Today is their birthday!";
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  NSString *monthName = formatter.monthSymbols[(NSUInteger)month - 1];
  if (year > 0) return [NSString stringWithFormat:@"Born %@ %ld, %ld", monthName, (long)day, (long)year];
  return [NSString stringWithFormat:@"Born %@ %ld", monthName, (long)day];
}

- (NSDate *)profileDateFromString:(NSString *)dateString {
  if (dateString.length == 0) return nil;
  static NSDateFormatter *millisecondsFormatter = nil;
  static NSDateFormatter *secondsFormatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    millisecondsFormatter = [[NSDateFormatter alloc] init];
    millisecondsFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    millisecondsFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    millisecondsFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

    secondsFormatter = [[NSDateFormatter alloc] init];
    secondsFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    secondsFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    secondsFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
  });
  return [millisecondsFormatter dateFromString:dateString] ?: [secondsFormatter dateFromString:dateString];
}

- (void)loadHeaderAvatar:(UIImageView *)avatarView {
  NSString *urlString = [NFBAtprotoClient avatarURLForProfile:self.profile];
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      avatarView.image = image;
    });
  }] resume];
}

- (void)loadHeaderBanner:(UIImageView *)bannerView {
  NSString *urlString = [self.profile[@"banner"] isKindOfClass:[NSString class]] ? self.profile[@"banner"] : @"";
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      bannerView.image = image;
      [self updateProfileCoverChromeImage:image];
    });
  }] resume];
}

- (void)loadNavigationAvatarURL:(NSString *)urlString {
  if (![self ownsCurrentAccount]) return;
  NFBLoadAccountAvatar(self.avatarButtonImageView, urlString);
}

- (BOOL)ownsCurrentAccount {
  return self.owningAccountGeneration == [NFBAtprotoSession sharedSession].accountGeneration;
}

- (void)updateEmptyState:(NSString *)message {
  BOOL loading = [message isEqualToString:@"Loading..."];
  BOOL searchEmpty = self.searchResultsMode && !loading && self.items.count == 0 && [message isEqualToString:[self emptyMessageForCurrentView]];
  self.searchEmptyView.hidden = !searchEmpty;
  if (searchEmpty) {
    self.searchEmptyTitle.text = self.cursor.length ? @"Keep searching" : [NSString stringWithFormat:@"No results for “%@”", self.searchQuery];
    self.searchEmptySubtitle.text = self.cursor.length ? @"No matches in these results. Tap Show more results to keep searching." : @"Try searching for something else, or check your search settings to see if they’re protecting you from potentially sensitive content.";
    self.searchEmptyTitle.textColor = NFBColorText(); self.searchEmptySubtitle.textColor = NFBColorSecondaryText();
  }
  self.emptyLoadingView.hidden = !loading;
  self.emptyLabel.attributedText = nil;
  if (!loading && [self isNotificationEmptyStateMessage:message]) {
    self.emptyLabel.attributedText = [self notificationEmptyStateAttributedString];
  } else {
    self.emptyLabel.text = loading ? @"" : message;
  }
  self.emptyLabel.hidden = loading || searchEmpty || message.length == 0;
  if (loading) NFBStartLoadingAnimation(self.emptyLoadingView);
  else NFBStopLoadingAnimation(self.emptyLoadingView);
}


- (void)feedListCacheInvalidated:(NSNotification *)notification {
  if (![self ownsCurrentAccount]) return;
  (void)notification;
  if (self.kind != NFBTimelineKindHome) return;
  if (!NSThread.isMainThread) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self feedListCacheInvalidated:notification];
    });
    return;
  }
  [self.homeFeedItemsCache removeAllObjects];
  [self.homeFeedCursorCache removeAllObjects];
  [self.homeFeedPrefetchingIndexes removeAllObjects];
  [self loadHomeFeedTabs];
}

- (void)advancedNotificationFiltersChanged:(NSNotification *)notification {
  (void)notification;
  if (self.kind != NFBTimelineKindNotifications) return;
  if (!NSThread.isMainThread) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self advancedNotificationFiltersChanged:notification];
    });
    return;
  }
  if (self.loading) {
    self.loading = NO;
    self.timelineLoadGeneration++;
    self.refreshSuccessSoundPending = NO;
    [self.refreshControl endRefreshing];
  }
  [self refreshTimeline];
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  self.view.backgroundColor = NFBColorBackground();
  NFBIPAApplyTableViewAppearance(self.tableView);
  NFBIPAApplyTableViewAppearance(self.homeFeedPreviewTableView);
  self.homeFeedPreviewLoadingView.backgroundColor = NFBColorBackground();
  self.homeFeedPreviewLoadingImageView.tintColor = NFBColorAccent();
  self.emptyLabel.textColor = NFBColorSecondaryText();
  self.emptyLoadingView.tintColor = NFBColorAccent();
  NFBUpdateRefreshControlAppearance(self.refreshControl);
  self.homeTabsView.backgroundColor = NFBColorBackground();
  self.homeTabsScrollView.backgroundColor = NFBColorBackground();
  self.homeTabsBorder.backgroundColor = NFBColorBorder();
  self.homeTabUnderline.backgroundColor = NFBColorAccent();
  self.notificationsTabsView.backgroundColor = NFBColorBackground();
  self.notificationsTabsBorder.backgroundColor = NFBColorBorder();
  [self updateHomeTabsSelection];
  [self updateNotificationsTabSelection];
  [self updateSearchTabs];
  self.composeButton.backgroundColor = NFBColorAccent();
  if ([self.navigationController isKindOfClass:UINavigationController.class]) {
    NFBApplyNavigationAppearance(self.navigationController);
  }
  [self configureNavigation];
  [self configureHomeNavigationAppearance];
  [self updateProfileCoverChromeTheme];
  self.profileNavigationAppearanceConfigured = NO;
  [self configureProfileNavigationAppearanceIfNeeded];
  if (self.feedMetadata) [self updateFeedHeader];
  if (self.kind == NFBTimelineKindProfile && self.profile) [self updateProfileHeader];
  if (self.kind == NFBTimelineKindSearch) [self updateSearchHeaderVisible:!self.searchResultsMode && self.searchQuery.length == 0];
  [self.tableView reloadData];
}

- (void)composeTapped {
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
    return;
  }
  NFBComposeViewController *compose = [[NFBComposeViewController alloc] init];
  compose.completionHandler = ^(BOOL posted) {
    if (posted) [self refreshTimeline];
  };
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:compose];
  NFBApplyNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)accountMenuTapped {
  NFBSideMenuViewController *menu = [[NFBSideMenuViewController alloc] init];
  menu.modalPresentationStyle = UIModalPresentationOverFullScreen;
  menu.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  [self presentViewController:menu animated:NO completion:nil];
}

- (void)manageFeedsTapped {
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
    return;
  }
  NFBTimelineViewController *feeds = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindFeeds actor:nil];
  [self.navigationController pushViewController:feeds animated:YES];
}

- (void)topicsTapped {
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    NFBPresentBlueskyLoginIfNeeded();
    return;
  }
  Class topicsClass = NSClassFromString(@"NFBTopicsSettingsViewController");
  UIViewController *topics = topicsClass ? [[topicsClass alloc] init] : nil;
  if (!topics) return;
  [self.navigationController pushViewController:topics animated:YES];
}

- (void)notificationSettingsTapped {
  UIViewController *settings = [NFBSettingsViewController notificationSettingsViewController];
  if (!settings) return;
  [self.navigationController pushViewController:settings animated:YES];
}

- (void)signOutTapped {
  [[NFBNotificationCoordinator sharedCoordinator] unregisterRemoteNotificationsForCurrentAccountWithCompletion:^{
    [[NFBAtprotoSession sharedSession] signOut];
    [self refreshTimeline];
    NFBPresentBlueskyLoginIfNeeded();
  }];
}

- (void)filterBookmarkItems {
  NSDictionary *query = NFBParseBookmarkSearch(self.searchQuery);
  [self.items removeAllObjects];
  for (NSDictionary *item in self.bookmarkItems) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    if (NFBBookmarkPostMatchesSearch(post, query)) {
      [self.items addObject:item];
    }
  }
}

- (void)loadRemainingBookmarksForSearch {
  if (self.kind != NFBTimelineKindBookmarks || self.searchQuery.length == 0 || self.loading || self.cursor.length == 0) return;
  [self loadNextPageReplacing:NO];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
  self.searchQuery = searchController.searchBar.text ?: @"";
  if (self.kind == NFBTimelineKindBookmarks) {
    self.searchQuery = [self.searchQuery stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self filterBookmarkItems];
    [self.tableView reloadData];
    [self updateEmptyState:self.items.count > 0 ? @"" : (self.loading ? @"Loading..." : [self emptyMessageForCurrentView])];
    [self loadRemainingBookmarksForSearch];
    return;
  }
  if (self.kind == NFBTimelineKindFeeds && self.selectedHomeFeedIndex != 1) return;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshTimeline) object:nil];
  [self performSelector:@selector(refreshTimeline) withObject:nil afterDelay:0.35];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
  if (self.kind == NFBTimelineKindBookmarks) [searchBar resignFirstResponder];
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
  if (self.kind == NFBTimelineKindBookmarks) return YES;
  if (self.kind == NFBTimelineKindFeeds) {
    if (self.selectedHomeFeedIndex != 1) [self switchToHomeFeedIndex:1 direction:0 animated:NO];
    return YES;
  }
  (void)searchBar;
  [self presentSearchTypeahead];
  return NO;
}

- (void)presentSearchTypeahead {
  NSString *initialQuery = self.searchResultsMode ? self.searchQuery : (self.navigationItem.searchController.searchBar.text ?: self.searchQuery ?: @"");
  NFBSearchTypeaheadViewController *search = [[NFBSearchTypeaheadViewController alloc] initWithInitialQuery:initialQuery];
  search.delegate = self;
  search.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:search animated:YES completion:nil];
}

- (void)performSearchQuery:(NSString *)query {
  NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmed.length == 0) return;
  if (self.kind == NFBTimelineKindSearch && !self.searchResultsMode) {
    NFBTimelineViewController *results = [[NFBTimelineViewController alloc] initWithSearchQuery:trimmed];
    [self.navigationController pushViewController:results animated:YES];
    return;
  }
  self.searchQuery = trimmed;
  if (self.searchResultsMode) { self.searchResultsBar.text = trimmed; [self restartSearch]; return; }
  UISearchController *searchController = self.navigationItem.searchController;
  searchController.searchBar.text = trimmed;
  [searchController.searchBar resignFirstResponder];
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshTimeline) object:nil];
  [self refreshTimeline];
}

- (void)searchTypeaheadViewController:(NFBSearchTypeaheadViewController *)viewController didSelectSearchQuery:(NSString *)query {
  [viewController dismissViewControllerAnimated:YES completion:^{
    [self performSearchQuery:query];
  }];
}

- (void)searchTypeaheadViewController:(NFBSearchTypeaheadViewController *)viewController didSelectActor:(NSString *)actor {
  [viewController dismissViewControllerAnimated:YES completion:^{
    NFBTimelineViewController *profile = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
    [self.navigationController pushViewController:profile animated:YES];
  }];
}

- (void)searchForTrend:(NSDictionary *)trend {
  NSString *link = [trend[@"url"] isKindOfClass:NSString.class] ? trend[@"url"] : @"";
  NSDictionary *route = NFBFeedRouteFromString(link);
  if (route) {
    NFBTimelineViewController *feed = [[NFBTimelineViewController alloc] initWithFeedActor:route[@"actor"] recordKey:route[@"rkey"] title:trend[@"displayName"]];
    [self.navigationController pushViewController:feed animated:YES];
    return;
  }
  if (link.length > 0) {
    NFBOpenTweetTextURL([NSURL URLWithString:link], self);
    return;
  }
  NSString *query = [trend[@"query"] isKindOfClass:NSString.class] ? trend[@"query"] : @"";
  if (query.length == 0) query = [trend[@"displayName"] isKindOfClass:NSString.class] ? trend[@"displayName"] : @"";
  if (query.length == 0) return;
  [NFBSearchTypeaheadViewController addRecentSearchQuery:query];
  [self performSearchQuery:query];
}

- (NSString *)titleForResourceItem:(NSDictionary *)item fallback:(NSString *)fallback {
  NSDictionary *resource = [item[@"resource"] isKindOfClass:NSDictionary.class] ? item[@"resource"] : @{};
  NSDictionary *record = [resource[@"record"] isKindOfClass:NSDictionary.class] ? resource[@"record"] : @{};
  NSString *title = [resource[@"name"] isKindOfClass:NSString.class] ? resource[@"name"] : @"";
  if (title.length == 0) title = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : @"";
  if (title.length == 0) title = [resource[@"displayName"] isKindOfClass:NSString.class] ? resource[@"displayName"] : @"";
  return title.length > 0 ? title : fallback;
}

- (NSDictionary *)resourceForItem:(NSDictionary *)item {
  return [item[@"resource"] isKindOfClass:NSDictionary.class] ? item[@"resource"] : @{};
}

- (NSString *)resourceURIForItem:(NSDictionary *)item {
  NSDictionary *resource = [self resourceForItem:item];
  return [resource[@"uri"] isKindOfClass:NSString.class] ? resource[@"uri"] : @"";
}

- (BOOL)isSavedFeedsResourceListActive {
  if (self.kind != NFBTimelineKindFeeds || self.selectedHomeFeedIndex < 0 || self.selectedHomeFeedIndex >= (NSInteger)self.homeFeedTabs.count) return NO;
  NSDictionary *tab = self.homeFeedTabs[(NSUInteger)self.selectedHomeFeedIndex];
  NSString *type = [tab[@"type"] isKindOfClass:NSString.class] ? tab[@"type"] : @"";
  return [type isEqualToString:@"saved-feeds"];
}

- (NSDictionary *)feedResourceItemAtIndexPath:(NSIndexPath *)indexPath {
  if (self.kind != NFBTimelineKindFeeds || indexPath.row < 0 || indexPath.row >= (NSInteger)self.items.count) return nil;
  NSDictionary *item = self.items[(NSUInteger)indexPath.row];
  if (![item[@"type"] isEqualToString:@"feed"]) return nil;
  if ([self resourceURIForItem:item].length == 0) return nil;
  return item;
}

- (BOOL)canReorderFeedResourceAtIndexPath:(NSIndexPath *)indexPath {
  NSDictionary *item = [self feedResourceItemAtIndexPath:indexPath];
  if (item.count == 0 || ![self isSavedFeedsResourceListActive]) return NO;
  return [[[self resourceForItem:item] objectForKey:@"_nfbSavedFeedSaved"] boolValue];
}

- (void)openFeedResourceItem:(NSDictionary *)item {
  NSString *uri = [self resourceURIForItem:item];
  if (uri.length == 0) return;
  NFBTimelineViewController *feed = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindFeedTimeline actor:uri];
  feed.timelineTitleOverride = [self titleForResourceItem:item fallback:@"Feed"];
  [self.navigationController pushViewController:feed animated:YES];
}

- (void)handleResourceItemSelection:(NSDictionary *)item sourceView:(UIView *)sourceView {
  NSDictionary *resource = [item[@"resource"] isKindOfClass:NSDictionary.class] ? item[@"resource"] : @{};
  NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"";
  NSString *uri = [resource[@"uri"] isKindOfClass:NSString.class] ? resource[@"uri"] : @"";
  if (uri.length == 0) return;

  if ([type isEqualToString:@"list"]) {
    NFBTimelineViewController *list = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindListTimeline actor:uri];
    list.timelineTitleOverride = [self titleForResourceItem:item fallback:@"List"];
    [self.navigationController pushViewController:list animated:YES];
    return;
  }

  if (![type isEqualToString:@"feed"]) return;
  (void)sourceView;
  [self openFeedResourceItem:item];
}

- (UIButton *)feedResourceMenuButtonWithTitle:(NSString *)title imageName:(NSString *)imageName destructive:(BOOL)destructive enabled:(BOOL)enabled action:(SEL)action {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.frame = CGRectMake(0.0, 0.0, 256.0, 46.0);
  button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 18.0, 0.0, 16.0);
  [button setTitle:title forState:UIControlStateNormal];
  UIColor *textColor = destructive ? [UIColor colorWithRed:0.956 green:0.196 blue:0.318 alpha:1.0] : NFBColorText();
  [button setTitleColor:[textColor colorWithAlphaComponent:enabled ? 1.0 : 0.42] forState:UIControlStateNormal];
  button.titleLabel.font = NFBFont(16.0, NFBFontWeightRegular);
  button.enabled = enabled;
  if (imageName.length > 0) {
    NSDictionary<NSString *, NSString *> *iconMap = @{
      @"trash": @"nfb_trash",
      @"bookmark": @"nfb_bookmark",
      @"plus": @"nfb_plus",
      @"xmark": @"nfb_close",
      @"checkmark": @"nfb_check"
    };
    UIImage *image = NFBTemplateIcon(iconMap[imageName] ?: imageName);
    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = [textColor colorWithAlphaComponent:enabled ? 1.0 : 0.42];
    button.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    button.imageEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, -182.0);
    button.titleEdgeInsets = UIEdgeInsetsMake(0.0, -20.0, 0.0, 20.0);
  }
  [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (void)dismissFeedResourceMenuAnimated:(BOOL)animated {
  UIView *overlay = self.feedResourceMenuOverlay;
  if (!overlay) return;
  UIView *snapshot = self.feedResourceDragSnapshotView;
  NSIndexPath *snapshotIndexPath = self.feedResourceDragIndexPath;
  BOOL shouldClearSnapshot = snapshot && !self.feedResourceDidDrag;
  self.feedResourceMenuOverlay = nil;
  self.feedResourceMenuBlurView = nil;
  self.feedResourceMenuView = nil;
  self.feedResourceMenuItem = nil;
  self.feedResourceMenuIndexPath = nil;
  void (^cleanup)(void) = ^{
    if (shouldClearSnapshot) {
      UITableViewCell *cell = snapshotIndexPath ? [self.tableView cellForRowAtIndexPath:snapshotIndexPath] : nil;
      cell.hidden = NO;
      [snapshot removeFromSuperview];
      self.feedResourceDragSnapshotView = nil;
      self.feedResourceDragIndexPath = nil;
      self.feedResourceDragCanReorder = NO;
      self.feedResourceOrderDirty = NO;
    }
    [overlay removeFromSuperview];
  };
  if (!animated) {
    cleanup();
    return;
  }
  [UIView animateWithDuration:0.16 animations:^{
    overlay.alpha = 0.0;
  } completion:^(__unused BOOL finished) {
    cleanup();
  }];
}

- (void)feedResourceMenuOpenTapped {
  NSDictionary *item = self.feedResourceMenuItem ?: @{};
  [self dismissFeedResourceMenuAnimated:YES];
  [self openFeedResourceItem:item];
}

- (void)feedResourceMenuToggleSavedTapped {
  NSDictionary *item = self.feedResourceMenuItem ?: @{};
  NSDictionary *resource = [self resourceForItem:item];
  NSString *uri = [self resourceURIForItem:item];
  if (uri.length == 0) return;
  BOOL saved = [resource[@"_nfbSavedFeedSaved"] boolValue];
  [self dismissFeedResourceMenuAnimated:YES];
  UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
  [feedback impactOccurred];
  [[NFBAtprotoClient sharedClient] setSavedFeedWithURI:uri saved:!saved completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Feeds" message:error.localizedDescription ?: @"Could not update that Feed." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
      }
      [self refreshTimeline];
      if (self.kind == NFBTimelineKindHome) [self loadHomeFeedTabs];
    });
  }];
}

- (void)presentFeedResourceMenuForItem:(NSDictionary *)item indexPath:(NSIndexPath *)indexPath sourceRect:(CGRect)sourceRect {
  [self dismissFeedResourceMenuAnimated:NO];
  self.feedResourceMenuItem = item ?: @{};
  self.feedResourceMenuIndexPath = indexPath;

  UIControl *overlay = [[UIControl alloc] initWithFrame:self.view.bounds];
  overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  overlay.backgroundColor = UIColor.clearColor;
  overlay.alpha = 0.0;
  [overlay addTarget:self action:@selector(feedResourceMenuOverlayTapped:) forControlEvents:UIControlEventTouchUpInside];

  UIBlurEffectStyle blurStyle = [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? UIBlurEffectStyleSystemThinMaterialLight : UIBlurEffectStyleSystemThinMaterialDark;
  UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:blurStyle]];
  blur.frame = overlay.bounds;
  blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  blur.userInteractionEnabled = NO;
  blur.alpha = 0.72;
  [overlay addSubview:blur];

  UIView *scrim = [[UIView alloc] initWithFrame:overlay.bounds];
  scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  scrim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:([NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? 0.08 : 0.22)];
  scrim.userInteractionEnabled = NO;
  [overlay addSubview:scrim];

  BOOL saved = [[[self resourceForItem:item] objectForKey:@"_nfbSavedFeedSaved"] boolValue];
  NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
  [buttons addObject:[self feedResourceMenuButtonWithTitle:@"Open Feed" imageName:@"arrow.up.forward.app" destructive:NO enabled:YES action:@selector(feedResourceMenuOpenTapped)]];
  [buttons addObject:[self feedResourceMenuButtonWithTitle:saved ? @"Remove from Feeds" : @"Add to Feeds"
                                                 imageName:saved ? @"minus.circle" : @"plus.circle"
                                               destructive:saved
                                                   enabled:YES
                                                   action:@selector(feedResourceMenuToggleSavedTapped)]];

  CGFloat menuWidth = MIN(272.0, CGRectGetWidth(self.view.bounds) - 32.0);
  CGFloat menuHeight = 12.0 + (46.0 * buttons.count);
  CGFloat menuX = MIN(MAX(16.0, CGRectGetMinX(sourceRect) + 12.0), CGRectGetWidth(self.view.bounds) - menuWidth - 16.0);
  CGFloat menuY = CGRectGetMaxY(sourceRect) + 8.0;
  if (menuY + menuHeight > CGRectGetHeight(self.view.bounds) - 16.0) {
    menuY = MAX(16.0, CGRectGetMinY(sourceRect) - menuHeight - 8.0);
  }

  UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
  menu.backgroundColor = [NFBColorElevatedBackground() colorWithAlphaComponent:0.96];
  menu.layer.cornerRadius = 14.0;
  menu.layer.masksToBounds = NO;
  menu.layer.borderColor = [NFBColorBorder() colorWithAlphaComponent:0.72].CGColor;
  menu.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  menu.layer.shadowColor = UIColor.blackColor.CGColor;
  menu.layer.shadowOpacity = [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? 0.16 : 0.34;
  menu.layer.shadowRadius = 24.0;
  menu.layer.shadowOffset = CGSizeMake(0.0, 12.0);

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
  stack.frame = CGRectInset(menu.bounds, 0.0, 6.0);
  stack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.distribution = UIStackViewDistributionFillEqually;
  [menu addSubview:stack];

  [overlay addSubview:menu];
  [self.view addSubview:overlay];
  self.feedResourceMenuOverlay = overlay;
  self.feedResourceMenuBlurView = blur;
  self.feedResourceMenuView = menu;

  menu.transform = CGAffineTransformMakeScale(0.97, 0.97);
  [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    overlay.alpha = 1.0;
    menu.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (void)feedResourceMenuOverlayTapped:(UIControl *)sender {
  (void)sender;
  [self dismissFeedResourceMenuAnimated:YES];
}

- (UIView *)snapshotForFeedResourceCell:(UITableViewCell *)cell {
  UIView *snapshot = [cell snapshotViewAfterScreenUpdates:NO];
  snapshot.frame = [self.tableView convertRect:cell.frame toView:self.view];
  snapshot.layer.cornerRadius = 16.0;
  snapshot.layer.masksToBounds = NO;
  snapshot.layer.shadowColor = UIColor.blackColor.CGColor;
  snapshot.layer.shadowOpacity = 0.0;
  snapshot.layer.shadowRadius = 18.0;
  snapshot.layer.shadowOffset = CGSizeMake(0.0, 10.0);
  snapshot.alpha = 0.0;
  snapshot.transform = CGAffineTransformMakeScale(0.985, 0.985);
  return snapshot;
}

- (NSArray<NSString *> *)savedFeedURIsFromCurrentItems {
  NSMutableArray<NSString *> *uris = [NSMutableArray array];
  for (NSDictionary *item in self.items ?: @[]) {
    if (![item[@"type"] isEqualToString:@"feed"]) continue;
    NSString *uri = [self resourceURIForItem:item];
    if (uri.length > 0) [uris addObject:uri];
  }
  return uris;
}

- (void)moveSavedFeedResourceFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex animated:(BOOL)animated {
  if (fromIndex < 0 || toIndex < 0 || fromIndex >= (NSInteger)self.items.count || toIndex >= (NSInteger)self.items.count || fromIndex == toIndex) return;
  NSMutableArray *next = [self.items mutableCopy];
  NSDictionary *item = next[(NSUInteger)fromIndex];
  [next removeObjectAtIndex:(NSUInteger)fromIndex];
  [next insertObject:item atIndex:(NSUInteger)toIndex];
  self.items = next;
  NSIndexPath *from = [NSIndexPath indexPathForRow:fromIndex inSection:0];
  NSIndexPath *to = [NSIndexPath indexPathForRow:toIndex inSection:0];
  if (animated) {
    [self.tableView beginUpdates];
    [self.tableView moveRowAtIndexPath:from toIndexPath:to];
    [self.tableView endUpdates];
  } else {
    [self.tableView moveRowAtIndexPath:from toIndexPath:to];
  }
}

- (void)persistSavedFeedResourceOrder {
  NSArray<NSString *> *uris = [self savedFeedURIsFromCurrentItems];
  if (uris.count == 0) return;
  [[NFBAtprotoClient sharedClient] reorderSavedFeedURIs:uris completion:^(NSDictionary *value, NSError *error) {
    (void)value;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) {
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Feeds" message:error.localizedDescription ?: @"Could not reorder your Feeds." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self refreshTimeline];
        return;
      }
      UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
      [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
      if (self.kind == NFBTimelineKindHome) [self loadHomeFeedTabs];
    });
  }];
}

- (void)finishFeedResourceDragPersisting:(BOOL)persist {
  UIView *snapshot = self.feedResourceDragSnapshotView;
  NSIndexPath *indexPath = self.feedResourceDragIndexPath;
  BOOL orderDirty = self.feedResourceOrderDirty;
  self.feedResourceDragSnapshotView = nil;
  self.feedResourceDragIndexPath = nil;
  self.feedResourceDragCanReorder = NO;
  self.feedResourceDidDrag = NO;
  self.feedResourceOrderDirty = NO;
  if (!snapshot) {
    if (persist && orderDirty) [self persistSavedFeedResourceOrder];
    return;
  }

  UITableViewCell *cell = indexPath ? [self.tableView cellForRowAtIndexPath:indexPath] : nil;
  CGRect targetFrame = cell ? [self.tableView convertRect:cell.frame toView:self.view] : snapshot.frame;
  [UIView animateWithDuration:0.16 animations:^{
    snapshot.frame = targetFrame;
    snapshot.transform = CGAffineTransformIdentity;
  } completion:^(__unused BOOL finished) {
    cell.hidden = NO;
    [snapshot removeFromSuperview];
    if (persist && orderDirty) [self persistSavedFeedResourceOrder];
  }];
}

- (void)feedResourceLongPressed:(UILongPressGestureRecognizer *)gesture {
  CGPoint tablePoint = [gesture locationInView:self.tableView];
  NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:tablePoint];

  if (gesture.state == UIGestureRecognizerStateBegan) {
    NSDictionary *item = [self feedResourceItemAtIndexPath:indexPath];
    if (item.count == 0) return;
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];

    CGRect cellRect = [self.tableView convertRect:cell.frame toView:self.view];
    [self presentFeedResourceMenuForItem:item indexPath:indexPath sourceRect:cellRect];

    UIView *snapshot = [self snapshotForFeedResourceCell:cell];
    [self.view addSubview:snapshot];
    cell.hidden = YES;
    CGPoint viewPoint = [gesture locationInView:self.view];
    self.feedResourceDragIndexPath = indexPath;
    self.feedResourceDragSnapshotView = snapshot;
    self.feedResourceDragCanReorder = [self canReorderFeedResourceAtIndexPath:indexPath];
    self.feedResourceDragStartCenter = snapshot.center;
    self.feedResourceDragTouchOffset = CGPointMake(viewPoint.x - snapshot.center.x, viewPoint.y - snapshot.center.y);
    self.feedResourceDidDrag = NO;
    self.feedResourceOrderDirty = NO;
    [UIView animateWithDuration:0.2 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
      snapshot.alpha = 1.0;
      snapshot.transform = CGAffineTransformMakeScale(1.025, 1.025);
      snapshot.layer.shadowOpacity = 0.28;
    } completion:nil];
    return;
  }

  if (gesture.state == UIGestureRecognizerStateChanged) {
    UIView *snapshot = self.feedResourceDragSnapshotView;
    NSIndexPath *currentIndexPath = self.feedResourceDragIndexPath;
    if (!snapshot || !currentIndexPath) return;

    CGPoint viewPoint = [gesture locationInView:self.view];
    CGPoint nextCenter = CGPointMake(self.feedResourceDragStartCenter.x, viewPoint.y - self.feedResourceDragTouchOffset.y);
    CGFloat dragDistance = fabs(nextCenter.y - self.feedResourceDragStartCenter.y);
    if (!self.feedResourceDragCanReorder) return;
    if (!self.feedResourceDidDrag && dragDistance > 9.0) {
      self.feedResourceDidDrag = YES;
      [self dismissFeedResourceMenuAnimated:YES];
    }
    if (!self.feedResourceDidDrag) return;

    snapshot.center = nextCenter;
    NSIndexPath *targetIndexPath = [self.tableView indexPathForRowAtPoint:tablePoint];
    if (!targetIndexPath || targetIndexPath.row == currentIndexPath.row || ![self canReorderFeedResourceAtIndexPath:targetIndexPath]) return;

    [self moveSavedFeedResourceFromIndex:currentIndexPath.row toIndex:targetIndexPath.row animated:YES];
    self.feedResourceDragIndexPath = targetIndexPath;
    self.feedResourceOrderDirty = YES;
    return;
  }

  if (gesture.state == UIGestureRecognizerStateEnded ||
      gesture.state == UIGestureRecognizerStateCancelled ||
      gesture.state == UIGestureRecognizerStateFailed) {
    BOOL shouldPersist = self.feedResourceDidDrag;
    if (shouldPersist || !self.feedResourceMenuOverlay) {
      [self finishFeedResourceDragPersisting:shouldPersist];
    }
  }
}

- (NSString *)normalizedProfileIdentifier:(NSString *)identifier {
  if (![identifier isKindOfClass:NSString.class]) return @"";
  NSString *normalized = [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if ([normalized hasPrefix:@"@"]) normalized = [normalized substringFromIndex:1];
  return normalized.lowercaseString;
}

- (void)addProfileIdentifiersFromProfile:(NSDictionary *)profile toSet:(NSMutableSet<NSString *> *)identifiers {
  if (![profile isKindOfClass:NSDictionary.class]) return;
  NSString *did = [self normalizedProfileIdentifier:profile[@"did"]];
  NSString *handle = [self normalizedProfileIdentifier:profile[@"handle"]];
  if (did.length > 0) [identifiers addObject:did];
  if (handle.length > 0) [identifiers addObject:handle];
}

- (BOOL)isAlreadyViewingProfile:(NSDictionary *)profile {
  if (self.kind != NFBTimelineKindProfile) return NO;

  NSMutableSet<NSString *> *visibleIdentifiers = [NSMutableSet set];
  NSString *actor = [self normalizedProfileIdentifier:self.actor];
  NSString *loadedActor = [self normalizedProfileIdentifier:self.loadedProfileActor];
  if (actor.length > 0) [visibleIdentifiers addObject:actor];
  if (loadedActor.length > 0) [visibleIdentifiers addObject:loadedActor];
  [self addProfileIdentifiersFromProfile:self.profile toSet:visibleIdentifiers];
  if (self.actor.length == 0) {
    NSString *sessionDID = [self normalizedProfileIdentifier:[NFBAtprotoSession sharedSession].did];
    NSString *sessionHandle = [self normalizedProfileIdentifier:[NFBAtprotoSession sharedSession].handle];
    if (sessionDID.length > 0) [visibleIdentifiers addObject:sessionDID];
    if (sessionHandle.length > 0) [visibleIdentifiers addObject:sessionHandle];
  }

  NSMutableSet<NSString *> *targetIdentifiers = [NSMutableSet set];
  [self addProfileIdentifiersFromProfile:profile toSet:targetIdentifiers];
  for (NSString *identifier in targetIdentifiers) {
    if ([visibleIdentifiers containsObject:identifier]) return YES;
  }
  return NO;
}

- (BOOL)isViewingProfileForProfile:(NSDictionary *)profile {
  return [self isAlreadyViewingProfile:profile];
}

- (UITableViewCell *)cellContainingView:(UIView *)view {
  UIView *candidate = view;
  while (candidate && ![candidate isKindOfClass:UITableViewCell.class]) {
    candidate = candidate.superview;
  }
  return [candidate isKindOfClass:UITableViewCell.class] ? (UITableViewCell *)candidate : nil;
}

- (void)animateCurrentProfileReselection {
  if (self.kind != NFBTimelineKindProfile || UIAccessibilityIsReduceMotionEnabled()) return;
  // TFNAdditions tfn_animateBounce, Twitter 9.67: the profile view (not
  // the avatar) moves horizontally by -5/+3pt over these exact key times.
  CAKeyframeAnimation *bounce = [CAKeyframeAnimation animationWithKeyPath:@"position.x"];
  CGFloat x = self.view.layer.position.x;
  bounce.values = @[@(x), @(x - 5.0), @(x), @(x + 3.0), @(x)];
  bounce.keyTimes = @[@0.0, @0.5, @0.7, @0.8, @1.0];
  bounce.duration = 0.3;
  [self.view.layer addAnimation:bounce forKey:@"nfb.profile.reselection"];
}

- (void)profileAvatarTapped {
  [self presentProfilePhotoURL:[NFBAtprotoClient avatarURLForProfile:self.profile] imageView:self.profileHeaderAvatarImageView avatar:YES];
}
- (void)profileBannerTapped {
  // The reference first expands a collapsed cover, then opens its photo.
  if (self.tableView.contentOffset.y > 1.0) { [self.tableView setContentOffset:CGPointZero animated:YES]; return; }
  [self presentProfilePhotoURL:[self profileStringForKey:@"banner"] imageView:self.profileHeaderBannerImageView avatar:NO];
}
- (void)presentProfilePhotoURL:(NSString *)url imageView:(UIImageView *)imageView avatar:(BOOL)avatar {
  if (!url.length || self.presentedViewController) return;
  NFBMediaViewerViewController *viewer = [[NFBMediaViewerViewController alloc] initWithProfileImageURL:url previewImage:imageView.image avatar:avatar sourceImageView:imageView];
  [self presentViewController:viewer animated:YES completion:nil];
}

- (void)pushProfileForProfile:(NSDictionary *)profile {
  if ([self isAlreadyViewingProfile:profile]) { [self animateCurrentProfileReselection]; return; }
  NSString *actor = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
  if (actor.length == 0) actor = [profile[@"handle"] isKindOfClass:NSString.class] ? profile[@"handle"] : @"";
  if (actor.length == 0) return;
  NFBTimelineViewController *profileController = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
  [self.navigationController pushViewController:profileController animated:YES];
}

- (BOOL)openNotificationTweetForGroup:(NSDictionary *)item {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  if (uri.length == 0) uri = [item[@"targetURI"] isKindOfClass:NSString.class] ? item[@"targetURI"] : @"";
  if (uri.length == 0) return NO;

  NSMutableDictionary *detailPost = [post mutableCopy] ?: [NSMutableDictionary dictionary];
  detailPost[@"uri"] = uri;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:detailPost];
  [self.navigationController pushViewController:detail animated:YES];
  return YES;
}

- (void)openNotificationPeopleForGroup:(NSDictionary *)item {
  NSArray *users = [item[@"users"] isKindOfClass:NSArray.class] ? item[@"users"] : @[];
  NSDictionary *firstProfile = [users.firstObject isKindOfClass:NSDictionary.class] ? users.firstObject : @{};
  if (users.count > 1) {
    NFBActorListViewController *list = [[NFBActorListViewController alloc] initWithActors:users title:[self notificationPeopleTitleForGroup:item]];
    [self.navigationController pushViewController:list animated:YES];
  } else {
    [self pushProfileForProfile:firstProfile];
  }
}

- (void)openNotificationActivityGroup:(NSDictionary *)item {
  if ([self notificationGroupRoutesToProfile:item]) {
    [self openNotificationPeopleForGroup:item];
    return;
  }

  if ([self openNotificationTweetForGroup:item]) return;
  [self openNotificationPeopleForGroup:item];
}

- (NSString *)notificationActivityGroupKeyFromGroup:(NSDictionary *)group {
  NSString *key = [group[@"groupKey"] isKindOfClass:NSString.class] ? group[@"groupKey"] : @"";
  if (key.length > 0) return key;
  return [self notificationActivityGroupKeyForItem:group ?: @{}];
}

- (BOOL)notificationActivityGroup:(NSDictionary *)group hasKey:(NSString *)key {
  if (key.length == 0) return NO;
  return [[self notificationActivityGroupKeyFromGroup:group] isEqualToString:key];
}

- (void)dismissNotificationActivityGroup:(NSDictionary *)group preferredIndexPath:(NSIndexPath *)preferredIndexPath {
  NSString *key = [self notificationActivityGroupKeyFromGroup:group];
  if (key.length > 0) [self addDismissedNotificationActivityGroupKey:key];

  __block NSInteger row = NSNotFound;
  if (preferredIndexPath && preferredIndexPath.row >= 0 && preferredIndexPath.row < (NSInteger)self.items.count) {
    NSDictionary *candidate = self.items[(NSUInteger)preferredIndexPath.row];
    if ([self notificationActivityGroup:candidate hasKey:key]) row = preferredIndexPath.row;
  }
  if (row == NSNotFound) {
    [self.items enumerateObjectsUsingBlock:^(NSDictionary *candidate, NSUInteger index, BOOL *stop) {
      if ([self notificationActivityGroup:candidate hasKey:key]) {
        row = (NSInteger)index;
        *stop = YES;
      }
    }];
  }
  if (row == NSNotFound || row < 0 || row >= (NSInteger)self.items.count) return;

  NSIndexPath *deleteIndexPath = [NSIndexPath indexPathForRow:row inSection:0];
  [self.items removeObjectAtIndex:(NSUInteger)row];
  [self.tableView deleteRowsAtIndexPaths:@[deleteIndexPath] withRowAnimation:UITableViewRowAnimationFade];
  [self updateEmptyState:self.items.count == 0 ? [self emptyMessageForCurrentView] : @""];
}

- (NSIndexPath *)indexPathForNotificationActivityControl:(UIView *)control {
  UITableViewCell *cell = [self cellContainingView:control];
  NSIndexPath *indexPath = cell ? [self.tableView indexPathForCell:cell] : nil;
  if (!indexPath || indexPath.row < 0 || indexPath.row >= (NSInteger)self.items.count) return nil;
  NSDictionary *item = self.items[(NSUInteger)indexPath.row];
  if (![item[@"type"] isEqualToString:@"notificationActivityGroup"]) return nil;
  return indexPath;
}

- (void)notificationPositiveFeedbackTapped:(UIButton *)sender {
  NSIndexPath *indexPath = [self indexPathForNotificationActivityControl:sender];
  if (!indexPath) return;
  NSDictionary *item = self.items[(NSUInteger)indexPath.row];
  NSString *key = [self notificationActivityGroupKeyFromGroup:item];
  if (key.length > 0) [self addPositiveFeedbackNotificationActivityGroupKey:key];

  NSMutableDictionary *updated = [item mutableCopy];
  updated[@"positiveFeedback"] = @YES;
  self.items[(NSUInteger)indexPath.row] = updated;
  UISelectionFeedbackGenerator *feedback = [[UISelectionFeedbackGenerator alloc] init];
  [feedback selectionChanged];
  [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)notificationNegativeFeedbackTapped:(UIButton *)sender {
  NSIndexPath *indexPath = [self indexPathForNotificationActivityControl:sender];
  if (!indexPath) return;
  NSDictionary *item = self.items[(NSUInteger)indexPath.row];
  UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
  [feedback impactOccurred];
  [self dismissNotificationActivityGroup:item preferredIndexPath:indexPath];
}

- (void)notificationActivityMoreTapped:(UIButton *)sender {
  UITableViewCell *cell = [self cellContainingView:sender];
  NSIndexPath *indexPath = cell ? [self.tableView indexPathForCell:cell] : nil;
  if (!indexPath || indexPath.row < 0 || indexPath.row >= (NSInteger)self.items.count) return;
  NSDictionary *item = self.items[(NSUInteger)indexPath.row];
  if (![item[@"type"] isEqualToString:@"notificationActivityGroup"]) return;

  NSArray *users = [item[@"users"] isKindOfClass:NSArray.class] ? item[@"users"] : @[];
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  if (uri.length == 0) uri = [item[@"targetURI"] isKindOfClass:NSString.class] ? item[@"targetURI"] : @"";
  BOOL routesToProfile = [self notificationGroupRoutesToProfile:item];

  __weak typeof(self) weakSelf = self;
  NSMutableArray<NSDictionary<NSString *, id> *> *actions = [NSMutableArray array];
  if (!routesToProfile && uri.length > 0) {
    [actions addObject:@{
      @"id": @"view-tweet",
      @"title": @"View Tweet",
      @"subtitle": @"Open the Tweet tied to this notification",
      @"icon": @"nfb_link",
      @"handler": [^{
      [weakSelf openNotificationTweetForGroup:item];
    } copy]
    }];
  }
  if (users.count > 0) {
    NSString *title = users.count > 1 ? @"View people" : @"View profile";
    [actions addObject:@{
      @"id": @"view-people",
      @"title": title,
      @"subtitle": users.count > 1 ? @"See the accounts in this notification" : @"Open this account’s profile",
      @"icon": @"nfb_profile",
      @"handler": [^{
      [weakSelf openNotificationPeopleForGroup:item];
    } copy]
    }];
  }
  if (actions.count == 0) {
    [actions addObject:@{
      @"id": @"open",
      @"title": @"Open Notification",
      @"subtitle": @"Open this notification",
      @"icon": @"nfb_notifications",
      @"handler": [^{
      [weakSelf openNotificationActivityGroup:item];
    } copy]
    }];
  }
  [actions addObject:@{
    @"id": @"dismiss",
    @"title": @"Dismiss this notification",
    @"subtitle": @"Hide it from this list",
    @"icon": @"nfb_close",
    @"handler": [^{
    [weakSelf dismissNotificationActivityGroup:item preferredIndexPath:indexPath];
  } copy]
  }];
  (void)sender;
  NFBPresentNeoFreeBirdMenuSheet(self, @"Notification options", nil, actions, nil);
}

#pragma mark - UITableViewDataSource

- (NSArray<NSDictionary *> *)itemsForTableView:(UITableView *)tableView {
  if (tableView == self.homeFeedPreviewTableView) return self.homeFeedPreviewItems ?: @[];
  return self.items ?: @[];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)section;
  return (NSInteger)[self itemsForTableView:tableView].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSArray<NSDictionary *> *items = [self itemsForTableView:tableView];
  NSDictionary *item = indexPath.row < (NSInteger)items.count ? items[(NSUInteger)indexPath.row] : @{};
  if (self.searchResultsMode && self.searchTab == NFBSearchTabPeople) {
    NFBActorCell *cell = [tableView dequeueReusableCellWithIdentifier:@"searchActor" forIndexPath:indexPath]; cell.delegate = self; [cell configureWithProfile:item]; return cell;
  }
  if ([item[@"type"] isEqualToString:@"trend"]) {
    NFBTrendCell *cell = [tableView dequeueReusableCellWithIdentifier:@"trend" forIndexPath:indexPath];
    [cell configureWithTrend:item];
    return cell;
  }

  if ([item[@"type"] isEqualToString:@"notificationActivityGroup"]) {
    NFBNotificationActivityCell *cell = [tableView dequeueReusableCellWithIdentifier:@"notificationActivity" forIndexPath:indexPath];
    [cell configureWithGroup:item];
    [cell.positiveFeedbackButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.positiveFeedbackButton addTarget:self action:@selector(notificationPositiveFeedbackTapped:) forControlEvents:UIControlEventTouchUpInside];
    [cell.negativeFeedbackButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.negativeFeedbackButton addTarget:self action:@selector(notificationNegativeFeedbackTapped:) forControlEvents:UIControlEventTouchUpInside];
    [cell.moreButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.moreButton addTarget:self action:@selector(notificationActivityMoreTapped:) forControlEvents:UIControlEventTouchUpInside];
    return cell;
  }

  if ((self.kind == NFBTimelineKindProfile && [self profileTabUsesResourceCells:self.selectedProfileTabID]) ||
      self.kind == NFBTimelineKindLists ||
      self.kind == NFBTimelineKindFeeds) {
    NFBProfileResourceCell *cell = [tableView dequeueReusableCellWithIdentifier:@"profileResource" forIndexPath:indexPath];
    [cell configureWithItem:item];
    return cell;
  }

  NFBPostCell *cell = [tableView dequeueReusableCellWithIdentifier:@"post" forIndexPath:indexPath];
  cell.delegate = tableView == self.homeFeedPreviewTableView ? nil : self;
  [cell configureWithFeedItem:item];
  if (@available(iOS 13.0, *)) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    [cell setMoreMenu:cell.delegate ? [[self postActionCoordinator] contextMenuForPost:post] : nil];
  }
  return cell;
}

#pragma mark - UITableViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (scrollView == self.searchPager) {
    NSInteger page = NFBSearchPageForOffset(scrollView.contentOffset.x, CGRectGetWidth(scrollView.bounds), self.searchPages.count);
    [self loadSearchPagesNearIndex:page];
    [self updateSearchPageIndicator];
    return;
  }
  if (scrollView == self.searchTabsScrollView) { [self updateSearchPageIndicator]; return; }
  if (scrollView == self.homeFeedPreviewTableView) return;
  if (scrollView == self.tableView) {
    [self updateFeedNavigationForScrollOffset];
    if (self.kind == NFBTimelineKindHome && self.navigationController.topViewController == self &&
        scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top && self.navigationController.navigationBarHidden) {
      [self.navigationController setNavigationBarHidden:NO animated:YES];
    }
  }
  [self updateProfileNavigationForScrollOffset];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)cell;
  if (tableView == self.homeFeedPreviewTableView) return;
  if (self.cursor.length > 0 && indexPath.row >= (NSInteger)self.items.count - 5) {
    [self loadNextPageReplacing:NO];
  }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  if (tableView == self.homeFeedPreviewTableView) return;
  if (self.suppressTimelineSelectionForSwipe || self.homeFeedPanTracking) {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    return;
  }
  if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.items.count) return;
  NSDictionary *item = self.items[(NSUInteger)indexPath.row];
  if (self.searchResultsMode && self.searchTab == NFBSearchTabPeople) { [[self postActionCoordinator] performGoToProfile:item]; return; }
  if ([item[@"type"] isEqualToString:@"trend"]) {
    [self searchForTrend:item];
    return;
  }
  if ([item[@"type"] isEqualToString:@"notificationActivityGroup"]) {
    [self openNotificationActivityGroup:item];
    return;
  }
  if ((self.kind == NFBTimelineKindProfile && [self profileTabUsesResourceCells:self.selectedProfileTabID]) ||
      self.kind == NFBTimelineKindLists ||
      self.kind == NFBTimelineKindFeeds) {
    [self handleResourceItemSelection:item sourceView:[tableView cellForRowAtIndexPath:indexPath]];
    return;
  }
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
  if (![post[@"uri"] isKindOfClass:NSString.class]) return;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
  [self.navigationController pushViewController:detail animated:YES];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
  (void)tableView;
  (void)point;
  if (@available(iOS 13.0, *)) {
    NSDictionary *post = [self postForActionAtIndexPath:indexPath];
    NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if (uri.length == 0) return nil;
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:uri
                                                  previewProvider:^UIViewController * _Nullable{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      NFBTweetDetailViewController *preview = [[NFBTweetDetailViewController alloc] initWithPost:post];
      CGFloat width = strongSelf ? MIN(390.0, MAX(300.0, CGRectGetWidth(strongSelf.view.bounds) - 28.0)) : 360.0;
      preview.preferredContentSize = CGSizeMake(width, 520.0);
      return preview;
    } actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
      (void)suggestedActions;
      __strong typeof(weakSelf) strongSelf = weakSelf;
      return strongSelf ? [[strongSelf postActionCoordinator] contextMenuForPost:post] : nil;
    }];
  }
  return nil;
}

- (void)tableView:(UITableView *)tableView willPerformPreviewActionForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionCommitAnimating>)animator {
  (void)tableView;
  if (@available(iOS 13.0, *)) {
    id identifier = configuration.identifier;
    NSString *uri = [identifier isKindOfClass:NSString.class] ? (NSString *)identifier : @"";
    if (uri.length == 0) return;
    __weak typeof(self) weakSelf = self;
    [animator addCompletion:^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      NSDictionary *post = [strongSelf postForURI:uri];
      if (strongSelf && post.count > 0) [strongSelf pushDetailForPost:post];
    }];
  }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
  // Horizontal drags belong to navigation, section paging, or media. Tweet
  // actions remain in the existing action bar and long-press/overflow menu.
  return nil;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)tableView;
  (void)indexPath;
  return nil;
}

#pragma mark - NFBPostCellDelegate

- (BOOL)ensureSessionForTweetAction {
  if ([[NFBAtprotoSession sharedSession] hasSession]) return YES;
  NFBPresentBlueskyLoginIfNeeded();
  return NO;
}

- (void)presentReplyForPost:(NSDictionary *)post {
  if (![self ensureSessionForTweetAction]) return;
  NFBComposeViewController *compose = [[NFBComposeViewController alloc] initWithReplyToPost:post];
  compose.completionHandler = ^(BOOL posted) {
    if (posted) [self refreshTimeline];
  };
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:compose];
  NFBApplyNavigationAppearance(nav);
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)showRepostMenuForPost:(NSDictionary *)post updatedPostHandler:(void (^)(NSDictionary *updatedPost))updatedPostHandler {
  if (![self ensureSessionForTweetAction]) return;
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL reposted = [viewer[@"repost"] isKindOfClass:NSString.class] && [viewer[@"repost"] length] > 0;
  __weak typeof(self) weakSelf = self;
  NFBPresentNeoFreeBirdRetweetSheet(self, reposted, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [[NFBAtprotoClient sharedClient] toggleRepostForPost:post completion:^(NSDictionary *value, NSError *error) {
      if (!error) {
        NSDictionary *updatedPost = [NFBAtprotoClient post:post applyingToggleForViewerKey:@"repost" countKey:@"repostCount" response:value];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (updatedPostHandler) updatedPostHandler(updatedPost);
        });
      }
    }];
  }, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    NFBComposeViewController *compose = [[NFBComposeViewController alloc] initWithQuotePost:post];
    compose.completionHandler = ^(BOOL posted) {
      if (posted) [strongSelf refreshTimeline];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:compose];
    NFBApplyNavigationAppearance(nav);
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [strongSelf presentViewController:nav animated:YES completion:nil];
  });
}

- (NSDictionary *)feedItem:(NSDictionary *)item byReplacingPost:(NSDictionary *)post {
  if (![item isKindOfClass:NSDictionary.class]) return @{@"post": post ?: @{}};
  NSMutableDictionary *updatedItem = [item mutableCopy];
  updatedItem[@"post"] = post ?: @{};
  return updatedItem;
}

- (void)applyUpdatedPost:(NSDictionary *)updatedPost originalPost:(NSDictionary *)originalPost {
  NSString *targetURI = [originalPost[@"uri"] isKindOfClass:NSString.class] ? originalPost[@"uri"] : @"";
  if (targetURI.length == 0 || ![updatedPost isKindOfClass:NSDictionary.class]) return;
  NSDictionary *updatedViewer = [updatedPost[@"viewer"] isKindOfClass:NSDictionary.class] ? updatedPost[@"viewer"] : @{};
  if (self.kind == NFBTimelineKindBookmarks && [updatedViewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && ![updatedViewer[@"bookmarked"] boolValue]) {
    [self removeDeletedPost:originalPost];
    return;
  }
  if (self.kind == NFBTimelineKindBookmarks) {
    for (NSUInteger index = 0; index < self.bookmarkItems.count; index++) {
      NSDictionary *item = self.bookmarkItems[index];
      NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
      if ([post[@"uri"] isEqual:targetURI]) self.bookmarkItems[index] = [self feedItem:item byReplacingPost:updatedPost];
    }
    [self filterBookmarkItems];
    [self.tableView reloadData];
    [self updateEmptyState:self.items.count == 0 ? [self emptyMessageForCurrentView] : @""];
    return;
  }
  NSMutableArray<NSIndexPath *> *reloadPaths = [NSMutableArray array];
  for (NSUInteger index = 0; index < self.items.count; index++) {
    NSDictionary *item = self.items[index];
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if (![uri isEqualToString:targetURI]) continue;
    self.items[index] = [self feedItem:item byReplacingPost:updatedPost];
    [reloadPaths addObject:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]];
  }
  if (reloadPaths.count > 0) {
    [self.tableView reloadRowsAtIndexPaths:reloadPaths withRowAnimation:UITableViewRowAnimationNone];
  }
}

- (NSDictionary *)postForActionAtIndexPath:(NSIndexPath *)indexPath {
  if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.items.count) return @{};
  NSDictionary *item = self.items[(NSUInteger)indexPath.row];
  if ([item[@"type"] isEqualToString:@"trend"]) return @{};
  if ([item[@"type"] isEqualToString:@"notificationActivityGroup"] && [self notificationGroupRoutesToProfile:item]) return @{};
  if (self.kind == NFBTimelineKindProfile && [self profileTabUsesResourceCells:self.selectedProfileTabID]) return @{};
  if (self.kind == NFBTimelineKindLists || self.kind == NFBTimelineKindFeeds) return @{};
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
  return [post[@"uri"] isKindOfClass:NSString.class] ? post : @{};
}

- (BOOL)isPostAuthoredByCurrentUser:(NSDictionary *)post {
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  NSString *authorDID = [author[@"did"] isKindOfClass:NSString.class] ? author[@"did"] : @"";
  NSString *sessionDID = [NFBAtprotoSession sharedSession].did ?: @"";
  return authorDID.length > 0 && sessionDID.length > 0 && [authorDID isEqualToString:sessionDID];
}

- (void)presentShareForPost:(NSDictionary *)post {
  NSString *urlString = [NFBAtprotoClient webURLStringForPost:post];
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  id shareItem = url ?: (uri ?: @"");
  if ([shareItem isKindOfClass:NSString.class] && [(NSString *)shareItem length] == 0) return;
  UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[shareItem] applicationActivities:nil];
  [self presentViewController:activity animated:YES completion:nil];
}

- (void)openExternalCardForPost:(NSDictionary *)post {
  NSDictionary *card = [NFBAtprotoClient externalCardForPost:post ?: @{}];
  if ([NFBAtprotoClient externalCardIsStandardSiteArticle:card]) {
    NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if (uri.length > 0) {
      NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
      [self.navigationController pushViewController:detail animated:YES];
    }
    return;
  }
  NSString *urlString = [card[@"url"] isKindOfClass:NSString.class] ? card[@"url"] : @"";
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
  safari.preferredControlTintColor = NFBColorAccent();
  [self presentViewController:safari animated:YES completion:nil];
}

- (void)openExternalCardWebsiteForPost:(NSDictionary *)post {
  NSDictionary *card = [NFBAtprotoClient externalCardForPost:post ?: @{}];
  NSString *urlString = [card[@"url"] isKindOfClass:NSString.class] ? card[@"url"] : @"";
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
  safari.preferredControlTintColor = NFBColorAccent();
  [self presentViewController:safari animated:YES completion:nil];
}

- (void)toggleBookmarkForPost:(NSDictionary *)post {
  if (![self ensureSessionForTweetAction]) return;
  [[NFBAtprotoClient sharedClient] toggleBookmarkForPost:post completion:^(NSDictionary *value, NSError *error) {
    if (!error) {
      NSDictionary *updatedPost = [NFBAtprotoClient postByApplyingBookmarkToggleForPost:post response:value];
      dispatch_async(dispatch_get_main_queue(), ^{ [self applyUpdatedPost:updatedPost originalPost:post]; });
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{ [self showActionError:error]; });
    }
  }];
}

- (void)toggleLikeForPost:(NSDictionary *)post {
  if (![self ensureSessionForTweetAction]) return;
  [[NFBAtprotoClient sharedClient] toggleLikeForPost:post completion:^(NSDictionary *value, NSError *error) {
    if (!error) {
      NSDictionary *updatedPost = [NFBAtprotoClient post:post applyingToggleForViewerKey:@"like" countKey:@"likeCount" response:value];
      dispatch_async(dispatch_get_main_queue(), ^{ [self applyUpdatedPost:updatedPost originalPost:post]; });
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{ [self showActionError:error]; });
    }
  }];
}

- (void)confirmDeletePost:(NSDictionary *)post {
  [[self postActionCoordinator] performDeleteForPost:post sourceView:nil];
}

- (void)removeDeletedPost:(NSDictionary *)post {
  NSString *targetURI = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  if (targetURI.length == 0) {
    [self refreshTimeline];
    return;
  }
  if (self.kind == NFBTimelineKindBookmarks) {
    NSIndexSet *bookmarkIndexes = [self.bookmarkItems indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
      return [[NFBAtprotoClient postFromFeedItem:item][@"uri"] isEqual:targetURI];
    }];
    [self.bookmarkItems removeObjectsAtIndexes:bookmarkIndexes];
    [self filterBookmarkItems];
    [self.tableView reloadData];
    [self updateEmptyState:self.items.count == 0 ? [self emptyMessageForCurrentView] : @""];
    return;
  }
  NSMutableArray<NSIndexPath *> *paths = [NSMutableArray array];
  NSIndexSet *indexes = [self.items indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
    (void)idx;
    (void)stop;
    NSDictionary *candidate = [NFBAtprotoClient postFromFeedItem:item];
    NSString *uri = [candidate[@"uri"] isKindOfClass:NSString.class] ? candidate[@"uri"] : @"";
    return [uri isEqualToString:targetURI];
  }];
  [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
    (void)stop;
    [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)idx inSection:0]];
  }];
  if (paths.count == 0) {
    [self refreshTimeline];
    return;
  }
  [self.items removeObjectsAtIndexes:indexes];
  [self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationAutomatic];
  [self updateEmptyState:self.items.count == 0 ? [self emptyMessageForCurrentView] : @""];
}

- (void)showActionError:(NSError *)error {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't update Tweet"
                                                                 message:error.localizedDescription ?: @"Please try again."
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (NSDictionary *)postForURI:(NSString *)uri {
  if (uri.length == 0) return @{};
  for (NSDictionary *item in self.items) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    NSString *candidateURI = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if ([candidateURI isEqualToString:uri]) return post;
  }
  return @{};
}

- (void)pushDetailForPost:(NSDictionary *)post {
  if (![post[@"uri"] isKindOfClass:NSString.class]) return;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
  [self.navigationController pushViewController:detail animated:YES];
}

- (UIMenu *)contextMenuForPost:(NSDictionary *)post {
  return [[self postActionCoordinator] contextMenuForPost:post];
}

- (void)showMoreMenuForPost:(NSDictionary *)post {
  [[self postActionCoordinator] presentMoreMenuForPost:post sourceView:nil];
}

- (void)presentMediaItems:(NSArray<NSDictionary *> *)mediaItems initialIndex:(NSUInteger)index post:(NSDictionary *)post transitionSource:(NFBMediaTransitionSource *)transitionSource {
  if (mediaItems.count == 0) return;
  NFBMediaViewerViewController *viewer = [[NFBMediaViewerViewController alloc] initWithMediaItems:mediaItems initialIndex:index post:post];
  viewer.transitionSource = transitionSource;
  viewer.delegate = self;
  [self presentViewController:viewer animated:YES completion:nil];
}

- (void)postCellDidTapReply:(NFBPostCell *)cell {
  [[self postActionCoordinator] performReplyForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidTapRepost:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  [[self postActionCoordinator] performRepostForPost:post sourceView:nil];
}

- (void)postCellDidTapLike:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  [[self postActionCoordinator] performLikeForPost:post sourceView:nil];
}

- (void)postCellDidTapBookmark:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  [[self postActionCoordinator] performBookmarkForPost:post sourceView:nil];
}

- (void)postCellDidTapShare:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  [[self postActionCoordinator] performShareForPost:post sourceView:nil];
}

- (void)postCellDidTapMore:(NFBPostCell *)cell {
  [[self postActionCoordinator] presentMoreMenuForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidLongPress:(NFBPostCell *)cell {
  [[self postActionCoordinator] presentMoreMenuForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidTapReposter:(NFBPostCell *)cell {
  NSDictionary *reposter = NFBFeedReposter(cell.feedItem);
  NSString *actor = [reposter[@"did"] isKindOfClass:NSString.class] ? reposter[@"did"] : reposter[@"handle"];
  if (![actor isKindOfClass:NSString.class] || actor.length == 0) return;
  NFBTimelineViewController *profile = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
  [self.navigationController pushViewController:profile animated:YES];
}

- (void)postCellDidTapAuthor:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  [self pushProfileForProfile:author];
}

- (void)postCell:(NFBPostCell *)cell didTapLinkURL:(NSURL *)url {
  (void)cell;
  NFBOpenTweetTextURL(url, self);
}

- (void)postCell:(NFBPostCell *)cell didTapMediaAtIndex:(NSUInteger)index transitionSource:(NFBMediaTransitionSource *)transitionSource {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  [self presentMediaItems:[NFBAtprotoClient mediaItemsForPost:post] initialIndex:index post:post transitionSource:transitionSource];
}

- (void)postCellDidTapExternalCard:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  [self openExternalCardForPost:post];
}

- (void)postCellDidTapExternalCardWebsite:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  [self openExternalCardWebsiteForPost:post];
}

- (void)postCellDidTapQuotedPost:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post];
  if (!quotedPost) return;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:quotedPost];
  [self.navigationController pushViewController:detail animated:YES];
}

- (void)postCell:(NFBPostCell *)cell didTapQuotedMediaAtIndex:(NSUInteger)index transitionSource:(NFBMediaTransitionSource *)transitionSource {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post];
  [self presentMediaItems:[NFBAtprotoClient mediaItemsForPost:quotedPost ?: @{}] initialIndex:index post:quotedPost ?: @{} transitionSource:transitionSource];
}

- (void)postCellDidTapQuotedExternalCard:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post];
  [self openExternalCardForPost:quotedPost ?: @{}];
}

- (void)postCellDidTapQuotedExternalCardWebsite:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post];
  [self openExternalCardWebsiteForPost:quotedPost ?: @{}];
}

- (void)mediaViewerViewController:(NFBMediaViewerViewController *)viewer
                    didUpdatePost:(NSDictionary *)updatedPost
                     originalPost:(NSDictionary *)originalPost {
  (void)viewer;
  [self applyUpdatedPost:updatedPost originalPost:originalPost];
}

@end
