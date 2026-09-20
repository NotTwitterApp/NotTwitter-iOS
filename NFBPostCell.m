#import "NFBPostCell.h"

#import "NFBAtprotoClient.h"
#import "NFBExternalCardView.h"
#import "NFBMediaPreviewView.h"
#import "NFBModeration.h"
#import "NFBNeoFreeBirdUI.h"
#import "NFBPostActionCoordinator.h"
#import "NFBQuotedPostView.h"
#import "NFBTheme.h"

@interface NFBPostCell () <NFBMediaPreviewViewDelegate, NFBExternalCardViewDelegate, NFBQuotedPostViewDelegate>

@property (nonatomic, strong) UILabel *reasonLabel;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIView *threadConnectorTopView;
@property (nonatomic, strong) UIView *threadConnectorBottomView;
@property (nonatomic, strong) UIView *headerRow;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadgeView;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *timeSeparatorLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *replyContextLabel;
@property (nonatomic, strong) NFBInteractiveTextLabel *bodyLabel;
@property (nonatomic, strong) UIView *tombstoneView;
@property (nonatomic, strong) NFBInteractiveTextLabel *tombstoneTitleLabel;
@property (nonatomic, strong) NFBInteractiveTextLabel *tombstoneSubtitleLabel;
@property (nonatomic, strong) NFBMediaPreviewView *mediaView;
@property (nonatomic, strong) NFBExternalCardView *externalCardView;
@property (nonatomic, strong) NFBQuotedPostView *quotedPostView;
@property (nonatomic, strong) UIStackView *actionsRow;
@property (nonatomic, strong) UIImageView *replyIconView;
@property (nonatomic, strong) UIImageView *repostIconView;
@property (nonatomic, strong) UIImageView *likeIconView;
@property (nonatomic, strong) UIImageView *bookmarkIconView;
@property (nonatomic, strong) UIImageView *shareIconView;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UILabel *replyCountLabel;
@property (nonatomic, strong) UILabel *repostCountLabel;
@property (nonatomic, strong) UILabel *likeCountLabel;
@property (nonatomic, strong) UILabel *viewCountLabel;
@property (nonatomic, strong) UIView *viewActionItem;
@property (nonatomic, strong) UIView *bottomBorder;
@property (nonatomic, strong) NSLayoutConstraint *replyActionWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *repostActionWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *likeActionWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *viewActionWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bookmarkActionWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *shareActionWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *mediaHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *externalCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bottomBorderLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentStackDefaultLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentStackTombstoneLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tombstoneSubtitleBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tombstoneTitleOnlyBottomConstraint;
@property (nonatomic, copy) NSString *avatarURLString;
@property (nonatomic, copy) NSArray<NSDictionary *> *mediaItems;
@property (nonatomic, strong, nullable) NSDictionary *externalCard;
@property (nonatomic, strong, nullable) NSDictionary *quotedPost;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *feedItem;
@property (nonatomic, assign) BOOL tombstoned;

@end

@implementation NFBPostCell

