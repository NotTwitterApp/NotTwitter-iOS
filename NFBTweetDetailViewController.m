#import "NFBTweetDetailViewController.h"
#import "NFBThreadModel.h"

#import "NFBAtprotoClient.h"
#import "NFBActorListViewController.h"
#import "NFBAtprotoSession.h"
#import "NFBBlueskyLoginViewController.h"
#import "NFBComposeViewController.h"
#import "NFBExternalCardView.h"
#import "NFBLinkRouter.h"
#import "NFBMediaPreviewView.h"
#import "NFBMediaViewerViewController.h"
#import "NFBModeration.h"
#import "NFBNeoFreeBirdUI.h"
#import "NFBNotificationCoordinator.h"
#import "NFBPostActionCoordinator.h"
#import "NFBPostCell.h"
#import "NFBQuotedPostView.h"
#import "NFBTheme.h"
#import "NFBTimelineViewController.h"

#import <SafariServices/SafariServices.h>

@class NFBTweetDetailFocalCell;
@class NFBTweetDetailReaderCell;

@protocol NFBTweetDetailFocalCellDelegate <NSObject>
- (void)tweetDetailFocalCellDidTapReply:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapRepost:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapLike:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapBookmark:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapShare:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapMore:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapFollow:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidLongPress:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapAuthor:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCell:(NFBTweetDetailFocalCell *)cell didTapLinkURL:(NSURL *)url;
- (void)tweetDetailFocalCell:(NFBTweetDetailFocalCell *)cell didTapMetricType:(NSString *)metricType;
- (void)tweetDetailFocalCell:(NFBTweetDetailFocalCell *)cell didTapMediaAtIndex:(NSUInteger)index;
- (void)tweetDetailFocalCellDidTapExternalCard:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapExternalCardWebsite:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapArticleNotifications:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapQuotedPost:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCell:(NFBTweetDetailFocalCell *)cell didTapQuotedMediaAtIndex:(NSUInteger)index;
- (void)tweetDetailFocalCellDidTapQuotedExternalCard:(NFBTweetDetailFocalCell *)cell;
- (void)tweetDetailFocalCellDidTapQuotedExternalCardWebsite:(NFBTweetDetailFocalCell *)cell;
@end

@protocol NFBTweetDetailReaderCellDelegate <NSObject>
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapLinkURL:(NSURL *)url;
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapAuthorForPost:(NSDictionary *)post;
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapMediaAtIndex:(NSUInteger)index post:(NSDictionary *)post;
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapExternalCardForPost:(NSDictionary *)post;
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapExternalCardWebsiteForPost:(NSDictionary *)post;
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapQuotedPostForPost:(NSDictionary *)post;
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapQuotedMediaAtIndex:(NSUInteger)index post:(NSDictionary *)post;
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapQuotedExternalCardForPost:(NSDictionary *)post;
- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapQuotedExternalCardWebsiteForPost:(NSDictionary *)post;
@end

@interface NFBTweetDetailFocalCell : UITableViewCell

@property (nonatomic, weak) id<NFBTweetDetailFocalCellDelegate> delegate;
@property (nonatomic, strong, readonly) NSDictionary *post;

- (void)configureWithPost:(NSDictionary *)post;
- (void)setThreadConnectorAbove:(BOOL)above below:(BOOL)below;
- (void)setMoreMenu:(nullable UIMenu *)menu API_AVAILABLE(ios(13.0));

@end

@interface NFBTweetDetailFocalCell () <NFBMediaPreviewViewDelegate, NFBExternalCardViewDelegate, NFBQuotedPostViewDelegate>

@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIView *threadConnectorTopView;
@property (nonatomic, strong) UIView *threadConnectorBottomView;
@property (nonatomic, strong) UIStackView *headerRow;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *followsYouLabel;
@property (nonatomic, strong) UIImageView *verifiedBadgeView;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UIButton *followButton;
@property (nonatomic, strong) NFBInteractiveTextLabel *bodyLabel;
@property (nonatomic, strong) UIView *tombstoneView;
@property (nonatomic, strong) NFBInteractiveTextLabel *tombstoneTitleLabel;
@property (nonatomic, strong) NFBInteractiveTextLabel *tombstoneSubtitleLabel;
@property (nonatomic, strong) NFBMediaPreviewView *mediaView;
@property (nonatomic, strong) NFBExternalCardView *externalCardView;
@property (nonatomic, strong) UIButton *articleNotificationButton;
@property (nonatomic, strong) NFBQuotedPostView *quotedPostView;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) UIView *metricsContainer;
@property (nonatomic, strong) UIStackView *metricsStack;
@property (nonatomic, strong) UILabel *repostMetricLabel;
@property (nonatomic, strong) UILabel *quoteMetricLabel;
@property (nonatomic, strong) UILabel *likeMetricLabel;
@property (nonatomic, strong) UILabel *viewMetricLabel;
@property (nonatomic, strong) UIView *actionsContainer;
@property (nonatomic, strong) UIStackView *actionsRow;
@property (nonatomic, strong) UIView *actionsBottomBorder;
@property (nonatomic, strong) UIImageView *replyIconView;
@property (nonatomic, strong) UIImageView *repostIconView;
@property (nonatomic, strong) UIImageView *likeIconView;
@property (nonatomic, strong) UIImageView *bookmarkIconView;
@property (nonatomic, strong) UIImageView *shareIconView;
@property (nonatomic, strong) UIView *bottomBorder;
@property (nonatomic, strong) NSLayoutConstraint *mediaHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *externalCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tombstoneSubtitleBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tombstoneTitleOnlyBottomConstraint;
@property (nonatomic, copy) NSString *avatarURLString;
@property (nonatomic, copy) NSArray<NSDictionary *> *mediaItems;
@property (nonatomic, strong, nullable) NSDictionary *externalCard;
@property (nonatomic, strong, nullable) NSDictionary *quotedPost;
@property (nonatomic, strong, readwrite) NSDictionary *post;
@property (nonatomic, assign) BOOL tombstoned;

@end

@implementation NFBTweetDetailFocalCell

