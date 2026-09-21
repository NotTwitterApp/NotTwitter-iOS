#import "NFBQuotedPostView.h"

#import "NFBAtprotoClient.h"
#import "NFBExternalCardView.h"
#import "NFBMediaPreviewView.h"
#import "NFBModeration.h"
#import "NFBTheme.h"

@interface NFBQuotedPostView () <NFBMediaPreviewViewDelegate, NFBExternalCardViewDelegate>

@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIStackView *headerStack;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIStackView *textStack;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadgeView;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) NFBInteractiveTextLabel *bodyLabel;
@property (nonatomic, strong) UIView *tombstoneView;
@property (nonatomic, strong) NFBInteractiveTextLabel *tombstoneTitleLabel;
@property (nonatomic, strong) NFBInteractiveTextLabel *tombstoneSubtitleLabel;
@property (nonatomic, strong) NFBMediaPreviewView *mediaView;
@property (nonatomic, strong) NFBExternalCardView *externalCardView;
@property (nonatomic, strong) NSLayoutConstraint *mediaHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *externalCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tombstoneSubtitleBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tombstoneTitleOnlyBottomConstraint;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *post;
@property (nonatomic, copy) NSString *avatarURLString;
@property (nonatomic, copy) NSArray<NSDictionary *> *mediaItems;
@property (nonatomic, strong, nullable) NSDictionary *externalCard;
@property (nonatomic, assign) BOOL tombstoned;

@end

@implementation NFBQuotedPostView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self buildSubviews];
  }
  return self;
}

- (void)buildSubviews {
  NFBIPAApplyEmbeddedCardFrameAppearance(self);
  [self addTarget:self action:@selector(cardTapped) forControlEvents:UIControlEventTouchUpInside];

  self.avatarView = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage()];
  self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarView.clipsToBounds = YES;
  self.avatarView.layer.cornerRadius = NFBIPAMetricValue(NFBIPAMetricEmbeddedCardAvatarSize) * 0.5;
  self.avatarView.userInteractionEnabled = NO;

  self.nameLabel = [[UILabel alloc] init];
  self.nameLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricEmbeddedCardNameFontSize), NFBFontWeightBold);
  self.nameLabel.textColor = NFBColorText();
  self.nameLabel.numberOfLines = 1;
  self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.nameLabel.userInteractionEnabled = NO;
  [self.nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [self.nameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

  self.verifiedBadgeView = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
  self.verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
  self.verifiedBadgeView.contentMode = UIViewContentModeScaleAspectFit;
  self.verifiedBadgeView.userInteractionEnabled = NO;
  [self.verifiedBadgeView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.verifiedBadgeView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.handleLabel = [[UILabel alloc] init];
  self.handleLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricEmbeddedCardNameFontSize), NFBFontWeightRegular);
  self.handleLabel.textColor = NFBColorSecondaryText();
  self.handleLabel.numberOfLines = 1;
  self.handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.handleLabel.userInteractionEnabled = NO;
  [self.handleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  [self.handleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  self.timeLabel = [[UILabel alloc] init];
  self.timeLabel.userInteractionEnabled = NO;
  [self.timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *nameStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.verifiedBadgeView, self.handleLabel, self.timeLabel]];
  nameStack.axis = UILayoutConstraintAxisHorizontal;
  nameStack.alignment = UIStackViewAlignmentCenter;
  nameStack.spacing = 3.0;
  nameStack.userInteractionEnabled = NO;
  [nameStack setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  self.headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.avatarView, nameStack]];
  self.headerStack.axis = UILayoutConstraintAxisHorizontal;
  self.headerStack.alignment = UIStackViewAlignmentCenter;
  self.headerStack.spacing = 8.0;
  self.headerStack.userInteractionEnabled = NO;

  self.bodyLabel = [[NFBInteractiveTextLabel alloc] init];
  self.bodyLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricEmbeddedCardBodyFontSize), NFBFontWeightRegular);
  self.bodyLabel.textColor = NFBColorText();
  self.bodyLabel.numberOfLines = 5;
  self.bodyLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.bodyLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
  [self.bodyLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
  __weak typeof(self) weakSelf = self;
  self.bodyLabel.linkTapHandler = ^(NSURL *url) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if ([strongSelf.delegate respondsToSelector:@selector(quotedPostView:didTapLinkURL:)]) {
      [strongSelf.delegate quotedPostView:strongSelf didTapLinkURL:url];
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
  self.tombstoneSubtitleBottomConstraint = [self.tombstoneSubtitleLabel.bottomAnchor constraintEqualToAnchor:self.tombstoneView.bottomAnchor constant:-3.0];
  self.tombstoneTitleOnlyBottomConstraint = [self.tombstoneTitleLabel.bottomAnchor constraintEqualToAnchor:self.tombstoneView.bottomAnchor constant:-3.0];
  [NSLayoutConstraint activateConstraints:@[
    [self.tombstoneTitleLabel.topAnchor constraintEqualToAnchor:self.tombstoneView.topAnchor constant:3.0],
    [self.tombstoneTitleLabel.leadingAnchor constraintEqualToAnchor:self.tombstoneView.leadingAnchor],
    [self.tombstoneTitleLabel.trailingAnchor constraintEqualToAnchor:self.tombstoneView.trailingAnchor],
    [self.tombstoneSubtitleLabel.topAnchor constraintEqualToAnchor:self.tombstoneTitleLabel.bottomAnchor constant:2.0],
    [self.tombstoneSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.tombstoneTitleLabel.leadingAnchor],
    [self.tombstoneSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.tombstoneTitleLabel.trailingAnchor],
    self.tombstoneSubtitleBottomConstraint,
    [self.tombstoneView.heightAnchor constraintGreaterThanOrEqualToConstant:28.0]
  ]];
  self.tombstoneTitleOnlyBottomConstraint.active = NO;

  self.mediaView = [[NFBMediaPreviewView alloc] init];
  self.mediaView.translatesAutoresizingMaskIntoConstraints = NO;
  self.mediaView.delegate = self;
  self.mediaView.quotedCardStyle = YES;
  self.mediaView.hidden = YES;

  self.externalCardView = [[NFBExternalCardView alloc] init];
  self.externalCardView.translatesAutoresizingMaskIntoConstraints = NO;
  self.externalCardView.delegate = self;
  self.externalCardView.quotedCardStyle = YES;
  self.externalCardView.hidden = YES;

  self.textStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.headerStack, self.tombstoneView, self.bodyLabel]];
  self.textStack.axis = UILayoutConstraintAxisVertical;
  self.textStack.alignment = UIStackViewAlignmentFill;
  self.textStack.layoutMarginsRelativeArrangement = YES;
  self.textStack.insetsLayoutMarginsFromSafeArea = NO;

  // The reference attachment cancels the quote's side and bottom insets.
  // Only the outer quote clips its media and link preview to rounded corners.
  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.textStack, self.mediaView, self.externalCardView]];
  self.contentStack = stack;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.userInteractionEnabled = YES;
  [self addSubview:stack];

  self.mediaHeightConstraint = [self.mediaView.heightAnchor constraintEqualToAnchor:self.mediaView.widthAnchor multiplier:9.0 / 16.0];
  self.mediaHeightConstraint.priority = UILayoutPriorityDefaultHigh;
  self.externalCardHeightConstraint = [self.externalCardView.heightAnchor constraintEqualToConstant:0.0];
  [NSLayoutConstraint activateConstraints:@[
	    [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
	    [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
	    [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
	    [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
	    [self.avatarView.widthAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricEmbeddedCardAvatarSize)],
	    [self.avatarView.heightAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricEmbeddedCardAvatarSize)],
	    [self.verifiedBadgeView.widthAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricEmbeddedCardNameFontSize)],
	    [self.verifiedBadgeView.heightAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricEmbeddedCardNameFontSize)],
    self.mediaHeightConstraint,
    self.externalCardHeightConstraint
  ]];
  [self applyTheme];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self updateExternalCardHeightForCurrentWidth];
}