#define NFBPostCellHorizontalInset NFBIPAMetricValue(NFBIPAMetricTimelineHorizontalInset)
#define NFBPostCellAvatarSize NFBIPAMetricValue(NFBIPAMetricTimelineAvatarSize)
#define NFBPostCellAvatarTextGap NFBIPAMetricValue(NFBIPAMetricTimelineAvatarTextGap)
#define NFBPostCellTopInset NFBIPAMetricValue(NFBIPAMetricTimelineTopInset)
#define NFBPostCellContentTopInset NFBIPAMetricValue(NFBIPAMetricTimelineContentTopInset)
#define NFBPostCellBottomInset NFBIPAMetricValue(NFBIPAMetricTimelineBottomInset)
#define NFBPostCellReasonAvatarTopInset NFBIPAMetricValue(NFBIPAMetricTimelineReasonAvatarTopInset)
#define NFBPostCellActionHeight NFBIPAMetricValue(NFBIPAMetricTimelineActionHeight)
#define NFBPostCellActionButtonMinWidth NFBIPAMetricValue(NFBIPAMetricTimelineActionButtonMinWidth)
#define NFBPostCellActionIconSize NFBIPAMetricValue(NFBIPAMetricTimelineActionIconSize)
#define NFBPostCellActionLabelGap NFBIPAMetricValue(NFBIPAMetricTimelineActionLabelGap)
#define NFBPostCellThreadRailWidth NFBIPAMetricValue(NFBIPAMetricThreadRailWidth)
#define NFBPostCellThreadRailAvatarGap NFBIPAMetricValue(NFBIPAMetricThreadRailAvatarGap)

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
  [self applyTheme];
  self.avatarView.image = [self.class placeholderAvatarImage];
  [self.mediaView configureWithMediaItems:@[]];
  self.mediaView.hidden = YES;
  [self.externalCardView configureWithCard:nil];
  self.externalCardView.hidden = YES;
  self.externalCardHeightConstraint.constant = 0.0;
  [self.quotedPostView configureWithPost:nil];
	  self.quotedPostView.hidden = YES;
	  self.reasonLabel.hidden = YES;
	  self.reasonLabel.attributedText = nil;
	  self.reasonLabel.text = @"";
	  self.headerRow.hidden = NO;
  self.replyContextLabel.hidden = YES;
  self.replyContextLabel.attributedText = nil;
  self.bodyLabel.hidden = NO;
  self.tombstoneView.hidden = YES;
  self.contentStackTombstoneLeadingConstraint.active = NO;
  self.contentStackDefaultLeadingConstraint.active = YES;
  self.avatarTopConstraint.constant = NFBPostCellTopInset;
  self.avatarView.hidden = NO;
  self.actionsRow.hidden = NO;
  [self setThreadConnectorAbove:NO below:NO compactSeparator:NO];
  if (@available(iOS 13.0, *)) [self setMoreMenu:nil];
  self.avatarURLString = nil;
  self.mediaItems = @[];
  self.externalCard = nil;
  self.quotedPost = nil;
  self.tombstoned = NO;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  if (!self.externalCardView.hidden) [self updateExternalCardHeight];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

  self.reasonLabel = [[UILabel alloc] init];
  self.reasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.reasonLabel.font = NFBFont(13.0, NFBFontWeightBold);
  self.reasonLabel.textColor = NFBColorSecondaryText();

  self.avatarView = [[UIImageView alloc] initWithImage:[self.class placeholderAvatarImage]];
  self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarView.clipsToBounds = YES;
  self.avatarView.layer.cornerRadius = NFBPostCellAvatarSize * 0.5;
  self.avatarView.userInteractionEnabled = YES;
  UITapGestureRecognizer *avatarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)];
  [self.avatarView addGestureRecognizer:avatarTap];

  self.threadConnectorTopView = [[UIView alloc] init];
  self.threadConnectorTopView.translatesAutoresizingMaskIntoConstraints = NO;
  self.threadConnectorTopView.hidden = YES;
  self.threadConnectorTopView.layer.cornerRadius = NFBPostCellThreadRailWidth * 0.5;

  self.threadConnectorBottomView = [[UIView alloc] init];
  self.threadConnectorBottomView.translatesAutoresizingMaskIntoConstraints = NO;
  self.threadConnectorBottomView.hidden = YES;
  self.threadConnectorBottomView.layer.cornerRadius = NFBPostCellThreadRailWidth * 0.5;

  self.nameLabel = [[UILabel alloc] init];
  self.nameLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightBold);
  self.nameLabel.textColor = NFBColorText();
  self.nameLabel.numberOfLines = 1;
  self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.verifiedBadgeView = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
  self.verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
  self.verifiedBadgeView.contentMode = UIViewContentModeScaleAspectFit;
  [self.verifiedBadgeView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.verifiedBadgeView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.handleLabel = [[UILabel alloc] init];
  self.handleLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.handleLabel.textColor = NFBColorSecondaryText();
  self.handleLabel.numberOfLines = 1;
  self.handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.timeSeparatorLabel = [[UILabel alloc] init];
  self.timeSeparatorLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.timeSeparatorLabel.textColor = NFBColorSecondaryText();
  self.timeSeparatorLabel.text = @"·";
  self.timeSeparatorLabel.numberOfLines = 1;
  [self.timeSeparatorLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.timeSeparatorLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.timeLabel = [[UILabel alloc] init];
  self.timeLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.timeLabel.textColor = NFBColorSecondaryText();
  self.timeLabel.numberOfLines = 1;
  self.timeLabel.lineBreakMode = NSLineBreakByClipping;
  [self.timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *displayNameStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.verifiedBadgeView]];
  displayNameStack.axis = UILayoutConstraintAxisHorizontal;
  displayNameStack.spacing = 3.0;
  displayNameStack.alignment = UIStackViewAlignmentCenter;
  [displayNameStack setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [displayNameStack setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[displayNameStack, self.handleLabel, self.timeSeparatorLabel, self.timeLabel]];
  nameRow.translatesAutoresizingMaskIntoConstraints = NO;
  nameRow.userInteractionEnabled = YES;
  nameRow.axis = UILayoutConstraintAxisHorizontal;
  nameRow.spacing = 4.0;
  nameRow.alignment = UIStackViewAlignmentCenter;
  [nameRow setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  [nameRow setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [self.nameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [self.handleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  [self.handleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  UITapGestureRecognizer *authorTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)];
  [nameRow addGestureRecognizer:authorTap];

  self.moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.moreButton setImage:NFBTemplateIcon(@"nfb_more") forState:UIControlStateNormal];
  self.moreButton.tintColor = NFBColorSecondaryText();
  self.moreButton.contentEdgeInsets = UIEdgeInsetsMake(6.0, 6.0, 6.0, 6.0);
  self.moreButton.accessibilityLabel = @"More";
  [self.moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.moreButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.moreButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.headerRow = [[UIView alloc] init];
  self.headerRow.translatesAutoresizingMaskIntoConstraints = NO;
  [self.headerRow addSubview:nameRow];
  [self.headerRow addSubview:self.moreButton];

  self.replyContextLabel = [[UILabel alloc] init];
  self.replyContextLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.replyContextLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.replyContextLabel.textColor = NFBColorSecondaryText();
  self.replyContextLabel.numberOfLines = 1;
  self.replyContextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.replyContextLabel.hidden = YES;
  [self.replyContextLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
  [self.replyContextLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

  self.bodyLabel = [[NFBInteractiveTextLabel alloc] init];
  self.bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.bodyLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineBodyFontSize), NFBFontWeightRegular);
  self.bodyLabel.textColor = NFBColorText();
  self.bodyLabel.numberOfLines = 0;
  self.bodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
  [self.bodyLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
  [self.bodyLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
  __weak typeof(self) weakSelf = self;
  self.bodyLabel.linkTapHandler = ^(NSURL *url) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if ([strongSelf.delegate respondsToSelector:@selector(postCell:didTapLinkURL:)]) {
      [strongSelf.delegate postCell:strongSelf didTapLinkURL:url];
    }
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

  self.quotedPostView = [[NFBQuotedPostView alloc] init];
  self.quotedPostView.translatesAutoresizingMaskIntoConstraints = NO;
  self.quotedPostView.delegate = self;
  self.quotedPostView.hidden = YES;

  self.replyCountLabel = [self actionCountLabel];
  self.repostCountLabel = [self actionCountLabel];
  self.likeCountLabel = [self actionCountLabel];
  self.viewCountLabel = [self actionCountLabel];
  NSLayoutConstraint *viewWidthConstraint = nil;
  NSLayoutConstraint *replyWidthConstraint = nil;
  NSLayoutConstraint *repostWidthConstraint = nil;
  NSLayoutConstraint *likeWidthConstraint = nil;
  NSLayoutConstraint *bookmarkWidthConstraint = nil;
  NSLayoutConstraint *shareWidthConstraint = nil;
  self.viewActionItem = [self actionItemWithIcon:@"nfb_view_count" label:self.viewCountLabel widthConstraint:&viewWidthConstraint];
  UIView *replyItem = [self actionButtonWithIcon:@"nfb_reply" label:self.replyCountLabel selector:@selector(replyTapped) widthConstraint:&replyWidthConstraint];
  UIView *repostItem = [self actionButtonWithIcon:@"nfb_retweet" label:self.repostCountLabel selector:@selector(repostTapped) widthConstraint:&repostWidthConstraint];
  UIView *likeItem = [self actionButtonWithIcon:@"nfb_like" label:self.likeCountLabel selector:@selector(likeTapped) widthConstraint:&likeWidthConstraint];
  UIView *bookmarkItem = [self actionButtonWithIcon:@"nfb_bookmark" label:nil selector:@selector(bookmarkTapped) widthConstraint:&bookmarkWidthConstraint];
  UIView *shareItem = [self actionButtonWithIcon:@"nfb_share" label:nil selector:@selector(shareTapped) widthConstraint:&shareWidthConstraint];
  self.viewActionWidthConstraint = viewWidthConstraint;
  self.replyActionWidthConstraint = replyWidthConstraint;
  self.repostActionWidthConstraint = repostWidthConstraint;
  self.likeActionWidthConstraint = likeWidthConstraint;
  self.bookmarkActionWidthConstraint = bookmarkWidthConstraint;
  self.shareActionWidthConstraint = shareWidthConstraint;
  self.replyIconView = [self iconViewInActionButton:replyItem];
  self.repostIconView = [self iconViewInActionButton:repostItem];
  self.likeIconView = [self iconViewInActionButton:likeItem];
  self.bookmarkIconView = [self iconViewInActionButton:bookmarkItem];
  self.shareIconView = [self iconViewInActionButton:shareItem];

  self.actionsRow = [[UIStackView alloc] initWithArrangedSubviews:@[replyItem, repostItem, likeItem, self.viewActionItem, bookmarkItem, shareItem]];
  self.actionsRow.translatesAutoresizingMaskIntoConstraints = NO;
  self.actionsRow.axis = UILayoutConstraintAxisHorizontal;
  self.actionsRow.distribution = UIStackViewDistributionEqualSpacing;
  self.actionsRow.alignment = UIStackViewAlignmentCenter;
  self.actionsRow.spacing = 0.0;
  [self.actionsRow setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

  UIStackView *contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.reasonLabel, self.tombstoneView, self.headerRow, self.replyContextLabel, self.bodyLabel, self.mediaView, self.externalCardView, self.quotedPostView, self.actionsRow]];
  contentStack.translatesAutoresizingMaskIntoConstraints = NO;
  contentStack.axis = UILayoutConstraintAxisVertical;
  contentStack.spacing = 0.0;
  contentStack.alignment = UIStackViewAlignmentFill;
  [contentStack setCustomSpacing:2.0 afterView:self.reasonLabel];
  [contentStack setCustomSpacing:1.0 afterView:self.headerRow];
  [contentStack setCustomSpacing:1.0 afterView:self.replyContextLabel];
  [contentStack setCustomSpacing:7.0 afterView:self.bodyLabel];
  [contentStack setCustomSpacing:8.0 afterView:self.mediaView];
  [contentStack setCustomSpacing:8.0 afterView:self.externalCardView];
  [contentStack setCustomSpacing:8.0 afterView:self.quotedPostView];

  self.bottomBorder = [[UIView alloc] init];
  self.bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);

  [self.contentView addSubview:self.threadConnectorTopView];
  [self.contentView addSubview:self.threadConnectorBottomView];
  [self.contentView addSubview:self.avatarView];
  [self.contentView addSubview:contentStack];
  [self.contentView addSubview:self.bottomBorder];

  self.mediaHeightConstraint = [self.mediaView.heightAnchor constraintEqualToAnchor:self.mediaView.widthAnchor multiplier:9.0 / 16.0];
  self.mediaHeightConstraint.priority = UILayoutPriorityDefaultHigh;
  self.externalCardHeightConstraint = [self.externalCardView.heightAnchor constraintEqualToConstant:0.0];
  self.externalCardHeightConstraint.priority = UILayoutPriorityDefaultHigh;
  self.avatarTopConstraint = [self.avatarView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:NFBPostCellTopInset];
  self.bottomBorderLeadingConstraint = [self.bottomBorder.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor];
  self.contentStackDefaultLeadingConstraint = [contentStack.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:NFBPostCellAvatarTextGap];
  self.contentStackTombstoneLeadingConstraint = [contentStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:NFBPostCellHorizontalInset];
  self.contentStackTombstoneLeadingConstraint.active = NO;
  [NSLayoutConstraint activateConstraints:@[
    [self.avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:NFBPostCellHorizontalInset],
    self.avatarTopConstraint,
    [self.avatarView.widthAnchor constraintEqualToConstant:NFBPostCellAvatarSize],
    [self.avatarView.heightAnchor constraintEqualToConstant:NFBPostCellAvatarSize],
    [self.threadConnectorTopView.centerXAnchor constraintEqualToAnchor:self.avatarView.centerXAnchor],
    [self.threadConnectorTopView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
    [self.threadConnectorTopView.bottomAnchor constraintEqualToAnchor:self.avatarView.topAnchor constant:-NFBPostCellThreadRailAvatarGap],
    [self.threadConnectorTopView.widthAnchor constraintEqualToConstant:NFBPostCellThreadRailWidth],
    [self.threadConnectorBottomView.centerXAnchor constraintEqualToAnchor:self.avatarView.centerXAnchor],
    [self.threadConnectorBottomView.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:NFBPostCellThreadRailAvatarGap],
    [self.threadConnectorBottomView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.threadConnectorBottomView.widthAnchor constraintEqualToConstant:NFBPostCellThreadRailWidth],

    self.contentStackDefaultLeadingConstraint,
    [contentStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-NFBPostCellHorizontalInset],
    [contentStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:NFBPostCellContentTopInset],
    [contentStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-NFBPostCellBottomInset],
    [self.verifiedBadgeView.widthAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricVerifiedBadgeSize)],
    [self.verifiedBadgeView.heightAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricVerifiedBadgeSize)],
    [nameRow.leadingAnchor constraintEqualToAnchor:self.headerRow.leadingAnchor],
    [nameRow.topAnchor constraintEqualToAnchor:self.headerRow.topAnchor],
    [nameRow.bottomAnchor constraintEqualToAnchor:self.headerRow.bottomAnchor],
    [nameRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.moreButton.leadingAnchor constant:-8.0],
    [self.moreButton.trailingAnchor constraintEqualToAnchor:self.headerRow.trailingAnchor],
    [self.moreButton.centerYAnchor constraintEqualToAnchor:nameRow.centerYAnchor],
    [self.moreButton.widthAnchor constraintEqualToConstant:30.0],
    [self.moreButton.heightAnchor constraintEqualToConstant:30.0],
    [self.actionsRow.heightAnchor constraintEqualToConstant:NFBPostCellActionHeight],
    self.mediaHeightConstraint,
    self.externalCardHeightConstraint,
    self.bottomBorderLeadingConstraint,
    [self.bottomBorder.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
    [self.bottomBorder.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
}

- (UILabel *)actionCountLabel {
  UILabel *label = [[UILabel alloc] init];
  label.font = NFBFont(13.0, NFBFontWeightRegular);
  label.textColor = NFBColorSecondaryText();
  label.textAlignment = NSTextAlignmentLeft;
  label.adjustsFontSizeToFitWidth = YES;
  label.minimumScaleFactor = 0.75;
  [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  return label;
}

- (UIView *)actionItemWithIcon:(NSString *)iconName label:(UILabel *)label widthConstraint:(NSLayoutConstraint **)widthConstraint {
  UIStackView *item = [[UIStackView alloc] init];
  item.axis = UILayoutConstraintAxisHorizontal;
  item.alignment = UIStackViewAlignmentCenter;
  item.spacing = NFBPostCellActionLabelGap;
  item.translatesAutoresizingMaskIntoConstraints = NO;
  item.userInteractionEnabled = NO;
  UIImageView *icon = [[UIImageView alloc] initWithImage:NFBTemplateIcon(iconName)];
  icon.tintColor = NFBColorSecondaryText();
  icon.contentMode = UIViewContentModeScaleAspectFit;
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  icon.userInteractionEnabled = NO;
  [item addArrangedSubview:icon];
  [NSLayoutConstraint activateConstraints:@[
    [icon.widthAnchor constraintEqualToConstant:NFBPostCellActionIconSize],
    [icon.heightAnchor constraintEqualToConstant:NFBPostCellActionIconSize]
  ]];
  if (label) {
    label.userInteractionEnabled = NO;
    [item addArrangedSubview:label];
  }
  NSLayoutConstraint *constraint = [item.widthAnchor constraintEqualToConstant:NFBPostCellActionButtonMinWidth];
  constraint.priority = UILayoutPriorityRequired;
  constraint.active = YES;
  if (widthConstraint) *widthConstraint = constraint;
  return item;
}

- (UIView *)actionButtonWithIcon:(NSString *)iconName label:(UILabel *)label selector:(SEL)selector widthConstraint:(NSLayoutConstraint **)widthConstraint {
  UIControl *control = [[UIControl alloc] init];
  control.translatesAutoresizingMaskIntoConstraints = NO;
  control.userInteractionEnabled = YES;
  [control addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];

  UIStackView *stack = (UIStackView *)[self actionItemWithIcon:iconName label:label widthConstraint:widthConstraint];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [control addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:control.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:control.trailingAnchor],
    [stack.centerXAnchor constraintEqualToAnchor:control.centerXAnchor],
    [control.heightAnchor constraintGreaterThanOrEqualToConstant:NFBPostCellActionHeight]
  ]];
  return control;
}

- (CGFloat)actionWidthForLabel:(UILabel *)label {
  if (!label || label.text.length == 0) return NFBPostCellActionButtonMinWidth;
  CGSize labelSize = [label sizeThatFits:CGSizeMake(CGFLOAT_MAX, NFBPostCellActionHeight)];
  return ceil(MAX(NFBPostCellActionButtonMinWidth,
                  NFBPostCellActionButtonMinWidth + NFBPostCellActionLabelGap + labelSize.width));
}

- (void)updateActionWidthConstraints {
  self.replyActionWidthConstraint.constant = [self actionWidthForLabel:self.replyCountLabel];
  self.repostActionWidthConstraint.constant = [self actionWidthForLabel:self.repostCountLabel];
  self.likeActionWidthConstraint.constant = [self actionWidthForLabel:self.likeCountLabel];
  self.viewActionWidthConstraint.constant = self.viewActionItem.hidden ? 0.0 : [self actionWidthForLabel:self.viewCountLabel];
  self.bookmarkActionWidthConstraint.constant = NFBPostCellActionButtonMinWidth;
  self.shareActionWidthConstraint.constant = NFBPostCellActionButtonMinWidth;
}

- (UIImageView *)iconViewInActionButton:(UIView *)button {
  for (UIView *subview in button.subviews) {
    if (![subview isKindOfClass:UIStackView.class]) continue;
    UIStackView *stack = (UIStackView *)subview;
    return [stack.arrangedSubviews.firstObject isKindOfClass:UIImageView.class] ? (UIImageView *)stack.arrangedSubviews.firstObject : nil;
  }
  return nil;
}

- (void)replyTapped {
  if (self.tombstoned) return;
  [NFBPostActionCoordinator animateActionView:self.replyIconView kind:NFBPostActionKindReply activating:YES];
  if ([self.delegate respondsToSelector:@selector(postCellDidTapReply:)]) [self.delegate postCellDidTapReply:self];
}

- (void)repostTapped {
  if (self.tombstoned) return;
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.feedItem ?: @{}];
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL reposted = [viewer[@"repost"] isKindOfClass:NSString.class] && [viewer[@"repost"] length] > 0;
  [NFBPostActionCoordinator animateActionView:self.repostIconView kind:NFBPostActionKindRepost activating:!reposted];
  if ([self.delegate respondsToSelector:@selector(postCellDidTapRepost:)]) [self.delegate postCellDidTapRepost:self];
}

- (void)likeTapped {
  if (self.tombstoned) return;
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.feedItem ?: @{}];
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL liked = [viewer[@"like"] isKindOfClass:NSString.class] && [viewer[@"like"] length] > 0;
  [NFBPostActionCoordinator animateActionView:self.likeIconView kind:NFBPostActionKindLike activating:!liked];
  if ([self.delegate respondsToSelector:@selector(postCellDidTapLike:)]) [self.delegate postCellDidTapLike:self];
}

- (void)bookmarkTapped {
  if (self.tombstoned) return;
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.feedItem ?: @{}];
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL bookmarked = [viewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && [viewer[@"bookmarked"] boolValue];
  [NFBPostActionCoordinator animateActionView:self.bookmarkIconView kind:NFBPostActionKindBookmark activating:!bookmarked];
  if ([self.delegate respondsToSelector:@selector(postCellDidTapBookmark:)]) [self.delegate postCellDidTapBookmark:self];
}

- (void)shareTapped {
  if (self.tombstoned) return;
  [NFBPostActionCoordinator animateActionView:self.shareIconView kind:NFBPostActionKindShare activating:YES];
  if ([self.delegate respondsToSelector:@selector(postCellDidTapShare:)]) [self.delegate postCellDidTapShare:self];
}

- (void)moreTapped {
  if (self.tombstoned) return;
  if (@available(iOS 14.0, *)) {
    if (self.moreButton.menu != nil) return;
  }
  if ([self.delegate respondsToSelector:@selector(postCellDidTapMore:)]) [self.delegate postCellDidTapMore:self];
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
  if (self.tombstoned || gesture.state != UIGestureRecognizerStateBegan) return;
  if (@available(iOS 14.0, *)) {
    if (self.moreButton.menu != nil) return;
  }
  if ([self.delegate respondsToSelector:@selector(postCellDidLongPress:)]) [self.delegate postCellDidLongPress:self];
}

- (void)authorTapped {
  if (self.tombstoned) return;
  if ([self.delegate respondsToSelector:@selector(postCellDidTapAuthor:)]) [self.delegate postCellDidTapAuthor:self];
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

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.reasonLabel.textColor = NFBColorSecondaryText();
  self.threadConnectorTopView.backgroundColor = NFBIPAThreadRailColor();
  self.threadConnectorBottomView.backgroundColor = NFBIPAThreadRailColor();
  self.reasonLabel.font = NFBFont(13.0, NFBFontWeightBold);
  self.nameLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightBold);
  self.handleLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.timeSeparatorLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.timeLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.replyContextLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.bodyLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineBodyFontSize), NFBFontWeightRegular);
  self.nameLabel.textColor = NFBColorText();
  self.handleLabel.textColor = NFBColorSecondaryText();
  self.timeSeparatorLabel.textColor = NFBColorSecondaryText();
  self.timeLabel.textColor = NFBColorSecondaryText();
  self.replyContextLabel.textColor = NFBColorSecondaryText();
  self.bodyLabel.textColor = NFBColorText();
  if (self.feedItem) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.feedItem];
    self.bodyLabel.attributedText = [self bodyAttributedStringForPost:post];
    self.replyContextLabel.attributedText = [self replyContextAttributedStringForFeedItem:self.feedItem post:post];
  }
  NFBApplyFramedTombstoneAppearance(self.tombstoneView, self.tombstoneTitleLabel, self.tombstoneSubtitleLabel, 15.0, 15.0);
  [self.mediaView applyTheme];
  [self.externalCardView applyTheme];
  [self.quotedPostView applyTheme];
  NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);
  self.moreButton.tintColor = NFBColorSecondaryText();
	  [self applySecondaryTintInView:self.actionsRow];
	}