#define NFBTweetDetailActionButtonWidth NFBIPAMetricValue(NFBIPAMetricDetailActionButtonWidth)
#define NFBTweetDetailActionIconSize NFBIPAMetricValue(NFBIPAMetricDetailActionIconSize)
#define NFBTweetDetailThreadRailWidth NFBIPAMetricValue(NFBIPAMetricThreadRailWidth)
#define NFBTweetDetailThreadRailAvatarGap NFBIPAMetricValue(NFBIPAMetricThreadRailAvatarGap)

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    [self buildSubviews];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    longPress.minimumPressDuration = 0.36;
    longPress.cancelsTouchesInView = NO;
    [self.contentView addGestureRecognizer:longPress];
  }
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.post = nil;
  self.avatarView.image = [self.class placeholderAvatarImage];
  [self.mediaView configureWithMediaItems:@[]];
  self.mediaView.hidden = YES;
  [self.externalCardView configureWithCard:nil];
  self.externalCardView.hidden = YES;
  self.externalCardHeightConstraint.constant = 0.0;
  self.articleNotificationButton.hidden = YES;
  [self.quotedPostView configureWithPost:nil];
  self.quotedPostView.hidden = YES;
  self.headerRow.hidden = NO;
  self.tombstoneView.hidden = YES;
  self.bodyLabel.hidden = NO;
  self.footerLabel.hidden = NO;
  self.metricsContainer.hidden = NO;
  self.actionsContainer.hidden = NO;
  self.avatarURLString = nil;
  self.mediaItems = @[];
  self.externalCard = nil;
  self.quotedPost = nil;
  self.tombstoned = NO;
  if (@available(iOS 13.0, *)) [self setMoreMenu:nil];
  [self setThreadConnectorAbove:NO below:NO];
  [self applyTheme];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  if (!self.externalCardView.hidden) [self updateExternalCardHeight];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

  self.avatarView = [[UIImageView alloc] initWithImage:[self.class placeholderAvatarImage]];
  self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarView.clipsToBounds = YES;
  self.avatarView.layer.cornerRadius = 24.0;
  self.avatarView.userInteractionEnabled = YES;
  UITapGestureRecognizer *avatarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)];
  [self.avatarView addGestureRecognizer:avatarTap];

  self.threadConnectorTopView = [[UIView alloc] init];
  self.threadConnectorTopView.translatesAutoresizingMaskIntoConstraints = NO;
  self.threadConnectorTopView.hidden = YES;
  self.threadConnectorTopView.layer.cornerRadius = NFBTweetDetailThreadRailWidth * 0.5;

  self.threadConnectorBottomView = [[UIView alloc] init];
  self.threadConnectorBottomView.translatesAutoresizingMaskIntoConstraints = NO;
  self.threadConnectorBottomView.hidden = YES;
  self.threadConnectorBottomView.layer.cornerRadius = NFBTweetDetailThreadRailWidth * 0.5;

  self.nameLabel = [[UILabel alloc] init];
  self.nameLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.nameLabel.textColor = NFBColorText();
  self.nameLabel.numberOfLines = 1;
  self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.verifiedBadgeView = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
  self.verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
  self.verifiedBadgeView.contentMode = UIViewContentModeScaleAspectFit;
  [self.verifiedBadgeView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.verifiedBadgeView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.verifiedBadgeView]];
  nameRow.translatesAutoresizingMaskIntoConstraints = NO;
  nameRow.axis = UILayoutConstraintAxisHorizontal;
  nameRow.alignment = UIStackViewAlignmentCenter;
  nameRow.spacing = 3.0;
  [nameRow setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [nameRow setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [self.nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [self.nameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

  self.handleLabel = [[UILabel alloc] init];
  self.handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.handleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.handleLabel.textColor = NFBColorSecondaryText();
  self.handleLabel.numberOfLines = 1;
  self.handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.handleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  self.followsYouLabel = [[UILabel alloc] init];
  self.followsYouLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.followsYouLabel.hidden = YES;
  NFBIPAApplyFollowsYouBadgeAppearance(self.followsYouLabel);

  UIStackView *handleRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.handleLabel, self.followsYouLabel]];
  handleRow.translatesAutoresizingMaskIntoConstraints = NO;
  handleRow.axis = UILayoutConstraintAxisHorizontal;
  handleRow.alignment = UIStackViewAlignmentCenter;
  handleRow.spacing = 6.0;

  UIStackView *authorStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, handleRow]];
  authorStack.axis = UILayoutConstraintAxisVertical;
  authorStack.alignment = UIStackViewAlignmentLeading;
  authorStack.spacing = 0.0;
  authorStack.userInteractionEnabled = YES;
  UITapGestureRecognizer *authorTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)];
  [authorStack addGestureRecognizer:authorTap];
  [authorStack setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  self.moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.moreButton setImage:NFBTemplateIcon(@"nfb_more") forState:UIControlStateNormal];
  self.moreButton.contentEdgeInsets = UIEdgeInsetsMake(5.0, 5.0, 5.0, 5.0);
  self.moreButton.accessibilityLabel = @"More";
  [self.moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.moreButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.followButton = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  self.followButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.followButton.layer.cornerRadius = 17.0;
  self.followButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 14.0, 0.0, 14.0);
  self.followButton.titleLabel.font = NFBFont(14.0, NFBFontWeightHeavy);
  self.followButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.followButton.accessibilityLabel = @"Follow";
  [self.followButton addTarget:self action:@selector(followTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.followButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.followButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *headerActions = [[UIStackView alloc] initWithArrangedSubviews:@[self.followButton, self.moreButton]];
  headerActions.axis = UILayoutConstraintAxisHorizontal;
  headerActions.alignment = UIStackViewAlignmentCenter;
  headerActions.spacing = 8.0;
  headerActions.distribution = UIStackViewDistributionFill;
  [headerActions setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [headerActions setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.avatarView, authorStack, headerActions]];
  self.headerRow.axis = UILayoutConstraintAxisHorizontal;
  self.headerRow.alignment = UIStackViewAlignmentCenter;
  self.headerRow.spacing = 12.0;
  self.headerRow.distribution = UIStackViewDistributionFill;

  self.bodyLabel = [[NFBInteractiveTextLabel alloc] init];
  self.bodyLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricDetailBodyFontSize), NFBFontWeightRegular);
  self.bodyLabel.textColor = NFBColorText();
  self.bodyLabel.numberOfLines = 0;
  self.bodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
  [self.bodyLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
  [self.bodyLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
  __weak typeof(self) weakSelf = self;
  self.bodyLabel.linkTapHandler = ^(NSURL *url) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf.delegate tweetDetailFocalCell:strongSelf didTapLinkURL:url];
  };

  self.tombstoneView = [[UIView alloc] init];
  self.tombstoneView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tombstoneView.hidden = YES;

  self.tombstoneTitleLabel = [[NFBInteractiveTextLabel alloc] init];
  self.tombstoneTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.tombstoneTitleLabel.linkTapHandler = self.bodyLabel.linkTapHandler;

  self.tombstoneSubtitleLabel = [[NFBInteractiveTextLabel alloc] init];
  self.tombstoneSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.tombstoneSubtitleLabel.linkTapHandler = self.bodyLabel.linkTapHandler;

  [self.tombstoneView addSubview:self.tombstoneTitleLabel];
  [self.tombstoneView addSubview:self.tombstoneSubtitleLabel];
  self.tombstoneSubtitleBottomConstraint = [self.tombstoneSubtitleLabel.bottomAnchor constraintEqualToAnchor:self.tombstoneView.bottomAnchor constant:-10.0];
  self.tombstoneTitleOnlyBottomConstraint = [self.tombstoneTitleLabel.bottomAnchor constraintEqualToAnchor:self.tombstoneView.bottomAnchor constant:-10.0];
  [NSLayoutConstraint activateConstraints:@[
    [self.tombstoneTitleLabel.topAnchor constraintEqualToAnchor:self.tombstoneView.topAnchor constant:10.0],
    [self.tombstoneTitleLabel.leadingAnchor constraintEqualToAnchor:self.tombstoneView.leadingAnchor constant:12.0],
    [self.tombstoneTitleLabel.trailingAnchor constraintEqualToAnchor:self.tombstoneView.trailingAnchor constant:-12.0],
    [self.tombstoneSubtitleLabel.topAnchor constraintEqualToAnchor:self.tombstoneTitleLabel.bottomAnchor],
    [self.tombstoneSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.tombstoneTitleLabel.leadingAnchor],
    [self.tombstoneSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.tombstoneTitleLabel.trailingAnchor],
    self.tombstoneSubtitleBottomConstraint,
    [self.tombstoneView.heightAnchor constraintGreaterThanOrEqualToConstant:40.0]
  ]];
  self.tombstoneTitleOnlyBottomConstraint.active = NO;

  self.mediaView = [[NFBMediaPreviewView alloc] init];
  self.mediaView.translatesAutoresizingMaskIntoConstraints = NO;
  self.mediaView.delegate = self;
  self.mediaView.hidden = YES;

  self.externalCardView = [[NFBExternalCardView alloc] init];
  self.externalCardView.translatesAutoresizingMaskIntoConstraints = NO;
  self.externalCardView.delegate = self;
  self.externalCardView.hidden = YES;

  self.articleNotificationButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.articleNotificationButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.articleNotificationButton.hidden = YES;
  self.articleNotificationButton.layer.cornerRadius = 0.0;
  self.articleNotificationButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  self.articleNotificationButton.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.articleNotificationButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.articleNotificationButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
  self.articleNotificationButton.imageEdgeInsets = UIEdgeInsetsMake(0.0, 1.0, 0.0, 0.0);
  self.articleNotificationButton.titleEdgeInsets = UIEdgeInsetsMake(0.0, 10.0, 0.0, -10.0);
  self.articleNotificationButton.accessibilityLabel = @"Article notifications";
  [self.articleNotificationButton addTarget:self action:@selector(articleNotificationsTapped) forControlEvents:UIControlEventTouchUpInside];

  self.quotedPostView = [[NFBQuotedPostView alloc] init];
  self.quotedPostView.translatesAutoresizingMaskIntoConstraints = NO;
  self.quotedPostView.delegate = self;
  self.quotedPostView.hidden = YES;

  self.footerLabel = [[UILabel alloc] init];
  self.footerLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricDetailFooterFontSize), NFBFontWeightRegular);
  self.footerLabel.textColor = NFBColorSecondaryText();
  self.footerLabel.numberOfLines = 1;

  self.repostMetricLabel = [self metricLabel];
  self.quoteMetricLabel = [self metricLabel];
  self.likeMetricLabel = [self metricLabel];
  self.viewMetricLabel = [self metricLabel];
  [self makeMetricLabel:self.repostMetricLabel type:@"reposts"];
  [self makeMetricLabel:self.quoteMetricLabel type:@"quotes"];
  [self makeMetricLabel:self.likeMetricLabel type:@"likes"];
  self.metricsStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.repostMetricLabel, self.quoteMetricLabel, self.likeMetricLabel, self.viewMetricLabel]];
  self.metricsStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.metricsStack.axis = UILayoutConstraintAxisHorizontal;
  self.metricsStack.alignment = UIStackViewAlignmentCenter;
  self.metricsStack.spacing = 20.0;
  self.metricsStack.distribution = UIStackViewDistributionFill;

  self.metricsContainer = [[UIView alloc] init];
  self.metricsContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [self.metricsContainer addSubview:self.metricsStack];
  UIView *metricsTopBorder = [self borderView];
  UIView *metricsBottomBorder = [self borderView];
  [self.metricsContainer addSubview:metricsTopBorder];
  [self.metricsContainer addSubview:metricsBottomBorder];

  UIView *replyItem = [self actionButtonWithIcon:@"nfb_reply" selector:@selector(replyTapped)];
  UIView *repostItem = [self actionButtonWithIcon:@"nfb_retweet" selector:@selector(repostTapped)];
  UIView *likeItem = [self actionButtonWithIcon:@"nfb_like" selector:@selector(likeTapped)];
  UIView *bookmarkItem = [self actionButtonWithIcon:@"nfb_bookmark" selector:@selector(bookmarkTapped)];
  UIView *shareItem = [self actionButtonWithIcon:@"nfb_share" selector:@selector(shareTapped)];
  self.replyIconView = [self iconViewInActionButton:replyItem];
  self.repostIconView = [self iconViewInActionButton:repostItem];
  self.likeIconView = [self iconViewInActionButton:likeItem];
  self.bookmarkIconView = [self iconViewInActionButton:bookmarkItem];
  self.shareIconView = [self iconViewInActionButton:shareItem];

  self.actionsRow = [[UIStackView alloc] initWithArrangedSubviews:@[replyItem, repostItem, likeItem, bookmarkItem, shareItem]];
  self.actionsRow.translatesAutoresizingMaskIntoConstraints = NO;
  self.actionsRow.axis = UILayoutConstraintAxisHorizontal;
  self.actionsRow.alignment = UIStackViewAlignmentCenter;
  self.actionsRow.distribution = UIStackViewDistributionEqualSpacing;
  self.actionsRow.spacing = 0.0;

  self.actionsContainer = [[UIView alloc] init];
  self.actionsContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [self.actionsContainer addSubview:self.actionsRow];
  self.actionsBottomBorder = [self borderView];
  [self.actionsContainer addSubview:self.actionsBottomBorder];

  self.bottomBorder = [self borderView];

  UIStackView *contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.tombstoneView, self.headerRow, self.bodyLabel, self.mediaView, self.externalCardView, self.articleNotificationButton, self.quotedPostView, self.footerLabel, self.metricsContainer, self.actionsContainer]];
  contentStack.translatesAutoresizingMaskIntoConstraints = NO;
  contentStack.axis = UILayoutConstraintAxisVertical;
  contentStack.alignment = UIStackViewAlignmentFill;
  contentStack.spacing = 12.0;
  [contentStack setCustomSpacing:14.0 afterView:self.bodyLabel];
  [contentStack setCustomSpacing:12.0 afterView:self.footerLabel];
  [contentStack setCustomSpacing:0.0 afterView:self.metricsContainer];
  [contentStack setCustomSpacing:0.0 afterView:self.actionsContainer];

  [self.contentView addSubview:self.threadConnectorTopView];
  [self.contentView addSubview:self.threadConnectorBottomView];
  [self.contentView addSubview:contentStack];
  [self.contentView addSubview:self.bottomBorder];

  self.mediaHeightConstraint = [self.mediaView.heightAnchor constraintEqualToAnchor:self.mediaView.widthAnchor multiplier:9.0 / 16.0];
  self.mediaHeightConstraint.priority = UILayoutPriorityDefaultHigh;
  self.externalCardHeightConstraint = [self.externalCardView.heightAnchor constraintEqualToConstant:0.0];
  self.externalCardHeightConstraint.priority = UILayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[
    [contentStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
    [contentStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
    [contentStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
    [contentStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.threadConnectorTopView.centerXAnchor constraintEqualToAnchor:self.avatarView.centerXAnchor],
    [self.threadConnectorTopView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
    [self.threadConnectorTopView.bottomAnchor constraintEqualToAnchor:self.avatarView.topAnchor constant:-NFBTweetDetailThreadRailAvatarGap],
    [self.threadConnectorTopView.widthAnchor constraintEqualToConstant:NFBTweetDetailThreadRailWidth],
    [self.threadConnectorBottomView.centerXAnchor constraintEqualToAnchor:self.avatarView.centerXAnchor],
    [self.threadConnectorBottomView.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:NFBTweetDetailThreadRailAvatarGap],
    [self.threadConnectorBottomView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.threadConnectorBottomView.widthAnchor constraintEqualToConstant:NFBTweetDetailThreadRailWidth],
    [self.avatarView.widthAnchor constraintEqualToConstant:48.0],
    [self.avatarView.heightAnchor constraintEqualToConstant:48.0],
    [self.verifiedBadgeView.widthAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricVerifiedBadgeSize)],
    [self.verifiedBadgeView.heightAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricVerifiedBadgeSize)],
    [nameRow.widthAnchor constraintLessThanOrEqualToAnchor:authorStack.widthAnchor],
    [handleRow.widthAnchor constraintLessThanOrEqualToAnchor:authorStack.widthAnchor],
    [self.followsYouLabel.heightAnchor constraintEqualToConstant:18.0],
    [self.followsYouLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70.0],
    [self.moreButton.widthAnchor constraintEqualToConstant:30.0],
    [self.moreButton.heightAnchor constraintEqualToConstant:30.0],
    [self.followButton.widthAnchor constraintGreaterThanOrEqualToConstant:76.0],
    [self.followButton.heightAnchor constraintEqualToConstant:34.0],
    self.mediaHeightConstraint,
    self.externalCardHeightConstraint,
    [self.articleNotificationButton.heightAnchor constraintEqualToConstant:42.0],
    [metricsTopBorder.topAnchor constraintEqualToAnchor:self.metricsContainer.topAnchor],
    [metricsTopBorder.leadingAnchor constraintEqualToAnchor:self.metricsContainer.leadingAnchor],
    [metricsTopBorder.trailingAnchor constraintEqualToAnchor:self.metricsContainer.trailingAnchor],
    [metricsTopBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [metricsBottomBorder.bottomAnchor constraintEqualToAnchor:self.metricsContainer.bottomAnchor],
    [metricsBottomBorder.leadingAnchor constraintEqualToAnchor:self.metricsContainer.leadingAnchor],
    [metricsBottomBorder.trailingAnchor constraintEqualToAnchor:self.metricsContainer.trailingAnchor],
    [metricsBottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.metricsStack.topAnchor constraintEqualToAnchor:self.metricsContainer.topAnchor constant:14.0],
    [self.metricsStack.leadingAnchor constraintEqualToAnchor:self.metricsContainer.leadingAnchor],
    [self.metricsStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.metricsContainer.trailingAnchor],
    [self.metricsStack.bottomAnchor constraintEqualToAnchor:self.metricsContainer.bottomAnchor constant:-14.0],
    [self.actionsContainer.heightAnchor constraintEqualToConstant:48.0],
    [self.actionsRow.topAnchor constraintEqualToAnchor:self.actionsContainer.topAnchor],
    [self.actionsRow.leadingAnchor constraintEqualToAnchor:self.actionsContainer.leadingAnchor],
    [self.actionsRow.trailingAnchor constraintEqualToAnchor:self.actionsContainer.trailingAnchor],
    [self.actionsRow.bottomAnchor constraintEqualToAnchor:self.actionsContainer.bottomAnchor],
    [self.actionsBottomBorder.leadingAnchor constraintEqualToAnchor:self.actionsContainer.leadingAnchor],
    [self.actionsBottomBorder.trailingAnchor constraintEqualToAnchor:self.actionsContainer.trailingAnchor],
    [self.actionsBottomBorder.bottomAnchor constraintEqualToAnchor:self.actionsContainer.bottomAnchor],
    [self.actionsBottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.bottomBorder.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
    [self.bottomBorder.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
    [self.bottomBorder.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
}

- (UILabel *)metricLabel {
  UILabel *label = [[UILabel alloc] init];
  label.font = NFBFont(15.0, NFBFontWeightRegular);
  label.textColor = NFBColorSecondaryText();
  label.numberOfLines = 1;
  return label;
}

- (void)makeMetricLabel:(UILabel *)label type:(NSString *)type {
  label.userInteractionEnabled = YES;
  label.accessibilityIdentifier = type;
  [label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(metricTapped:)]];
}

- (void)metricTapped:(UITapGestureRecognizer *)recognizer {
  NSString *type = recognizer.view.accessibilityIdentifier ?: @"";
  if (type.length == 0) return;
  [self.delegate tweetDetailFocalCell:self didTapMetricType:type];
}

- (UIView *)borderView {
  UIView *view = [[UIView alloc] init];
  view.translatesAutoresizingMaskIntoConstraints = NO;
  view.backgroundColor = NFBColorBorder();
  return view;
}

- (UIView *)actionButtonWithIcon:(NSString *)iconName selector:(SEL)selector {
  UIControl *control = [[UIControl alloc] init];
  control.translatesAutoresizingMaskIntoConstraints = NO;
  control.userInteractionEnabled = YES;
  [control addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];

  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.userInteractionEnabled = NO;
  icon.contentMode = UIViewContentModeScaleAspectFit;
  icon.tintColor = NFBColorSecondaryText();
  [control addSubview:icon];
  [NSLayoutConstraint activateConstraints:@[
    [icon.centerXAnchor constraintEqualToAnchor:control.centerXAnchor],
    [icon.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
    [icon.widthAnchor constraintEqualToConstant:NFBTweetDetailActionIconSize],
    [icon.heightAnchor constraintEqualToConstant:NFBTweetDetailActionIconSize],
    [control.widthAnchor constraintEqualToConstant:NFBTweetDetailActionButtonWidth],
    [control.heightAnchor constraintGreaterThanOrEqualToConstant:NFBTweetDetailActionButtonWidth]
  ]];
  return control;
}

- (UIImageView *)iconViewInActionButton:(UIView *)button {
  for (UIView *subview in button.subviews) {
    if ([subview isKindOfClass:UIImageView.class]) return (UIImageView *)subview;
  }
  return nil;
}

- (void)replyTapped {
  if (self.tombstoned) return;
  [NFBPostActionCoordinator animateActionView:self.replyIconView kind:NFBPostActionKindReply activating:YES];
  [self.delegate tweetDetailFocalCellDidTapReply:self];
}

- (void)repostTapped {
  if (self.tombstoned) return;
  NSDictionary *viewer = [self.post[@"viewer"] isKindOfClass:NSDictionary.class] ? self.post[@"viewer"] : @{};
  BOOL reposted = [viewer[@"repost"] isKindOfClass:NSString.class] && [viewer[@"repost"] length] > 0;
  [NFBPostActionCoordinator animateActionView:self.repostIconView kind:NFBPostActionKindRepost activating:!reposted];
  [self.delegate tweetDetailFocalCellDidTapRepost:self];
}

- (void)likeTapped {
  if (self.tombstoned) return;
  NSDictionary *viewer = [self.post[@"viewer"] isKindOfClass:NSDictionary.class] ? self.post[@"viewer"] : @{};
  BOOL liked = [viewer[@"like"] isKindOfClass:NSString.class] && [viewer[@"like"] length] > 0;
  [NFBPostActionCoordinator animateActionView:self.likeIconView kind:NFBPostActionKindLike activating:!liked];
  [self.delegate tweetDetailFocalCellDidTapLike:self];
}

- (void)bookmarkTapped {
  if (self.tombstoned) return;
  NSDictionary *viewer = [self.post[@"viewer"] isKindOfClass:NSDictionary.class] ? self.post[@"viewer"] : @{};
  BOOL bookmarked = [viewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && [viewer[@"bookmarked"] boolValue];
  [NFBPostActionCoordinator animateActionView:self.bookmarkIconView kind:NFBPostActionKindBookmark activating:!bookmarked];
  [self.delegate tweetDetailFocalCellDidTapBookmark:self];
}

- (void)shareTapped {
  if (self.tombstoned) return;
  [NFBPostActionCoordinator animateActionView:self.shareIconView kind:NFBPostActionKindShare activating:YES];
  [self.delegate tweetDetailFocalCellDidTapShare:self];
}

- (void)moreTapped {
  if (self.tombstoned) return;
  if (@available(iOS 14.0, *)) {
    if (self.moreButton.menu != nil) return;
  }
  [self.delegate tweetDetailFocalCellDidTapMore:self];
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
  if (self.tombstoned || gesture.state != UIGestureRecognizerStateBegan) return;
  if (@available(iOS 14.0, *)) {
    if (self.moreButton.menu != nil) return;
  }
  [self.delegate tweetDetailFocalCellDidLongPress:self];
}

- (void)followTapped {
  if (self.tombstoned) return;
  [self.delegate tweetDetailFocalCellDidTapFollow:self];
}

- (void)articleNotificationsTapped {
  if (self.tombstoned) return;
  [self.delegate tweetDetailFocalCellDidTapArticleNotifications:self];
}

- (void)authorTapped {
  if (self.tombstoned) return;
  [self.delegate tweetDetailFocalCellDidTapAuthor:self];
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.nameLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.handleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.followButton.titleLabel.font = NFBFont(14.0, NFBFontWeightHeavy);
  self.bodyLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricDetailBodyFontSize), NFBFontWeightRegular);
  self.articleNotificationButton.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.footerLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricDetailFooterFontSize), NFBFontWeightRegular);
  self.nameLabel.textColor = NFBColorText();
  self.handleLabel.textColor = NFBColorSecondaryText();
  NFBIPAApplyFollowsYouBadgeAppearance(self.followsYouLabel);
  self.bodyLabel.textColor = NFBColorText();
  if (self.post) self.bodyLabel.attributedText = [self bodyAttributedStringForPost:self.post];
  NFBApplyFramedTombstoneAppearance(self.tombstoneView, self.tombstoneTitleLabel, self.tombstoneSubtitleLabel, 15.0, 15.0);
  self.footerLabel.textColor = NFBColorSecondaryText();
  self.threadConnectorTopView.backgroundColor = NFBIPAThreadRailColor();
  self.threadConnectorBottomView.backgroundColor = NFBIPAThreadRailColor();
  [self.articleNotificationButton setTitleColor:NFBColorText() forState:UIControlStateNormal];
  self.articleNotificationButton.tintColor = NFBColorText();
  [self.mediaView applyTheme];
  [self.externalCardView applyTheme];
  [self.quotedPostView applyTheme];
  self.moreButton.tintColor = NFBColorSecondaryText();
  for (UIView *subview in self.metricsContainer.subviews) {
    if ([subview isKindOfClass:UIView.class] && ![subview isKindOfClass:UIStackView.class]) subview.backgroundColor = NFBColorBorder();
  }
  for (UIView *subview in self.actionsContainer.subviews) {
    if ([subview isKindOfClass:UIView.class] && ![subview isKindOfClass:UIStackView.class]) subview.backgroundColor = NFBColorBorder();
  }
  NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);
  [self applySecondaryTintInView:self.actionsRow];
}

- (void)setThreadConnectorAbove:(BOOL)above below:(BOOL)below {
  self.threadConnectorTopView.hidden = !above;
  self.threadConnectorBottomView.hidden = !below;
  self.actionsBottomBorder.hidden = below;
  self.bottomBorder.hidden = below;
}

- (void)setMoreMenu:(UIMenu *)menu {
  if (@available(iOS 14.0, *)) {
    [self.moreButton removeTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
    self.moreButton.menu = menu;
    self.moreButton.showsMenuAsPrimaryAction = menu != nil;
    if (menu == nil) {
      [self.moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
    }
  }
}

- (void)applySecondaryTintInView:(UIView *)view {
  if ([view isKindOfClass:UIImageView.class]) {
    ((UIImageView *)view).tintColor = NFBColorSecondaryText();
  } else if ([view isKindOfClass:UILabel.class]) {
    ((UILabel *)view).textColor = NFBColorSecondaryText();
  }
  for (UIView *subview in view.subviews) {
    [self applySecondaryTintInView:subview];
  }
}

- (void)configureWithPost:(NSDictionary *)post {
  self.post = post ?: @{};
  [self applyTheme];
  self.tombstoned = NO;

  NSDictionary *tombstone = NFBModerationTombstoneForFeedItem(self.post, self.post);
  if (tombstone.count > 0) {
    [self configureTombstone:tombstone];
    return;
  }
  self.tombstoneView.hidden = YES;
  self.headerRow.hidden = NO;
  self.bodyLabel.hidden = NO;
  self.footerLabel.hidden = NO;
  self.actionsContainer.hidden = NO;

  NSDictionary *author = [self.post[@"author"] isKindOfClass:NSDictionary.class] ? self.post[@"author"] : @{};
  self.nameLabel.text = [NFBAtprotoClient displayNameForProfile:author];
  self.handleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:author]];
  self.followsYouLabel.hidden = !NFBIPAProfileFollowsViewer(author);
  self.verifiedBadgeView.hidden = ![NFBAtprotoClient isProfileVerified:author];
  [NFBPostActionCoordinator configureFollowButton:self.followButton profile:author overDarkBackground:NO];
  self.bodyLabel.attributedText = [self bodyAttributedStringForPost:self.post];
  self.footerLabel.text = [self footerTextForPost:self.post];

  NSNumber *repostCount = [self numberFromPostKey:@"repostCount"];
  NSNumber *quoteCount = [self numberFromPostKey:@"quoteCount"];
  NSNumber *likeCount = [self numberFromPostKey:@"likeCount"];
  NSNumber *viewCount = [self numberFromPostKey:@"viewCount"];
  BOOL hideViewCount = NFBNeoFreeBirdHideViewCount();
  BOOL hasReposts = repostCount.integerValue > 0;
  BOOL hasQuotes = quoteCount.integerValue > 0;
  BOOL hasLikes = likeCount.integerValue > 0;
  BOOL hasViews = !hideViewCount && viewCount.integerValue > 0;
  self.repostMetricLabel.hidden = !hasReposts;
  self.quoteMetricLabel.hidden = !hasQuotes;
  self.likeMetricLabel.hidden = !hasLikes;
  self.viewMetricLabel.hidden = !hasViews;
  self.repostMetricLabel.attributedText = [self metricTextWithCount:repostCount label:repostCount.integerValue == 1 ? @"Retweet" : @"Retweets"];
  self.quoteMetricLabel.attributedText = [self metricTextWithCount:quoteCount label:quoteCount.integerValue == 1 ? @"Quote Tweet" : @"Quote Tweets"];
  self.likeMetricLabel.attributedText = [self metricTextWithCount:likeCount label:likeCount.integerValue == 1 ? @"Like" : @"Likes"];
  self.viewMetricLabel.attributedText = [self metricTextWithCount:viewCount label:viewCount.integerValue == 1 ? @"View" : @"Views"];
  self.metricsContainer.hidden = !(hasReposts || hasQuotes || hasLikes || hasViews);

  NSDictionary *viewer = [self.post[@"viewer"] isKindOfClass:NSDictionary.class] ? self.post[@"viewer"] : @{};
  BOOL liked = [viewer[@"like"] isKindOfClass:NSString.class] && [viewer[@"like"] length] > 0;
  BOOL reposted = [viewer[@"repost"] isKindOfClass:NSString.class] && [viewer[@"repost"] length] > 0;
  BOOL bookmarked = [viewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && [viewer[@"bookmarked"] boolValue];
  self.likeIconView.image = NFBTemplateIcon(liked ? @"nfb_like_filled" : @"nfb_like");
  self.likeIconView.tintColor = liked ? [UIColor colorWithRed:0.976 green:0.094 blue:0.502 alpha:1.0] : NFBColorSecondaryText();
  self.repostIconView.tintColor = reposted ? [UIColor colorWithRed:0.0 green:0.729 blue:0.486 alpha:1.0] : NFBColorSecondaryText();
  self.bookmarkIconView.image = NFBTemplateIcon(bookmarked ? @"nfb_bookmark_filled" : @"nfb_bookmark");
  self.bookmarkIconView.tintColor = bookmarked ? NFBColorAccent() : NFBColorSecondaryText();

  [self loadImageURL:[NFBAtprotoClient avatarURLForProfile:author] intoImageView:self.avatarView avatar:YES];
  NSArray<NSDictionary *> *mediaItems = NFBModerationMediaItemsByApplyingWarnings([NFBAtprotoClient mediaItemsForPost:self.post], self.post);
  self.mediaItems = mediaItems;
  if (mediaItems.count > 0) {
    self.mediaView.hidden = NO;
    [self.mediaView configureWithMediaItems:mediaItems];
  } else {
    [self.mediaView configureWithMediaItems:@[]];
    self.mediaView.hidden = YES;
  }

  NSDictionary *externalCard = [NFBAtprotoClient externalCardForPost:self.post];
  self.externalCard = externalCard;
  if (externalCard.count > 0) {
    self.externalCardView.hidden = NO;
    [self.externalCardView configureWithCard:externalCard compact:NO fullArticleReader:YES];
    BOOL isStandardSiteArticle = [NFBAtprotoClient externalCardIsStandardSiteArticle:externalCard];
    NSString *authorDID = [author[@"did"] isKindOfClass:NSString.class] ? author[@"did"] : @"";
    BOOL isOwnPost = authorDID.length > 0 && [authorDID isEqualToString:[NFBAtprotoSession sharedSession].did ?: @""];
    self.articleNotificationButton.hidden = !isStandardSiteArticle || isOwnPost;
    if (!self.articleNotificationButton.hidden) [self updateArticleNotificationButtonForAuthor:author];
    [self updateExternalCardHeight];
  } else {
    [self.externalCardView configureWithCard:nil];
    self.externalCardView.hidden = YES;
    self.externalCardHeightConstraint.constant = 0.0;
    self.articleNotificationButton.hidden = YES;
  }

  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:self.post];
  self.quotedPost = quotedPost;
  if (quotedPost.count > 0) {
    self.quotedPostView.hidden = NO;
    [self.quotedPostView configureWithPost:quotedPost];
  } else {
    [self.quotedPostView configureWithPost:nil];
    self.quotedPostView.hidden = YES;
  }
}

- (void)configureTombstone:(NSDictionary *)tombstone {
  self.tombstoned = YES;
  self.headerRow.hidden = YES;
  self.bodyLabel.hidden = YES;
  self.mediaView.hidden = YES;
  self.externalCardView.hidden = YES;
  self.articleNotificationButton.hidden = YES;
  self.quotedPostView.hidden = YES;
  self.footerLabel.hidden = YES;
  self.metricsContainer.hidden = YES;
  self.actionsContainer.hidden = YES;
  self.tombstoneView.hidden = NO;
  self.tombstoneTitleLabel.attributedText = NFBModerationTombstoneAttributedString(tombstone, self.tombstoneTitleLabel.font);
  self.tombstoneSubtitleLabel.text = @"";
  self.tombstoneSubtitleLabel.attributedText = nil;
  self.tombstoneSubtitleLabel.hidden = YES;
  self.tombstoneSubtitleBottomConstraint.active = NO;
  self.tombstoneTitleOnlyBottomConstraint.active = YES;
  [self.mediaView configureWithMediaItems:@[]];
  [self.externalCardView configureWithCard:nil];
  [self.quotedPostView configureWithPost:nil];
  self.mediaItems = @[];
  self.externalCard = nil;
  self.quotedPost = nil;
}

- (void)updateArticleNotificationButtonForAuthor:(NSDictionary *)author {
  NSArray<NSString *> *categories = [NFBNotificationCoordinator activityNotificationCategoriesForProfile:author ?: @{}];
  BOOL enabled = [NFBNotificationCoordinator activityNotificationCategories:categories includeCategory:NFBActivityNotificationCategoryArticles];
  NSDictionary *viewer = [author[@"viewer"] isKindOfClass:NSDictionary.class] ? author[@"viewer"] : @{};
  BOOL following = [viewer[@"following"] isKindOfClass:NSString.class] && [viewer[@"following"] length] > 0;
  NSString *handle = [NFBAtprotoClient handleForProfile:author ?: @{}];
  NSString *title = following ? @"Notify me of articles" : @"Follow & Notify me about articles";
  if (handle.length > 0) {
    if (enabled) {
      title = [NSString stringWithFormat:@"Article notifications on for @%@", handle];
    } else if (following) {
      title = [NSString stringWithFormat:@"Notify me of articles from @%@", handle];
    } else {
      title = [NSString stringWithFormat:@"Follow & Notify me about articles from @%@", handle];
    }
  } else if (enabled) {
    title = @"Article notifications are on";
  }
  [self.articleNotificationButton setTitle:title forState:UIControlStateNormal];
  [self.articleNotificationButton setImage:NFBTemplateIcon(enabled ? @"nfb_notifications_filled" : @"nfb_notifications") forState:UIControlStateNormal];
  self.articleNotificationButton.tintColor = enabled ? NFBColorAccent() : NFBColorText();
  [self.articleNotificationButton setTitleColor:enabled ? NFBColorAccent() : NFBColorText() forState:UIControlStateNormal];
}

- (CGFloat)externalCardAvailableWidth {
  CGFloat width = CGRectGetWidth(self.externalCardView.bounds);
  if (width <= 0.0) width = CGRectGetWidth(self.contentView.bounds) - 32.0;
  if (width <= 0.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds) - 32.0;
  return MAX(1.0, width);
}

- (void)updateExternalCardHeight {
  if (self.externalCardView.hidden || self.externalCard.count == 0) {
    self.externalCardHeightConstraint.constant = 0.0;
    return;
  }
  self.externalCardHeightConstraint.constant = [self.externalCardView preferredHeightForWidth:[self externalCardAvailableWidth]];
}

- (UITableView *)enclosingTableView {
  UIView *view = self.superview;
  while (view) {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    view = view.superview;
  }
  return nil;
}

- (NSNumber *)numberFromPostKey:(NSString *)key {
  id value = self.post[key];
  return [value respondsToSelector:@selector(stringValue)] ? value : @0;
}

- (NSAttributedString *)bodyAttributedStringForPost:(NSDictionary *)post {
  return NFBTweetBodyAttributedStringForPost(post, self.bodyLabel.font);
}

- (NSAttributedString *)metricTextWithCount:(NSNumber *)count label:(NSString *)label {
  NSString *countText = NFBShortCountString(count.integerValue);
  NSString *text = [NSString stringWithFormat:@"%@ %@", countText, label];
  NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
    NSFontAttributeName: NFBFont(15.0, NFBFontWeightRegular),
    NSForegroundColorAttributeName: NFBColorSecondaryText()
  }];
  [attributed addAttributes:@{
    NSFontAttributeName: NFBFont(15.0, NFBFontWeightBold),
    NSForegroundColorAttributeName: NFBColorText()
  } range:NSMakeRange(0, countText.length)];
  return attributed;
}