- (CGFloat)externalCardAvailableWidth {
  CGFloat width = CGRectGetWidth(self.bounds);
  if (width <= 0.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds) - 112.0;
  return MAX(1.0, width);
}

- (void)updateExternalCardHeightForCurrentWidth {
  if (self.externalCardView.hidden || self.externalCard.count == 0) {
    self.externalCardHeightConstraint.constant = 0.0;
    return;
  }
  CGFloat height = [self.externalCardView preferredHeightForWidth:[self externalCardAvailableWidth]];
  if (fabs(self.externalCardHeightConstraint.constant - height) > 0.5) {
    self.externalCardHeightConstraint.constant = height;
  }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hitView = [super hitTest:point withEvent:event];
  if (!hitView) return nil;
  if ([hitView isDescendantOfView:self.mediaView]) return hitView;
  if ([hitView isDescendantOfView:self.externalCardView]) return hitView;
  if (hitView == self.bodyLabel) return hitView;
  return self;
}

- (void)configureWithPost:(NSDictionary *)post {
  self.post = post;
  self.hidden = post.count == 0;
  if (self.hidden) return;
  self.tombstoned = NO;
  NSDictionary *tombstone = NFBModerationTombstoneForFeedItem(post, post);
  if (tombstone.count > 0) {
    [self configureTombstone:tombstone];
    [self applyTheme];
    return;
  }
  self.headerStack.hidden = NO;
  self.tombstoneView.hidden = YES;

  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  self.nameLabel.text = [NFBAtprotoClient displayNameForProfile:author];
  self.verifiedBadgeView.hidden = ![NFBAtprotoClient isProfileVerified:author];
  self.handleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:author]];
  self.timeLabel.text = [@"· " stringByAppendingString:[NFBAtprotoClient relativeTimeForPost:post]];

  self.bodyLabel.attributedText = NFBTweetBodyAttributedStringForPost(post, self.bodyLabel.font);
  self.bodyLabel.hidden = self.bodyLabel.attributedText.length == 0;

  NSArray<NSDictionary *> *mediaItems = NFBModerationMediaItemsByApplyingWarnings([NFBAtprotoClient mediaItemsForPost:post], post);
  self.mediaItems = mediaItems;
  // 9.67's display-text options allow five lines for text quotes and the
  // complete body with photo/video attachments. It does not recurse into
  // another quoted-status view; tapping this card opens that next Tweet.
  self.bodyLabel.numberOfLines = mediaItems.count > 0 ? 0 : 5;
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
    [self.externalCardView configureWithCard:externalCard compact:YES];
    [self updateExternalCardHeightForCurrentWidth];
  } else {
    [self.externalCardView configureWithCard:nil compact:YES];
    self.externalCardView.hidden = YES;
    self.externalCardHeightConstraint.constant = 0.0;
  }
  [self loadAvatarURL:[NFBAtprotoClient avatarURLForProfile:author]];
  [self applyTheme];
}