- (UIImage *)statusIconImageNamed:(NSString *)iconName size:(CGSize)size color:(UIColor *)color {
  UIImage *image = NFBTemplateIcon(iconName);
  if (!image) return nil;
  UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
  CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
  [image drawInRect:rect];
  [color setFill];
  UIRectFillUsingBlendMode(rect, kCGBlendModeSourceIn);
  UIImage *tinted = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return tinted;
}

- (NSAttributedString *)pinnedReasonAttributedString {
  UIColor *color = NFBColorSecondaryText();
  UIFont *font = NFBFont(13.0, NFBFontWeightBold);
  NSMutableAttributedString *string = [[NSMutableAttributedString alloc] init];
  UIImage *icon = [self statusIconImageNamed:@"nfb_pin" size:CGSizeMake(13.0, 13.0) color:color];
  if (icon) {
    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = icon;
    attachment.bounds = CGRectMake(0.0, -2.2, 13.0, 13.0);
    [string appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:@{NSFontAttributeName: font}]];
  }
  [string appendAttributedString:[[NSAttributedString alloc] initWithString:@"Pinned Tweet" attributes:@{
    NSForegroundColorAttributeName: color,
    NSFontAttributeName: font
  }]];
  return string;
}
	
	- (void)setThreadConnectorAbove:(BOOL)above below:(BOOL)below {
  [self setThreadConnectorAbove:above below:below compactSeparator:NO];
}