- (NSString *)footerTextForPost:(NSDictionary *)post {
  NSDate *date = [self.class dateForPost:post];
  if (!date) return @"now · Bluesky";
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.dateFormat = @"h:mm a · MMM d, yyyy";
  return [[formatter stringFromDate:date] stringByAppendingString:@" · Bluesky"];
}

+ (NSDate *)dateForPost:(NSDictionary *)post {
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  NSString *dateString = [record[@"createdAt"] isKindOfClass:NSString.class] ? record[@"createdAt"] : nil;
  if (dateString.length == 0) dateString = [post[@"indexedAt"] isKindOfClass:NSString.class] ? post[@"indexedAt"] : nil;
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

- (void)loadImageURL:(NSString *)urlString intoImageView:(UIImageView *)imageView avatar:(BOOL)avatar {
  if (urlString.length == 0) {
    imageView.image = avatar ? [self.class placeholderAvatarImage] : nil;
    return;
  }
  if (avatar) self.avatarURLString = urlString;

  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    imageView.image = cached;
    return;
  }
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    [[self.class imageCache] setObject:image forKey:urlString];
    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *current = self.avatarURLString;
      if ([current isEqualToString:urlString]) imageView.image = image;
    });
  }];
  [task resume];
}

- (void)mediaPreviewView:(NFBMediaPreviewView *)view didSelectItemAtIndex:(NSUInteger)index {
  (void)view;
  [self.delegate tweetDetailFocalCell:self didTapMediaAtIndex:index];
}