- (void)applyTheme {
  NFBIPAApplyEmbeddedCardFrameAppearance(self);
  self.nameLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricEmbeddedCardNameFontSize), NFBFontWeightBold);
  self.handleLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricEmbeddedCardNameFontSize), NFBFontWeightRegular);
  self.timeLabel.font = self.handleLabel.font;
  self.bodyLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricEmbeddedCardBodyFontSize), NFBFontWeightRegular);
  // T1QuotedStatusParameters scales its 12/12/4/12pt padding and 8pt
  // author/body/media gaps by lineHeight / 18. Insets round up to pixels.
  CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
  CGFloat unit = self.bodyLabel.font.lineHeight / 18.0;
  CGFloat padding = ceil(12.0 * unit * scale) / scale;
  CGFloat smallGap = ceil(4.0 * unit * scale) / scale;
  CGFloat contentGap = 8.0 * unit;
  BOOL hasAttachment = !self.mediaView.hidden || !self.externalCardView.hidden;
  self.textStack.layoutMargins = UIEdgeInsetsMake(padding, padding, hasAttachment ? contentGap : padding, padding);
  self.textStack.spacing = smallGap;
  [self.textStack setCustomSpacing:contentGap afterView:self.headerStack];
  self.contentStack.spacing = 0.0;
  self.nameLabel.textColor = NFBColorText();
  self.handleLabel.textColor = NFBColorSecondaryText();
  self.timeLabel.textColor = NFBColorSecondaryText();
  self.bodyLabel.textColor = NFBColorText();
  if (self.post) self.bodyLabel.attributedText = NFBTweetBodyAttributedStringForPost(self.post, self.bodyLabel.font);
  NFBApplyTombstoneAppearance(self.tombstoneView, self.tombstoneTitleLabel, self.tombstoneSubtitleLabel, NFBIPAMetricValue(NFBIPAMetricEmbeddedCardBodyFontSize), 13.0);
  [self.mediaView applyTheme];
  [self.externalCardView applyTheme];
}

- (void)loadAvatarURL:(NSString *)urlString {
  self.avatarURLString = urlString ?: @"";
  self.avatarView.image = NFBDefaultAvatarImage();
  if (urlString.length == 0) {
    return;
  }
  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    self.avatarView.image = cached;
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
      if ([self.avatarURLString isEqualToString:urlString]) self.avatarView.image = image;
    });
  }];
  [task resume];
}

- (void)cardTapped {
  if (self.tombstoned) return;
  if ([self.delegate respondsToSelector:@selector(quotedPostViewDidTapPost:)]) {
    [self.delegate quotedPostViewDidTapPost:self];
  }
}

- (void)mediaPreviewView:(NFBMediaPreviewView *)view didSelectItemAtIndex:(NSUInteger)index {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(quotedPostView:didTapMediaAtIndex:)]) {
    [self.delegate quotedPostView:self didTapMediaAtIndex:index];
  }
}

- (void)externalCardViewDidTapCard:(NFBExternalCardView *)view {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(quotedPostViewDidTapExternalCard:)]) {
    [self.delegate quotedPostViewDidTapExternalCard:self];
  }
}

- (void)externalCardViewDidTapReadOnWebsite:(NFBExternalCardView *)view {
  (void)view;
  if ([self.delegate respondsToSelector:@selector(quotedPostViewDidTapExternalCardWebsite:)]) {
    [self.delegate quotedPostViewDidTapExternalCardWebsite:self];
  }
}

- (void)configureTombstone:(NSDictionary *)tombstone {
  self.tombstoned = YES;
  self.headerStack.hidden = YES;
  self.bodyLabel.hidden = YES;
  self.mediaView.hidden = YES;
  self.externalCardView.hidden = YES;
  self.tombstoneView.hidden = NO;
  self.tombstoneTitleLabel.attributedText = NFBModerationTombstoneAttributedString(tombstone, self.tombstoneTitleLabel.font);
  self.tombstoneSubtitleLabel.text = @"";
  self.tombstoneSubtitleLabel.attributedText = nil;
  self.tombstoneSubtitleLabel.hidden = YES;
  self.tombstoneSubtitleBottomConstraint.active = NO;
  self.tombstoneTitleOnlyBottomConstraint.active = YES;
  [self.mediaView configureWithMediaItems:@[]];
  [self.externalCardView configureWithCard:nil compact:YES];
  self.mediaItems = @[];
  self.externalCard = nil;
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