- (void)setThreadConnectorAbove:(BOOL)above below:(BOOL)below compactSeparator:(BOOL)compactSeparator {
  self.threadConnectorTopView.hidden = !above;
  self.threadConnectorBottomView.hidden = !below;
  self.bottomBorder.hidden = compactSeparator && below;
  self.bottomBorderLeadingConstraint.constant = compactSeparator ? NFBPostCellHorizontalInset + NFBPostCellAvatarSize + NFBPostCellAvatarTextGap : 0.0;
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

- (NSAttributedString *)replyContextAttributedStringForFeedItem:(NSDictionary *)item post:(NSDictionary *)post {
  BOOL showReplyContext = [item[@"_nfbShowReplyContext"] respondsToSelector:@selector(boolValue)] && [item[@"_nfbShowReplyContext"] boolValue];
  if (!showReplyContext) return nil;
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  if (![record[@"reply"] isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *parentPost = [NFBAtprotoClient replyParentPostFromFeedItem:item];
  NSDictionary *parentAuthor = [parentPost[@"author"] isKindOfClass:NSDictionary.class] ? parentPost[@"author"] : nil;
  NSString *handle = parentAuthor.count > 0 ? [NFBAtprotoClient handleForProfile:parentAuthor] : @"";
  if (handle.length == 0) return nil;
  NSString *target = [@"@" stringByAppendingString:handle];
  NSString *prefix = @"Replying to ";
  NSString *text = [prefix stringByAppendingString:target];
  NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
    NSForegroundColorAttributeName: NFBColorSecondaryText(),
    NSFontAttributeName: self.replyContextLabel.font ?: NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular)
  }];
  [attributed addAttribute:NSForegroundColorAttributeName value:NFBColorAccent() range:NSMakeRange(prefix.length, target.length)];
  return attributed;
}