- (void)externalCardViewDidTapCard:(NFBExternalCardView *)view {
  (void)view;
  [self.delegate tweetDetailFocalCellDidTapExternalCard:self];
}

- (void)externalCardViewDidTapReadOnWebsite:(NFBExternalCardView *)view {
  (void)view;
  [self.delegate tweetDetailFocalCellDidTapExternalCardWebsite:self];
}

- (void)externalCardViewDidUpdateContent:(NFBExternalCardView *)view {
  (void)view;
  [self updateExternalCardHeight];
  UITableView *tableView = [self enclosingTableView];
  [tableView beginUpdates];
  [tableView endUpdates];
}

- (void)quotedPostViewDidTapPost:(NFBQuotedPostView *)view {
  (void)view;
  [self.delegate tweetDetailFocalCellDidTapQuotedPost:self];
}

- (void)quotedPostView:(NFBQuotedPostView *)view didTapLinkURL:(NSURL *)url {
  (void)view;
  [self.delegate tweetDetailFocalCell:self didTapLinkURL:url];
}

- (void)quotedPostView:(NFBQuotedPostView *)view didTapMediaAtIndex:(NSUInteger)index {
  (void)view;
  [self.delegate tweetDetailFocalCell:self didTapQuotedMediaAtIndex:index];
}

- (void)quotedPostViewDidTapExternalCard:(NFBQuotedPostView *)view {
  (void)view;
  [self.delegate tweetDetailFocalCellDidTapQuotedExternalCard:self];
}

- (void)quotedPostViewDidTapExternalCardWebsite:(NFBQuotedPostView *)view {
  (void)view;
  [self.delegate tweetDetailFocalCellDidTapQuotedExternalCardWebsite:self];
}

+ (NSCache *)imageCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 160;
  });
  return cache;
}

+ (UIImage *)placeholderAvatarImage {
  static UIImage *image = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    image = NFBDefaultAvatarImage() ?: NFBBrandIconImage();
  });
  return image;
}

@end

@interface NFBTweetDetailReaderCell : UITableViewCell <NFBMediaPreviewViewDelegate, NFBExternalCardViewDelegate, NFBQuotedPostViewDelegate>

@property (nonatomic, weak) id<NFBTweetDetailReaderCellDelegate> delegate;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *posts;

- (void)configureWithPosts:(NSArray<NSDictionary *> *)posts;
- (void)applyTheme;

@end

@interface NFBTweetDetailReaderCell ()

@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIStackView *authorStack;
@property (nonatomic, strong) UIStackView *sectionsStack;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UIImageView *verifiedBadgeView;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *posts;
@property (nonatomic, copy) NSString *avatarURLString;
@property (nonatomic, strong) NSMutableArray<NFBMediaPreviewView *> *mediaViews;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mediaViewPosts;
@property (nonatomic, strong) NSMutableArray<NFBExternalCardView *> *externalCardViews;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *externalCardViewPosts;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *externalCardHeightConstraints;
@property (nonatomic, strong) NSMutableArray<NFBQuotedPostView *> *quotedPostViews;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *quotedPostViewPosts;

@end

@implementation NFBTweetDetailReaderCell

static NSInteger const NFBTweetDetailReaderSeparatorTag = 93045;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    self.mediaViews = [NSMutableArray array];
    self.mediaViewPosts = [NSMutableArray array];
    self.externalCardViews = [NSMutableArray array];
    self.externalCardViewPosts = [NSMutableArray array];
    self.externalCardHeightConstraints = [NSMutableArray array];
    self.quotedPostViews = [NSMutableArray array];
    self.quotedPostViewPosts = [NSMutableArray array];
    [self buildSubviews];
  }
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.posts = @[];
  self.avatarURLString = nil;
  self.avatarView.image = [self.class placeholderAvatarImage];
  [self clearSections];
  [self applyTheme];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self updateExternalCardHeights];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

  self.avatarView = [[UIImageView alloc] initWithImage:[self.class placeholderAvatarImage]];
  self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarView.clipsToBounds = YES;
  self.avatarView.layer.cornerRadius = 24.0;
  self.avatarView.userInteractionEnabled = YES;
  [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)]];

  self.nameLabel = [[UILabel alloc] init];
  self.nameLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.nameLabel.numberOfLines = 1;
  self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.verifiedBadgeView = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
  self.verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
  self.verifiedBadgeView.contentMode = UIViewContentModeScaleAspectFit;

  UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.verifiedBadgeView]];
  nameRow.axis = UILayoutConstraintAxisHorizontal;
  nameRow.alignment = UIStackViewAlignmentCenter;
  nameRow.spacing = 3.0;

  self.handleLabel = [[UILabel alloc] init];
  self.handleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.handleLabel.numberOfLines = 1;
  self.handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.authorStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, self.handleLabel]];
  self.authorStack.axis = UILayoutConstraintAxisVertical;
  self.authorStack.alignment = UIStackViewAlignmentLeading;
  self.authorStack.spacing = 0.0;
  self.authorStack.userInteractionEnabled = YES;
  [self.authorStack addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)]];

  UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.avatarView, self.authorStack]];
  headerRow.axis = UILayoutConstraintAxisHorizontal;
  headerRow.alignment = UIStackViewAlignmentCenter;
  headerRow.spacing = 12.0;

  self.sectionsStack = [[UIStackView alloc] init];
  self.sectionsStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.sectionsStack.axis = UILayoutConstraintAxisVertical;
  self.sectionsStack.alignment = UIStackViewAlignmentFill;
  self.sectionsStack.spacing = 16.0;

  self.contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[headerRow, self.sectionsStack]];
  self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentStack.axis = UILayoutConstraintAxisVertical;
  self.contentStack.alignment = UIStackViewAlignmentFill;
  self.contentStack.spacing = 16.0;
  [self.contentView addSubview:self.contentStack];

  [NSLayoutConstraint activateConstraints:@[
    [self.contentStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16.0],
    [self.contentStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
    [self.contentStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
    [self.contentStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16.0],
    [self.avatarView.widthAnchor constraintEqualToConstant:48.0],
    [self.avatarView.heightAnchor constraintEqualToConstant:48.0],
    [self.verifiedBadgeView.widthAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricVerifiedBadgeSize)],
    [self.verifiedBadgeView.heightAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricVerifiedBadgeSize)]
  ]];
  [self applyTheme];
}