- (NSAttributedString *)bodyAttributedStringForPost:(NSDictionary *)post {
  return NFBTweetBodyAttributedStringForPost(post, self.bodyLabel.font);
}

- (void)configureWithFeedItem:(NSDictionary *)item {
  self.feedItem = item;
  [self applyTheme];
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
	  NSDictionary *author = [post[@"author"] isKindOfClass:[NSDictionary class]] ? post[@"author"] : @{};
	  NSString *reason = [NFBAtprotoClient reasonTextForFeedItem:item];
	  NSString *rawReason = [item[@"reason"] isKindOfClass:NSString.class] ? item[@"reason"] : @"";
	  NSDictionary *tombstone = NFBModerationTombstoneForFeedItem(item, post);
	
	  self.reasonLabel.attributedText = [rawReason isEqualToString:@"pinned"] ? [self pinnedReasonAttributedString] : nil;
	  self.reasonLabel.text = [rawReason isEqualToString:@"pinned"] ? nil : reason;
	  self.reasonLabel.hidden = reason.length == 0;
  self.avatarTopConstraint.constant = reason.length > 0 ? NFBPostCellReasonAvatarTopInset : NFBPostCellTopInset;
  self.tombstoned = tombstone.count > 0;
  if (self.tombstoned) {
    [self configureTombstone:tombstone];
    return;
  }
  self.tombstoneView.hidden = YES;
  self.contentStackTombstoneLeadingConstraint.active = NO;
  self.contentStackDefaultLeadingConstraint.active = YES;
  self.headerRow.hidden = NO;
  self.avatarView.hidden = NO;
  self.actionsRow.hidden = NO;
  self.nameLabel.text = [NFBAtprotoClient displayNameForProfile:author];
  self.verifiedBadgeView.hidden = ![NFBAtprotoClient isProfileVerified:author];
  self.handleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:author]];
  self.timeLabel.text = [NFBAtprotoClient relativeTimeForPost:post];
  NSString *bodyText = [NFBAtprotoClient textForPost:post];
  self.bodyLabel.hidden = bodyText.length == 0;
  self.bodyLabel.attributedText = [self bodyAttributedStringForPost:post];
  self.replyContextLabel.attributedText = [self replyContextAttributedStringForFeedItem:item post:post];
  self.replyContextLabel.hidden = self.replyContextLabel.attributedText.length == 0;

  NSNumber *replyCount = [post[@"replyCount"] respondsToSelector:@selector(stringValue)] ? post[@"replyCount"] : @0;
  NSNumber *repostCount = [post[@"repostCount"] respondsToSelector:@selector(stringValue)] ? post[@"repostCount"] : @0;
  NSNumber *likeCount = [post[@"likeCount"] respondsToSelector:@selector(stringValue)] ? post[@"likeCount"] : @0;
  NSNumber *viewCount = [post[@"viewCount"] respondsToSelector:@selector(stringValue)] ? post[@"viewCount"] : @0;
  self.replyCountLabel.text = [self visibleCountText:replyCount];
  self.repostCountLabel.text = [self visibleCountText:repostCount];
  self.likeCountLabel.text = [self visibleCountText:likeCount];
  NSDictionary *viewer = [post[@"viewer"] isKindOfClass:NSDictionary.class] ? post[@"viewer"] : @{};
  BOOL liked = [viewer[@"like"] isKindOfClass:NSString.class] && [viewer[@"like"] length] > 0;
  BOOL reposted = [viewer[@"repost"] isKindOfClass:NSString.class] && [viewer[@"repost"] length] > 0;
  BOOL bookmarked = [viewer[@"bookmarked"] respondsToSelector:@selector(boolValue)] && [viewer[@"bookmarked"] boolValue];
  self.likeIconView.image = NFBTemplateIcon(liked ? @"nfb_like_filled" : @"nfb_like");
  self.likeIconView.tintColor = liked ? [UIColor colorWithRed:0.976 green:0.094 blue:0.502 alpha:1.0] : NFBColorSecondaryText();
  self.likeCountLabel.textColor = liked ? self.likeIconView.tintColor : NFBColorSecondaryText();
  self.repostIconView.tintColor = reposted ? [UIColor colorWithRed:0.0 green:0.729 blue:0.486 alpha:1.0] : NFBColorSecondaryText();
  self.repostCountLabel.textColor = reposted ? self.repostIconView.tintColor : NFBColorSecondaryText();
  self.bookmarkIconView.image = NFBTemplateIcon(bookmarked ? @"nfb_bookmark_filled" : @"nfb_bookmark");
  self.bookmarkIconView.tintColor = bookmarked ? NFBColorAccent() : NFBColorSecondaryText();
  BOOL hideViewCount = NFBNeoFreeBirdHideViewCount();
  self.viewActionItem.hidden = hideViewCount;
  self.viewCountLabel.text = hideViewCount ? @"" : [self visibleCountText:viewCount];
  [self updateActionWidthConstraints];

  [self loadImageURL:[NFBAtprotoClient avatarURLForProfile:author] intoImageView:self.avatarView avatar:YES];

  NSArray<NSDictionary *> *mediaItems = NFBModerationMediaItemsByApplyingWarnings([NFBAtprotoClient mediaItemsForPost:post], post);
  self.mediaItems = mediaItems;
  if (mediaItems.count > 0) {
    self.mediaView.hidden = NO;
    [self.mediaView configureWithMediaItems:mediaItems];
  } else {
    [self.mediaView configureWithMediaItems:@[]];
    self.mediaView.hidden = YES;
  }

  NSDictionary *externalCard = [NFBAtprotoClient externalCardForPost:post];
  self.externalCard = externalCard;
  if (externalCard.count > 0) {
    self.externalCardView.hidden = NO;
    [self.externalCardView configureWithCard:externalCard compact:NO fullArticleReader:NO];
    [self updateExternalCardHeight];
  } else {
    [self.externalCardView configureWithCard:nil];
    self.externalCardView.hidden = YES;
    self.externalCardHeightConstraint.constant = 0.0;
  }

  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:post];
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
  self.reasonLabel.hidden = YES;
  self.reasonLabel.text = @"";
  self.contentStackDefaultLeadingConstraint.active = NO;
  self.contentStackTombstoneLeadingConstraint.active = YES;
  self.avatarView.hidden = YES;
  self.headerRow.hidden = YES;
  self.replyContextLabel.hidden = YES;
  self.replyContextLabel.attributedText = nil;
  self.bodyLabel.hidden = YES;
  self.mediaView.hidden = YES;
  self.externalCardView.hidden = YES;
  self.quotedPostView.hidden = YES;
  self.actionsRow.hidden = YES;
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