- (void)clearSections {
  for (UIView *view in self.sectionsStack.arrangedSubviews.copy) {
    [self.sectionsStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  [self.mediaViews removeAllObjects];
  [self.mediaViewPosts removeAllObjects];
  [self.externalCardViews removeAllObjects];
  [self.externalCardViewPosts removeAllObjects];
  [self.externalCardHeightConstraints removeAllObjects];
  [self.quotedPostViews removeAllObjects];
  [self.quotedPostViewPosts removeAllObjects];
}

- (void)configureWithPosts:(NSArray<NSDictionary *> *)posts {
  self.posts = posts ?: @[];
  [self clearSections];
  NSDictionary *firstPost = self.posts.firstObject ?: @{};
  NSDictionary *author = [firstPost[@"author"] isKindOfClass:NSDictionary.class] ? firstPost[@"author"] : @{};
  self.nameLabel.text = [NFBAtprotoClient displayNameForProfile:author];
  NSString *handle = [NFBAtprotoClient handleForProfile:author];
  self.handleLabel.text = handle.length > 0 ? [@"@" stringByAppendingString:handle] : @"";
  self.verifiedBadgeView.hidden = ![NFBAtprotoClient isProfileVerified:author];
  [self loadImageURL:[NFBAtprotoClient avatarURLForProfile:author] intoImageView:self.avatarView];

  [self.posts enumerateObjectsUsingBlock:^(NSDictionary *post, NSUInteger index, BOOL *stop) {
    (void)stop;
    UIView *section = [self sectionViewForPost:post showSeparator:index > 0];
    [self.sectionsStack addArrangedSubview:section];
  }];
  [self applyTheme];
}

- (UIView *)sectionViewForPost:(NSDictionary *)post showSeparator:(BOOL)showSeparator {
  UIStackView *section = [[UIStackView alloc] init];
  section.axis = UILayoutConstraintAxisVertical;
  section.alignment = UIStackViewAlignmentFill;
  section.spacing = 14.0;

  if (showSeparator) {
    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.tag = NFBTweetDetailReaderSeparatorTag;
    separator.backgroundColor = NFBColorBorder();
    [section addArrangedSubview:separator];
    [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    [section setCustomSpacing:16.0 afterView:separator];
  }

  NFBInteractiveTextLabel *bodyLabel = [[NFBInteractiveTextLabel alloc] init];
  bodyLabel.font = [self readerBodyFont];
  bodyLabel.numberOfLines = 0;
  bodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
  bodyLabel.attributedText = NFBTweetBodyAttributedStringForPost(post, bodyLabel.font);
  __weak typeof(self) weakSelf = self;
  bodyLabel.linkTapHandler = ^(NSURL *url) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf.delegate tweetDetailReaderCell:strongSelf didTapLinkURL:url];
  };
  if (bodyLabel.attributedText.length > 0) [section addArrangedSubview:bodyLabel];

  NSArray<NSDictionary *> *mediaItems = NFBModerationMediaItemsByApplyingWarnings([NFBAtprotoClient mediaItemsForPost:post], post);
  if (mediaItems.count > 0) {
    NFBMediaPreviewView *mediaView = [[NFBMediaPreviewView alloc] init];
    mediaView.delegate = self;
    [mediaView configureWithMediaItems:mediaItems];
    [self.mediaViews addObject:mediaView];
    [self.mediaViewPosts addObject:post ?: @{}];
    [section addArrangedSubview:mediaView];
    [mediaView.heightAnchor constraintEqualToAnchor:mediaView.widthAnchor multiplier:9.0 / 16.0].active = YES;
  }

  NSDictionary *externalCard = [NFBAtprotoClient externalCardForPost:post];
  if (externalCard.count > 0) {
    NFBExternalCardView *cardView = [[NFBExternalCardView alloc] init];
    cardView.delegate = self;
    [cardView configureWithCard:externalCard compact:NO fullArticleReader:NO];
    [self.externalCardViews addObject:cardView];
    [self.externalCardViewPosts addObject:post ?: @{}];
    NSLayoutConstraint *height = [cardView.heightAnchor constraintEqualToConstant:[self preferredExternalCardHeightForView:cardView]];
    height.priority = UILayoutPriorityDefaultHigh;
    height.active = YES;
    [self.externalCardHeightConstraints addObject:height];
    [section addArrangedSubview:cardView];
  }

  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post];
  if (quotedPost.count > 0) {
    NFBQuotedPostView *quotedView = [[NFBQuotedPostView alloc] init];
    quotedView.delegate = self;
    [quotedView configureWithPost:quotedPost];
    [self.quotedPostViews addObject:quotedView];
    [self.quotedPostViewPosts addObject:post ?: @{}];
    [section addArrangedSubview:quotedView];
  }

  return section;
}

- (UIFont *)readerBodyFont {
  return NFBFont(NFBIPAMetricValue(NFBIPAMetricDetailBodyFontSize), NFBFontWeightRegular);
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.nameLabel.textColor = NFBColorText();
  self.handleLabel.textColor = NFBColorSecondaryText();
  self.nameLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.handleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  for (UIView *view in self.sectionsStack.arrangedSubviews) [self applyThemeToReaderSubview:view];
}

- (void)applyThemeToReaderSubview:(UIView *)view {
  if ([view isKindOfClass:NFBInteractiveTextLabel.class]) {
    NFBInteractiveTextLabel *label = (NFBInteractiveTextLabel *)view;
    label.textColor = NFBColorText();
    label.font = [self readerBodyFont];
  } else if ([view isKindOfClass:NFBMediaPreviewView.class]) {
    [(NFBMediaPreviewView *)view applyTheme];
  } else if ([view isKindOfClass:NFBExternalCardView.class]) {
    [(NFBExternalCardView *)view applyTheme];
  } else if ([view isKindOfClass:NFBQuotedPostView.class]) {
    [(NFBQuotedPostView *)view applyTheme];
  } else if (view.tag == NFBTweetDetailReaderSeparatorTag) {
    view.backgroundColor = NFBColorBorder();
  }
  for (UIView *subview in view.subviews) [self applyThemeToReaderSubview:subview];
}

- (CGFloat)preferredExternalCardHeightForView:(NFBExternalCardView *)view {
  CGFloat width = CGRectGetWidth(view.bounds);
  if (width <= 0.0) width = CGRectGetWidth(self.contentView.bounds) - 32.0;
  if (width <= 0.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds) - 32.0;
  return [view preferredHeightForWidth:MAX(1.0, width)];
}

- (void)updateExternalCardHeights {
  for (NSUInteger index = 0; index < self.externalCardViews.count && index < self.externalCardHeightConstraints.count; index++) {
    NFBExternalCardView *view = self.externalCardViews[index];
    NSLayoutConstraint *height = self.externalCardHeightConstraints[index];
    height.constant = [self preferredExternalCardHeightForView:view];
  }
}

- (NSDictionary *)postForMediaView:(NFBMediaPreviewView *)view {
  NSUInteger index = [self.mediaViews indexOfObjectIdenticalTo:view];
  if (index == NSNotFound || index >= self.mediaViewPosts.count) return @{};
  return self.mediaViewPosts[index];
}

- (NSDictionary *)postForExternalCardView:(NFBExternalCardView *)view {
  NSUInteger index = [self.externalCardViews indexOfObjectIdenticalTo:view];
  if (index == NSNotFound || index >= self.externalCardViewPosts.count) return @{};
  return self.externalCardViewPosts[index];
}

- (NSDictionary *)postForQuotedPostView:(NFBQuotedPostView *)view {
  NSUInteger index = [self.quotedPostViews indexOfObjectIdenticalTo:view];
  if (index == NSNotFound || index >= self.quotedPostViewPosts.count) return @{};
  return self.quotedPostViewPosts[index];
}

- (void)authorTapped {
  NSDictionary *post = self.posts.firstObject ?: @{};
  [self.delegate tweetDetailReaderCell:self didTapAuthorForPost:post];
}

- (void)mediaPreviewView:(NFBMediaPreviewView *)view didSelectItemAtIndex:(NSUInteger)index {
  [self.delegate tweetDetailReaderCell:self didTapMediaAtIndex:index post:[self postForMediaView:view]];
}

- (void)externalCardViewDidTapCard:(NFBExternalCardView *)view {
  [self.delegate tweetDetailReaderCell:self didTapExternalCardForPost:[self postForExternalCardView:view]];
}

- (void)externalCardViewDidTapReadOnWebsite:(NFBExternalCardView *)view {
  [self.delegate tweetDetailReaderCell:self didTapExternalCardWebsiteForPost:[self postForExternalCardView:view]];
}

- (void)externalCardViewDidUpdateContent:(NFBExternalCardView *)view {
  (void)view;
  [self updateExternalCardHeights];
  UITableView *tableView = [self enclosingTableView];
  [tableView beginUpdates];
  [tableView endUpdates];
}

- (void)quotedPostViewDidTapPost:(NFBQuotedPostView *)view {
  [self.delegate tweetDetailReaderCell:self didTapQuotedPostForPost:[self postForQuotedPostView:view]];
}

- (void)quotedPostView:(NFBQuotedPostView *)view didTapLinkURL:(NSURL *)url {
  (void)view;
  [self.delegate tweetDetailReaderCell:self didTapLinkURL:url];
}

- (void)quotedPostView:(NFBQuotedPostView *)view didTapMediaAtIndex:(NSUInteger)index {
  [self.delegate tweetDetailReaderCell:self didTapQuotedMediaAtIndex:index post:[self postForQuotedPostView:view]];
}

- (void)quotedPostViewDidTapExternalCard:(NFBQuotedPostView *)view {
  [self.delegate tweetDetailReaderCell:self didTapQuotedExternalCardForPost:[self postForQuotedPostView:view]];
}

- (void)quotedPostViewDidTapExternalCardWebsite:(NFBQuotedPostView *)view {
  [self.delegate tweetDetailReaderCell:self didTapQuotedExternalCardWebsiteForPost:[self postForQuotedPostView:view]];
}

- (UITableView *)enclosingTableView {
  UIView *view = self.superview;
  while (view) {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    view = view.superview;
  }
  return nil;
}

- (void)loadImageURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
  self.avatarURLString = urlString ?: @"";
  if (urlString.length == 0) {
    imageView.image = [self.class placeholderAvatarImage];
    return;
  }
  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    imageView.image = cached;
    return;
  }
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    [[self.class imageCache] setObject:image forKey:urlString];
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.avatarURLString isEqualToString:urlString]) imageView.image = image;
    });
  }];
  [task resume];
}

+ (NSCache *)imageCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 160;
  });
  return cache;
}

+ (UIImage *)placeholderAvatarImage {
  return NFBDefaultAvatarImage() ?: NFBBrandIconImage();
}

@end

// Twitter 9.67 T1ConversationShowMoreCell: normal text + 23pt vertical
// padding, text aligned with Tweets, a three-dot continuation in the avatar rail.
@interface NFBThreadGapCell : UITableViewCell
@property (nonatomic, strong) UILabel *actionLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL connected;
@end
@implementation NFBThreadGapCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
  if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.actionLabel = [[UILabel alloc] init];
    self.actionLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    self.actionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.actionLabel];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [self.contentView addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
      [self.actionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:NFBIPAMetricValue(NFBIPAMetricTimelineHorizontalInset) + NFBIPAMetricValue(NFBIPAMetricTimelineAvatarSize) + NFBIPAMetricValue(NFBIPAMetricTimelineAvatarTextGap)],
      [self.actionLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
      [self.actionLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11.0],
      [self.actionLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0]]];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
  }
  return self;
}
- (void)layoutSubviews {
  [super layoutSubviews];
  self.spinner.center = CGPointMake(40.0, CGRectGetMidY(self.contentView.bounds));
  [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
  [super drawRect:rect];
  [NFBColorBorder() setFill];
  CGFloat middle = CGRectGetMidY(self.bounds);
  if (self.connected) [[UIBezierPath bezierPathWithRect:CGRectMake(39.0, 0, 2.0, MAX(0, middle - 11.0))] fill];
  if (!self.spinner.isAnimating) {
    for (NSInteger i = -1; i <= 1; i++) [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(38.5, middle + i * 6.0 - 1.5, 3.0, 3.0)] fill];
  }
}
@end

@interface NFBTweetDetailViewController () <UITableViewDataSource, UITableViewDelegate, NFBPostCellDelegate, NFBTweetDetailFocalCellDelegate, NFBTweetDetailReaderCellDelegate, NFBMediaViewerViewControllerDelegate>

@property (nonatomic, strong) NSDictionary *initialPost;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyLoadingView;
@property (nonatomic, strong) UIActivityIndicatorView *threadLoadingIndicator;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, strong) UIView *replyComposerBar;
@property (nonatomic, strong) UIView *replyComposerTopBorder;
@property (nonatomic, strong) UIControl *replyComposerInput;
@property (nonatomic, strong) UILabel *replyComposerPlaceholderLabel;
@property (nonatomic, strong) NSLayoutConstraint *replyComposerHeightConstraint;
@property (nonatomic, strong) UIButton *readerModeButton;
@property (nonatomic, strong) UIButton *readerExitButton;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) NFBThreadModel *threadModel;
@property (nonatomic, strong) NSMutableSet<NSString *> *loadingBranches;
@property (nonatomic, strong) NSMutableSet<NSString *> *failedBranches;
@property (nonatomic, assign) BOOL didLoadThread;
@property (nonatomic, assign) NSInteger focalIndex;
@property (nonatomic, assign) BOOL readerModeActive;
@property (nonatomic, strong) NFBPostActionCoordinator *postActionCoordinator;

@end

@implementation NFBTweetDetailViewController

- (instancetype)initWithPost:(NSDictionary *)post {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _initialPost = [post copy];
    _items = [NSMutableArray arrayWithObject:@{@"post": post ?: @{}}];
    _focalIndex = 0;
    _loadingBranches = [NSMutableSet set];
    _failedBranches = [NSMutableSet set];
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
      [weakSelf loadThread];
    };
    _postActionCoordinator.profileUpdateHandler = ^(NSDictionary *updatedProfile, NSDictionary *originalProfile) {
      [weakSelf applyUpdatedProfile:updatedProfile originalProfile:originalProfile];
    };
  }
  _postActionCoordinator.presentingViewController = self;
  return _postActionCoordinator;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBColorBackground();
  [self configureNavigation];
  [self configureTableView];
  [self loadThread];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureNavigation {
  self.navigationItem.titleView = NFBTitleView(@"Tweet", nil);
  if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
    self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
    self.navigationItem.hidesBackButton = YES;
  }
  self.readerModeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.readerModeButton.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
  self.readerModeButton.tintColor = NFBColorText();
  self.readerModeButton.accessibilityLabel = @"Reader Mode";
  [self.readerModeButton setImage:NFBTemplateIcon(@"nfb_lists") forState:UIControlStateNormal];
  [self.readerModeButton addTarget:self action:@selector(readerModeTapped) forControlEvents:UIControlEventTouchUpInside];
  [self updateReaderModeChrome];
}

- (void)backTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)configureTableView {
  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.estimatedRowHeight = 180.0;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  NFBIPAApplyTableViewAppearance(self.tableView);
  [self.tableView registerClass:NFBPostCell.class forCellReuseIdentifier:@"post"];
  [self.tableView registerClass:NFBThreadGapCell.class forCellReuseIdentifier:@"gap"];
  [self.tableView registerClass:NFBTweetDetailFocalCell.class forCellReuseIdentifier:@"focal"];
  [self.tableView registerClass:NFBTweetDetailReaderCell.class forCellReuseIdentifier:@"reader"];

  self.emptyStateView = [[UIView alloc] init];
  self.emptyStateView.backgroundColor = UIColor.clearColor;
  self.emptyLoadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
  self.emptyLoadingView.translatesAutoresizingMaskIntoConstraints = NO;
  self.emptyLoadingView.tintColor = NFBColorAccent();
  self.emptyLoadingView.contentMode = UIViewContentModeScaleAspectFit;
  self.emptyLoadingView.hidden = YES;
  self.emptyLabel = [[UILabel alloc] init];
  self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.emptyLabel.textColor = NFBColorSecondaryText();
  self.emptyLabel.font = NFBFont(17.0, NFBFontWeightRegular);
  self.emptyLabel.textAlignment = NSTextAlignmentCenter;
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

  [self.view addSubview:self.tableView];
  [self configureReplyComposerBar];
  [self configureReaderExitButton];
  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.replyComposerBar.topAnchor]
  ]];
}

- (void)configureReplyComposerBar {
  self.replyComposerBar = [[UIView alloc] init];
  self.replyComposerBar.translatesAutoresizingMaskIntoConstraints = NO;

  self.replyComposerTopBorder = [[UIView alloc] init];
  self.replyComposerTopBorder.translatesAutoresizingMaskIntoConstraints = NO;

  self.replyComposerInput = [[UIControl alloc] init];
  self.replyComposerInput.translatesAutoresizingMaskIntoConstraints = NO;
  self.replyComposerInput.layer.cornerRadius = 20.0;
  self.replyComposerInput.accessibilityLabel = @"Tweet your reply";
  [self.replyComposerInput addTarget:self action:@selector(inlineReplyTapped) forControlEvents:UIControlEventTouchUpInside];

  self.replyComposerPlaceholderLabel = [[UILabel alloc] init];
  self.replyComposerPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.replyComposerPlaceholderLabel.text = @"Tweet your reply";
  self.replyComposerPlaceholderLabel.font = NFBFont(17.0, NFBFontWeightRegular);
  self.replyComposerPlaceholderLabel.numberOfLines = 1;
  self.replyComposerPlaceholderLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  [self.replyComposerBar addSubview:self.replyComposerTopBorder];
  [self.replyComposerBar addSubview:self.replyComposerInput];
  [self.replyComposerInput addSubview:self.replyComposerPlaceholderLabel];
  [self.view addSubview:self.replyComposerBar];

  self.replyComposerHeightConstraint = [self.replyComposerBar.heightAnchor constraintEqualToConstant:56.0];

  [NSLayoutConstraint activateConstraints:@[
    [self.replyComposerBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.replyComposerBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.replyComposerBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    self.replyComposerHeightConstraint,
    [self.replyComposerTopBorder.topAnchor constraintEqualToAnchor:self.replyComposerBar.topAnchor],
    [self.replyComposerTopBorder.leadingAnchor constraintEqualToAnchor:self.replyComposerBar.leadingAnchor],
    [self.replyComposerTopBorder.trailingAnchor constraintEqualToAnchor:self.replyComposerBar.trailingAnchor],
    [self.replyComposerTopBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.replyComposerInput.leadingAnchor constraintEqualToAnchor:self.replyComposerBar.leadingAnchor constant:14.0],
    [self.replyComposerInput.trailingAnchor constraintEqualToAnchor:self.replyComposerBar.trailingAnchor constant:-14.0],
    [self.replyComposerInput.centerYAnchor constraintEqualToAnchor:self.replyComposerBar.centerYAnchor constant:1.0],
    [self.replyComposerInput.heightAnchor constraintEqualToConstant:40.0],
    [self.replyComposerPlaceholderLabel.leadingAnchor constraintEqualToAnchor:self.replyComposerInput.leadingAnchor constant:26.0],
    [self.replyComposerPlaceholderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.replyComposerInput.trailingAnchor constant:-20.0],
    [self.replyComposerPlaceholderLabel.centerYAnchor constraintEqualToAnchor:self.replyComposerInput.centerYAnchor]
  ]];

  [self applyReplyComposerBarTheme];
}

- (void)configureReaderExitButton {
  self.readerExitButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.readerExitButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.readerExitButton.hidden = YES;
  self.readerExitButton.layer.cornerRadius = 22.0;
  self.readerExitButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 18.0, 0.0, 18.0);
  self.readerExitButton.titleLabel.font = NFBFont(17.0, NFBFontWeightHeavy);
  [self.readerExitButton setTitle:@"×  Exit Reader" forState:UIControlStateNormal];
  [self.readerExitButton addTarget:self action:@selector(exitReaderButtonTapped) forControlEvents:UIControlEventTouchUpInside];
  self.readerExitButton.layer.shadowColor = UIColor.blackColor.CGColor;
  self.readerExitButton.layer.shadowOpacity = 0.28;
  self.readerExitButton.layer.shadowRadius = 12.0;
  self.readerExitButton.layer.shadowOffset = CGSizeMake(0.0, 3.0);
  [self.view addSubview:self.readerExitButton];
  [NSLayoutConstraint activateConstraints:@[
    [self.readerExitButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [self.readerExitButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18.0],
    [self.readerExitButton.heightAnchor constraintEqualToConstant:44.0],
    [self.readerExitButton.widthAnchor constraintGreaterThanOrEqualToConstant:176.0]
  ]];
  [self applyReaderExitButtonTheme];
}

- (void)exitReaderButtonTapped {
  if (!self.readerModeActive) return;
  self.readerModeActive = NO;
  [self updateReaderModeChrome];
  [self.tableView reloadData];
}

- (UIColor *)replyComposerInputBackgroundColor {
  NSString *mode = NFBCurrentDisplayMode();
  if ([mode isEqualToString:NFBDisplayModeLight]) return NFBColorElevatedBackground();
  if ([mode isEqualToString:NFBDisplayModeDim]) return NFBColorElevatedBackground();
  return [UIColor colorWithRed:0.126 green:0.141 blue:0.153 alpha:1.0];
}

- (void)applyReplyComposerBarTheme {
  self.replyComposerBar.backgroundColor = NFBColorBackground();
  self.replyComposerTopBorder.backgroundColor = NFBColorBorder();
  self.replyComposerInput.backgroundColor = [self replyComposerInputBackgroundColor];
  self.replyComposerPlaceholderLabel.textColor = NFBColorSecondaryText();
}

- (void)applyReaderExitButtonTheme {
  self.readerExitButton.backgroundColor = NFBColorElevatedBackground();
  [self.readerExitButton setTitleColor:NFBColorText() forState:UIControlStateNormal];
}

- (void)updateThreadFooter:(NSString *)message loading:(BOOL)loading {
  [self.threadLoadingIndicator stopAnimating];
  self.threadLoadingIndicator = nil;
  if (loading) {
    // Twitter 9.67 TFNActivityIndicatorCollectionViewCell: a 44pt row with
    // a centered medium system indicator; "Loading" is accessibility-only.
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 44.0)];
    footer.backgroundColor = UIColor.clearColor;
    footer.userInteractionEnabled = NO;
    footer.isAccessibilityElement = YES;
    footer.accessibilityLabel = @"Loading";
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.color = NFBColorSecondaryText();
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.isAccessibilityElement = NO;
    [footer addSubview:indicator];
    [NSLayoutConstraint activateConstraints:@[
      [indicator.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
      [indicator.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]
    ]];
    [indicator startAnimating];
    self.threadLoadingIndicator = indicator;
    self.tableView.tableFooterView = footer;
    return;
  }
  if (!message.length) { self.tableView.tableFooterView = nil; return; }
  UIButton *footer = [UIButton buttonWithType:UIButtonTypeSystem];
  footer.frame = CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 52.0);
  [footer setTitle:message forState:UIControlStateNormal];
  [footer setTitleColor:NFBColorAccent() forState:UIControlStateNormal];
  footer.titleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  [footer addTarget:self action:@selector(loadThread) forControlEvents:UIControlEventTouchUpInside];
  self.tableView.tableFooterView = footer;
}

- (void)loadThread {
  NSString *uri = [self.initialPost[@"uri"] isKindOfClass:NSString.class] ? self.initialPost[@"uri"] : @"";
  if (!uri.length || self.loading) return;
  if (self.didLoadThread) [[NFBAtprotoClient sharedClient] invalidatePostThreadForURI:uri];
  self.loading = YES;
  [self updateThreadFooter:@"" loading:YES];
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] fetchPostThreadForURI:uri completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) self = weakSelf;
      if (!self) return;
      self.loading = NO;
      if (error || !value) {
        [self updateThreadFooter:@"Couldn't load replies. Tap to retry." loading:NO];
        return;
      }
      BOOL initialLoad = !self.didLoadThread;
      self.didLoadThread = YES;
      self.threadModel = [[NFBThreadModel alloc] init];
      self.threadModel.anchorURI = uri;
      [self.threadModel mergeNodes:value[@"nodes"] ?: @[]];
      [self reloadThreadItemsPreservingPosition:!initialLoad];
      [self updateThreadFooter:@"" loading:NO];
      [self updateEmptyState:@""];
      if (initialLoad && self.focalIndex > 0 && !self.tableView.dragging && !self.tableView.decelerating) {
        [self.tableView layoutIfNeeded];
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.focalIndex inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
      }
    });
  }];
}

- (void)reloadThreadItemsPreservingPosition:(BOOL)preserve {
  NSIndexPath *top = self.tableView.indexPathsForVisibleRows.firstObject;
  NSString *visibleURI = top ? [self postURIAtThreadIndex:top.row] : @"";
  CGFloat relativeY = top ? CGRectGetMinY([self.tableView rectForRowAtIndexPath:top]) - self.tableView.contentOffset.y : 0;
  NSArray *items = [self.threadModel displayItems];
  if (!items.count) return;
  self.items = [items mutableCopy];
  self.focalIndex = 0;
  for (NSUInteger i = 0; i < items.count; i++) if ([items[i][@"_nfbThreadRole"] isEqual:@"focal"]) { self.focalIndex = i; break; }
  [self updateReaderModeChrome];
  [self.tableView reloadData];
  if (preserve && visibleURI.length && !self.readerModeActive) {
    [self.tableView layoutIfNeeded];
    for (NSUInteger i = 0; i < self.items.count; i++) {
      if ([self.items[i][@"_nfbThreadRole"] isEqual:@"gap"]) continue;
      if ([[self postURIAtThreadIndex:i] isEqual:visibleURI]) {
        CGFloat y = CGRectGetMinY([self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]]) - relativeY;
        self.tableView.contentOffset = CGPointMake(self.tableView.contentOffset.x, MAX(-self.tableView.adjustedContentInset.top, y));
        break;
      }
    }
  }
}

- (void)expandRepliesForItem:(NSDictionary *)item {
  NSString *uri = item[@"_nfbExpandURI"];
  if (!uri.length || [self.loadingBranches containsObject:uri] || self.loading) return;
  [self.loadingBranches addObject:uri];
  [self.failedBranches removeObject:uri];
  [self.tableView reloadData];
  NFBThreadModel *model = self.threadModel;
  NSUInteger previousCount = model.postCount;
  __weak typeof(self) weakSelf = self;
  BOOL additional = [item[@"_nfbAdditionalReplies"] boolValue];
  NFBAtprotoDictionaryCompletion completion = ^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) self = weakSelf;
      if (!self) return;
      [self.loadingBranches removeObject:uri];
      if (model != self.threadModel) return;
      if (error || !value) { [self.failedBranches addObject:uri]; [self.tableView reloadData]; return; }
      [model mergeNodes:value[@"nodes"] ?: @[]];
      if (additional) [model markAdditionalRepliesLoadedForURI:uri];
      if (model.postCount == previousCount) [model markRepliesExhaustedForURI:uri];
      [self reloadThreadItemsPreservingPosition:YES];
    });
  };
  if (additional) [[NFBAtprotoClient sharedClient] fetchAdditionalPostRepliesForURI:uri completion:completion];
  else [[NFBAtprotoClient sharedClient] fetchPostThreadForURI:uri completion:completion];
}