- (CGFloat)externalCardAvailableWidth {
  CGFloat width = CGRectGetWidth(self.externalCardView.bounds);
  if (width <= 0.0) width = CGRectGetWidth(self.contentView.bounds) - 92.0;
  if (width <= 0.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds) - 92.0;
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

- (NSString *)visibleCountText:(NSNumber *)count {
  return count.integerValue > 0 ? NFBShortCountString(count.integerValue) : @"";
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
  if ([self.delegate respondsToSelector:@selector(postCell:didTapMediaAtIndex:)]) {
    [self.delegate postCell:self didTapMediaAtIndex:index];
  }
}

- (void)externalCardViewDidTapCard:(NFBExternalCardView *)view {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(postCellDidTapExternalCard:)]) {
    [self.delegate postCellDidTapExternalCard:self];
  }
}

- (void)externalCardViewDidTapReadOnWebsite:(NFBExternalCardView *)view {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(postCellDidTapExternalCardWebsite:)]) {
    [self.delegate postCellDidTapExternalCardWebsite:self];
  }
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
  if ([self.delegate respondsToSelector:@selector(postCellDidTapQuotedPost:)]) {
    [self.delegate postCellDidTapQuotedPost:self];
  }
}

- (void)quotedPostView:(NFBQuotedPostView *)view didTapLinkURL:(NSURL *)url {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(postCell:didTapLinkURL:)]) {
    [self.delegate postCell:self didTapLinkURL:url];
  }
}

- (void)quotedPostView:(NFBQuotedPostView *)view didTapMediaAtIndex:(NSUInteger)index {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(postCell:didTapQuotedMediaAtIndex:)]) {
    [self.delegate postCell:self didTapQuotedMediaAtIndex:index];
  }
}

- (void)quotedPostViewDidTapExternalCard:(NFBQuotedPostView *)view {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(postCellDidTapQuotedExternalCard:)]) {
    [self.delegate postCellDidTapQuotedExternalCard:self];
  }
}

- (void)quotedPostViewDidTapExternalCardWebsite:(NFBQuotedPostView *)view {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(postCellDidTapQuotedExternalCardWebsite:)]) {
    [self.delegate postCellDidTapQuotedExternalCardWebsite:self];
  }
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