- (NSDictionary *)item:(NSDictionary *)item withThreadRole:(NSString *)role {
  NSMutableDictionary *mutable = [item isKindOfClass:NSDictionary.class] ? [item mutableCopy] : [NSMutableDictionary dictionary];
  if (role.length > 0) mutable[@"_nfbThreadRole"] = role;
  return [mutable copy];
}

- (NSString *)threadRoleAtIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)self.items.count) return @"";
  NSDictionary *item = self.items[(NSUInteger)index];
  return [item[@"_nfbThreadRole"] isKindOfClass:NSString.class] ? item[@"_nfbThreadRole"] : @"";
}

- (BOOL)threadIndexIsParent:(NSInteger)index {
  return [[self threadRoleAtIndex:index] isEqualToString:@"parent"];
}

- (BOOL)threadIndexIsAuthorContinuation:(NSInteger)index {
  return [[self threadRoleAtIndex:index] isEqualToString:@"threadReply"];
}

- (NSString *)authorDIDAtThreadIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)self.items.count) return @"";
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)index]];
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  NSString *did = [author[@"did"] isKindOfClass:NSString.class] ? author[@"did"] : @"";
  return did ?: @"";
}

- (NSString *)focalAuthorDID {
  return [self authorDIDAtThreadIndex:self.focalIndex];
}

- (BOOL)threadIndexHasFocalAuthor:(NSInteger)index {
  NSString *focalAuthorDID = [self focalAuthorDID];
  NSString *authorDID = [self authorDIDAtThreadIndex:index];
  return focalAuthorDID.length > 0 && authorDID.length > 0 && [authorDID isEqualToString:focalAuthorDID];
}

- (NSArray<NSNumber *> *)readerModeIndexes {
  NSMutableArray *indexes = [NSMutableArray arrayWithObject:@(self.focalIndex)];
  // Only the contiguous same-author chain containing the selected Tweet belongs
  // in Reader. An author's answer after another participant is a separate reply.
  for (NSInteger i = self.focalIndex - 1; i >= 0; i--) {
    if (![self threadIndexHasFocalAuthor:i] || [self.items[i][@"_nfbUnavailable"] boolValue] ||
        ![[self replyParentURIAtThreadIndex:i + 1] isEqual:[self postURIAtThreadIndex:i]]) break;
    [indexes insertObject:@(i) atIndex:0];
  }
  for (NSInteger i = self.focalIndex + 1; i < (NSInteger)self.items.count; i++) {
    if (![self threadIndexIsAuthorContinuation:i] || ![self threadIndexHasFocalAuthor:i] ||
        ![[self replyParentURIAtThreadIndex:i] isEqual:[self postURIAtThreadIndex:i - 1]]) break;
    [indexes addObject:@(i)];
  }
  return indexes;
}

- (NSArray<NSDictionary *> *)readerModePosts {
  NSMutableArray<NSDictionary *> *posts = [NSMutableArray array];
  for (NSNumber *indexNumber in [self readerModeIndexes]) {
    NSInteger index = indexNumber.integerValue;
    if (index < 0 || index >= (NSInteger)self.items.count) continue;
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)index]];
    if (post.count > 0) [posts addObject:post];
  }
  return posts;
}

- (BOOL)readerModeAvailable {
  if (!NFBThreadReaderModeEnabled()) return NO;
  return [self readerModeIndexes].count > 1;
}

- (NSInteger)itemIndexForVisibleRow:(NSInteger)row {
  if (!self.readerModeActive) return row;
  NSArray<NSNumber *> *indexes = [self readerModeIndexes];
  if (row < 0 || row >= (NSInteger)indexes.count) return NSNotFound;
  return indexes[(NSUInteger)row].integerValue;
}

- (void)readerModeTapped {
  if (![self readerModeAvailable]) return;
  self.readerModeActive = !self.readerModeActive;
  [self updateReaderModeChrome];
  [self.tableView reloadData];
}

- (void)updateReaderModeChrome {
  BOOL available = [self readerModeAvailable];
  if (!available) self.readerModeActive = NO;
  self.navigationItem.titleView = NFBTitleView(self.readerModeActive ? @"Thread" : @"Tweet", self.readerModeActive ? @"Reader Mode" : nil);
  self.readerModeButton.tintColor = self.readerModeActive ? NFBColorAccent() : NFBColorText();
  self.readerModeButton.accessibilityLabel = self.readerModeActive ? @"Exit Reader" : @"View thread in Reader";
  self.navigationItem.rightBarButtonItem = available ? [[UIBarButtonItem alloc] initWithCustomView:self.readerModeButton] : nil;
  self.replyComposerBar.hidden = self.readerModeActive;
  self.replyComposerHeightConstraint.constant = self.readerModeActive ? 0.0 : 56.0;
  self.readerExitButton.hidden = !self.readerModeActive;
  [self applyReaderExitButtonTheme];
}

- (NSString *)postURIAtThreadIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)self.items.count) return @"";
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)index]];
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  return uri ?: @"";
}

- (NSString *)replyParentURIAtThreadIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)self.items.count) return @"";
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)index]];
  return [NFBAtprotoClient replyParentURIForPost:post ?: @{}];
}

- (BOOL)threadIndexHasConnectorAbove:(NSInteger)index {
  return index >= 0 && index < (NSInteger)self.items.count && [self.items[index][@"_nfbConnectorAbove"] boolValue];
}
- (BOOL)threadIndexHasConnectorBelow:(NSInteger)index {
  return index >= 0 && index < (NSInteger)self.items.count && [self.items[index][@"_nfbConnectorBelow"] boolValue];
}
- (BOOL)threadIndexUsesCompactSeparator:(NSInteger)index {
  return [self threadIndexHasConnectorBelow:index];
}

- (void)updateEmptyState:(NSString *)message {
  BOOL loading = [message isEqualToString:@"Loading..."];
  self.emptyLoadingView.hidden = !loading;
  self.emptyLabel.text = loading ? @"" : message;
  self.emptyLabel.hidden = loading || message.length == 0;
  if (loading) NFBStartLoadingAnimation(self.emptyLoadingView);
  else NFBStopLoadingAnimation(self.emptyLoadingView);
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  self.view.backgroundColor = NFBColorBackground();
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.emptyLabel.textColor = NFBColorSecondaryText();
  self.emptyLoadingView.tintColor = NFBColorAccent();
  self.threadLoadingIndicator.color = NFBColorSecondaryText();
  [self applyReplyComposerBarTheme];
  [self applyReaderExitButtonTheme];
  NFBApplyNavigationAppearance(self.navigationController);
  [self updateReaderModeChrome];
  [self.tableView reloadData];
}

- (NSDictionary *)focalPost {
  if (self.focalIndex >= 0 && self.focalIndex < (NSInteger)self.items.count) {
    return [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)self.focalIndex]];
  }
  return self.initialPost ?: @{};
}

- (BOOL)ensureSessionForTweetAction {
  if ([[NFBAtprotoSession sharedSession] hasSession]) return YES;
  NFBPresentBlueskyLoginIfNeeded();
  return NO;
}

- (void)inlineReplyTapped {
  [[self postActionCoordinator] performReplyForPost:[self focalPost] sourceView:self.replyComposerInput];
}

- (void)presentReplyForPost:(NSDictionary *)post {
  if (![self ensureSessionForTweetAction]) return;
  NFBComposeViewController *compose = [[NFBComposeViewController alloc] initWithReplyToPost:post];
  compose.completionHandler = ^(BOOL posted) {
    if (posted) [self loadThread];
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
      if (posted) [strongSelf loadThread];
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
  if (updatedPost) [self.threadModel mergeNodes:@[@{@"post": updatedPost}]];
  NSString *targetURI = [originalPost[@"uri"] isKindOfClass:NSString.class] ? originalPost[@"uri"] : @"";
  if (targetURI.length == 0 || ![updatedPost isKindOfClass:NSDictionary.class]) return;
  NSString *initialURI = [self.initialPost[@"uri"] isKindOfClass:NSString.class] ? self.initialPost[@"uri"] : @"";
  if ([initialURI isEqualToString:targetURI]) self.initialPost = updatedPost;
  for (NSUInteger index = 0; index < self.items.count; index++) {
    NSDictionary *item = self.items[index];
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if (![uri isEqualToString:targetURI]) continue;
    self.items[index] = [self feedItem:item byReplacingPost:updatedPost];
    [self.threadModel mergeNodes:@[@{@"post": updatedPost}]];
  }
  [self.tableView reloadData];
}

- (NSDictionary *)post:(NSDictionary *)post byReplacingAuthorProfile:(NSDictionary *)profile {
  if (![post isKindOfClass:NSDictionary.class] || ![profile isKindOfClass:NSDictionary.class]) return post ?: @{};
  NSMutableDictionary *updatedPost = [post mutableCopy];
  updatedPost[@"author"] = profile;
  return updatedPost;
}

- (void)applyUpdatedProfile:(NSDictionary *)updatedProfile originalProfile:(NSDictionary *)originalProfile {
  NSString *targetDID = [originalProfile[@"did"] isKindOfClass:NSString.class] ? originalProfile[@"did"] : @"";
  if (targetDID.length == 0) targetDID = [updatedProfile[@"did"] isKindOfClass:NSString.class] ? updatedProfile[@"did"] : @"";
  if (targetDID.length == 0 || ![updatedProfile isKindOfClass:NSDictionary.class]) return;

  NSDictionary *initialAuthor = [self.initialPost[@"author"] isKindOfClass:NSDictionary.class] ? self.initialPost[@"author"] : @{};
  NSString *initialAuthorDID = [initialAuthor[@"did"] isKindOfClass:NSString.class] ? initialAuthor[@"did"] : @"";
  if ([initialAuthorDID isEqualToString:targetDID]) self.initialPost = [self post:self.initialPost byReplacingAuthorProfile:updatedProfile];

  for (NSUInteger index = 0; index < self.items.count; index++) {
    NSDictionary *item = self.items[index];
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
    NSString *authorDID = [author[@"did"] isKindOfClass:NSString.class] ? author[@"did"] : @"";
    if (![authorDID isEqualToString:targetDID]) continue;
    NSDictionary *updatedPost = [self post:post byReplacingAuthorProfile:updatedProfile];
    self.items[index] = [self feedItem:item byReplacingPost:updatedPost];
    [self.threadModel mergeNodes:@[@{@"post": updatedPost}]];
  }
  [self.tableView reloadData];
}

- (NSDictionary *)postForActionAtIndexPath:(NSIndexPath *)indexPath {
  NSInteger itemIndex = [self itemIndexForVisibleRow:indexPath.row];
  if (itemIndex == NSNotFound || itemIndex < 0 || itemIndex >= (NSInteger)self.items.count) return @{};
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)itemIndex]];
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
    NSDictionary *currentPost = [self focalPost];
    NSString *currentURI = [currentPost[@"uri"] isKindOfClass:NSString.class] ? currentPost[@"uri"] : @"";
    if (uri.length > 0 && ![uri isEqualToString:currentURI]) {
      NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
      [self.navigationController pushViewController:detail animated:YES];
      return;
    }
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

- (void)confirmDeletePost:(NSDictionary *)post {
  [[self postActionCoordinator] performDeleteForPost:post sourceView:nil];
}

- (void)removeDeletedPost:(NSDictionary *)post {
  NSString *targetURI = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  if (targetURI.length == 0) {
    [self loadThread];
    return;
  }
  NSString *focalURI = [[self focalPost][@"uri"] isKindOfClass:NSString.class] ? [self focalPost][@"uri"] : @"";
  if ([targetURI isEqualToString:focalURI]) {
    [self.navigationController popViewControllerAnimated:YES];
    return;
  }

  NSIndexSet *indexes = [self.items indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
    (void)idx;
    (void)stop;
    NSDictionary *candidate = [NFBAtprotoClient postFromFeedItem:item];
    NSString *uri = [candidate[@"uri"] isKindOfClass:NSString.class] ? candidate[@"uri"] : @"";
    return [uri isEqualToString:targetURI];
  }];
  if (indexes.count == 0) {
    [self loadThread];
    return;
  }
  [self.items removeObjectsAtIndexes:indexes];
  [self loadThread];
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
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  NSString *currentURI = [[self focalPost][@"uri"] isKindOfClass:NSString.class] ? [self focalPost][@"uri"] : @"";
  if (uri.length == 0 || [uri isEqualToString:currentURI]) return;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
  [self.navigationController pushViewController:detail animated:YES];
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

- (UIMenu *)contextMenuForPost:(NSDictionary *)post {
  return [[self postActionCoordinator] contextMenuForPost:post];
}

- (void)showMoreMenuForPost:(NSDictionary *)post {
  [[self postActionCoordinator] presentMoreMenuForPost:post sourceView:nil];
}

- (void)presentMediaItems:(NSArray<NSDictionary *> *)mediaItems initialIndex:(NSUInteger)index post:(NSDictionary *)post {
  if (mediaItems.count == 0) return;
  NFBMediaViewerViewController *viewer = [[NFBMediaViewerViewController alloc] initWithMediaItems:mediaItems initialIndex:index post:post];
  viewer.delegate = self;
  [self presentViewController:viewer animated:YES completion:nil];
}

- (void)pushProfileForPost:(NSDictionary *)post {
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  NSString *actor = [author[@"did"] isKindOfClass:NSString.class] ? author[@"did"] : @"";
  if (actor.length == 0) actor = [author[@"handle"] isKindOfClass:NSString.class] ? author[@"handle"] : @"";
  if (actor.length == 0) return;
  NFBTimelineViewController *profile = [[NFBTimelineViewController alloc] initWithKind:NFBTimelineKindProfile actor:actor];
  [self.navigationController pushViewController:profile animated:YES];
}

#pragma mark - NFBTweetDetailReaderCellDelegate

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapLinkURL:(NSURL *)url {
  (void)cell;
  NFBOpenTweetTextURL(url, self);
}

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapAuthorForPost:(NSDictionary *)post {
  (void)cell;
  [self pushProfileForPost:post];
}

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapMediaAtIndex:(NSUInteger)index post:(NSDictionary *)post {
  (void)cell;
  [self presentMediaItems:[NFBAtprotoClient mediaItemsForPost:post] initialIndex:index post:post];
}

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapExternalCardForPost:(NSDictionary *)post {
  (void)cell;
  [self openExternalCardForPost:post];
}

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapExternalCardWebsiteForPost:(NSDictionary *)post {
  (void)cell;
  [self openExternalCardWebsiteForPost:post];
}

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapQuotedPostForPost:(NSDictionary *)post {
  (void)cell;
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post ?: @{}];
  if (quotedPost.count > 0) [self pushDetailForPost:quotedPost];
}

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapQuotedMediaAtIndex:(NSUInteger)index post:(NSDictionary *)post {
  (void)cell;
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post ?: @{}];
  [self presentMediaItems:[NFBAtprotoClient mediaItemsForPost:quotedPost ?: @{}] initialIndex:index post:quotedPost ?: @{}];
}

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapQuotedExternalCardForPost:(NSDictionary *)post {
  (void)cell;
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post ?: @{}];
  [self openExternalCardForPost:quotedPost ?: @{}];
}

- (void)tweetDetailReaderCell:(NFBTweetDetailReaderCell *)cell didTapQuotedExternalCardWebsiteForPost:(NSDictionary *)post {
  (void)cell;
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post ?: @{}];
  [self openExternalCardWebsiteForPost:quotedPost ?: @{}];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  if (self.readerModeActive) return 1;
  return (NSInteger)self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  if (self.readerModeActive) {
    NFBTweetDetailReaderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reader" forIndexPath:indexPath];
    cell.delegate = self;
    [cell configureWithPosts:[self readerModePosts]];
    return cell;
  }
  NSInteger itemIndex = [self itemIndexForVisibleRow:indexPath.row];
  if (itemIndex == NSNotFound || itemIndex < 0 || itemIndex >= (NSInteger)self.items.count) return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
  NSDictionary *rowItem = self.items[itemIndex];
  if ([rowItem[@"_nfbThreadRole"] isEqual:@"gap"]) {
    NFBThreadGapCell *cell = [tableView dequeueReusableCellWithIdentifier:@"gap" forIndexPath:indexPath];
    NSString *uri = rowItem[@"_nfbExpandURI"];
    BOOL loading = [self.loadingBranches containsObject:uri];
    cell.backgroundColor = NFBColorBackground();
    cell.actionLabel.textColor = NFBColorAccent();
    cell.actionLabel.text = [self.failedBranches containsObject:uri] ? @"Couldn't load replies. Tap to retry." : ([rowItem[@"_nfbEarlierReplies"] boolValue] ? @"Show earlier replies" : ([rowItem[@"_nfbAdditionalReplies"] boolValue] ? @"Show additional replies" : @"Show more replies"));
    cell.accessibilityLabel = cell.actionLabel.text;
    cell.accessibilityValue = loading ? @"Loading" : nil;
    cell.accessibilityTraits = loading ? UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled : UIAccessibilityTraitButton;
    cell.connected = [rowItem[@"_nfbConnectorAbove"] boolValue];
    // The reference keeps the action label and replaces the rail dots with
    // the medium system spinner, retaining its native default color.
    cell.spinner.color = nil;
    if (loading) [cell.spinner startAnimating]; else [cell.spinner stopAnimating];
    [cell setNeedsDisplay];
    return cell;
  }
  if (itemIndex == self.focalIndex) {
    NFBTweetDetailFocalCell *cell = [tableView dequeueReusableCellWithIdentifier:@"focal" forIndexPath:indexPath];
    cell.delegate = self;
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)itemIndex]];
    [cell configureWithPost:post];
    if (@available(iOS 13.0, *)) {
      [cell setMoreMenu:[[self postActionCoordinator] contextMenuForPost:post]];
    }
    [cell setThreadConnectorAbove:[self threadIndexHasConnectorAbove:itemIndex] below:[self threadIndexHasConnectorBelow:itemIndex]];
    return cell;
  }
  NFBPostCell *cell = [tableView dequeueReusableCellWithIdentifier:@"post" forIndexPath:indexPath];
  cell.delegate = self;
  NSDictionary *item = self.items[(NSUInteger)itemIndex];
  [cell configureWithFeedItem:item];
  if (@available(iOS 13.0, *)) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    [cell setMoreMenu:[[self postActionCoordinator] contextMenuForPost:post]];
  }
  [cell setThreadConnectorAbove:[self threadIndexHasConnectorAbove:itemIndex]
                          below:[self threadIndexHasConnectorBelow:itemIndex]
               compactSeparator:[self threadIndexUsesCompactSeparator:itemIndex]];
  return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)tableView;
  if (self.readerModeActive) return;
  NSInteger itemIndex = [self itemIndexForVisibleRow:indexPath.row];
  if (itemIndex == NSNotFound || itemIndex < 0 || itemIndex >= (NSInteger)self.items.count || itemIndex == self.focalIndex) return;
  if ([self.items[itemIndex][@"_nfbThreadRole"] isEqual:@"gap"]) { [self expandRepliesForItem:self.items[itemIndex]]; return; }
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)itemIndex]];
  NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
  NSString *currentURI = [self.initialPost[@"uri"] isKindOfClass:NSString.class] ? self.initialPost[@"uri"] : @"";
  if (uri.length == 0 || [uri isEqualToString:currentURI]) return;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
  [self.navigationController pushViewController:detail animated:YES];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
  (void)tableView;
  (void)point;
  if (@available(iOS 13.0, *)) {
    if (!self.readerModeActive && indexPath.row < (NSInteger)self.items.count && [self.items[indexPath.row][@"_nfbThreadRole"] isEqual:@"gap"]) return nil;
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

- (void)postCellDidTapAuthor:(NFBPostCell *)cell {
  [self pushProfileForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}]];
}

- (void)postCell:(NFBPostCell *)cell didTapLinkURL:(NSURL *)url {
  (void)cell;
  NFBOpenTweetTextURL(url, self);
}

- (void)postCell:(NFBPostCell *)cell didTapMediaAtIndex:(NSUInteger)index {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  [self presentMediaItems:[NFBAtprotoClient mediaItemsForPost:post] initialIndex:index post:post];
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

- (void)postCell:(NFBPostCell *)cell didTapQuotedMediaAtIndex:(NSUInteger)index {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post];
  [self presentMediaItems:[NFBAtprotoClient mediaItemsForPost:quotedPost ?: @{}] initialIndex:index post:quotedPost ?: @{}];
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

#pragma mark - NFBTweetDetailFocalCellDelegate

- (void)tweetDetailFocalCellDidTapReply:(NFBTweetDetailFocalCell *)cell {
  [[self postActionCoordinator] performReplyForPost:cell.post ?: @{} sourceView:nil];
}

- (void)tweetDetailFocalCellDidTapRepost:(NFBTweetDetailFocalCell *)cell {
  NSDictionary *post = cell.post ?: @{};
  [[self postActionCoordinator] performRepostForPost:post sourceView:nil];
}

- (void)tweetDetailFocalCellDidTapLike:(NFBTweetDetailFocalCell *)cell {
  NSDictionary *post = cell.post ?: @{};
  [[self postActionCoordinator] performLikeForPost:post sourceView:nil];
}

- (void)tweetDetailFocalCellDidTapBookmark:(NFBTweetDetailFocalCell *)cell {
  NSDictionary *post = cell.post ?: @{};
  [[self postActionCoordinator] performBookmarkForPost:post sourceView:nil];
}

- (void)tweetDetailFocalCellDidTapShare:(NFBTweetDetailFocalCell *)cell {
  [[self postActionCoordinator] performShareForPost:cell.post ?: @{} sourceView:nil];
}

- (void)tweetDetailFocalCellDidTapMore:(NFBTweetDetailFocalCell *)cell {
  [[self postActionCoordinator] presentMoreMenuForPost:cell.post ?: @{} sourceView:nil];
}

- (void)tweetDetailFocalCellDidTapFollow:(NFBTweetDetailFocalCell *)cell {
  NSDictionary *author = [cell.post[@"author"] isKindOfClass:NSDictionary.class] ? cell.post[@"author"] : @{};
  [[self postActionCoordinator] performFollowForProfile:author sourceView:cell.followButton completion:nil];
}

- (void)tweetDetailFocalCellDidLongPress:(NFBTweetDetailFocalCell *)cell {
  [[self postActionCoordinator] presentMoreMenuForPost:cell.post ?: @{} sourceView:nil];
}

- (void)tweetDetailFocalCellDidTapAuthor:(NFBTweetDetailFocalCell *)cell {
  [self pushProfileForPost:cell.post ?: @{}];
}

- (void)tweetDetailFocalCell:(NFBTweetDetailFocalCell *)cell didTapLinkURL:(NSURL *)url {
  (void)cell;
  NFBOpenTweetTextURL(url, self);
}

- (void)tweetDetailFocalCell:(NFBTweetDetailFocalCell *)cell didTapMetricType:(NSString *)metricType {
  if (metricType.length == 0) return;
  NFBActorListViewController *list = [[NFBActorListViewController alloc] initWithPost:cell.post ?: @{} selectedType:metricType];
  [self.navigationController pushViewController:list animated:YES];
}

- (void)tweetDetailFocalCell:(NFBTweetDetailFocalCell *)cell didTapMediaAtIndex:(NSUInteger)index {
  [self presentMediaItems:[NFBAtprotoClient mediaItemsForPost:cell.post ?: @{}] initialIndex:index post:cell.post ?: @{}];
}

- (void)tweetDetailFocalCellDidTapExternalCard:(NFBTweetDetailFocalCell *)cell {
  [self openExternalCardForPost:cell.post ?: @{}];
}

- (void)tweetDetailFocalCellDidTapExternalCardWebsite:(NFBTweetDetailFocalCell *)cell {
  [self openExternalCardWebsiteForPost:cell.post ?: @{}];
}

- (void)tweetDetailFocalCellDidTapArticleNotifications:(NFBTweetDetailFocalCell *)cell {
  NSDictionary *author = [cell.post[@"author"] isKindOfClass:NSDictionary.class] ? cell.post[@"author"] : @{};
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] followProfileIfNeeded:author completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if (error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Follow & Notify"
                                                                       message:error.localizedDescription ?: @"Could not follow this account."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [strongSelf presentViewController:alert animated:YES completion:nil];
        return;
      }
      NSDictionary *notificationAuthor = value.count > 0 && ![value[@"did"] isKindOfClass:NSString.class] ? [NFBAtprotoClient profile:author applyingFollowToggleWithResponse:value] : author;
      [NFBNotificationCoordinator setArticleNotificationsOnlyForProfile:notificationAuthor
                                                      fromViewController:strongSelf
                                                              completion:^{
        [strongSelf.tableView reloadData];
      }];
    });
  }];
}

- (void)tweetDetailFocalCellDidTapQuotedPost:(NFBTweetDetailFocalCell *)cell {
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:cell.post ?: @{}];
  if (!quotedPost) return;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:quotedPost];
  [self.navigationController pushViewController:detail animated:YES];
}

- (void)tweetDetailFocalCell:(NFBTweetDetailFocalCell *)cell didTapQuotedMediaAtIndex:(NSUInteger)index {
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:cell.post ?: @{}];
  [self presentMediaItems:[NFBAtprotoClient mediaItemsForPost:quotedPost ?: @{}] initialIndex:index post:quotedPost ?: @{}];
}

- (void)tweetDetailFocalCellDidTapQuotedExternalCard:(NFBTweetDetailFocalCell *)cell {
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:cell.post ?: @{}];
  [self openExternalCardForPost:quotedPost ?: @{}];
}

- (void)tweetDetailFocalCellDidTapQuotedExternalCardWebsite:(NFBTweetDetailFocalCell *)cell {
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:cell.post ?: @{}];
  [self openExternalCardWebsiteForPost:quotedPost ?: @{}];
}

- (void)mediaViewerViewController:(NFBMediaViewerViewController *)viewer
                    didUpdatePost:(NSDictionary *)updatedPost
                     originalPost:(NSDictionary *)originalPost {
  (void)viewer;
  [self applyUpdatedPost:updatedPost originalPost:originalPost];
}

@end
